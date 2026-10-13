// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:ui' show PointMode;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/models/layout/edge_route.dart';
import 'package:netcrux/features/viewer/rendering/overview_batch.dart';

void main() {
  group('OverviewRectBatch', () {
    test('a rectangle below the floor grows to it from its top-left', () {
      final batch = OverviewRectBatch()
        ..add(const Rect.fromLTWH(10, 20, 8, 8), Colors.red, floor: 1000);
      expect(batch.length, 1);
      expect(batch.rectAt(0), const Rect.fromLTWH(10, 20, 1000, 1000));
      expect(batch.colorAt(0).toARGB32(), Colors.red.toARGB32());
    });

    test('a rectangle above the floor keeps its own size on each side', () {
      final batch = OverviewRectBatch()
        ..add(const Rect.fromLTWH(0, 0, 60, 4), Colors.blue, floor: 10);
      expect(batch.rectAt(0), const Rect.fromLTWH(0, 0, 60, 10));
    });

    test('grows past its initial capacity and keeps every rectangle', () {
      final batch = OverviewRectBatch(2);
      for (var i = 0; i < 100; i++) {
        batch.add(Rect.fromLTWH(i * 10.0, 0, 8, 8), Color(0xFF000000 | i));
      }
      expect(batch.length, 100);
      for (var i = 0; i < 100; i++) {
        expect(batch.rectAt(i), Rect.fromLTWH(i * 10.0, 0, 8, 8));
        expect(batch.colorAt(i), Color(0xFF000000 | i));
      }
    });

    test('paints every rectangle with one drawVertices call, none when '
        'empty', () {
      final canvas = TestRecordingCanvas();
      OverviewRectBatch().paint(canvas);
      expect(canvas.invocations, isEmpty);

      final batch = OverviewRectBatch();
      for (var i = 0; i < 50; i++) {
        batch.add(Rect.fromLTWH(i * 10.0, 0, 8, 8), Colors.green);
      }
      batch.paint(canvas);
      expect(canvas.invocations, hasLength(1));
      expect(canvas.invocations.single.invocation.memberName, #drawVertices);
    });
  });

  group('OverviewLineBatch', () {
    test('a polyline becomes one segment per consecutive pair', () {
      final batch = OverviewLineBatch()
        ..addPolyline(const <LayoutPoint>[
          LayoutPoint(0, 0),
          LayoutPoint(10, 0),
          LayoutPoint(10, 5),
          LayoutPoint(30, 5),
        ]);
      expect(batch.length, 3);
    });

    test('grows past its initial capacity', () {
      final batch = OverviewLineBatch(1);
      for (var i = 0; i < 300; i++) {
        batch.addSegment(i.toDouble(), 0, i + 1.0, 0);
      }
      expect(batch.length, 300);
    });

    test('strokes every segment with one drawRawPoints call, none when '
        'empty', () {
      final canvas = TestRecordingCanvas();
      final paint = Paint()..strokeWidth = 1;
      OverviewLineBatch().paint(canvas, paint);
      expect(canvas.invocations, isEmpty);

      final batch = OverviewLineBatch();
      for (var i = 0; i < 40; i++) {
        batch.addSegment(0, i.toDouble(), 10, i.toDouble());
      }
      batch.paint(canvas, paint);
      expect(canvas.invocations, hasLength(1));
      final call = canvas.invocations.single.invocation;
      expect(call.memberName, #drawRawPoints);
      expect(call.positionalArguments.first, PointMode.lines);
      expect(call.positionalArguments[1], hasLength(40 * 4));
    });
  });
}
