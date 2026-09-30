// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/services/custom_cell_symbols/custom_cell_symbol_openers.dart';

void main() {
  testWidgets(
    'every opener defaults to a no-op that swallows the dispatch',
    (tester) async {
      var didInvokeAny = false;
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Consumer(
              builder: (context, ref, _) {
                return Material(
                  child: Builder(
                    builder: (innerContext) {
                      return ElevatedButton(
                        onPressed: () {
                          // Invoke every opener — open-core defaults
                          // are all no-ops that complete silently.
                          ref.read(openSymbolManagerOpenerProvider)(
                            innerContext,
                          );
                          ref.read(importSymbolFromSvgOpenerProvider)(
                            innerContext,
                            ref,
                          );
                          ref.read(
                            editSymbolForCurrentInstanceOpenerProvider,
                          )(innerContext, ref, moduleType: 'mod_a');
                          ref.read(
                            removeSymbolForCurrentInstanceOpenerProvider,
                          )(innerContext, ref);
                          didInvokeAny = true;
                        },
                        child: const Text('go'),
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ),
      );

      await tester.tap(find.byType(ElevatedButton));
      await tester.pump();
      expect(didInvokeAny, isTrue);
      expect(tester.takeException(), isNull);
    },
  );

  test(
    'opener providers default to instances of the typedef shapes',
    () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      expect(
        c.read(openSymbolManagerOpenerProvider),
        isA<OpenSymbolManagerOpener>(),
      );
      expect(
        c.read(importSymbolFromSvgOpenerProvider),
        isA<ImportSymbolFromSvgOpener>(),
      );
      expect(
        c.read(editSymbolForCurrentInstanceOpenerProvider),
        isA<EditSymbolForCurrentInstanceOpener>(),
      );
      expect(
        c.read(removeSymbolForCurrentInstanceOpenerProvider),
        isA<RemoveSymbolForCurrentInstanceOpener>(),
      );
    },
  );
}
