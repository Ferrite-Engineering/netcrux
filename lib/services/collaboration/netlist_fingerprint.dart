// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

/// A stable digest of an elaborated netlist, for answering one question:
/// **is everyone in this room looking at the same design?**
///
/// That question has a habit of being answered wrongly. A schematic review
/// where one participant elaborated before a colleague's commit landed looks
/// exactly like a review where everybody agrees, right up until two people
/// describe the same instance differently. WaveCrux hit the same problem with
/// waveform captures and solved it the same way — announce a digest, warn when
/// the room reports more than one.
///
/// **Only the digest crosses the wire.** The structure it summarizes is design
/// IP; the digest is 64 hex characters that reveal nothing about the design and
/// answer the only question a peer needs answered.
library;

import 'dart:convert';

import 'package:crux_netlist/crux_netlist.dart';
import 'package:crypto/crypto.dart';

/// SHA-256 over a canonical structural summary of [model], as lowercase hex.
///
/// **Structure, not the raw JSON.** Two elaborations of identical RTL can
/// differ in whitespace, key order and the Yosys version banner while
/// describing the same design; hashing the document would report a mismatch
/// every time somebody upgraded Yosys. So the summary is built from what
/// actually has to match for two people to be looking at the same schematic:
/// module names, and each module's port, cell and net counts, in sorted order.
///
/// Deliberately coarse. It will not catch a change that preserves every count —
/// a renamed net, a swapped input — and it is not trying to: this is a "you are
/// looking at different designs" alarm, not a verification tool. A digest
/// sensitive enough to fire on a formatting difference would be ignored inside
/// a week, which is worse than one that occasionally stays quiet.
String netlistFingerprint(NetlistModel model) {
  final names = model.modules.keys.toList()..sort();
  final buffer = StringBuffer();
  for (final name in names) {
    final module = model.modules[name]!;
    buffer
      ..write(name)
      ..write(':')
      ..write(module.ports.length)
      ..write(',')
      ..write(module.cells.length)
      ..write(',')
      ..write(module.nets.length)
      ..write(';');
  }
  return sha256.convert(utf8.encode(buffer.toString())).toString();
}
