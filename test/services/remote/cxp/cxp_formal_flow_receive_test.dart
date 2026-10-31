// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// What NetCrux does with what Formal and Flow send it (CXP 1.3 rev. 9): a
// formal property's failing signal (selected, single-step fanin), a property
// (its union cone is NetCrux Pro's; open core says so), a netlist cell, a
// timing path from an implementation run (its registers highlighted, the
// path in the Inspector) and an implementation run or timing report to open.
// Expectations come from the design's RTL (`formal_flow_design.dart`).

import 'dart:io';
import 'dart:ui' show Locale;

import 'package:crux_cxp/crux_cxp.dart';
import 'package:crux_cxp_ui/crux_cxp_ui.dart';
import 'package:crux_license/crux_license.dart';
import 'package:crux_telemetry/crux_telemetry.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/core/providers/pro_overlay_installed_provider.dart';
import 'package:netcrux/domain/models/netlist/hierarchy_node.dart';
import 'package:netcrux/domain/models/netlist/netlist_model.dart';
import 'package:netcrux/domain/models/schematic/laid_out_graph.dart';
import 'package:netcrux/domain/models/selection/selected_element.dart';
import 'package:netcrux/domain/models/selection/selection.dart';
import 'package:netcrux/domain/models/trace/trace_overlay.dart';
import 'package:netcrux/features/hierarchy/providers/hierarchy_tree_notifier.dart';
import 'package:netcrux/features/hierarchy/providers/scope_flash_notifier.dart';
import 'package:netcrux/features/inspector/providers/received_timing_path_provider.dart';
import 'package:netcrux/features/project/providers/current_laid_out_graph_provider.dart';
import 'package:netcrux/features/project/providers/current_project_provider.dart';
import 'package:netcrux/features/viewer/providers/reveal_request_notifier.dart';
import 'package:netcrux/features/viewer/providers/selected_element_notifier.dart';
import 'package:netcrux/features/viewer/providers/trace_overlay_notifier.dart';
import 'package:netcrux/l10n/generated/app_localizations.dart';
import 'package:netcrux/services/remote/cxp/cxp_inbound_handler.dart';
import 'package:netcrux/services/remote/cxp/flow_artifact_opener.dart';
import 'package:netcrux/services/remote/cxp/inbound_property_cone.dart';
import 'package:netcrux/services/remote/cxp/netcrux_cxp_binding.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../helpers/cxp_test_overrides.dart';
import '../../../helpers/formal_flow_design.dart';

class _RecordingTelemetry implements TelemetryService {
  final List<TelemetryEvent> events = <TelemetryEvent>[];

  @override
  void record(TelemetryEvent event) => events.add(event);

  Iterable<TelemetryEvent> named(String name) =>
      events.where((e) => e.name == name);
}

/// The overlay's property cone, as a test double: a tier verdict the test
/// chooses, and a cone that marks every seed it was handed.
class _FakeCone implements InboundPropertyCone {
  _FakeCone({this.denied, this.sameNets = const <String>[]});

  final LicenseTier? denied;
  final List<String> sameNets;
  final List<List<SelectedElement>> seedsSeen = <List<SelectedElement>>[];
  List<String> namesAsked = const <String>[];

  @override
  LicenseTier? deniedTier() => denied;

  @override
  Future<TraceOverlay> unionCone(
    LaidOutGraph laidOut,
    List<SelectedElement> seeds,
  ) async {
    seedsSeen.add(seeds);
    return const TraceOverlay(
      mode: TraceOverlayMode.fanin,
      highlightedCellIds: <String>{'cone'},
      highlightedEdgeIds: <String>{},
      highlightedBoundaryPortIds: <String>{},
    );
  }

  @override
  List<String> sameNetsInScope({
    required NetlistModel model,
    required List<String> scopePath,
    required List<String> names,
  }) {
    namesAsked = names;
    return sameNets;
  }
}

class _FakeOpener implements FlowArtifactOpener {
  _FakeOpener({this.denied});

  final LicenseTier? denied;
  final List<(String, String)> opened = <(String, String)>[];

  @override
  LicenseTier? deniedTier() => denied;

  @override
  Future<String?> open({required String kind, required String path}) async {
    opened.add((kind, path));
    return null;
  }
}

const PeerIdentity _simcrux = PeerIdentity(
  peerId: 'simcrux-test',
  productName: 'simcrux',
  productVersion: '1.2.0-test',
);

/// A tab container shaped like production's: the per-tab state this
/// handler touches, re-bound per tab, and a layout that is the schematic of
/// whatever scope the tab shows.
ProviderContainer _tab(ProviderContainer root, NetlistModel model) {
  final tab = ProviderContainer(
    parent: root,
    overrides: <Override>[
      currentProjectProvider.overrideWith(CurrentProject.new),
      hierarchyTreeProvider.overrideWith(HierarchyTreeNotifier.new),
      selectedElementProvider.overrideWith(SelectedElementNotifier.new),
      traceOverlayProvider.overrideWith(TraceOverlayNotifier.new),
      revealRequestProvider.overrideWith(RevealRequestNotifier.new),
      scopeFlashProvider.overrideWith(ScopeFlashNotifier.new),
      receivedTimingPathProvider.overrideWith(ReceivedTimingPathNotifier.new),
      currentLaidOutGraphProvider.overrideWith((ref) async {
        final scope = ref.watch(hierarchyTreeProvider).selected;
        return scope == null ? LaidOutGraph.empty : laidOutScope(model, scope);
      }),
    ],
  );
  tab.read(hierarchyTreeProvider.notifier).setModel(model);
  return tab;
}

class _Rig {
  _Rig({List<Override> overrides = const <Override>[], NetlistModel? model})
    : model = model ?? formalFlowDesign() {
    root = ProviderContainer(
      overrides: <Override>[
        ...netcruxCxpOffTestOverrides(),
        telemetryServiceProvider.overrideWithValue(telemetry),
        cruxCxpAttentionRequesterProvider.overrideWithValue(
          () => attention++,
        ),
        ...overrides,
      ],
    );
    tab = _tab(root, this.model);
    handler = NetcruxCxpRequestHandler(
      rootContainer: root,
      activeTabContainerLookup: () => active ?? tab,
      selectionFramer: (_) {
        selectionFrames++;
        return true;
      },
      elementFramer: (_, elements) {
        elementFrames.add(elements);
        return true;
      },
      notice: (message) => notices.add(message(_en)),
      revealInspector: () => inspectorReveals++,
    );
  }

  final NetlistModel model;
  final _RecordingTelemetry telemetry = _RecordingTelemetry();
  late final ProviderContainer root;
  late final ProviderContainer tab;
  ProviderContainer? active;
  late final NetcruxCxpRequestHandler handler;
  final List<String> notices = <String>[];
  int attention = 0;
  int inspectorReveals = 0;

  /// How often the whole selection was framed (Zoom to Selection).
  int selectionFrames = 0;

  /// The parts of the selection framed on their own, in order.
  final List<Set<SelectedElement>> elementFrames = <Set<SelectedElement>>[];

  static final L10N _en = lookupL10N(const Locale('en'));

  Future<void> dispose() async {
    await handler.dispose();
    tab.dispose();
    root.dispose();
  }

  Future<CruxCxpHandlerResult> highlight(
    ElementKind kind,
    String path, {
    Map<String, Object?> metadata = const <String, Object?>{},
  }) => handler.highlight(
    RequestHighlight(
      element: ElementId(kind: kind, path: path),
      metadata: metadata,
    ),
    _simcrux,
  );

  /// Lets the fire-and-forget selection work and the layout listeners run.
  Future<void> settle() async {
    for (var i = 0; i < 5; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  test('NetCrux advertises the rev. 9 kinds its handler acts on', () {
    expect(
      kNetcruxCxpBinding.acceptedKinds,
      containsAll(<ElementKind>[
        ElementKind.cell,
        ElementKind.property,
        ElementKind.timingPath,
      ]),
    );
  });

  group('a signal rooted at the top', () {
    test('is found in the scope it names, and that scope is shown', () async {
      final rig = _Rig();
      addTearDown(rig.dispose);
      final ack = await rig.highlight(ElementKind.signal, 'top.u_sub.state');
      expect(ack.honored, isTrue, reason: ack.reason);
      expect(rig.tab.read(hierarchyTreeProvider).selected!.path, <String>[
        'u_sub',
      ]);
      expect(rig.tab.read(selectedElementProvider).isEmpty, isFalse);
    });

    test('is never leaf-matched in another scope', () async {
      final rig = _Rig();
      addTearDown(rig.dispose);
      // `clk` is a net of top; `top.u_sub.clk` names one in u_sub, which has
      // none.
      final ack = await rig.highlight(ElementKind.signal, 'top.u_sub.clk');
      expect(ack.honored, isFalse);
      expect(ack.reason, isNot(contains('u_sub')));
      expect(ack.reason, isNot(contains('clk')));
      expect(rig.tab.read(selectedElementProvider).isEmpty, isTrue);
    });

    test('an escaped register is found by its escaped name', () async {
      final rig = _Rig();
      addTearDown(rig.dispose);
      final ack = await rig.highlight(ElementKind.signal, r'top.\esc.q ');
      expect(ack.honored, isTrue, reason: ack.reason);
    });

    test("a formal property's failing signal shows its fanin", () async {
      final rig = _Rig();
      addTearDown(rig.dispose);
      final ack = await rig.highlight(
        ElementKind.signal,
        'top.full',
        metadata: const <String, Object?>{
          cxpFormalPropertyKindMetadataKey: 'assert',
          cxpFormalPropertyLabelMetadataKey: 'p_full',
        },
      );
      expect(ack.honored, isTrue, reason: ack.reason);
      await rig.settle();
      final overlay = rig.tab.read(traceOverlayProvider);
      expect(overlay.mode, TraceOverlayMode.fanin);
      // full is driven by full_reg, whose D is cnt_q.
      expect(overlay.highlightedCellIds, contains('full_reg'));
    });

    test('a plain signal shows no fanin', () async {
      final rig = _Rig();
      addTearDown(rig.dispose);
      await rig.highlight(ElementKind.signal, 'top.full');
      await rig.settle();
      expect(rig.tab.read(traceOverlayProvider).isEmpty, isTrue);
    });
  });

  test('a cell is selected by its netlist name in its scope', () async {
    final rig = _Rig();
    addTearDown(rig.dispose);
    final ack = await rig.highlight(ElementKind.cell, 'top.u_sub.state_reg');
    expect(ack.honored, isTrue, reason: ack.reason);
    final primary = rig.tab.read(selectedElementProvider).primary;
    expect(primary, const SelectedElement.cell(cellId: 'state_reg'));
    expect(
      (await rig.highlight(ElementKind.cell, 'top.nope_reg')).honored,
      isFalse,
    );
  });

  test('a directed timing path is declined without echoing it', () async {
    final rig = _Rig();
    addTearDown(rig.dispose);
    final ack = await rig.highlight(ElementKind.timingPath, 'run_7/1');
    expect(ack.honored, isFalse);
    expect(ack.reason, isNot(contains('run_7')));
  });

  group('a property', () {
    late Directory dir;
    late String topFile;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('nc_property_');
      topFile = '${dir.path}/$kFormalFlowTopFile';
      File(topFile)
        ..createSync(recursive: true)
        ..writeAsStringSync(formalFlowTopSource());
    });
    tearDown(() => dir.deleteSync(recursive: true));

    _Rig rigWith(List<Override> overrides) {
      final rig = _Rig(
        model: formalFlowDesign(srcRoot: dir.path),
        overrides: overrides,
      );
      rig.tab.read(currentProjectProvider.notifier).setSourceFiles(<String>[
        topFile,
      ]);
      return rig;
    }

    test('in open core: the "requires NetCrux Pro" toast', () async {
      final rig = rigWith(const <Override>[]);
      addTearDown(rig.dispose);
      final ack = await rig.highlight(
        ElementKind.property,
        '$kFormalFlowTopFile:20',
      );
      expect(ack.honored, isFalse);
      expect(rig.notices, <String>['Property cone requires NetCrux Pro.']);
      expect(rig.tab.read(traceOverlayProvider).isEmpty, isTrue);
    });

    test('a tier that does not admit the cone: a toast naming it', () async {
      final cone = _FakeCone(denied: LicenseTier.pro);
      final rig = rigWith(<Override>[
        proOverlayInstalledProvider.overrideWithValue(true),
        inboundPropertyConeProvider.overrideWithValue(cone),
      ]);
      addTearDown(rig.dispose);
      final ack = await rig.highlight(
        ElementKind.property,
        '$kFormalFlowTopFile:20',
      );
      expect(ack.honored, isFalse);
      expect(rig.notices.single, contains('NetCrux Pro'));
      expect(rig.notices.single, contains('SimCrux'));
      expect(cone.seedsSeen, isEmpty);
    });

    test('an Enterprise verdict names Enterprise', () async {
      final rig = rigWith(<Override>[
        proOverlayInstalledProvider.overrideWithValue(true),
        inboundPropertyConeProvider.overrideWithValue(
          _FakeCone(denied: LicenseTier.enterprise),
        ),
      ]);
      addTearDown(rig.dispose);
      final ack = await rig.highlight(
        ElementKind.property,
        '$kFormalFlowTopFile:20',
      );
      expect(ack.honored, isFalse);
      expect(rig.notices.single, contains('NetCrux Enterprise'));
    });

    test('admitted: the union cone of every signal it reads', () async {
      final cone = _FakeCone(sameNets: const <String>['sub_o']);
      final rig = rigWith(<Override>[
        proOverlayInstalledProvider.overrideWithValue(true),
        inboundPropertyConeProvider.overrideWithValue(cone),
      ]);
      addTearDown(rig.dispose);
      final ack = await rig.highlight(
        ElementKind.property,
        '$kFormalFlowTopFile:22',
      );
      expect(ack.honored, isTrue, reason: ack.reason);
      await rig.settle();
      // p_sub reads u_sub.state (another scope: asked of the overlay) and
      // cnt_q; the overlay said u_sub.state is sub_o here.
      expect(cone.namesAsked, <String>['u_sub.state']);
      expect(cone.seedsSeen, hasLength(1));
      expect(cone.seedsSeen.single, isNotEmpty);
      expect(
        rig.tab.read(traceOverlayProvider).highlightedCellIds,
        contains('cone'),
      );
      expect(rig.notices, isEmpty);
    });

    test('a file that is not a source of the open design is refused', () async {
      final rig = rigWith(<Override>[
        proOverlayInstalledProvider.overrideWithValue(true),
        inboundPropertyConeProvider.overrideWithValue(_FakeCone()),
      ]);
      addTearDown(rig.dispose);
      for (final path in <String>[
        'rtl/elsewhere.sv:20',
        '../outside/top.sv:20',
        '/etc/passwd:1',
      ]) {
        final ack = await rig.highlight(ElementKind.property, path);
        expect(ack.honored, isFalse, reason: path);
        expect(ack.reason, isNot(contains(path)), reason: path);
      }
      expect(rig.notices, isEmpty);
    });
  });

  group('a timing path in a selection', () {
    NotifySelection path(
      List<String> registers, {
      String? mapping = 'register',
    }) => NotifySelection(
      elements: <ElementId>[
        const ElementId(kind: ElementKind.timingPath, path: 'run_1/1'),
        for (final r in registers) ElementId(kind: ElementKind.signal, path: r),
        const ElementId(
          kind: ElementKind.source,
          path: 'file:///w/rtl/top.sv#L21',
        ),
      ],
      metadata: <String, Object?>{cxpMappingMetadataKey: ?mapping},
    );

    test('highlights its registers and shows the path', () async {
      final rig = _Rig();
      addTearDown(rig.dispose);
      rig.handler.selection(path(<String>['top.cnt_q', 'top.full']), _simcrux);
      await rig.settle();
      final shown = rig.tab.read(receivedTimingPathProvider)!;
      expect(shown.peer, 'SimCrux');
      expect(shown.fidelity, TimingPathFidelity.register);
      expect(shown.registers.map((r) => r.place), <TimingPathRegisterPlace>[
        TimingPathRegisterPlace.shown,
        TimingPathRegisterPlace.shown,
      ]);
      expect(shown.statements, <String>['top.sv:21']);
      expect(rig.tab.read(selectedElementProvider).elements.length, 3);
      expect(rig.inspectorReveals, 1);
      // A selection is not a request, so the runtime asks for no attention;
      // the handler asks once, under the user's setting (on by default).
      expect(rig.attention, 1);
      final event = rig.telemetry.named('flow.path.highlighted').single;
      expect(event.properties, <String, Object?>{
        'fidelity': 'register',
        'resolved': true,
      });
    });

    test('a weaker or unknown mapping is never shown stronger', () async {
      final rig = _Rig();
      addTearDown(rig.dispose);
      rig.handler.selection(
        path(<String>['top.full'], mapping: 'statement'),
        _simcrux,
      );
      await rig.settle();
      expect(
        rig.tab.read(receivedTimingPathProvider)!.fidelity,
        TimingPathFidelity.statement,
      );
      rig.handler.selection(
        path(<String>['top.full'], mapping: 'exact'),
        _simcrux,
      );
      await rig.settle();
      expect(
        rig.tab.read(receivedTimingPathProvider)!.fidelity,
        TimingPathFidelity.unmapped,
      );
      rig.handler.selection(
        path(<String>['top.full'], mapping: null),
        _simcrux,
      );
      await rig.settle();
      expect(
        rig.tab.read(receivedTimingPathProvider)!.fidelity,
        TimingPathFidelity.unmapped,
      );
    });

    test('says which registers are elsewhere or absent', () async {
      final rig = _Rig();
      addTearDown(rig.dispose);
      rig.handler.selection(
        path(<String>['top.u_sub.state', 'top.missing_q', 'top.full']),
        _simcrux,
      );
      await rig.settle();
      final shown = rig.tab.read(receivedTimingPathProvider)!;
      expect(shown.registers.map((r) => r.place), <TimingPathRegisterPlace>[
        TimingPathRegisterPlace.otherScope,
        TimingPathRegisterPlace.notFound,
        TimingPathRegisterPlace.shown,
      ]);
      // The endpoint's scope is the one shown.
      expect(rig.tab.read(hierarchyTreeProvider).selected!.isRoot, isTrue);
    });

    test('nothing in the design: shown unresolved, counted so', () async {
      final rig = _Rig();
      addTearDown(rig.dispose);
      rig.handler.selection(path(<String>['top.nope']), _simcrux);
      await rig.settle();
      expect(rig.tab.read(receivedTimingPathProvider)!.resolved, isFalse);
      expect(
        rig.telemetry.named('flow.path.highlighted').single.properties,
        <String, Object?>{'fidelity': 'register', 'resolved': false},
      );
    });

    test('lands in the tab that is active when it arrives', () async {
      final rig = _Rig();
      addTearDown(rig.dispose);
      final other = _tab(rig.root, rig.model);
      addTearDown(other.dispose);
      rig.active = other;
      rig.handler.selection(path(<String>['top.full']), _simcrux);
      await rig.settle();
      expect(other.read(receivedTimingPathProvider), isNotNull);
      expect(rig.tab.read(receivedTimingPathProvider), isNull);
    });

    group('followed by a directed highlight of one of its ends', () {
      /// What a highlight of [signal] selects on its own, with no path
      /// before it: the register's part of the path's selection.
      Future<Selection> alone(String signal) async {
        final rig = _Rig();
        addTearDown(rig.dispose);
        final ack = await rig.highlight(ElementKind.signal, signal);
        expect(ack.honored, isTrue, reason: ack.reason);
        final selection = rig.tab.read(selectedElementProvider);
        return selection;
      }

      test('the end register keeps both ends selected and is framed', () async {
        final end = await alone('top.full');
        final start = await alone('top.cnt_q');
        final rig = _Rig();
        addTearDown(rig.dispose);
        // SimCrux's order: the path as a selection, then the endpoint.
        rig.handler.selection(
          path(<String>['top.cnt_q', 'top.full']),
          _simcrux,
        );
        await rig.settle();
        final ack = await rig.highlight(ElementKind.signal, 'top.full');
        await rig.settle();

        expect(ack.honored, isTrue, reason: ack.reason);
        final selection = rig.tab.read(selectedElementProvider);
        expect(selection.elements, containsAll(start.elements));
        expect(selection.elements, containsAll(end.elements));
        expect(selection.primary, end.primary);
        expect(rig.elementFrames, <Set<SelectedElement>>[end.elements]);
        expect(rig.selectionFrames, 0);
        // The Inspector still names both ends of the path.
        final shown = rig.tab.read(receivedTimingPathProvider)!;
        expect(shown.registers.map((r) => r.name), <String>[
          'top.cnt_q',
          'top.full',
        ]);
        expect(
          shown.registers.map((r) => r.place),
          everyElement(TimingPathRegisterPlace.shown),
        );
      });

      test('the start register keeps the path too, as its primary', () async {
        final start = await alone('top.cnt_q');
        final rig = _Rig();
        addTearDown(rig.dispose);
        rig.handler.selection(
          path(<String>['top.cnt_q', 'top.full']),
          _simcrux,
        );
        await rig.settle();
        final before = rig.tab.read(selectedElementProvider).elements;
        final ack = await rig.highlight(ElementKind.signal, 'top.cnt_q');

        expect(ack.honored, isTrue, reason: ack.reason);
        final selection = rig.tab.read(selectedElementProvider);
        expect(selection.elements, before);
        expect(selection.primary, start.primary);
        expect(rig.elementFrames, <Set<SelectedElement>>[start.elements]);
      });

      test(
        'once the selection has moved on, the highlight replaces it',
        () async {
          final end = await alone('top.full');
          final rig = _Rig();
          addTearDown(rig.dispose);
          rig.handler.selection(
            path(<String>['top.cnt_q', 'top.full']),
            _simcrux,
          );
          await rig.settle();
          rig.tab
              .read(selectedElementProvider.notifier)
              .select(const SelectedElement.cell(cellId: 'esc_reg'));
          final ack = await rig.highlight(ElementKind.signal, 'top.full');

          expect(ack.honored, isTrue, reason: ack.reason);
          expect(rig.tab.read(selectedElementProvider), end);
          expect(rig.elementFrames, isEmpty);
          expect(rig.selectionFrames, 1);
        },
      );

      test('a register that is not an end replaces the selection', () async {
        final other = await alone('top.sub_o');
        final rig = _Rig();
        addTearDown(rig.dispose);
        rig.handler.selection(
          path(<String>['top.cnt_q', 'top.full']),
          _simcrux,
        );
        await rig.settle();
        final ack = await rig.highlight(ElementKind.signal, 'top.sub_o');

        expect(ack.honored, isTrue, reason: ack.reason);
        expect(rig.tab.read(selectedElementProvider), other);
        expect(rig.elementFrames, isEmpty);
      });
    });
  });

  group('an implementation run or timing report to open', () {
    late Directory dir;
    late String report;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('nc_flow_');
      report = File('${dir.path}/report.json').absolute.path;
      File(report).writeAsStringSync('{}');
    });
    tearDown(() => dir.deleteSync(recursive: true));

    Future<CruxCxpHandlerResult> open(_Rig rig, String kind, String? path) =>
        rig.handler.openArtifact(
          RequestOpenArtifact(designId: 'd1', artifactKind: kind, path: path),
          _simcrux,
        );

    test(
      'a path that fails the floor or is the wrong entry is refused',
      () async {
        final rig = _Rig(
          overrides: <Override>[
            proOverlayInstalledProvider.overrideWithValue(true),
            flowArtifactOpenerProvider.overrideWithValue(_FakeOpener()),
          ],
        );
        addTearDown(rig.dispose);
        for (final (kind, path) in <(String, String)>[
          (kCxpTimingReportArtifactKind, 'relative/report.json'),
          (kCxpTimingReportArtifactKind, ' $report'),
          (kCxpTimingReportArtifactKind, dir.absolute.path),
          (kCxpFlowRunArtifactKind, report),
          (kCxpTimingReportArtifactKind, '${dir.absolute.path}/missing.json'),
        ]) {
          final ack = await open(rig, kind, path);
          expect(ack.honored, isFalse, reason: '$kind $path');
          expect(ack.reason, isNot(contains(dir.path)), reason: path);
        }
      },
    );

    test('in open core: the "requires NetCrux Pro" toast', () async {
      final rig = _Rig();
      addTearDown(rig.dispose);
      final ack = await open(rig, kCxpTimingReportArtifactKind, report);
      expect(ack.honored, isFalse);
      expect(rig.notices, <String>[
        'Open implementation run requires NetCrux Pro.',
      ]);
    });

    test('a tier that does not admit it: a toast naming it', () async {
      final opener = _FakeOpener(denied: LicenseTier.pro);
      final rig = _Rig(
        overrides: <Override>[
          proOverlayInstalledProvider.overrideWithValue(true),
          flowArtifactOpenerProvider.overrideWithValue(opener),
        ],
      );
      addTearDown(rig.dispose);
      final ack = await open(rig, kCxpTimingReportArtifactKind, report);
      expect(ack.honored, isFalse);
      expect(rig.notices.single, contains('NetCrux Pro'));
      expect(opener.opened, isEmpty);
    });

    test('admitted: handed to the overlay', () async {
      final opener = _FakeOpener();
      final rig = _Rig(
        overrides: <Override>[
          proOverlayInstalledProvider.overrideWithValue(true),
          flowArtifactOpenerProvider.overrideWithValue(opener),
        ],
      );
      addTearDown(rig.dispose);
      final ack = await open(rig, kCxpTimingReportArtifactKind, report);
      expect(ack.honored, isTrue);
      expect(opener.opened, <(String, String)>[
        (kCxpTimingReportArtifactKind, report),
      ]);
    });
  });
}
