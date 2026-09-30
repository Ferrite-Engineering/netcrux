// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/core/license/netcrux_license_badge_strings.dart';
import 'package:netcrux/l10n/generated/app_localizations.dart';

void main() {
  group('NetCruxLicenseBadgeStrings', () {
    Future<NetCruxLicenseBadgeStrings> buildAdapter(
      WidgetTester tester,
      Locale locale,
    ) async {
      late L10N captured;
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
              captured = L10N.of(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      return NetCruxLicenseBadgeStrings(captured);
    }

    testWidgets('English returns the PRO/ENT/EDU label vocabulary', (
      tester,
    ) async {
      final strings = await buildAdapter(tester, const Locale('en'));
      expect(strings.tierBadgePro, 'PRO');
      expect(strings.tierBadgeProSemantic, 'Pro tier feature');
      expect(strings.tierBadgeEnterprise, 'ENT');
      expect(strings.tierBadgeEnterpriseSemantic, 'Enterprise tier feature');
      expect(strings.tierBadgeEdu, 'EDU');
      expect(strings.tierBadgeEduSemantic, 'Educational license');
      expect(tester.takeException(), isNull);
    });

    testWidgets('zh_CN, ja, ko semantic labels are translated', (tester) async {
      final zhCn = await buildAdapter(tester, const Locale('zh', 'CN'));
      expect(zhCn.tierBadgePro, 'PRO');
      expect(zhCn.tierBadgeProSemantic, 'Pro 等级功能');
      expect(zhCn.tierBadgeEduSemantic, '教育版许可');

      final ja = await buildAdapter(tester, const Locale('ja'));
      expect(ja.tierBadgeProSemantic, 'Pro ティア機能');
      expect(ja.tierBadgeEduSemantic, '教育用ライセンス');

      final ko = await buildAdapter(tester, const Locale('ko'));
      expect(ko.tierBadgeProSemantic, 'Pro 등급 기능');
      expect(ko.tierBadgeEduSemantic, '교육용 라이선스');
      expect(tester.takeException(), isNull);
    });

    testWidgets('zh fallback locale mirrors zh_CN translations', (
      tester,
    ) async {
      final zh = await buildAdapter(tester, const Locale('zh'));
      expect(zh.tierBadgePro, 'PRO');
      expect(zh.tierBadgeProSemantic, 'Pro 等级功能');
      expect(zh.tierBadgeEduSemantic, '教育版许可');
      expect(tester.takeException(), isNull);
    });
  });
}
