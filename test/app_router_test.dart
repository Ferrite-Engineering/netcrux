// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/app_router.dart';

void main() {
  group('webDeepLinkRedirect', () {
    test('a fragment hint reaching the router goes to the workspace', () {
      // What go_router sees for `https://app.netcrux.app/?json=…#scope=…`.
      for (final location in const [
        '/scope=top.u_cpu&sig=alu_y',
        '/scope=top',
        '/sig=alu_y',
      ]) {
        expect(webDeepLinkRedirect(Uri.parse(location)), '/', reason: location);
      }
    });

    test('real routes are left alone', () {
      for (final location in const ['/', '/settings']) {
        expect(webDeepLinkRedirect(Uri.parse(location)), isNull);
      }
    });
  });
}
