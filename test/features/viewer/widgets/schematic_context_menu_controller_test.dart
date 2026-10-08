// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:crux_license/crux_license.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/models/netlist/cell.dart';
import 'package:netcrux/domain/models/netlist/module.dart';
import 'package:netcrux/domain/models/netlist/netlist_model.dart';
import 'package:netcrux/domain/models/selection/selected_element.dart';
import 'package:netcrux/features/hierarchy/providers/hierarchy_tree_notifier.dart';
import 'package:netcrux/features/project/providers/loaded_netlist_provider.dart';
import 'package:netcrux/features/viewer/providers/selected_element_notifier.dart';
import 'package:netcrux/features/viewer/providers/trace_overlay_notifier.dart';
import 'package:netcrux/features/viewer/services/trace_overlay_controller.dart';
import 'package:netcrux/features/viewer/widgets/schematic_context_menu_controller.dart';
import 'package:netcrux/features/viewer/widgets/schematic_context_menu_extension.dart';
import 'package:netcrux/features/viewer/widgets/schematic_context_menu_extensions_provider.dart';
import 'package:netcrux/l10n/generated/app_localizations.dart';
import 'package:netcrux/shared/widgets/netcrux_feature_tier_badge.dart';

/// `top` with one child scope `u_cpu` (module `cpu`) so the hierarchy
/// notifier has a real root to select and pop out of.
NetlistModel _model() {
  Cell cell(String name, String type) => Cell(
    name: name,
    type: type,
    parameters: const {},
    attributes: const {},
    portDirections: const {},
    connections: const {},
  );
  final top = Module(
    name: 'top',
    attributes: const <String, String>{'top': '1'},
    ports: const {},
    cells: <String, Cell>{'u_cpu': cell('u_cpu', 'cpu')},
    nets: const {},
  );
  const cpu = Module(
    name: 'cpu',
    attributes: <String, String>{},
    ports: {},
    cells: {},
    nets: {},
  );
  return NetlistModel(
    creator: 'test',
    modules: <String, Module>{'top': top, 'cpu': cpu},
  );
}

/// Recording stand-in for the trace controller so the menu's fanin /
/// fanout wiring can be asserted without a laid-out graph.
class _RecordingTraceController extends TraceOverlayController {
  _RecordingTraceController(super.container) : super.fromContainer();

  int faninCalls = 0;
  int fanoutCalls = 0;

  @override
  void showFanin() => faninCalls++;

  @override
  void showFanout() => fanoutCalls++;
}

void main() {
  const target = SelectedElement.cell(cellId: 'u_cpu');

  /// Pumps a host and returns the controller, its recording trace stub,
  /// the container, and a context that has a `ScaffoldMessenger` above it.
  Future<
    ({
      SchematicContextMenuController controller,
      _RecordingTraceController trace,
      ProviderContainer container,
      BuildContext context,
    })
  >
  pumpController(
    WidgetTester tester, {
    List<Override> overrides = const [],
    bool withModel = true,
  }) async {
    final container = ProviderContainer(overrides: overrides);
    addTearDown(container.dispose);
    if (withModel) {
      container.read(hierarchyTreeProvider.notifier).setModel(_model());
    }
    final trace = _RecordingTraceController(container);

    late SchematicContextMenuController controller;
    late BuildContext hostContext;
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          localizationsDelegates: L10N.localizationsDelegates,
          supportedLocales: L10N.supportedLocales,
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, _) {
                hostContext = context;
                controller = SchematicContextMenuController(
                  ref: ref,
                  traceController: trace,
                );
                return const SizedBox.expand();
              },
            ),
          ),
        ),
      ),
    );
    return (
      controller: controller,
      trace: trace,
      container: container,
      context: hostContext,
    );
  }

  group('dispatch — trace entries', () {
    testWidgets('traceFanin selects the target then runs the fanin trace', (
      tester,
    ) async {
      final h = await pumpController(tester);

      await h.controller.dispatch(
        context: h.context,
        action: SchematicContextMenuAction.traceFanin,
        target: target,
      );

      expect(h.container.read(selectedElementProvider).primary, target);
      expect(h.trace.faninCalls, 1);
      expect(h.trace.fanoutCalls, 0);
    });

    testWidgets('traceFanout selects the target then runs the fanout trace', (
      tester,
    ) async {
      final h = await pumpController(tester);

      await h.controller.dispatch(
        context: h.context,
        action: SchematicContextMenuAction.traceFanout,
        target: target,
      );

      expect(h.container.read(selectedElementProvider).primary, target);
      expect(h.trace.fanoutCalls, 1);
      expect(h.trace.faninCalls, 0);
    });
  });

  group('dispatch — selection + hierarchy entries', () {
    testWidgets('openInInspector promotes the target to the selection', (
      tester,
    ) async {
      final h = await pumpController(tester);

      await h.controller.dispatch(
        context: h.context,
        action: SchematicContextMenuAction.openInInspector,
        target: target,
      );

      expect(h.container.read(selectedElementProvider).primary, target);
      expect(h.trace.faninCalls, 0);
      expect(h.trace.fanoutCalls, 0);
    });

    testWidgets('findInHierarchy re-selects the active scope', (tester) async {
      final h = await pumpController(tester);
      final rootPath = h.container.read(hierarchyTreeProvider).selected!.path;

      await h.controller.dispatch(
        context: h.context,
        action: SchematicContextMenuAction.findInHierarchy,
        target: target,
      );

      expect(h.container.read(hierarchyTreeProvider).selected?.path, rootPath);
      expect(tester.takeException(), isNull);
    });

    testWidgets('findInHierarchy is a no-op with no scope selected', (
      tester,
    ) async {
      final h = await pumpController(tester, withModel: false);

      await h.controller.dispatch(
        context: h.context,
        action: SchematicContextMenuAction.findInHierarchy,
        target: target,
      );

      expect(h.container.read(hierarchyTreeProvider).selected, isNull);
      expect(tester.takeException(), isNull);
    });
  });

  group('dispatch — copy path', () {
    late List<MethodCall> clipboardCalls;

    setUp(() {
      clipboardCalls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            if (call.method == 'Clipboard.setData') clipboardCalls.add(call);
            return null;
          });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    });

    testWidgets('copies the canonical path and flashes the snackbar', (
      tester,
    ) async {
      final h = await pumpController(
        tester,
        overrides: [
          loadedNetlistProvider.overrideWith(() => _StaticNetlist(_model())),
        ],
      );
      await h.container.read(loadedNetlistProvider.future);
      await tester.pump();

      await h.controller.dispatch(
        context: h.context,
        action: SchematicContextMenuAction.copyPath,
        target: target,
      );
      await tester.pump();

      expect(clipboardCalls, hasLength(1));
      expect(
        (clipboardCalls.single.arguments as Map)['text'],
        'top.u_cpu:cell',
      );
      final l10n = L10N.of(h.context);
      expect(
        find.text(l10n.contextMenuCopyPathSuccess('top.u_cpu:cell')),
        findsOneWidget,
      );
    });

    testWidgets('no scope selected copies nothing', (tester) async {
      final h = await pumpController(
        tester,
        withModel: false,
        overrides: [
          loadedNetlistProvider.overrideWith(() => _StaticNetlist(_model())),
        ],
      );
      await h.container.read(loadedNetlistProvider.future);
      await tester.pump();

      await h.controller.dispatch(
        context: h.context,
        action: SchematicContextMenuAction.copyPath,
        target: target,
      );
      await tester.pump();

      expect(clipboardCalls, isEmpty);
    });

    testWidgets('no loaded model copies nothing', (tester) async {
      final h = await pumpController(
        tester,
        overrides: [
          loadedNetlistProvider.overrideWith(_NoNetlist.new),
        ],
      );
      await h.container.read(loadedNetlistProvider.future);
      await tester.pump();

      await h.controller.dispatch(
        context: h.context,
        action: SchematicContextMenuAction.copyPath,
        target: target,
      );
      await tester.pump();

      expect(clipboardCalls, isEmpty);
    });

    testWidgets('an unresolvable element copies nothing', (tester) async {
      final h = await pumpController(
        tester,
        overrides: [
          loadedNetlistProvider.overrideWith(() => _StaticNetlist(_model())),
        ],
      );
      await h.container.read(loadedNetlistProvider.future);
      await tester.pump();

      await h.controller.dispatch(
        context: h.context,
        action: SchematicContextMenuAction.copyPath,
        // The "none" element has no canonical path.
        target: const SelectedElement.none(),
      );
      await tester.pump();

      expect(clipboardCalls, isEmpty);
    });
  });

  group('showAt', () {
    testWidgets('a none target never opens a menu', (tester) async {
      final h = await pumpController(tester);

      final result = await h.controller.showAt(
        context: h.context,
        globalPosition: const Offset(100, 100),
        target: const SelectedElement.none(),
      );
      await tester.pump();

      expect(result, isNull);
      expect(find.byType(PopupMenuItem<Object>), findsNothing);
    });

    testWidgets('renders the five built-in entries', (tester) async {
      final h = await pumpController(
        tester,
        overrides: [
          schematicContextMenuExtensionsProvider.overrideWithValue(
            const <SchematicContextMenuExtensionBuilder>[],
          ),
        ],
      );

      unawaitedShow(h.controller, h.context);
      await tester.pumpAndSettle();

      final l10n = L10N.of(h.context);
      expect(find.text(l10n.contextMenuCopyPath), findsOneWidget);
      expect(find.text(l10n.contextMenuTraceFanin), findsOneWidget);
      expect(find.text(l10n.contextMenuTraceFanout), findsOneWidget);
      expect(find.text(l10n.contextMenuFindInHierarchy), findsOneWidget);
      expect(find.text(l10n.contextMenuOpenInInspector), findsOneWidget);
      expect(find.byType(PopupMenuDivider), findsNothing);
    });

    testWidgets(
      'open core adds Add Bookmark and Add Annotation below a divider',
      (
        tester,
      ) async {
        final h = await pumpController(tester);

        unawaitedShow(h.controller, h.context);
        await tester.pumpAndSettle();

        final l10n = L10N.of(h.context);
        expect(find.text(l10n.bookmarkMenuAddBookmark), findsOneWidget);
        expect(find.text(l10n.bookmarkMenuAddAnnotation), findsOneWidget);
        expect(find.byType(PopupMenuDivider), findsOneWidget);
        // Free: no tier chip beside either entry.
        expect(find.byType(NetCruxFeatureTierBadge), findsNothing);
      },
    );

    testWidgets('selecting a built-in entry dispatches it', (tester) async {
      final h = await pumpController(tester);

      unawaitedShow(h.controller, h.context);
      await tester.pumpAndSettle();
      await tester.tap(find.text(L10N.of(h.context).contextMenuTraceFanout));
      await tester.pumpAndSettle();

      expect(h.trace.fanoutCalls, 1);
      expect(h.container.read(selectedElementProvider).primary, target);
    });

    testWidgets('extension entries render below a divider and dispatch', (
      tester,
    ) async {
      var taps = 0;
      SelectedElement? seenTarget;
      final h = await pumpController(
        tester,
        overrides: [
          schematicContextMenuExtensionsProvider.overrideWithValue(
            <SchematicContextMenuExtensionBuilder>[
              (ref, element) {
                seenTarget = element;
                return <SchematicContextMenuExtensionEntry>[
                  SchematicContextMenuExtensionEntry(
                    id: 'ext-1',
                    label: 'Cross-probe → wavecrux',
                    onTap: (_, _) async => taps++,
                  ),
                ];
              },
            ],
          ),
        ],
      );

      unawaitedShow(h.controller, h.context);
      await tester.pumpAndSettle();

      expect(seenTarget, target, reason: 'builders receive the clicked target');
      expect(find.byType(PopupMenuDivider), findsOneWidget);
      await tester.tap(find.text('Cross-probe → wavecrux'));
      await tester.pumpAndSettle();

      expect(taps, 1);
      expect(
        h.container.read(selectedElementProvider).isEmpty,
        isTrue,
        reason: 'an extension dispatch must not mutate the built-in selection',
      );
    });

    testWidgets('a tiered extension entry carries the tier chip beside its '
        'label', (tester) async {
      final h = await pumpController(
        tester,
        overrides: [
          schematicContextMenuExtensionsProvider.overrideWithValue(
            <SchematicContextMenuExtensionBuilder>[
              (ref, element) => <SchematicContextMenuExtensionEntry>[
                SchematicContextMenuExtensionEntry(
                  id: 'ext-pro',
                  label: 'Pro entry',
                  requiredTier: LicenseTier.pro,
                  onTap: (_, _) async {},
                ),
                SchematicContextMenuExtensionEntry(
                  id: 'ext-ent',
                  label: 'Enterprise entry',
                  requiredTier: LicenseTier.enterprise,
                  onTap: (_, _) async {},
                ),
                SchematicContextMenuExtensionEntry(
                  id: 'ext-free',
                  label: 'Free entry',
                  onTap: (_, _) async {},
                ),
              ],
            ],
          ),
        ],
      );

      unawaitedShow(h.controller, h.context);
      await tester.pumpAndSettle();

      Finder chipIn(String label) => find.descendant(
        of: find.ancestor(of: find.text(label), matching: find.byType(Row)),
        matching: find.byType(NetCruxFeatureTierBadge),
      );
      expect(
        tester
            .widget<NetCruxFeatureTierBadge>(chipIn('Pro entry'))
            .requiredTier,
        LicenseTier.pro,
      );
      expect(
        tester
            .widget<NetCruxFeatureTierBadge>(chipIn('Enterprise entry'))
            .requiredTier,
        LicenseTier.enterprise,
      );
      expect(find.byType(NetCruxFeatureTierBadge), findsNWidgets(2));
      expect(find.text('PRO'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a disabled extension entry renders its tooltip and cannot '
        'be dispatched', (tester) async {
      var taps = 0;
      final h = await pumpController(
        tester,
        overrides: [
          schematicContextMenuExtensionsProvider.overrideWithValue(
            <SchematicContextMenuExtensionBuilder>[
              (ref, element) => <SchematicContextMenuExtensionEntry>[
                SchematicContextMenuExtensionEntry(
                  id: 'ext-disabled',
                  label: 'Cross-probe → no peers',
                  tooltip: 'No peers connected',
                  enabled: false,
                  onTap: (_, _) async => taps++,
                ),
              ],
            ],
          ),
        ],
      );

      unawaitedShow(h.controller, h.context);
      await tester.pumpAndSettle();

      expect(find.byType(Tooltip), findsWidgets);
      await tester.tap(find.text('Cross-probe → no peers'));
      await tester.pumpAndSettle();

      expect(taps, 0);
    });

    testWidgets('dismissing the menu without a selection returns null', (
      tester,
    ) async {
      final h = await pumpController(tester);

      final pending = h.controller.showAt(
        context: h.context,
        globalPosition: const Offset(100, 100),
        target: target,
      );
      await tester.pumpAndSettle();
      // Tap the barrier outside the menu.
      await tester.tapAt(const Offset(700, 550));
      await tester.pumpAndSettle();

      expect(await pending, isNull);
      expect(h.container.read(traceOverlayProvider).isEmpty, isTrue);
    });

    testWidgets('locale sweep renders every built-in entry', (tester) async {
      for (final locale in const <Locale>[
        Locale('en'),
        Locale('zh', 'CN'),
        Locale('ja'),
        Locale('ko'),
      ]) {
        final container = ProviderContainer(
          overrides: [
            schematicContextMenuExtensionsProvider.overrideWithValue(
              const <SchematicContextMenuExtensionBuilder>[],
            ),
          ],
        );
        addTearDown(container.dispose);
        container.read(hierarchyTreeProvider.notifier).setModel(_model());
        late SchematicContextMenuController controller;
        late BuildContext hostContext;
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              locale: locale,
              localizationsDelegates: L10N.localizationsDelegates,
              supportedLocales: L10N.supportedLocales,
              home: Scaffold(
                body: Consumer(
                  builder: (context, ref, _) {
                    hostContext = context;
                    controller = SchematicContextMenuController(
                      ref: ref,
                      traceController: _RecordingTraceController(container),
                    );
                    return const SizedBox.expand();
                  },
                ),
              ),
            ),
          ),
        );

        unawaitedShow(controller, hostContext);
        await tester.pumpAndSettle();

        expect(find.byType(PopupMenuItem<Object>), findsNWidgets(5));
        expect(tester.takeException(), isNull, reason: 'locale $locale');

        await tester.tapAt(const Offset(700, 550));
        await tester.pumpAndSettle();
      }
    });
  });
}

/// Opens the menu without awaiting it — the future completes only once
/// the user picks an entry or dismisses the overlay.
void unawaitedShow(
  SchematicContextMenuController controller,
  BuildContext context,
) {
  unawaited(
    controller.showAt(
      context: context,
      globalPosition: const Offset(100, 100),
      target: const SelectedElement.cell(cellId: 'u_cpu'),
    ),
  );
}

class _StaticNetlist extends LoadedNetlist {
  _StaticNetlist(this._model);

  final NetlistModel _model;

  @override
  Future<NetlistModel?> build() async => _model;
}

class _NoNetlist extends LoadedNetlist {
  @override
  Future<NetlistModel?> build() async => null;
}
