// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/interfaces/x_trace_service.dart';
import 'package:netcrux/domain/models/netlist/bit_ref.dart';
import 'package:netcrux/domain/models/netlist/cell.dart';
import 'package:netcrux/domain/models/netlist/module.dart';
import 'package:netcrux/domain/models/netlist/net.dart';
import 'package:netcrux/domain/models/netlist/netlist_model.dart';
import 'package:netcrux/domain/models/netlist/port.dart';
import 'package:netcrux/domain/models/selection/selected_element.dart';
import 'package:netcrux/features/hierarchy/providers/hierarchy_tree_notifier.dart';
import 'package:netcrux/features/viewer/providers/reveal_request_notifier.dart';
import 'package:netcrux/features/viewer/providers/selected_element_notifier.dart';
import 'package:netcrux/features/viewer/providers/x_trace_in_flight_provider.dart';
import 'package:netcrux/features/viewer/providers/x_trace_result_notifier.dart';
import 'package:netcrux/features/viewer/widgets/x_trace_result_panel.dart';
import 'package:netcrux/l10n/generated/app_localizations.dart';

/// A chain the walker could actually have produced: two internal steps ending
/// at a module boundary port, which is the `reachedBoundary` shape the Pro
/// integration journey asserts.
XTraceResult _boundaryChain() => const XTraceResult(
  rootNetId: 7,
  chain: <XTraceStep>[
    XTraceStep(depth: 0, netId: 7, edgeId: 'e7', cellId: 'buf1'),
    XTraceStep(depth: 1, netId: 4, edgeId: 'e4', cellId: 'buf0'),
    XTraceStep(
      depth: 2,
      netId: 1,
      edgeId: 'e1',
      boundaryPortId: 'port:d_in',
    ),
  ],
  termination: XTraceTermination.reachedBoundary,
);

NetlistModel _model() => const NetlistModel(
  creator: 'test',
  modules: <String, Module>{
    'top': Module(
      name: 'top',
      attributes: <String, String>{'top': '1'},
      ports: <String, Port>{},
      cells: <String, Cell>{},
      nets: <String, Net>{
        // Named carriers for the chain's net ids, so the rows render names
        // rather than falling back to raw Yosys integers.
        'alarm_r': Net(
          name: 'alarm_r',
          bits: <BitRef>[NetBit(7)],
          attributes: <String, String>{},
        ),
        'stage0': Net(
          name: 'stage0',
          bits: <BitRef>[NetBit(4)],
          attributes: <String, String>{},
        ),
      },
    ),
  },
);

Future<ProviderContainer> _pump(
  WidgetTester tester, {
  XTraceResult? result,
  bool inFlight = false,
  bool withModel = true,
  Locale locale = const Locale('en'),
  Size size = const Size(360, 600),
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final container = ProviderContainer();
  addTearDown(container.dispose);
  if (withModel) {
    container.read(hierarchyTreeProvider.notifier).setModel(_model());
  }
  if (result != null) {
    container.read(xTraceResultProvider.notifier).set(result);
  }
  if (inFlight) {
    container.read(xTraceInFlightProvider.notifier).set(running: true);
  }
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        locale: locale,
        localizationsDelegates: const [
          L10N.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: L10N.supportedLocales,
        home: const Scaffold(body: XTraceResultPanel()),
      ),
    ),
  );
  // An indeterminate progress indicator animates forever, so a settle would
  // time out rather than tell us anything.
  if (inFlight) {
    await tester.pump();
  } else {
    await tester.pumpAndSettle();
  }
  return container;
}

void main() {
  group('XTraceResultPanel states', () {
    testWidgets('empty: explainer, no status row, no progress line', (
      tester,
    ) async {
      await _pump(tester);
      expect(
        find.text('No active X-trace. Select a net and run "Show X-Trace".'),
        findsOneWidget,
      );
      // `noTraceableSelection` is the sentinel for "nothing ran", so its
      // status string must NOT appear — the empty state replaces it.
      expect(find.text('No traceable selection'), findsNothing);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(find.byType(ListView), findsNothing);
    });

    testWidgets('populated: status row, step count, one row per step', (
      tester,
    ) async {
      await _pump(tester, result: _boundaryChain());
      expect(find.text('Boundary reached'), findsOneWidget);
      expect(find.text('3 steps'), findsOneWidget);
      expect(find.text('Step 0'), findsOneWidget);
      expect(find.text('Step 1'), findsOneWidget);
      expect(find.text('Step 2'), findsOneWidget);
      expect(
        find.text('No active X-trace. Select a net and run "Show X-Trace".'),
        findsNothing,
      );
    });

    testWidgets('loading: progress line replaces the divider, chain stays', (
      tester,
    ) async {
      await _pump(tester, result: _boundaryChain(), inFlight: true);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      // The previous result stays visible underneath rather than blanking —
      // a walk in progress is not the same thing as no result.
      expect(find.text('Step 0'), findsOneWidget);
    });

    testWidgets('single-step chain uses the =1 plural branch', (tester) async {
      await _pump(
        tester,
        result: const XTraceResult(
          rootNetId: 7,
          chain: <XTraceStep>[
            XTraceStep(depth: 0, netId: 7, edgeId: 'e7', cellId: 'buf1'),
          ],
          termination: XTraceTermination.foundOrigin,
        ),
      );
      expect(find.text('1 step'), findsOneWidget);
    });
  });

  group('termination switch', () {
    // Every value, including the two no walker emits: `noVcdLoaded` has no
    // producer at all and `noTraceableSelection` arrives only with
    // `XTraceResult.empty`. Both are translated in five locales and the
    // switch must stay total.
    const cases = <XTraceTermination, String>{
      // "on this path" is load-bearing, not padding: the walk follows one
      // input per cell, so this is an origin, never the origin.
      XTraceTermination.foundOrigin: 'Origin reached on this path',
      XTraceTermination.maxDepthReached: 'Depth limit reached',
      XTraceTermination.reachedBoundary: 'Boundary reached',
      XTraceTermination.noVcdLoaded: 'No waveform loaded',
      XTraceTermination.cycleDetected: 'Combinational cycle',
    };

    for (final entry in cases.entries) {
      testWidgets('${entry.key.name} renders "${entry.value}"', (tester) async {
        await _pump(
          tester,
          result: XTraceResult(
            rootNetId: 7,
            chain: const <XTraceStep>[
              XTraceStep(depth: 0, netId: 7, edgeId: 'e7', cellId: 'buf1'),
            ],
            termination: entry.key,
          ),
        );
        expect(find.text(entry.value), findsOneWidget);
      });
    }

    testWidgets('every enum value has a label — the switch is total', (
      tester,
    ) async {
      await _pump(tester);
      final l10n = await L10N.delegate.load(const Locale('en'));
      for (final t in XTraceTermination.values) {
        expect(terminationLabel(l10n, t), isNotEmpty, reason: t.name);
      }
      expect(XTraceTermination.values, hasLength(6));
    });

    const reasons = <XTraceOriginReason, (String?, String)>{
      XTraceOriginReason.undrivenInput: (
        r'$mul$mac.v:25$1:B',
        'Origin reached on this path: undriven input B',
      ),
      XTraceOriginReason.xTiedInput: (
        r'$procmux$26:A',
        'Origin reached on this path: input A tied to x',
      ),
      XTraceOriginReason.registerWithoutReset: (
        null,
        'Origin reached on this path: register with no reset',
      ),
      XTraceOriginReason.noDrivenInputs: (
        null,
        'Origin reached on this path: no driven inputs',
      ),
    };

    for (final entry in reasons.entries) {
      testWidgets('an origin names its reason: ${entry.key.name}', (
        tester,
      ) async {
        final (portId, label) = entry.value;
        await _pump(
          tester,
          result: XTraceResult(
            rootNetId: 7,
            chain: const <XTraceStep>[
              XTraceStep(depth: 0, netId: 7, edgeId: 'e7', cellId: 'buf1'),
            ],
            termination: XTraceTermination.foundOrigin,
            originReason: entry.key,
            originPortId: portId,
          ),
        );
        expect(find.text(label), findsOneWidget);
      });
    }

    testWidgets('every origin reason has a label in every locale', (
      tester,
    ) async {
      await _pump(tester);
      for (final locale in L10N.supportedLocales) {
        final l10n = await L10N.delegate.load(locale);
        for (final reason in XTraceOriginReason.values) {
          final label = statusLabel(
            l10n,
            XTraceResult(
              rootNetId: 1,
              chain: const <XTraceStep>[],
              termination: XTraceTermination.foundOrigin,
              originReason: reason,
              originPortId: 'c:B',
            ),
          );
          expect(
            label,
            isNot(l10n.xTracePanelTerminationFoundOrigin),
            reason: '$locale ${reason.name}',
          );
        }
      }
    });

    testWidgets('a reason on another termination is not shown', (
      tester,
    ) async {
      await _pump(tester);
      final l10n = await L10N.delegate.load(const Locale('en'));
      final label = statusLabel(
        l10n,
        const XTraceResult(
          rootNetId: 1,
          chain: <XTraceStep>[],
          termination: XTraceTermination.reachedBoundary,
          originReason: XTraceOriginReason.undrivenInput,
        ),
      );
      expect(label, 'Boundary reached');
    });
  });

  group('step rows', () {
    testWidgets('resolves net ids to names, labels cell and boundary hosts', (
      tester,
    ) async {
      await _pump(tester, result: _boundaryChain());
      expect(find.text('alarm_r'), findsOneWidget);
      expect(find.text('stage0'), findsOneWidget);
      expect(find.text('in buf1'), findsOneWidget);
      expect(find.text('in buf0'), findsOneWidget);
      // The `port:` prefix is an internal graph convention, never shown.
      expect(find.text('boundary port d_in'), findsOneWidget);
      expect(find.textContaining('port:'), findsNothing);
    });

    testWidgets('falls back to the raw net id when no named net carries it', (
      tester,
    ) async {
      await _pump(tester, result: _boundaryChain(), withModel: false);
      expect(find.text('7'), findsOneWidget);
      expect(find.text('alarm_r'), findsNothing);
    });

    testWidgets('renders a value only when the step carries one', (
      tester,
    ) async {
      await _pump(
        tester,
        result: const XTraceResult(
          rootNetId: 7,
          chain: <XTraceStep>[
            XTraceStep(depth: 0, netId: 7, edgeId: 'e7', cellId: 'buf1'),
            XTraceStep(
              depth: 1,
              netId: 4,
              edgeId: 'e4',
              cellId: 'buf0',
              value: 'x',
            ),
          ],
          termination: XTraceTermination.foundOrigin,
        ),
      );
      expect(find.text('= x'), findsOneWidget);
    });

    testWidgets('tapping a step selects it and requests a reveal', (
      tester,
    ) async {
      final container = await _pump(tester, result: _boundaryChain());
      expect(container.read(selectedElementProvider).isEmpty, isTrue);

      await tester.tap(find.text('alarm_r'));
      await tester.pumpAndSettle();

      final primary = container.read(selectedElementProvider).primary;
      expect(primary, isA<SelectedElementWire>());
      expect((primary as SelectedElementWire).edgeId, 'e7');
      expect(primary.netId, 7);
      // Reveal is cell-addressed; the wire step asks for its host cell.
      expect(container.read(revealRequestProvider), 'buf1');
    });

    testWidgets('tapping the boundary terminator selects a boundary port', (
      tester,
    ) async {
      final container = await _pump(tester, result: _boundaryChain());
      await tester.tap(find.text('boundary port d_in'));
      await tester.pumpAndSettle();

      final primary = container.read(selectedElementProvider).primary;
      expect(primary, isA<SelectedElementBoundaryPort>());
      expect((primary as SelectedElementBoundaryPort).portId, 'port:d_in');
      expect(primary.portName, 'd_in');
    });
  });

  group('layout', () {
    testWidgets('survives an 80 px dock height without overflowing', (
      tester,
    ) async {
      // A docked panel is dragged to whatever height the user wants. Mirrors
      // `wavecrux/test/features/viewer/widgets/x_trace_panel_test.dart`.
      await _pump(
        tester,
        result: _boundaryChain(),
        size: const Size(300, 80),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('lays out in a 300 px pane without horizontal scrolling', (
      tester,
    ) async {
      await _pump(
        tester,
        result: _boundaryChain(),
        size: const Size(300, 600),
      );
      expect(tester.takeException(), isNull);
      final lists = tester.widgetList<ListView>(find.byType(ListView));
      for (final l in lists) {
        expect(l.scrollDirection, Axis.vertical);
      }
    });
  });

  group('locales', () {
    for (final locale in const <Locale>[
      Locale('en'),
      Locale('ja'),
      Locale('ko'),
      Locale('zh'),
      Locale('zh', 'CN'),
    ]) {
      testWidgets('renders in $locale', (tester) async {
        await _pump(tester, result: _boundaryChain(), locale: locale);
        expect(tester.takeException(), isNull);
        // The panel is localized end to end, so no English leaks into a
        // non-English build.
        if (locale.languageCode != 'en') {
          expect(find.text('Boundary reached'), findsNothing);
        }
      });

      testWidgets('renders the empty state in $locale', (tester) async {
        await _pump(tester, locale: locale);
        expect(tester.takeException(), isNull);
      });
    }
  });
}
