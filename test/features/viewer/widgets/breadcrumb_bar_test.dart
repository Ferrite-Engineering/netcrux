// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/models/netlist/bit_ref.dart';
import 'package:netcrux/domain/models/netlist/cell.dart';
import 'package:netcrux/domain/models/netlist/module.dart';
import 'package:netcrux/domain/models/netlist/net.dart';
import 'package:netcrux/domain/models/netlist/netlist_model.dart';
import 'package:netcrux/domain/models/netlist/port.dart';
import 'package:netcrux/domain/models/netlist/port_direction.dart';
import 'package:netcrux/features/hierarchy/providers/hierarchy_tree_notifier.dart';
import 'package:netcrux/features/viewer/widgets/breadcrumb_bar.dart';
import 'package:netcrux/l10n/generated/app_localizations.dart';
import '../../../helpers/telemetry_test_overrides.dart';

Cell _emptyCell(String name, String type) {
  return Cell(
    name: name,
    type: type,
    parameters: const <String, String>{},
    attributes: const <String, String>{},
    portDirections: const <String, PortDirection>{},
    connections: const <String, List<BitRef>>{},
  );
}

Module _mod(
  String name, {
  required bool top,
  required Map<String, Cell> cells,
}) {
  return Module(
    name: name,
    attributes: top
        ? const <String, String>{'top': '1'}
        : const <String, String>{},
    ports: const <String, Port>{},
    cells: cells,
    nets: const <String, Net>{},
  );
}

NetlistModel _model() {
  return NetlistModel(
    creator: 'test',
    modules: <String, Module>{
      'top': _mod(
        'top',
        top: true,
        cells: <String, Cell>{'u_cpu': _emptyCell('u_cpu', 'cpu')},
      ),
      'cpu': _mod(
        'cpu',
        top: false,
        cells: <String, Cell>{'alu': _emptyCell('alu', 'alu_mod')},
      ),
      'alu_mod': _mod(
        'alu_mod',
        top: false,
        cells: const <String, Cell>{},
      ),
    },
  );
}

Future<void> _pump(
  WidgetTester tester,
  ProviderContainer container, {
  Locale? locale,
}) async {
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        locale: locale ?? const Locale('en'),
        localizationsDelegates: const [
          L10N.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: L10N.supportedLocales,
        home: const Scaffold(body: BreadcrumbBar()),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('BreadcrumbBar', () {
    testWidgets('renders top segment for root scope', (tester) async {
      final container = ProviderContainer(
        overrides: netcruxTelemetryTestOverrides(),
      );
      addTearDown(container.dispose);
      container.read(hierarchyTreeProvider.notifier).setModel(_model());
      await _pump(tester, container);
      expect(find.text('top'), findsOneWidget);
    });

    testWidgets('renders chain after pushInto', (tester) async {
      final container = ProviderContainer(
        overrides: netcruxTelemetryTestOverrides(),
      );
      addTearDown(container.dispose);
      final notifier = container.read(hierarchyTreeProvider.notifier)
        ..setModel(_model())
        ..pushInto('u_cpu')
        ..pushInto('alu');
      await _pump(tester, container);
      expect(notifier.state.selected?.path, ['u_cpu', 'alu']);
      expect(find.text('top'), findsOneWidget);
      expect(find.text('u_cpu'), findsOneWidget);
      expect(find.text('alu'), findsOneWidget);
    });

    testWidgets('clicking a non-current segment pops back to that scope', (
      tester,
    ) async {
      final container = ProviderContainer(
        overrides: netcruxTelemetryTestOverrides(),
      );
      addTearDown(container.dispose);
      final notifier = container.read(hierarchyTreeProvider.notifier)
        ..setModel(_model())
        ..pushInto('u_cpu')
        ..pushInto('alu');
      await _pump(tester, container);
      await tester.tap(find.text('u_cpu'));
      await tester.pumpAndSettle();
      expect(notifier.state.selected?.path, ['u_cpu']);
    });

    testWidgets('renders nothing when no design loaded', (tester) async {
      final container = ProviderContainer(
        overrides: netcruxTelemetryTestOverrides(),
      );
      addTearDown(container.dispose);
      await _pump(tester, container);
      expect(find.byType(TextButton), findsNothing);
    });

    group('locale sweep', () {
      final locales = <Locale>[
        const Locale('en'),
        const Locale('zh', 'CN'),
        const Locale('zh'),
        const Locale('ja'),
        const Locale('ko'),
      ];
      for (final locale in locales) {
        testWidgets('renders in $locale without exceptions', (tester) async {
          final container = ProviderContainer(
            overrides: netcruxTelemetryTestOverrides(),
          );
          addTearDown(container.dispose);
          container.read(hierarchyTreeProvider.notifier).setModel(_model());
          await _pump(tester, container, locale: locale);
          expect(tester.takeException(), isNull);
        });
      }
    });
  });
}
