// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:netcrux/domain/enums/netcrux_source_language.dart';
import 'package:netcrux/domain/models/project/netcrux_project.dart';
import 'package:path/path.dart' as p;

/// Resolves a project's relative file references against the directory
/// holding its `.netcrux-project` file.
///
/// A `.netcrux-project` is a *version-controllable* description of a
/// design, so the paths inside it have to be relative for the file to
/// survive being committed and opened on another machine. Relative paths
/// only mean something once they are anchored: the Yosys subprocess
/// resolves a bare `alu.v` against its own working directory, which for a
/// GUI launched from Finder or a desktop launcher is unrelated to wherever
/// the project file lives. Anchoring here is what lets a project be shared
/// at all — a project authored with relative paths and handed to the
/// elaboration pipeline unanchored fails with "No such file", naming a path
/// the user can see is present.
///
/// [projectDir] is the directory containing the project file, not the
/// project file itself. Absolute entries keep their location (a project may
/// legitimately point at a shared IP directory outside its own tree);
/// relative entries are joined to [projectDir]. Both are normalized, so
/// `../../test/fixtures/verilog/adder4.v` collapses to a real absolute path
/// and `..` segments never reach Yosys.
///
/// Normalized, not canonicalized: `p.canonicalize` also lowercases on
/// Windows, and these strings are the project's source list, shown to the
/// user, handed to Yosys and written back into the workspace. A comparison
/// key belongs in the comparison (`canonicalPathKey` from `crux_io`), never
/// in the value. [pathContext] selects the path style, so a test can hold
/// Windows spelling to that rule from any host.
///
/// [NetcruxProject.sourceFileLanguages] is keyed by the same strings that
/// appear in [NetcruxProject.sourceFiles], so its keys are rewritten in
/// step. Leaving them behind would silently drop every per-file language
/// override the moment paths were anchored, sending VHDL through the
/// Verilog reader.
///
/// The Vivado filelist importer performs the equivalent anchoring against
/// the `.f` file's own directory — see `FilelistReader`.
NetcruxProject resolveProjectPaths(
  NetcruxProject project,
  String projectDir, {
  p.Context? pathContext,
}) {
  final context = pathContext ?? p.context;
  String resolve(String path) => context.normalize(
    context.absolute(
      context.isAbsolute(path) ? path : context.join(projectDir, path),
    ),
  );

  final sourceFiles = <String>[for (final f in project.sourceFiles) resolve(f)];
  final includePaths = <String>[
    for (final d in project.includePaths) resolve(d),
  ];
  final languages = <String, NetcruxSourceLanguage>{
    for (final entry in project.sourceFileLanguages.entries)
      resolve(entry.key): entry.value,
  };

  return project.copyWith(
    sourceFiles: sourceFiles,
    includePaths: includePaths,
    sourceFileLanguages: languages,
  );
}
