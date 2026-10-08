// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:meta/meta.dart';
import 'package:netcrux/domain/models/annotation.dart';
import 'package:netcrux/domain/models/bookmark.dart';

/// On-disk representation of a NetCrux viewer session.
///
/// Captures everything required to reconstitute the viewer to the
/// exact state the user had open: source-file list, current scope,
/// camera, selection, trace overlay, and expanded scopes. The schema
/// is forward-compatible — unknown fields are silently ignored on
/// load, and the [version] integer lets future renames swap the
/// reader path.
///
/// Pure data, no Flutter imports — lives under `lib/domain/models/`.
@immutable
class NetcruxSession {
  /// Creates a session.
  const NetcruxSession({
    required this.version,
    required this.sourceFilePaths,
    required this.topModule,
    required this.scopePath,
    required this.zoom,
    required this.panX,
    required this.panY,
    required this.selectionJson,
    required this.overlayMode,
    required this.expandedScopeKeys,
    this.bookmarks = const <Bookmark>[],
    this.annotations = const <Annotation>[],
  });

  /// Parses a session document. Rejects unknown versions with a
  /// [NetcruxSessionVersionException]; unknown fields are tolerated.
  factory NetcruxSession.fromJson(Map<String, Object?> json) {
    final v = json['version'] as int?;
    if (v == null) {
      throw const NetcruxSessionFormatException(
        'missing "version" field',
      );
    }
    if (v != currentVersion) {
      throw NetcruxSessionVersionException(v);
    }
    final sources = json['sourceFiles'];
    final paths = sources is List
        ? sources.whereType<String>().toList(growable: false)
        : const <String>[];
    final scopePathRaw = json['scopePath'];
    final scopePath = scopePathRaw is List
        ? scopePathRaw.whereType<String>().toList(growable: false)
        : const <String>[];
    final expanded = json['expandedScopes'];
    final expandedKeys = expanded is List
        ? expanded.whereType<String>().toList(growable: false)
        : const <String>[];
    final selectionRaw = json['selection'];
    final bookmarksRaw = json['bookmarks'];
    final bookmarks = bookmarksRaw is List
        ? <Bookmark>[
            for (final entry in bookmarksRaw)
              if (entry is Map<String, Object?>) ?Bookmark.fromJson(entry),
          ]
        : const <Bookmark>[];
    final annotationsRaw = json['annotations'];
    final annotations = annotationsRaw is List
        ? <Annotation>[
            for (final entry in annotationsRaw)
              if (entry is Map<String, Object?>) ?Annotation.fromJson(entry),
          ]
        : const <Annotation>[];
    return NetcruxSession(
      version: v,
      sourceFilePaths: paths,
      topModule: (json['topModule'] as String?) ?? '',
      scopePath: scopePath,
      zoom: ((json['zoom'] as num?) ?? 1).toDouble(),
      panX: ((json['panX'] as num?) ?? 0).toDouble(),
      panY: ((json['panY'] as num?) ?? 0).toDouble(),
      selectionJson: selectionRaw is Map<String, Object?> ? selectionRaw : null,
      overlayMode: json['overlayMode'] as String?,
      expandedScopeKeys: expandedKeys,
      bookmarks: bookmarks,
      annotations: annotations,
    );
  }

  /// Schema version, currently `1`. Unknown versions are rejected
  /// at load with a snackbar (see SessionController).
  static const int currentVersion = 1;

  /// File-extension used for session files (and the file picker filter).
  static const String fileExtension = 'netcrux';

  /// Schema version of this session — must equal [currentVersion]
  /// to load.
  final int version;

  /// Absolute paths of the source files that produced the netlist.
  /// Re-opened on load via the same elaboration pipeline.
  final List<String> sourceFilePaths;

  /// Top module name at save time — the elaborated top, which a restore
  /// passes back as the top module when it re-elaborates the sources.
  final String topModule;

  /// Dotted instance-name path of the active scope (e.g. ['u_cpu', 'alu']
  /// for `top.u_cpu.alu`). Empty for the root.
  final List<String> scopePath;

  /// Viewport zoom level.
  final double zoom;

  /// Viewport offset X in canvas pixels.
  final double panX;

  /// Viewport offset Y in canvas pixels.
  final double panY;

  /// Opaque JSON snapshot of the active selection. The actual shape is
  /// decided by [SelectedElement]; the session does not need to know
  /// it (forward compatibility — new variants don't break old loaders).
  /// `null` when nothing is selected.
  final Map<String, Object?>? selectionJson;

  /// Active overlay mode — `'fanin'` / `'fanout'` / `null`. The
  /// overlay is reconstituted from the selection + mode rather than
  /// stored as a set of element ids, because those ids change after
  /// re-elaboration.
  final String? overlayMode;

  /// Expansion-key strings for scopes that were expanded in the
  /// hierarchy tree. Identical encoding to
  /// [HierarchyTreeState.expandedKeys] (instance-name path joined by
  /// `/`).
  final List<String> expandedScopeKeys;

  /// Bookmarks persisted in the session. Empty when the tab has none.
  final List<Bookmark> bookmarks;

  /// Annotations persisted in the session. Empty when the tab has none.
  final List<Annotation> annotations;

  /// Serializes to a forward-compatible JSON map.
  Map<String, Object?> toJson() => <String, Object?>{
    'version': version,
    'sourceFiles': sourceFilePaths,
    'topModule': topModule,
    'scopePath': scopePath,
    'zoom': zoom,
    'panX': panX,
    'panY': panY,
    if (selectionJson != null) 'selection': selectionJson,
    if (overlayMode != null) 'overlayMode': overlayMode,
    'expandedScopes': expandedScopeKeys,
    if (bookmarks.isNotEmpty)
      'bookmarks': [for (final b in bookmarks) b.toJson()],
    if (annotations.isNotEmpty)
      'annotations': [for (final a in annotations) a.toJson()],
  };

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! NetcruxSession) return false;
    if (other.version != version) return false;
    if (other.topModule != topModule) return false;
    if (other.zoom != zoom) return false;
    if (other.panX != panX) return false;
    if (other.panY != panY) return false;
    if (other.overlayMode != overlayMode) return false;
    if (!_listEquals(other.sourceFilePaths, sourceFilePaths)) return false;
    if (!_listEquals(other.scopePath, scopePath)) return false;
    if (!_listEquals(other.expandedScopeKeys, expandedScopeKeys)) return false;
    if (!_mapEquals(other.selectionJson, selectionJson)) return false;
    if (!_listEquals(other.bookmarks, bookmarks)) return false;
    if (!_listEquals(other.annotations, annotations)) return false;
    return true;
  }

  @override
  int get hashCode => Object.hash(
    version,
    topModule,
    zoom,
    panX,
    panY,
    overlayMode,
    Object.hashAll(sourceFilePaths),
    Object.hashAll(scopePath),
    Object.hashAll(expandedScopeKeys),
    selectionJson == null ? 0 : selectionJson!.length,
    Object.hashAll(bookmarks),
    Object.hashAll(annotations),
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

/// Thrown when a session document is malformed.
class NetcruxSessionFormatException implements Exception {
  /// Creates a format-exception.
  const NetcruxSessionFormatException(this.message);

  /// One-line human-readable summary.
  final String message;

  @override
  String toString() => 'NetcruxSessionFormatException: $message';
}

/// Thrown when a session was saved by an unknown schema version.
class NetcruxSessionVersionException implements Exception {
  /// Creates a version-exception.
  const NetcruxSessionVersionException(this.version);

  /// The unknown version integer the file carried.
  final int version;

  @override
  String toString() => 'NetcruxSessionVersionException: version=$version';
}
