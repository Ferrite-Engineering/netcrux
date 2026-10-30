// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

/// [stderr] without the `Info: Netlist read by ...` line the elaboration
/// pipeline puts at the head of Diagnostics to say which reader ran, for a
/// test about what else the Diagnostics text holds.
String withoutReaderNote(String stderr) {
  final lines = stderr
      .split('\n')
      .where((line) => !line.startsWith('Info: Netlist read by'));
  return lines.join('\n');
}
