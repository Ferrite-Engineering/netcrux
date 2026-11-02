// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:meta/meta.dart';

/// A Boolean expression as a Liberty `function`, `next_state` or
/// `clocked_on` attribute writes it, parsed.
///
/// The grammar is the one the Liberty reference gives: `!` before and `'`
/// after an operand invert it, `^` is XOR, `*`, `&` and two operands side by
/// side are AND, `+` and `|` are OR, `0` and `1` are constants, and
/// parentheses group. Inversion binds tightest, then XOR, then AND, then OR.
@immutable
sealed class LibertyExpression {
  const LibertyExpression();

  /// Parses [text]. Returns `null` for anything that is not a well-formed
  /// expression in that grammar.
  static LibertyExpression? tryParse(String text) {
    final tokens = _tokenize(text);
    if (tokens == null || tokens.isEmpty) return null;
    final parser = _ExpressionParser(tokens);
    final expression = parser.parseOr();
    if (expression == null || !parser.atEnd) return null;
    return expression;
  }

  /// The value under [assignment], a bit per variable in [variables] order.
  bool evaluate(List<String> variables, int assignment);

  /// Every variable the expression names, in first-use order.
  List<String> get variables {
    final out = <String>[];
    _collect(out);
    return out;
  }

  void _collect(List<String> out);
}

/// A pin or state variable.
final class LibertyVariable extends LibertyExpression {
  /// Creates a variable.
  const LibertyVariable(this.name);

  /// Its name as written.
  final String name;

  @override
  bool evaluate(List<String> variables, int assignment) {
    final index = variables.indexOf(name);
    return index >= 0 && (assignment >> index) & 1 == 1;
  }

  @override
  void _collect(List<String> out) {
    if (!out.contains(name)) out.add(name);
  }
}

/// `0` or `1`.
final class LibertyConstant extends LibertyExpression {
  /// Creates a constant.
  const LibertyConstant({required this.value});

  /// The constant's value.
  final bool value;

  @override
  bool evaluate(List<String> variables, int assignment) => value;

  @override
  void _collect(List<String> out) {}
}

/// An inverted operand.
final class LibertyNot extends LibertyExpression {
  /// Creates an inversion.
  const LibertyNot(this.operand);

  /// What is inverted.
  final LibertyExpression operand;

  @override
  bool evaluate(List<String> variables, int assignment) =>
      !operand.evaluate(variables, assignment);

  @override
  void _collect(List<String> out) => operand._collect(out);
}

/// The binary operators.
enum LibertyOperator {
  /// AND.
  and,

  /// OR.
  or,

  /// XOR.
  xor,
}

/// Two operands joined by an operator.
final class LibertyBinary extends LibertyExpression {
  /// Creates a binary expression.
  const LibertyBinary(this.operator, this.left, this.right);

  /// The operator.
  final LibertyOperator operator;

  /// The left operand.
  final LibertyExpression left;

  /// The right operand.
  final LibertyExpression right;

  @override
  bool evaluate(List<String> variables, int assignment) {
    final a = left.evaluate(variables, assignment);
    final b = right.evaluate(variables, assignment);
    return switch (operator) {
      LibertyOperator.and => a && b,
      LibertyOperator.or => a || b,
      LibertyOperator.xor => a != b,
    };
  }

  @override
  void _collect(List<String> out) {
    left._collect(out);
    right._collect(out);
  }
}

/// The gate a combinational function is, when it is one of the gates a
/// schematic has a symbol for.
enum LibertyGate {
  /// The input itself.
  buffer,

  /// The input inverted.
  inverter,

  /// AND of every input.
  and,

  /// The inverted AND of every input.
  nand,

  /// OR of every input.
  or,

  /// The inverted OR of every input.
  nor,

  /// XOR of every input.
  xor,

  /// The inverted XOR of every input.
  xnor,

  /// A two-input multiplexer: one input selects which of the other two the
  /// output follows.
  mux2,
}

/// The most inputs a function is classified over: 64 rows of truth table.
const int maxClassifiedInputs = 6;

/// The gate [function] computes over exactly the pins [inputs], or `null`
/// when it is none of the [LibertyGate]s: a compound gate such as an AOI,
/// a function of other pins, more than [maxClassifiedInputs] inputs, or an
/// expression that does not parse.
///
/// The test is the function's truth table, so `!(A&B)`, `!A+!B` and `(A B)'`
/// are all a NAND.
LibertyGate? classifyLibertyFunction(String function, List<String> inputs) {
  final expression = LibertyExpression.tryParse(function);
  if (expression == null) return null;
  final n = inputs.length;
  if (n == 0 || n > maxClassifiedInputs) return null;
  final used = expression.variables;
  if (used.length != n || !used.every(inputs.contains)) return null;
  final rows = 1 << n;
  final table = <bool>[
    for (var row = 0; row < rows; row++) expression.evaluate(inputs, row),
  ];
  bool matches(bool Function(int row) f) {
    for (var row = 0; row < rows; row++) {
      if (table[row] != f(row)) return false;
    }
    return true;
  }

  final all = rows - 1;
  if (n == 1) {
    if (matches((row) => row == 1)) return LibertyGate.buffer;
    if (matches((row) => row == 0)) return LibertyGate.inverter;
    return null;
  }
  if (matches((row) => row == all)) return LibertyGate.and;
  if (matches((row) => row != all)) return LibertyGate.nand;
  if (matches((row) => row != 0)) return LibertyGate.or;
  if (matches((row) => row == 0)) return LibertyGate.nor;
  bool odd(int row) => _popCount(row).isOdd;
  if (matches(odd)) return LibertyGate.xor;
  if (matches((row) => !odd(row))) return LibertyGate.xnor;
  if (n == 3) {
    bool bit(int row, int i) => (row >> i) & 1 == 1;
    for (var s = 0; s < 3; s++) {
      final a = (s + 1) % 3;
      final b = (s + 2) % 3;
      if (matches((row) => bit(row, s) ? bit(row, b) : bit(row, a)) ||
          matches((row) => bit(row, s) ? bit(row, a) : bit(row, b))) {
        return LibertyGate.mux2;
      }
    }
  }
  return null;
}

int _popCount(int value) {
  var count = 0;
  for (var v = value; v != 0; v >>= 1) {
    count += v & 1;
  }
  return count;
}

// ---------------------------------------------------------------------------
// Parsing
// ---------------------------------------------------------------------------

enum _Tok { name, zero, one, not, postNot, and, or, xor, open, close }

final class _Token {
  const _Token(this.kind, [this.text = '']);
  final _Tok kind;
  final String text;
}

/// Splits [text] into tokens; `null` on a character the grammar does not
/// have.
List<_Token>? _tokenize(String text) {
  final tokens = <_Token>[];
  var i = 0;
  while (i < text.length) {
    final c = text[i];
    switch (c) {
      case ' ' || '\t' || '\n' || '\r':
        // Whitespace between two operands is an AND; the parser decides
        // that from the tokens on either side.
        i++;
      case '!':
        tokens.add(const _Token(_Tok.not));
        i++;
      case "'":
        tokens.add(const _Token(_Tok.postNot));
        i++;
      case '*' || '&':
        tokens.add(const _Token(_Tok.and));
        i++;
      case '+' || '|':
        tokens.add(const _Token(_Tok.or));
        i++;
      case '^':
        tokens.add(const _Token(_Tok.xor));
        i++;
      case '(':
        tokens.add(const _Token(_Tok.open));
        i++;
      case ')':
        tokens.add(const _Token(_Tok.close));
        i++;
      case '"':
        // A function some writers quote twice; the quotes say nothing.
        i++;
      default:
        final start = i;
        while (i < text.length && !_isOperatorOrSpace(text[i])) {
          i++;
        }
        if (i == start) return null;
        final word = text.substring(start, i);
        tokens.add(switch (word) {
          '0' => const _Token(_Tok.zero),
          '1' => const _Token(_Tok.one),
          _ => _Token(_Tok.name, word),
        });
    }
  }
  return tokens;
}

bool _isOperatorOrSpace(String c) => switch (c) {
  ' ' ||
  '\t' ||
  '\n' ||
  '\r' ||
  '!' ||
  "'" ||
  '*' ||
  '&' ||
  '+' ||
  '|' ||
  '^' ||
  '(' ||
  ')' ||
  '"' => true,
  _ => false,
};

class _ExpressionParser {
  _ExpressionParser(this._tokens);

  final List<_Token> _tokens;
  int _pos = 0;

  bool get atEnd => _pos >= _tokens.length;

  _Tok? get _peek => atEnd ? null : _tokens[_pos].kind;

  /// Whether the next token can start an operand, which makes two operands
  /// side by side an AND.
  bool get _startsOperand => switch (_peek) {
    _Tok.name || _Tok.zero || _Tok.one || _Tok.not || _Tok.open => true,
    _ => false,
  };

  LibertyExpression? parseOr() {
    var left = _parseAnd();
    while (left != null && _peek == _Tok.or) {
      _pos++;
      final right = _parseAnd();
      if (right == null) return null;
      left = LibertyBinary(LibertyOperator.or, left, right);
    }
    return left;
  }

  LibertyExpression? _parseAnd() {
    var left = _parseXor();
    while (left != null) {
      if (_peek == _Tok.and) {
        _pos++;
      } else if (!_startsOperand) {
        break;
      }
      final right = _parseXor();
      if (right == null) return null;
      left = LibertyBinary(LibertyOperator.and, left, right);
    }
    return left;
  }

  LibertyExpression? _parseXor() {
    var left = _parseUnary();
    while (left != null && _peek == _Tok.xor) {
      _pos++;
      final right = _parseUnary();
      if (right == null) return null;
      left = LibertyBinary(LibertyOperator.xor, left, right);
    }
    return left;
  }

  LibertyExpression? _parseUnary() {
    if (_peek == _Tok.not) {
      _pos++;
      final operand = _parseUnary();
      return operand == null ? null : LibertyNot(operand);
    }
    var operand = _parsePrimary();
    while (operand != null && _peek == _Tok.postNot) {
      _pos++;
      operand = LibertyNot(operand);
    }
    return operand;
  }

  LibertyExpression? _parsePrimary() {
    if (atEnd) return null;
    final token = _tokens[_pos++];
    switch (token.kind) {
      case _Tok.name:
        return LibertyVariable(token.text);
      case _Tok.zero:
        return const LibertyConstant(value: false);
      case _Tok.one:
        return const LibertyConstant(value: true);
      case _Tok.open:
        final inner = parseOr();
        if (inner == null || _peek != _Tok.close) return null;
        _pos++;
        return inner;
      case _Tok.not ||
          _Tok.postNot ||
          _Tok.and ||
          _Tok.or ||
          _Tok.xor ||
          _Tok.close:
        return null;
    }
  }
}
