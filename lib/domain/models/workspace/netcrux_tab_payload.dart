// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;

/// Per-tab persistence payload owned by NetCrux and bound to
/// `crux_workspace`'s generic [`WorkspaceTab<P>`].
///
/// The workspace document only persists the slice of per-tab state needed to
/// re-bind the elaboration backend and restore the user's view on next
/// launch — heavyweight live state (the elaborated [`NetlistModel`], the
/// hierarchy panel's expanded-row set in memory, the active painter
/// transform stream) lives in per-tab Riverpod providers and is rebuilt
/// from this payload + the on-disk source files.
///
/// Schema follows the spirit of the existing [`NetcruxSession`] (per-tab
/// session export shape) so a future "export tab as session" mapping is a
/// field-for-field projection rather than a re-design.
///
/// Pure data, no Flutter imports.
@immutable
class NetcruxTabPayload {
  /// Creates a payload. Caller is responsible for passing absolute (or
  /// project-root-relative) paths — the elaboration pipeline normalises
  /// before use.
  const NetcruxTabPayload({
    required this.sourceFiles,
    this.topModule = '',
    this.projectFilePath,
    this.scopePath = const <String>[],
    this.expandedScopeKeys = const <String>[],
    this.selectionJson,
    this.overlayMode,
    this.zoom = 1.0,
    this.panX = 0.0,
    this.panY = 0.0,
    this.sessionExportPath,
  });

  /// Canonical empty payload — used as the default for "+"-button tabs and
  /// as the post-`closeProject` payload when the user wants to keep the tab
  /// open at the empty-canvas state.
  static const NetcruxTabPayload empty = NetcruxTabPayload(
    sourceFiles: <String>[],
  );

  /// Ordered list of HDL source paths bound to this tab. Drives the
  /// elaboration backend. Empty when the tab has no design loaded (e.g. a
  /// freshly-opened "+" tab whose user has not yet chosen anything).
  final List<String> sourceFiles;

  /// Top module name override; empty string means "auto-detect" (same shape
  /// as [`NetcruxProject.topModule`]).
  final String topModule;

  /// Path to the `.netcrux-project` file or `<design>.crux-project` manifest
  /// the tab was opened from. `null` for tabs opened directly from a
  /// source-file list or from a `.netcrux` session import.
  final String? projectFilePath;

  /// Dotted instance-name path of the active scope (e.g. `['u_cpu', 'alu']`
  /// for `top.u_cpu.alu`). Empty list selects the top module's scope.
  final List<String> scopePath;

  /// Expanded scope keys for the hierarchy panel — uses the same encoding as
  /// [`HierarchyTreeState.expandedKeys`] (instance-name path joined by `/`).
  final List<String> expandedScopeKeys;

  /// Opaque JSON snapshot of the active selection. The actual shape is owned
  /// by [`SelectedElement`]; the payload is forward-compatible — new variants
  /// don't break older readers. `null` when nothing is selected.
  final Map<String, Object?>? selectionJson;

  /// Active overlay mode — `'fanin'` / `'fanout'` / `null`. Reconstructed at
  /// load time by running the trace overlay computation against the restored
  /// selection so element ids that may have changed under re-elaboration are
  /// recomputed rather than stored.
  final String? overlayMode;

  /// Viewport zoom level.
  final double zoom;

  /// Viewport offset X in canvas pixels.
  final double panX;

  /// Viewport offset Y in canvas pixels.
  final double panY;

  /// Path of the last `.netcrux` session this tab was exported to. Used by
  /// the next "Export Tab as Session…" invocation to default the file
  /// picker's destination. `null` when the tab has never been exported.
  final String? sessionExportPath;

  /// Returns a copy with the given fields replaced. Pass `null` for value
  /// fields to leave them; pass explicit empty collections to clear them.
  /// Pass `clearProjectFilePath` / `clearSelection` / `clearOverlayMode` /
  /// `clearSessionExportPath` to set the corresponding field to `null`.
  NetcruxTabPayload copyWith({
    List<String>? sourceFiles,
    String? topModule,
    String? projectFilePath,
    List<String>? scopePath,
    List<String>? expandedScopeKeys,
    Map<String, Object?>? selectionJson,
    String? overlayMode,
    double? zoom,
    double? panX,
    double? panY,
    String? sessionExportPath,
    bool clearProjectFilePath = false,
    bool clearSelection = false,
    bool clearOverlayMode = false,
    bool clearSessionExportPath = false,
  }) {
    return NetcruxTabPayload(
      sourceFiles: sourceFiles == null
          ? this.sourceFiles
          : List<String>.unmodifiable(sourceFiles),
      topModule: topModule ?? this.topModule,
      projectFilePath: clearProjectFilePath
          ? null
          : (projectFilePath ?? this.projectFilePath),
      scopePath: scopePath == null
          ? this.scopePath
          : List<String>.unmodifiable(scopePath),
      expandedScopeKeys: expandedScopeKeys == null
          ? this.expandedScopeKeys
          : List<String>.unmodifiable(expandedScopeKeys),
      selectionJson: clearSelection
          ? null
          : (selectionJson ?? this.selectionJson),
      overlayMode: clearOverlayMode ? null : (overlayMode ?? this.overlayMode),
      zoom: zoom ?? this.zoom,
      panX: panX ?? this.panX,
      panY: panY ?? this.panY,
      sessionExportPath: clearSessionExportPath
          ? null
          : (sessionExportPath ?? this.sessionExportPath),
    );
  }

  /// Best-effort display name derived from the payload. The framework's
  /// `displayName` field is authoritative for tabs that carry one; this is
  /// the fallback the codec hands the framework when an older workspace
  /// document predates `displayName`.
  String get derivedDisplayName {
    if (projectFilePath != null) {
      return p.basenameWithoutExtension(projectFilePath!);
    }
    if (sourceFiles.isNotEmpty) return p.basename(sourceFiles.first);
    return 'Untitled';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! NetcruxTabPayload) return false;
    if (other.topModule != topModule) return false;
    if (other.projectFilePath != projectFilePath) return false;
    if (other.overlayMode != overlayMode) return false;
    if (other.sessionExportPath != sessionExportPath) return false;
    if (other.zoom != zoom) return false;
    if (other.panX != panX) return false;
    if (other.panY != panY) return false;
    if (!_listEquals(other.sourceFiles, sourceFiles)) return false;
    if (!_listEquals(other.scopePath, scopePath)) return false;
    if (!_listEquals(other.expandedScopeKeys, expandedScopeKeys)) return false;
    if (!_mapEquals(other.selectionJson, selectionJson)) return false;
    return true;
  }

  @override
  int get hashCode => Object.hash(
    topModule,
    projectFilePath,
    overlayMode,
    sessionExportPath,
    zoom,
    panX,
    panY,
    Object.hashAll(sourceFiles),
    Object.hashAll(scopePath),
    Object.hashAll(expandedScopeKeys),
    selectionJson == null ? 0 : selectionJson!.length,
  );

  static bool _listEquals<T>(List<T> a, List<T> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  static bool _mapEquals(Map<String, Object?>? a, Map<String, Object?>? b) {
    if (identical(a, b)) return true;
    if (a == null || b == null) return false;
    if (a.length != b.length) return false;
    for (final entry in a.entries) {
      if (!b.containsKey(entry.key)) return false;
      if (b[entry.key] != entry.value) return false;
    }
    return true;
  }
}
