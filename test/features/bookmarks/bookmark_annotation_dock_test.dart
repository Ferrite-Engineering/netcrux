// The Bookmarks and Annotations panels dock as right-dock tabs
// (netcrux#17). They used to open as modal dialogs over the schematic,
// hiding the design they are about.
//
// The host mirrors production's topology: a root container, a workspace with
// one open tab whose container is built from `netcruxTabOverridesFactory`, the
// tab's scope
// holding a stand-in canvas beside the real `NetcruxRightDock`, and the
// openers driven from a context OUTSIDE that scope, where the menu bar,
// command palette and shortcut dispatch run.
import 'dart:io';

import 'package:crux_workspace/crux_workspace.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/models/analysis/analysis_panel_kind.dart';
import 'package:netcrux/domain/models/annotation.dart';
import 'package:netcrux/domain/models/bookmark.dart';
import 'package:netcrux/domain/models/bookmark_annotation_target.dart';
import 'package:netcrux/domain/models/netlist/netlist_model.dart';
import 'package:netcrux/domain/models/selection/selected_element.dart';
import 'package:netcrux/domain/models/workspace/netcrux_tab_payload.dart';
import 'package:netcrux/features/bookmarks/services/bookmark_annotation_actions.dart';
import 'package:netcrux/features/bookmarks/services/bookmark_annotation_openers.dart';
import 'package:netcrux/features/bookmarks/widgets/annotations_panel.dart';
import 'package:netcrux/features/bookmarks/widgets/bookmarks_panel.dart';
import 'package:netcrux/features/hierarchy/providers/hierarchy_tree_notifier.dart';
import 'package:netcrux/features/viewer/providers/analysis_dock_provider.dart';
import 'package:netcrux/features/viewer/providers/right_dock_provider.dart';
import 'package:netcrux/features/viewer/providers/selected_element_notifier.dart';
import 'package:netcrux/features/viewer/widgets/bookmark_annotation_menu_entries.dart';
import 'package:netcrux/features/workspace/widgets/netcrux_docks.dart';
import 'package:netcrux/l10n/generated/app_localizations.dart';
import 'package:netcrux/services/session/bookmark_annotation_store_provider.dart';
import 'package:netcrux/services/workspace/netcrux_pane_overrides.dart';
import 'package:netcrux/services/workspace/netcrux_tab_overrides.dart';
import 'package:netcrux/services/workspace/netcrux_workspace_codec.dart';
import 'package:netcrux/services/workspace/netcrux_workspace_notifier.dart';
import 'package:netcrux/services/yosys/yosys_json_parser.dart';
import 'package:netcrux/shared/widgets/workspace_managers_scope.dart';

import '../../helpers/telemetry_test_overrides.dart';

const List<Locale> _locales = <Locale>[
  Locale('en'),
  Locale('zh', 'CN'),
  Locale('zh'),
  Locale('ja'),
  Locale('ko'),
];

/// `top` instantiates `u_cpu` (module `cpu`, cells `u_alu` and `pc_reg`),
/// and has a `dma_reg` cell of its own.
NetlistModel _seed() => const YosysJsonParser().parse(
  File(
    'test/fixtures/netlist/design_seed/generated/design_seed.netlist.json',
  ).readAsStringSync(),
);

class _Host {
  _Host({
    required this.context,
    required this.root,
    required this.tab,
    required this.canvasRef,
    required this.canvasContext,
  });

  /// A context outside the tab scope: where menu / palette dispatch runs.
  final BuildContext context;
  final ProviderContainer root;
  final ProviderContainer tab;

  /// The tab-scoped ref the schematic context menu builds its entries with.
  final WidgetRef canvasRef;
  final BuildContext canvasContext;
}

Future<_Host> _pumpHost(
  WidgetTester tester, {
  Locale locale = const Locale('en'),
}) async {
  await tester.binding.setSurfaceSize(const Size(1400, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final root = ProviderContainer(
    overrides: <Override>[
      ...netcruxTelemetryTestOverrides(),
      netcruxWorkspaceProvider.overrideWith(
        () => NetcruxWorkspaceNotifier(
          service: WorkspaceService<NetcruxTabPayload>(
            codec: const NetcruxWorkspaceCodec(),
            directoryFactory: () async =>
                Directory.systemTemp.createTempSync('netcrux_notes_dock_'),
            logger: (_) {},
          ),
          autoSaveDebounce: const Duration(milliseconds: 50),
          restoreGate: () async => true,
        ),
      ),
    ],
  );
  addTearDown(root.dispose);
  final tabs = TabContainerManager(
    rootContainer: root,
    overridesFactory: netcruxTabOverridesFactory,
  );
  addTearDown(tabs.dispose);
  final panes = PaneContainerManager(
    rootContainer: root,
    overridesFactory: netcruxPaneOverridesFactory,
  );
  addTearDown(panes.dispose);
  await root.read(netcruxWorkspaceProvider.future);
  await root
      .read(netcruxWorkspaceProvider.notifier)
      .openTab(displayName: 'notes host', payload: NetcruxTabPayload.empty);
  final tab = tabs.containerFor(
    root.read(netcruxWorkspaceProvider).value!.activeTabId!,
  );
  tab.read(hierarchyTreeProvider.notifier).setModel(_seed());

  late BuildContext ctx;
  late WidgetRef canvasRef;
  late BuildContext canvasContext;
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: root,
      child: WorkspaceManagersScope(
        tabContainerManager: tabs,
        paneContainerManager: panes,
        child: MaterialApp(
          locale: locale,
          localizationsDelegates: const <LocalizationsDelegate<Object?>>[
            L10N.delegate,
            L10N.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: _locales,
          home: Scaffold(
            body: Row(
              children: <Widget>[
                Builder(
                  builder: (innerContext) {
                    ctx = innerContext;
                    return const SizedBox.shrink();
                  },
                ),
                Expanded(
                  child: UncontrolledProviderScope(
                    container: tab,
                    child: Row(
                      children: <Widget>[
                        Expanded(
                          child: Consumer(
                            builder: (context, ref, _) {
                              canvasRef = ref;
                              canvasContext = context;
                              final primary = ref
                                  .watch(selectedElementProvider)
                                  .primary;
                              return Center(child: Text('selected: $primary'));
                            },
                          ),
                        ),
                        const SizedBox(width: 420, child: NetcruxRightDock()),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return _Host(
    context: ctx,
    root: root,
    tab: tab,
    canvasRef: canvasRef,
    canvasContext: canvasContext,
  );
}

Finder _docked(Type panel) => find.descendant(
  of: find.byType(NetcruxRightDock),
  matching: find.byType(panel),
);

const Key _bookmarksTab = ValueKey<String>('cruxDockTab-analysis:bookmarks');
const Key _annotationsTab = ValueKey<String>(
  'cruxDockTab-analysis:annotations',
);

const Bookmark _pcReg = Bookmark(
  id: 'bm-1',
  name: 'Program counter',
  targetKind: BookmarkTargetKind.cell,
  targetId: 'pc_reg',
  createdAtMillis: 1,
  note: 'Check the reset value',
  moduleName: 'cpu',
);

const Bookmark _dma = Bookmark(
  id: 'bm-2',
  name: 'DMA register',
  targetKind: BookmarkTargetKind.cell,
  targetId: 'dma_reg',
  createdAtMillis: 2,
  moduleName: 'top',
);

Annotation _note(String id, String targetId, {String? moduleName}) =>
    Annotation(
      id: id,
      targetKind: BookmarkTargetKind.cell,
      targetId: targetId,
      body: 'Note on $targetId',
      createdAtMillis: 1,
      updatedAtMillis: 1,
      moduleName: moduleName,
    );

void main() {
  group('the Bookmarks and Annotations panels dock', () {
    for (final (name, open, panel, tabKey, kind)
        in <
          (
            String,
            void Function(BuildContext),
            Type,
            Key,
            AnalysisPanelKind,
          )
        >[
          (
            'Bookmarks',
            openBookmarksPanel,
            BookmarksPanel,
            _bookmarksTab,
            AnalysisPanelKind.bookmarks,
          ),
          (
            'Annotations',
            openAnnotationsPanel,
            AnnotationsPanel,
            _annotationsTab,
            AnalysisPanelKind.annotations,
          ),
        ]) {
      testWidgets('Show $name Panel opens the $name tab, not a dialog', (
        tester,
      ) async {
        final host = await _pumpHost(tester);
        open(host.context);
        await tester.pumpAndSettle();

        expect(host.root.read(analysisDockProvider), contains(kind));
        expect(find.byKey(tabKey), findsOneWidget);
        expect(_docked(panel), findsOneWidget);
        expect(find.byType(Dialog), findsNothing);
        expect(tester.takeException(), isNull);
      });

      testWidgets('Show $name Panel focuses the tab when it is behind', (
        tester,
      ) async {
        final host = await _pumpHost(tester);
        open(host.context);
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const ValueKey<String>('cruxDockTab-inspector')),
        );
        await tester.pumpAndSettle();
        expect(_docked(panel), findsNothing);

        open(host.context);
        await tester.pumpAndSettle();
        expect(host.root.read(analysisDockProvider), contains(kind));
        expect(_docked(panel), findsOneWidget);
      });

      testWidgets('Show $name Panel again closes the tab on screen', (
        tester,
      ) async {
        final host = await _pumpHost(tester);
        open(host.context);
        await tester.pumpAndSettle();
        open(host.context);
        await tester.pumpAndSettle();
        expect(host.root.read(analysisDockProvider), isNot(contains(kind)));
        expect(find.byKey(tabKey), findsNothing);
      });

      testWidgets("the $name tab's x closes it", (tester) async {
        final host = await _pumpHost(tester);
        open(host.context);
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(ValueKey<String>('cruxDockClose-analysis:${kind.name}')),
        );
        await tester.pumpAndSettle();
        expect(host.root.read(analysisDockProvider), isEmpty);
        expect(_docked(panel), findsNothing);
      });
    }

    for (final locale in _locales) {
      testWidgets('both tabs render in ${locale.toLanguageTag()}', (
        tester,
      ) async {
        final host = await _pumpHost(tester, locale: locale);
        host.tab.read(bookmarkAnnotationStoreProvider)
          ..addBookmark(_pcReg)
          ..addAnnotation(_note('an-1', 'pc_reg', moduleName: 'cpu'));
        openBookmarksPanel(host.context);
        openAnnotationsPanel(host.context);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.byKey(_bookmarksTab), findsOneWidget);
        expect(find.byKey(_annotationsTab), findsOneWidget);
      });
    }
  });

  group('the Bookmarks list', () {
    Future<_Host> pumpWithBookmarks(WidgetTester tester) async {
      final host = await _pumpHost(tester);
      host.tab.read(bookmarkAnnotationStoreProvider)
        ..addBookmark(_pcReg)
        ..addBookmark(_dma);
      openBookmarksPanel(host.context);
      await tester.pumpAndSettle();
      return host;
    }

    testWidgets('shows each name, target kind and id', (tester) async {
      await pumpWithBookmarks(tester);
      expect(find.text('Program counter'), findsOneWidget);
      expect(find.text('Cell · pc_reg'), findsOneWidget);
      expect(find.text('DMA register'), findsOneWidget);
      expect(find.text('Cell · dma_reg'), findsOneWidget);
    });

    testWidgets('marks only the rows that have a note', (tester) async {
      await pumpWithBookmarks(tester);
      expect(
        find.byKey(const ValueKey<String>('bookmarkNoteMarker-bm-1')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('bookmarkNoteMarker-bm-2')),
        findsNothing,
      );
    });

    testWidgets('hovering a row shows its note in a tooltip', (tester) async {
      await pumpWithBookmarks(tester);
      expect(find.text('Check the reset value'), findsNothing);
      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      addTearDown(gesture.removePointer);
      await gesture.addPointer(location: Offset.zero);
      await gesture.moveTo(
        tester.getCenter(
          find.byKey(const ValueKey<String>('bookmarkRow-bm-1')),
        ),
      );
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Check the reset value'), findsOneWidget);
      await gesture.moveTo(Offset.zero);
      await tester.pumpAndSettle();
    });

    testWidgets('a screen reader reads the name, the element and the note', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await pumpWithBookmarks(tester);
      expect(
        find.bySemanticsLabel(
          'Program counter, Cell pc_reg. Note: Check the reset value',
        ),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel('DMA register, Cell dma_reg'),
        findsOneWidget,
      );
      // One name per row: the tooltip adds no second label.
      expect(find.bySemanticsLabel('Check the reset value'), findsNothing);
      handle.dispose();
    });

    testWidgets('a row takes keyboard focus and Enter reveals it', (
      tester,
    ) async {
      final host = await pumpWithBookmarks(tester);
      final row = find.byKey(const ValueKey<String>('bookmarkRow-bm-1'));
      bool focusInRow() {
        final focused = FocusManager.instance.primaryFocus?.context;
        if (focused == null) return false;
        final rowElement = tester.element(row);
        if (identical(focused, rowElement)) return true;
        var inside = false;
        focused.visitAncestorElements((ancestor) {
          if (identical(ancestor, rowElement)) {
            inside = true;
            return false;
          }
          return true;
        });
        return inside;
      }

      // Tab from wherever focus starts until it lands on the row.
      for (var i = 0; i < 40 && !focusInRow(); i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
      }
      expect(focusInRow(), isTrue, reason: 'the row is a Tab stop');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(
        host.tab.read(selectedElementProvider).primary,
        const SelectedElement.cell(cellId: 'pc_reg'),
      );
    });

    testWidgets('clicking a row selects and reveals the element in its '
        'scope', (tester) async {
      final host = await pumpWithBookmarks(tester);
      expect(host.tab.read(hierarchyTreeProvider).selected?.moduleName, 'top');

      await tester.tap(find.byKey(const ValueKey<String>('bookmarkRow-bm-1')));
      await tester.pumpAndSettle();

      expect(host.tab.read(hierarchyTreeProvider).selected?.moduleName, 'cpu');
      expect(
        host.tab.read(selectedElementProvider).primary,
        const SelectedElement.cell(cellId: 'pc_reg'),
      );
      expect(
        find.text(
          'selected: ${host.tab.read(selectedElementProvider).primary}',
        ),
        findsOneWidget,
      );
    });

    testWidgets('a bookmark whose element is gone says so', (tester) async {
      final host = await _pumpHost(tester);
      host.tab
          .read(bookmarkAnnotationStoreProvider)
          .addBookmark(
            const Bookmark(
              id: 'bm-x',
              name: 'Renamed away',
              targetKind: BookmarkTargetKind.cell,
              targetId: 'u_gone',
              createdAtMillis: 1,
            ),
          );
      openBookmarksPanel(host.context);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey<String>('bookmarkRow-bm-x')));
      await tester.pump();
      expect(find.text('Renamed away is not in this design.'), findsOneWidget);
      expect(host.tab.read(selectedElementProvider).isEmpty, isTrue);
      await tester.pumpAndSettle();
    });
  });

  group('Show Annotation opens the Annotations tab at the note', () {
    testWidgets('the context-menu entry appears only on an annotated element', (
      tester,
    ) async {
      final host = await _pumpHost(tester);
      host.tab
          .read(bookmarkAnnotationStoreProvider)
          .addAnnotation(
            _note('an-1', 'dma_reg', moduleName: 'top'),
          );
      List<String> labels(SelectedElement target) => <String>[
        for (final entry in buildBookmarkAnnotationMenuEntries(
          host.canvasRef,
          target,
        ))
          entry.label,
      ];
      expect(
        labels(const SelectedElement.cell(cellId: 'dma_reg')),
        contains('Show Annotation'),
      );
      expect(
        labels(const SelectedElement.cell(cellId: 'u_cpu')),
        isNot(contains('Show Annotation')),
      );
    });

    testWidgets('opening it docks the tab and asks for that note', (
      tester,
    ) async {
      final host = await _pumpHost(tester);
      final store = host.tab.read(bookmarkAnnotationStoreProvider);
      for (var i = 0; i < 40; i++) {
        store.addAnnotation(_note('an-$i', 'cell_$i', moduleName: 'top'));
      }
      store.addAnnotation(_note('an-target', 'dma_reg', moduleName: 'top'));

      final entry = buildBookmarkAnnotationMenuEntries(
        host.canvasRef,
        const SelectedElement.cell(cellId: 'dma_reg'),
      ).singleWhere((e) => e.label == 'Show Annotation');
      await entry.onTap(host.canvasContext, host.canvasRef);
      await tester.pump();
      await tester.pump();

      expect(
        host.root.read(analysisDockProvider),
        contains(AnalysisPanelKind.annotations),
      );
      expect(
        host.root.read(rightDockTabProvider),
        analysisDockTabId(AnalysisPanelKind.annotations),
      );
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      // The last of 41 rows is scrolled into view and flashing.
      expect(find.text('Note on dma_reg').hitTestable(), findsOneWidget);
      final flash = tester.widget<AnimatedContainer>(
        find.byKey(const ValueKey<String>('annotationRow-an-target')),
      );
      expect((flash.decoration! as BoxDecoration).color!.a, greaterThan(0));
      await tester.pumpAndSettle();
    });

    testWidgets('the badge opener with the panel closed reveals on mount', (
      tester,
    ) async {
      final host = await _pumpHost(tester);
      host.tab
          .read(bookmarkAnnotationStoreProvider)
          .addAnnotation(
            _note('an-1', 'dma_reg', moduleName: 'top'),
          );
      host.root.read(showAnnotationForTargetOpenerProvider)(
        host.canvasContext,
        host.canvasRef,
        const BookmarkAnnotationTarget(
          kind: BookmarkTargetKind.cell,
          targetId: 'dma_reg',
        ),
      );
      await tester.pumpAndSettle();
      expect(_docked(AnnotationsPanel), findsOneWidget);
      expect(find.text('Note on dma_reg'), findsOneWidget);
    });
  });
}
