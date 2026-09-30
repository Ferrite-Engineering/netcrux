// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_license/crux_license.dart'
    show betaPeriodProvider, kBetaPeriod;
import 'package:crux_telemetry/crux_telemetry.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:netcrux/core/telemetry/netcrux_telemetry_config.dart';
import 'package:netcrux/core/telemetry/netcrux_telemetry_storage.dart';
import 'package:netcrux/core/telemetry/netcrux_telemetry_strings.dart';
import 'package:netcrux/features/settings/screens/settings_screen.dart';
import 'package:netcrux/l10n/generated/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// NetCrux's half of the telemetry gate.
///
/// The 12-cell `beta × dev × consent` gating matrix and the traffic-level
/// beta-inert test live in `crux_telemetry` — they exercise the gate itself,
/// which is shared. What cannot move, and is asserted here, is that **this
/// build** is wired so the gate holds:
///
///  * the real `kBetaPeriod` / `kTelemetryDev` constants this release ships
///    with: the public beta is over, so the gate waits on the user's consent
///    rather than being closed outright, and sends nothing until it is given;
///  * a beta build, pinned through telemetry's own seam, resolves to the
///    no-op service through NetCrux's configuration whatever the consent;
///  * a `betaPeriodProvider` override — the *badging* seam — does not reach
///    telemetry;
///  * neither consent surface mounts in a beta build's UI.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  /// The root container `bootstrap` builds, minus the network.
  ProviderContainer netcruxContainer({List<Override> extra = const []}) {
    final container = ProviderContainer(
      overrides: [
        cruxTelemetryConfigProvider.overrideWithValue(netcruxTelemetryConfig),
        telemetryStorageProvider.overrideWithValue(
          const NetcruxTelemetryStorage(),
        ),
        telemetryHttpClientProvider.overrideWithValue(
          MockClient((_) async => http.Response('{}', 202)),
        ),
        ...extra,
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  test(
    'the shipping build is past the beta, and sends nothing unasked',
    () async {
      // The flip that activates telemetry is this constant, and nothing else.
      expect(kBetaPeriod, isFalse);
      expect(kTelemetryDev, isFalse);

      final container = netcruxContainer();
      // Before the store has read the persisted answer, events wait rather
      // than go anywhere; once it has, "never asked" is not consent.
      expect(
        container.read(telemetryServiceProvider),
        isA<PendingTelemetryService>(),
      );
      await container.read(telemetryConsentReadyProvider.future);
      expect(container.read(telemetryEnabledProvider), isFalse);
      expect(
        container.read(telemetryServiceProvider),
        isA<NoopTelemetryService>(),
      );
    },
  );

  group("THE BETA-INERT TEST — NetCrux's side of the dark launch", () {
    // A beta build, pinned through telemetry's own seam rather than leaning
    // on the shipping default, which is no longer a beta.
    List<Override> inBeta([List<Override> extra = const []]) => <Override>[
      telemetryBetaPeriodProvider.overrideWithValue(true),
      ...extra,
    ];

    test('a beta build resolves to the no-op service', () {
      final container = netcruxContainer(extra: inBeta());
      expect(container.read(telemetryEnabledProvider), isFalse);
      expect(
        container.read(telemetryServiceProvider),
        isA<NoopTelemetryService>(),
      );
    });

    test('an explicit `enabled` consent does not override the beta gate', () {
      final container = netcruxContainer(extra: inBeta());
      container.read(telemetryConsentStoreProvider.notifier).state =
          TelemetryConsentState.enabled;

      expect(container.read(telemetryEnabledProvider), isFalse);
      expect(
        container.read(telemetryServiceProvider),
        isA<NoopTelemetryService>(),
      );
    });

    test('a betaPeriodProvider override does not reach telemetry', () {
      // NetCrux ships desktop and web runners only, so — unlike WaveCrux — it
      // does not override `betaPeriodProvider` on mobile hosts for App Store
      // badging (Review Guideline 2.2). It does *read* the provider: the Pro
      // tier gate consults it so tests can pin either side of the beta.
      //
      // This pins the separation. If telemetry keyed off
      // `betaPeriodProvider`, any override of it — a badging decision, or a
      // Pro-gate test pinning the beta *off* — would move telemetry with it.
      // `telemetryBetaPeriodProvider` is telemetry's own seam; here it says
      // beta, and the badging seam saying otherwise changes nothing.
      final container = netcruxContainer(
        extra: inBeta([betaPeriodProvider.overrideWithValue(false)]),
      );
      container.read(telemetryConsentStoreProvider.notifier).state =
          TelemetryConsentState.enabled;

      expect(container.read(telemetryEnabledProvider), isFalse);
      expect(
        container.read(telemetryServiceProvider),
        isA<NoopTelemetryService>(),
      );
      expect(container.read(telemetryConsentUiVisibleProvider), isFalse);
    });

    testWidgets(
      'during beta with no dev flag, neither consent surface mounts',
      (tester) async {
        // The dark launch covers the UI too. A beta build must not show the
        // first-launch disclosure or the Settings → Privacy toggle: there is
        // nothing to consent to, and asking would advertise collection this
        // build is structurally incapable of doing.
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              cruxTelemetryConfigProvider.overrideWithValue(
                netcruxTelemetryConfig,
              ),
              telemetryStorageProvider.overrideWithValue(
                const NetcruxTelemetryStorage(),
              ),
              telemetryBetaPeriodProvider.overrideWithValue(true),
              telemetryDevModeProvider.overrideWithValue(false),
              telemetryHttpClientProvider.overrideWithValue(
                MockClient((_) async => http.Response('{}', 202)),
              ),
            ],
            child: MaterialApp(
              localizationsDelegates: L10N.localizationsDelegates,
              supportedLocales: L10N.supportedLocales,
              home: Builder(
                builder: (context) => ProviderScope(
                  overrides: [
                    cruxTelemetryStringsProvider.overrideWithValue(
                      NetcruxTelemetryStrings(L10N.of(context)),
                    ),
                  ],
                  child: const TelemetryConsentGate(child: SettingsScreen()),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byType(TelemetryConsentDisclosure), findsNothing);
        expect(find.text('Privacy'), findsNothing);
        expect(find.byKey(const Key('settingsTelemetrySwitch')), findsNothing);
      },
    );
  });

  group('the gating matrix, through NetCrux wiring', () {
    // The package asserts this against traffic; repeated here through
    // NetCrux's own config + storage so a wiring mistake (a config that never
    // resolves, a storage adapter that throws) cannot pass the package suite
    // and fail here silently.
    for (final beta in const [true, false]) {
      for (final dev in const [true, false]) {
        for (final consent in TelemetryConsentState.values) {
          final expected = dev
              ? consent != TelemetryConsentState.disabled
              : !beta && consent == TelemetryConsentState.enabled;
          test(
            'beta=$beta dev=$dev consent=${consent.name} → $expected',
            () async {
              final container = netcruxContainer(
                extra: [
                  telemetryBetaPeriodProvider.overrideWithValue(beta),
                  telemetryDevModeProvider.overrideWithValue(dev),
                ],
              );
              container.read(telemetryConsentStoreProvider.notifier).state =
                  consent;
              // The matrix states the settled behaviour. Under the dev flag
              // `unset` counts as consent only once the store has read its
              // persisted value back — before that a stored refusal wears the
              // same value, which is how a `disabled` installation transmitted
              // (D3). `NetcruxTelemetryStorage` reads SharedPreferences, so the
              // window is real here, not a package-level abstraction.
              await container.read(telemetryConsentReadyProvider.future);

              expect(container.read(telemetryEnabledProvider), expected);
              expect(
                container.read(telemetryServiceProvider),
                expected
                    ? isA<LiveTelemetryService>()
                    : isA<NoopTelemetryService>(),
              );
            },
          );
        }
      }
    }
  });

  group("NetCrux's envelope wiring", () {
    test('reports the netcrux slug and a Worker-legal envelope', () async {
      // The product slug is the one field `crux_telemetry` cannot supply, and
      // a slug the Worker does not know rejects every batch NetCrux ever sends
      // with a 400 the client never sees.
      final container = netcruxContainer(
        extra: [telemetryAppVersionProvider.overrideWith((_) async => '0.6.0')],
      );

      final envelope = await container.read(
        telemetryEnvelopeResolverProvider,
      )();

      expect(envelope, isNotNull);
      expect(envelope!.product, 'netcrux');
      expect(envelope.userAgent, 'NetCrux/0.6.0');
      expect(kTelemetryOperatingSystems, contains(envelope.os));
      expect(kTelemetryFormFactors, contains(envelope.formFactor));
      expect(kTelemetryLicenseTiers, contains(envelope.licenseTier));
      expect(
        kTelemetryInstallationIdPattern.hasMatch(envelope.installationId),
        isTrue,
      );
    });

    test(
      'the installation id persists under the suite-fixed prefs key',
      () async {
        final id = await netcruxContainer().read(
          telemetryInstallationIdProvider.future,
        );

        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getString('telemetry.installationId'), id);
        expect(kTelemetryInstallationIdKey, 'telemetry.installationId');
        // Outside the `netcrux.*` settings namespace on purpose: a settings
        // file copied to a second machine must not carry this id with it.
        expect(kTelemetryInstallationIdKey.startsWith('netcrux.'), isFalse);
        expect(kTelemetryConsentKey.startsWith('netcrux.'), isFalse);
      },
    );

    test('the endpoint is the production suite ingest', () {
      // Not a dev build, so not the staging dataset. The path selects the
      // dataset; nothing NetCrux sends can move it.
      expect(
        netcruxContainer().read(telemetryEndpointProvider).toString(),
        'https://telemetry.edacrux.app/v1/events',
      );
    });
  });

  group('the seam itself', () {
    test('can be overridden with a recording fake', () {
      final recorder = _RecordingTelemetryService();
      final container = ProviderContainer(
        overrides: [telemetryServiceProvider.overrideWithValue(recorder)],
      );
      addTearDown(container.dispose);

      container
          .read(telemetryServiceProvider)
          .record(TelemetryEvent('design.elaborated'));

      expect(recorder.events, hasLength(1));
      expect(recorder.events.first.name, 'design.elaborated');
    });
  });
}

class _RecordingTelemetryService implements TelemetryService {
  final events = <TelemetryEvent>[];

  @override
  void record(TelemetryEvent event) => events.add(event);
}
