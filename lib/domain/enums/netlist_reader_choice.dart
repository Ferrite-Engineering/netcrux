// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

/// Which reader turns a design's sources into a netlist.
///
/// The user's Settings → Engines switch, a project's `netlistReader` key and
/// the `--netlist-reader` command-line flag all speak this vocabulary. A
/// design the native gate-level reader cannot read faithfully is read by
/// Yosys whatever the choice (the fallback names the reason in Diagnostics),
/// so [native] means "prefer the native reader", not "refuse Yosys".
enum NetlistReaderChoice {
  /// Follow the next level down: the project follows the user's setting.
  auto,

  /// Read structural Verilog with the native gate-level reader, falling
  /// back to Yosys for anything it does not handle.
  native,

  /// Always read through Yosys.
  yosys;

  /// The choice written as [name], or `null` for any other text.
  static NetlistReaderChoice? parse(String? text) {
    if (text == null) return null;
    final lower = text.trim().toLowerCase();
    for (final choice in values) {
      if (choice.name == lower) return choice;
    }
    return null;
  }

  /// The reader to use given the three levels that can speak: the
  /// command-line flag [cli] for this session, the [project]'s key, and the
  /// user's [settingEnabled] switch. The first that says [native] or [yosys]
  /// wins; [auto] defers. [NetlistReaderDecision.source] names the level
  /// that decided.
  static NetlistReaderDecision resolve({
    required NetlistReaderChoice? cli,
    required NetlistReaderChoice project,
    required bool settingEnabled,
  }) {
    final levels = <(NetlistReaderChoice?, NetlistReaderSource)>[
      (cli, NetlistReaderSource.commandLine),
      (project, NetlistReaderSource.project),
    ];
    for (final (choice, source) in levels) {
      if (choice == NetlistReaderChoice.native) {
        return NetlistReaderDecision(native: true, source: source);
      }
      if (choice == NetlistReaderChoice.yosys) {
        return NetlistReaderDecision(native: false, source: source);
      }
    }
    return NetlistReaderDecision(
      native: settingEnabled,
      source: NetlistReaderSource.setting,
    );
  }
}

/// Which level of configuration chose the reader.
enum NetlistReaderSource {
  /// The `--netlist-reader` flag.
  commandLine,

  /// The project's `netlistReader` key.
  project,

  /// Settings → Engines.
  setting,
}

/// The outcome of [NetlistReaderChoice.resolve].
class NetlistReaderDecision {
  /// Creates a decision.
  const NetlistReaderDecision({required this.native, required this.source});

  /// Whether the native gate-level reader is tried first.
  final bool native;

  /// Who decided.
  final NetlistReaderSource source;
}
