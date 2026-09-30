// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_toolbar/crux_toolbar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/core/shortcuts/netcrux_action.dart';
import 'package:netcrux/core/shortcuts/netcrux_action_context.dart';
import 'package:netcrux/core/shortcuts/netcrux_action_descriptor.dart';
import 'package:netcrux/core/shortcuts/netcrux_action_descriptors.dart';
import 'package:netcrux/features/viewer/widgets/netcrux_toolbar.dart';
import 'package:netcrux/features/workspace/providers/netcrux_action_context_provider.dart';
import 'package:netcrux/l10n/generated/app_localizations.dart';

/// A design loaded, something selected, split panes — so every descriptor gate
/// the toolbar reads is satisfied and the buttons are live.
const _loaded = NetcruxActionContext(
  hasOpenTab: true,
  hasNetlist: true,
  hasSelection: true,
  hasTraceOverlay: true,
  paneCount: 2,
  tabCountInActivePane: 2,
);

Widget _wrap({
  NetcruxActionContext ctx = _loaded,
  void Function(NetcruxAction)? onAction,
  Locale? locale,
  double width = 1400,
}) => ProviderScope(
  overrides: [netcruxActionContextProvider.overrideWithValue(ctx)],
  child: MaterialApp(
    locale: locale ?? const Locale('en'),
    localizationsDelegates: const [
      L10N.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: L10N.supportedLocales,
    home: Scaffold(
      body: SizedBox(
        width: width,
        child: NetcruxToolbar(onAction: onAction ?? (_) {}),
      ),
    ),
  ),
);

/// Every action the strip currently renders a button for. Split-button
/// siblings do not appear — only the faced variant occupies a slot.
Set<NetcruxAction> _rendered(WidgetTester tester) => tester
    .widgetList<CruxToolbarButton>(find.byType(CruxToolbarButton))
    .map((b) => (b.key! as ValueKey<NetcruxAction>).value)
    .toSet();

IconButton _buttonFor(WidgetTester tester, NetcruxAction a) =>
    tester.widget<IconButton>(
      find.descendant(
        of: find.byKey(ValueKey<NetcruxAction>(a)),
        matching: find.byType(IconButton),
      ),
    );

void main() {
  group('NetcruxToolbar', () {
    testWidgets('renders through the shared CruxToolbar', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(CruxToolbar<NetcruxAction>), findsOneWidget);
    });

    testWidgets('leads with the canonical common block, in suite order', (
      tester,
    ) async {
      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();

      // Open · Save · Close │ Search · Cross-Probe · Settings — the six
      // buttons that mean the same thing in all four products.
      const common = [
        NetcruxAction.openProject,
        NetcruxAction.saveSession,
        NetcruxAction.closeProject,
        NetcruxAction.openSearch,
        NetcruxAction.showCrossProbePanel,
        NetcruxAction.openSettings,
      ];
      final xs = [
        for (final a in common)
          tester.getCenter(find.byKey(ValueKey<NetcruxAction>(a))).dx,
      ];
      expect(
        xs,
        orderedEquals(List<double>.from(xs)..sort()),
        reason: 'the common block must render in the canonical order',
      );

      // Every app-specific button sits to the right of all of them.
      for (final a in [
        NetcruxAction.openSourceFiles,
        NetcruxAction.zoomIn,
        NetcruxAction.jumpToTop,
      ]) {
        expect(
          tester.getCenter(find.byKey(ValueKey<NetcruxAction>(a))).dx,
          greaterThan(xs.last),
          reason: '$a is app-specific and belongs after the section divider',
        );
      }
    });

    testWidgets('every rendered button declares the toolbar surface', (
      tester,
    ) async {
      // The direction the old conformance test did not check: it asserted
      // that descriptor-toolbar actions had buttons, so a button whose
      // descriptor omitted the surface passed silently.
      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();
      for (final action in _rendered(tester)) {
        expect(
          descriptorFor(action).surfaces,
          contains(NetcruxActionSurface.toolbar),
          reason:
              '${action.name} has a toolbar button but its descriptor does '
              'not list NetcruxActionSurface.toolbar',
        );
      }
    });

    testWidgets('every toolbar-surface action is reachable from the strip', (
      tester,
    ) async {
      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();
      final rendered = _rendered(tester);
      // The trace trio shares one grouped slot, so its siblings are reachable
      // through the cluster menu rather than as top-level buttons.
      const inSplitCluster = {
        NetcruxAction.showFanin,
        NetcruxAction.showFanout,
        NetcruxAction.clearOverlay,
      };
      for (final action in NetcruxAction.values) {
        final onToolbar = descriptorFor(
          action,
        ).surfaces.contains(NetcruxActionSurface.toolbar);
        if (!onToolbar) continue;
        expect(
          rendered.contains(action) || inSplitCluster.contains(action),
          isTrue,
          reason:
              '${action.name} declares the toolbar surface but has no button',
        );
      }
    });

    testWidgets('greys buttons whose descriptor gate is unmet', (tester) async {
      await tester.pumpWidget(_wrap(ctx: const NetcruxActionContext()));
      await tester.pumpAndSettle();
      // Open works on the empty canvas; zoom and save need a design.
      expect(
        _buttonFor(tester, NetcruxAction.openProject).onPressed,
        isNotNull,
      );
      expect(_buttonFor(tester, NetcruxAction.zoomIn).onPressed, isNull);
      expect(_buttonFor(tester, NetcruxAction.saveSession).onPressed, isNull);
    });

    testWidgets('dispatches the action for the tapped button', (tester) async {
      final fired = <NetcruxAction>[];
      await tester.pumpWidget(_wrap(onAction: fired.add));
      await tester.pumpAndSettle();
      for (final action in [
        NetcruxAction.openProject,
        NetcruxAction.openSearch,
        NetcruxAction.zoomIn,
        NetcruxAction.openSettings,
      ]) {
        fired.clear();
        await tester.tap(find.byKey(ValueKey<NetcruxAction>(action)));
        await tester.pump();
        expect(fired, [action], reason: 'tapping $action should dispatch it');
      }
    });

    testWidgets('shows the overflow button only when the strip overflows', (
      tester,
    ) async {
      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.more_vert), findsNothing);

      await tester.pumpWidget(_wrap(width: 240));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.more_vert), findsOneWidget);
    });

    testWidgets('groups fan-in / fan-out / clear into one split button', (
      tester,
    ) async {
      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();
      expect(
        find.byType(CruxToolbarSplitButton<NetcruxAction>),
        findsOneWidget,
      );
      final rendered = _rendered(tester);
      expect(rendered, contains(NetcruxAction.showFanin));
      expect(rendered, isNot(contains(NetcruxAction.showFanout)));
    });

    testWidgets('tooltips carry the action label', (tester) async {
      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();
      final l10n = L10N.of(tester.element(find.byType(NetcruxToolbar)));
      // The shared tooltip builder appends the live binding when there is
      // one, so match on the label prefix rather than the whole string.
      final tooltips = tester
          .widgetList<Tooltip>(find.byType(Tooltip))
          .map((t) => t.message ?? '')
          .toList();
      expect(
        tooltips.any(
          (m) => m.startsWith(NetcruxAction.openProject.label(l10n)),
        ),
        isTrue,
      );
      expect(
        tooltips.any((m) => m.startsWith(NetcruxAction.openSearch.label(l10n))),
        isTrue,
      );
    });

    group('locale sweep', () {
      for (final locale in const [
        Locale('en'),
        Locale('zh', 'CN'),
        Locale('zh'),
        Locale('ja'),
        Locale('ko'),
      ]) {
        testWidgets('renders in $locale without exceptions', (tester) async {
          await tester.pumpWidget(_wrap(locale: locale));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          expect(find.byType(CruxToolbar<NetcruxAction>), findsOneWidget);
        });
      }
    });
  });
}
