// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:netcrux/domain/models/netlist/bit_ref.dart';
import 'package:netcrux/domain/models/netlist/module.dart';
import 'package:netcrux/domain/models/schematic/pin_tie.dart';
import 'package:netcrux/l10n/generated/app_localizations.dart';
import 'package:netcrux/services/schematic/net_name_lookup.dart';

/// The inspector's words for what a pin with [tie] and [bits] is tied to.
///
/// A constant reads as its value, an all-`x` pin as an unknown value, and an
/// undriven or unconnected pin says so. A pin on nets lists what its bits
/// carry, most-significant first and each name once: the named net from
/// [module] (or the net id when Yosys named none) and the value of any bit
/// tied to a constant, so a bus with a few constant bits reads as its nets
/// plus those values.
String pinTieText(
  L10N l10n,
  PinTie tie,
  List<BitRef> bits,
  Module? module,
) {
  switch (tie.kind) {
    case PinTieKind.unconnected:
      return l10n.inspectorTieUnconnected;
    case PinTieKind.undriven:
      return l10n.inspectorTieUndriven;
    case PinTieKind.constant:
      return tie.isX
          ? l10n.inspectorTieUnknown
          : l10n.inspectorTieConstant(tie.constantText ?? '');
    case PinTieKind.net:
      final names = <String>{};
      final byNet = <int, String>{};
      for (final bit in bits.reversed) {
        switch (bit) {
          case NetBit(:final netId):
            names.add(
              byNet[netId] ??=
                  netNameForId(module, netId) ?? l10n.inspectorTieNet(netId),
            );
          case ConstantBit():
            names.add(bit.toJson() as String);
        }
      }
      return names.join(', ');
  }
}
