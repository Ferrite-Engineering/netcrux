// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/features/workspace/widgets/netcrux_viewer_tab_bar_strings.dart';
import 'package:netcrux/l10n/generated/app_localizations.dart';

Future<NetcruxViewerTabBarStrings> _stringsFor(
  WidgetTester tester,
  Locale locale,
) async {
  late NetcruxViewerTabBarStrings result;
  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      localizationsDelegates: const [
        L10N.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: L10N.supportedLocales,
      home: Builder(
        builder: (context) {
          result = NetcruxViewerTabBarStrings(L10N.of(context));
          return const SizedBox.shrink();
        },
      ),
    ),
  );
  return result;
}

void main() {
  group('NetcruxViewerTabBarStrings', () {
    testWidgets('en yields the English ARB values', (tester) async {
      final s = await _stringsFor(tester, const Locale('en'));
      expect(s.closeTabTooltip, 'Close tab');
      expect(s.newTabTooltip, 'New tab');
      expect(s.unnamedTabFallback, '(unnamed tab)');
      expect(s.activePaneAccessibilityLabel, 'Active pane');
      expect(tester.takeException(), isNull);
    });

    testWidgets('zh_CN yields the Simplified Chinese ARB values', (
      tester,
    ) async {
      final s = await _stringsFor(tester, const Locale('zh', 'CN'));
      expect(s.closeTabTooltip, '关闭标签页');
      expect(s.newTabTooltip, '新建标签页');
      expect(tester.takeException(), isNull);
    });

    testWidgets('ja yields the Japanese ARB values', (tester) async {
      final s = await _stringsFor(tester, const Locale('ja'));
      expect(s.closeTabTooltip, 'タブを閉じる');
      expect(s.activePaneAccessibilityLabel, 'アクティブなペイン');
      expect(tester.takeException(), isNull);
    });

    testWidgets('ko yields the Korean ARB values', (tester) async {
      final s = await _stringsFor(tester, const Locale('ko'));
      expect(s.closeTabTooltip, '탭 닫기');
      expect(s.unnamedTabFallback, '(이름 없는 탭)');
      expect(tester.takeException(), isNull);
    });

    testWidgets('the close button names the tab it closes, in every locale', (
      tester,
    ) async {
      // The shared default returns the generic "Close tab" for every chip, so
      // a screen reader moving across several tabs could not tell which one a
      // close button belongs to.
      const expected = <(Locale, String)>[
        (Locale('en'), 'Close top.v'),
        (Locale('ja'), 'top.v を閉じる'),
        (Locale('ko'), 'top.v 닫기'),
        (Locale('zh'), '关闭 top.v'),
        (Locale('zh', 'CN'), '关闭 top.v'),
      ];
      for (final (locale, text) in expected) {
        final s = await _stringsFor(tester, locale);
        expect(s.closeTabTooltipFor('top.v'), text, reason: '$locale');
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('the scroll-chevron tooltips are overridden, not inherited', (
      tester,
    ) async {
      // `scrollTabsLeftTooltip` / `scrollTabsRightTooltip` are the only two
      // members of `ViewerTabBarStrings` with an English default — they were
      // added after four products already subclassed it. A missing override
      // therefore compiles and ships English into every locale, which no other
      // member of this interface can do. Assert the ARB is actually reached.
      for (final locale in const [Locale('ja'), Locale('ko'), Locale('zh')]) {
        final s = await _stringsFor(tester, locale);
        expect(
          s.scrollTabsLeftTooltip,
          isNot('Scroll tabs left'),
          reason: 'inherited the shared English default in $locale',
        );
        expect(
          s.scrollTabsRightTooltip,
          isNot('Scroll tabs right'),
          reason: 'inherited the shared English default in $locale',
        );
      }
    });
  });
}
