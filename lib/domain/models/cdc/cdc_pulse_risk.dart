// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

/// Why a one-cycle pulse crossing a clock-domain boundary can be lost.
///
/// A synchronizer passes a level safely, but a pulse that is high for
/// only one source-clock cycle can begin and end between two edges of
/// the destination clock, and then no destination flop ever sees it. The
/// structure of the synchronizer does not change that: a proper 2-flop
/// chain drops the pulse just the same. A crossing carries a pulse risk
/// when its source register is a one-cycle pulse in the source domain
/// (high for exactly one cycle every time it is high, or low for exactly
/// one cycle every time it is low) and nothing stretches it or hands it
/// across with a handshake.
///
/// The value says what the netlist tells about the two clocks. NetCrux
/// never guesses a frequency from a clock's name: when the netlist does
/// not relate the clocks, the risk is [clockRatesUnknown], and both
/// values rate the crossing at least a warning.
enum CdcPulseRisk {
  /// The destination clock is derived from the source clock through one
  /// or more registers (a clock divider), so it runs slower: at most half
  /// the source rate. A one-cycle pulse falls between destination edges
  /// on some cycles.
  destinationSlower,

  /// The netlist does not say how the two clocks' rates compare (two
  /// independent clock inputs, PLL outputs, or anything the analysis
  /// cannot relate). A one-cycle pulse is lost whenever the destination
  /// clock is not fast enough to sample it.
  clockRatesUnknown;

  /// Stable JSON tag used by fixture round-trip.
  String toJsonString() => name;

  /// Parses [raw] into a [CdcPulseRisk], or null when [raw] is null.
  /// An unknown tag maps to [clockRatesUnknown], the reading that claims
  /// the least about the clocks.
  static CdcPulseRisk? fromJsonString(String? raw) {
    if (raw == null) return null;
    for (final v in CdcPulseRisk.values) {
      if (v.name == raw) return v;
    }
    return CdcPulseRisk.clockRatesUnknown;
  }
}
