#!/usr/bin/env python3
# Copyright 2026 Ferrite Engineering LLC
# SPDX-License-Identifier: Apache-2.0

"""Independent oracle for the gate symbols NetCrux draws for Liberty cells.

    python3 -I liberty_oracle.py LIB [LIB...]            # print JSON
    python3 -I liberty_oracle.py --write LIB [LIB...]    # write expected files
    python3 -I liberty_oracle.py --check LIB [LIB...]    # compare with them
    python3 -I liberty_oracle.py --names PDK LIB [LIB...]

For every cell of each Liberty file (plain or `.gz`) it states the symbol
NetCrux's documentation says the cell is drawn as, the pins that carry a
clock wedge, the power pins drawn on the top face, the ground pins drawn on
the bottom face, and the area. `--write` puts that in
`<name>.expected_symbols.json` beside each library, where `<name>` is the
file name without `.lib`, `.liberty` and `.gz`.

The rules are the ones in `docs-site/docs/files-and-projects.md` (section
"Standard cells as gate symbols"), read as a specification. Nothing here
comes from NetCrux's own code: this file has its own Liberty reader and its
own Boolean-expression evaluator (operator precedence by shunting-yard into
postfix form, then a truth table), so that a fault in NetCrux's reader or
classifier shows up as a disagreement instead of being copied into the
expectation.

`--names` cross-checks the result against the cell naming convention of
PDK (`sky130`, `gf180mcu`, `sg13g2`, `asap7`) and prints each cell where the
name suggests a different symbol. Each such cell is decided by reading its
Liberty text and recorded in REVIEW.md.

Standard library only; run with `python3 -I`.
"""

import gzip
import json
import os
import re
import sys

KINDS = ('buffer', 'inverter', 'and', 'nand', 'or', 'nor', 'xor', 'xnor',
         'mux2', 'dff', 'latch', 'box')

MAX_INPUTS = 6

POWER_TYPES = {'primary_power', 'backup_power', 'internal_power', 'nwell',
               'deepnwell'}
GROUND_TYPES = {'primary_ground', 'backup_ground', 'internal_ground',
                'pwell', 'deeppwell'}

# Groups whose contents no rule reads; their bodies are stepped over.
SKIPPED_GROUPS = {'timing', 'internal_power', 'leakage_power',
                  'lu_table_template', 'power_lut_template',
                  'output_current_template', 'normalized_driver_waveform',
                  'receiver_capacitance', 'ccsn_first_stage',
                  'ccsn_last_stage', 'operating_conditions',
                  'wire_load', 'wire_load_selection'}


# ---------------------------------------------------------------------------
# Liberty reader
# ---------------------------------------------------------------------------

_TOKEN = re.compile(r'''
    (?P<space>[ \t\r\f]+)
  | (?P<newline>\n)
  | (?P<cont>\\\r?\n)
  | (?P<comment>/\*.*?\*/|//[^\n]*)
  | (?P<string>"(?:[^"\\]|\\.)*")
  | (?P<punct>[(){}:;,])
  | (?P<word>(?:\[[^\]\n]*\]|[^\s(){}:;,"\[])+)
''', re.S | re.X)


class Group:
    __slots__ = ('name', 'args', 'simple', 'children')

    def __init__(self, name, args):
        self.name = name
        self.args = args
        self.simple = {}
        self.children = []

    def first(self, name):
        for child in self.children:
            if child.name == name:
                return child
        return None


def _tokens(text):
    """(kind, text, newline_before) for every significant token."""
    newline = False
    pos = 0
    n = len(text)
    match = _TOKEN.match
    while pos < n:
        m = match(text, pos)
        if m is None:
            raise ValueError(f'unreadable text at offset {pos}: '
                             f'{text[pos:pos + 20]!r}')
        pos = m.end()
        kind = m.lastgroup
        if kind == 'newline':
            newline = True
            continue
        if kind in ('space', 'cont'):
            continue
        if kind == 'comment':
            if '\n' in m.group():
                newline = True
            continue
        value = m.group()
        if kind == 'string':
            body = value[1:-1]
            # A backslash-newline inside a string continues it; any other
            # escaped character stands for itself.
            body = re.sub(r'\\\r?\n', '', body)
            body = re.sub(r'\\(.)', r'\1', body, flags=re.S)
            yield ('string', body, newline)
        else:
            yield (kind if kind == 'word' else value, value, newline)
        newline = False


class _Reader:
    def __init__(self, text):
        self._tokens = _tokens(text)
        self._back = []

    def next(self):
        if self._back:
            return self._back.pop()
        return next(self._tokens, ('eof', '', True))

    def push(self, token):
        self._back.append(token)

    def skip_body(self):
        depth = 1
        while depth:
            kind = self.next()[0]
            if kind == '{':
                depth += 1
            elif kind == '}':
                depth -= 1
            elif kind == 'eof':
                raise ValueError('unterminated group')

    def body(self, group):
        """Reads statements into [group] up to its closing brace."""
        while True:
            token = self.next()
            kind = token[0]
            if kind == '}' or kind == 'eof':
                return
            if kind == ';':
                continue
            name = token[1]
            follow = self.next()
            if follow[0] == ':':
                parts = []
                while True:
                    t = self.next()
                    if t[0] == ';':
                        break
                    if t[0] in ('}', 'eof') or (t[2] and parts):
                        self.push(t)
                        break
                    parts.append(t[1])
                group.simple.setdefault(name, ' '.join(parts))
            elif follow[0] == '(':
                args = []
                while True:
                    t = self.next()
                    if t[0] == ')':
                        break
                    if t[0] in ('word', 'string'):
                        args.append(t[1])
                    elif t[0] == 'eof':
                        raise ValueError('unterminated argument list')
                after = self.next()
                if after[0] == '{':
                    if name in SKIPPED_GROUPS:
                        self.skip_body()
                        continue
                    child = Group(name, args)
                    self.body(child)
                    group.children.append(child)
                else:
                    if after[0] != ';':
                        self.push(after)
                    # A complex attribute (`members (A, B);`).
                    group.children.append(Group(name, args))
            else:
                raise ValueError(f'unexpected {follow[1]!r} after {name!r}')


def read_library(path):
    opener = gzip.open if path.endswith('.gz') else open
    with opener(path, 'rt', encoding='utf-8', errors='replace') as f:
        text = f.read()
    root = Group('', [])
    _Reader(text).body(root)
    library = root.first('library')
    if library is None:
        raise ValueError(f'{path}: no library group')
    return library


# ---------------------------------------------------------------------------
# Boolean expressions
# ---------------------------------------------------------------------------

_PRECEDENCE = {'!': 4, '^': 3, '&': 2, '|': 1}
_EXPR_TOKEN = re.compile(r"\s+|[!'^*&+|()]|[^\s!'^*&+|()]+")


def to_postfix(expression):
    """The expression in postfix form, or None when it does not parse.

    Operators: prefix `!` and postfix `'` invert, `^` is XOR, `*`, `&` and
    two operands side by side are AND, `+` and `|` are OR; inversion binds
    tightest, then XOR, then AND, then OR. `0` and `1` are constants.
    """
    raw = [t for t in _EXPR_TOKEN.findall(expression.replace('"', ' '))
           if not t.isspace()]
    if not raw:
        return None
    tokens = []
    for t in raw:
        t = {'*': '&', '+': '|'}.get(t, t)
        if tokens:
            prev = tokens[-1]
            ends = prev not in ('!', '^', '&', '|', '(')
            starts = t not in ('^', '&', '|', ')', "'")
            if ends and starts:
                tokens.append('&')
        tokens.append(t)
    out = []
    stack = []
    expect_operand = True
    for t in tokens:
        if t == '(':
            if not expect_operand:
                return None
            stack.append(t)
        elif t == ')':
            if expect_operand:
                return None
            while stack and stack[-1] != '(':
                out.append(stack.pop())
            if not stack:
                return None
            stack.pop()
        elif t == "'":
            if expect_operand:
                return None
            out.append('!')
        elif t == '!':
            if not expect_operand:
                return None
            stack.append(t)
        elif t in ('^', '&', '|'):
            if expect_operand:
                return None
            while (stack and stack[-1] != '(' and
                   _PRECEDENCE[stack[-1]] >= _PRECEDENCE[t]):
                out.append(stack.pop())
            stack.append(t)
            expect_operand = True
        else:
            if not expect_operand:
                return None
            out.append(('const', t == '1') if t in ('0', '1') else
                       ('var', t))
            expect_operand = False
    if expect_operand:
        return None
    while stack:
        top = stack.pop()
        if top == '(':
            return None
        out.append(top)
    return out


def variables(postfix):
    seen = []
    for item in postfix:
        if isinstance(item, tuple) and item[0] == 'var' and \
                item[1] not in seen:
            seen.append(item[1])
    return seen


def evaluate(postfix, values):
    stack = []
    for item in postfix:
        if isinstance(item, tuple):
            stack.append(item[1] if item[0] == 'const' else values[item[1]])
        elif item == '!':
            stack.append(not stack.pop())
        else:
            b = stack.pop()
            a = stack.pop()
            stack.append({'&': a and b, '|': a or b, '^': a != b}[item])
    (result,) = stack
    return result


def gate_of(function, inputs):
    """The gate `function` is over exactly `inputs`, or 'box'."""
    postfix = to_postfix(function)
    if postfix is None or not inputs or len(inputs) > MAX_INPUTS:
        return 'box'
    if set(variables(postfix)) != set(inputs):
        return 'box'
    rows = []
    for row in range(1 << len(inputs)):
        bits = [(row >> i) & 1 == 1 for i in range(len(inputs))]
        rows.append((bits, evaluate(postfix, dict(zip(inputs, bits)))))

    def table_is(reference):
        return all(out == reference(bits) for bits, out in rows)

    if len(inputs) == 1:
        if table_is(lambda b: b[0]):
            return 'buffer'
        if table_is(lambda b: not b[0]):
            return 'inverter'
        return 'box'
    candidates = (
        ('and', all),
        ('nand', lambda b: not all(b)),
        ('or', any),
        ('nor', lambda b: not any(b)),
        ('xor', lambda b: sum(b) % 2 == 1),
        ('xnor', lambda b: sum(b) % 2 == 0),
    )
    for name, reference in candidates:
        if table_is(reference):
            return name
    if len(inputs) == 3:
        for s in range(3):
            d0, d1 = [i for i in range(3) if i != s]
            for low, high in ((d0, d1), (d1, d0)):
                if table_is(lambda b, s=s, low=low, high=high:
                            b[high] if b[s] else b[low]):
                    return 'mux2'
    return 'box'


# ---------------------------------------------------------------------------
# Cells
# ---------------------------------------------------------------------------

def supply_side(name, pg_type):
    """'power', 'ground' or None for a pg_pin."""
    if pg_type in POWER_TYPES:
        return 'power'
    if pg_type in GROUND_TYPES:
        return 'ground'
    upper = name.upper()
    if upper.startswith(('VDD', 'VCC')) or upper in ('VPWR', 'VPB'):
        return 'power'
    if upper.startswith(('VSS', 'GND')) or upper in ('VGND', 'VNB'):
        return 'ground'
    return None


def describe_cell(cell):
    name = cell.args[0] if cell.args else ''
    area = cell.simple.get('area')
    pins = {}          # name -> attributes, signal pins in order
    pg = {}            # name -> pg_type or None
    vectors = False
    storage = []       # ff / latch groups
    other_storage = 0
    for child in cell.children:
        if child.name == 'pin':
            for pin in child.args:
                pins.setdefault(pin, child.simple)
        elif child.name == 'pg_pin':
            for pin in child.args:
                pg.setdefault(pin, child.simple.get('pg_type'))
        elif child.name in ('bus', 'bundle'):
            vectors = True
        elif child.name in ('ff', 'latch'):
            storage.append(child)
        elif child.name in ('ff_bank', 'latch_bank', 'statetable'):
            other_storage += 1
    power = sorted(p for p, t in pg.items() if supply_side(p, t) == 'power')
    ground = sorted(p for p, t in pg.items()
                    if supply_side(p, t) == 'ground')
    signal = {p: a for p, a in pins.items()
              if p not in pg and a.get('direction') != 'internal'}
    inputs = [p for p, a in signal.items() if a.get('direction') == 'input']
    outputs = [p for p, a in signal.items() if a.get('direction') == 'output']
    others = [p for p in signal if p not in inputs and p not in outputs]

    kind = 'box'
    clocks = []
    tri_state = any('three_state' in signal[p] for p in outputs)
    if (not vectors and not others and inputs and outputs and
            not other_storage and len(storage) <= 1 and not tri_state):
        if storage:
            group = storage[0]
            state = set(group.args)
            readable = True
            for p in outputs:
                function = signal[p].get('function')
                postfix = to_postfix(function) if function else None
                used = variables(postfix) if postfix else []
                if not used or not set(used) <= state:
                    readable = False
            if readable:
                if group.name == 'ff':
                    kind = 'dff'
                    clocked_on = group.simple.get('clocked_on', '')
                    postfix = to_postfix(clocked_on) if clocked_on else None
                    named = set(variables(postfix)) if postfix else set()
                    marked = {p for p in inputs
                              if signal[p].get('clock', '').lower() == 'true'}
                    clocks = sorted(p for p in inputs
                                    if p in named or p in marked)
                else:
                    kind = 'latch'
        elif len(outputs) == 1:
            function = signal[outputs[0]].get('function')
            if function:
                kind = gate_of(function, inputs)
    return name, {
        'kind': kind,
        'clock': clocks,
        'power': power,
        'ground': ground,
        'area': float(area) if area is not None else None,
    }


def describe_library(path):
    library = read_library(path)
    cells = {}
    for child in library.children:
        if child.name == 'cell':
            name, entry = describe_cell(child)
            cells.setdefault(name, entry)
    counts = {kind: 0 for kind in KINDS}
    for entry in cells.values():
        counts[entry['kind']] += 1
    return {
        'library': library.args[0] if library.args else None,
        'source': os.path.basename(path),
        'oracle': 'liberty_oracle.py',
        'counts': counts,
        'cells': cells,
    }


# ---------------------------------------------------------------------------
# Naming conventions, for the cross-check only
# ---------------------------------------------------------------------------

def _function_part(pdk, cell):
    if pdk in ('sky130', 'gf180mcu'):
        base = cell.split('__', 1)[-1]
        return re.sub(r'_\d+$', '', base)
    if pdk == 'sg13g2':
        base = cell[len('sg13g2_'):] if cell.startswith('sg13g2_') else cell
        return re.sub(r'_\d+$', '', base)
    if pdk == 'asap7':
        base = cell.split('_ASAP7', 1)[0]
        return re.sub(r'(x|xp)\d+[a-z0-9]*$', '', base, flags=re.I).lower()
    raise SystemExit(f'unknown PDK {pdk!r}')


_NAME_RULES = [
    # Integrated clock gates: a latch and a gate in one cell.
    (r's?dlclkp|icg.*|s?lgcp', 'box'),
    (r'(clk)?buf|bufbuf|dly.*|clkdlybuf.*|probe_p|hb\d*', 'buffer'),
    (r'(clk)?inv(lp)?|bufinv', 'inverter'),
    (r'and[2-6]', 'and'),
    (r'nand[2-6]', 'nand'),
    (r'or[2-6]', 'or'),
    (r'nor[2-6]', 'nor'),
    (r'xor[2-3]', 'xor'),
    (r'xnor[2-3]', 'xnor'),
    (r'mux2', 'mux2'),
    (r's?e?df.*|async_?dff.*|icg.*', 'dff'),
    (r'dl.*|lat.*|dh.*', 'latch'),
]


def kind_by_name(pdk, cell):
    part = _function_part(pdk, cell)
    for pattern, kind in _NAME_RULES:
        if re.fullmatch(pattern, part):
            return kind
    return 'box'


# ---------------------------------------------------------------------------
# Output
# ---------------------------------------------------------------------------

def expected_path(path):
    base = os.path.basename(path)
    for suffix in ('.gz', '.lib', '.liberty'):
        if base.endswith(suffix):
            base = base[:-len(suffix)]
    return os.path.join(os.path.dirname(path),
                        base + '.expected_symbols.json')


def render(result):
    """JSON with one cell per line, so a diff shows one line per cell."""
    lines = ['{']
    for key in ('library', 'source', 'oracle', 'counts'):
        lines.append(f'  {json.dumps(key)}: {json.dumps(result[key])},')
    lines.append('  "cells": {')
    names = sorted(result['cells'])
    for i, name in enumerate(names):
        comma = ',' if i < len(names) - 1 else ''
        entry = json.dumps(result['cells'][name], sort_keys=True)
        lines.append(f'    {json.dumps(name)}: {entry}{comma}')
    lines.append('  }')
    lines.append('}')
    return '\n'.join(lines) + '\n'


def main(argv):
    args = argv[1:]
    mode = 'print'
    pdk = None
    if args and args[0] in ('--write', '--check'):
        mode = args.pop(0)[2:]
    elif args and args[0] == '--names':
        mode = 'names'
        args.pop(0)
        pdk = args.pop(0)
    if not args:
        sys.exit(__doc__)
    failed = False
    for path in args:
        result = describe_library(path)
        text = render(result)
        if mode == 'print':
            sys.stdout.write(text)
        elif mode == 'write':
            with open(expected_path(path), 'w', encoding='utf-8') as f:
                f.write(text)
            print(f'{expected_path(path)}: {result["counts"]}')
        elif mode == 'check':
            with open(expected_path(path), encoding='utf-8') as f:
                if f.read() != text:
                    print(f'{expected_path(path)}: differs')
                    failed = True
                else:
                    print(f'{expected_path(path)}: matches')
        else:
            for name in sorted(result['cells']):
                by_function = result['cells'][name]['kind']
                by_name = kind_by_name(pdk, name)
                if by_function != by_name:
                    print(f'{name}\tname={by_name}\tfunction={by_function}')
    if failed:
        sys.exit(1)


if __name__ == '__main__':
    main(sys.argv)
