// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';
import 'dart:io';

import 'package:crux_cxp/crux_cxp.dart';
import 'package:crux_cxp_ui/crux_cxp_ui.dart';
import 'package:crux_license/crux_license.dart';
import 'package:crux_telemetry/crux_telemetry.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:netcrux/domain/enums/netcrux_design_source.dart';
import 'package:netcrux/domain/models/app_settings.dart';
import 'package:netcrux/domain/models/netlist/hierarchy_node.dart';
import 'package:netcrux/domain/models/netlist/netlist_model.dart';
import 'package:netcrux/domain/models/project/netcrux_project.dart';
import 'package:netcrux/domain/models/schematic/laid_out_graph.dart';
import 'package:netcrux/domain/models/selection/selected_element.dart';
import 'package:netcrux/domain/models/selection/selection.dart';
import 'package:netcrux/domain/models/trace/trace_overlay.dart';
import 'package:netcrux/features/hierarchy/providers/hierarchy_tree_notifier.dart';
import 'package:netcrux/features/hierarchy/providers/scope_flash_notifier.dart';
import 'package:netcrux/features/inspector/providers/received_timing_path_provider.dart';
import 'package:netcrux/features/project/providers/current_laid_out_graph_provider.dart';
import 'package:netcrux/features/project/providers/current_project_provider.dart';
import 'package:netcrux/features/settings/providers/app_settings_provider.dart';
import 'package:netcrux/features/viewer/providers/reveal_request_notifier.dart';
import 'package:netcrux/features/viewer/providers/right_dock_provider.dart';
import 'package:netcrux/features/viewer/providers/selected_element_notifier.dart';
import 'package:netcrux/features/viewer/providers/trace_overlay_notifier.dart';
import 'package:netcrux/features/viewer/services/zoom_to_selection_controller.dart';
import 'package:netcrux/l10n/generated/app_localizations.dart';
import 'package:netcrux/services/file_open/crux_project_resolution.dart';
import 'package:netcrux/services/filelist/filelist_reader.dart';
import 'package:netcrux/services/project/netcrux_project_file.dart';
import 'package:netcrux/services/project/netcrux_project_path_resolver.dart';
import 'package:netcrux/services/remote/cxp/cxp_design_names.dart';
import 'package:netcrux/services/remote/cxp/cxp_workspace_link.dart';
import 'package:netcrux/services/remote/cxp/editor_open_service.dart';
import 'package:netcrux/services/remote/cxp/flow_artifact_opener.dart';
import 'package:netcrux/services/remote/cxp/inbound_property.dart';
import 'package:netcrux/services/remote/cxp/inbound_property_cone.dart';
import 'package:netcrux/services/remote/cxp/netcrux_name_resolver.dart';
import 'package:netcrux/services/schematic/netlist_element_lookup.dart';
import 'package:netcrux/services/schematic/trace_service.dart';
import 'package:netcrux/services/workspace/netcrux_workspace_notifier.dart';
import 'package:path/path.dart' as p;

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

/// Tells the user about a request a peer started, as a toast built from the
/// app's strings: a request has no `BuildContext`, so whoever builds the
/// handler supplies the strings and the toast (the publisher passes the
/// context-free `CruxToasts.showInfo`).
typedef CxpInboundNotice = void Function(String Function(L10N l10n) message);

/// The reason a directed request names an element the open design does not
/// have. It never repeats the element's path (CXP §9.11's rule for reasons,
/// applied to every acknowledgement).
const String kCxpElementNotInDesign =
    'the element was not found in the open design';

/// What NetCrux does when a peer asks (`cruxCxpRequestHandlerProvider`), for the
/// v1 request messages it honours:
///
///   - [`RequestHighlight`] — focus on an [`ElementId`] in the active
///     tab. For [`ElementKind.instance`] / [`ElementKind.scope`] /
///     [`ElementKind.port`] / [`ElementKind.net`] the handler updates
///     the per-tab selection. For [`ElementKind.source`] the handler
///     hands off to the [`EditorOpenService`].
///     A `signal` or `net` rooted at the top is found in the scope it names;
///     a formal property's failing signal also shows its fanin; a `cell` is
///     selected by its netlist name; a `property` is the Pro union cone
///     ([inboundPropertyConeProvider]); a `timing_path` is declined.
///   - [`RequestOpenSource`] — shell out to the configured editor.
///   - [`RequestOpenArtifact`] — open a `source` or `project` artifact, or
///     hand a `flow_run` / `timing_report` to [flowArtifactOpenerProvider].
///   - [`NotifySelection`] — a peer's live selection gossip, or a timing
///     path from an implementation run, shown in the Inspector.
///
/// Each request method returns whether it was honoured, and why not; the shared
/// runtime sends the acknowledgement and asks for the user's attention, so this
/// class never replies on the wire.
///
/// Lifecycle: the handler resolves the active tab's container when a request
/// arrives, so it is built where the tab containers are reachable (a mounted
/// widget) and published into `netcruxInboundHandlerHolderProvider`; whoever
/// publishes it calls [dispose] when it is replaced.
class NetcruxCxpRequestHandler extends CruxCxpRequestHandler {
  /// Creates the handler.
  NetcruxCxpRequestHandler({
    required this.rootContainer,
    required this.activeTabContainerLookup,
    EditorOpenService? editorService,
    NameResolver? nameResolver,
    SelectionFramer? selectionFramer,
    CxpInboundNotice? notice,
    this._revealInspector,
  }) : _editorService = editorService ?? EditorOpenService(),
       _frame = selectionFramer ?? _zoomToSelection,
       _nameResolver = nameResolver ?? const NetcruxNameResolver(),
       _notice = notice ?? _noNotice;

  static void _noNotice(String Function(L10N l10n) message) {}

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
  final CxpInboundNotice _notice;
  final void Function()? _revealInspector;

  /// Deferred post-open highlight subscriptions/timers. A shared-workspace open
  /// loads a design's source into a tab and elaboration then runs
  /// ASYNCHRONOUSLY, so the follow-up select cannot happen inline — it is
  /// parked on a one-shot listener of the tab's hierarchy model (see
  /// [_deferHighlightUntilLoaded]). Tracked here so [dispose] tears down any
  /// still-pending deferral.
  final List<ProviderSubscription<Object?>> _deferredSubs =
      <ProviderSubscription<Object?>>[];
  final List<Timer> _deferredTimers = <Timer>[];

  /// Cancels any still-pending deferred highlight or framing.
  Future<void> dispose() async {
    for (final sub in _deferredSubs) {
      sub.close();
    }
    _deferredSubs.clear();
    for (final timer in _deferredTimers) {
      timer.cancel();
    }
    _deferredTimers.clear();
  }

  @override
  Future<CruxCxpHandlerResult> highlight(
    RequestHighlight request,
    PeerIdentity from,
  ) async {
    final element = request.element;
    if (element.kind == ElementKind.property) {
      final result = await _highlightProperty(element, from);
      _recordCrossProbe(honored: result.honored);
      return CruxCxpHandlerResult(
        honored: result.honored,
        reason: result.reason,
      );
    }
    if (element.kind == ElementKind.timingPath) {
      // CXP §8.2: a timing path's id is opaque, and NetCrux acts only on the
      // registers beside it, which a directed request cannot carry. The path
      // arrives whole in the sender's selection.
      _recordCrossProbe(honored: false);
      return const CruxCxpHandlerResult(
        honored: false,
        reason:
            'a timing path is shown from the selection that names its '
            'registers; send its signal instead',
      );
    }
    final tab = activeTabContainerLookup();
    final result = await _resolveAndAct(
      element,
      request.metadata,
      frame: true,
    );
    // The failing signal of a formal property (Formal's "Show in NetCrux"):
    // selected, and its single-step fanin shown, free at every tier. The
    // multi-step cone is the Pro cone-of-influence the user widens to.
    if (result.honored &&
        result.reason == null &&
        tab != null &&
        _isFormalSignal(request)) {
      _whenScopeLaidOut(tab, (laidOut) {
        final selection = tab.read(selectedElementProvider);
        if (selection.isEmpty) return;
        tab
            .read(traceOverlayProvider.notifier)
            .set(
              const TraceService().compute(
                laidOut: laidOut,
                selection: selection.primary,
                mode: TraceOverlayMode.fanin,
              ),
            );
      });
    }
    return CruxCxpHandlerResult(honored: result.honored, reason: result.reason);
  }

  /// A formal property a peer sent (CXP `property`, `<file>:<line>`): the
  /// union fanin cone of every signal it reads, NetCrux Pro's `coi`.
  ///
  /// Finding the property and its signals is free and runs first, so a
  /// property this design does not have is declined the same at every tier.
  /// The cone is the overlay's: without it the answer is the "requires
  /// NetCrux Pro" toast, and with it a licence that does not admit the cone
  /// gets a toast naming the tier. Nobody in this window asked, so a denial
  /// is never the upgrade dialog.
  Future<({bool honored, String? reason})> _highlightProperty(
    ElementId element,
    PeerIdentity from,
  ) async {
    final tab = activeTabContainerLookup();
    if (tab == null) return (honored: false, reason: 'No active tab');
    final model = tab.read(hierarchyTreeProvider).model;
    if (model == null) return (honored: false, reason: 'No design loaded');
    final location = PropertyLocation.parse(element.path);
    if (location == null) {
      return (
        honored: false,
        reason: 'the property is not a project-relative <file>:<line>',
      );
    }
    final source = designSourceFor(
      tab.read(currentProjectProvider).sourceFiles,
      location,
    );
    if (source == null) {
      return (
        honored: false,
        reason: 'the property is not in a source file of the open design',
      );
    }
    final statement = await readPropertyStatement(source, location.line);
    final reads = statement == null
        ? null
        : placePropertyReads(
            model: model,
            current: tab.read(hierarchyTreeProvider).selected,
            location: location,
            identifiers: propertyIdentifiers(statement),
          );
    if (reads == null || reads.isEmpty) {
      return (honored: false, reason: 'the property reads no signal here');
    }

    final peer = cruxCxpDisplayName(from.productName);
    // The null seam: only the Pro overlay binds the cone, so a null one is
    // a build without it.
    final cone = rootContainer.read(inboundPropertyConeProvider);
    if (cone == null) {
      _notice((l10n) => l10n.actionRequiresPro(l10n.cxpPropertyConeFeature));
      return (honored: false, reason: 'the property cone needs NetCrux Pro');
    }
    final denied = cone.deniedTier();
    if (denied != null) {
      _notice(
        (l10n) => l10n.upgradeDialogMessage(
          l10n.cxpPropertyConeFromPeer(peer),
          denied == LicenseTier.enterprise
              ? l10n.upgradeDialogTierNameEnterprise
              : l10n.upgradeDialogTierNamePro,
        ),
      );
      return (
        honored: false,
        reason:
            'the property cone needs NetCrux '
            '${denied == LicenseTier.enterprise ? 'Enterprise' : 'Pro'}',
      );
    }

    _showScope(tab, reads.scope);
    final module = reads.scope.resolve(model)!;
    final names = <String>[
      ...reads.local,
      ...cone.sameNetsInScope(
        model: model,
        scopePath: reads.scope.path,
        names: reads.otherScopes,
      ),
    ];
    final seeds = <SelectedElement>[];
    Selection? selection;
    for (final name in names) {
      final net = findNetNamed(module, name);
      final found = net == null ? null : selectionForNet(module, net);
      if (found == null) continue;
      seeds.addAll(found.elements);
      selection = selection == null
          ? found
          : Selection(
              elements: <SelectedElement>{
                ...selection.elements,
                ...found.elements,
              },
              primary: selection.primary,
            );
    }
    if (selection == null) {
      return (honored: false, reason: 'the property reads no signal here');
    }
    tab.read(selectedElementProvider.notifier).replace(selection);
    _whenScopeLaidOut(tab, (laidOut) {
      unawaited(
        cone.unionCone(laidOut, seeds).then((overlay) {
          tab.read(traceOverlayProvider.notifier).set(overlay);
        }, onError: (Object _) {}),
      );
    });
    return (honored: true, reason: null);
  }

  /// A path from an implementation run, sent as one `notify_selection`
  /// (CXP §8.2, Flow §9.1): the `timing_path`, `signal` elements for its
  /// mapped registers, start first, and `source` elements for its
  /// statements, with `crux.mapping` saying how the registers were mapped.
  ///
  /// Each register is placed by its full hierarchical name; the scope of the
  /// path's last register (its endpoint) is shown, and every register in it
  /// is highlighted. The path, the mapping the sender stated (never
  /// upgraded) and where each register landed go to this tab's Inspector,
  /// which is revealed without taking focus. A selection is not
  /// acknowledged, so a register that is not in the design is said there.
  Future<void> _handleTimingPath(
    NotifySelection message,
    PeerIdentity from,
  ) async {
    final fidelity = TimingPathFidelity.parse(
      message.metadata[cxpMappingMetadataKey],
    );
    final tab = activeTabContainerLookup();
    final model = tab?.read(hierarchyTreeProvider).model;
    final signals = <String>[
      for (final e in message.elements)
        if (e.kind == ElementKind.signal) ?_nameResolver.toLocal(e),
    ];
    final statements = <String>[
      for (final e in message.elements)
        if (e.kind == ElementKind.source) _statementLabel(e.path),
    ];
    if (tab == null || model == null) {
      _recordPathHighlighted(fidelity, resolved: false);
      return;
    }

    final current = tab.read(hierarchyTreeProvider).selected;
    final placed = <(String, CxpScopedName?)>[
      for (final name in signals) (name, _placeRegister(model, current, name)),
    ];
    final shown = placed.reversed
        .map((entry) => entry.$2?.scope)
        .whereType<HierarchyNode>()
        .firstOrNull;
    final registers = <TimingPathRegister>[];
    Selection? selection;
    if (shown != null) {
      final module = shown.resolve(model);
      for (final (name, scoped) in placed) {
        if (scoped == null) {
          registers.add(
            TimingPathRegister(
              name: name,
              place: TimingPathRegisterPlace.notFound,
            ),
          );
          continue;
        }
        if (scoped.scope != shown || module == null) {
          registers.add(
            TimingPathRegister(
              name: name,
              place: TimingPathRegisterPlace.otherScope,
            ),
          );
          continue;
        }
        final net = findNetNamed(module, scoped.leaf)!;
        final found = selectionForNet(module, net);
        if (found != null) {
          selection = selection == null
              ? found
              : Selection(
                  elements: <SelectedElement>{
                    ...selection.elements,
                    ...found.elements,
                  },
                  primary: found.primary,
                );
        }
        registers.add(
          TimingPathRegister(name: name, place: TimingPathRegisterPlace.shown),
        );
      }
      _showScope(tab, shown);
      if (selection != null) {
        tab.read(selectedElementProvider.notifier).replace(selection);
        _revealElement(tab, selection.primary);
      }
    } else {
      registers.addAll(<TimingPathRegister>[
        for (final name in signals)
          TimingPathRegister(
            name: name,
            place: TimingPathRegisterPlace.notFound,
          ),
      ]);
    }

    final path = ReceivedTimingPath(
      peer: cruxCxpDisplayName(from.productName),
      fidelity: fidelity,
      registers: registers,
      statements: statements,
    );
    tab.read(receivedTimingPathProvider.notifier).show(path);
    _revealInspectorTab();
    _recordPathHighlighted(fidelity, resolved: path.resolved);
    if (path.resolved) _requestAttentionForSelection();
  }

  /// Places a register name a timing path carries: in the scope its rooted
  /// name names, or, for a name not rooted at this design's top, in the
  /// scope on screen by its leaf. Null when the design has no such net.
  static CxpScopedName? _placeRegister(
    NetlistModel model,
    HierarchyNode? current,
    String name,
  ) {
    final placed =
        scopeOfHierarchicalName(model, name) ??
        (current == null
            ? null
            : CxpScopedName(scope: current, leaf: _inboundLeaf(name)));
    if (placed == null || placed.leaf.isEmpty) return null;
    final module = placed.scope.resolve(model);
    if (module == null || findNetNamed(module, placed.leaf) == null) {
      return null;
    }
    return placed;
  }

  /// A statement's `source` element as a short label: the file's name and
  /// the line (`div.v:21`). Display only: nothing is opened from it.
  static String _statementLabel(String path) {
    final hash = path.indexOf('#L');
    final file = hash < 0 ? path : path.substring(0, hash);
    final fragment = hash < 0 ? '' : path.substring(hash + 2);
    final line = fragment.split(':').first;
    final name = p.posix.basename(file.replaceAll(r'\', '/'));
    return line.isEmpty ? name : '$name:$line';
  }

  /// Shows this tab's Inspector without moving focus, so a received path is
  /// readable without a gesture.
  void _revealInspectorTab() {
    final reveal = _revealInspector;
    if (reveal != null) {
      reveal();
      return;
    }
    try {
      rootContainer
          .read(rightDockTabProvider.notifier)
          .reveal(kRightDockTabInspector);
    } on Object {
      // No dock in this build (a headless harness): the section is still
      // there when the Inspector is opened.
    }
  }

  /// `flow.path.highlighted`: whether a path that arrived landed on
  /// anything, and how it was mapped. Never a name or a path.
  void _recordPathHighlighted(
    TimingPathFidelity fidelity, {
    required bool resolved,
  }) {
    rootContainer
        .read(telemetryServiceProvider)
        .record(
          TelemetryEvent(
            'flow.path.highlighted',
            properties: <String, Object?>{
              'fidelity': fidelity.token,
              'resolved': resolved,
            },
          ),
        );
  }

  /// Whether [request] names a formal property's failing signal: a `signal`
  /// that carries the property's registered `formal.` keys.
  static bool _isFormalSignal(RequestHighlight request) =>
      request.element.kind == ElementKind.signal &&
      (request.metadata.containsKey(cxpFormalPropertyKindMetadataKey) ||
          request.metadata.containsKey(cxpFormalPropertyLabelMetadataKey));

  /// Handles an inbound `notify_selection`, a peer's live selection gossip.
  /// The mirror of WaveCrux's `handleInboundSelection`: resolve the first
  /// signal-like element and highlight it (opening the design via the shared
  /// workspace when it isn't loaded). It is fire-and-forget, so nothing is
  /// acknowledged and the runtime asks for no attention: the one attention
  /// request here is this handler's own, gated on the user's setting.
  ///
  /// A selection that names a `timing_path` is a whole path from an
  /// implementation run (Flow): its registers are highlighted together and
  /// the path is shown in the Inspector.
  @override
  void selection(NotifySelection message, PeerIdentity from) {
    if (message.elements.any((e) => e.kind == ElementKind.timingPath)) {
      unawaited(_handleTimingPath(message, from));
      return;
    }
    unawaited(_handleNotifySelection(message));
  }

  Future<void> _handleNotifySelection(NotifySelection message) async {
    for (final element in message.elements) {
      if (!_isSignalLikeKind(element.kind)) continue;
      final result = await _resolveAndAct(
        element,
        message.metadata,
        frame: false,
      );
      if (result.honored) {
        _requestAttentionForSelection();
        return;
      }
    }
  }

  /// Asks the window manager for the user's attention, without stealing focus,
  /// when the user has that on. Used only for a live selection, which is not a
  /// request and so is not covered by the runtime's own attention request.
  void _requestAttentionForSelection() {
    if (!rootContainer.read(cruxCxpSettingsProvider).requestAttention) return;
    rootContainer.read(cruxCxpAttentionRequesterProvider)?.call();
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
    if (await _openDesignFromWorkspace(element, metadata, frame: frame)) {
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
          reason: 'the scope was not found in the open design',
        );
      }
      return (honored: true, reason: null);
    }

    // A cell of a netlist (CXP §8.2: `<top>.<flat cell name>`): found in the
    // scope its path names, never by its leaf anywhere else.
    if (element.kind == ElementKind.cell) {
      return _applyCell(tabContainer, local);
    }

    // A signal or a named net whose path is rooted at this design's top
    // (`top.u_div.cnt_q`) is looked up in the scope the path names, and that
    // scope is shown. A name rooted elsewhere (a waveform's testbench path)
    // keeps the leaf match below, in the scope on screen.
    if ((element.kind == ElementKind.signal ||
            element.kind == ElementKind.net) &&
        !local.contains(':net:')) {
      final rooted = _applyRooted(tabContainer, local);
      if (rooted != null) return rooted;
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
        // Pre-validate against the current scope's netlist module, never its
        // schematic graph: a scope held back for its size must not be walked
        // whole to answer whether one element is there.
        if (_selectionExists(tabContainer, element)) {
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
      return (honored: false, reason: 'Unsupported element kind');
    }
    final leaf = _inboundLeaf(local);
    if (leaf.isNotEmpty && _applyLeafMatch(tabContainer, leaf)) {
      return (honored: true, reason: null);
    }

    return (honored: false, reason: kCxpElementNotInDesign);
  }

  /// Resolves a hierarchical name rooted at the design's top in the scope it
  /// names, shows that scope and selects the net (every drawn strand, or the
  /// register driving it when it has none). Null when [local] is not rooted
  /// at this design's top, so the caller keeps its own fallback; a rooted
  /// name that is not in its scope is declined, never leaf-matched in
  /// another scope.
  ({bool honored, String? reason})? _applyRooted(
    ProviderContainer tab,
    String local,
  ) {
    final model = tab.read(hierarchyTreeProvider).model;
    if (model == null) return null;
    final scoped = scopeOfHierarchicalName(model, local);
    if (scoped == null) return null;
    final module = scoped.scope.resolve(model);
    final net = module == null ? null : findNetNamed(module, scoped.leaf);
    if (module == null || net == null) {
      return (honored: false, reason: kCxpElementNotInDesign);
    }
    final selection = selectionForNet(module, net);
    if (selection == null) {
      return (honored: false, reason: 'the element is not drawn in its scope');
    }
    _showScope(tab, scoped.scope);
    tab.read(selectedElementProvider.notifier).replace(selection);
    _revealElement(tab, selection.primary);
    return (honored: true, reason: null);
  }

  /// Selects the netlist cell [local] names (`<top>.<flat cell name>`) and
  /// reveals it, in the scope the name's instance prefix names. A flattened
  /// netlist keeps the whole flat name (`u_div.cnt_q_reg`) as one cell of the
  /// top, which the walk finds because `u_div` is then not an instance.
  ({bool honored, String? reason}) _applyCell(
    ProviderContainer tab,
    String local,
  ) {
    final model = tab.read(hierarchyTreeProvider).model;
    if (model == null) return (honored: false, reason: 'No design loaded');
    final scoped = scopeOfHierarchicalName(model, local);
    final module = scoped?.scope.resolve(model);
    if (scoped == null ||
        module == null ||
        !module.cells.containsKey(scoped.leaf)) {
      return (honored: false, reason: kCxpElementNotInDesign);
    }
    if (!schematicDrawsCell(module, scoped.leaf)) {
      return (honored: false, reason: 'the element is not drawn in its scope');
    }
    _showScope(tab, scoped.scope);
    tab
        .read(selectedElementProvider.notifier)
        .select(SelectedElement.cell(cellId: scoped.leaf));
    tab.read(revealRequestProvider.notifier).request(scoped.leaf);
    return (honored: true, reason: null);
  }

  /// Makes [scope] the scope on screen when it is not already, and flashes
  /// its hierarchy row so the move is visible.
  void _showScope(ProviderContainer tab, HierarchyNode scope) {
    final tree = tab.read(hierarchyTreeProvider);
    if (tree.selected == scope) return;
    tab.read(hierarchyTreeProvider.notifier).selectScope(scope);
    tab.read(scopeFlashProvider.notifier).flash(scope.path);
  }

  /// Runs [action] with the laid-out schematic of the scope on screen, now
  /// when it is laid out, or as soon as the layout lands (a scope that was
  /// just shown lays out on a background isolate). Bounded like the deferred
  /// select; [dispose] tears it down.
  void _whenScopeLaidOut(
    ProviderContainer tab,
    void Function(LaidOutGraph laidOut) action,
  ) {
    ProviderSubscription<AsyncValue<LaidOutGraph>>? sub;
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

    void attempt(AsyncValue<LaidOutGraph> value) {
      if (done) return;
      final laidOut = value.value;
      final scope = tab.read(hierarchyTreeProvider).selected;
      if (value.isLoading ||
          laidOut == null ||
          laidOut.isEmpty ||
          scope == null ||
          laidOut.graph.moduleName != scope.moduleName) {
        return;
      }
      cleanup();
      action(laidOut);
    }

    timer = Timer(const Duration(seconds: 15), cleanup);
    _deferredTimers.add(timer);
    sub = tab.listen<AsyncValue<LaidOutGraph>>(
      currentLaidOutGraphProvider,
      (_, next) => attempt(next),
      fireImmediately: true,
    );
    if (done) {
      sub.close();
    } else {
      _deferredSubs.add(sub);
    }
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

    // The scope's netlist module answers all three, so a scope held back for
    // its size is never built into a schematic graph to be searched.
    // 1. Named net → whole-net wire selection (symmetric to WaveCrux lighting
    // a signal lane).
    final net = module.nets[leaf];
    if (net != null) {
      final selection = wholeNetWireSelection(module, net);
      if (selection != null) {
        tabContainer.read(selectedElementProvider.notifier).replace(selection);
        return true;
      }
    }
    // 2. Boundary port.
    if (schematicDrawsBoundaryPort(module, leaf)) {
      tabContainer
          .read(selectedElementProvider.notifier)
          .select(
            SelectedElement.boundaryPort(portId: 'port:$leaf', portName: leaf),
          );
      return true;
    }
    // 3. Cell instance → select + reveal.
    if (schematicDrawsCell(module, leaf)) {
      tabContainer
          .read(selectedElementProvider.notifier)
          .select(SelectedElement.cell(cellId: leaf));
      tabContainer.read(revealRequestProvider.notifier).request(leaf);
      return true;
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
  Future<bool> _openDesignFromWorkspace(
    ElementId element,
    Map<String, Object?> metadata, {
    required bool frame,
  }) async {
    final designId = metadata[cxpDesignIdMetadataKey];
    if (designId is! String || designId.isEmpty) return false;
    final path = await resolveDesignSourceArtifactPath(rootContainer, designId);
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
    // Segments as the netlist names them: an escaped identifier (`\a.b `) or
    // a `$`-name keeps its dots.
    final segments = NetcruxNameResolver.splitHierarchicalPath(tail);
    if (segments.isEmpty) return '';
    return segments.last.replaceFirst(_busBitSelectSuffix, '');
  }

  /// A trailing numeric bit-select / slice on a signal leaf: `[7:0]`, `[3]`.
  static final RegExp _busBitSelectSuffix = RegExp(r'\[\d+(?::\d+)?\]$');

  /// Handles an inbound `request_open_artifact` (shared-workspace consumer):
  /// NetCrux opens `source` and `project` artifacts, resolving the concrete
  /// file through its shared workspace store (preferring that over the
  /// sender's hint path, whose absolute path may not exist on this machine's
  /// layout) and loading it into the active tab. A `source` is one HDL file,
  /// loaded as a single-file design; a `project` is a `.netcrux-project`, a
  /// `<design>.crux-project` manifest or a `.f` filelist, opened through the
  /// project loader so a multi-file design arrives with its source list, top
  /// module, defines and include paths. Acks honored=false with a reason when
  /// the kind is neither, neither a record nor a hint names a file, the path
  /// fails the floor ([kCxpOpenArtifactContainment]: empty, relative, a NUL,
  /// or padded with white space), it is not a file here, no tab is active, or
  /// a `project` file is not one NetCrux reads as a project.
  ///
  /// A design NetCrux has never opened is honoured: this route is not rooted
  /// in the directories the user has opened, and [kCxpOpenArtifactContainment]
  /// says why.
  @override
  Future<CruxCxpHandlerResult> openArtifact(
    RequestOpenArtifact request,
    PeerIdentity from,
  ) async {
    final kind = request.artifactKind;
    final result =
        kind == kCxpFlowRunArtifactKind || kind == kCxpTimingReportArtifactKind
        ? await _openFlowArtifact(request, from)
        : await _resolveOpenArtifact(request);
    return CruxCxpHandlerResult(honored: result.honored, reason: result.reason);
  }

  /// A run directory (`flow_run`) or a run's timing report
  /// (`timing_report`) a peer sent (CXP §9.10.2): the slack overlay's input,
  /// a NetCrux Pro capability ([flowArtifactOpenerProvider]).
  ///
  /// Only the path on the message is considered (NetCrux keeps no record of
  /// runs), held to the floor ([kCxpOpenArtifactContainment]) and to being
  /// the right kind of entry: a directory for a run, a file for a report.
  /// That is checked before the tier, so a malformed path is refused the
  /// same in every build. Without the overlay the answer is the "requires
  /// NetCrux Pro" toast; with it, a licence that does not admit it gets a
  /// toast naming the tier. Reasons never repeat the path.
  Future<({bool honored, String? reason})> _openFlowArtifact(
    RequestOpenArtifact request,
    PeerIdentity from,
  ) async {
    final kind = request.artifactKind;
    final path = request.path;
    if (path == null) {
      return (honored: false, reason: 'no $kind path was sent');
    }
    final refusal = kCxpOpenArtifactContainment.refuse(path);
    if (refusal != null) return (honored: false, reason: refusal);
    final want = kind == kCxpFlowRunArtifactKind
        ? FileSystemEntityType.directory
        : FileSystemEntityType.file;
    if (FileSystemEntity.typeSync(path) != want) {
      return (
        honored: false,
        reason: kind == kCxpFlowRunArtifactKind
            ? 'the run is not a directory here'
            : 'the timing report is not a file here',
      );
    }
    final opener = rootContainer.read(flowArtifactOpenerProvider);
    if (opener == null) {
      _notice((l10n) => l10n.actionRequiresPro(l10n.cxpFlowArtifactFeature));
      return (honored: false, reason: 'opening a $kind needs NetCrux Pro');
    }
    final denied = opener.deniedTier();
    if (denied != null) {
      final peer = cruxCxpDisplayName(from.productName);
      _notice(
        (l10n) => l10n.upgradeDialogMessage(
          l10n.cxpFlowArtifactFromPeer(peer),
          denied == LicenseTier.enterprise
              ? l10n.upgradeDialogTierNameEnterprise
              : l10n.upgradeDialogTierNamePro,
        ),
      );
      return (
        honored: false,
        reason:
            'opening a $kind needs NetCrux '
            '${denied == LicenseTier.enterprise ? 'Enterprise' : 'Pro'}',
      );
    }
    final why = await opener.open(kind: kind, path: path);
    return (honored: why == null, reason: why);
  }

  Future<({bool honored, String? reason})> _resolveOpenArtifact(
    RequestOpenArtifact request,
  ) async {
    final kind = request.artifactKind;
    if (kind != kCxpSourceArtifactKind && kind != kCxpProjectArtifactKind) {
      return (
        honored: false,
        reason: 'netcrux opens only source and project artifacts',
      );
    }
    final path =
        await resolveOpenArtifactPath(
          rootContainer,
          request.designId,
          kind: kind,
        ) ??
        request.path;
    if (path == null) {
      return (
        honored: false,
        reason: 'no $kind artifact recorded for that design',
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
    if (kind == kCxpSourceArtifactKind) {
      tab.read(currentProjectProvider.notifier).setSourceFiles(<String>[path]);
      return (honored: true, reason: null);
    }
    final artifact = await _readProjectArtifact(path);
    final project = artifact.project;
    if (project == null) return (honored: false, reason: artifact.reason);
    tab
        .read(currentProjectProvider.notifier)
        .setProject(project, source: artifact.source);
    return (honored: true, reason: null);
  }

  /// Reads the project a `project` artifact names, in the same three forms
  /// Open Project… and the command line accept: a `<design>.crux-project`
  /// manifest (its netlist, else its sources and top), a `.netcrux-project`
  /// with its relative paths anchored to its own directory, or a `.f`
  /// filelist. Anything else, and a file that does not parse, is refused
  /// with a reason that never repeats the path (CXP §9.11).
  static Future<_ProjectArtifact> _readProjectArtifact(String path) async {
    switch (const CruxProjectResolver().resolve(path)) {
      case ManifestNetlist(:final netlistPath):
        return _ProjectArtifact.loaded(
          NetcruxProject.create(sourceFiles: <String>[netlistPath]),
          NetcruxDesignSource.project,
        );
      case ManifestSources(:final sources, :final top):
        return _ProjectArtifact.loaded(
          NetcruxProject.create(sourceFiles: sources, topModule: top ?? ''),
          NetcruxDesignSource.project,
        );
      case ManifestUnusable(reason: final why):
        return _ProjectArtifact.refused(switch (why) {
          ManifestUnusableReason.invalid =>
            'the manifest is not a valid crux-project file',
          ManifestUnusableReason.netlistMissing =>
            'the manifest names a netlist that is not here',
          ManifestUnusableReason.nothingToOpen =>
            'the manifest names nothing to open',
          ManifestUnusableReason.noManifestInDirectory =>
            'no manifest in that directory',
        });
      case ManifestAmbiguous():
        return const _ProjectArtifact.refused(
          'more than one manifest in that directory',
        );
      case NotAManifest():
        break;
    }
    final lower = path.toLowerCase();
    try {
      if (lower.endsWith('.$kNetcruxProjectExtension')) {
        final project = await const NetcruxProjectFileReader().read(path);
        return _ProjectArtifact.loaded(
          resolveProjectPaths(project, p.dirname(path)),
          NetcruxDesignSource.project,
        );
      }
      if (lower.endsWith('.$kFilelistExtension')) {
        return _ProjectArtifact.loaded(
          await const FilelistReader().readAsProject(path),
          NetcruxDesignSource.filelist,
        );
      }
    } on Object {
      // A malformed or unreadable project file. The exception text can carry
      // the path, so a fixed phrase goes on the wire instead.
      return const _ProjectArtifact.refused(
        'the project file could not be read',
      );
    }
    return const _ProjectArtifact.refused(
      'a project artifact must be a .netcrux-project, a <design>.crux-project '
      'manifest or a .f filelist',
    );
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
  /// row-tap selection (see [wholeNetWireSelection]). The renderer
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

    return wholeNetWireSelection(module, net);
  }

  /// Whether [element] names a cell, cell-port or boundary port that the
  /// schematic of the active tab's current scope draws, answered from the
  /// scope's netlist module. The scope's schematic graph is not built: for a
  /// scope held back for its size that walk over every cell is the cost the
  /// layout limit exists to avoid, and a peer's highlight must not pay it.
  ///
  /// A wire is not a name a peer can send here (a net is resolved by name in
  /// [_resolveNetSelection]), so one is reported as absent.
  bool _selectionExists(
    ProviderContainer tabContainer,
    SelectedElement element,
  ) {
    final tree = tabContainer.read(hierarchyTreeProvider);
    final model = tree.model;
    final node = tree.selected;
    if (model == null || node == null) return false;
    final module = node.resolve(model);
    if (module == null) return false;
    return switch (element) {
      SelectedElementCell(:final cellId) => schematicDrawsCell(module, cellId),
      SelectedElementPort(:final cellId, :final portName) =>
        schematicDrawsCellPort(model, module, cellId, portName),
      SelectedElementWire() => false,
      SelectedElementBoundaryPort(:final portId) => module.ports.values.any(
        (p) => 'port:${p.name}' == portId,
      ),
      SelectedElementNone() => false,
    };
  }

  @override
  Future<CruxCxpHandlerResult> openSource(
    RequestOpenSource request,
    PeerIdentity from,
  ) async {
    final result = await _openSource(
      request.filePath,
      request.line,
      request.column,
    );
    return CruxCxpHandlerResult(honored: result.honored, reason: result.reason);
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
      case KnownElementKind.property:
      case KnownElementKind.timingPath:
      case KnownElementKind.cell:
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

/// The outcome of reading a `project` artifact: the [project] with the
/// [source] to record it under, or the wire-safe [reason] it was refused.
class _ProjectArtifact {
  const _ProjectArtifact.loaded(NetcruxProject this.project, this.source)
    : reason = null;

  const _ProjectArtifact.refused(String this.reason)
    : project = null,
      source = NetcruxDesignSource.project;

  /// The project read from the artifact; null when it was refused.
  final NetcruxProject? project;

  /// How the design reached the tab, for the `schematic.opened` audit line.
  final NetcruxDesignSource source;

  /// Why the artifact was refused; null when [project] is set. Never carries
  /// the path (CXP §9.11).
  final String? reason;
}
