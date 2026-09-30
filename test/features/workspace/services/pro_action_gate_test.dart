// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_license/crux_license.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/core/providers/pro_overlay_installed_provider.dart';
import 'package:netcrux/core/shortcuts/netcrux_action.dart';
import 'package:netcrux/features/workspace/services/pro_action_gate.dart';
import 'package:netcrux/l10n/generated/app_localizations.dart';

import '../../../helpers/telemetry_test_overrides.dart';

/// Pumps a host and returns a gate bound to its context and ref.
Future<bool Function(NetcruxAction)> _gate(
  WidgetTester tester,
  List<Override> overrides,
) async {
  late BuildContext hostContext;
  late WidgetRef hostRef;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [...netcruxTelemetryTestOverrides(), ...overrides],
      child: MaterialApp(
        localizationsDelegates: L10N.localizationsDelegates,
        supportedLocales: L10N.supportedLocales,
        home: Scaffold(
          body: Consumer(
            builder: (context, ref, _) {
              hostContext = context;
              hostRef = ref;
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    ),
  );
  bool allow(NetcruxAction action) =>
      allowProAction(hostContext, hostRef, action);
  return allow;
}

void main() {
  testWidgets('an open-core action is always allowed, silently', (
    tester,
  ) async {
    final allow = await _gate(tester, <Override>[
      betaPeriodProvider.overrideWithValue(false),
      licenseTierProvider.overrideWithValue(LicenseTier.openCore),
    ]);
    expect(allow(NetcruxAction.openSearch), isTrue);
    await tester.pump();
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('a Pro action with no overlay says it requires NetCrux Pro', (
    tester,
  ) async {
    final allow = await _gate(tester, <Override>[
      betaPeriodProvider.overrideWithValue(true),
    ]);
    expect(allow(NetcruxAction.showConeOfInfluenceFanin), isFalse);
    await tester.pump();
    expect(
      find.text('Show Cone of Influence (Fanin) requires NetCrux Pro.'),
      findsOneWidget,
    );
  });

  testWidgets('a Pro action with the overlay installed runs', (tester) async {
    final allow = await _gate(tester, <Override>[
      betaPeriodProvider.overrideWithValue(true),
      proOverlayInstalledProvider.overrideWithValue(true),
    ]);
    expect(allow(NetcruxAction.showConeOfInfluenceFanin), isTrue);
    await tester.pump();
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('post-beta, an insufficient tier gets the upgrade dialog first', (
    tester,
  ) async {
    final allow = await _gate(tester, <Override>[
      betaPeriodProvider.overrideWithValue(false),
      licenseTierProvider.overrideWithValue(LicenseTier.openCore),
    ]);
    expect(allow(NetcruxAction.showXTrace), isFalse);
    await tester.pumpAndSettle();
    expect(find.byType(CruxUpgradeDialog), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
  });
}
