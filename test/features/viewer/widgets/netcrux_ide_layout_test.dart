// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_settings/crux_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/models/analysis/analysis_panel_kind.dart';
import 'package:netcrux/domain/models/app_settings.dart';
import 'package:netcrux/domain/models/panel_layout_state.dart';
import 'package:netcrux/features/settings/providers/app_settings_provider.dart';
import 'package:netcrux/features/viewer/providers/analysis_dock_provider.dart';
import 'package:netcrux/features/viewer/providers/panel_layout_provider.dart';
import 'package:netcrux/features/viewer/providers/right_dock_provider.dart';
import 'package:netcrux/features/viewer/widgets/netcrux_ide_layout.dart';
import 'package:netcrux/l10n/generated/app_localizations.dart';
import 'package:netcrux/services/settings/netcrux_settings_codec.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late SharedPreferences prefs;

  setUp(() async {
    // A real-but-mocked SharedPreferences so the panel-layout notifier's
    // persistence side effect (toggle → AppSettings.save) resolves instead
    // of hanging on an unimplemented platform channel.
    SharedPreferences.setMockInitialValues(<String, Object>{});
    prefs = await SharedPreferences.getInstance();
  });

  Widget harness({
    Locale locale = const Locale('en'),
    PanelLayoutState? seed,
  }) {
    final overrides = [
      settingsServiceProvider.overrideWithValue(
        SettingsService<AppSettings>(
          const NetcruxSettingsCodec(),
          prefsOverride: prefs,
        ),
      ),
      if (seed != null)
        panelLayoutProvider.overrideWith(() => _SeededNotifier(seed)),
    ];
    return ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        locale: locale,
        localizationsDelegates: const [
          L10N.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: L10N.supportedLocales,
        home: const Scaffold(
          body: SizedBox(
            width: 1400,
            height: 800,
            child: NetcruxIdeLayout(
              hierarchyBuilder: _hierarchy,
              centerBuilder: _center,
              inspectorBuilder: _inspector,
              diagnosticsBuilder: _diagnostics,
            ),
          ),
        ),
      ),
    );
  }

  group('NetcruxIdeLayout', () {
    testWidgets('renders without exceptions at default state', (tester) async {
      await tester.pumpWidget(harness());
      await tester.pumpAndSettle();
      expect(find.byType(NetcruxIdeLayout), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'programmatic visibility toggle propagates from provider to layout',
      (tester) async {
        await tester.pumpWidget(harness());
        await tester.pumpAndSettle();
        final element = tester.element(find.byType(NetcruxIdeLayout));
        final container = ProviderScope.containerOf(element);

        // Default: hierarchy visible, inspector + diagnostics collapsed.
        expect(
          container.read(panelLayoutProvider).hierarchyTreeVisible,
          isTrue,
        );

        // Toggle the inspector on and the hierarchy off; the layout must
        // re-sync its IdeController without throwing.
        final notifier = container.read(panelLayoutProvider.notifier);
        await notifier.toggleInspector();
        await notifier.toggleHierarchyTree();
        await tester.pumpAndSettle();

        expect(container.read(panelLayoutProvider).inspectorVisible, isTrue);
        expect(
          container.read(panelLayoutProvider).hierarchyTreeVisible,
          isFalse,
        );
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'opening the analysis dock REVEALS the right region (no forced-visible '
      'special case), and closing it falls back with the region open',
      (tester) async {
        // The dock model: `inspectorVisible` is the region's one visibility
        // flag. `AnalysisDockNotifier.open` reveals — sets the right-dock tab
        // and opens the region through the ordinary flag — and `close`
        // leaves the region open on the Inspector tab, the same VSCode
        // fallback as every other dock in the suite.
        await tester.pumpWidget(
          harness(seed: const PanelLayoutState()),
        );
        await tester.pumpAndSettle();
        final element = tester.element(find.byType(NetcruxIdeLayout));
        final container = ProviderScope.containerOf(element);

        expect(container.read(panelLayoutProvider).inspectorVisible, isFalse);

        container
            .read(analysisDockProvider.notifier)
            .open(AnalysisPanelKind.cdc);
        await tester.pumpAndSettle();
        expect(
          container.read(panelLayoutProvider).inspectorVisible,
          isTrue,
          reason: 'open() reveals through the ordinary region flag',
        );
        expect(
          container.read(effectiveRightDockTabProvider),
          analysisDockTabId(AnalysisPanelKind.cdc),
        );

        container
            .read(analysisDockProvider.notifier)
            .close(AnalysisPanelKind.cdc);
        await tester.pumpAndSettle();
        expect(
          container.read(panelLayoutProvider).inspectorVisible,
          isTrue,
          reason: 'closing an analysis falls back to Inspector, region open',
        );
        expect(
          container.read(effectiveRightDockTabProvider),
          kRightDockTabInspector,
        );
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('honours a seeded initial visibility from the provider', (
      tester,
    ) async {
      await tester.pumpWidget(
        harness(seed: const PanelLayoutState(hierarchyTreeVisible: false)),
      );
      await tester.pumpAndSettle();
      final element = tester.element(find.byType(NetcruxIdeLayout));
      final container = ProviderScope.containerOf(element);
      // The seeded notifier hides every pane; the IdeController is built
      // from the seeded state, so the layout still pumps cleanly.
      expect(container.read(panelLayoutProvider).hierarchyTreeVisible, isFalse);
      expect(tester.takeException(), isNull);
    });

    group('locale sweep', () {
      for (final locale in const [
        Locale('en'),
        Locale('zh', 'CN'),
        Locale('zh'),
        Locale('ja'),
        Locale('ko'),
      ]) {
        testWidgets('renders without exceptions in $locale', (tester) async {
          await tester.pumpWidget(harness(locale: locale));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        });
      }
    });
  });
}

Widget _hierarchy(BuildContext context, double _) =>
    const ColoredBox(color: Color(0xFFAA0000));
Widget _center(BuildContext context, double _) =>
    const ColoredBox(color: Color(0xFF00AA00));
const Widget _inspectorMarker = ColoredBox(color: Color(0xFF0000AA));
Widget _inspector(BuildContext context, double _) => _inspectorMarker;
Widget _diagnostics(BuildContext context, double _) =>
    const ColoredBox(color: Color(0xFFAAAA00));

class _SeededNotifier extends PanelLayoutNotifier {
  _SeededNotifier(this._seed);

  final PanelLayoutState _seed;

  @override
  PanelLayoutState build() => _seed;
}
