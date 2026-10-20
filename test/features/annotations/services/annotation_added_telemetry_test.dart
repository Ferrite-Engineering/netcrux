// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_dock/crux_dock.dart';
import 'package:crux_telemetry/crux_telemetry.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/models/annotation_target.dart';
import 'package:netcrux/domain/models/layout/bounding_box.dart';
import 'package:netcrux/domain/models/layout/edge_route.dart';
import 'package:netcrux/domain/models/layout/netlist_layout.dart';
import 'package:netcrux/domain/models/layout/node_position.dart';
import 'package:netcrux/domain/models/schematic/cell_kind.dart';
import 'package:netcrux/domain/models/schematic/laid_out_graph.dart';
import 'package:netcrux/domain/models/schematic/schematic_graph.dart';
import 'package:netcrux/features/annotations/providers/annotation_drafts_provider.dart';
import 'package:netcrux/features/annotations/services/annotation_actions.dart';
import 'package:netcrux/features/inspector/widgets/inspector_panel.dart';
import 'package:netcrux/features/project/providers/current_laid_out_graph_provider.dart';
import 'package:netcrux/l10n/generated/app_localizations.dart';
import 'package:netcrux/services/telemetry/annotation_telemetry.dart';
import 'package:netcrux/services/telemetry/telemetry_event_catalog.dart';

class _RecordingTelemetryService implements TelemetryService {
  final List<TelemetryEvent> events = <TelemetryEvent>[];

  @override
  void record(TelemetryEvent event) => events.add(event);

  Iterable<TelemetryEvent> all(String name) =>
      events.where((e) => e.name == name);
}

/// Fails unless [event] is in the shared catalog and every property it carries
/// is declared there with a value from the declared vocabulary.
void _assertInCatalog(TelemetryEvent event) {
  final entry = kNetcruxEventCatalog.firstWhere(
    (e) => e.name == event.name,
    orElse: () => throw StateError('${event.name} is not in the catalog'),
  );
  event.properties.forEach((key, value) {
    expect(entry.propertyKeys, contains(key));
    if (entry.enumeratedValues.containsKey(key)) {
      expect(
        entry.enumeratedValues[key],
        contains(value),
        reason: '${event.name}.$key = "$value" is outside the catalog set',
      );
    }
  });
}

const _graph = LaidOutGraph(
  graph: SchematicGraph(
    moduleName: 'top',
    cells: <SchematicCell>[
      SchematicCell(
        id: 'u_alu',
        kind: CellKind.generic,
        type: 'alu',
        ports: [],
      ),
    ],
    boundaryPorts: <SchematicBoundaryPort>[],
    edges: <SchematicEdge>[],
  ),
  layout: NetlistLayout(
    nodes: <NodePosition>[],
    edges: <EdgeRoute>[],
    bounds: BoundingBox(x: 0, y: 0, width: 0, height: 0),
  ),
);

void main() {
  late _RecordingTelemetryService telemetry;

  setUp(() => telemetry = _RecordingTelemetryService());

  /// The Inspector in a tab-like scope; returns a context and ref inside it,
  /// as the schematic context menu has.
  Future<(BuildContext, WidgetRef)> pumpHost(WidgetTester tester) async {
    late BuildContext ctx;
    late WidgetRef wref;
    await tester.binding.setSurfaceSize(const Size(800, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          telemetryServiceProvider.overrideWithValue(telemetry),
          currentLaidOutGraphProvider.overrideWith((ref) async => _graph),
        ],
        child: MaterialApp(
          localizationsDelegates: L10N.localizationsDelegates,
          supportedLocales: L10N.supportedLocales,
          home: Consumer(
            builder: (context, ref, _) {
              wref = ref;
              ctx = context;
              return const Scaffold(
                body: SizedBox(width: 420, child: InspectorPanel()),
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return (ctx, wref);
  }

  const target = AnnotationTarget(
    kind: AnnotationTargetKind.cell,
    targetId: 'u_alu',
  );
  final key = newAnnotationDraftKey(AnnotationTargetKind.cell, 'u_alu', null);
  final title = find.byKey(ValueKey<String>('annotationTitleField-$key'));
  final body = find.byKey(ValueKey<String>('annotationBodyField-$key'));
  final apply = find.descendant(
    of: find.byType(CruxInspectorApplyBar),
    matching: find.byType(FilledButton),
  );

  group('annotation.added', () {
    testWidgets('saving a titled annotation records the bare event', (
      tester,
    ) async {
      final (ctx, ref) = await pumpHost(tester);

      openAddAnnotationDialog(ctx, ref, target: target);
      await tester.pumpAndSettle();
      await tester.enterText(title, 'my marker');
      await tester.pumpAndSettle();
      await tester.tap(apply);
      await tester.pumpAndSettle();

      final event = telemetry.all('annotation.added').single;
      expect(event.properties, isEmpty);
      // The title the user typed and the element it anchors to are theirs.
      expect(event.toString(), isNot(contains('my marker')));
      expect(event.toString(), isNot(contains('u_alu')));
      _assertInCatalog(event);
    });

    testWidgets('saving an annotation body records nothing of the text', (
      tester,
    ) async {
      final (ctx, ref) = await pumpHost(tester);

      openAddAnnotationDialog(ctx, ref, target: target);
      await tester.pumpAndSettle();
      await tester.enterText(body, 'a private note');
      await tester.pumpAndSettle();
      await tester.tap(apply);
      await tester.pumpAndSettle();

      final event = telemetry.all('annotation.added').single;
      expect(event.properties, isEmpty);
      expect(event.toString(), isNot(contains('a private note')));
      _assertInCatalog(event);
    });

    testWidgets('discarding the new annotation records nothing', (
      tester,
    ) async {
      final l10n = await L10N.delegate.load(const Locale('en'));
      final (ctx, ref) = await pumpHost(tester);

      openAddAnnotationDialog(ctx, ref, target: target);
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.annotationUnsavedChangesDiscard));
      await tester.pumpAndSettle();

      expect(telemetry.all('annotation.added'), isEmpty);
    });

    test('the catalog declares annotation.added with no properties', () {
      final entry = kNetcruxEventCatalog.firstWhere(
        (e) => e.name == 'annotation.added',
      );
      expect(entry.propertyKeys, isEmpty);
    });

    test('recordAnnotationAdded writes the bare event', () {
      recordAnnotationAdded(telemetry);
      expect(telemetry.all('annotation.added').single.properties, isEmpty);
    });
  });
}
