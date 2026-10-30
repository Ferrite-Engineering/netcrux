// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

@TestOn('vm')
library;

import 'dart:io';

import 'package:crux_cxp/crux_cxp.dart';
import 'package:crux_cxp_ui/crux_cxp_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderListenable;
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/models/project/netcrux_project.dart';
import 'package:netcrux/domain/models/selection/selected_element.dart';
import 'package:netcrux/features/hierarchy/providers/hierarchy_tree_notifier.dart';
import 'package:netcrux/features/project/providers/current_project_provider.dart';
import 'package:netcrux/features/viewer/widgets/cross_probe_menu_entries.dart';
import 'package:netcrux/features/viewer/widgets/schematic_context_menu_extension.dart';
import 'package:netcrux/l10n/generated/app_localizations.dart';
import 'package:netcrux/services/remote/cxp/netcrux_cxp_binding.dart';

import '../../../helpers/formal_flow_design.dart';

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

class _SeededProject extends CurrentProject {
  _SeededProject(this._project);

  final NetcruxProject _project;

  @override
  NetcruxProject build() => _project;
}

PeerIdentity _peer(String product, int startedAt) => PeerIdentity(
  peerId: '$product-7-$startedAt',
  productName: product,
  productVersion: '1.2.0',
);

Widget _host({
  required List<PeerIdentity> peers,
  required SelectedElement target,
  required void Function(List<SchematicContextMenuExtensionEntry>) onEntries,
  Locale? locale,
  NetcruxProject? project,
}) {
  final container = ProviderContainer(
    overrides: [
      if (project != null)
        currentProjectProvider.overrideWith(() => _SeededProject(project)),
      cruxCxpProductBindingProvider.overrideWithValue(kNetcruxCxpBinding),
      cruxCxpPeersProvider.overrideWithValue(peers),
      cruxCxpServerStatusProvider.overrideWithValue((
        running: true,
        port: 54323,
        problem: null,
      )),
      cruxCxpRuntimeProvider.overrideWith((_) async => null),
      crossProbeDispatcherProvider.overrideWith((ref) => _FakeDispatcher()),
    ],
  );
  addTearDown(container.dispose);
  container.read(hierarchyTreeProvider.notifier).setModel(formalFlowDesign());
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
            final entries = buildCrossProbeMenuEntries(ref, target);
            onEntries(entries);
            final timing = entries
                .where((e) => e.id == 'cxp-show-timing-paths')
                .firstOrNull;
            return ElevatedButton(
              onPressed: timing == null
                  ? null
                  : () => timing.onTap(context, ref, const Offset(120, 90)),
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

  testWidgets('on a register: sends SimCrux its RTL name as a signal', (
    tester,
  ) async {
    late List<SchematicContextMenuExtensionEntry> entries;
    await tester.pumpWidget(
      _host(
        peers: [_peer('simcrux', 1), _peer('wavecrux', 1)],
        target: const SelectedElement.cell(cellId: 'cnt_reg'),
        onEntries: (e) => entries = e,
      ),
    );
    await tester.pump();
    expect(entries.map((e) => e.id), <String>[
      'cxp-cross-probe-to',
      'cxp-show-timing-paths',
    ]);
    final timing = entries.last;
    expect(timing.label, 'Show timing paths through this register');
    expect(timing.enabled, isTrue);
    expect(timing.requiredTier, isNull, reason: 'free, no badge');

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    final (peer, selection) = _sent.single;
    expect(peer.productName, 'simcrux');
    expect(selection!.candidates, const <ElementId>[
      ElementId(kind: ElementKind.signal, path: 'top.cnt_q'),
    ]);
  });

  testWidgets('an escaped register name travels escaped', (tester) async {
    await tester.pumpWidget(
      _host(
        peers: [_peer('simcrux', 1)],
        target: const SelectedElement.cell(cellId: 'esc_reg'),
        onEntries: (_) {},
      ),
    );
    await tester.pump();
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(_sent.single.$2!.candidates.single.path, r'top.\esc.q ');
  });

  testWidgets('without SimCrux it is greyed and says what to start', (
    tester,
  ) async {
    late List<SchematicContextMenuExtensionEntry> entries;
    await tester.pumpWidget(
      _host(
        peers: [_peer('wavecrux', 1)],
        target: const SelectedElement.cell(cellId: 'cnt_reg'),
        onEntries: (e) => entries = e,
      ),
    );
    await tester.pump();
    final timing = entries.last;
    expect(timing.enabled, isFalse);
    expect(timing.tooltip, contains('SimCrux'));
  });

  testWidgets('a cell that is not a register gets no entry', (tester) async {
    late List<SchematicContextMenuExtensionEntry> entries;
    await tester.pumpWidget(
      _host(
        peers: [_peer('simcrux', 1)],
        target: const SelectedElement.cell(cellId: 'g1'),
        onEntries: (e) => entries = e,
      ),
    );
    await tester.pump();
    expect(entries.map((e) => e.id), <String>['cxp-cross-probe-to']);
  });

  testWidgets('several SimCrux windows: the user picks one', (tester) async {
    await tester.pumpWidget(
      _host(
        peers: [_peer('simcrux', 20), _peer('simcrux', 10)],
        target: const SelectedElement.cell(cellId: 'cnt_reg'),
        onEntries: (_) {},
      ),
    );
    await tester.pump();
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('SimCrux 2'));
    await tester.pumpAndSettle();
    expect(_sent.single.$1.peerId, 'simcrux-7-20');
  });

  testWidgets(
    'on a host with no file system a register still gets its menu entries',
    (tester) async {
      // A browser, which includes the viewer hosted in an editor's webview:
      // asking the file system whether a path is a directory throws there, and
      // the viewer's project names a source file (the netlist the editor
      // handed it). Building the entry used to throw with it, so a right-click
      // on a register opened no menu at all.
      late List<SchematicContextMenuExtensionEntry> entries;
      await IOOverrides.runZoned(
        () async {
          await tester.pumpWidget(
            _host(
              peers: [_peer('simcrux', 1)],
              target: const SelectedElement.cell(cellId: 'cnt_reg'),
              onEntries: (e) => entries = e,
              project: NetcruxProject.create(
                sourceFiles: const <String>['fixture.json'],
              ),
            ),
          );
          await tester.pump();
        },
        fseGetTypeSync: (path, followLinks) =>
            throw UnsupportedError('_Namespace'),
      );
      expect(tester.takeException(), isNull);
      expect(entries.map((e) => e.id), <String>[
        'cxp-cross-probe-to',
        'cxp-show-timing-paths',
      ]);
    },
  );

  for (final locale in L10N.supportedLocales) {
    testWidgets('renders in $locale', (tester) async {
      late List<SchematicContextMenuExtensionEntry> entries;
      await tester.pumpWidget(
        _host(
          peers: [_peer('simcrux', 1)],
          target: const SelectedElement.cell(cellId: 'cnt_reg'),
          onEntries: (e) => entries = e,
          locale: locale,
        ),
      );
      await tester.pump();
      expect(entries.last.label, isNotEmpty);
      expect(tester.takeException(), isNull);
    });
  }
}
