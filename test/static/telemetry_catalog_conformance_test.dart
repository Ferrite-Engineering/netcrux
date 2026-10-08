// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// The telemetry catalog's conformance guard.
//
// WHY THIS TEST EXISTS, AND WHY IT IS WORTH ITS LENGTH:
//
// The telemetry ingestion Worker validates every
// event it receives, and every one of its rejections is SILENT.
//
//   * An event NAME that fails `^[a-z0-9_]+(\.[a-z0-9_]+){1,2}$` is skipped.
//     The batch still returns 202; the row is counted only in the response's
//     `dropped` field, which the client does not read and no dashboard shows.
//   * A property KEY that fails `^[a-z][a-z0-9_]{0,31}$`, or a VALUE that is
//     neither `[a-z0-9_]{1,64}`, nor a bool, nor an integer with |v| <= 100000,
//     is dropped while the event is KEPT. That is the worse failure: the
//     counter looks healthy and one of its dimensions is permanently empty.
//
// Nothing in the app, the queue, the response, or the SQL API can distinguish
// "nobody used this feature" from "every row was discarded at the edge". A
// capital letter in an event name — `sourcePane.opened` — costs the whole
// event, forever, with no error anywhere. So the grammar is asserted HERE,
// client-side, where a violation is a failing build instead of a quiet hole in
// the data.
//
// The rules enforced:
//
//  1. Every event name recorded anywhere in `lib/` appears in the pinned
//     `kNetcruxEventCatalog`. An undocumented event cannot ship.
//  2. Conversely, every catalog entry is still recorded somewhere (Pro-only
//     entries excepted, since they live in the other repo, and the shared
//     `app.uncaught_error`, which `crux_telemetry` records) — a catalog that
//     accumulates dead names stops being a description of the product.
//  3. Every catalog name matches the Worker's event-name class.
//  4. Every property key matches the Worker's property-key class.
//  5. Every enumerated property value matches the Worker's value class.
//  6. The catalog's enum-derived value sets equal what `telemetryEnumToken`
//     produces from the Dart enums they came from, so adding a camelCase
//     constant to `NetcruxAnalysisKind` (or a new `SearchMode`) fails here
//     rather than losing a property at the edge.
//  7. No duplicate names; no event over the Worker's six-property cap.
//
// The scanner reads string literals passed to `TelemetryEvent(...)`, which is
// why instrumentation call sites spell their event names as literals rather
// than referencing constants: a constant would make rule 1 vacuous.

import 'dart:io';

import 'package:crux_license/crux_license.dart';
import 'package:crux_telemetry/crux_telemetry.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/core/license/netcrux_gated_feature.dart';
import 'package:netcrux/core/shortcuts/netcrux_action.dart';
import 'package:netcrux/domain/enums/netcrux_design_source.dart';
import 'package:netcrux/domain/enums/netcrux_export_kind.dart';
import 'package:netcrux/domain/models/trace/trace_overlay.dart';
import 'package:netcrux/features/project/providers/loaded_netlist_provider.dart';
import 'package:netcrux/services/search/design_search_service.dart';
import 'package:netcrux/services/telemetry/netcrux_design_language_mix.dart';
import 'package:netcrux/services/telemetry/netcrux_telemetry_vocabulary.dart';
import 'package:netcrux/services/telemetry/telemetry_event_catalog.dart';

/// The ingestion Worker's `EVENT_NAME`.
final _eventName = RegExp(r'^[a-z0-9_]+(\.[a-z0-9_]+){1,2}$');

/// The ingestion Worker's `PROPERTY_KEY`.
final _propertyKey = RegExp(r'^[a-z][a-z0-9_]{0,31}$');

/// The ingestion Worker's `PROPERTY_VALUE`.
final _propertyValue = RegExp(r'^[a-z0-9_]{1,64}$');

/// The Worker's `MAX_PROPERTIES`.
const int _maxProperties = 6;

/// Matches the event-name argument of a `TelemetryEvent('…')` construction, or
/// of the workspace notifier's `_emit('…')` wrapper around one.
///
/// Single-quoted only — the house style throughout `lib/`, and a double-quoted
/// literal would be caught by the analyzer's quote lint first.
final _recordedEvent = RegExp(r"(?:TelemetryEvent|_emit)\(\s*'([^']+)'");

/// Every `TelemetryEvent(` construction, whether or not its first argument is
/// a literal. Used to prove the scanner above sees all of them.
final _anyConstruction = RegExp(r'TelemetryEvent\(');

/// The one place a `TelemetryEvent` is constructed from a variable rather than
/// a literal: the workspace notifier's `_emit` helper, whose callers pass the
/// literal instead and are matched by [_recordedEvent].
const String _indirectConstructionSite =
    'lib/services/workspace/netcrux_workspace_notifier.dart';

/// Catalog entries that live in the Pro overlay and so cannot be found by a
/// scan of this repository. The Pro repo runs the same rule-2 check over its
/// own tree against the same catalog.
///
/// `tier.gate_hit` is deliberately NOT here: both repositories record it, from
/// the two gate-denial helpers, so open core must find its own call site.
const Set<String> _proOnlyEvents = <String>{
  'analysis.run',
  'diff.loaded',
  'symbol.imported',
  'symbol.edited',
  'source_pane.opened',
  'filter_view.enabled',
  'cxp.open_in_wavecrux',
};

/// Catalog entries recorded by a shared package rather than by a call site in
/// either repository. `crux_telemetry` records `app.uncaught_error` from the
/// global error handlers, so no scan of this repository's `lib/` can find it,
/// and it is excused from the "still recorded" rule.
const Set<String> _sharedEvents = <String>{'app.uncaught_error'};

void main() {
  const catalog = kNetcruxEventCatalog;

  test('no duplicate catalog entries', () {
    final seen = <String>{};
    final duplicates = <String>[];
    for (final event in catalog) {
      if (!seen.add(event.name)) duplicates.add(event.name);
    }
    expect(duplicates, isEmpty, reason: 'each event is listed once');
  });

  test('every catalog name matches the Worker event-name class', () {
    final bad = [
      for (final event in catalog)
        if (!_eventName.hasMatch(event.name)) event.name,
    ];
    expect(
      bad,
      isEmpty,
      reason:
          'The ingestion Worker drops these names without reporting anything, '
          'so the events would never arrive. Names are lowercase, '
          'dot-separated, two or three segments:\n'
          '${bad.join('\n')}',
    );
  });

  test('every property key matches the Worker property-key class', () {
    final bad = <String>[];
    for (final event in catalog) {
      for (final key in event.propertyKeys) {
        if (!_propertyKey.hasMatch(key)) bad.add('${event.name}.$key');
      }
    }
    expect(
      bad,
      isEmpty,
      reason:
          'A key outside the Worker property-key class is dropped while its '
          'event is kept — the counter survives and the dimension is silently '
          'empty:\n${bad.join('\n')}',
    );
  });

  test('every enumerated property value matches the Worker value class', () {
    final bad = <String>[];
    for (final event in catalog) {
      event.enumeratedValues.forEach((key, values) {
        for (final value in values) {
          if (!_propertyValue.hasMatch(value)) {
            bad.add('${event.name}.$key = $value');
          }
        }
      });
    }
    expect(
      bad,
      isEmpty,
      reason:
          'Values are identifiers from our own vocabulary — no capitals, no '
          'dots, no spaces:\n${bad.join('\n')}',
    );
  });

  test('no event exceeds the Worker property cap', () {
    final over = [
      for (final event in catalog)
        if (event.propertyKeys.length > _maxProperties)
          '${event.name} (${event.propertyKeys.length})',
    ];
    expect(
      over,
      isEmpty,
      reason:
          'The Worker encodes at most $_maxProperties properties per event; '
          'the rest are dropped in key order:\n${over.join('\n')}',
    );
  });

  group('enum-derived vocabularies match their Dart enums', () {
    // Each of these pins a catalog value list to the enum it is derived from,
    // so a new constant cannot be added to the enum without the catalog being
    // updated in the same change.

    List<String> valuesFor(String event, String key) =>
        catalog.firstWhere((e) => e.name == event).enumeratedValues[key]!;

    test('design.elaborated.language is NetcruxDesignLanguageMix', () {
      expect(
        valuesFor('design.elaborated', 'language').toSet(),
        NetcruxDesignLanguageMix.values.map(telemetryEnumToken).toSet(),
      );
    });

    test('design.elaborated.source is NetcruxDesignSource', () {
      expect(
        valuesFor('design.elaborated', 'source').toSet(),
        NetcruxDesignSource.values.map(telemetryEnumToken).toSet(),
      );
    });

    test('design.elaboration_failed.reason is LoadedNetlistErrorKind', () {
      // The load-bearing assertion of the whole never-collect argument for this
      // event: the reason vocabulary is exactly the pipeline's own typed
      // failure enum, so it cannot grow a Yosys diagnostic or an exception
      // message without this failing first.
      expect(
        valuesFor('design.elaboration_failed', 'reason').toSet(),
        LoadedNetlistErrorKind.values.map(telemetryEnumToken).toSet(),
      );
    });

    test('search.used.mode covers every SearchMode', () {
      expect(
        valuesFor('search.used', 'mode').toSet(),
        SearchMode.values.map(telemetryEnumToken).toSet(),
      );
    });

    test('trace.used.kind covers every TraceOverlayMode', () {
      expect(
        valuesFor('trace.used', 'kind').toSet(),
        TraceOverlayMode.values.map(telemetryEnumToken).toSet(),
      );
    });

    test('export.completed.kind covers every NetcruxExportKind', () {
      expect(
        valuesFor('export.completed', 'kind').toSet(),
        NetcruxExportKind.values.map(telemetryEnumToken).toSet(),
      );
    });

    test('analysis.run.kind covers every NetcruxAnalysisKind', () {
      expect(
        valuesFor('analysis.run', 'kind').toSet(),
        NetcruxAnalysisKind.values.map(telemetryEnumToken).toSet(),
      );
    });

    test('annotation.added.kind covers every NetcruxAnnotationKind', () {
      expect(
        valuesFor('annotation.added', 'kind').toSet(),
        NetcruxAnnotationKind.values.map(telemetryEnumToken).toSet(),
      );
    });

    test('tier.gate_hit.feature is NetcruxGatedFeature', () {
      // The gate-denial guard: the ONLY thing a denial may report as `feature`
      // is a constant of this enum. Adding a Pro action without extending the
      // enum, or extending it without updating the catalog, fails
      // here — before an unlisted token reaches the Worker and is dropped.
      expect(
        valuesFor('tier.gate_hit', 'feature').toSet(),
        NetcruxGatedFeature.values.map(telemetryEnumToken).toSet(),
      );
    });

    test('tier.gate_hit.required is pro or enterprise only', () {
      // Not the whole of `LicenseTier`: `openCore` satisfies every gate so it
      // can never be the tier a denial demands, and `edu` is never demanded
      // because `LicenseTier.featureEquivalent` maps it to `pro` for gating.
      expect(
        valuesFor('tier.gate_hit', 'required').toSet(),
        <String>{LicenseTier.pro.name, LicenseTier.enterprise.name},
      );
    });
  });

  group('every gated action can name the feature it was denied for', () {
    // `tier.gate_hit {feature}` is derived from the action at the denial site,
    // so the two switches on NetcruxAction — `requiredTier` and `gatedFeature`
    // — have to agree exactly. A Pro action that gained a tier and no feature
    // id would raise the upgrade dialog and record nothing; an open-core action
    // that gained a feature id would advertise a denial that cannot happen.

    test('every Pro/Enterprise action maps to a NetcruxGatedFeature', () {
      final missing = [
        for (final action in NetcruxAction.values)
          if (action.requiredTier != LicenseTier.openCore &&
              action.gatedFeature == null)
            action.name,
      ];
      expect(
        missing,
        isEmpty,
        reason:
            'These actions raise the upgrade dialog but have no feature id '
            'from the closed vocabulary, so their gate hits go unrecorded. '
            'Add them to NetcruxActionGatedFeature (and, if the feature is '
            'new, to NetcruxGatedFeature + the catalog):\n'
            '${missing.join('\n')}',
      );
    });

    test('no open-core action carries a feature id', () {
      final spurious = [
        for (final action in NetcruxAction.values)
          if (action.requiredTier == LicenseTier.openCore &&
              action.gatedFeature != null)
            '${action.name} -> ${action.gatedFeature!.name}',
      ];
      expect(
        spurious,
        isEmpty,
        reason:
            'An open-core action satisfies every tier, so its denial branch is '
            'unreachable and the feature id is a value nothing can emit:\n'
            '${spurious.join('\n')}',
      );
    });

    test('every NetcruxGatedFeature is reachable from some denial site', () {
      // One exception: `crossProbe`'s only gated activation is the overlay's
      // schematic context menu (`cross_probe_menu_entries.dart`), not a
      // NetcruxAction, so the Pro repo's own tests cover that side. The
      // open-core `showCrossProbePanel` action is open-core-tier.
      //
      // `collaboration` is reached from File > Share Session (hosting is the
      // Enterprise step); joining is free and never denied.
      final fromActions = <NetcruxGatedFeature>{
        for (final action in NetcruxAction.values) ?action.gatedFeature,
      };
      expect(
        fromActions,
        NetcruxGatedFeature.values.toSet()
          ..remove(NetcruxGatedFeature.crossProbe),
      );
    });
  });

  test('app.uncaught_error carries the shared counter vocabulary', () {
    // Recorded by `crux_telemetry`, not by this repository, so the lists are
    // the package's: four properties, no free text, a catch-all in each
    // open-ended dimension, and `none` for an error with no framework library.
    final entry = catalog.firstWhere((e) => e.name == 'app.uncaught_error');
    expect(entry.propertyKeys.toSet(), <String>{
      'source',
      'kind',
      'library',
      'silent',
    });
    expect(entry.boolProperties, <String>['silent']);
    expect(entry.intProperties, isEmpty);
    expect(entry.enumeratedValues['source'], <String>['flutter', 'platform']);
    expect(entry.enumeratedValues['kind'], contains('other'));
    expect(
      entry.enumeratedValues['library'],
      containsAll(<String>['none', 'other']),
    );
  });

  group('source scan', () {
    final recorded = <String, Set<String>>{};
    // Files holding a `TelemetryEvent(` the name scanner could not read a
    // literal out of. Exactly one is expected, and it is the `_emit` wrapper.
    final opaqueConstructions = <String>[];

    final libDir = Directory('lib');
    if (!libDir.existsSync()) {
      throw StateError('run from the package root (flutter test)');
    }
    for (final entity in libDir.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final path = entity.path.replaceAll(r'\', '/');
      if (path.endsWith('.g.dart')) continue;
      final source = entity.readAsStringSync();
      var literalConstructions = 0;
      for (final match in _recordedEvent.allMatches(source)) {
        recorded.putIfAbsent(match.group(1)!, () => <String>{}).add(path);
        if (match.group(0)!.startsWith('TelemetryEvent')) {
          literalConstructions++;
        }
      }
      final total = _anyConstruction.allMatches(source).length;
      for (var i = literalConstructions; i < total; i++) {
        opaqueConstructions.add(path);
      }
    }

    test('the scan found the instrumentation at all', () {
      // A regex that silently stops matching would turn the rules below into
      // tests that assert nothing, so assert the scanner is alive.
      expect(
        recorded.length,
        greaterThan(10),
        reason:
            'the TelemetryEvent scan matched almost nothing — the call-site '
            'idiom probably changed and this guard has gone blind',
      );
    });

    test('no event name is hidden from the scanner behind an indirection', () {
      // The closure property that makes "every recorded name is in the
      // catalog" mean something: an event constructed from a variable is an
      // event this file cannot see, and so an event that could ship
      // undocumented. One such indirection exists by design.
      expect(
        opaqueConstructions,
        <String>[_indirectConstructionSite],
        reason:
            'A TelemetryEvent built from a non-literal name is invisible to '
            'the catalog check. Spell the name as a literal at the call site, '
            'or — if a new thin wrapper is genuinely warranted — teach '
            '_recordedEvent to read its callers and list it here.',
      );
    });

    test('every recorded event name is in the catalog', () {
      final names = kNetcruxEventNames;
      final undocumented = [
        for (final entry in recorded.entries)
          if (!names.contains(entry.key))
            '${entry.key}  (${entry.value.join(', ')})',
      ];
      expect(
        undocumented,
        isEmpty,
        reason:
            'An event that is not in kNetcruxEventCatalog is an event nobody '
            'vetted against the never-collect list. Add it to the catalog or '
            'remove the call site:\n${undocumented.join('\n')}',
      );
    });

    test('every open-core catalog entry is still recorded', () {
      final dead = [
        for (final event in catalog)
          if (!_proOnlyEvents.contains(event.name) &&
              !_sharedEvents.contains(event.name) &&
              !recorded.containsKey(event.name))
            event.name,
      ];
      expect(
        dead,
        isEmpty,
        reason:
            'These catalog entries have no call site in this repository. If '
            'the feature was removed, remove the entry; if the event moved to '
            'the Pro overlay, add it to _proOnlyEvents:\n${dead.join('\n')}',
      );
    });
  });
}
