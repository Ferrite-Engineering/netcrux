// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/models/selection/selected_element.dart';
import 'package:netcrux/features/viewer/services/trace_overlay_controller.dart';
import 'package:netcrux/features/viewer/widgets/schematic_context_menu_controller.dart';
import 'package:netcrux/l10n/generated/app_localizations.dart';

import '../../../helpers/cxp_test_overrides.dart';

class _NoopTraceController extends TraceOverlayController {
  _NoopTraceController(super.container) : super.fromContainer();
}

/// A strip above the app's navigator (as the licence-expiry strip is), and
/// above the canvas a toolbar, all inside a nested navigator like the one each
/// file tab has: the nested overlay's origin is not the root overlay's.
const double _strip = 30;
const double _toolbar = 55;

void main() {
  testWidgets('the schematic menu opens at the click inside a tab navigator', (
    tester,
  ) async {
    final container = ProviderContainer(
      overrides: netcruxCxpOffTestOverrides(),
    );
    addTearDown(container.dispose);
    final trace = _NoopTraceController(container);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          localizationsDelegates: L10N.localizationsDelegates,
          supportedLocales: L10N.supportedLocales,
          builder: (context, navigator) => Column(
            children: <Widget>[
              const SizedBox(height: _strip),
              Expanded(child: navigator!),
            ],
          ),
          home: Scaffold(
            body: Column(
              children: <Widget>[
                const SizedBox(height: _toolbar),
                Expanded(
                  child: Navigator(
                    onGenerateRoute: (_) => MaterialPageRoute<void>(
                      builder: (_) => Consumer(
                        builder: (context, ref, _) => GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onSecondaryTapUp: (details) {
                            unawaited(
                              SchematicContextMenuController(
                                ref: ref,
                                traceController: trace,
                              ).showAt(
                                context: context,
                                globalPosition: details.globalPosition,
                                target: const SelectedElement.cell(
                                  cellId: 'u_cpu',
                                ),
                              ),
                            );
                          },
                          child: const SizedBox.expand(),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    const click = Offset(200, 100);
    // Sanity: the nested overlay really is offset from the root overlay, or
    // this test could not fail.
    final nested = tester.getTopLeft(find.byType(Overlay).last);
    final root = tester.getTopLeft(find.byType(Overlay).first);
    expect(nested.dy - root.dy, _toolbar);

    await tester.tapAt(click, buttons: kSecondaryButton);
    await tester.pumpAndSettle();

    final firstItem = tester.getTopLeft(
      find.byType(PopupMenuItem<Object>).first,
    );
    // The menu's own vertical padding sits above its first item.
    const menuPadding = 8.0;
    expect(firstItem.dx, closeTo(click.dx, 2));
    expect(firstItem.dy - menuPadding, closeTo(click.dy, 2));
  });
}
