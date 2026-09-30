// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/interfaces/netlist_diff_service.dart';
import 'package:netcrux/domain/models/diff/netlist_diff.dart';
import 'package:netcrux/domain/models/diff/netlist_diff_request.dart';
import 'package:netcrux/services/diff/netlist_diff_service_provider.dart';

class _TestService implements NetlistDiffService {
  bool compareCalled = false;
  @override
  Future<NetlistDiff> compare(NetlistDiffRequest request) async {
    compareCalled = true;
    return NetlistDiff.empty();
  }

  @override
  Stream<void> get diffsInvalidated => const Stream<void>.empty();
}

void main() {
  test('netlistDiffServiceProvider defaults to NoopNetlistDiffService', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    expect(c.read(netlistDiffServiceProvider), isA<NoopNetlistDiffService>());
  });

  test('netlistDiffServiceProvider accepts overrides', () async {
    final test = _TestService();
    final c = ProviderContainer(
      overrides: <Override>[
        netlistDiffServiceProvider.overrideWithValue(test),
      ],
    );
    addTearDown(c.dispose);
    final s = c.read(netlistDiffServiceProvider);
    expect(s, same(test));
    await s.compare(
      const NetlistDiffRequest(
        baselineNetlist: NetlistRef(identifier: 'a'),
        comparisonNetlist: NetlistRef(identifier: 'b'),
      ),
    );
    expect(test.compareCalled, isTrue);
  });
}
