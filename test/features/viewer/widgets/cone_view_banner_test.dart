// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_ide_layout/crux_ide_layout.dart';
import 'package:crux_license/crux_license.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/core/providers/pro_overlay_installed_provider.dart';
import 'package:netcrux/domain/interfaces/cone_of_influence_service.dart';
import 'package:netcrux/domain/interfaces/transitive_cone_resolver.dart';
import 'package:netcrux/domain/models/layout/bounding_box.dart';
import 'package:netcrux/domain/models/layout/edge_route.dart';
import 'package:netcrux/domain/models/layout/netlist_layout.dart';
import 'package:netcrux/domain/models/layout/node_position.dart';
import 'package:netcrux/domain/models/netlist/hierarchy_node.dart';
import 'package:netcrux/domain/models/schematic/cell_kind.dart';
import 'package:netcrux/domain/models/schematic/laid_out_graph.dart';
import 'package:netcrux/domain/models/schematic/schematic_graph.dart';
import 'package:netcrux/domain/models/selection/selected_element.dart';
import 'package:netcrux/domain/models/trace/cone_view.dart';
import 'package:netcrux/domain/models/trace/trace_overlay.dart';
import 'package:netcrux/features/project/providers/current_laid_out_graph_provider.dart';
import 'package:netcrux/features/viewer/providers/cone_view_notifier.dart';
import 'package:netcrux/features/viewer/providers/reveal_request_notifier.dart';
import 'package:netcrux/features/viewer/widgets/cone_view_banner.dart';
import 'package:netcrux/l10n/generated/app_localizations.dart';
import 'package:netcrux/services/schematic/transitive_cone_resolver_provider.dart';

import '../../../helpers/telemetry_test_overrides.dart';

const _scope = HierarchyNode(path: <String>[], moduleName: 'top');
const _request = ConeViewRequest(
  scope: _scope,
  root: SelectedElement.cell(cellId: 'u_add'),
);

LaidOutGraph _laidOut(ConeViewRequest? cone) => LaidOutGraph(
  graph: const SchematicGraph(
    moduleName: 'top',
    cells: <SchematicCell>[
      SchematicCell(
        id: 'u_add',
        kind: CellKind.generic,
        type: r'$add',
        ports: <SchematicPort>[],
      ),
      SchematicCell(
        id: 'u_mux',
        kind: CellKind.generic,
        type: r'$mux',
        ports: <SchematicPort>[],
      ),
    ],
    boundaryPorts: <SchematicBoundaryPort>[],
    edges: <SchematicEdge>[],
  ),
  layout: const NetlistLayout(
    nodes: <NodePosition>[
      NodePosition(
        id: 'u_add',
        bounds: BoundingBox(x: 0, y: 0, width: 10, height: 10),
      ),
    ],
    edges: <EdgeRoute>[],
    bounds: BoundingBox(x: 0, y: 0, width: 10, height: 10),
  ),
  cone: cone == null
      ? null
      : ConeViewExtent(request: cone, scopeCellCount: 16384),
);

class _Resolver implements TransitiveConeResolver {
  @override
  Future<TraceOverlay> resolve(
    SchematicGraph graph,
    SelectedElement root,
    ConeOfInfluenceMode mode,
  ) async => TraceOverlay.empty;
}

Future<ProviderContainer> _pump(
  WidgetTester tester, {
  ConeViewRequest? cone = _request,
  List<Override> overrides = const <Override>[],
  Locale locale = const Locale('en'),
}) async {
  final container = ProviderContainer(
    overrides: <Override>[
      ...netcruxTelemetryTestOverrides(),
      currentLaidOutGraphProvider.overrideWith((ref) async => _laidOut(cone)),
      ...overrides,
    ],
  );
  addTearDown(container.dispose);
  if (cone != null) container.read(coneViewProvider.notifier).show(cone);
  await container.read(currentLaidOutGraphProvider.future);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        locale: locale,
        localizationsDelegates: L10N.localizationsDelegates,
        supportedLocales: L10N.supportedLocales,
        home: const Scaffold(body: ConeViewBanner()),
      ),
    ),
  );
  await tester.pump();
  return container;
}

void main() {
  testWidgets('renders nothing for a whole-scope layout', (tester) async {
    await _pump(tester, cone: null);
    expect(find.byType(CruxSegmentedControl<ConeViewDirection>), findsNothing);
    expect(find.text('Show Whole Scope'), findsNothing);
  });

  testWidgets('describes the cone against the scope and announces it', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await _pump(tester);
    expect(find.text('Cone view of u_add: 2 of 16384 cells'), findsOneWidget);
    expect(find.text('Show Whole Scope'), findsOneWidget);
    expect(find.text('2 levels'), findsOneWidget);
    expect(find.text('Fan-in'), findsOneWidget);
    expect(find.text('Fan-in and fan-out'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('choosing a direction re-lays the cone that way', (
    tester,
  ) async {
    final container = await _pump(tester);
    await tester.tap(find.text('Fan-in and fan-out'));
    await tester.pump();
    expect(
      container.read(coneViewProvider)?.direction,
      ConeViewDirection.fanInAndFanOut,
    );
  });

  testWidgets('choosing a depth re-lays the cone that deep', (tester) async {
    final container = await _pump(tester);
    await tester.tap(find.text('2 levels'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('4 levels').last);
    await tester.pumpAndSettle();
    expect(container.read(coneViewProvider)?.depth, 4);
  });

  testWidgets('All levels carries the Pro suffix and is gated', (
    tester,
  ) async {
    final container = await _pump(
      tester,
      overrides: <Override>[
        betaPeriodProvider.overrideWithValue(false),
        licenseTierProvider.overrideWith((_) => LicenseTier.openCore),
        proOverlayInstalledProvider.overrideWithValue(true),
        transitiveConeResolverProvider.overrideWithValue(_Resolver()),
      ],
    );
    await tester.tap(find.text('2 levels'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('All levels (PRO)'));
    await tester.pumpAndSettle();
    expect(container.read(coneViewProvider)?.depth, 2);
    expect(find.byType(CruxUpgradeDialog), findsOneWidget);
  });

  testWidgets('All levels at Pro lays out the whole cone', (tester) async {
    final container = await _pump(
      tester,
      overrides: <Override>[
        betaPeriodProvider.overrideWithValue(false),
        licenseTierProvider.overrideWith((_) => LicenseTier.pro),
        proOverlayInstalledProvider.overrideWithValue(true),
        transitiveConeResolverProvider.overrideWithValue(_Resolver()),
      ],
    );
    await tester.tap(find.text('2 levels'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('All levels (PRO)'));
    await tester.pumpAndSettle();
    expect(container.read(coneViewProvider)?.isTransitive, isTrue);
  });

  testWidgets('All levels in open core says it requires NetCrux Pro', (
    tester,
  ) async {
    final container = await _pump(
      tester,
      overrides: <Override>[betaPeriodProvider.overrideWithValue(true)],
    );
    await tester.tap(find.text('2 levels'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('All levels (PRO)'));
    await tester.pumpAndSettle();
    expect(container.read(coneViewProvider)?.depth, 2);
    expect(
      find.text('Cone View, All Levels requires NetCrux Pro.'),
      findsOneWidget,
    );
  });

  testWidgets('Show Whole Scope leaves the cone and frames its root', (
    tester,
  ) async {
    final container = await _pump(tester);
    await tester.tap(find.text('Show Whole Scope'));
    await tester.pump();
    expect(container.read(coneViewProvider), isNull);
    expect(container.read(revealRequestProvider), 'u_add');
  });

  testWidgets('each control is a Tab stop', (tester) async {
    await _pump(tester);
    final focused = <FocusNode?>[];
    for (var i = 0; i < 4; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      focused.add(FocusManager.instance.primaryFocus);
    }
    // Direction, depth, Show Whole Scope, then round to the first again.
    expect(focused.take(3).toSet(), hasLength(3));
    expect(focused[3], focused[0]);
  });

  testWidgets('locale sweep', (tester) async {
    for (final locale in const <Locale>[
      Locale('en'),
      Locale('zh', 'CN'),
      Locale('zh'),
      Locale('ja'),
      Locale('ko'),
    ]) {
      await _pump(tester, locale: locale);
      expect(tester.takeException(), isNull, reason: '$locale');
      expect(find.byType(ConeViewBanner), findsOneWidget);
    }
  });
}
