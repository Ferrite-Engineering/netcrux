// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/services/export/raster_edu_mark.dart';

/// A [width] x [height] image filled with opaque red.
Future<ui.Image> _red(int width, int height) {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawRect(
    ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    ui.Paint()..color = const ui.Color(0xFFFF0000),
  );
  final picture = recorder.endRecording();
  return picture.toImage(width, height);
}

/// The RGBA bytes of pixel ([x], [y]).
List<int> _pixel(ByteData rgba, int width, int x, int y) {
  final offset = (y * width + x) * 4;
  return [for (var i = 0; i < 4; i++) rgba.getUint8(offset + i)];
}

void main() {
  test('paints the mark in the bottom-right corner and nowhere else', () async {
    final source = await _red(600, 120);
    final stamped = await stampEduExportMark(
      source,
      'Made with NetCrux Educational · Non-commercial use only',
      pixelRatio: 2,
    );
    expect(stamped.width, 600);
    expect(stamped.height, 120);
    final rgba = (await stamped.toByteData())!;

    // Inside the plate: in from the corner margin (6 px at 2x = 12) and
    // clear of its rounded corner.
    final corner = _pixel(rgba, 600, 600 - 24, 120 - 16);
    expect(corner, isNot(<int>[255, 0, 0, 255]));
    // The top-left is untouched.
    expect(_pixel(rgba, 600, 2, 2), <int>[255, 0, 0, 255]);
    // So is the margin outside the plate.
    expect(_pixel(rgba, 600, 600 - 2, 120 - 2), <int>[255, 0, 0, 255]);

    source.dispose();
    stamped.dispose();
  });
}
