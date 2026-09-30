// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meta/meta.dart';

/// Extracts the current pass name from a Yosys stderr line.
///
/// Yosys announces each pass on stderr with a numbered banner:
///
/// ```text
/// 2.1. Executing HIERARCHY pass (managing design hierarchy).
/// 4. Executing PROC pass (convert processes to netlists).
/// ```
///
/// Returns the pass token (`HIERARCHY`, `PROC`) or `null` for any line
/// that is not a pass banner — which is most of them, since Yosys
/// interleaves warnings and per-module chatter between banners.
///
/// Deliberately strict about the leading section number. Yosys also prints
/// lines like `Executing Verilog-2005 frontend` without one, and matching
/// those would make the readout jump between real passes and incidental
/// mentions.
@visibleForTesting
String? parseYosysPassName(String line) {
  final match = _passBanner.firstMatch(line.trim());
  return match?.group(1);
}

final RegExp _passBanner = RegExp(
  r'^\d+(?:\.\d+)*\.\s+Executing\s+([A-Za-z0-9_]+)\s+pass\b',
);

/// The Yosys pass currently executing, or `null` when nothing is running.
///
/// Root-scope: elaboration is one subprocess at a time, and the strip
/// shows whatever is running now regardless of which tab started it.
///
/// Feeds NetCrux's statistics-strip elaboration indicator.
/// Distinct from the Tab Diagnostics
/// drawer, which reports what the *last* run produced: this is "what is
/// happening right now", and it is only meaningful while a run is in
/// flight.
class ElaborationProgressNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  /// Consumes a Yosys stderr line, updating the pass name if it is a
  /// banner. Non-banner lines leave the current pass in place — the
  /// warnings Yosys prints between passes are not a reason to blank the
  /// readout.
  void consumeStderrLine(String line) {
    final pass = parseYosysPassName(line);
    if (pass == null) return;
    state = pass;
  }

  /// Clears the readout when a run ends.
  void clear() => state = null;
}

/// The currently-executing Yosys pass, or `null`.
final NotifierProvider<ElaborationProgressNotifier, String?>
elaborationProgressProvider =
    NotifierProvider<ElaborationProgressNotifier, String?>(
      ElaborationProgressNotifier.new,
    );
