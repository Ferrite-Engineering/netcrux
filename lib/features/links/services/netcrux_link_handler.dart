// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:crux_io/crux_io.dart' show canonicalPathKey;
import 'package:crux_workspace/crux_workspace.dart';
import 'package:flutter/scheduler.dart' show SchedulerBinding;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meta/meta.dart';
import 'package:netcrux/domain/enums/netcrux_design_source.dart';
import 'package:netcrux/domain/models/netlist/netlist_model.dart';
import 'package:netcrux/domain/models/project/netcrux_project.dart';
import 'package:netcrux/domain/models/selection/selected_element.dart';
import 'package:netcrux/domain/models/selection/selection.dart';
import 'package:netcrux/domain/models/workspace/netcrux_tab_payload.dart';
import 'package:netcrux/features/hierarchy/providers/hierarchy_tree_notifier.dart';
import 'package:netcrux/features/project/providers/current_laid_out_graph_provider.dart';
import 'package:netcrux/features/project/providers/current_project_provider.dart';
import 'package:netcrux/features/project/providers/loaded_netlist_provider.dart';
import 'package:netcrux/features/project/providers/scope_layout_gate_provider.dart';
import 'package:netcrux/features/viewer/providers/cone_view_notifier.dart';
import 'package:netcrux/features/viewer/providers/reveal_request_notifier.dart';
import 'package:netcrux/features/viewer/providers/selected_element_notifier.dart';
import 'package:netcrux/features/viewer/services/cone_view_controller.dart';
import 'package:netcrux/features/viewer/services/zoom_to_selection_controller.dart';
import 'package:netcrux/features/workspace/providers/recent_lists.dart';
import 'package:netcrux/features/workspace/services/restored_tab_project.dart';
import 'package:netcrux/services/links/netcrux_link.dart';
import 'package:netcrux/services/links/netcrux_link_target.dart';
import 'package:netcrux/services/remote/cxp/cxp_design_names.dart';
import 'package:netcrux/services/schematic/netlist_element_lookup.dart';
import 'package:netcrux/services/workspace/netcrux_workspace_notifier.dart';
import 'package:netcrux/services/workspace/tab_container_manager_holder.dart';
import 'package:path/path.dart' as p;

/// Asks the user whether to open a file a link named. Resolves true only when
/// they chose to open it.
typedef NetCruxLinkConsent = Future<bool> Function(String path);

/// Frames the selection of a tab once its schematic is laid out.
typedef NetCruxLinkFramer = void Function(ProviderContainer tab);

/// Why a link opened nothing.
enum NetCruxLinkFailure {
  /// The link did not parse. See [NetCruxLinkOutcome.parseRefusal].
  malformed,

  /// The path is not an absolute, well-formed local path.
  pathRefused,

  /// The file is not a design format a link may open.
  notADesign,

  /// The file is not there.
  fileNotFound,

  /// The file opened in a tab, and the tab shows why it could not be read.
  loadFailed,
}

/// What handling a link did, for the caller to tell the user.
@immutable
class NetCruxLinkOutcome {
  /// A link that opened nothing.
  const NetCruxLinkOutcome.failed(
    NetCruxLinkFailure this.failure, {
    this.fileName,
    this.parseRefusal,
  }) : declined = false,
       path = null,
       openedTab = false,
       kind = null,
       name = null,
       elementNotFound = false,
       coneView = false;

  /// A link the user chose not to open.
  const NetCruxLinkOutcome.declined({required String this.path})
    : failure = null,
      declined = true,
      fileName = null,
      parseRefusal = null,
      openedTab = false,
      kind = null,
      name = null,
      elementNotFound = false,
      coneView = false;

  /// A link whose design is now the active tab.
  const NetCruxLinkOutcome.opened({
    required String this.path,
    required this.openedTab,
    this.kind,
    this.name,
    this.elementNotFound = false,
    this.coneView = false,
  }) : failure = null,
       declined = false,
       fileName = null,
       parseRefusal = null;

  /// Why nothing opened, or null when something did or the user declined.
  final NetCruxLinkFailure? failure;

  /// The parser's reason, for [NetCruxLinkFailure.malformed] and a relative
  /// path's [NetCruxLinkFailure.pathRefused].
  final NetCruxLinkRefusal? parseRefusal;

  /// The file's base name, for a failure that names it.
  final String? fileName;

  /// Whether the user cancelled the confirmation.
  final bool declined;

  /// The resolved file, once the link got that far.
  final String? path;

  /// Whether a new tab was created, as opposed to an open one focused.
  final bool openedTab;

  /// Whether the link asked for a cell or a net; null when neither.
  final NetCruxLinkElementKind? kind;

  /// The cell or net the link asked for.
  final String? name;

  /// The link named a cell or net the design does not have (or does not
  /// draw).
  final bool elementNotFound;

  /// The scope holding the element is over the layout limit, so the element
  /// is shown in a Cone View instead of the whole scope.
  final bool coneView;

  /// Whether the design is now open.
  bool get opened => failure == null && !declined;
}

/// Opens what a link names: parses it, vets the file, asks the user when the
/// file is not one they have opened before, then opens the design in a new
/// tab (or focuses the tab that already has it), waits for it to load,
/// selects the cell or net, and fits it in view. A scope over the layout
/// limit (Settings > Performance, `layoutCellLimit`) is not laid out whole:
/// the element is shown in a Cone View, as any selection in such a scope is.
///
/// Never throws, never runs anything the link chooses, never fetches
/// anything. The file must exist, be a design format
/// ([kNetCruxLinkExtensions]) both as named and once symbolic links resolve,
/// and pass the CXP receive floor ([kNetCruxLinkContainment]). The resolved
/// path is what is shown in the confirmation, re-checked after the user
/// answers, and opened.
///
/// [confirm] is asked only for a file that is neither in an open tab nor in a
/// recent list ([wasOpenedBefore]). A design opened from a link is not added
/// to the recent lists, so the answer is not remembered.
///
/// An unknown cell or net still opens the design; the outcome says so.
/// [frame] replaces the framing (Zoom to Selection once the schematic is laid
/// out), for tests. [tabs] replaces the app's tab container manager, also for
/// tests.
Future<NetCruxLinkOutcome> openNetCruxLink(
  ProviderContainer root,
  String raw, {
  required NetCruxLinkConsent confirm,
  NetCruxLinkFramer? frame,
  TabContainerManager? tabs,
}) async {
  final NetCruxLink link;
  switch (parseNetCruxLink(raw)) {
    case NetCruxLinkRejected(:final refusal):
      return NetCruxLinkOutcome.failed(
        refusal == NetCruxLinkRefusal.relativePath
            ? NetCruxLinkFailure.pathRefused
            : NetCruxLinkFailure.malformed,
        parseRefusal: refusal,
      );
    case NetCruxLinkParsed(link: final parsed):
      link = parsed;
  }

  final fileName = _displayName(link.file);
  final String path;
  switch (vetNetCruxLinkTarget(link.file)) {
    case NetCruxLinkTargetRefused(:final refusal):
      return _refused(refusal, fileName);
    case NetCruxLinkTargetAccepted(path: final resolved):
      path = resolved;
  }

  await root.read(netcruxWorkspaceProvider.future);
  // The recent lists fill in the background; asking before they have would
  // count a file the user opened yesterday as new.
  await Future.wait(<Future<void>>[
    root.read(recentSources.provider.notifier).restored,
    root.read(recentProjects.provider.notifier).restored,
  ]);
  final workspaceTabs = _openTabs(root);
  final openedBefore = wasOpenedBefore(
    path,
    openTabPaths: [
      for (final tab in workspaceTabs) ...[
        tab.payload.projectFilePath,
        ...tab.payload.sourceFiles,
      ],
    ],
    recentPaths: [
      ...root.read(recentSources.provider),
      ...root.read(recentProjects.provider),
    ],
  );
  if (!openedBefore) {
    final bool agreed;
    try {
      agreed = await confirm(path);
    } on Object {
      return NetCruxLinkOutcome.declined(path: path);
    }
    if (!agreed) return NetCruxLinkOutcome.declined(path: path);
    // The question may have been on screen for a while. Check again, and
    // open only if the same file is still what the link resolves to.
    switch (vetNetCruxLinkTarget(path)) {
      case NetCruxLinkTargetRefused(:final refusal):
        return _refused(refusal, fileName);
      case NetCruxLinkTargetAccepted(path: final again) when again != path:
        return NetCruxLinkOutcome.failed(
          NetCruxLinkFailure.fileNotFound,
          fileName: fileName,
        );
      case NetCruxLinkTargetAccepted():
        break;
    }
  }

  final manager = tabs ?? root.read(tabContainerManagerHolderProvider).manager;
  if (manager == null) {
    return NetCruxLinkOutcome.failed(
      NetCruxLinkFailure.loadFailed,
      fileName: fileName,
    );
  }
  final ({ProviderContainer tab, bool openedTab}) opened;
  final NetlistModel? model;
  try {
    opened = await _openOrFocus(root, manager, path);
    model = await opened.tab.read(loadedNetlistProvider.future);
  } on Object {
    return NetCruxLinkOutcome.failed(
      NetCruxLinkFailure.loadFailed,
      fileName: fileName,
    );
  }
  if (model == null) {
    return NetCruxLinkOutcome.failed(
      NetCruxLinkFailure.loadFailed,
      fileName: fileName,
    );
  }

  final kind = link.kind;
  final name = link.name;
  if (kind == null || name == null) {
    return NetCruxLinkOutcome.opened(path: path, openedTab: opened.openedTab);
  }
  final placed = placeNetCruxLinkElement(opened.tab, model, kind, name);
  if (placed == null) {
    return NetCruxLinkOutcome.opened(
      path: path,
      openedTab: opened.openedTab,
      kind: kind,
      name: name,
      elementNotFound: true,
    );
  }
  (frame ?? frameNetCruxLinkSelection)(opened.tab);
  return NetCruxLinkOutcome.opened(
    path: path,
    openedTab: opened.openedTab,
    kind: kind,
    name: name,
    coneView: placed.coneView,
  );
}

/// Finds the cell or net [name] in [model], shows its scope in [tab],
/// selects it and asks the canvas to reveal it. Returns null, changing
/// nothing, when the design has no such element or does not draw it.
///
/// [name] is a hierarchical name, its scopes separated by `.`: rooted at the
/// top module (`top.u_cpu.pc_reg`) or written from just below it
/// (`u_cpu.pc_reg`). A rooted name is tried first. Each instance segment
/// walks one level down; what is left once a segment names no child instance
/// is the element's name in that scope, so a flattened name (`u_cpu.pc_reg`
/// as one cell of the top) is found as well. A bit select on a net
/// (`data[3]`) selects the whole net. The name is never matched by its last
/// segment alone in some other scope: a link that names one place opens that
/// place or none.
///
/// When the scope is over the layout limit, a Cone View of the element opens
/// in place of the whole scope, as for any selection in a scope held back for
/// its size; the result says so.
///
/// An editor host's `select` frame goes through here too, so a link opened
/// in the editor's preview finds the same element the desktop app would.
({bool coneView})? placeNetCruxLinkElement(
  ProviderContainer tab,
  NetlistModel model,
  NetCruxLinkElementKind kind,
  String name,
) {
  final tree = tab.read(hierarchyTreeProvider.notifier);
  if (!identical(tab.read(hierarchyTreeProvider).model, model)) {
    tree.setModel(model);
  }
  final top = model.topModule?.name;
  final candidates = <String>[
    name,
    if (top != null && !name.startsWith('$top.')) '$top.$name',
  ];
  for (final candidate in candidates) {
    final scoped = scopeOfHierarchicalName(model, candidate);
    final module = scoped?.scope.resolve(model);
    if (scoped == null || module == null) continue;
    final Selection? selection;
    final String? revealCell;
    switch (kind) {
      case NetCruxLinkElementKind.cell:
        if (!module.cells.containsKey(scoped.leaf) ||
            !schematicDrawsCell(module, scoped.leaf)) {
          continue;
        }
        selection = Selection.single(
          SelectedElement.cell(cellId: scoped.leaf),
        );
        revealCell = scoped.leaf;
      case NetCruxLinkElementKind.net:
        final net = findNetNamed(module, scoped.leaf);
        selection = net == null ? null : selectionForNet(module, net);
        if (selection == null) continue;
        revealCell = switch (selection.primary) {
          SelectedElementCell(:final cellId) => cellId,
          _ => net == null ? null : driverCellOf(module, net),
        };
    }
    tree.selectScope(scoped.scope);
    tab.read(selectedElementProvider.notifier).replace(selection);
    if (revealCell != null) {
      tab.read(revealRequestProvider.notifier).request(revealCell);
    }
    return (coneView: _showConeWhenTooLarge(tab, selection));
  }
  return null;
}

/// Opens a Cone View of [selection]'s primary element when the scope on the
/// canvas is over the layout limit and no cone of it is on show yet. Returns
/// whether the element is shown in a cone.
///
/// The tab content does the same for every selection in a held-back scope
/// (`heldBackSelectionConeProvider`); doing it here as well makes the link's
/// result independent of whether that listener is mounted yet.
bool _showConeWhenTooLarge(ProviderContainer tab, Selection selection) {
  final gate = tab.read(scopeLayoutGateProvider);
  final tooLarge = gate.limit > 0 && gate.cellCount > gate.limit;
  if (!tooLarge || gate.approved) return false;
  final cone = tab.read(coneViewProvider);
  final scope = tab.read(hierarchyTreeProvider).selected;
  if (cone != null && cone.scope == scope && cone.root == selection.primary) {
    return true;
  }
  return ConeViewController(tab.read).enter();
}

/// Frames [tab]'s selection the way Zoom to Selection does: now, when the
/// schematic is laid out, or as soon as it is. The retry waits two frames
/// after the layout lands, so the canvas' own fit of a new layout runs first
/// and does not undo the framing. Gives up after fifteen seconds.
void frameNetCruxLinkSelection(ProviderContainer tab) {
  bool frame() => ZoomToSelectionController(tab).run();
  if (frame()) return;
  ProviderSubscription<Object?>? sub;
  Timer? timer;
  var done = false;

  void cleanup() {
    if (done) return;
    done = true;
    sub?.close();
    timer?.cancel();
  }

  void attempt() {
    if (done) return;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (done) return;
        if (frame()) cleanup();
      });
    });
    SchedulerBinding.instance.scheduleFrame();
  }

  sub = tab.listen<Object?>(currentLaidOutGraphProvider, (_, _) => attempt());
  timer = Timer(const Duration(seconds: 15), cleanup);
  attempt();
}

/// The workspace's tabs, or none before it has loaded.
List<WorkspaceTab<NetcruxTabPayload>> _openTabs(ProviderContainer root) =>
    root.read(netcruxWorkspaceProvider).value?.tabs ??
    const <WorkspaceTab<NetcruxTabPayload>>[];

/// Focuses the tab that already holds [path] (as one of its sources, or as
/// the project it came from), by file identity, or opens a new tab for it,
/// and gives the tab its design when it has none yet.
Future<({ProviderContainer tab, bool openedTab})> _openOrFocus(
  ProviderContainer root,
  TabContainerManager manager,
  String path,
) async {
  final key = canonicalPathKey(path);
  final workspace = root.read(netcruxWorkspaceProvider.notifier);
  for (final tab in _openTabs(root)) {
    final files = <String?>[
      tab.payload.projectFilePath,
      ...tab.payload.sourceFiles,
    ];
    final holds = files.any(
      (file) =>
          file != null && file.isNotEmpty && canonicalPathKey(file) == key,
    );
    if (!holds) continue;
    await workspace.setActiveTab(tab.id);
    final container = manager.containerFor(tab.id);
    await hydrateTabProject(container, tab.payload);
    return (tab: container, openedTab: false);
  }
  final project = NetcruxProject.fromOpenedFiles(<String>[path]);
  final tabId = await workspace.openTab(
    displayName: p.basename(path),
    payload: NetcruxTabPayload(sourceFiles: project.sourceFiles),
  );
  final container = manager.containerFor(tabId);
  if (container.read(currentProjectProvider).sourceFiles.isEmpty) {
    container
        .read(currentProjectProvider.notifier)
        .setProject(
          project,
          source: project.isPrebuiltNetlist
              ? NetcruxDesignSource.netlistJson
              : NetcruxDesignSource.rtl,
        );
  }
  return (tab: container, openedTab: true);
}

NetCruxLinkOutcome _refused(NetCruxLinkTargetRefusal refusal, String name) =>
    switch (refusal) {
      NetCruxLinkTargetRefusal.pathRefused => const NetCruxLinkOutcome.failed(
        NetCruxLinkFailure.pathRefused,
      ),
      NetCruxLinkTargetRefusal.notADesign => NetCruxLinkOutcome.failed(
        NetCruxLinkFailure.notADesign,
        fileName: name,
      ),
      NetCruxLinkTargetRefusal.fileNotFound => NetCruxLinkOutcome.failed(
        NetCruxLinkFailure.fileNotFound,
        fileName: name,
      ),
      NetCruxLinkTargetRefusal.unsupportedPlatform =>
        const NetCruxLinkOutcome.failed(NetCruxLinkFailure.malformed),
    };

/// The base name of a link's path, shortened for a message. A link chooses
/// this text, so it is bounded before it reaches the screen.
String _displayName(String path) {
  final base = p.basename(path.replaceAll(r'\', '/'));
  return base.length <= 80 ? base : '${base.substring(0, 77)}...';
}

/// Holds links until the app can act on them, and handles them one at a time.
///
/// Nothing is handled before [markReady]: a link that launched the app waits
/// for the launch intent and the workspace restore, so a tab it asks for is
/// matched against the restored tabs. While one link is being handled (its
/// confirmation may be on screen, or its design elaborating), only the newest
/// link to arrive is kept; the ones in between are dropped, so a page that
/// fires a burst of links raises at most one more question.
class NetCruxLinkInbox {
  /// Creates an inbox that hands each link to [handle].
  NetCruxLinkInbox(this._handle);

  final Future<void> Function(String raw) _handle;
  bool _ready = false;
  bool _busy = false;
  String? _pending;

  /// Queues [raw], replacing any link still waiting.
  void add(String raw) {
    _pending = raw;
    unawaited(_drain());
  }

  /// Starts handling links.
  void markReady() {
    _ready = true;
    unawaited(_drain());
  }

  Future<void> _drain() async {
    if (!_ready || _busy) return;
    _busy = true;
    try {
      while (true) {
        final raw = _pending;
        if (raw == null) break;
        _pending = null;
        try {
          await _handle(raw);
        } on Object {
          // One bad link never stops the next one.
        }
      }
    } finally {
      _busy = false;
    }
  }
}
