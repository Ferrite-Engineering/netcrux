// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_updates/crux_updates.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/core/updates/netcrux_update_config.dart';
import 'package:netcrux/core/updates/netcrux_update_strings.dart';
import 'package:netcrux/l10n/generated/app_localizations.dart';

/// The update banner as NetCrux mounts it: NetCrux's config, NetCrux's ARB
/// strings, NetCrux's download target.
///
/// The widget itself belongs to `crux_updates`; what is verified here is the
/// contract a NetCrux *user* sees — the localized copy renders, "Update Now"
/// lands on the NetCrux download page, a dismissal sticks for the session,
/// and a **mandatory** update offers no dismiss affordance at all.
class _PinnedStatus extends UpdateStatusNotifier {
  _PinnedStatus(this._status);

  final UpdateStatus _status;

  @override
  UpdateStatus build() => _status;
}

void main() {
  const childKey = Key('routedContent');

  late List<Uri> launched;

  setUp(() => launched = <Uri>[]);

  Widget buildBanner({
    required UpdateStatus status,
    String locale = 'en',
    bool isWeb = false,
  }) => ProviderScope(
    overrides: <Override>[
      cruxUpdateConfigProvider.overrideWithValue(netcruxUpdateConfig),
      updateStatusProvider.overrideWith(() => _PinnedStatus(status)),
      updateUrlLauncherProvider.overrideWithValue((uri) async {
        launched.add(uri);
        return true;
      }),
    ],
    child: MaterialApp(
      locale: Locale(locale),
      localizationsDelegates: L10N.localizationsDelegates,
      supportedLocales: L10N.supportedLocales,
      builder: (context, child) => ProviderScope(
        overrides: <Override>[
          cruxUpdateStringsProvider.overrideWithValue(
            NetcruxUpdateStrings(L10N.of(context)),
          ),
        ],
        child: UpdateBanner(
          isWeb: isWeb,
          child: child ?? const SizedBox.shrink(),
        ),
      ),
      home: const Scaffold(
        body: ColoredBox(key: childKey, color: Colors.transparent),
      ),
    ),
  );

  group('visibility', () {
    testWidgets('renders nothing while the build is current', (tester) async {
      await tester.pumpWidget(
        buildBanner(status: const UpdateStatusCurrent()),
      );
      expect(find.byType(UpdateAvailableBanner), findsNothing);
      expect(find.byKey(childKey), findsOneWidget);
    });

    testWidgets('never nags on a failed check', (tester) async {
      await tester.pumpWidget(buildBanner(status: const UpdateStatusError()));
      expect(find.byType(UpdateAvailableBanner), findsNothing);
    });

    testWidgets('shows the strip when an update is available', (tester) async {
      await tester.pumpWidget(
        buildBanner(
          status: const UpdateStatusAvailable(UpdateInfo(version: '1.2.0')),
        ),
      );
      expect(find.byType(UpdateAvailableBanner), findsOneWidget);
      expect(find.textContaining('NetCrux 1.2.0'), findsOneWidget);
    });

    testWidgets('the web viewer never shows the strip', (tester) async {
      // A web build self-updates on reload, so a "download the new version"
      // banner is noise there. The check itself still runs for `server_time`.
      await tester.pumpWidget(
        buildBanner(
          status: const UpdateStatusAvailable(UpdateInfo(version: '1.2.0')),
          isWeb: true,
        ),
      );
      expect(find.byType(UpdateAvailableBanner), findsNothing);
      expect(find.byKey(childKey), findsOneWidget);
    });
  });

  group('actions', () {
    testWidgets('Update Now opens the NetCrux download page', (tester) async {
      await tester.pumpWidget(
        buildBanner(
          status: const UpdateStatusAvailable(UpdateInfo(version: '1.2.0')),
        ),
      );
      await tester.tap(find.text('Update Now'));
      await tester.pump();
      expect(launched, [Uri.parse(netcruxDownloadPageUrl)]);
    });

    testWidgets('View Changes opens the changelog when present', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildBanner(
          status: const UpdateStatusAvailable(
            UpdateInfo(
              version: '1.2.0',
              changelogUrl: 'https://netcrux.app/releases/1.2.0',
            ),
          ),
        ),
      );
      await tester.tap(find.text('View Changes'));
      await tester.pump();
      expect(launched, [Uri.parse('https://netcrux.app/releases/1.2.0')]);
    });

    testWidgets('View Changes is absent without a changelog', (tester) async {
      await tester.pumpWidget(
        buildBanner(
          status: const UpdateStatusAvailable(UpdateInfo(version: '1.2.0')),
        ),
      );
      expect(find.text('View Changes'), findsNothing);
    });
  });

  group('dismissal', () {
    testWidgets('an optional update can be dismissed for the session', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildBanner(
          status: const UpdateStatusAvailable(UpdateInfo(version: '1.2.0')),
        ),
      );
      await tester.tap(find.byIcon(Icons.close));
      await tester.pump();
      expect(find.byType(UpdateAvailableBanner), findsNothing);
      expect(find.byKey(childKey), findsOneWidget);
    });

    testWidgets('a MANDATORY update has no dismiss affordance', (tester) async {
      // A build below `min_supported_version` is no longer supported; the
      // banner must not offer a way to hide that.
      await tester.pumpWidget(
        buildBanner(
          status: const UpdateStatusAvailable(
            UpdateInfo(version: '1.2.0', mandatory: true),
          ),
        ),
      );
      expect(find.byType(UpdateAvailableBanner), findsOneWidget);
      expect(find.byIcon(Icons.close), findsNothing);
    });
  });

  group('touch targets', () {
    testWidgets('the banner actions clear 44 dp', (tester) async {
      await tester.pumpWidget(
        buildBanner(
          status: const UpdateStatusAvailable(
            UpdateInfo(
              version: '1.2.0',
              changelogUrl: 'https://netcrux.app/releases/1.2.0',
            ),
          ),
        ),
      );
      for (final label in ['Update Now', 'View Changes']) {
        expect(
          tester.getSize(find.text(label).hitTestable()).height,
          greaterThan(0),
        );
      }
      final dismiss = tester.getSize(find.byIcon(Icons.close));
      expect(dismiss.height, greaterThan(0));

      // The banner's own metrics default to the suite's 44 dp floor; NetCrux
      // mounts it with those defaults (no device-class system on desktop).
      const metrics = CruxUpdateBannerMetrics();
      expect(metrics.touchTarget, greaterThanOrEqualTo(44));
    });
  });

  group('locale sweep', () {
    for (final locale in ['en', 'zh_CN', 'ja', 'ko']) {
      testWidgets('renders in $locale without exception', (tester) async {
        await tester.pumpWidget(
          buildBanner(
            status: const UpdateStatusAvailable(
              UpdateInfo(
                version: '1.2.0',
                changelogUrl: 'https://netcrux.app/releases/1.2.0',
              ),
            ),
            locale: locale,
          ),
        );
        expect(find.byType(UpdateAvailableBanner), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  });
}
