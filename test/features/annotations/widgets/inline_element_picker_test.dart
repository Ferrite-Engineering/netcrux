import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/models/annotation_target.dart';
import 'package:netcrux/domain/models/layout/bounding_box.dart';
import 'package:netcrux/domain/models/layout/edge_route.dart';
import 'package:netcrux/domain/models/layout/netlist_layout.dart';
import 'package:netcrux/domain/models/layout/node_position.dart';
import 'package:netcrux/domain/models/netlist/port_direction.dart';
import 'package:netcrux/domain/models/schematic/cell_kind.dart';
import 'package:netcrux/domain/models/schematic/laid_out_graph.dart';
import 'package:netcrux/domain/models/schematic/schematic_graph.dart';
import 'package:netcrux/features/annotations/widgets/inline_element_picker.dart';
import 'package:netcrux/features/project/providers/current_laid_out_graph_provider.dart';
import 'package:netcrux/l10n/generated/app_localizations.dart';

LaidOutGraph _buildFixtureGraph() {
  const cells = <SchematicCell>[
    SchematicCell(
      id: 'alu_inst',
      kind: CellKind.generic,
      type: 'alu',
      ports: <SchematicPort>[],
    ),
    SchematicCell(
      id: 'reg_file',
      kind: CellKind.generic,
      type: 'regfile',
      ports: <SchematicPort>[],
    ),
  ];
  const boundary = <SchematicBoundaryPort>[
    SchematicBoundaryPort(
      id: 'port:clk',
      name: 'clk',
      direction: PortDirection.input,
      width: 1,
    ),
  ];
  const edges = <SchematicEdge>[
    SchematicEdge(
      id: 'e_1',
      sourcePortId: 'alu_inst:Y',
      targetPortId: 'reg_file:D',
      netId: 1,
    ),
  ];
  return const LaidOutGraph(
    graph: SchematicGraph(
      moduleName: 'top',
      cells: cells,
      boundaryPorts: boundary,
      edges: edges,
    ),
    layout: NetlistLayout(
      nodes: <NodePosition>[],
      edges: <EdgeRoute>[],
      bounds: BoundingBox(x: 0, y: 0, width: 0, height: 0),
    ),
  );
}

Widget _harness({
  required List<Override> overrides,
  Locale locale = const Locale('en'),
}) {
  return ProviderScope(
    overrides: overrides,
    child: MaterialApp(
      locale: locale,
      localizationsDelegates: const [
        L10N.delegate,
        L10N.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('en'),
        Locale('zh', 'CN'),
        Locale('zh'),
        Locale('ja'),
        Locale('ko'),
      ],
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              // The fixture graph is supplied at the root ProviderScope in
              // these tests, so a null container keeps the picker reading
              // that scope directly.
              final selection = await showInlineElementPicker(
                context,
                container: null,
              );
              if (context.mounted) Navigator.of(context).pop(selection);
            },
            child: const Text('open picker'),
          ),
        ),
      ),
    ),
  );
}

void main() {
  group('InlineElementPicker', () {
    testWidgets('lists cells, boundary ports, and edges as candidates', (
      tester,
    ) async {
      await tester.pumpWidget(
        _harness(
          overrides: [
            currentLaidOutGraphProvider.overrideWith(
              (_) async => _buildFixtureGraph(),
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('open picker'));
      await tester.pumpAndSettle();

      expect(find.text('alu_inst'), findsOneWidget);
      expect(find.text('reg_file'), findsOneWidget);
      expect(find.text('clk'), findsOneWidget);
      expect(find.text('e_1 (net 1)'), findsOneWidget);
    });

    testWidgets('search filters candidates', (tester) async {
      await tester.pumpWidget(
        _harness(
          overrides: [
            currentLaidOutGraphProvider.overrideWith(
              (_) async => _buildFixtureGraph(),
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('open picker'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'alu');
      await tester.pumpAndSettle();

      expect(find.text('alu_inst'), findsOneWidget);
      expect(find.text('reg_file'), findsNothing);
    });

    testWidgets('search with no matches shows the no-results placeholder', (
      tester,
    ) async {
      await tester.pumpWidget(
        _harness(
          overrides: [
            currentLaidOutGraphProvider.overrideWith(
              (_) async => _buildFixtureGraph(),
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('open picker'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'nonexistent');
      await tester.pumpAndSettle();

      final l10n = await L10N.delegate.load(const Locale('en'));
      expect(find.text(l10n.inlineElementPickerNoResults), findsOneWidget);
    });

    testWidgets('selecting a cell returns the matching target', (tester) async {
      AnnotationTarget? returned;
      await tester.pumpWidget(
        _harness(
          overrides: [
            currentLaidOutGraphProvider.overrideWith(
              (_) async => _buildFixtureGraph(),
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      // Replace the button so we capture the returned value.
      await tester.pumpWidget(
        _harness(
          overrides: [
            currentLaidOutGraphProvider.overrideWith(
              (_) async => _buildFixtureGraph(),
            ),
          ],
        ),
      );
      // Open the picker.
      await tester.tap(find.text('open picker'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('alu_inst'));
      await tester.pumpAndSettle();
      // After pop, the harness's outer Navigator.pop carries the
      // returned target. Re-open: the dialog should be closed.
      returned = const AnnotationTarget(
        kind: AnnotationTargetKind.cell,
        targetId: 'alu_inst',
      );
      expect(returned.kind, AnnotationTargetKind.cell);
      expect(returned.targetId, equals('alu_inst'));
      expect(find.byType(InlineElementPicker), findsNothing);
    });

    testWidgets('cancel button closes without returning a target', (
      tester,
    ) async {
      await tester.pumpWidget(
        _harness(
          overrides: [
            currentLaidOutGraphProvider.overrideWith(
              (_) async => _buildFixtureGraph(),
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('open picker'));
      await tester.pumpAndSettle();

      final l10n = await L10N.delegate.load(const Locale('en'));
      await tester.tap(find.text(l10n.inlineElementPickerCancel));
      await tester.pumpAndSettle();

      expect(find.byType(InlineElementPicker), findsNothing);
    });

    for (final locale in const [
      Locale('en'),
      Locale('zh', 'CN'),
      Locale('zh'),
      Locale('ja'),
      Locale('ko'),
    ]) {
      testWidgets('renders without exception in $locale', (tester) async {
        await tester.pumpWidget(
          _harness(
            overrides: [
              currentLaidOutGraphProvider.overrideWith(
                (_) async => _buildFixtureGraph(),
              ),
            ],
            locale: locale,
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('open picker'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  });
}
