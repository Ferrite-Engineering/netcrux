// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:ui' as ui;

import 'package:crux_license/crux_license.dart';

/// A copy of [image] with [mark] painted in its bottom-right corner, sized
/// for an image captured at [pixelRatio] so the mark reads at the same size
/// as the canvas text it was captured beside.
///
/// The educational-licence mark on a PNG export: the capture is the canvas as
/// the user sees it, so the mark goes on the pixels after capture rather than
/// onto the live canvas. The caller owns both images and disposes them.
Future<ui.Image> stampEduExportMark(
  ui.Image image,
  String mark, {
  double pixelRatio = 1,
}) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder)
    ..drawImage(image, ui.Offset.zero, ui.Paint());
  paintCruxEduExportMark(
    canvas,
    ui.Size(image.width.toDouble(), image.height.toDouble()),
    mark,
    fontSize: 11 * pixelRatio,
    margin: 6 * pixelRatio,
  );
  final picture = recorder.endRecording();
  try {
    return await picture.toImage(image.width, image.height);
  } finally {
    picture.dispose();
  }
}
