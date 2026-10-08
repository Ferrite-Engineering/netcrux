// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_telemetry/crux_telemetry.dart';
import 'package:meta/meta.dart';

/// One entry of the NetCrux event catalog: an event name and the closed
/// vocabulary of each property it may carry.
///
/// [enumeratedValues] lists the string values a property key is allowed to
/// take. A key mapped to an empty list carries something that is not a closed
/// string set — a bool, or a bounded integer — and is checked by the
/// conformance test's per-key rules instead.
@immutable
class TelemetryCatalogEvent {
  /// Pins one catalog event and its property vocabulary.
  const TelemetryCatalogEvent(
    this.name, {
    this.enumeratedValues = const <String, List<String>>{},
    this.boolProperties = const <String>[],
    this.intProperties = const <String>[],
  });

  /// The catalog event name, as recorded.
  final String name;

  /// String-valued properties → every value the call site may emit.
  final Map<String, List<String>> enumeratedValues;

  /// Properties whose value is a `bool`.
  final List<String> boolProperties;

  /// Properties whose value is a bounded integer.
  final List<String> intProperties;

  /// Every property key this event may carry.
  Iterable<String> get propertyKeys => <String>[
    ...enumeratedValues.keys,
    ...boolProperties,
    ...intProperties,
  ];
}

/// **The** NetCrux event catalog — every telemetry event either repository
/// may record, with the closed vocabulary of every property.
///
/// This list is the pinned, published event catalog. Two
/// tests hold it to that role: one scans both source trees and fails on an
/// event name that is recorded but not listed here, and one checks every name,
/// key and value in this list against the ingestion Worker's grammar.
///
/// The second check is the load-bearing one. The Worker drops a malformed
/// event name *silently* — the batch still returns 202, the row is counted
/// only in the response's `dropped` field, and the client is not told. A
/// property whose key or value fails its class is dropped while the event is
/// kept, which is worse: the counter looks healthy and its dimension is
/// simply, permanently empty. Neither failure is visible from the app, from
/// the queue, or from a dashboard that has never seen the missing rows. The
/// conformance test is the only place either one can be caught.
const List<TelemetryCatalogEvent>
kNetcruxEventCatalog = <TelemetryCatalogEvent>[
  // ── workspace, tabs, panes (open core) ─────────────────────────────────
  // The shared suite set: same names as WaveCrux, emitted at the matching
  // seams of `crux_workspace`'s notifier so the two products' workspace
  // numbers are directly comparable.
  TelemetryCatalogEvent(
    'workspace.restored',
    intProperties: <String>['tabs', 'panes'],
  ),
  TelemetryCatalogEvent('workspace.created'),
  TelemetryCatalogEvent('workspace.reset'),
  TelemetryCatalogEvent('workspace.named.saved'),
  TelemetryCatalogEvent(
    'workspace.named.opened',
    intProperties: <String>['tabs', 'panes'],
  ),
  TelemetryCatalogEvent(
    'tab.opened',
    intProperties: <String>['tabs', 'panes'],
  ),
  TelemetryCatalogEvent('tab.dragged_to_pane'),
  TelemetryCatalogEvent('pane.split'),
  TelemetryCatalogEvent('pane.closed'),

  // ── the elaboration funnel (open core) ─────────────────────────────────
  TelemetryCatalogEvent(
    'design.elaborated',
    enumeratedValues: <String, List<String>>{
      // `NetcruxDesignLanguageMix.values` under `telemetryEnumToken`. NOT
      // derived from anything about the file being elaborated — the mix is
      // folded from each source's `NetcruxProject.resolveLanguage`, which
      // is itself a closed enum.
      'language': <String>['verilog', 'system_verilog', 'vhdl', 'mixed'],
      // `NetcruxDesignSource.values` under `telemetryEnumToken` — which of
      // the four entry paths the user took, carried on the
      // `CurrentProject` notifier rather than inferred from a path.
      //
      // `netlist_json` is its own value because it is not RTL: an
      // already-elaborated netlist is the output of elaboration, so counting
      // it as `rtl` would overstate how often users bring source to NetCrux.
      'source': <String>['rtl', 'project', 'filelist', 'netlist_json'],
    },
    // Elaboration-cache hit. The single most useful bit for the sub-50 ms
    // cache-hit budget: it says how often the cache is what the user
    // actually experienced.
    boolProperties: <String>['cached'],
  ),
  TelemetryCatalogEvent(
    'design.elaboration_failed',
    enumeratedValues: <String, List<String>>{
      // `LoadedNetlistErrorKind.values` under `telemetryEnumToken`, and
      // nothing else. NEVER a Yosys diagnostic, a stderr line, or an
      // exception message: a failure reason is a classification NetCrux
      // made, not text a compiler produced, and the never-collect list
      // (`https://edacrux.app/telemetry`) rules out the latter absolutely.
      // The typed kind already exists because the schematic error view
      // needs it to pick a localized message, so this costs no new
      // vocabulary.
      'reason': <String>[
        'yosys_unavailable',
        'timeout',
        'non_zero_exit',
        'unknown',
      ],
    },
  ),

  // ── navigation, search, trace, export (open core) ──────────────────────
  TelemetryCatalogEvent('schematic.scope_pushed'),
  TelemetryCatalogEvent(
    'search.used',
    enumeratedValues: <String, List<String>>{
      // `SearchMode.values` — already lowercase single words, so the call
      // site still routes them through `telemetryEnumToken` and the
      // conformance test derives this list from the enum.
      'mode': <String>['substring', 'glob', 'regex'],
    },
  ),
  TelemetryCatalogEvent(
    'trace.used',
    enumeratedValues: <String, List<String>>{
      // `TraceOverlayMode.values`. Open-core single-step tracing; the Pro
      // transitive cone reports `analysis.run {kind: coi}` instead, which
      // is what makes the free-vs-paid comparison possible.
      'kind': <String>['fanin', 'fanout'],
    },
  ),
  TelemetryCatalogEvent(
    'export.completed',
    enumeratedValues: <String, List<String>>{
      // `NetcruxExportKind.values`.
      'kind': <String>['png', 'svg', 'json'],
    },
  ),
  TelemetryCatalogEvent(
    'cxp.crossprobe',
    enumeratedValues: <String, List<String>>{
      'direction': <String>['inbound', 'outbound'],
    },
    boolProperties: <String>['honored'],
  ),

  // ── recorded by the shared telemetry package ───────────────────────────
  // `crux_telemetry`'s `TelemetryUncaughtErrorCounter` records this from the
  // global error handlers `captureFlutterErrors` installs, so no call site in
  // either repository spells it. At most once per (source, kind, library) per
  // session and ten per session; never the message, the stack or a file
  // name. `kind` is the error's class bucketed by `is` checks, never its
  // runtime type name, and `library` is the Flutter framework library that
  // reported it. The name and the value lists are the package's own
  // constants, not a copy of them: the ingestion Worker enforces them value
  // by value for this one event, and a copy here would go stale the day the
  // package's vocabulary moved.
  TelemetryCatalogEvent(
    kTelemetryUncaughtErrorEvent,
    enumeratedValues: <String, List<String>>{
      'source': kTelemetryUncaughtErrorSources,
      'kind': kTelemetryUncaughtErrorKinds,
      'library': kTelemetryUncaughtErrorLibraries,
    },
    boolProperties: <String>['silent'],
  ),

  // ── the commercial group ──────────────────────────────────────────────
  // Recorded from BOTH repositories, by three gate-denial sites covering
  // disjoint activation surfaces: open core's `allowProAction` (the
  // workspace action dispatcher and the inspector's Go to source), open
  // core's `crossProbeOriginateGateProvider` (the docked cross-probe
  // panel's per-peer send), and the overlay's `proFeatureGateAllows`
  // (schematic context-menu entries). Each call site is real and none
  // double-counts another. It is the one catalog entry the two conformance
  // scans both expect to find.
  //
  // Cannot fire during the beta by construction: the gate short-circuits to
  // allow while `betaPeriodProvider` is true, so no denial exists to record.
  // That is the intended shape, not a bug — see the call sites.
  TelemetryCatalogEvent(
    'tier.gate_hit',
    enumeratedValues: <String, List<String>>{
      // `NetcruxGatedFeature.values` under `telemetryEnumToken`. NEVER the
      // upgrade dialog's `featureName`, which is localized display text: it
      // varies per locale and fails the Worker's value class, so the
      // property would be dropped and the event kept — a healthy-looking
      // counter with a permanently empty dimension.
      'feature': <String>[
        'coi',
        'x_trace',
        'source_pane',
        'diff',
        'symbol',
        'fsm',
        'cdc',
        'reset',
        'waveform',
        'activity',
        'cross_probe',
        'collaboration',
      ],
      // `LicenseTier.name` for the tier the FEATURE needs. Only two values
      // can occur: an open-core gate admits everyone and never denies, and
      // a gate never demands `edu` because EDU is Pro-equivalent for
      // gating. The tier the user HOLDS is `license_tier` in the envelope.
      'required': <String>['pro', 'enterprise'],
    },
  ),

  // An annotation added from the dialog. Recorded in open core, where
  // annotations are free.
  TelemetryCatalogEvent('annotation.added'),

  // ── Pro overlay ────────────────────────────────────────────────────────
  // Recorded from the Pro overlay's code, through the open-core
  // `telemetryServiceProvider`. They are Pro-side rather than at the
  // open-core dispatcher because the dispatcher's tier gate is open during
  // the beta and its openers resolve to no-ops in an open-core build — an
  // open-core `analysis.run` would count a run that did not happen.
  TelemetryCatalogEvent(
    'analysis.run',
    enumeratedValues: <String, List<String>>{
      // `NetcruxAnalysisKind.values` under `telemetryEnumToken`, declared
      // in open core so the catalog and the Pro call sites cannot drift.
      'kind': <String>['coi', 'x_trace', 'fsm', 'cdc', 'reset', 'activity'],
    },
  ),
  TelemetryCatalogEvent('diff.loaded'),
  TelemetryCatalogEvent('symbol.imported'),
  // A symbol already in the library reopened in the editor and re-saved.
  // Disjoint from `symbol.imported` by construction — the import flow opens
  // the same editor with no `existing`, so it can only produce the import
  // event. The pair answers whether the custom-symbol library is MAINTAINED or
  // imported once and forgotten, which is what decides whether the three-tab
  // editor earns its place beside a plain SVG drop.
  TelemetryCatalogEvent('symbol.edited'),
  TelemetryCatalogEvent('source_pane.opened'),
  // The Pro cone filter view (hide everything outside the cone) switched ON.
  // Only the off→on transition is recorded: turning it back off is undoing,
  // not using, and a toggle counted both ways answers no question. Open core
  // paints the dim veil instead, so this says whether the Pro hide-mode is the
  // thing users actually want or a preference nobody moves.
  TelemetryCatalogEvent('filter_view.enabled'),
  // The one-click "Open in WaveCrux" handoff from the CDC panel / schematic —
  // the suite's headline network effect. No properties: the dispatcher targets
  // the single discovered peer whose `productName` is the hardcoded `wavecrux`,
  // so a `peer` dimension would have exactly one value.
  TelemetryCatalogEvent('cxp.open_in_wavecrux'),
];

/// Every catalog event name, for the source-scanning conformance test.
Set<String> get kNetcruxEventNames => <String>{
  for (final event in kNetcruxEventCatalog) event.name,
};
