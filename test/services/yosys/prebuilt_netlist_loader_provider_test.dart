// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/services/yosys/prebuilt_netlist_loader_provider.dart';

void main() {
  test(
    'the VM build elaborates HDL and parses netlists off the UI isolate',
    () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(hdlElaborationSupportedProvider), isTrue);
      expect(
        container.read(prebuiltNetlistLoaderProvider).parseOnIsolate,
        isTrue,
      );
    },
  );
}
