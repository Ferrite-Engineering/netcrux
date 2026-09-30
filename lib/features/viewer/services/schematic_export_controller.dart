// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:crux_ide_layout/crux_ide_layout.dart';
import 'package:crux_telemetry/crux_telemetry.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:netcrux/domain/enums/netcrux_export_kind.dart';
import 'package:netcrux/features/hierarchy/providers/hierarchy_tree_notifier.dart';
import 'package:netcrux/features/project/providers/current_laid_out_graph_provider.dart';
import 'package:netcrux/features/project/providers/loaded_netlist_provider.dart';
import 'package:netcrux/l10n/generated/app_localizations.dart';
import 'package:netcrux/services/export/svg_exporter.dart';

/// Resolves the destination path for an export whose suggested file name
/// is [defaultName]. Returns `null` when the user cancels.
typedef SaveLocationPicker = Future<String?> Function(String defaultName);

/// Coordinates the three schematic export flavors (PNG, SVG, JSON).
///
/// PNG comes from the `RenderRepaintBoundary` wrapping the canvas;
/// SVG is generated programmatically from the laid-out graph; JSON
/// re-emits the slice of the underlying Yosys netlist that the
/// current scope covers.
///
/// All three flows pop the OS save-file dialog and surface success /
/// failure as a snackbar so the user has a clear signal that the
/// export landed (or didn't).
///
/// Reads through a [ProviderContainer] rather than a [WidgetRef] so
/// callers from outside the tab widget tree (the workspace-screen
/// command dispatcher) can pass the active tab's container — every
/// per-tab provider (graph, hierarchy, netlist) round-trips
/// correctly.
class SchematicExportController {
  /// Creates an export controller.
  ///
  /// [pickSavePath] defaults to the platform save dialog; tests inject a
  /// resolver so the three export flows can be driven end-to-end without
  /// a `file_picker` static that no test can stand in for (the same
  /// injectable-picker seam `ColorThemeSection` uses).
  SchematicExportController({
    required this.container,
    required this.messenger,
    required this.l10n,
    required this.canvasKey,
    SaveLocationPicker? pickSavePath,
  }) : _pickSavePathOverride = pickSavePath;

  /// Tab-scoped container the controller reads through.
  final ProviderContainer container;

  /// Scaffold messenger used to surface result snackbars.
  final ScaffoldMessengerState messenger;

  /// Localized strings.
  final L10N l10n;

  /// Global key on the `RepaintBoundary` wrapping the canvas. The PNG
  /// path turns its render object into an image. May be `null` when
  /// the export is dispatched from a context that doesn't have access
  /// to the canvas widget (e.g. before the active tab's content has
  /// been mounted) — the PNG flow surfaces a clear "canvas not
  /// mounted" snackbar in that case.
  final GlobalKey? canvasKey;

  final SaveLocationPicker? _pickSavePathOverride;

  /// Exports the current canvas as PNG via [RenderRepaintBoundary.toImage].
  Future<void> exportPng() async {
    // Capture the render object before any async gap so we don't carry
    // BuildContext across the picker await.
    final ctx = canvasKey?.currentContext;
    if (ctx == null) {
      _fail('canvas not mounted');
      return;
    }
    final boundary = ctx.findRenderObject();
    if (boundary is! RenderRepaintBoundary) {
      _fail('canvas not a RepaintBoundary');
      return;
    }
    final path = await _pickSavePath('schematic.png');
    if (path == null) return;
    try {
      final image = await boundary.toImage(pixelRatio: 2);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) {
        _fail('image encode failed');
        return;
      }
      await File(path).writeAsBytes(byteData.buffer.asUint8List());
      _success(NetcruxExportKind.png, path);
    } on Object catch (e) {
      _fail(e.toString());
    }
  }

  /// Exports the current canvas as SVG using [SvgExporter].
  Future<void> exportSvg() async {
    final path = await _pickSavePath('schematic.svg');
    if (path == null) return;
    try {
      final laidOut = container.read(currentLaidOutGraphProvider).value;
      if (laidOut == null || laidOut.isEmpty) {
        _fail('no graph to export');
        return;
      }
      final svg = const SvgExporter().toSvg(laidOut);
      await File(path).writeAsString(svg);
      _success(NetcruxExportKind.svg, path);
    } on Object catch (e) {
      _fail(e.toString());
    }
  }

  /// Exports the current scope's portion of the Yosys netlist as JSON.
  Future<void> exportJson() async {
    final path = await _pickSavePath('schematic.json');
    if (path == null) return;
    try {
      final model = container.read(loadedNetlistProvider).value;
      final node = container.read(hierarchyTreeProvider).selected;
      if (model == null || node == null) {
        _fail('no design loaded');
        return;
      }
      final module = node.resolve(model);
      if (module == null) {
        _fail('scope not resolved');
        return;
      }
      final slice = <String, Object?>{
        'creator': model.creator,
        'modules': <String, Object?>{
          module.name: module.toJson(),
        },
      };
      const encoder = JsonEncoder.withIndent('  ');
      await File(path).writeAsString(encoder.convert(slice));
      _success(NetcruxExportKind.json, path);
    } on Object catch (e) {
      _fail(e.toString());
    }
  }

  Future<String?> _pickSavePath(String defaultName) async {
    final override = _pickSavePathOverride;
    if (override != null) return await override(defaultName);
    return await FilePicker.saveFile(
      // file_picker 12 requires bytes & writes the file; pass empty so it
      // only returns the chosen path and we write the slice JSON ourselves.
      bytes: Uint8List(0),
      dialogTitle: defaultName.endsWith('.json')
          ? l10n.exportDialogJsonTitle
          : l10n.exportDialogSaveTitle,
      fileName: defaultName,
      lockParentWindow: true,
    );
  }

  void _success(NetcruxExportKind kind, String path) {
    // Only the three flows that actually wrote a file reach here — a cancelled
    // picker, an unmounted canvas and an encode failure all return before it,
    // so `export.completed` means completed. `path` is used for the snackbar
    // and nothing else; the event carries the format token and no path.
    container
        .read(telemetryServiceProvider)
        .record(
          TelemetryEvent(
            'export.completed',
            properties: <String, Object?>{'kind': telemetryEnumToken(kind)},
          ),
        );
    messenger.showSnackBar(
      SnackBar(
        content: Text(l10n.exportSuccessMessage(path)),
        behavior: SnackBarBehavior.floating,
        // Canon info duration matches the framework default today; keep it
        // explicit so this surface can't drift from the suite standard.
        // ignore: avoid_redundant_argument_values
        duration: kCruxInfoSnackDuration,
      ),
    );
  }

  void _fail(String reason) {
    messenger.showSnackBar(
      SnackBar(
        content: Text(l10n.exportFailureMessage(reason)),
        behavior: SnackBarBehavior.floating,
        duration: kCruxErrorSnackDuration,
      ),
    );
  }
}
