// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

@TestOn('vm')
library;

import 'package:crux_cxp/crux_cxp.dart';
import 'package:crux_cxp_ui/crux_cxp_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override, ProviderListenable;
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/core/policy/org_cross_probe_allowlist.dart';
import 'package:netcrux/domain/models/netlist/cell.dart';
import 'package:netcrux/domain/models/netlist/module.dart';
import 'package:netcrux/domain/models/netlist/netlist_model.dart';
import 'package:netcrux/domain/models/selection/selected_element.dart';
import 'package:netcrux/features/hierarchy/providers/hierarchy_tree_notifier.dart';
import 'package:netcrux/features/remote/netcrux_cxp_overrides.dart';
import 'package:netcrux/features/viewer/widgets/cross_probe_menu_entries.dart';
import 'package:netcrux/features/viewer/widgets/schematic_context_menu_extension.dart';
import 'package:netcrux/l10n/generated/app_localizations.dart';
import 'package:netcrux/services/remote/cxp/netcrux_cxp_binding.dart';

/// Every send the fake dispatcher saw in the current test.
final List<(PeerIdentity, CrossProbeSelection?)> _sent = [];

class _FakeDispatcher extends CrossProbeDispatcher {
  _FakeDispatcher() : super(_unread);

  static T _unread<T>(ProviderListenable<T> provider) =>
      throw UnimplementedError('the fake reads nothing');

  @override
  Future<CrossProbeOutcome> send(
    PeerIdentity peer,
    CrossProbeSelection? selection, {
    String? label,
  }) async {
    _sent.add((peer, selection));
    return CrossProbeOutcome(
      CrossProbeOutcomeKind.sent,
      target: label ?? cruxCxpDisplayName(peer.productName),
    );
  }
}

PeerIdentity _peer(String product, int startedAt) => PeerIdentity(
  peerId: '$product-7-$startedAt',
  productName: product,
  productVersion: '1.2.0',
);

NetlistModel _model() {
  const top = Module(
    name: 'top',
    attributes: <String, String>{'top': '1'},
    ports: {},
    cells: <String, Cell>{
      'u_cpu': Cell(
        name: 'u_cpu',
        type: 'cpu',
        parameters: {},
        attributes: {},
        portDirections: {},
        connections: {},
      ),
      'u_dma': Cell(
        name: 'u_dma',
        type: 'dma',
        parameters: {},
        attributes: {},
        portDirections: {},
        connections: {},
      ),
    },
    nets: {},
  );
  return const NetlistModel(
    creator: 'test',
    modules: <String, Module>{'top': top},
  );
}

/// Mounts a button that builds the "Cross-probe to" entry for [target] and
/// taps it the way the schematic menu does, at (120, 90).
Widget _host({
  required List<PeerIdentity> peers,
  required SelectedElement target,
  required void Function(SchematicContextMenuExtensionEntry entry) onEntry,
  List<Override> extra = const <Override>[],
  Locale? locale,
}) {
  final container = ProviderContainer(
    overrides: [
      cruxCxpProductBindingProvider.overrideWithValue(kNetcruxCxpBinding),
      cruxCxpPeersProvider.overrideWithValue(peers),
      cruxCxpServerStatusProvider.overrideWithValue((
        running: true,
        port: 54323,
        problem: null,
      )),
      cruxCxpRuntimeProvider.overrideWith((_) async => null),
      crossProbeDispatcherProvider.overrideWith((ref) => _FakeDispatcher()),
      ...extra,
    ],
  );
  addTearDown(container.dispose);
  // The tab's design, set before anything builds.
  container.read(hierarchyTreeProvider.notifier).setModel(_model());
  return UncontrolledProviderScope(
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
      home: Scaffold(
        body: Consumer(
          builder: (context, ref, _) {
            final entry = buildCrossProbeMenuEntries(ref, target).single;
            onEntry(entry);
            return ElevatedButton(
              onPressed: () => entry.onTap(context, ref, const Offset(120, 90)),
              child: const Text('Open'),
            );
          },
        ),
      ),
    ),
  );
}

void main() {
  setUp(_sent.clear);

  testWidgets('lists the running products and sends the right-clicked '
      'element', (tester) async {
    late SchematicContextMenuExtensionEntry entry;
    await tester.pumpWidget(
      _host(
        peers: [_peer('lintcrux', 1), _peer('wavecrux', 1)],
        target: const SelectedElement.cell(cellId: 'u_dma'),
        onEntry: (e) => entry = e,
      ),
    );
    await tester.pump();
    expect(entry.label, 'Cross-probe to');
    expect(entry.enabled, isTrue);
    expect(entry.requiredTier, isNull, reason: 'free in every edition');

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    // The targets are the shared list, in suite order.
    final wave = tester.getTopLeft(find.text('WaveCrux'));
    final lint = tester.getTopLeft(find.text('LintCrux'));
    expect(wave.dy, lessThan(lint.dy));
    // Opened where the schematic menu opened.
    expect(wave.dx, closeTo(120, 80));

    await tester.tap(find.text('WaveCrux'));
    await tester.pumpAndSettle();

    final (peer, selection) = _sent.single;
    expect(peer.productName, 'wavecrux');
    // The element named is the one right-clicked (u_dma), as an instance.
    expect(selection!.candidates.single.kind, ElementKind.instance);
    expect(selection.candidates.single.path, 'top.u_dma');
    expect(selection.displayName, 'u_dma');
    expect(tester.takeException(), isNull);
  });

  testWidgets('several windows of a product are a nested list', (tester) async {
    await tester.pumpWidget(
      _host(
        peers: [_peer('wavecrux', 20), _peer('wavecrux', 10)],
        target: const SelectedElement.cell(cellId: 'u_cpu'),
        onEntry: (_) {},
      ),
    );
    await tester.pump();
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('WaveCrux'));
    await tester.pumpAndSettle();
    expect(find.text('WaveCrux 1'), findsOneWidget);
    await tester.tap(find.text('WaveCrux 2'));
    await tester.pumpAndSettle();

    expect(_sent.single.$1.peerId, 'wavecrux-7-20');
  });

  testWidgets('with no peer running the entry is greyed and says what to '
      'start', (tester) async {
    late SchematicContextMenuExtensionEntry entry;
    await tester.pumpWidget(
      _host(
        peers: const [],
        target: const SelectedElement.cell(cellId: 'u_cpu'),
        onEntry: (e) => entry = e,
      ),
    );
    await tester.pump();

    expect(entry.label, 'Cross-probe to (no peers running)');
    expect(entry.enabled, isFalse);
    expect(
      entry.tooltip,
      'Start WaveCrux, NetCrux, LintCrux or SimCrux with CXP on to '
      'cross-probe to it.',
    );
  });

  for (final locale in L10N.supportedLocales) {
    testWidgets('the entry and its target list render in $locale', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          peers: [_peer('wavecrux', 1), _peer('lintcrux', 1)],
          target: const SelectedElement.cell(cellId: 'u_cpu'),
          onEntry: (_) {},
          locale: locale,
        ),
      );
      await tester.pump();
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('WaveCrux'), findsOneWidget);
      expect(find.text('LintCrux'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  test('the organization allowlist removes a product from every surface', () {
    final container = ProviderContainer(
      overrides: [
        ...netcruxCxpOverrides,
        orgCrossProbeAllowlistProvider.overrideWithValue(<String>{'wavecrux'}),
      ],
    );
    addTearDown(container.dispose);

    final allowed = container.read(cruxCxpPeerFilterProvider);

    expect(allowed(_peer('wavecrux', 1)), isTrue);
    expect(allowed(_peer('lintcrux', 1)), isFalse);
  });

  test('with no allowlist every product is offered', () {
    final container = ProviderContainer(
      overrides: [
        ...netcruxCxpOverrides,
        orgCrossProbeAllowlistProvider.overrideWithValue(null),
      ],
    );
    addTearDown(container.dispose);

    final allowed = container.read(cruxCxpPeerFilterProvider);

    expect(allowed(_peer('wavecrux', 1)), isTrue);
    expect(allowed(_peer('lintcrux', 1)), isTrue);
  });
}
