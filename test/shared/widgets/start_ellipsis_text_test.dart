// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/shared/widgets/start_ellipsis_text.dart';

const _name = 'servant.servile.cpu.alu.add_cy_r_SB_LUT4_I3_1';
const _style = TextStyle(fontSize: 10);

double _width(String text) {
  final painter = TextPainter(
    text: TextSpan(text: text, style: _style),
    textDirection: TextDirection.ltr,
    maxLines: 1,
  )..layout();
  final width = painter.width;
  painter.dispose();
  return width;
}

void main() {
  group('startElidedText', () {
    test('returns text that fits unchanged', () {
      expect(
        startElidedText(_name, style: _style, maxWidth: _width(_name)),
        _name,
      );
      expect(
        startElidedText(_name, style: _style, maxWidth: double.infinity),
        _name,
      );
      expect(startElidedText('', style: _style, maxWidth: 0), '');
    });

    test('keeps the longest tail that fits behind the ellipsis', () {
      const tail = 'add_cy_r_SB_LUT4_I3_1';
      final width = _width('$startEllipsis$tail');
      final shown = startElidedText(_name, style: _style, maxWidth: width);
      expect(shown, '$startEllipsis$tail');
      // One pixel less loses one more character from the front.
      expect(
        startElidedText(_name, style: _style, maxWidth: width - 1),
        '$startEllipsis${tail.substring(1)}',
      );
    });

    test('never exceeds the width it is given', () {
      for (final maxWidth in <double>[30, 55, 120, 200]) {
        final shown = startElidedText(
          _name,
          style: _style,
          maxWidth: maxWidth,
        );
        expect(_width(shown), lessThanOrEqualTo(maxWidth), reason: shown);
        expect(_name.endsWith(shown.substring(1)), isTrue, reason: shown);
      }
    });

    test('cuts between characters, not inside one', () {
      const text = 'cell_\u{1F600}\u{1F600}\u{1F600}_tail';
      final shown = startElidedText(
        text,
        style: _style,
        maxWidth: _width('$startEllipsis\u{1F600}_tail'),
      );
      expect(shown, '$startEllipsis\u{1F600}_tail');
    });
  });

  group('StartEllipsisText', () {
    Future<void> pump(WidgetTester tester, double width) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: width,
                child: const StartEllipsisText(_name, style: _style),
              ),
            ),
          ),
        ),
      );
    }

    String shown(WidgetTester tester) =>
        tester.widget<Text>(find.byType(Text)).data!;

    testWidgets('shows the whole name when there is room', (tester) async {
      await pump(tester, 1000);
      expect(shown(tester), _name);
      expect(tester.takeException(), isNull);
    });

    testWidgets('cuts the start when the box is narrow', (tester) async {
      await pump(tester, 160);
      expect(shown(tester), startsWith(startEllipsis));
      expect(_name.endsWith(shown(tester).substring(1)), isTrue);
      expect(tester.takeException(), isNull);
    });

    testWidgets('re-fits when the box widens', (tester) async {
      await pump(tester, 160);
      final narrow = shown(tester);
      await pump(tester, 320);
      expect(shown(tester).length, greaterThan(narrow.length));
    });
  });
}
