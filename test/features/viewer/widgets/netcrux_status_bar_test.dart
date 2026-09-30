// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_status_bar/crux_status_bar.dart';
import 'package:crux_yosys/crux_yosys.dart';
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
import 'package:netcrux/features/project/providers/current_project_provider.dart';
import 'package:netcrux/features/project/providers/loaded_netlist_provider.dart';
import 'package:netcrux/features/viewer/widgets/netcrux_status_bar.dart';
import 'package:netcrux/l10n/generated/app_localizations.dart';
import 'package:netcrux/services/yosys/prebuilt_netlist_loader_provider.dart';
import 'package:netcrux/services/yosys/yosys_availability_provider.dart';

// Injected by each test before building the container; the stub reads it.
NetlistModel? _injectedNetlist;

class _StubLoadedNetlist extends LoadedNetlist {
  @override
  Future<NetlistModel?> build() async => _injectedNetlist;
}

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

/// Top (1 cell) + cpu (1 cell) + alu_mod (0 cells) → 2 cells design-wide.
NetlistModel _twoCellModel() {
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
      'alu_mod': _mod('alu_mod', top: false, cells: const <String, Cell>{}),
    },
  );
}

/// Exactly one cell design-wide → exercises the `=1` plural branch.
NetlistModel _singleCellModel() {
  return NetlistModel(
    creator: 'test',
    modules: <String, Module>{
      'soc': _mod(
        'soc',
        top: true,
        cells: <String, Cell>{'u_only': _emptyCell('u_only', 'leaf')},
      ),
    },
  );
}

Future<ProviderContainer> _pump(
  WidgetTester tester, {
  List<String> sourceFiles = const <String>[],
  bool yosysAvailable = true,
  bool browser = false,
  Locale? locale,
}) async {
  final container = ProviderContainer(
    overrides: [
      if (browser) hdlElaborationSupportedProvider.overrideWithValue(false),
      loadedNetlistProvider.overrideWith(_StubLoadedNetlist.new),
      // The bar now reports a missing engine, so it reads the availability
      // probe — which shells out to `yosys --version` unless stubbed. Real
      // builds hit a warm `keepAlive` result seeded at startup; the test has
      // to say which answer it wants.
      yosysAvailabilityProvider.overrideWith(
        (ref) async => yosysAvailable
            ? const YosysAvailability.available(
                executablePath: 'yosys',
                versionString: 'test stub',
              )
            : const YosysAvailability.notFound(reason: 'test stub'),
      ),
    ],
  );
  addTearDown(container.dispose);
  if (sourceFiles.isNotEmpty) {
    container.read(currentProjectProvider.notifier).setSourceFiles(sourceFiles);
  }
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
        home: const Scaffold(body: NetcruxStatusBar()),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

void main() {
  setUp(() => _injectedNetlist = null);

  group('NetcruxStatusBar', () {
    testWidgets('renders file, top module, and design-wide cell count', (
      tester,
    ) async {
      _injectedNetlist = _twoCellModel();
      await _pump(tester, sourceFiles: <String>['/designs/cpu_top.v']);

      expect(find.text('File: cpu_top.v'), findsOneWidget);
      expect(find.text('Top: top'), findsOneWidget);
      expect(find.text('2 cells'), findsOneWidget);
      // Mounts on the shared cross-suite chrome.
      expect(find.byType(CruxStatusBar), findsOneWidget);
    });

    testWidgets('strips the directory from the file path', (tester) async {
      _injectedNetlist = _twoCellModel();
      await _pump(
        tester,
        sourceFiles: <String>['/Users/dev/proj/sub/picorv32.v'],
      );
      expect(find.text('File: picorv32.v'), findsOneWidget);
    });

    testWidgets('uses the singular "1 cell" plural form', (tester) async {
      _injectedNetlist = _singleCellModel();
      await _pump(tester, sourceFiles: <String>['/d/soc.v']);
      expect(find.text('1 cell'), findsOneWidget);
      expect(find.text('Top: soc'), findsOneWidget);
    });

    testWidgets('shows the no-design placeholder for an empty tab', (
      tester,
    ) async {
      // No injected netlist and no source files: a freshly-opened "+" tab.
      await _pump(tester);
      expect(find.text('No design loaded'), findsOneWidget);
      expect(find.textContaining('File:'), findsNothing);
    });

    testWidgets('omits the file segment but shows design info when only the '
        'netlist is present', (tester) async {
      _injectedNetlist = _twoCellModel();
      await _pump(tester); // netlist loaded, but project has no source files
      expect(find.textContaining('File:'), findsNothing);
      expect(find.text('Top: top'), findsOneWidget);
      expect(find.text('2 cells'), findsOneWidget);
    });

    group('the engine segment', () {
      testWidgets('stays away while Yosys resolves', (tester) async {
        _injectedNetlist = _twoCellModel();
        await _pump(tester, sourceFiles: <String>['/d/soc.v']);
        expect(find.text('Yosys not found'), findsNothing);
      });

      testWidgets('calls out a missing engine', (tester) async {
        // A missing engine is the most common cause of an elaboration that
        // never produces a netlist, and it used to be visible only in
        // Settings and on the Welcome screen — nowhere a user who had
        // already got past both would look.
        _injectedNetlist = _twoCellModel();
        await _pump(
          tester,
          sourceFiles: <String>['/d/soc.v'],
          yosysAvailable: false,
        );
        expect(find.text('Yosys not found'), findsOneWidget);
        // …alongside the design identity, not instead of it.
        expect(find.text('File: soc.v'), findsOneWidget);
      });

      testWidgets('is not news in a build that never elaborates', (
        tester,
      ) async {
        _injectedNetlist = _twoCellModel();
        await _pump(
          tester,
          sourceFiles: <String>['https://example.com/n/soc.json'],
          yosysAvailable: false,
          browser: true,
        );
        expect(find.text('Yosys not found'), findsNothing);
        expect(find.text('File: soc.json'), findsOneWidget);
      });
    });

    testWidgets('names a browser upload by its file name, not its blob id', (
      tester,
    ) async {
      _injectedNetlist = _twoCellModel();
      await _pump(
        tester,
        sourceFiles: <String>[
          'blob:https://app.netcrux.app/5b0c-44e1#my%20design.json',
        ],
        browser: true,
      );
      expect(find.text('File: my design.json'), findsOneWidget);
    });

    group('the idle bar', () {
      testWidgets('renders the empty-canvas variant with no per-tab reads', (
        tester,
      ) async {
        // Mounted by WorkspaceScreen when the workspace has zero tabs, where
        // the real bar has no tab to live in. It must build under a bare
        // ProviderScope — no tab container, no overrides.
        await tester.pumpWidget(
          const ProviderScope(
            child: MaterialApp(
              localizationsDelegates: [
                L10N.delegate,
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
              supportedLocales: L10N.supportedLocales,
              home: Scaffold(
                body: Builder(builder: NetcruxStatusBar.idle),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.byType(CruxStatusBar), findsOneWidget);
        expect(find.text('No design loaded'), findsOneWidget);
      });
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
          _injectedNetlist = _twoCellModel();
          await _pump(
            tester,
            sourceFiles: <String>['/designs/cpu_top.v'],
            locale: locale,
          );
          expect(tester.takeException(), isNull);
        });
      }
    });
  });
}
