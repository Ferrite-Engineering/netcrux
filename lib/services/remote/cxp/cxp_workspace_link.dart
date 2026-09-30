// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_cxp/crux_cxp.dart';
import 'package:crux_workspace/crux_workspace.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:netcrux/domain/models/project/netcrux_project.dart';
import 'package:netcrux/domain/models/workspace/netcrux_tab_payload.dart';
import 'package:netcrux/features/settings/providers/app_settings_provider.dart';
import 'package:netcrux/services/workspace/netcrux_workspace_notifier.dart';
import 'package:path/path.dart' as p;

/// The shared-workspace artifact kind NetCrux **produces** (the producer side).
///
/// NetCrux's primary design input is HDL source, so on opening a design it
/// upserts a `source` record keyed by the design's INPUT directory — letting a
/// peer that receives a cross-probe naming the same design open NetCrux's
/// source even when it had nothing loaded.
const String kCxpSourceArtifactKind = 'source';

/// NetCrux's producer short-name stamped into workspace records.
const String kNetcruxWorkspaceProducer = 'netcrux';

/// The directories the user has opened, as CXP §11's containment rule
/// consumes them.
///
/// Two sources, both "the user opened this":
///
/// * every open tab: the containing directory of each source file loaded
///   into it, and of the project file or manifest it was opened from; and
/// * the recent lists on the start screen: the containing directory of
///   every recent project (which also records manifests, sessions, and a
///   design opened by path), recent source file and recent named workspace.
///   Each is a file the user picked in this installation.
///
/// The recent lists are what make the rule useful as well as safe. The
/// `crux.design_id` fallback a highlight or selection takes when its element
/// is not in the open design exists to open a design NetCrux does *not* have
/// open: WaveCrux, LintCrux and SimCrux attach the design id to every
/// cross-probe. Rooted on open tabs alone, the rule refused the one case that
/// route serves; with the recent lists, a design whose tab was closed can be
/// reopened by a peer, as in the other products. A design never opened in
/// this installation is still refused there.
///
/// `request_open_artifact` is not rooted at all: see
/// [kCxpOpenArtifactContainment] for why it is held to the floor.
///
/// Read on every containment check rather than snapshotted when the server
/// starts, so a design opened after CXP came up is one the user opened. The
/// settings load asynchronously; until they have, the open tabs alone
/// apply.
Iterable<String> cxpOpenDirectories(Ref ref) {
  final roots = <String>{};
  void addDirectoryOf(String file) {
    // A browser build records blob URLs and loads by URL; neither is a
    // directory on this machine.
    if (file.isNotEmpty && p.isAbsolute(file)) roots.add(p.dirname(file));
  }

  final workspace = ref.read(netcruxWorkspaceProvider).value;
  for (final tab
      in workspace?.tabs ?? const <WorkspaceTab<NetcruxTabPayload>>[]) {
    tab.payload.sourceFiles.forEach(addDirectoryOf);
    final projectFile = tab.payload.projectFilePath;
    if (projectFile != null) addDirectoryOf(projectFile);
  }
  final settings = ref.read(appSettingsProvider).value;
  if (settings != null) {
    settings.recentProjectPaths.forEach(addDirectoryOf);
    settings.recentSourceFilePaths.forEach(addDirectoryOf);
    settings.recentWorkspacePaths.forEach(addDirectoryOf);
  }
  return roots;
}

/// The rooted [CxpPathContainment]: a peer-supplied path must lie inside
/// [cxpOpenDirectories].
///
/// One instance, so the routes that keep the roots apply the *same* rule,
/// which is what CXP §11 requires of an artifact resolved through our own
/// records: [cxpWorkspaceStoreProvider] screens what it resolves for the
/// `crux.design_id` fallback, and `CxpInboundHandler` checks once more on
/// the value it is about to load from that fallback or hand to an editor
/// argv (`request_open_source`, and a `request_highlight` of a `source`
/// element).
///
/// `request_open_artifact` is held to [kCxpOpenArtifactContainment] instead,
/// and so is `LocalCxpServer`'s screen of the wire, because that one rule
/// covers the artifact request's hint as well as `request_open_source`.
final Provider<CxpPathContainment> cxpPathContainmentProvider =
    Provider<CxpPathContainment>(
      (ref) => CxpPathContainment(roots: () => cxpOpenDirectories(ref)),
    );

/// The rule a `request_open_artifact` is held to: CXP §11.3's floor, and
/// not the directories the user has opened.
///
/// The floor refuses what a path must never be on its way into a load: empty,
/// relative (resolved against whatever directory NetCrux was launched from),
/// carrying a NUL, or padded with white space. It judges the exact string the
/// caller is about to load, so a padded path is refused rather than trimmed
/// into a different file.
///
/// It is not rooted, because on this route a rooted rule is secure and
/// useless at once. `request_open_artifact` exists to open a design NetCrux
/// does not have open: the VS Code extension's "Open in NetCrux Desktop"
/// sends it for the HDL file the user is editing, which is, as often as not,
/// a design this installation has never seen. Rooted on the open tabs and
/// the recent lists, the rule refused exactly the request the route serves,
/// and the roots bought nothing to pay for that:
///
/// * the sender is already a same-user process. Since CXP 1.2 a peer must
///   present the per-process token NetCrux publishes in its manifest, which
///   only a process that can read this user's application data can do, and
///   such a process can already read any file NetCrux could be asked to
///   load;
/// * NetCrux only parses what this route loads. Yosys reads the file as HDL
///   and elaborates it; nothing in it is executed, and what comes of it is a
///   schematic drawn in the user's own window.
///
/// WaveCrux took the same decision for the hand-off that opens a waveform a
/// peer names, which is held to the floor alone.
///
/// The roots stay where they still buy something ([cxpPathContainmentProvider]):
/// the `crux.design_id` fallback resolves an id a peer attached to a
/// cross-probe through store records nobody asked NetCrux to open, and
/// `request_open_source` hands its path to an editor command line.
const CxpPathContainment kCxpOpenArtifactContainment = CxpPathContainment();

/// Where [cxpWorkspaceStoreProvider] keeps the shared workspace: `null`, the
/// default, is the suite-shared per-user directory
/// (`sharedCxpWorkspaceDirectory()`).
///
/// Tests point it at a temp directory. That keeps them out of the user's real
/// workspace while still running the production store provider — rule and
/// all — which overriding the store itself would skip.
final Provider<String?> cxpWorkspaceDirectoryProvider = Provider<String?>(
  (ref) => null,
);

/// The shared design→artifact link store.
///
/// A single keep-alive instance rooted at [cxpWorkspaceDirectoryProvider].
///
/// Carries [cxpPathContainmentProvider] so a record written by a peer — the
/// workspace directory is user-writable, and the sender chose the `design_id`
/// that selects the record — cannot name a file outside the directories this
/// process has open (CXP §11). `request_open_artifact` reads the same records
/// under its own rule instead: see [resolveOpenArtifactSourcePath].
final Provider<CxpWorkspaceStore> cxpWorkspaceStoreProvider =
    Provider<CxpWorkspaceStore>(
      (ref) => CxpWorkspaceStore(
        workspaceDirectory: ref.watch(cxpWorkspaceDirectoryProvider),
        containment: ref.watch(cxpPathContainmentProvider),
      ),
    );

/// The shared CXP `design_id` for the currently-open design in [project], or
/// null when no source is loaded.
///
/// Derived from the design's **input** directory — the directory containing
/// the first loaded source file — via the one shared [cxpDesignIdForPath]
/// helper every product uses, so NetCrux, SimCrux, and WaveCrux key the same
/// design folder identically.
String? cxpDesignIdForProject(NetcruxProject project) {
  if (project.sourceFiles.isEmpty) return null;
  return cxpDesignIdForPath(project.sourceFiles.first);
}

/// Records NetCrux's loaded HDL source in the shared workspace so a peer that
/// receives a cross-probe it cannot satisfy locally can resolve and open this
/// design's source (the producer side).
///
/// Keyed by [designId], which callers derive from the design's **input**
/// directory via [cxpDesignIdForProject] — the same join key NetCrux attaches
/// to its outbound `crux.design_id` metadata.
///
/// Gated on [serverRunning], which the caller resolves from the feature-layer
/// `cxpServerHostProvider`: with CXP off there is no peer to serve and no
/// reason to write into the shared workspace directory — which also keeps
/// the wide swath of open/elaborate tests from writing into the real
/// per-user workspace.
/// Best-effort throughout: a failed upsert must never break a load.
Future<void> publishDesignSourceArtifact(
  ProviderContainer container, {
  required bool serverRunning,
  required String designId,
  required String sourcePath,
  String? topModule,
}) async {
  if (!serverRunning) return;
  if (designId.isEmpty || sourcePath.isEmpty) return;
  try {
    await container
        .read(cxpWorkspaceStoreProvider)
        .upsertArtifact(
          designId: designId,
          kind: kCxpSourceArtifactKind,
          path: sourcePath,
          producer: kNetcruxWorkspaceProducer,
          topModule: (topModule == null || topModule.isEmpty)
              ? null
              : topModule,
          basename: p.basename(sourcePath),
        );
  } on Object {
    // The shared workspace is a courtesy link; never let a workspace write
    // surface as an error on the design-load path.
  }
}

/// Resolves the shared-workspace `source` artifact for the design named by
/// [designId] (consumer-side resolution), preferring an exact `design_id`+kind
/// match and falling back to the descriptive [topModule]/[basename] hints.
///
/// Returns the absolute path NetCrux should open, or null when the design has
/// no source artifact recorded.
String? resolveDesignSourceArtifactPath(
  ProviderContainer container,
  String designId, {
  String? topModule,
  String? basename,
}) {
  if (designId.isEmpty) return null;
  final artifact = container
      .read(cxpWorkspaceStoreProvider)
      .resolveArtifact(
        designId,
        kCxpSourceArtifactKind,
        topModule: topModule,
        basename: basename,
      );
  return artifact?.path;
}

/// Resolves the `source` artifact recorded for [designId] the way
/// `request_open_artifact` needs it: the records [cxpWorkspaceStoreProvider]
/// reads, from the same directory, admitted by [kCxpOpenArtifactContainment]
/// rather than by the rooted rule that store carries.
///
/// Reading them through the rooted store would drop the record for a design
/// NetCrux has never opened, and the request would be refused as though
/// nothing were recorded — the failure [kCxpOpenArtifactContainment]
/// explains. The store keeps no state between reads, so a second view of the
/// directory costs nothing.
///
/// Returns the absolute path NetCrux should open, or null when the design has
/// no source artifact recorded.
String? resolveOpenArtifactSourcePath(
  ProviderContainer container,
  String designId,
) {
  if (designId.isEmpty) return null;
  final store = container.read(cxpWorkspaceStoreProvider);
  return CxpWorkspaceStore(
    workspaceDirectory: store.workspaceDirectory,
    ttl: store.ttl,
    containment: kCxpOpenArtifactContainment,
  ).resolveArtifact(designId, kCxpSourceArtifactKind)?.path;
}
