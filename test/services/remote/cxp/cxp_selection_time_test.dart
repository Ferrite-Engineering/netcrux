// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_cxp/crux_cxp.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/services/remote/cxp/cxp_selection_resolver.dart';

/// A selection's `time` (CXP §9.3.3) survives NetCrux forwarding it: as the
/// peer-targeted cross-probe selection and as the broadcast `notify_selection`.
void main() {
  const element = ElementId(kind: ElementKind.net, path: 'top.clk');

  ResolvedCxpSelection resolved({CxpTime? time}) => ResolvedCxpSelection(
    element: element,
    displayName: 'clk',
    scopePath: 'top',
    time: time,
  );

  test('the cross-probe selection carries the time unchanged', () {
    final selection = resolved(
      time: CxpTime.parse('41250ps'),
    ).toCrossProbeSelection();

    expect(selection.time?.toJson(), '41250ps');
    expect(selection.candidates, <ElementId>[element]);
  });

  test('a bare tick time stays a tick time', () {
    final selection = resolved(time: CxpTime.ticks(42)).toCrossProbeSelection();

    expect(selection.time?.isTicks, isTrue);
    expect(selection.time?.toJson(), '42');
  });

  test('the broadcast selection carries it too', () {
    final message = resolved(time: CxpTime.parse('7ns')).toNotifySelection();

    expect(message.time?.toJson(), '7ns');
  });

  test('without a time neither form sends one', () {
    expect(resolved().toCrossProbeSelection().time, isNull);
    expect(resolved().toNotifySelection().time, isNull);
  });
}
