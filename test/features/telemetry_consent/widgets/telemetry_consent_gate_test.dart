// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_telemetry/crux_telemetry.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/core/telemetry/netcrux_telemetry_config.dart';
import 'package:netcrux/core/telemetry/netcrux_telemetry_storage.dart';
import 'package:netcrux/core/telemetry/netcrux_telemetry_strings.dart';
import 'package:netcrux/l10n/generated/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ── Harness ──────────────────────────────────────────────────────────────────
//
// The gate and the disclosure are `crux_telemetry`'s; their own behaviour is
// tested there against an in-memory store. This file exercises the NetCrux
// *wiring* end to end and against the real plugin: `NetcruxTelemetryStorage`
// over SharedPreferences under the suite-fixed key, `NetcruxTelemetryStrings`
// over the ARB, and the `isDesktopPlatform` idiom `app.dart` hands to the
// shared widget.
//
// NetCrux is desktop-first, so its production `isPhoneLayout` is
// `!isDesktopPlatform` rather than a width classification. The layout sweep
// below therefore drives the parameter explicitly at each surface size: what
// is being asserted is that BOTH presentations render, and clear 44 dp, at
// every size NetCrux could plausibly be given — a narrow window on a desktop
// host included.

/// Real device sizes rather than round numbers, so the constraints under test
/// are ones a user's display actually produces.
const _phone = Size(390, 844);
const _tablet = Size(834, 1112);
const _desktop = Size(1440, 900);

const _locales = <Locale>[
  Locale('en'),
  Locale('zh', 'CN'),
  Locale('zh'),
  Locale('ja'),
  Locale('ko'),
];

/// Every URL the surface asked to open.
late List<Uri> launched;

void _setSurface(WidgetTester tester, Size size) {
  tester.view
    ..devicePixelRatio = 1.0
    ..physicalSize = size;
  addTearDown(tester.view.reset);
}

Widget _wrap({
  bool beta = false,
  bool dev = false,
  bool isPhoneLayout = false,
  Locale? locale,
  Widget child = const SizedBox.shrink(),
}) {
  launched = <Uri>[];
  return ProviderScope(
    overrides: [
      cruxTelemetryConfigProvider.overrideWithValue(netcruxTelemetryConfig),
      telemetryStorageProvider.overrideWithValue(
        const NetcruxTelemetryStorage(),
      ),
      telemetryBetaPeriodProvider.overrideWithValue(beta),
      telemetryDevModeProvider.overrideWithValue(dev),
      telemetryUrlLauncherProvider.overrideWithValue((uri) async {
        launched.add(uri);
        return true;
      }),
    ],
    child: MaterialApp(
      localizationsDelegates: L10N.localizationsDelegates,
      supportedLocales: L10N.supportedLocales,
      locale: locale,
      // Exactly what `app.dart` mounts: the strings bundle bound from inside
      // MaterialApp (where L10N.of resolves), and the layout idiom handed to
      // the shared widget rather than re-derived inside it.
      home: Builder(
        builder: (context) => ProviderScope(
          overrides: [
            cruxTelemetryStringsProvider.overrideWithValue(
              NetcruxTelemetryStrings(L10N.of(context)),
            ),
          ],
          child: TelemetryConsentGate(
            isPhoneLayout: isPhoneLayout,
            child: child,
          ),
        ),
      ),
    ),
  );
}

Finder get _disclosure => find.byType(TelemetryConsentDisclosure);
Finder get _switch => find.byKey(const Key('telemetryConsentSwitch'));
Finder get _continue => find.byKey(const Key('telemetryConsentContinueButton'));
Finder get _learnMore =>
    find.byKey(const Key('telemetryConsentLearnMoreButton'));

Future<TelemetryConsentState> _storedConsent() async {
  final prefs = await SharedPreferences.getInstance();
  return TelemetryConsentState.tryParse(
        prefs.getString(TelemetryConsentStore.storageKey),
      ) ??
      TelemetryConsentState.unset;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  // ── When it mounts ─────────────────────────────────────────────────────────

  group('TelemetryConsentGate mounting', () {
    testWidgets('mounts once on a fresh post-beta installation', (
      tester,
    ) async {
      _setSurface(tester, _desktop);
      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();

      expect(_disclosure, findsOneWidget);
    });

    testWidgets('does not mount for an installation that already answered', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'telemetry.consent': 'disabled',
      });
      _setSurface(tester, _desktop);
      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();

      expect(_disclosure, findsNothing);
    });

    testWidgets('never flashes before the persisted consent has settled', (
      tester,
    ) async {
      // The store publishes `unset` synchronously and loads afterwards. A gate
      // keyed on the state alone would mount here — and re-ask a user who
      // answered on a previous launch.
      SharedPreferences.setMockInitialValues(<String, Object>{
        'telemetry.consent': 'enabled',
      });
      _setSurface(tester, _desktop);
      await tester.pumpWidget(_wrap());

      await tester.pump();
      expect(_disclosure, findsNothing);
      await tester.pumpAndSettle();
      expect(_disclosure, findsNothing);
    });

    testWidgets('leaves the wrapped content alone when it does not mount', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'telemetry.consent': 'enabled',
      });
      _setSurface(tester, _desktop);
      await tester.pumpWidget(
        _wrap(child: const Text('routed', textDirection: TextDirection.ltr)),
      );
      await tester.pumpAndSettle();

      expect(find.text('routed'), findsOneWidget);
      expect(_disclosure, findsNothing);
    });

    testWidgets('shows exactly once per installation', (tester) async {
      _setSurface(tester, _desktop);
      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();
      expect(_disclosure, findsOneWidget);

      await tester.tap(_continue);
      await tester.pumpAndSettle();
      expect(_disclosure, findsNothing);

      // A second launch reads the same preferences store back.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();
      expect(_disclosure, findsNothing);
    });

    testWidgets('a beta build never mounts it, whatever the consent', (
      tester,
    ) async {
      _setSurface(tester, _desktop);
      await tester.pumpWidget(_wrap(beta: true));
      await tester.pumpAndSettle();

      expect(_disclosure, findsNothing);
    });
  });

  // ── What Continue writes ───────────────────────────────────────────────────

  group('the decision', () {
    testWidgets('the toggle arrives pre-armed on', (tester) async {
      _setSurface(tester, _desktop);
      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();

      expect(tester.widget<SwitchListTile>(_switch).value, isTrue);
    });

    testWidgets('pre-armed on + Continue writes enabled', (tester) async {
      _setSurface(tester, _desktop);
      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();

      await tester.tap(_continue);
      await tester.pumpAndSettle();

      expect(await _storedConsent(), TelemetryConsentState.enabled);
    });

    testWidgets('toggled off + Continue writes disabled', (tester) async {
      _setSurface(tester, _desktop);
      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();

      await tester.tap(_switch);
      await tester.pumpAndSettle();
      expect(tester.widget<SwitchListTile>(_switch).value, isFalse);

      await tester.tap(_continue);
      await tester.pumpAndSettle();

      expect(await _storedConsent(), TelemetryConsentState.disabled);
    });

    testWidgets(
      'off is exactly as reachable as on — one visible switch, one button, '
      'both on screen without scrolling',
      (tester) async {
        _setSurface(tester, _desktop);
        await tester.pumpWidget(_wrap());
        await tester.pumpAndSettle();

        // No "advanced", no second confirmation step, no hidden affordance:
        // declining is flip-then-Continue, accepting is Continue.
        expect(_switch, findsOneWidget);
        expect(find.byType(FilledButton), findsOneWidget);
        expect(
          tester.getRect(_switch).overlaps(tester.getRect(_continue)),
          isFalse,
        );
      },
    );

    testWidgets('the documentation link opens the suite telemetry page', (
      tester,
    ) async {
      _setSurface(tester, _desktop);
      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();

      await tester.tap(_learnMore);
      await tester.pumpAndSettle();

      expect(launched, [Uri.parse('https://edacrux.app/telemetry')]);
      // Reading the docs is not an answer — the disclosure stays up.
      expect(_disclosure, findsOneWidget);
    });

    testWidgets('the system back gesture cannot dismiss it unanswered', (
      tester,
    ) async {
      _setSurface(tester, _phone);
      await tester.pumpWidget(_wrap(isPhoneLayout: true));
      await tester.pumpAndSettle();

      final popScope = tester.widget<PopScope<dynamic>>(
        find.descendant(
          of: _disclosure,
          matching: find.byType(PopScope<dynamic>),
        ),
      );
      expect(popScope.canPop, isFalse);
      expect(await _storedConsent(), TelemetryConsentState.unset);
    });
  });

  // ── Layout ─────────────────────────────────────────────────────────────────

  group('layout', () {
    testWidgets('the desktop idiom renders the dialog card', (tester) async {
      _setSurface(tester, _desktop);
      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('telemetryConsentDialog')), findsOneWidget);
      expect(find.byKey(const Key('telemetryConsentSheet')), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the phone idiom renders the full-screen sheet', (
      tester,
    ) async {
      _setSurface(tester, _phone);
      await tester.pumpWidget(_wrap(isPhoneLayout: true));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('telemetryConsentSheet')), findsOneWidget);
      expect(find.byKey(const Key('telemetryConsentDialog')), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the dialog card survives a phone-narrow window', (
      tester,
    ) async {
      // NetCrux's desktop minimum is 800x500, but a web tab has no floor at
      // all — the dialog presentation has to survive the phone constraint too.
      _setSurface(tester, _phone);
      await tester.pumpWidget(_wrap());
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('telemetryConsentDialog')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    for (final (name, size, isPhoneLayout) in [
      ('phone', _phone, true),
      ('phone-narrow desktop idiom', _phone, false),
      ('tablet', _tablet, false),
      ('tablet sheet idiom', _tablet, true),
      ('desktop', _desktop, false),
    ]) {
      testWidgets('every control clears 44 dp at $name', (tester) async {
        _setSurface(tester, size);
        await tester.pumpWidget(_wrap(isPhoneLayout: isPhoneLayout));
        await tester.pumpAndSettle();

        for (final target in [_switch, _continue, _learnMore]) {
          final rect = tester.getSize(target);
          expect(
            rect.height,
            greaterThanOrEqualTo(kTelemetryConsentMinTarget),
            reason: '$target is under the 44 dp floor at $name',
          );
          expect(rect.width, greaterThanOrEqualTo(kTelemetryConsentMinTarget));
        }
      });
    }
  });

  // ── Locale sweep ───────────────────────────────────────────────────────────

  group('locale sweep', () {
    for (final locale in _locales) {
      for (final (name, size, isPhoneLayout) in [
        ('phone', _phone, true),
        ('tablet', _tablet, false),
      ]) {
        testWidgets('renders in $locale at $name without exceptions', (
          tester,
        ) async {
          _setSurface(tester, size);
          await tester.pumpWidget(
            _wrap(locale: locale, isPhoneLayout: isPhoneLayout),
          );
          await tester.pumpAndSettle();

          expect(_disclosure, findsOneWidget);
          expect(tester.takeException(), isNull);
        });
      }

      testWidgets('$locale supplies every disclosure string', (tester) async {
        // The five-locale ARB parity sweep the package cannot run: it holds no
        // ARB files, so "did NetCrux translate every disclosure key" is a
        // NetCrux test. A missing key would surface as the English fallback,
        // which the ARB generator inserts silently.
        _setSurface(tester, _desktop);
        await tester.pumpWidget(_wrap(locale: locale));
        await tester.pumpAndSettle();

        final l10n = await L10N.delegate.load(locale);
        for (final text in <String>[
          l10n.telemetryConsentTitle,
          l10n.telemetryConsentBody,
          l10n.telemetryConsentToggleLabel,
          l10n.telemetryConsentContinue,
          l10n.telemetryConsentLearnMore,
        ]) {
          expect(
            find.textContaining(text, findRichText: true),
            findsWidgets,
            reason: '$locale is missing "$text" from the disclosure',
          );
        }
      });
    }

    test('every locale names NetCrux, not another product', () async {
      // The title is the only string that names the product now — the body
      // was reworded to be product-neutral so all four ship the same
      // sentence, which is also why a stray 'WaveCrux' would only ever
      // appear here.
      for (final locale in _locales) {
        final l10n = await L10N.delegate.load(locale);
        expect(l10n.telemetryConsentTitle, contains('NetCrux'));
        expect(l10n.telemetryConsentTitle, isNot(contains('WaveCrux')));
        expect(l10n.telemetryConsentBody, isNot(contains('Crux')));
      }
    });
  });
}
