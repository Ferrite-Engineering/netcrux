// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:meta/meta.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'netlist_reader_run_provider.g.dart';

/// Which reader a netlist is read by.
enum NetlistReaderKind {
  /// The native gate-level reader.
  native,

  /// Yosys elaboration.
  yosys,
}

/// The reader of the tab's current or last read, so the statistics strip
/// and Diagnostics can say which path ran.
@immutable
class NetlistReaderRun {
  /// Creates the record.
  const NetlistReaderRun(this.kind, {this.fellBack = false});

  /// The reader in use, or that produced the model on screen.
  final NetlistReaderKind kind;

  /// Whether the native reader was tried and declined, so Yosys read the
  /// design.
  final bool fellBack;

  @override
  bool operator ==(Object other) =>
      other is NetlistReaderRun &&
      other.kind == kind &&
      other.fellBack == fellBack;

  @override
  int get hashCode => Object.hash(kind, fellBack);
}

/// The tab's [NetlistReaderRun], or `null` before any read. Written by the
/// elaboration pipeline (`LoadedNetlist`).
@Riverpod(keepAlive: true)
class NetlistReaderRunNotifier extends _$NetlistReaderRunNotifier {
  @override
  NetlistReaderRun? build() => null;

  /// Records the reader in use now.
  // ignore: use_setters_to_change_properties, matches the sibling notifiers.
  void set(NetlistReaderRun? run) => state = run;
}
