// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// `tier.gate_hit` on its open-core production seam.
//
// The counter comes out of `WorkspaceActionDispatcher._proActionAllowed` — the
// single guard every Pro/Enterprise action passes through on its way to the
// upgrade dialog, and therefore the suite's gate-denial convention as it exists
// in this repository.
//
// Two things this suite is here to hold:
//
//  1. **The denial is the seam, not the gate.** `FeatureGate.satisfiesTier` /
//     `isAvailable` are pure predicates called from `build()`; instrumenting
//     them would fire on every rebuild. So the tests dispatch actions and count
//     events, and assert explicitly that an ALLOWED dispatch records nothing.
//  2. **`feature` is never the dialog's label.** The upgrade dialog is handed a
//     localized `featureLabel` on the very next line of the same method; the
//     event must carry the closed `NetcruxGatedFeature` token instead. A test
//     asserts every recorded value is a catalog token, which a localized string
//     could not be.
//  3. **One event per dialog shown.** A held chord re-dispatches the denial on
//     every key repeat and the dialog's guard shows one dialog, so the event is
//     recorded when a dialog opens, not when a denial happens. The docked
//     cross-probe panel's send gate is held to the same rule.
//
// Every test overrides `betaPeriodProvider` to false. During the beta the gate
// short-circuits to allow and this event cannot fire at all — which is correct,
// matches telemetry's own dark launch, and is exactly why the gate reads the
// overridable provider rather than the compile-time `kBetaPeriod`.

@TestOn('vm')
library;

import 'package:crux_license/crux_license.dart';
import 'package:crux_telemetry/crux_telemetry.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/core/license/netcrux_gated_feature.dart';
import 'package:netcrux/core/providers/pro_overlay_installed_provider.dart';
import 'package:netcrux/core/shortcuts/netcrux_action.dart';
import 'package:netcrux/core/shortcuts/shortcut_bindings_provider.dart';
import 'package:netcrux/core/shortcuts/shortcut_manager_widget.dart';
import 'package:netcrux/features/remote/providers/cross_probe_originate_gate_provider.dart';
import 'package:netcrux/features/workspace/services/workspace_action_dispatcher.dart';
import 'package:netcrux/l10n/generated/app_localizations.dart';
import 'package:netcrux/services/telemetry/telemetry_event_catalog.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _RecordingTelemetryService implements TelemetryService {
  final List<TelemetryEvent> events = <TelemetryEvent>[];

  @override
  void record(TelemetryEvent event) => events.add(event);

  Iterable<TelemetryEvent> all(String name) =>
      events.where((e) => e.name == name);

  int count(String name) => all(name).length;
}

TelemetryCatalogEvent get _entry =>
    kNetcruxEventCatalog.firstWhere((e) => e.name == 'tier.gate_hit');

/// Fails unless every property of [event] is declared by its catalog entry with
/// a value from the declared vocabulary.
void _assertInCatalog(TelemetryEvent event) {
  final entry = kNetcruxEventCatalog.firstWhere(
    (e) => e.name == event.name,
    orElse: () => throw StateError('${event.name} is not in the catalog'),
  );
  event.properties.forEach((key, value) {
    expect(entry.propertyKeys, contains(key));
    expect(entry.enumeratedValues[key], contains(value));
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _RecordingTelemetryService telemetry;

  setUp(() {
    telemetry = _RecordingTelemetryService();
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  Future<(WorkspaceActionDispatcher, BuildContext)> pumpDispatcher(
    WidgetTester tester, {
    required bool beta,
    LicenseTier tier = LicenseTier.openCore,
    bool shortcuts = false,
  }) async {
    late WorkspaceActionDispatcher dispatcher;
    late BuildContext hostContext;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          telemetryServiceProvider.overrideWithValue(telemetry),
          betaPeriodProvider.overrideWithValue(beta),
          licenseTierProvider.overrideWith((_) => tier),
          // These tests count tier denials; the overlay is present so an
          // admitted action runs rather than asking for Pro.
          proOverlayInstalledProvider.overrideWithValue(true),
        ],
        child: MaterialApp(
          localizationsDelegates: L10N.localizationsDelegates,
          supportedLocales: L10N.supportedLocales,
          // With [shortcuts], every action's chord dispatches through the
          // dispatcher, from above the Navigator: a key that repeats after
          // the upgrade dialog has taken focus still reaches the shortcut
          // layer, which is the case the dialog's guard exists for.
          builder: shortcuts
              ? (context, child) => ShortcutManagerWidget(
                  handlers: <NetcruxAction, VoidCallback>{
                    for (final action in NetcruxAction.values)
                      action: () => dispatcher.dispatch(hostContext, action),
                  },
                  child: child!,
                )
              : null,
          home: Consumer(
            builder: (context, ref, _) {
              hostContext = context;
              dispatcher = WorkspaceActionDispatcher(
                ref: ref,
                openProject: () async {},
                openSourceFiles: () async {},
                openNetlistJson: () async {},
                openWorkspaceFlow: () async {},
              );
              return const Focus(autofocus: true, child: SizedBox.shrink());
            },
          ),
        ),
      ),
    );
    return (dispatcher, hostContext);
  }

  // Closes the upgrade dialog a denial opened, as the user would, so the next
  // denial opens a dialog of its own.
  Future<void> dismissUpgradeDialog(WidgetTester tester) async {
    await tester.pumpAndSettle();
    final dialog = find.byType(CruxUpgradeDialog);
    expect(dialog, findsOneWidget);
    await tester.tap(find.text(L10N.of(tester.element(dialog)).commonOk));
    await tester.pumpAndSettle();
  }

  group('tier.gate_hit', () {
    testWidgets('a denied Pro action records the feature and required tier', (
      tester,
    ) async {
      final (dispatcher, context) = await pumpDispatcher(
        tester,
        beta: false,
      );

      dispatcher.dispatch(context, NetcruxAction.showCdcAnalysisPane);
      await tester.pump();

      expect(telemetry.count('tier.gate_hit'), 1);
      final event = telemetry.all('tier.gate_hit').single;
      expect(event.properties['feature'], 'cdc');
      expect(event.properties['required'], 'pro');
      _assertInCatalog(event);
    });

    testWidgets('the recorded feature is the closed token, not the label', (
      tester,
    ) async {
      // The dialog's `featureLabel` for this action is "Show Cone of Influence
      // (Fanin)" in English and different text in each of the other four
      // locales. Whatever reaches the wire has to be `coi`.
      final (dispatcher, context) = await pumpDispatcher(
        tester,
        beta: false,
      );

      dispatcher.dispatch(context, NetcruxAction.showConeOfInfluenceFanin);
      await tester.pump();

      final event = telemetry.all('tier.gate_hit').single;
      expect(
        event.properties['feature'],
        telemetryEnumToken(NetcruxGatedFeature.coi),
      );
      expect(
        _entry.enumeratedValues['feature'],
        contains(event.properties['feature']),
      );
    });

    testWidgets('fanin and fanout report one feature, not two', (tester) async {
      // Granularity is the priced feature, not the menu item: a user denied on
      // either wanted the same purchase. Each denial is dismissed before the
      // next, since a denial while a dialog is up records nothing.
      final (dispatcher, context) = await pumpDispatcher(
        tester,
        beta: false,
      );

      dispatcher.dispatch(context, NetcruxAction.showConeOfInfluenceFanin);
      await dismissUpgradeDialog(tester);
      dispatcher.dispatch(context, NetcruxAction.showConeOfInfluenceFanout);
      await dismissUpgradeDialog(tester);

      expect(
        [
          for (final e in telemetry.all('tier.gate_hit'))
            e.properties['feature'],
        ],
        <String>['coi', 'coi'],
      );
    });

    testWidgets('a held gated shortcut opens one dialog and records one hit', (
      tester,
    ) async {
      // Key auto-repeat re-dispatches the denial for as long as the chord is
      // held. The shared opener shows one dialog however often it is asked;
      // the funnel has to count the same way, or a held chord reads as a
      // dozen users asking to upgrade. MUTATION: recording before
      // `NetcruxUpgradeDialog.show` rather than in its `onOpened` makes this
      // count every repeat.
      final (_, context) = await pumpDispatcher(
        tester,
        beta: false,
        shortcuts: true,
      );
      // No Pro action ships with a default chord; a user can bind one.
      ProviderScope.containerOf(context)
          .read(shortcutBindingsProvider.notifier)
          .setBinding(
            NetcruxAction.showCdcAnalysisPane,
            const SingleActivator(
              LogicalKeyboardKey.keyK,
              control: true,
              alt: true,
            ),
          );
      await tester.pump();

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyK);
      await tester.pump();
      for (var i = 0; i < 5; i++) {
        await tester.sendKeyRepeatEvent(LogicalKeyboardKey.keyK);
        await tester.pump();
      }
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyK);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();

      expect(find.byType(CruxUpgradeDialog), findsOneWidget);
      expect(telemetry.count('tier.gate_hit'), 1);

      // Dismissed, the next press is a new denial and counts again.
      await dismissUpgradeDialog(tester);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();

      expect(find.byType(CruxUpgradeDialog), findsOneWidget);
      expect(telemetry.count('tier.gate_hit'), 2);
    });

    testWidgets('an allowed dispatch records nothing', (tester) async {
      // The event counts DENIALS. A Pro user exercising a Pro feature is
      // `analysis.run`, not a gate hit — conflating them would make the
      // upgrade-intent number read as usage.
      final (dispatcher, context) = await pumpDispatcher(
        tester,
        beta: false,
        tier: LicenseTier.pro,
      );

      dispatcher.dispatch(context, NetcruxAction.showCdcAnalysisPane);
      await tester.pump();

      expect(telemetry.count('tier.gate_hit'), 0);
    });

    testWidgets('a denied Share Session records "tried to host"', (
      tester,
    ) async {
      // Hosting is Enterprise, so a Pro licence is still denied, and the hit
      // names the collaboration feature and the Enterprise tier.
      final (dispatcher, context) = await pumpDispatcher(
        tester,
        beta: false,
        tier: LicenseTier.pro,
      );

      dispatcher.dispatch(context, NetcruxAction.shareSession);
      await tester.pump();

      final event = telemetry.all('tier.gate_hit').single;
      expect(event.properties['feature'], 'collaboration');
      expect(event.properties['required'], 'enterprise');
      _assertInCatalog(event);
    });

    testWidgets('Join Session and Leave Session never record a gate hit', (
      tester,
    ) async {
      // Joining is free in every edition: an unlicensed guest is a full
      // participant, so there is no denial to count.
      final (dispatcher, context) = await pumpDispatcher(
        tester,
        beta: false,
      );

      dispatcher
        ..dispatch(context, NetcruxAction.joinSession)
        ..dispatch(context, NetcruxAction.leaveSession);
      await tester.pump();

      expect(telemetry.count('tier.gate_hit'), 0);
      expect(find.byType(CruxUpgradeDialog), findsNothing);
    });

    testWidgets('an open-core action records nothing', (tester) async {
      final (dispatcher, context) = await pumpDispatcher(
        tester,
        beta: false,
      );

      dispatcher.dispatch(context, NetcruxAction.showFanin);
      await tester.pump();

      expect(telemetry.count('tier.gate_hit'), 0);
    });

    testWidgets('nothing is recorded during the beta', (tester) async {
      // Dormant by construction, not by accident: the gate admits every tier
      // while the beta flag is set, so there is no denial to record. This is
      // the assertion that keeps the branch honest when someone reads it as
      // dead code.
      final (dispatcher, context) = await pumpDispatcher(
        tester,
        beta: true,
      );

      dispatcher.dispatch(context, NetcruxAction.showCdcAnalysisPane);
      await tester.pump();

      expect(telemetry.count('tier.gate_hit'), 0);
    });

    testWidgets('every Pro action produces a catalogued feature token', (
      tester,
    ) async {
      // The closure that makes the catalog's `feature` list a description of
      // the product rather than a guess: dispatch EVERY tier-gated action and
      // check what each one actually emits.
      final (dispatcher, context) = await pumpDispatcher(
        tester,
        beta: false,
      );

      final gated = [
        for (final action in NetcruxAction.values)
          if (action.requiredTier != LicenseTier.openCore) action,
      ];
      for (final action in gated) {
        dispatcher.dispatch(context, action);
        await dismissUpgradeDialog(tester);
      }

      expect(telemetry.count('tier.gate_hit'), gated.length);
      for (final event in telemetry.all('tier.gate_hit')) {
        _assertInCatalog(event);
        expect(
          <String>['pro', 'enterprise'],
          contains(event.properties['required']),
        );
      }
    });

    testWidgets('the cross-probe send gate records one hit per dialog shown', (
      tester,
    ) async {
      // The panel's send is the other open-core gate-hit site, and it counts
      // the same way: a denial while the dialog is up records nothing.
      // MUTATION: recording before `NetcruxUpgradeDialog.show` in
      // `crossProbeOriginateGateProvider` makes the first count 3.
      final (_, context) = await pumpDispatcher(tester, beta: false);
      final gate = ProviderScope.containerOf(
        context,
      ).read(crossProbeOriginateGateProvider);

      for (var i = 0; i < 3; i++) {
        expect(gate(context), isFalse);
      }
      await tester.pumpAndSettle();

      expect(find.byType(CruxUpgradeDialog), findsOneWidget);
      expect(telemetry.count('tier.gate_hit'), 1);
      final event = telemetry.all('tier.gate_hit').single;
      expect(event.properties['feature'], 'cross_probe');
      _assertInCatalog(event);

      await dismissUpgradeDialog(tester);
      expect(gate(context), isFalse);
      await tester.pumpAndSettle();
      expect(telemetry.count('tier.gate_hit'), 2);
    });
  });
}
