// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

/// How the Inspector shows one cell parameter value.
class ParameterValueText {
  /// Creates a parameter value text.
  const ParameterValueText({required this.display, this.raw});

  /// What the row reads: the value as a number for a binary string, the
  /// string as written otherwise.
  final String display;

  /// The binary string the netlist carries, set only when [display] is a
  /// reading of it. The row offers it on hover.
  final String? raw;
}

final RegExp _binaryString = RegExp(r'^[01]+$');

/// The widest binary string whose decimal value is worth printing; a wider
/// one shows hex alone, since a 300-digit decimal says nothing.
const int _maxDecimalBits = 64;

/// The most significant bits a value can use before its hex form is added
/// to the decimal: `255` stands alone, `65280` gains `0xFF00`.
const int _maxBitsWithoutHex = 8;

/// Reads a parameter [value] the way Yosys writes it into its JSON.
///
/// Yosys writes a numeric parameter as a string of `0` and `1` characters, one
/// per bit, most-significant first: a `$dff` of width one carries `WIDTH` as
/// `00000000000000000000000000000001`. A string made only of those characters
/// reads as an unsigned number: decimal, followed by the hex form (padded to
/// the width of the string) when the value needs more than eight bits, or hex
/// alone past 64 bits. The bits themselves are kept in [ParameterValueText.raw]
/// for the row's hover.
///
/// Anything else is returned unchanged: a real string, a value with `x` or
/// `z` bits, a value that Yosys marks as a string by a trailing space, and the
/// empty string. A one-bit value (`0`, `1`) already reads as its number and
/// carries no raw form.
ParameterValueText parameterValueText(String value) {
  if (!_binaryString.hasMatch(value)) {
    return ParameterValueText(display: value);
  }
  final number = BigInt.parse(value, radix: 2);
  final String display;
  if (value.length > _maxDecimalBits) {
    display = _hex(number, value.length);
  } else if (number.bitLength > _maxBitsWithoutHex) {
    display = '$number (${_hex(number, value.length)})';
  } else {
    display = number.toString();
  }
  return ParameterValueText(
    display: display,
    raw: display == value ? null : value,
  );
}

String _hex(BigInt number, int bits) {
  final digits = (bits + 3) ~/ 4;
  return '0x${number.toRadixString(16).toUpperCase().padLeft(digits, '0')}';
}
