// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_license/crux_license.dart';
import 'package:netcrux/core/policy/netcrux_policy_keys.dart';
import 'package:netcrux/domain/enums/netcrux_design_source.dart';
import 'package:netcrux/domain/models/project/netcrux_project.dart';
import 'package:path/path.dart' as p;
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'current_project_provider.g.dart';

/// The active [NetcruxProject] for the currently focused tab.
///
/// Holds the elaboration backend's input — source file list, top
/// module, defines, include paths, plus Yosys engine knobs. The
/// elaboration pipeline ([`loadedNetlistProvider`]) watches this
/// provider; the file watcher watches its `sourceFiles`; the
/// session snapshot reads it.
///
/// Declared at root and re-bound per tab by `netcrux_tab_overrides.dart`
/// (mirrors WaveCrux). Writes are idempotent (the elaboration backend
/// doesn't rerun when the same project is set twice).
///
/// Default value: [NetcruxProject.empty] — no project open. The
/// welcome screen renders the empty-canvas state in that case.
@Riverpod(keepAlive: true)
class CurrentProject extends _$CurrentProject {
  @override
  NetcruxProject build() => NetcruxProject.empty;

  /// Which entry path put [state] here — the `source` dimension of the
  /// `design.elaborated` counter.
  ///
  /// A plain field rather than part of the state for two reasons. It must not
  /// travel into [NetcruxProject], because a project is the durable,
  /// version-controllable description of a design and "the user picked this
  /// from a filelist on this machine" is not a property of the design. And it
  /// must not make the notifier's state change: folding it in would give
  /// `currentProjectProvider` a second identity axis, so opening the same
  /// sources by two routes would re-run the whole elaboration pipeline for a
  /// difference nothing but a counter can see.
  ///
  /// Read (never watched) by `LoadedNetlist.build`, which is already reading
  /// the project this describes. Defaults to [NetcruxDesignSource.rtl] — the
  /// path every caller that does not say otherwise is on.
  NetcruxDesignSource activeSource = NetcruxDesignSource.rtl;

  /// Replaces the active project with [project]. No-op when the
  /// new project equals the current state — protects against
  /// thrashing the elaboration backend when the same project is
  /// reloaded.
  ///
  /// [source] records how the project arrived; see [activeSource]. It is
  /// updated even on the equal-project early return, because re-opening the
  /// same design from a `.netcrux-project` after having opened its files
  /// directly is still a project open.
  void setProject(
    NetcruxProject project, {
    NetcruxDesignSource source = NetcruxDesignSource.rtl,
  }) {
    activeSource = source;
    // Recorded even on the equal-project early return, and for the same reason
    // `activeSource` is updated there: re-opening the same design from a
    // `.netcrux-project` after having opened its files directly IS a project
    // open, and an audit trail that skipped it would under-report exactly the
    // repeat access an investigation is looking for.
    ref
        .read(cruxAuditRecorderProvider)
        .record(
          NetCruxAuditKinds.schematicOpened,
          payload: <String, Object?>{
            'source': source.name,
            'fileCount': project.sourceFiles.length,
            // Which design, not where it lives: a source path carries the
            // user's home directory, and this file is read by whoever runs
            // the organization's log shipper.
            'topModule': project.topModule,
            // The netlist-JSON route recorded
            // `{"source":"rtl","fileCount":1,"topModule":""}` — which names
            // nothing. `topModule` is empty because this audit is written
            // inside `setProject`, before elaboration resolves a top, and on
            // that route elaboration never runs at all. An Enterprise audit
            // trail exists to answer *which design did this person open*, and
            // there it answered *a design was opened*.
            //
            // A basename closes it without reopening the privacy problem
            // the excluded path exists to avoid: it identifies the file while
            // the home directory, the username inside the path and the
            // machine's layout stay out of a log that gets forwarded.
            // `soc_top.json` is an answer; the absolute path is a disclosure.
            // The same rule is applied to LintCrux's `waiver.created` and
            // WaveCrux's `session.saved` payloads.
            //
            // Only when nothing better is present, and only when one file
            // makes it unambiguous. With a top module the identity is already
            // recorded, and across several sources no single basename is the
            // design — `fileCount` already says how many there are, and
            // guessing "the first one" would name a design that was never
            // opened.
            if (project.topModule.isEmpty && project.sourceFiles.length == 1)
              'design': p.basename(project.sourceFiles.single),
          },
        );
    if (state == project) return;
    state = project;
  }

  /// Convenience: install a project that wraps [sourceFiles] with
  /// the documented defaults. Used by the "Open Source Files…"
  /// welcome-screen flow and by the CLI launch intent so a freshly-
  /// dropped file list becomes a real project without the caller
  /// having to import the model.
  void setSourceFiles(List<String> sourceFiles) {
    setProject(NetcruxProject.create(sourceFiles: sourceFiles));
  }

  /// Clears the project back to [NetcruxProject.empty]. Used by
  /// "Close Project" and on disposal of the project screen so a
  /// subsequent welcome navigation lands on the empty-canvas state.
  void clear() {
    activeSource = NetcruxDesignSource.rtl;
    if (state == NetcruxProject.empty) return;
    state = NetcruxProject.empty;
  }
}
