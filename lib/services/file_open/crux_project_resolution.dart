// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:crux_project/crux_project.dart';
import 'package:path/path.dart' as p;

/// The `<design>.crux-project` `artifacts:` key NetCrux consumes.
///
/// The key lives here rather than in `crux_project` on purpose: artifact kinds
/// are opaque strings in the shared package, because "netlist" is NetCrux's
/// domain vocabulary and crux-shared's domain-neutrality rule keeps
/// single-product nouns out of shared code.
const String kNetlistArtifactKind = 'netlist';

/// The manifest file name to give the design in [directory]: the directory's
/// own name with the suite extension, or `design.crux-project` for a
/// filesystem root.
///
/// Relative paths are made absolute first, so `.` suggests the name of the
/// working directory rather than `..crux-project`.
String suggestedCruxProjectFileName(String directory) {
  final absolute = p.normalize(p.absolute(directory));
  final stem = absolute == p.rootPrefix(absolute) ? '' : p.basename(absolute);
  return '${stem.isEmpty ? 'design' : stem}.$kCruxProjectExtension';
}

/// The outcome of pointing NetCrux at a path that might designate a
/// `<design>.crux-project` manifest: the manifest file itself, or the design
/// directory holding it.
///
/// NetCrux differs from its siblings in one way that shapes this type: it can
/// act on **either** a pre-built netlist or a list of RTL sources it
/// elaborates itself. A manifest that names sources but no netlist is a
/// perfectly good NetCrux project, so "no netlist" is not a refusal.
sealed class CruxProjectResolution {
  const CruxProjectResolution();
}

/// The path was not a manifest — open it as an ordinary project or session.
class NotAManifest extends CruxProjectResolution {
  /// Creates the pass-through outcome.
  const NotAManifest(this.path);

  /// The path, unchanged.
  final String path;
}

/// The manifest named a pre-built netlist and it is on disk.
class ManifestNetlist extends CruxProjectResolution {
  /// Creates the netlist outcome.
  const ManifestNetlist({
    required this.manifestPath,
    required this.netlistPath,
    required this.designId,
    required this.displayName,
    this.legacyRenameTo,
    this.warnings = const <String>[],
  });

  /// The manifest file that was read — the path itself, or the one manifest
  /// inside the directory the path named.
  final String manifestPath;

  /// The netlist file to load.
  final String netlistPath;

  /// CXP design id, derived from the manifest's directory.
  final String designId;

  /// The manifest's human label.
  final String displayName;

  /// The file name to rename a manifest read by the legacy bare
  /// `.crux-project` name to, or null for a named manifest.
  final String? legacyRenameTo;

  /// Non-fatal parse warnings worth surfacing once. The legacy file-name
  /// notice is not among them: it is [legacyRenameTo], so the caller can
  /// localize it.
  final List<String> warnings;
}

/// The manifest named RTL sources for NetCrux to elaborate.
class ManifestSources extends CruxProjectResolution {
  /// Creates the elaborate-these outcome.
  const ManifestSources({
    required this.manifestPath,
    required this.sources,
    required this.designId,
    required this.displayName,
    this.top,
    this.legacyRenameTo,
    this.warnings = const <String>[],
  });

  /// The manifest file that was read — the path itself, or the one manifest
  /// inside the directory the path named.
  final String manifestPath;

  /// Resolved source paths, in declaration order.
  final List<String> sources;

  /// The declared top module, when the manifest names one.
  final String? top;

  /// CXP design id, derived from the manifest's directory.
  final String designId;

  /// The manifest's human label.
  final String displayName;

  /// The file name to rename a manifest read by the legacy bare
  /// `.crux-project` name to, or null for a named manifest.
  final String? legacyRenameTo;

  /// Non-fatal parse warnings worth surfacing once. The legacy file-name
  /// notice is not among them: it is [legacyRenameTo], so the caller can
  /// localize it.
  final List<String> warnings;
}

/// Why a manifest has nothing NetCrux can open.
enum ManifestUnusableReason {
  /// The file is not a valid `<design>.crux-project` manifest.
  invalid,

  /// The manifest names an `artifacts.netlist` file that is not on disk.
  netlistMissing,

  /// The manifest names neither `design.sources` nor a netlist.
  nothingToOpen,

  /// The path is a directory with no manifest in it.
  noManifestInDirectory,
}

/// The path was a manifest but there is nothing here for NetCrux.
///
/// Carries a typed [reason] and its [detail] rather than a sentence, so the
/// caller renders a localized message.
class ManifestUnusable extends CruxProjectResolution {
  /// Creates the refusal outcome.
  const ManifestUnusable(this.reason, this.detail);

  /// What is wrong with the manifest.
  final ManifestUnusableReason reason;

  /// The value the message interpolates: the parser's diagnostic for
  /// [ManifestUnusableReason.invalid], the netlist path as written for
  /// [ManifestUnusableReason.netlistMissing], the manifest's display name
  /// for [ManifestUnusableReason.nothingToOpen], and the directory for
  /// [ManifestUnusableReason.noManifestInDirectory].
  final String detail;
}

/// The path was a directory holding more than one manifest.
///
/// A design directory holds exactly one manifest. NetCrux refuses to pick
/// one, because whichever lost would describe the design differently and the
/// user may not know it is stale.
class ManifestAmbiguous extends CruxProjectResolution {
  /// Creates the ambiguous-directory outcome.
  const ManifestAmbiguous({required this.directory, required this.candidates});

  /// The directory that was searched.
  final String directory;

  /// Every manifest found in [directory], as full paths, sorted.
  final List<String> candidates;
}

/// Resolves a possible manifest path, or a design directory, to what NetCrux
/// should elaborate.
class CruxProjectResolver {
  /// Creates a resolver.
  const CruxProjectResolver({
    this.parser = const CruxProjectParser(),
  });

  /// The manifest parser. Injectable for tests.
  final CruxProjectParser parser;

  CruxProjectOpenPlanner get _planner => const CruxProjectOpenPlanner();

  /// Resolves [path]: a `<design>.crux-project` file (or the legacy bare
  /// `.crux-project`), a directory holding exactly one of those, or anything
  /// else, which passes through as [NotAManifest].
  CruxProjectResolution resolve(
    String path, {
    bool Function(String path)? exists,
  }) {
    final String? manifestPath;
    try {
      manifestPath = CruxProjectParser.locate(path);
    } on CruxProjectAmbiguousException catch (e) {
      return ManifestAmbiguous(
        directory: e.directory,
        candidates: e.candidates,
      );
    }
    if (manifestPath == null) {
      return FileSystemEntity.isDirectorySync(path)
          ? ManifestUnusable(ManifestUnusableReason.noManifestInDirectory, path)
          : NotAManifest(path);
    }

    final CruxProjectManifest manifest;
    try {
      manifest = parser.parseFile(manifestPath);
    } on CruxProjectFormatException catch (e) {
      return ManifestUnusable(ManifestUnusableReason.invalid, e.message);
    }

    // The parser records the legacy file name as its first warning, in
    // English. NetCrux shows its own localized notice instead, so that
    // warning is carried as a typed field and dropped from the list.
    final legacy = CruxProjectParser.isLegacyManifestPath(manifestPath);
    final legacyRenameTo = legacy
        ? suggestedCruxProjectFileName(manifest.directory)
        : null;
    final warnings = legacy
        ? List<String>.unmodifiable(manifest.warnings.skip(1))
        : manifest.warnings;

    final plan = _planner.plan(
      manifest,
      kind: kNetlistArtifactKind,
      includeSources: true,
      exists: exists,
    );

    final netlist = plan.artifactPath;
    if (netlist != null) {
      return ManifestNetlist(
        manifestPath: manifestPath,
        netlistPath: netlist,
        designId: plan.designId,
        displayName: manifest.displayName,
        legacyRenameTo: legacyRenameTo,
        warnings: warnings,
      );
    }

    // A named-but-missing netlist is worth reporting even when sources exist:
    // the user asked for that file, and silently elaborating instead would
    // hide a stale build.
    if (plan.refusal == CruxOpenRefusal.pathMissing) {
      return ManifestUnusable(
        ManifestUnusableReason.netlistMissing,
        manifest.rawArtifacts[kNetlistArtifactKind] ?? '',
      );
    }

    if (plan.sources.isNotEmpty) {
      return ManifestSources(
        manifestPath: manifestPath,
        sources: plan.sources,
        top: plan.top,
        designId: plan.designId,
        displayName: manifest.displayName,
        legacyRenameTo: legacyRenameTo,
        warnings: warnings,
      );
    }

    return ManifestUnusable(
      ManifestUnusableReason.nothingToOpen,
      manifest.displayName,
    );
  }
}
