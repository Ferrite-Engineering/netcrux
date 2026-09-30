// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_cxp/crux_cxp.dart';
import 'package:meta/meta.dart';
import 'package:netcrux/domain/models/netlist/bit_ref.dart';
import 'package:netcrux/domain/models/netlist/hierarchy_node.dart';
import 'package:netcrux/domain/models/netlist/module.dart';
import 'package:netcrux/domain/models/netlist/netlist_model.dart';
import 'package:netcrux/domain/models/netlist/port_direction.dart';
import 'package:netcrux/domain/models/selection/element_path.dart';
import 'package:netcrux/domain/models/selection/selected_element.dart';
import 'package:netcrux/services/remote/cxp/netcrux_name_resolver.dart';
import 'package:netcrux/services/schematic/net_name_lookup.dart';

/// A selection that has been translated into over-the-wire CXP form.
@immutable
class ResolvedCxpSelection {
  /// Creates a resolved selection.
  const ResolvedCxpSelection({
    required this.element,
    required this.displayName,
    required this.scopePath,
  });

  /// Canonical [ElementId] for the selected element.
  final ElementId element;

  /// Human-friendly label for the element (cell id, port name, …).
  final String? displayName;

  /// Canonical hierarchical path of the scope the element lives in,
  /// carried as `netcrux.scope_path` metadata so peers can navigate.
  final String scopePath;

  /// The `notify_selection` message this selection produces.
  ///
  /// [extraMetadata] is merged on top of the always-present
  /// `netcrux.scope_path` hint — the shared-workspace link uses it
  /// to attach `crux.design_id` so a receiver that cannot resolve the element
  /// locally can open the right artifact via its workspace manifest. Kept an
  /// **optional positional** so call sites without metadata stay unchanged.
  NotifySelection toNotifySelection([Map<String, Object?>? extraMetadata]) =>
      NotifySelection(
        elements: <ElementId>[element],
        displayName: displayName,
        metadata: <String, Object?>{
          'netcrux.scope_path': scopePath,
          ...?extraMetadata,
        },
      );

  /// The `request_highlight` message this selection produces — the ack-bearing
  /// form the cross-probe panel's per-peer send uses so a rejected send can be
  /// surfaced to the user, versus the fire-and-forget [toNotifySelection] the
  /// automatic emitter broadcasts. Carries the same `netcrux.scope_path` hint
  /// plus any [extraMetadata] (e.g. `crux.design_id` for the shared workspace).
  RequestHighlight toRequestHighlight([Map<String, Object?>? extraMetadata]) =>
      RequestHighlight(
        element: element,
        metadata: <String, Object?>{
          'netcrux.scope_path': scopePath,
          ...?extraMetadata,
        },
      );
}

/// Translates [element] — selected inside [scope] of [model] — into
/// canonical CXP form, or `null` when it cannot be resolved.
///
/// Takes the pure model + scope rather than the hierarchy notifier's
/// state so this stays a `services/`-layer function with no `features/`
/// dependency (ARCHITECTURE §6.2); callers pass
/// `tree.model` / `tree.selected`.
///
/// Resolution fails (returns `null`) when nothing is selected, when no
/// model / scope / top module is loaded, or when the element has no
/// canonical path. Every outbound cross-probe path in NetCrux funnels
/// through this one function so the automatic selection broadcast
/// (`CxpOutboundEmitterController`) and the cross-probe panel's
/// peer-targeted send emit byte-identical references.
ResolvedCxpSelection? resolveCxpSelection({
  required SelectedElement element,
  required NetlistModel? model,
  required HierarchyNode? scope,
}) {
  if (element is SelectedElementNone) return null;
  if (model == null || scope == null) return null;
  final top = model.topModule;
  if (top == null) return null;

  // Wire selections carry the net's HUMAN NAME over the wire, not the
  // opaque synthesized graph edge id. `buildElementPath`'s WIRE case emits
  // `<scope>:net:<edgeId>` — an id no peer can match against its own model.
  // A peer (WaveCrux) matches on the hierarchical net name, so reverse-
  // resolve the selected wire's netId to the net that declares it and emit
  // `<scope>.<netName>` (the dot-joined convention documented in
  // element_path.dart / NetcruxNameResolver). Falls back to the opaque
  // `:net:` form only when no NAMED net carries the bit (a genuinely
  // internal/anonymous wire).
  if (element is SelectedElementWire) {
    final netName = netNameForId(scope.resolve(model), element.netId);
    if (netName != null) {
      final scopePrefix = <String>[top.name, ...scope.path].join('.');
      return ResolvedCxpSelection(
        element: ElementId(
          kind: ElementKind.net,
          path: '$scopePrefix.$netName',
        ),
        displayName: netName,
        scopePath: scope.canonicalPath(model),
      );
    }
    // Fall through to the opaque `:net:` form below for anonymous wires.
  }

  // Boundary ports and cells carry a CLEAN dot-joined hierarchical NAME over
  // the wire — never `buildElementPath`'s `:port:` / `:cell` markers, which a
  // peer's leaf-matcher (WaveCrux splits on `.`) cannot parse. `buildElementPath`
  // keeps emitting the marked form for "Copy Path" / local resolution, so it is
  // deliberately bypassed here (mirroring the wire case above). The CXP
  // `ElementKind` is carried separately, so the path needs no in-band marker.
  if (element is SelectedElementBoundaryPort) {
    // The boundary port lives on the scope module itself, so the parent is the
    // scope prefix and the leaf is the bare port name: `fsm_lock.state`.
    final scopePrefix = <String>[top.name, ...scope.path].join('.');
    return ResolvedCxpSelection(
      element: ElementId(
        kind: ElementKind.port,
        path: '$scopePrefix.${element.portName}',
      ),
      displayName: element.portName,
      scopePath: scope.canonicalPath(model),
    );
  }
  if (element is SelectedElementCell) {
    final scopePrefix = <String>[top.name, ...scope.path].join('.');
    // A synthesized register/flop cell (`$procdff$9`, `$dff…`) has no
    // waveform-matchable name — the VCD carries the RTL reg name (`alarm_r`),
    // which Yosys preserves as the flop's Q-output net. Resolve the cell to that
    // net and emit `kind: net` so a peer (WaveCrux) leaf-matches the waveform
    // signal, instead of the unmatchable cell name. Only real instances /
    // submodules (and registers whose Q net is synthetic/unnamed) stay
    // `kind: instance`.
    final regNet = _registerOutputNetName(scope.resolve(model), element.cellId);
    if (regNet != null) {
      return ResolvedCxpSelection(
        element: ElementId(
          kind: ElementKind.net,
          path: '$scopePrefix.$regNet',
        ),
        displayName: regNet,
        scopePath: scope.canonicalPath(model),
      );
    }
    // Drop `buildElementPath`'s `:cell` marker so a receiver can leaf-match the
    // instance name (`top.u_cpu`). Kind `instance` disambiguates it from a net.
    return ResolvedCxpSelection(
      element: ElementId(
        kind: ElementKind.instance,
        path: '$scopePrefix.${element.cellId}',
      ),
      displayName: element.cellId,
      scopePath: scope.canonicalPath(model),
    );
  }

  final localPath = buildElementPath(
    topModuleName: top.name,
    scope: scope,
    element: element,
  );
  if (localPath == null) return null;

  const resolver = NetcruxNameResolver();
  final canonical = resolver.toCanonical(
    kind: cxpElementKindFor(element),
    local: localPath,
  );
  if (canonical == null) return null;

  return ResolvedCxpSelection(
    element: canonical,
    displayName: cxpDisplayNameFor(element),
    scopePath: scope.canonicalPath(model),
  );
}

/// Resolves a selected register/flop cell ([cellId]) inside [module] to the
/// human RTL name of its Q-output net (`alarm_r`), or `null` when the cell is
/// not a register, is absent, or its output net has no source-declared name
/// (a synthetic `$…` net the caller should fall back to the instance name for).
///
/// Yosys keeps the RTL reg name as the flop's Q-output net, and the waveform
/// carries that same signal name — so emitting the net name (not the
/// synthesized `$procdff$9` cell name) is what lets a peer leaf-match the VCD
/// signal (the outbound complement of the inbound leaf-match).
///
/// When the Q net carries SEVERAL public aliases — `opt_clean` folds
/// `assign alarm = alarm_r` into ONE net that carries BOTH `alarm_r` and
/// `alarm` — the alias equal to the register cell's own name ([cellId]) wins,
/// so cross-probing the register the user selected emits `alarm_r`, not the
/// coincidental output-port alias `alarm`.
String? _registerOutputNetName(Module? module, String cellId) {
  if (module == null) return null;
  final cell = module.cells[cellId];
  if (cell == null || !_isRegisterCellType(cell.type)) return null;
  // Prefer the conventional `Q` output, then any other output port.
  final ports = <String>[
    'Q',
    for (final name in cell.portDirections.keys)
      if (name != 'Q') name,
  ];
  for (final portName in ports) {
    if (cell.portDirections[portName] != PortDirection.output) continue;
    final bits = cell.connections[portName];
    if (bits == null) continue;
    for (final bit in bits) {
      if (bit is! NetBit) continue;
      // Returns only a waveform-matchable (public, non-`$`) alias, preferring
      // the one matching the register's own name; `null` when the Q net has
      // only synthetic names so the caller falls back to the instance name.
      final name = _preferredNetAlias(module, bit.netId, cellId);
      if (name != null) return name;
    }
  }
  return null;
}

/// Whether [type] names a Yosys register/flop (or latch) cell — the classes
/// whose selection should resolve to their output net rather than the
/// synthesized cell name. Matches `$dff`, `$adff`, `$sdff`, `$dffe`,
/// `$procdff`, `$_DFF_*`, `$dlatch`, … case-insensitively.
bool _isRegisterCellType(String type) {
  final t = type.toLowerCase();
  return t.contains('dff') || t.contains('dlatch');
}

/// Returns the best waveform-matchable (public, source-declared, non-`$`)
/// alias name among the nets carrying [netId] in [module], or `null` when the
/// net has only synthetic auto-generated names (so the caller falls back to
/// the instance name).
///
/// A single netId can carry several public aliases: Yosys `opt_clean` folds
/// `assign alarm = alarm_r` into ONE net that carries BOTH `alarm_r` (the
/// internal reg) and `alarm` (the output port). The user selected the
/// REGISTER, so the alias that names the register must win over the
/// coincidental output-port alias. Preference order:
///
///   1. The alias equal to [preferName] — the selected flop cell's own name —
///      for the case where the flop is public-named (`\reg_r`) and that name
///      is itself one of the aliases.
///   2. An INTERNAL alias (not a module boundary-port name). In the real
///      elaboration the flop is a SYNTHETIC `$procdff$9` cell (so [preferName]
///      matches nothing), and the merged net carries `alarm` (a module output
///      port) and `alarm_r` (the internal reg) — this picks `alarm_r`, the
///      register the user selected, not the output-port alias `alarm`.
///   3. The first source-declared alias (single-alias nets, or the degenerate
///      all-ports case). A multi-bit user bus like `sample_a` still beats the
///      `$0\sample_a[7:0]` next-state shadow, which is `hide_name`d/`$`-prefixed.
String? _preferredNetAlias(Module module, int netId, String preferName) {
  final publicAliases = <String>[
    for (final net in module.nets.values)
      // Only source-declared, non-synthetic names are waveform-matchable.
      if (!net.hideName && !net.name.startsWith(r'$'))
        if (net.bits.any((b) => b is NetBit && b.netId == netId)) net.name,
  ];
  if (publicAliases.isEmpty) return null;
  // 1. The flop's own name, when it is public-named and aliases the Q net.
  if (publicAliases.contains(preferName)) return preferName;
  // 2. Prefer an internal (non-boundary-port) alias — the register name over
  //    the output-port name the register happens to be assigned to.
  for (final alias in publicAliases) {
    if (!module.ports.containsKey(alias)) return alias;
  }
  // 3. Every alias is a port (or there is just one) — take the first.
  return publicAliases.first;
}

/// Maps a NetCrux [SelectedElement] onto the CXP [ElementKind] a peer
/// understands.
ElementKind cxpElementKindFor(SelectedElement element) => switch (element) {
  SelectedElementNone() => ElementKind.instance,
  SelectedElementCell() => ElementKind.instance,
  SelectedElementPort() => ElementKind.port,
  SelectedElementBoundaryPort() => ElementKind.port,
  SelectedElementWire() => ElementKind.net,
};

/// Human-friendly label for [element], used as the `display_name` on the
/// wire so a peer can render something readable without re-parsing the
/// canonical path.
String? cxpDisplayNameFor(SelectedElement element) => switch (element) {
  SelectedElementNone() => null,
  SelectedElementCell(:final cellId) => cellId,
  SelectedElementPort(:final portName) => portName,
  SelectedElementBoundaryPort(:final portName) => portName,
  SelectedElementWire(:final netId) => 'net_$netId',
};
