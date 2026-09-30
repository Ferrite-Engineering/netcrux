// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:netcrux/domain/models/netlist/bit_ref.dart';
import 'package:netcrux/domain/models/netlist/module.dart';

/// Reverse-resolves [netId] to the name of the NAMED net that declares it
/// inside [module], or `null` when [module] is absent or no named net carries
/// the bit.
///
/// Prefers a source-declared net (Yosys `hide_name == 0`) over a synthetic
/// auto-generated one so a multi-bit user bus like `sample_a` wins over the
/// `$0\sample_a[7:0]` next-state shadow net Yosys emits for the same bit.
///
/// Everything else in the codebase resolves names *forward* — a name to a
/// selection, as `AnalysisSelectionProbe` does. This is the one backward
/// lookup, and it has two consumers with the same question: the CXP selection
/// resolver, naming a directly-selected wire for a peer, and the X-trace
/// result panel, turning an `XTraceStep.netId` into a row a human can read.
/// It lives here rather than in either of them because a second copy would be
/// a second answer to "what is this net called", and the alias-preference rule
/// above is exactly the part that must not diverge.
///
/// Callers that have a register name to bias toward want the CXP resolver's
/// alias-preference variant instead — that one picks between several public
/// aliases of one merged net, which is a different question.
String? netNameForId(Module? module, int netId) {
  if (module == null) return null;
  String? syntheticMatch;
  for (final net in module.nets.values) {
    final carriesBit = net.bits.any((b) => b is NetBit && b.netId == netId);
    if (!carriesBit) continue;
    if (!net.hideName) return net.name;
    syntheticMatch ??= net.name;
  }
  return syntheticMatch;
}
