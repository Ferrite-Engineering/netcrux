// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// The painting half of `tool/render_schematic.dart` (not a real test). The
// tool elaborates the design and runs this file under `flutter test`, which
// has the Flutter engine the painter needs, with the request in the
// NETCRUX_RENDER define: base64url of a JSON object with `netlist` (a Yosys
// JSON file), `scope`, `out` (.svg or .png), `zoom`, `region`, `theme`
// (`dark` or `light`) and `font` (a .ttf for the labels, optional).
//
// Without the define, as in the ordinary test run, it is skipped.

import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/core/theme/netcrux_theme.dart';
import 'package:netcrux/features/viewer/rendering/schematic_painter.dart';
import 'package:netcrux/features/viewer/services/svg_export_palette_from_theme.dart';
import 'package:netcrux/services/export/scope_render.dart';
import 'package:netcrux/services/export/svg_exporter.dart';
import 'package:netcrux/services/layout/native_elk_solver.dart';
import 'package:netcrux/services/yosys/streaming_yosys_json_reader.dart';

const String _request = String.fromEnvironment('NETCRUX_RENDER');

Map<String, Object?> _decodeRequest() =>
    jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(_request))))
        as Map<String, Object?>;

void main() {
  testWidgets('render a schematic scope', skip: _request.isEmpty, (
    tester,
  ) async {
    final request = _decodeRequest();
    final out = File(request['out']! as String);
    final zoom = (request['zoom'] as num?)?.toDouble() ?? 1.0;
    final regionText = request['region'] as String?;
    final region = regionText == null ? null : parseRenderRegion(regionText);

    final model = await tester.runAsync(
      () async => const StreamingYosysJsonReader().parse(
        await File(request['netlist']! as String).readAsString(),
      ),
    );
    final node = scopeAtPath(model!, (request['scope'] as String?) ?? '');
    final solver = NativeElkSolver.open();
    final laidOut = layOutScope(model, node, solver.solve);
    solver.dispose();
    final frame = renderFrame(laidOut, region: region);
    final base = request['theme'] == 'light'
        ? NetcruxTheme.light()
        : NetcruxTheme.dark();

    if (out.path.toLowerCase().endsWith('.svg')) {
      await tester.runAsync(() async {
        await out.parent.create(recursive: true);
        await out.writeAsString(
          const SvgExporter().toSvg(
            laidOut,
            frame: frame,
            palette: svgExportPaletteFromTheme(base),
          ),
        );
      });
      return;
    }

    final pixels = renderPixelSize(frame, zoom);
    final size = Size(pixels.width.toDouble(), pixels.height.toDouble());
    await tester.binding.setSurfaceSize(size);
    tester.view
      ..physicalSize = size
      ..devicePixelRatio = 1;
    addTearDown(() async {
      tester.view.reset();
      await tester.binding.setSurfaceSize(null);
    });

    // flutter_test draws text in the Ahem placeholder font, every glyph a
    // block; a real font makes the labels legible.
    final fontPath = request['font'] as String?;
    var labelFamily = '';
    if (fontPath != null && File(fontPath).existsSync()) {
      final bytes = File(fontPath).readAsBytesSync();
      final loader = FontLoader('RenderLabel')
        ..addFont(Future<ByteData>.value(ByteData.sublistView(bytes)));
      await tester.runAsync(loader.load);
      labelFamily = 'RenderLabel';
    }
    final theme = labelFamily.isEmpty
        ? base
        : base.copyWith(
            textTheme: base.textTheme.apply(fontFamily: labelFamily),
          );

    final key = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: theme,
        home: RepaintBoundary(
          key: key,
          child: SizedBox.fromSize(
            size: size,
            child: SchematicCanvas(
              laidOut: laidOut,
              transform: ViewportTransform(
                zoom: zoom,
                offset: Offset(-frame.x * zoom, -frame.y * zoom),
              ),
              statsSink: const NoopRenderStatsSink(),
              theme: theme,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);

    await tester.runAsync(() async {
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage();
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      await out.parent.create(recursive: true);
      await out.writeAsBytes(data!.buffer.asUint8List());
    });
  });
}
