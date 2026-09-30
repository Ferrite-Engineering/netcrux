// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_io/crux_io.dart';
import 'package:crux_workspace/crux_workspace.dart';
import 'package:netcrux/domain/models/workspace/netcrux_tab_payload.dart';

/// NetCrux's implementation of [`WorkspaceCodec<NetcruxTabPayload>`].
///
/// Serializes / deserializes the per-tab payload (source list, top module,
/// scope path, selection, overlay mode, expansion set, viewport) to and from
/// the flattened tab map that `crux_workspace` stores inside
/// `workspace.json`. Framework keys (`id`, `displayName`, `paneId`) are
/// supplied by the framework and must not be emitted here.
///
/// **Failure mode.** Strict per-field validation throws [FormatException]
/// when a required field is missing or has the wrong type — the framework
/// [`WorkspaceService.load`] catches the exception and falls back to
/// [`Workspace.empty()`], matching WaveCrux's precedent. Unknown keys are
/// silently ignored for forward compatibility.
class NetcruxWorkspaceCodec extends WorkspaceCodec<NetcruxTabPayload> {
  /// Creates the codec — stateless singleton.
  const NetcruxWorkspaceCodec();

  @override
  int get schemaVersion => 1;

  @override
  Map<String, Object?> payloadToJson(NetcruxTabPayload p) {
    return <String, Object?>{
      'sourceFiles': p.sourceFiles,
      if (p.topModule.isNotEmpty) 'topModule': p.topModule,
      if (p.projectFilePath != null) 'projectFilePath': p.projectFilePath,
      if (p.scopePath.isNotEmpty) 'scopePath': p.scopePath,
      if (p.expandedScopeKeys.isNotEmpty) 'expandedScopes': p.expandedScopeKeys,
      if (p.selectionJson != null) 'selection': p.selectionJson,
      if (p.overlayMode != null) 'overlayMode': p.overlayMode,
      if (p.zoom != 1.0) 'zoom': p.zoom,
      if (p.panX != 0.0) 'panX': p.panX,
      if (p.panY != 0.0) 'panY': p.panY,
      if (p.sessionExportPath != null) 'sessionExportPath': p.sessionExportPath,
    };
  }

  @override
  NetcruxTabPayload payloadFromJson(Map<String, Object?> json) {
    final rawSources = json['sourceFiles'];
    if (rawSources is! List) {
      throw const FormatException(
        'NetcruxTabPayload: missing or non-list "sourceFiles"',
      );
    }
    final sources = <String>[];
    for (final entry in rawSources) {
      if (entry is! String) {
        throw const FormatException(
          'NetcruxTabPayload: "sourceFiles" entries must be strings',
        );
      }
      sources.add(entry);
    }

    final scopeRaw = json['scopePath'];
    final scopePath = <String>[];
    if (scopeRaw is List) {
      for (final entry in scopeRaw) {
        if (entry is! String) {
          throw const FormatException(
            'NetcruxTabPayload: "scopePath" entries must be strings',
          );
        }
        scopePath.add(entry);
      }
    } else if (scopeRaw != null) {
      throw const FormatException(
        'NetcruxTabPayload: "scopePath" must be a list when present',
      );
    }

    final expandedRaw = json['expandedScopes'];
    final expandedKeys = <String>[];
    if (expandedRaw is List) {
      for (final entry in expandedRaw) {
        if (entry is! String) {
          throw const FormatException(
            'NetcruxTabPayload: "expandedScopes" entries must be strings',
          );
        }
        expandedKeys.add(entry);
      }
    } else if (expandedRaw != null) {
      throw const FormatException(
        'NetcruxTabPayload: "expandedScopes" must be a list when present',
      );
    }

    final selectionRaw = json['selection'];
    Map<String, Object?>? selectionJson;
    if (selectionRaw is Map<String, Object?>) {
      selectionJson = Map<String, Object?>.unmodifiable(selectionRaw);
    } else if (selectionRaw != null) {
      throw const FormatException(
        'NetcruxTabPayload: "selection" must be a JSON object when present',
      );
    }

    final overlayRaw = json['overlayMode'];
    if (overlayRaw != null && overlayRaw is! String) {
      throw const FormatException(
        'NetcruxTabPayload: "overlayMode" must be a string when present',
      );
    }

    final projectPathRaw = json['projectFilePath'];
    if (projectPathRaw != null && projectPathRaw is! String) {
      throw const FormatException(
        'NetcruxTabPayload: "projectFilePath" must be a string when present',
      );
    }

    final sessionExportRaw = json['sessionExportPath'];
    if (sessionExportRaw != null && sessionExportRaw is! String) {
      throw const FormatException(
        'NetcruxTabPayload: "sessionExportPath" must be a string when present',
      );
    }

    final topModuleRaw = json['topModule'];
    if (topModuleRaw != null && topModuleRaw is! String) {
      throw const FormatException(
        'NetcruxTabPayload: "topModule" must be a string when present',
      );
    }

    return NetcruxTabPayload(
      sourceFiles: List<String>.unmodifiable(sources),
      topModule: (topModuleRaw as String?) ?? '',
      projectFilePath: projectPathRaw as String?,
      scopePath: List<String>.unmodifiable(scopePath),
      expandedScopeKeys: List<String>.unmodifiable(expandedKeys),
      selectionJson: selectionJson,
      overlayMode: overlayRaw as String?,
      zoom: _asDouble(json['zoom'], 'zoom') ?? 1.0,
      panX: _asDouble(json['panX'], 'panX') ?? 0.0,
      panY: _asDouble(json['panY'], 'panY') ?? 0.0,
      sessionExportPath: sessionExportRaw as String?,
    );
  }

  @override
  String displayNameFor(NetcruxTabPayload p) => p.derivedDisplayName;

  /// Canonical identity of [p] — see [`WorkspaceCodec.identityOf`]. Two open
  /// tabs whose payloads produce the same non-null identity are one thing, so
  /// re-opening it focuses the existing tab instead of appending a second copy.
  ///
  /// A [NetcruxTabPayload] carries **two** identity-bearing fields
  /// ([NetcruxTabPayload.projectFilePath] and
  /// [NetcruxTabPayload.sourceFiles]), which forces an explicit rule:
  ///
  /// * **Project tab** — [NetcruxTabPayload.projectFilePath] set. Identity is
  ///   that file's [canonicalPathKey]. The source list and top module are
  ///   *derived* from the project file, so the file alone settles the
  ///   question; a project edited between launches is still the same project.
  /// * **Source-file tab** — no project file, [NetcruxTabPayload.sourceFiles]
  ///   non-empty. Identity is the **set** of canonical source path keys,
  ///   sorted, so it does not depend on the order the paths arrived in. A
  ///   shell glob, a filelist, and a multi-select file picker each impose
  ///   their own ordering that NetCrux does not control; keying on that order
  ///   would reintroduce the accumulate-one-tab-per-launch defect this method
  ///   exists to close.
  ///
  /// Deliberately **not** folded together:
  ///
  /// * **A project tab and a source-file tab naming the same file.** These are
  ///   different views of the design, not the same view opened twice: the
  ///   project tab carries the project's top-module override and its full
  ///   source list, the source-file tab is the bare file with auto-detection.
  ///   The `project:` / `sources:` prefixes keep them apart by construction,
  ///   so no path spelling can ever collide the two namespaces.
  /// * **Overlapping but unequal source sets.** Identity is exact set
  ///   equality. Adding or removing one file changes what elaborates and what
  ///   the canvas draws, so a superset is a different design, not a reopen of
  ///   the same one. Treating a subset as a hit would silently swallow the
  ///   user's request to look at the larger set.
  /// * **A payload with no path at all** — the "+" new-tab payload
  ///   ([NetcruxTabPayload.empty]) returns `null`, per the framework contract,
  ///   so a second blank tab stays openable.
  /// * **View state** — top module, scope path, expansion set, selection,
  ///   overlay mode, viewport, session-export path. Every one of them is
  ///   mutable inside the tab, and identity has to hold against tabs
  ///   rehydrated from `workspace.json` on the next launch.
  ///
  /// Paths go through [canonicalPathKey] rather than being compared raw (URLs
  /// excepted — see [_locationKey]): a
  /// relative CLI argument, a `..` segment, a trailing separator, a symlink
  /// (`/tmp` → `/private/tmp` on macOS) and a case difference on a
  /// case-insensitive volume all name one file, and each of those spellings
  /// otherwise presents as a duplicate tab that returns every launch.
  @override
  String? identityOf(NetcruxTabPayload p) {
    final projectPath = p.projectFilePath?.trim() ?? '';
    if (projectPath.isNotEmpty) {
      return '$_projectIdentityPrefix${_locationKey(projectPath)}';
    }

    final keys = <String>{};
    for (final file in p.sourceFiles) {
      if (file.trim().isEmpty) continue;
      final key = _locationKey(file);
      if (key.isEmpty) continue;
      keys.add(key);
    }
    if (keys.isEmpty) return null;
    final sorted = keys.toList()..sort();
    return '$_sourcesIdentityPrefix${sorted.join(_identitySeparator)}';
  }

  /// The comparison key for a tab's [location]: [canonicalPathKey] for a
  /// file path, the trimmed string itself for a URL.
  ///
  /// A URL — the web viewer's `?json=` netlist, a browser upload's `blob:` —
  /// is not a file-system path. On a desktop build, canonicalizing one would
  /// make it absolute against the working directory, collapse its dot
  /// segments and fold its case on a case-insensitive platform, changing what
  /// it names, so any build keys a URL verbatim. In
  /// the browser [canonicalPathKey] already answers the trimmed location with
  /// its case preserved, so every location there is keyed verbatim too.
  static String _locationKey(String location) {
    final trimmed = location.trim();
    final scheme = Uri.tryParse(trimmed)?.scheme ?? '';
    // A one-letter scheme is a Windows drive letter, not a URL.
    if (scheme.length > 1) return trimmed;
    return canonicalPathKey(trimmed);
  }

  /// Namespace for identities derived from a `.netcrux-project` file.
  static const String _projectIdentityPrefix = 'project:';

  /// Namespace for identities derived from a raw source-file set.
  static const String _sourcesIdentityPrefix = 'sources:';

  /// Joiner for the members of a source-set identity. NUL is the one byte no
  /// filesystem path can contain, so no combination of file names can forge
  /// the identity of a different set.
  static const String _identitySeparator = '\u0000';

  static double? _asDouble(Object? raw, String field) {
    if (raw == null) return null;
    if (raw is num) return raw.toDouble();
    throw FormatException(
      'NetcruxTabPayload: "$field" must be numeric when present',
    );
  }
}
