// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';
import 'dart:io';

import 'package:crux_cxp/crux_cxp.dart';
import 'package:crux_telemetry/crux_telemetry.dart';
import 'package:crux_window_chrome/crux_window_chrome.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:netcrux/domain/models/app_settings.dart';
import 'package:netcrux/domain/models/schematic/schematic_graph.dart';
import 'package:netcrux/domain/models/selection/selected_element.dart';
import 'package:netcrux/domain/models/selection/selection.dart';
import 'package:netcrux/features/hierarchy/providers/hierarchy_tree_notifier.dart';
import 'package:netcrux/features/hierarchy/providers/scope_flash_notifier.dart';
import 'package:netcrux/features/project/providers/current_laid_out_graph_provider.dart';
import 'package:netcrux/features/project/providers/current_project_provider.dart';
import 'package:netcrux/features/settings/providers/app_settings_provider.dart';
import 'package:netcrux/features/viewer/providers/reveal_request_notifier.dart';
import 'package:netcrux/features/viewer/providers/selected_element_notifier.dart';
import 'package:netcrux/features/viewer/services/zoom_to_selection_controller.dart';
import 'package:netcrux/services/remote/cxp/cxp_workspace_link.dart';
import 'package:netcrux/services/remote/cxp/editor_open_service.dart';
import 'package:netcrux/services/remote/cxp/netcrux_name_resolver.dart';
import 'package:netcrux/services/schematic/schematic_graph_builder.dart';
import 'package:netcrux/services/schematic/wire_selection_builder.dart';
import 'package:netcrux/services/workspace/netcrux_workspace_notifier.dart';

/// Looks up the per-tab `ProviderContainer` that the inbound handler
/// should route highlight requests to. The handler resolves the active
/// tab's container at the moment a request arrives so it acts on
/// whatever tab the user has focused — same behaviour the outbound
/// emitter has.
typedef ActiveTabContainerLookup = ProviderContainer? Function();

/// Frames the selection of a tab the way Zoom to Selection does. Returns false
/// when it could not (no layout yet, canvas not mounted), so the caller can
/// retry once layout exists.
typedef SelectionFramer = bool Function(ProviderContainer tab);

bool _zoomToSelection(ProviderContainer tab) =>
    ZoomToSelectionController(tab).run();

/// Subscribes to a [`LocalCxpServer`]'s inbound stream and dispatches
/// the v1 request messages NetCrux honours:
///
///   - [`RequestHighlight`] — focus on an [`ElementId`] in the active
///     tab. For [`ElementKind.instance`] / [`ElementKind.scope`] /
///     [`ElementKind.port`] / [`ElementKind.net`] the handler updates
///     the per-tab selection. For [`ElementKind.source`] the handler
///     hands off to the [`EditorOpenService`].
///   - [`RequestOpenSource`] — shell out to the configured editor.
///
/// Both handlers reply with the corresponding `Ack` carrying
/// `honored: true|false` plus a reason on failure. The reply targets
/// the sender peer via [`LocalCxpServer.sendTo`].
///
/// Lifecycle: [`CxpInboundHandler`] is constructed against a running
/// server and disposes its subscription on [dispose]. The
/// [`cxpServerHostProvider`] consumer is responsible for the
/// construction / teardown — this class itself does not touch the
/// provider container.
class CxpInboundHandler {
  /// Attaches the handler to [server].
  CxpInboundHandler({
    required this.server,
    required this.rootContainer,
    required this.activeTabContainerLookup,
    EditorOpenService? editorService,
    NameResolver? nameResolver,
    SelectionFramer? selectionFramer,
  }) : _editorService = editorService ?? EditorOpenService(),
       _frame = selectionFramer ?? _zoomToSelection,
       _nameResolver = nameResolver ?? const NetcruxNameResolver() {
    _subscription = server.inbound.listen(_onInbound);
  }

  /// CXP §11's rooted rule, read from the root container so this handler
  /// applies the very instance the workspace store applies to the
  /// `crux.design_id` fallback. It guards that fallback and the paths handed
  /// to an editor; `request_open_artifact` is held to the floor instead
  /// ([kCxpOpenArtifactContainment]).
  ///
  /// The shared layer screens what arrived on the wire; only the product can
  /// screen what it is about to open, which is what CXP §11 asks for — a record
  /// or a symlink can change between the lookup and the load.
  CxpPathContainment get _containment =>
      rootContainer.read(cxpPathContainmentProvider);

  /// The CXP server whose inbound stream is being handled.
  final CxpServer server;

  /// The root [`ProviderContainer`] — used to read app-wide settings
  /// (the editor command template).
  final ProviderContainer rootContainer;

  /// Resolves the per-tab container the highlight handler routes into.
  /// Returns `null` when no tab is active; in that case the handler
  /// acks `honored: false` with `element_not_found`.
  final ActiveTabContainerLookup activeTabContainerLookup;

  final EditorOpenService _editorService;
  final NameResolver _nameResolver;
  final SelectionFramer _frame;
  late final StreamSubscription<InboundCxpMessage> _subscription;

  /// Deferred post-open highlight subscriptions/timers. A shared-workspace open
  /// loads a design's source into a tab and elaboration then runs
  /// ASYNCHRONOUSLY, so the follow-up select cannot happen inline — it is
  /// parked on a one-shot listener of the tab's hierarchy model (see
  /// [_deferHighlightUntilLoaded]). Tracked here so [dispose] tears down any
  /// still-pending deferral.
  final List<ProviderSubscription<Object?>> _deferredSubs =
      <ProviderSubscription<Object?>>[];
  final List<Timer> _deferredTimers = <Timer>[];

  /// Stop handling inbound messages.
  Future<void> dispose() async {
    for (final sub in _deferredSubs) {
      sub.close();
    }
    _deferredSubs.clear();
    for (final timer in _deferredTimers) {
      timer.cancel();
    }
    _deferredTimers.clear();
    await _subscription.cancel();
  }

  void _onInbound(InboundCxpMessage message) {
    final body = message.message;
    if (body is RequestHighlight) {
      unawaited(_handleRequestHighlight(message, body));
    } else if (body is RequestOpenSource) {
      unawaited(_handleRequestOpenSource(message, body));
    } else if (body is RequestOpenArtifact) {
      unawaited(_handleRequestOpenArtifact(message, body));
    } else if (body is NotifySelection) {
      // A peer's live selection gossip (the emitter's auto-broadcast, and any
      // panel send from a build that still uses notify_selection). NetCrux acts
      // on it symmetrically to WaveCrux's inbound-selection handler: resolve the
      // first signal-like element and highlight it. No ack — notify_selection is
      // fire-and-forget in the protocol.
      unawaited(_handleNotifySelection(body));
    }
  }

  Future<void> _handleRequestHighlight(
    InboundCxpMessage message,
    RequestHighlight request,
  ) async {
    final result = await _resolveAndAct(
      request.element,
      request.metadata,
      frame: true,
    );
    _replyHighlight(
      from: message.from.peerId,
      replyTo: message.envelope.messageId,
      honored: result.honored,
      reason: result.reason,
    );
    // An actionable inbound message was applied — nudge the OS's
    // attention affordance without stealing focus. Gated by the user setting
    // via the swappable `windowAttentionRequester` seam, so this is a no-op
    // when the preference is off (and under tests, which have no native side).
    if (result.honored) unawaited(requestUserAttention());
  }

  /// Handles an inbound `notify_selection` — a peer's live selection gossip.
  /// The mirror of WaveCrux's `handleInboundSelection`: resolve the first
  /// signal-like element and highlight it (opening the design via the shared
  /// workspace when it isn't loaded). No ack is sent — `notify_selection` is
  /// fire-and-forget.
  Future<void> _handleNotifySelection(NotifySelection message) async {
    for (final element in message.elements) {
      if (!_isSignalLikeKind(element.kind)) continue;
      final result = await _resolveAndAct(
        element,
        message.metadata,
        frame: false,
      );
      if (result.honored) {
        unawaited(requestUserAttention());
        return;
      }
    }
  }

  /// Resolves [element] against the active tab and applies the highlight,
  /// falling back to the shared-workspace open when it doesn't resolve
  /// locally. Shared by the `request_highlight` (acked) and `notify_selection`
  /// (fire-and-forget) inbound paths so both behave identically.
  Future<({bool honored, String? reason})> _resolveAndAct(
    ElementId element,
    Map<String, Object?> metadata, {
    required bool frame,
  }) async {
    final tab = activeTabContainerLookup();
    final result = await _applyHighlight(element);
    if (result.honored) {
      // An explicit request_highlight frames what it selected, as Zoom to
      // Selection does (netcrux#19). Scope and source select nothing on the
      // canvas, so there is nothing to frame; notify_selection gossip never
      // zooms.
      if (frame &&
          tab != null &&
          element.kind != ElementKind.scope &&
          element.kind != ElementKind.source) {
        _frameWhenReady(tab);
      }
      _recordCrossProbe(honored: true);
      return result;
    }
    // Shared-workspace consumer: the element didn't resolve locally — fall back
    // to the shared workspace. Read `crux.design_id` from the message metadata,
    // resolve this design's `source` artifact, open (or activate) its tab, and
    // — once elaboration completes — select the element there. The join is
    // one-directional: the consumer trusts the sender's design id and never
    // re-derives one from the file it opens.
    if (_openDesignFromWorkspace(element, metadata, frame: frame)) {
      _recordCrossProbe(honored: true);
      return (
        honored: true,
        reason: 'opened design source from the shared workspace',
      );
    }
    _recordCrossProbe(honored: result.honored);
    return result;
  }

  /// Counts one inbound cross-probe (the suite network-effect funnel).
  ///
  /// **Both** outcomes are recorded, and that is the point of the `honored`
  /// property: a cross-probe a peer sent and NetCrux could not act on is
  /// exactly the failure the funnel exists to surface, so dropping it would
  /// leave the metric reading healthy precisely when it is not.
  ///
  /// Placed on `_resolveAndAct` rather than on the two message handlers
  /// because it is the one seam both the acked `request_highlight` and the
  /// fire-and-forget `notify_selection` pass through — the same shape as
  /// WaveCrux's `dispatchCxpHighlight`.
  void _recordCrossProbe({required bool honored}) {
    rootContainer
        .read(telemetryServiceProvider)
        .record(
          TelemetryEvent(
            'cxp.crossprobe',
            properties: <String, Object?>{
              'direction': 'inbound',
              'honored': honored,
            },
          ),
        );
  }

  /// Applies an inbound highlight locally, returning the honored/reason ack
  /// **without** replying — the caller adds the shared-workspace fallback,
  /// sends the ack, and requests attention.
  Future<({bool honored, String? reason})> _applyHighlight(
    ElementId element,
  ) async {
    // ElementKind.source maps to the editor handler — peers that ask for a
    // source highlight effectively want the file opened.
    if (element.kind == ElementKind.source) {
      final (filePath, line, column) = _parseSourceElementId(element);
      if (filePath == null || line == null) {
        return (honored: false, reason: 'Malformed source ElementId');
      }
      final result = await _openSource(filePath, line, column);
      return (honored: result.honored, reason: result.reason);
    }

    final tabContainer = activeTabContainerLookup();
    if (tabContainer == null) {
      return (honored: false, reason: 'No active tab');
    }

    final local = _nameResolver.toLocal(element);
    if (local == null || local.isEmpty) {
      return (honored: false, reason: 'Could not resolve element path');
    }

    // Scope must be handled before the signal-like path because scope is not
    // representable as a SelectedElement — the scope kind navigates the
    // hierarchy instead of selecting a canvas element.
    if (element.kind == ElementKind.scope) {
      final tree = tabContainer.read(hierarchyTreeProvider);
      if (tree.model == null) {
        return (honored: false, reason: 'No design loaded');
      }
      final matched = _walkHierarchy(tabContainer, local);
      if (!matched) {
        return (
          honored: false,
          reason: 'Scope $local not found in current design',
        );
      }
      return (honored: true, reason: null);
    }

    // Everything else (net / port / instance / signal, plus any kind a newer
    // peer names) is resolved as a signal-like reference against the loaded
    // netlist: exact-by-kind first, then leaf-match.
    return _applySignalLike(tabContainer, element.kind, local);
  }

  /// Resolves an inbound signal-like reference ([local], any of the
  /// signal/instance/port/net kinds — or an unmodelled kind a newer peer sent)
  /// against the active tab's netlist and applies the selection (and reveal for
  /// cells). Exact resolution using the kind the peer declared wins; when that
  /// misses — the common cross-representation case where a WAVEFORM name
  /// (`tb_fsm_trap.dut.state`, or a bare `state`) is probed against the
  /// synthesized NETLIST — it leaf-matches the trailing segment against the
  /// current scope's nets → boundary ports → cells. This is the mirror of
  /// WaveCrux's inbound leaf-match: the reverse direction NetCrux
  /// never had. Exact-path match stays highest priority; leaf-match is the
  /// fallback.
  ({bool honored, String? reason}) _applySignalLike(
    ProviderContainer tabContainer,
    ElementKind kind,
    String local,
  ) {
    // 1. Exact resolution using the declared kind.
    if (kind == ElementKind.net) {
      // Nets are resolved against the live netlist, not syntactically: the
      // canonical net reference carries the net's HUMAN NAME
      // (`<scope>.<netName>`), and the real Yosys net id — which the schematic
      // renderer keys the wire highlight off — can only be recovered by
      // looking the name up in the current scope's module.
      final selection = _resolveNetSelection(tabContainer, local);
      if (selection != null) {
        tabContainer.read(selectedElementProvider.notifier).replace(selection);
        return (honored: true, reason: null);
      }
    } else {
      final element = _localToSelection(kind, local);
      if (element != null) {
        // `_localToSelection` builds the selection syntactically — it cannot
        // tell whether the element exists in the active tab's design.
        // Pre-validate against the current scope's graph.
        final graph = _currentGraph(tabContainer);
        if (graph != null && _selectionExists(graph, element)) {
          tabContainer.read(selectedElementProvider.notifier).select(element);
          _revealElement(tabContainer, element);
          return (honored: true, reason: null);
        }
      }
    }

    // 2. Leaf-match fallback — the cross-representation case. Only the
    // signal-like kinds fall through here: an unmodelled kind a newer peer sent
    // is declined by name rather than coerced onto whatever element happens to
    // share the leaf (preserving the forward-compat "ignore gracefully"
    // contract). Strip any `:port:`/`:net:`/`:cell:` marker and testbench/dotted
    // hierarchy and match the trailing segment against the current scope.
    if (!_isSignalLikeKind(kind)) {
      return (
        honored: false,
        reason: 'Unsupported element kind ${kind.name}',
      );
    }
    final leaf = _inboundLeaf(local);
    if (leaf.isNotEmpty && _applyLeafMatch(tabContainer, leaf)) {
      return (honored: true, reason: null);
    }

    return (
      honored: false,
      reason: 'Element $local not found in current design',
    );
  }

  /// Matches a bare element [leaf] (e.g. `state`) against the active tab's
  /// current scope, preferring a NAMED NET (the signal analog — lights the
  /// whole wire), then a boundary port, then a cell instance. Applies the
  /// selection and returns whether anything matched.
  bool _applyLeafMatch(ProviderContainer tabContainer, String leaf) {
    final tree = tabContainer.read(hierarchyTreeProvider);
    final model = tree.model;
    final node = tree.selected;
    if (model == null || node == null) return false;
    final module = node.resolve(model);
    if (module == null) return false;
    final graph = const SchematicGraphBuilder().build(model, node);
    if (graph.isEmpty) return false;

    // 1. Named net → whole-net wire selection (symmetric to WaveCrux lighting
    // a signal lane).
    final net = module.nets[leaf];
    if (net != null) {
      final selection = buildWholeNetWireSelection(net, graph);
      if (selection != null) {
        tabContainer.read(selectedElementProvider.notifier).replace(selection);
        return true;
      }
    }
    // 2. Boundary port.
    for (final port in graph.boundaryPorts) {
      if (port.name == leaf) {
        tabContainer
            .read(selectedElementProvider.notifier)
            .select(
              SelectedElement.boundaryPort(
                portId: 'port:$leaf',
                portName: leaf,
              ),
            );
        return true;
      }
    }
    // 3. Cell instance → select + reveal.
    for (final cell in graph.cells) {
      if (cell.id == leaf) {
        tabContainer
            .read(selectedElementProvider.notifier)
            .select(SelectedElement.cell(cellId: cell.id));
        tabContainer.read(revealRequestProvider.notifier).request(cell.id);
        return true;
      }
    }
    return false;
  }

  /// Frames [tab]'s selection now, or, when layout is not there yet (a design
  /// just loaded for a deferred select), as soon as it is. The retry waits two
  /// frames after the layout lands so the canvas' own fit-to-view for a new
  /// layout runs first and does not undo the framing. Bounded like the
  /// deferred select; [dispose] tears it down.
  void _frameWhenReady(ProviderContainer tab) {
    if (_frame(tab)) return;
    ProviderSubscription<Object?>? sub;
    Timer? timer;
    var done = false;

    void cleanup() {
      if (done) return;
      done = true;
      final localSub = sub;
      if (localSub != null) {
        _deferredSubs.remove(localSub);
        localSub.close();
      }
      final localTimer = timer;
      if (localTimer != null) {
        _deferredTimers.remove(localTimer);
        localTimer.cancel();
      }
    }

    void attempt() {
      if (done) return;
      SchedulerBinding.instance.addPostFrameCallback((_) {
        SchedulerBinding.instance.addPostFrameCallback((_) {
          if (done) return;
          if (_frame(tab)) cleanup();
        });
      });
      SchedulerBinding.instance.scheduleFrame();
    }

    sub = tab.listen<Object?>(currentLaidOutGraphProvider, (_, _) => attempt());
    _deferredSubs.add(sub);
    timer = Timer(const Duration(seconds: 15), cleanup);
    _deferredTimers.add(timer);
  }

  /// Reveals the cell a resolved [element] lives on, when it names one. Nets and
  /// boundary ports have no single cell to centre on, so the selection highlight
  /// is their only cue (the reveal notifier is cell-keyed).
  void _revealElement(ProviderContainer tabContainer, SelectedElement element) {
    final cellId = switch (element) {
      SelectedElementCell(:final cellId) => cellId,
      SelectedElementPort(:final cellId) => cellId,
      _ => null,
    };
    if (cellId != null) {
      tabContainer.read(revealRequestProvider.notifier).request(cellId);
    }
  }

  /// Shared-workspace consumer fallback: resolves `crux.design_id` from
  /// [metadata] against the shared workspace and, when a `source` artifact is
  /// recorded for that design, opens it — or, when the design is already open
  /// in a tab, ACTIVATES that tab instead of clobbering the active one
  /// (mirroring WaveCrux's dedup). After a fresh open the element is selected
  /// once elaboration completes (deferred — elaboration is async). Returns
  /// whether a design was opened or activated.
  bool _openDesignFromWorkspace(
    ElementId element,
    Map<String, Object?> metadata, {
    required bool frame,
  }) {
    final designId = metadata[cxpDesignIdMetadataKey];
    if (designId is! String || designId.isEmpty) return false;
    final path = resolveDesignSourceArtifactPath(rootContainer, designId);
    if (path == null) return false;
    // CXP §11's rule, rooted in the directories the user has opened. Unlike
    // `request_open_artifact`, where the user asked for the design, nobody
    // asked NetCrux to open this one: a peer attached an id to a cross-probe,
    // and the record it selects would be loaded unasked.
    if (!_containment.allows(path)) return false;

    // DEDUP: if a tab already hosts this design (same crux.design_id), activate
    // it rather than reloading the active tab — never stack a second view or
    // stomp the tab the user is on.
    final workspace = rootContainer.read(netcruxWorkspaceProvider).value;
    if (workspace != null) {
      for (final tab in workspace.tabs) {
        final files = tab.payload.sourceFiles;
        if (files.isEmpty) continue;
        if (cxpDesignIdForPath(files.first) == designId) {
          if (tab.id != workspace.activeTabId) {
            unawaited(
              rootContainer
                  .read(netcruxWorkspaceProvider.notifier)
                  .setActiveTab(tab.id),
            );
          }
          return true;
        }
      }
    }

    // Not open anywhere: load the source into the active tab, then select the
    // probed element once its elaboration lands.
    final tab = activeTabContainerLookup();
    if (tab == null) return false;
    tab.read(currentProjectProvider.notifier).setSourceFiles(<String>[path]);
    _deferHighlightUntilLoaded(tab, element, frame: frame);
    return true;
  }

  /// Parks a select of [element] on [tabContainer] until its hierarchy model is
  /// available. A shared-workspace open sets the tab's source files, but Yosys
  /// elaboration + ELK layout run on a background isolate, so the netlist the
  /// leaf-match needs isn't there inline. A one-shot listener applies the
  /// highlight the moment the model resolves (or gives up after a bounded
  /// wait); [dispose] tears down any still-pending deferral.
  void _deferHighlightUntilLoaded(
    ProviderContainer tabContainer,
    ElementId element, {
    required bool frame,
  }) {
    final local = _nameResolver.toLocal(element);
    if (local == null || local.isEmpty) return;

    ProviderSubscription<Object?>? sub;
    Timer? timer;
    var done = false;

    void cleanup() {
      if (done) return;
      done = true;
      final localSub = sub;
      if (localSub != null) {
        _deferredSubs.remove(localSub);
        localSub.close();
      }
      final localTimer = timer;
      if (localTimer != null) {
        _deferredTimers.remove(localTimer);
        localTimer.cancel();
      }
    }

    void tryApply() {
      final tree = tabContainer.read(hierarchyTreeProvider);
      if (tree.model == null || tree.selected == null) return;
      final result = _applySignalLike(tabContainer, element.kind, local);
      cleanup();
      // The select is applied; the layout for the freshly loaded design may
      // not exist yet, so framing waits for it.
      if (frame && result.honored) _frameWhenReady(tabContainer);
    }

    sub = tabContainer.listen<HierarchyTreeState>(
      hierarchyTreeProvider,
      (_, _) => tryApply(),
    );
    _deferredSubs.add(sub);
    timer = Timer(const Duration(seconds: 15), cleanup);
    _deferredTimers.add(timer);
    // The model may already be present (cache hit) before the listener fires.
    tryApply();
  }

  /// Whether [kind] names a signal-like element NetCrux can highlight on the
  /// schematic — the kinds carried by an inbound `notify_selection` worth
  /// acting on.
  static bool _isSignalLikeKind(ElementKind kind) =>
      kind == ElementKind.signal ||
      kind == ElementKind.instance ||
      kind == ElementKind.net ||
      kind == ElementKind.port;

  /// Extracts the trailing element leaf from an inbound signal-like [path],
  /// tolerating `:port:`/`:net:`/`:cell:` markers and testbench/dotted
  /// hierarchy. Mirrors WaveCrux's `_signalLikeLeaf` so the two ends leaf-match
  /// identically: take the segment after the LAST marker, then the last
  /// `.`-separated segment of that tail. A clean, unmarked path falls straight
  /// through to the plain dot split.
  ///
  /// A trailing bus bit-select / slice suffix is stripped (`data_r[7:0]` →
  /// `data_r`, `q[3]` → `q`): WaveCrux preserves the slice verbatim on a signal
  /// path, but the elaborated netlist keys nets by the whole-net name, so the
  /// suffix would otherwise miss `module.nets['data_r']`. Only a numeric
  /// `[n]` / `[hi:lo]` suffix is removed, so a named generate-block segment
  /// (`genblk[foo]`) is left intact.
  static String _inboundLeaf(String path) {
    const markers = <String>[':port:', ':net:', ':cell:'];
    var cut = -1;
    var markerLen = 0;
    for (final marker in markers) {
      final idx = path.lastIndexOf(marker);
      if (idx > cut) {
        cut = idx;
        markerLen = marker.length;
      }
    }
    final tail = cut >= 0 ? path.substring(cut + markerLen) : path;
    final leaf = tail.split('.').last;
    return leaf.replaceFirst(_busBitSelectSuffix, '');
  }

  /// A trailing numeric bit-select / slice on a signal leaf: `[7:0]`, `[3]`.
  static final RegExp _busBitSelectSuffix = RegExp(r'\[\d+(?::\d+)?\]$');

  /// Handles an inbound `request_open_artifact` (shared-workspace consumer):
  /// NetCrux opens only `source` artifacts, resolving the concrete file through
  /// its shared workspace store (preferring that over the sender's hint path,
  /// whose absolute path may not exist on this machine's layout) and loading it
  /// into the active tab. Acks honored=false with a reason when the kind is not
  /// `source`, neither a record nor a hint names a file, the path fails the
  /// floor ([kCxpOpenArtifactContainment]: empty, relative, a NUL, or padded
  /// with white space), it is not a file here, or no tab is active.
  ///
  /// A design NetCrux has never opened is honoured: this route is not rooted
  /// in the directories the user has opened, and [kCxpOpenArtifactContainment]
  /// says why.
  Future<void> _handleRequestOpenArtifact(
    InboundCxpMessage message,
    RequestOpenArtifact request,
  ) async {
    final result = _resolveOpenArtifact(request);
    server.sendTo(
      message.from.peerId,
      RequestOpenArtifactAck(
        inReplyTo: message.envelope.messageId,
        honored: result.honored,
        reason: result.reason,
      ),
    );
    if (result.honored) unawaited(requestUserAttention());
  }

  ({bool honored, String? reason}) _resolveOpenArtifact(
    RequestOpenArtifact request,
  ) {
    if (request.artifactKind != kCxpSourceArtifactKind) {
      return (
        honored: false,
        reason:
            'netcrux opens only source artifacts, not "${request.artifactKind}"',
      );
    }
    final path =
        resolveOpenArtifactSourcePath(rootContainer, request.designId) ??
        request.path;
    if (path == null) {
      return (
        honored: false,
        reason: 'no source artifact recorded for design "${request.designId}"',
      );
    }
    // CXP §11's MUST: the artifact a receiver resolved through its own records
    // gets the same scrutiny as a `file_path` on the wire, applied to the
    // value about to be opened rather than the value looked up. The sender
    // chose the `design_id` that selected this record and the hint that may
    // have supplied it, and the workspace directory is user-writable — so
    // "we resolved it ourselves" is not a provenance. On this route that
    // scrutiny is the floor, judged on the exact string loaded below; see
    // [kCxpOpenArtifactContainment] for why it is not the open directories.
    // The reason travels back in the ack and never repeats the path
    // (CXP §9.11).
    final refusal = kCxpOpenArtifactContainment.refuse(path);
    if (refusal != null) return (honored: false, reason: refusal);
    // The peer's hint can name a file that is not there — the sender's path
    // on its own machine layout, or a design since deleted — or something
    // that is not a file at all. Loading it would replace the design in the
    // active tab with an elaboration error, so decline instead. Checked only
    // after the floor, so a malformed path is refused without this process
    // ever looking at it. (A workspace record never gets here missing: the
    // store drops records whose file is gone.)
    if (FileSystemEntity.typeSync(path) != FileSystemEntityType.file) {
      return (honored: false, reason: 'the artifact is not a file here');
    }
    final tab = activeTabContainerLookup();
    if (tab == null) return (honored: false, reason: 'No active tab');
    tab.read(currentProjectProvider.notifier).setSourceFiles(<String>[path]);
    return (honored: true, reason: null);
  }

  /// Resolves a canonical net reference ([local], e.g. `top.sample_a` or
  /// the opaque `<scope>:net:<edgeId>` fall-back) into a whole-net wire
  /// [Selection] carrying the net's REAL Yosys net ids, looked up in the
  /// active tab's current scope. Returns `null` when no design / scope is
  /// loaded, the named net is absent from the scope, or the net has no
  /// rendered edge (a wholly combinational / dangling net the schematic
  /// doesn't draw).
  ///
  /// A multi-bit bus resolves to one [SelectedElement.wire] per drawn bit
  /// so an inbound highlight lights the WHOLE bus, matching a local
  /// row-tap selection (see [buildWholeNetWireSelection]). The renderer
  /// highlights a wire by net id, so each net id must be correct; the
  /// [SelectedElementWire.edgeId] is filled from a laid-out edge on the
  /// bit purely so the selection also survives the handler's existence
  /// check.
  Selection? _resolveNetSelection(
    ProviderContainer tabContainer,
    String local,
  ) {
    final tree = tabContainer.read(hierarchyTreeProvider);
    final model = tree.model;
    final node = tree.selected;
    if (model == null || node == null) return null;
    final module = node.resolve(model);
    if (module == null) return null;

    // Named nets arrive as `<scope>.<netName>`; the leaf is the net name.
    // The opaque `<scope>:net:<edgeId>` form names no net we can resolve
    // to a net id, so it is not supported here (anonymous internal wire).
    if (local.contains(':net:')) return null;
    final netName = local.split('.').last;
    if (netName.isEmpty) return null;
    final net = module.nets[netName];
    if (net == null) return null;

    final graph = const SchematicGraphBuilder().build(model, node);
    return buildWholeNetWireSelection(net, graph);
  }

  /// Builds the current scope's schematic graph from the active tab's
  /// hierarchy state. Returns `null` when no design / scope is available.
  /// Only the graph topology (cells / ports / edges) is needed for
  /// existence checks, so this skips the async ELK layout that
  /// `currentLaidOutGraphProvider` also carries.
  SchematicGraph? _currentGraph(ProviderContainer tabContainer) {
    final tree = tabContainer.read(hierarchyTreeProvider);
    final model = tree.model;
    final node = tree.selected;
    if (model == null || node == null) return null;
    final graph = const SchematicGraphBuilder().build(model, node);
    return graph.isEmpty ? null : graph;
  }

  /// Whether [element] names a cell, cell-port, or net that exists in
  /// [graph]. Mirrors the resolution the canvas gesture handler performs
  /// when a user clicks the same element directly.
  bool _selectionExists(SchematicGraph graph, SelectedElement element) {
    return switch (element) {
      SelectedElementCell(:final cellId) => graph.cells.any(
        (c) => c.id == cellId,
      ),
      SelectedElementPort(:final cellId, :final portName) => graph.cells.any(
        (c) => c.id == cellId && c.ports.any((p) => p.name == portName),
      ),
      SelectedElementWire(:final edgeId) => graph.findEdge(edgeId) != null,
      SelectedElementBoundaryPort(:final portId) => graph.boundaryPorts.any(
        (p) => 'port:${p.name}' == portId,
      ),
      SelectedElementNone() => false,
    };
  }

  Future<void> _handleRequestOpenSource(
    InboundCxpMessage message,
    RequestOpenSource request,
  ) async {
    final replyTo = message.envelope.messageId;
    final from = message.from.peerId;
    final result = await _openSource(
      request.filePath,
      request.line,
      request.column,
    );
    final ack = RequestOpenSourceAck(
      inReplyTo: replyTo,
      honored: result.honored,
      reason: result.reason,
    );
    server.sendTo(from, ack);
    // Honored open-source is actionable — nudge attention (no-op when
    // gated off or under tests).
    if (result.honored) unawaited(requestUserAttention());
  }

  void _replyHighlight({
    required String from,
    required String replyTo,
    required bool honored,
    String? reason,
  }) {
    server.sendTo(
      from,
      RequestHighlightAck(
        inReplyTo: replyTo,
        honored: honored,
        reason: reason,
      ),
    );
  }

  Future<EditorOpenResult> _openSource(
    String filePath,
    int line,
    int? column,
  ) {
    // The rooted rule, on the value that actually becomes an editor argv,
    // whatever route reached this method. `LocalCxpServer` screens a
    // `request_open_source` on the wire first, but only with the floor: its
    // one rule also screens `request_open_artifact`'s hint, which must not be
    // rooted (see `kCxpOpenArtifactContainment`). So this check is the one
    // that keeps an editor to the directories the user has opened.
    final refusal = _containment.refuse(filePath);
    if (refusal != null) {
      return Future<EditorOpenResult>.value(
        EditorOpenResult(honored: false, reason: refusal),
      );
    }
    final settings =
        rootContainer.read(appSettingsProvider).value ??
        const AppSettings.defaults();
    return _editorService.openSourceLocation(
      commandTemplate: settings.cxpEditorCommand,
      filePath: filePath,
      line: line,
      column: column,
    );
  }

  /// Maps a canonical-form local path back into a [`SelectedElement`].
  ///
  /// The mapping is best-effort because the canonical form has lost
  /// some of the original information that NetCrux's [`SelectedElement`]
  /// carries:
  ///
  ///   - Cells need a `cellId`. We use the leaf segment of the
  ///     hierarchical path.
  ///   - Ports need a `cellId`, `portId`, and `portName`. We split on
  ///     `.` and pick the last two segments.
  ///   - Nets need an `edgeId` and `netId`. We use the trailing
  ///     `:net:<edgeId>` form; the numeric netId is unknown so we
  ///     fall back to 0 and rely on the canvas's edge lookup to
  ///     match the highlight.
  ///   - Scope is handled separately by the caller.
  SelectedElement? _localToSelection(ElementKind kind, String local) {
    switch (kind.known) {
      case KnownElementKind.instance:
        final segments = local.split('.');
        if (segments.isEmpty) return null;
        return SelectedElement.cell(cellId: segments.last);
      case KnownElementKind.port:
        final segments = local.split('.');
        if (segments.length < 2) return null;
        final portName = segments.last;
        final cellId = segments[segments.length - 2];
        return SelectedElement.port(
          cellId: cellId,
          portId: '$cellId:$portName',
          portName: portName,
        );
      case KnownElementKind.net:
        final marker = local.indexOf(':net:');
        if (marker == -1) return null;
        final edgeId = local.substring(marker + ':net:'.length);
        return SelectedElement.wire(edgeId: edgeId, netId: 0);
      // Kinds this build models but that select nothing on a schematic
      // (source, scope, signal, marker, …) are routed by the caller
      // before this helper runs.
      case KnownElementKind.source:
      case KnownElementKind.scope:
      case KnownElementKind.signal:
      case KnownElementKind.marker:
      case KnownElementKind.rule:
      case KnownElementKind.test:
      case KnownElementKind.breakpoint:
        return null;
      // A kind this build does not model. `ElementKind` is open
      // precisely so a peer on a newer protocol build can name one, so
      // an unrecognized kind selects nothing and the request is
      // ignored — it is never an error.
      case null:
        return null;
    }
  }

  bool _walkHierarchy(ProviderContainer tabContainer, String localPath) {
    final state = tabContainer.read(hierarchyTreeProvider);
    final model = state.model;
    if (model == null) return false;
    final segments = localPath.split('.');
    if (segments.isEmpty) return false;
    final top = model.topModule;
    if (top == null) return false;
    // First segment is the top module name; everything after it is the
    // instance-name chain HierarchyTreeNotifier.selectByPath expects.
    final instancePath = segments.skip(1).toList(growable: false);
    // Pre-validate the path resolves before committing the selection
    // so we can report `honored: false` accurately.
    var node = state.root;
    if (node == null) return false;
    for (final seg in instancePath) {
      final child = node!.child(model, seg);
      if (child == null) return false;
      node = child;
    }
    tabContainer
        .read(hierarchyTreeProvider.notifier)
        .selectByPath(instancePath);
    // Give a VISIBLE cue even when the scope was already selected (the common
    // case: an inbound scope cross-probe that resolves to the top module the
    // user is already viewing). `selectByPath` is a no-op then, so without this
    // flash nothing changes on screen — an "acked honored:true but nothing
    // happened" outcome. The hierarchy row pulses on the flash; the target
    // scope's instance path IS its expansion key (empty = top scope).
    tabContainer.read(scopeFlashProvider.notifier).flash(instancePath);
    return true;
  }

  (String?, int?, int?) _parseSourceElementId(ElementId id) {
    // Accept both `file:///abs/path.v#L<line>[:C<column>]` and bare
    // absolute paths (with no line). Bare paths default to line 1.
    final path = id.path;
    if (path.startsWith('file://')) {
      final hashIdx = path.indexOf('#');
      final filePart = hashIdx == -1
          ? path.substring('file://'.length)
          : path.substring('file://'.length, hashIdx);
      var line = 1;
      int? column;
      if (hashIdx != -1) {
        final tail = path.substring(hashIdx + 1);
        final colonIdx = tail.indexOf(':C');
        if (colonIdx == -1) {
          // #L42 form.
          final n = int.tryParse(tail.replaceFirst('L', ''));
          if (n != null) line = n;
        } else {
          final lineStr = tail.substring(0, colonIdx).replaceFirst('L', '');
          final n = int.tryParse(lineStr);
          if (n != null) line = n;
          final colStr = tail.substring(colonIdx + ':C'.length);
          column = int.tryParse(colStr);
        }
      }
      return (filePart, line, column);
    }
    // Bare path → line 1.
    return (path, 1, null);
  }
}
