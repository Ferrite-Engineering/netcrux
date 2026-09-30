// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_app_info/crux_app_info.dart';
import 'package:crux_workspace/crux_workspace.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/core/app_info/about_providers.dart';
import 'package:netcrux/core/netcrux_url_launcher.dart';
import 'package:netcrux/features/workspace/widgets/browser_empty_canvas_content.dart';
import 'package:netcrux/features/workspace/widgets/empty_canvas_content.dart';
import 'package:netcrux/l10n/generated/app_localizations.dart';
import 'package:netcrux/shared/widgets/netcrux_suite_footer.dart';
import 'package:netcrux/shared/widgets/netcrux_suite_peers.dart';

const _buildInfo = ApplicationBuildInfo(
  version: '9.9.9',
  buildNumber: '7',
  gitShortSha: 'abc1234',
  os: 'macos',
  architecture: 'arm64',
  flutterSdkVersion: '3.44.8',
  dartSdkVersion: '3.12.2',
);

Future<void> _pump(
  WidgetTester tester,
  Widget body, {
  Locale locale = const Locale('en'),
}) async {
  await tester.binding.setSurfaceSize(const Size(1200, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        aboutBuildInfoProvider.overrideWith((ref) async => _buildInfo),
      ],
      child: MaterialApp(
        locale: locale,
        localizationsDelegates: L10N.localizationsDelegates,
        supportedLocales: L10N.supportedLocales,
        home: Scaffold(body: body),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Widget get _desktopCanvas => EmptyCanvasContent(
  onOpenProject: () {},
  onOpenSourceFiles: () {},
  onOpenWorkspace: () {},
  onPickRecentProject: (_) {},
  onPickRecentSourceFile: (_) {},
  onPickRecentWorkspace: (_) {},
  onClearRecent: () {},
);

void main() {
  final opened = <Uri>[];
  setUp(() {
    opened.clear();
    netcruxLaunchUrl = (uri) async {
      opened.add(uri);
      return true;
    };
  });

  testWidgets('the desktop start screen carries the line', (tester) async {
    await _pump(tester, _desktopCanvas);
    expect(find.byType(NetCruxSuiteFooter), findsOneWidget);
  });

  testWidgets('so does the browser start screen, where a visitor has '
      'installed nothing yet', (tester) async {
    await _pump(
      tester,
      BrowserEmptyCanvasContent(onOpenNetlistJson: () {}),
    );
    expect(find.byType(NetCruxSuiteFooter), findsOneWidget);
  });

  testWidgets('following the line opens this product’s landing path', (
    tester,
  ) async {
    await _pump(tester, _desktopCanvas);
    // The peers block above it pushes the line below the fold on this
    // surface, and a tap outside the viewport silently does nothing.
    await tester.ensureVisible(find.byKey(CruxSuiteFooter.rowKey));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(CruxSuiteFooter.rowKey));
    await tester.pumpAndSettle();

    // Per-product path, not the shared `/products` page: the site's page-view
    // beacon records the path and drops the query string, so this segment is
    // the only thing that attributes the visit to NetCrux.
    expect(opened, [Uri.parse('https://edacrux.app/from/netcrux')]);
  });

  group('More from EDACrux', () {
    testWidgets('both start screens offer the other three', (tester) async {
      for (final body in <Widget>[
        _desktopCanvas,
        BrowserEmptyCanvasContent(onOpenNetlistJson: () {}),
      ]) {
        await _pump(tester, body);
        expect(find.byType(NetCruxSuitePeers), findsOneWidget);
        for (final peer in CruxSuiteProduct.netCrux.peers) {
          expect(
            find.byKey(CruxSuitePeers.rowKeyFor(peer)),
            findsOneWidget,
            reason: '${peer.displayName} row missing from $body',
          );
        }
        expect(
          find.byKey(CruxSuitePeers.rowKeyFor(CruxSuiteProduct.netCrux)),
          findsNothing,
        );
      }
    });

    testWidgets('a row lands on that product\u2019s card', (tester) async {
      await _pump(tester, _desktopCanvas);
      await tester.tap(
        find.byKey(CruxSuitePeers.rowKeyFor(CruxSuiteProduct.simCrux)),
      );
      await tester.pumpAndSettle();

      // Same attributable path as the footer, plus a fragment the site's
      // beacon drops before sending — so the reader lands on SimCrux's card
      // and the visit is still recorded against NetCrux.
      expect(opened, [Uri.parse('https://edacrux.app/from/netcrux#simcrux')]);
    });

    testWidgets('every locale names all three products', (tester) async {
      for (final locale in const [
        Locale('en'),
        Locale('zh', 'CN'),
        Locale('zh'),
        Locale('ja'),
        Locale('ko'),
      ]) {
        await _pump(tester, _desktopCanvas, locale: locale);
        expect(tester.takeException(), isNull, reason: 'locale $locale');
        for (final peer in CruxSuiteProduct.netCrux.peers) {
          // Product names are never translated.
          expect(
            find.text(peer.displayName),
            findsOneWidget,
            reason: '$locale dropped ${peer.displayName}',
          );
        }
      }
    });
  });

  testWidgets('every locale keeps the linked domain verbatim', (tester) async {
    for (final locale in const [
      Locale('en'),
      Locale('zh', 'CN'),
      Locale('zh'),
      Locale('ja'),
      Locale('ko'),
    ]) {
      await _pump(tester, _desktopCanvas, locale: locale);
      expect(tester.takeException(), isNull, reason: 'locale $locale');

      await tester.ensureVisible(find.byKey(CruxSuiteFooter.rowKey));
      await tester.pumpAndSettle();
      final rendered = tester
          .widget<Text>(
            find.descendant(
              of: find.byKey(CruxSuiteFooter.rowKey),
              matching: find.byType(Text),
            ),
          )
          .textSpan!
          .toPlainText();
      // The widget splits the sentence around this literal to underline it. A
      // translation that paraphrased the domain would render a line with
      // nothing to click, which is not a visible failure.
      expect(
        rendered,
        contains(CruxSuiteFooter.defaultLinkText),
        reason: 'locale $locale dropped the linked domain',
      );
      expect(rendered, contains('EDACrux'), reason: 'locale $locale');
    }
  });
}
