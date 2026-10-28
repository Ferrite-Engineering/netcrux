// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// An overlay's overrides replace the open core's when both bind the same
// provider, instead of reaching the container twice.

import 'package:crux_cxp_ui/crux_cxp_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/core/providers/layered_overrides.dart';
import 'package:netcrux/features/remote/netcrux_cxp_overrides.dart';

final _a = Provider<String>((_) => 'default a', name: 'a');
final _b = Provider<String>((_) => 'default b', name: 'b');

void main() {
  test('an entry the top list also overrides is dropped from the base', () {
    final layered = layeredOverrides(
      <Override>[
        _a.overrideWithValue('core a'),
        _b.overrideWithValue('core b'),
      ],
      <Override>[_a.overrideWithValue('overlay a')],
    );
    expect(layered, hasLength(2));
    final container = ProviderContainer(overrides: layered);
    addTearDown(container.dispose);
    expect(container.read(_a), 'overlay a');
    expect(container.read(_b), 'core b');
  });

  test('with nothing shared, both lists pass through in order', () {
    final core = _a.overrideWithValue('core a');
    final overlay = _b.overrideWithValue('overlay b');
    expect(layeredOverrides(<Override>[core], <Override>[overlay]), <Override>[
      core,
      overlay,
    ]);
  });

  test('an overlay can rebind the cross-probe send observer the open core '
      'binds, as the Pro overlay does to add its audit line', () {
    // Spread as two plain lists, the core's CXP overrides and an overlay's
    // observer, this container refused to build ("Tried to override a
    // provider twice"), and every debug and integration launch of the Pro
    // build failed with it.
    void observer(CrossProbeSendRecord record) {}
    final container = ProviderContainer(
      overrides: layeredOverrides(netcruxCxpOverrides, <Override>[
        crossProbeSendObserverProvider.overrideWith((ref) => observer),
      ]),
    );
    addTearDown(container.dispose);
    expect(container.read(crossProbeSendObserverProvider), same(observer));
  });
}
