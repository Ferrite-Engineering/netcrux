// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crux_ide_layout/crux_ide_layout.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:netcrux/domain/models/netlist/netlist_model.dart';
import 'package:netcrux/domain/models/project/netcrux_project.dart';
import 'package:netcrux/domain/models/schematic/schematic_graph.dart';
import 'package:netcrux/domain/models/selection/selected_element.dart';
import 'package:netcrux/domain/models/selection/selection.dart';
import 'package:netcrux/domain/models/session/netcrux_session.dart';
import 'package:netcrux/features/hierarchy/providers/hierarchy_tree_notifier.dart';
import 'package:netcrux/features/project/providers/current_laid_out_graph_provider.dart';
import 'package:netcrux/features/project/providers/current_project_provider.dart';
import 'package:netcrux/features/project/providers/loaded_netlist_provider.dart';
import 'package:netcrux/features/viewer/providers/selected_element_notifier.dart';
import 'package:netcrux/features/viewer/providers/trace_overlay_notifier.dart';
import 'package:netcrux/features/viewer/providers/viewport_transform_notifier.dart';
import 'package:netcrux/features/viewer/rendering/schematic_painter.dart';
import 'package:netcrux/l10n/generated/app_localizations.dart';
import 'package:netcrux/services/session/bookmark_annotation_store_provider.dart';

/// Bridges the file picker with the session model and the viewer
/// providers.
///
/// Save: snapshots every per-canvas provider into a [NetcruxSession]
/// and writes it as pretty-printed JSON. Load: parses the JSON, dispatches
/// elaboration via [currentProjectProvider], and once elaboration settles
/// restores scope, expanded scopes, selection and camera (see [apply]).
///
/// The controller reads through a raw [ProviderContainer] rather than
/// a [WidgetRef] so callers from outside the tab's widget tree (the
/// workspace-screen command dispatcher, the CLI / `--session` launch
/// intent) can resolve the active tab's per-tab providers by handing
/// in the corresponding tab container.
class SessionController {
  /// Creates a controller.
  const SessionController({
    required this.container,
    required this.messenger,
    required this.l10n,
  });

  /// The container the controller reads / writes providers through.
  /// Pass the active tab's container so per-tab state (project,
  /// hierarchy, selection, viewport, …) round-trips correctly.
  final ProviderContainer container;

  /// Surface for success/failure snackbars.
  final ScaffoldMessengerState messenger;

  /// Localized strings.
  final L10N l10n;

  /// Asks the user for a destination path then writes the session to
  /// disk. Re-uses the elaborated model and current viewer state.
  ///
  /// Returns the path written, or `null` when the user cancelled the picker or
  /// the write failed. Both failures already explain themselves to the user
  /// through a snackbar; the return value exists because the CALLER has a
  /// reason to know — the workspace dispatcher records a `session.saved` audit
  /// event, and an audit line for a save that did not happen is worse than no
  /// line, because it is the one an investigation would trust.
  Future<String?> saveAs() async {
    final path = await FilePicker.saveFile(
      // file_picker 12 requires bytes & writes the file; pass empty so it
      // only returns the chosen path and we write the session JSON ourselves.
      bytes: Uint8List(0),
      dialogTitle: l10n.sessionSaveDialogTitle,
      fileName: 'session.${NetcruxSession.fileExtension}',
      lockParentWindow: true,
    );
    if (path == null) return null;
    return await saveToPath(path) ? path : null;
  }

  /// Snapshots the live viewer state and writes it to [path] directly —
  /// no OS file dialog involved. This is the picker-free counterpart to
  /// [saveAs] (which resolves a path via the platform save dialog and
  /// delegates here), mirroring the split elsewhere in the workspace
  /// layer between a dialog-driven menu action and a plain path-based
  /// method (e.g. `NetcruxWorkspaceNotifier.saveAs(path)` /
  /// `.loadFrom(path)`). Tests call this directly, the same way
  /// workspace round-trip tests drive the notifier's path-based methods
  /// instead of the static platform picker (which isn't unit/integration
  /// drivable — see `SchematicExportController`'s test-file note).
  /// Returns whether the write succeeded. See [saveAs] for why the outcome is
  /// returned rather than only shown.
  Future<bool> saveToPath(String path) async {
    try {
      final session = _snapshot();
      const encoder = JsonEncoder.withIndent('  ');
      await File(path).writeAsString(encoder.convert(session.toJson()));
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
      return true;
    } on Object catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(l10n.sessionLoadFailed(e.toString())),
          behavior: SnackBarBehavior.floating,
          duration: kCruxErrorSnackDuration,
        ),
      );
      return false;
    }
  }

  /// Asks the user for a source path then loads the session.
  Future<void> openPicker() async {
    final result = await FilePicker.pickFiles(
      dialogTitle: l10n.sessionOpenDialogTitle,
      type: FileType.custom,
      allowedExtensions: <String>[NetcruxSession.fileExtension],
      lockParentWindow: true,
    );
    final path = result?.files.single.path;
    if (path == null) return;
    await openByPath(path);
  }

  /// Reads and parses the `.netcrux` session at [path].
  ///
  /// Throws [NetcruxSessionVersionException] for a version this build cannot
  /// read, and a [FileSystemException], [FormatException] or
  /// [NetcruxSessionFormatException] for a file that is missing or is not a
  /// session. Static so a caller can open a session into a tab it has yet to
  /// create — the tab's source list comes from the session.
  static Future<NetcruxSession> readSession(String path) async {
    final raw = await File(path).readAsString();
    final json = jsonDecode(raw);
    if (json is! Map<String, Object?>) {
      throw const NetcruxSessionFormatException('not a JSON object');
    }
    return NetcruxSession.fromJson(json);
  }

  /// Loads the session at [path] and applies its state.
  Future<void> openByPath(String path) async {
    try {
      final session = await readSession(path);
      await apply(session);
    } on NetcruxSessionVersionException catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(l10n.sessionLoadUnknownVersion(e.version)),
          behavior: SnackBarBehavior.floating,
          duration: kCruxErrorSnackDuration,
        ),
      );
    } on Object catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(l10n.sessionLoadFailed(e.toString())),
          behavior: SnackBarBehavior.floating,
          duration: kCruxErrorSnackDuration,
        ),
      );
    }
  }

  /// Captures the live state into a [NetcruxSession].
  NetcruxSession _snapshot() {
    final tree = container.read(hierarchyTreeProvider);
    final selection = container.read(selectedElementProvider);
    final overlay = container.read(traceOverlayProvider);
    final transform = container.read(viewportTransformProvider);
    final model = container.read(loadedNetlistProvider).value;
    final project = container.read(currentProjectProvider);
    // Pro bookmarks + annotations live in the active store. Open-core
    // resolves to NoopBookmarkAnnotationStore which yields an empty
    // snapshot → bookmarks and annotations fields stay empty in the
    // emitted JSON (readable by builds that predate bookmarks).
    final marks = container.read(bookmarkAnnotationStoreProvider).snapshot();
    return NetcruxSession(
      version: NetcruxSession.currentVersion,
      sourceFilePaths: project.sourceFiles,
      topModule: model?.topModule?.name ?? '',
      scopePath: tree.selected?.path ?? const <String>[],
      zoom: transform.zoom,
      panX: transform.offset.dx,
      panY: transform.offset.dy,
      // Persist the full multi-selection (primary + elements). Older
      // sessions wrote a single-element record under the same key; the
      // reader falls back to that shape via [Selection.single].
      selectionJson: _selectionToJson(selection),
      overlayMode: overlay.mode?.name,
      expandedScopeKeys: tree.expandedKeys.toList(),
      bookmarks: marks.bookmarks,
      annotations: marks.annotations,
    );
  }

  /// Applies [session] to this controller's tab: its design, then its view.
  ///
  /// The view waits for the design. The scope and expanded rows name
  /// instances of the elaborated netlist, and elaboration is a subprocess
  /// that takes far longer than a frame, so they are applied only once the
  /// tab's netlist has resolved — and the model is pushed into the hierarchy
  /// first, so the tab's own model listener, which would reset the tree to the
  /// root, finds it already there. When the design cannot be elaborated the
  /// tab shows why, and only the selection and camera, which need no model,
  /// are applied.
  ///
  /// The camera is handed to the canvas to reinstate when the restored
  /// scope's layout lands, instead of the fit-to-view a new layout otherwise
  /// gets. Completes once everything that can be applied has been.
  Future<void> apply(NetcruxSession session) async {
    // 1. Restore the project — triggers elaboration. The top module is part
    //    of what was elaborated, so it is restored with the sources.
    container
        .read(currentProjectProvider.notifier)
        .setProject(
          NetcruxProject.create(
            sourceFiles: session.sourceFilePaths,
            topModule: session.topModule,
          ),
        );
    // Pro bookmarks + annotations name elements by path and need no model.
    // Open-core resolves to NoopBookmarkAnnotationStore, which silently
    // ignores writes.
    final store = container.read(bookmarkAnnotationStoreProvider)..clear();
    session.bookmarks.forEach(store.addBookmark);
    session.annotations.forEach(store.addAnnotation);

    final camera = ViewportTransform(
      zoom: SchematicViewportLimits.clampZoom(session.zoom),
      offset: Offset(session.panX, session.panY),
    );
    final selection = _selectionFromJson(session.selectionJson);

    // 2. Wait for the design.
    final before = container.read(hierarchyTreeProvider);
    NetlistModel? model;
    try {
      model = await container.read(loadedNetlistProvider.future);
    } on Object {
      model = null;
    }
    final viewport = container.read(viewportTransformProvider.notifier);
    if (model == null) {
      container.read(selectedElementProvider.notifier).replace(selection);
      viewport.restore(camera);
      return;
    }

    // 3. Scope and expansion, on the model this tab now shows.
    final tree = container.read(hierarchyTreeProvider.notifier);
    if (!identical(container.read(hierarchyTreeProvider).model, model)) {
      tree.setModel(model);
    }
    tree
      ..selectByPath(session.scopePath)
      ..restoreExpanded(session.expandedScopeKeys);
    container.read(selectedElementProvider.notifier).replace(selection);

    // 4. The camera belongs to the saved scope. If the scope no longer
    //    resolves, the canvas fits the scope it did land on instead.
    final after = container.read(hierarchyTreeProvider);
    final landed = after.selected?.path ?? const <String>[];
    if (!_samePath(landed, session.scopePath)) return;
    final layoutUnchanged =
        identical(before.model, after.model) &&
        before.selected == after.selected &&
        container.read(currentLaidOutGraphProvider).hasValue;
    if (layoutUnchanged) {
      // The canvas already shows this scope and will not lay out again.
      viewport.restore(camera);
    } else {
      viewport.requestRestore(landed, camera);
    }
    // The trace overlay is not restored: overlayMode is informational, and
    // the overlay is recomputed when the user re-issues the trace.
  }

  static bool _samePath(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  /// Converts a [Selection] into a JSON object the session can
  /// persist. Returns `null` when [Selection.isEmpty] so the JSON
  /// stays small for the common case.
  ///
  /// The serialized shape is compatible with the original
  /// single-element format: a primary element record at the top
  /// level, with an `elements` array for the multi-select tail.
  /// Older sessions that only carry the single-element shape are
  /// read back as a single-element [Selection.single].
  Map<String, Object?>? _selectionToJson(Selection selection) {
    if (selection.isEmpty) return null;
    final primary = _elementToJson(selection.primary);
    if (primary == null) return null;
    final extras = <Map<String, Object?>>[];
    for (final element in selection.elements) {
      if (element == selection.primary) continue;
      final encoded = _elementToJson(element);
      if (encoded != null) extras.add(encoded);
    }
    if (extras.isEmpty) return primary;
    return <String, Object?>{
      ...primary,
      'elements': extras,
    };
  }

  /// Round-trips a single [SelectedElement] to JSON. Returns `null`
  /// for the none sentinel.
  Map<String, Object?>? _elementToJson(SelectedElement element) {
    switch (element) {
      case SelectedElementNone():
        return null;
      case SelectedElementCell(:final cellId):
        return <String, Object?>{'kind': 'cell', 'cellId': cellId};
      case SelectedElementPort(:final cellId, :final portId, :final portName):
        return <String, Object?>{
          'kind': 'port',
          'cellId': cellId,
          'portId': portId,
          'portName': portName,
        };
      case SelectedElementBoundaryPort(:final portId, :final portName):
        return <String, Object?>{
          'kind': 'boundaryPort',
          'portId': portId,
          'portName': portName,
        };
      case SelectedElementWire(:final edgeId, :final netId):
        return <String, Object?>{
          'kind': 'wire',
          'edgeId': edgeId,
          'netId': netId,
          'edgeIdScheme': _perNetEdgeIdScheme,
        };
    }
  }

  /// Reads a JSON record produced by [_selectionToJson] back into a
  /// [Selection]. Tolerates the older single-element shape.
  Selection _selectionFromJson(Map<String, Object?>? json) {
    if (json == null) return Selection.empty;
    final primary = _elementFromJson(json);
    if (primary.isNone) return Selection.empty;
    final extras = json['elements'];
    if (extras is! List) return Selection.single(primary);
    final elements = <SelectedElement>{primary};
    for (final entry in extras) {
      if (entry is! Map) continue;
      final element = _elementFromJson(
        entry.map<String, Object?>(
          (k, v) => MapEntry<String, Object?>(k.toString(), v),
        ),
      );
      if (element.isNone) continue;
      elements.add(element);
    }
    return Selection(elements: elements, primary: primary);
  }

  /// The `edgeIdScheme` a wire record carries when its edge id counts
  /// within the net (`netEdgeId`).
  static const String _perNetEdgeIdScheme = 'per-net';

  SelectedElement _elementFromJson(Map<String, Object?>? json) {
    if (json == null) return const SelectedElement.none();
    switch (json['kind']) {
      case 'cell':
        final id = json['cellId'] as String?;
        if (id == null) return const SelectedElement.none();
        return SelectedElement.cell(cellId: id);
      case 'port':
        final cellId = json['cellId'] as String?;
        final portId = json['portId'] as String?;
        final portName = json['portName'] as String?;
        if (cellId == null || portId == null || portName == null) {
          return const SelectedElement.none();
        }
        return SelectedElement.port(
          cellId: cellId,
          portId: portId,
          portName: portName,
        );
      case 'boundaryPort':
        final portId = json['portId'] as String?;
        final portName = json['portName'] as String?;
        if (portId == null || portName == null) {
          return const SelectedElement.none();
        }
        return SelectedElement.boundaryPort(
          portId: portId,
          portName: portName,
        );
      case 'wire':
        final edgeId = json['edgeId'] as String?;
        final netId = json['netId'] as int?;
        if (edgeId == null || netId == null) {
          return const SelectedElement.none();
        }
        // A record without the scheme marker was written when the edge id
        // counted across the whole module, so its id may name another wire
        // or none. Its net id is still right, so the net's first edge is
        // selected: the same net, and on a net with one driver the same
        // driver and sinks in the inspector.
        if (json['edgeIdScheme'] != _perNetEdgeIdScheme && netId >= 0) {
          return SelectedElement.wire(
            edgeId: netEdgeId(netId, 0),
            netId: netId,
          );
        }
        return SelectedElement.wire(edgeId: edgeId, netId: netId);
      default:
        return const SelectedElement.none();
    }
  }
}
