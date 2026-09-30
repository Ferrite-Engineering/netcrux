// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

@TestOn('browser')
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/services/yosys/prebuilt_netlist_loader.dart';
import 'package:netcrux/services/yosys/prebuilt_netlist_loader_provider.dart';

const String _netlist =
    '{"creator":"test","modules":{"top":{"attributes":{"top":"1"},'
    '"ports":{},"cells":{},"netnames":{}}}}';

/// Runs in a real browser (`flutter test --platform chrome`): the browser
/// build cannot elaborate and has no `Isolate.spawn`, so it must take the
/// netlist path and parse in place.
void main() {
  test('the browser build reads netlists and parses them in place', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(container.read(hdlElaborationSupportedProvider), isFalse);
    expect(
      container.read(prebuiltNetlistLoaderProvider).parseOnIsolate,
      isFalse,
    );
    final model = await PrebuiltNetlistLoader(
      read: (_) async => _netlist,
    ).load('blob:https://app.netcrux.app/1#top.json');
    expect(model?.topModule?.name, 'top');
  });
}
