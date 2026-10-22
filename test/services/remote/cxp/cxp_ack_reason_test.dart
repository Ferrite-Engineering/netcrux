// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

@TestOn('vm')
library;

import 'dart:io';

import 'package:crux_cxp/crux_cxp.dart';
import 'package:crux_cxp_ui/crux_cxp_ui.dart' show CruxCxpHandlerResult;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/models/netlist/module.dart';
import 'package:netcrux/domain/models/netlist/netlist_model.dart';
import 'package:netcrux/domain/models/project/netcrux_project.dart';
import 'package:netcrux/features/hierarchy/providers/hierarchy_tree_notifier.dart';
import 'package:netcrux/features/settings/providers/app_settings_provider.dart';
import 'package:netcrux/services/remote/cxp/cxp_inbound_handler.dart';
import 'package:netcrux/services/remote/cxp/cxp_workspace_link.dart';
import 'package:netcrux/services/remote/cxp/editor_open_service.dart';
import 'package:netcrux/services/remote/cxp/flow_artifact_opener.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../helpers/cxp_test_overrides.dart';
import '../../../helpers/telemetry_test_overrides.dart';

/// CXP 1.3 section 9.11 and conformance item 22: the `reason` of a refusal
/// names the kind of refusal and nothing the sender supplied. Every refusal
/// path of NetCrux's request handler is driven here with a request whose
/// path, design id, file name and kind name are unmistakable, and the reason
/// is searched for each of them.
///
/// MUTATION: interpolating a path, a design id, an element or artifact kind,
/// an executable or an exception into any reason in the handler or the editor
/// service turns the matching case red.
const PeerIdentity _sender = PeerIdentity(
  peerId: 'reason-test-sender',
  productName: 'test',
  productVersion: '0.0.0',
);

/// [posix] spelled as an absolute path on the host: a drive-less path is not
/// absolute on Windows, and the CXP floor refuses it as relative.
String _abs(String posix) =>
    Platform.isWindows ? 'C:${posix.replaceAll('/', r'\')}' : posix;

/// The sentinel segments of [value] read as a path in either separator style:
/// the ones this test minted, which start with `zq`.
Iterable<String> _segments(String value) =>
    value.split(RegExp(r'[/\\]')).where((s) => s.startsWith('zq'));

/// Fails when [result] is not a refusal or when its reason contains any of
/// [sent], whole or by path segment.
void _expectNothingEchoed(CruxCxpHandlerResult result, List<String> sent) {
  expect(result.honored, isFalse);
  final reason = result.reason;
  expect(reason, isNotNull);
  expect(reason, isNotEmpty);
  for (final value in sent) {
    expect(reason, isNot(contains(value)), reason: 'echoes "$value"');
    for (final segment in _segments(value)) {
      expect(reason, isNot(contains(segment)), reason: 'echoes "$segment"');
    }
  }
}

NetlistModel _model() => const NetlistModel(
  creator: 'test',
  modules: <String, Module>{
    'top': Module(
      name: 'top',
      attributes: <String, String>{'top': '1'},
      ports: {},
      cells: {},
      nets: {},
    ),
  },
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory records;
  late Directory workDir;
  late List<ProviderContainer> containers;

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    records = Directory.systemTemp.createTempSync('zqnetcrux_reason_ws_');
    workDir = Directory.systemTemp.createTempSync('zqnetcrux_reason_');
    containers = <ProviderContainer>[];
  });

  tearDown(() {
    for (final c in containers) {
      c.dispose();
    }
    for (final dir in <Directory>[records, workDir]) {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    }
  });

  /// NetCrux's real handler over a root container with `/zqrtl` as the one
  /// directory the user has open, an editor command when [editorCommand] is
  /// non-empty, and an active tab holding a design when [withTab] and
  /// [withModel].
  Future<NetcruxCxpRequestHandler> makeHandler({
    bool withTab = true,
    bool withModel = true,
    String editorCommand = '',
    EditorOpenService? editorService,
  }) async {
    final root = ProviderContainer(
      overrides: <Override>[
        ...netcruxTelemetryTestOverrides(),
        ...netcruxCxpOffTestOverrides(),
        cxpPathContainmentProvider.overrideWithValue(
          CxpPathContainment(roots: () => <String>[_abs('/zqrtl')]),
        ),
        cxpWorkspaceStoreProvider.overrideWithValue(
          CxpWorkspaceStore(workspaceDirectory: records.path),
        ),
      ],
    );
    containers.add(root);
    final tab = ProviderContainer(parent: root);
    containers.add(tab);
    if (withModel) {
      tab.read(hierarchyTreeProvider.notifier).setModel(_model());
    }
    await root.read(appSettingsProvider.future);
    // Always set, so an unset command is empty rather than the default.
    await root
        .read(appSettingsProvider.notifier)
        .setCxpEditorCommand(editorCommand);
    return NetcruxCxpRequestHandler(
      rootContainer: root,
      activeTabContainerLookup: () => withTab ? tab : null,
      // Never the real service: a request that reaches an editor must not
      // start one.
      editorService:
          editorService ??
          EditorOpenService(
            processRunner: (_, _) async => ProcessResult(0, 0, '', ''),
          ),
    );
  }

  group('request_highlight refusals', () {
    Future<CruxCxpHandlerResult> highlight(
      NetcruxCxpRequestHandler handler,
      ElementId element, {
      Map<String, Object?> metadata = const <String, Object?>{},
    }) => handler.highlight(
      RequestHighlight(element: element, metadata: metadata),
      _sender,
    );

    test('a signal-like element that is not in the open design', () async {
      final handler = await makeHandler();
      const path = 'top.zqsub.zqsig_missing';
      for (final kind in <ElementKind>[
        ElementKind.signal,
        ElementKind.instance,
        ElementKind.net,
        ElementKind.port,
      ]) {
        final result = await highlight(
          handler,
          ElementId(kind: kind, path: path),
        );
        _expectNothingEchoed(result, <String>[path]);
      }
    });

    test('a scope that is not in the open design', () async {
      final handler = await makeHandler();
      const path = 'top.zqscope.zqsub';
      final result = await highlight(
        handler,
        const ElementId(kind: ElementKind.scope, path: path),
      );
      _expectNothingEchoed(result, <String>[path]);
    });

    test('a scope when no design is loaded', () async {
      final handler = await makeHandler(withModel: false);
      const path = 'top.zqscope';
      final result = await highlight(
        handler,
        const ElementId(kind: ElementKind.scope, path: path),
      );
      _expectNothingEchoed(result, <String>[path]);
    });

    test('a signal-like element when no tab is active', () async {
      final handler = await makeHandler(withTab: false);
      const path = 'top.zqsig';
      final result = await highlight(
        handler,
        const ElementId(kind: ElementKind.signal, path: path),
      );
      _expectNothingEchoed(result, <String>[path]);
    });

    test(
      'a kind NetCrux does not handle and a kind it never heard of',
      () async {
        final handler = await makeHandler();
        const path = 'top.zqrule/zqpath.v:3';
        for (final kind in <ElementKind>[
          ElementKind.rule,
          ElementKind.test,
          ElementKind.breakpoint,
          ElementKind.marker,
          ElementKind('zqkind_unheard'),
        ]) {
          final result = await highlight(
            handler,
            ElementId(kind: kind, path: path),
          );
          _expectNothingEchoed(result, <String>[path, 'zqkind_unheard']);
        }
      },
    );

    test('a timing path', () async {
      final handler = await makeHandler();
      const path = 'zqrun/zq3';
      final result = await highlight(
        handler,
        const ElementId(kind: ElementKind.timingPath, path: path),
      );
      _expectNothingEchoed(result, <String>[path]);
    });

    test('a property that is not a project-relative file and line', () async {
      final handler = await makeHandler();
      const path = 'zqnolocation';
      final result = await highlight(
        handler,
        const ElementId(kind: ElementKind.property, path: path),
      );
      _expectNothingEchoed(result, <String>[path]);
    });

    test('a property in a file the open design does not have', () async {
      final handler = await makeHandler();
      const path = 'zqdir/zqprops.sv:7';
      final result = await highlight(
        handler,
        const ElementId(kind: ElementKind.property, path: path),
      );
      _expectNothingEchoed(result, <String>[path]);
    });

    test(
      'a source element outside the directories the user has opened',
      () async {
        final handler = await makeHandler(editorCommand: 'zqeditor {file}');
        final path = _abs('/zqoutside/zqdir/zqtop.v');
        final result = await highlight(
          handler,
          ElementId(kind: ElementKind.source, path: path),
        );
        _expectNothingEchoed(result, <String>[path]);
      },
    );

    test('a source element with no editor command configured', () async {
      final handler = await makeHandler();
      final path = _abs('/zqrtl/zqdir/zqtop.v');
      final result = await highlight(
        handler,
        ElementId(kind: ElementKind.source, path: path),
      );
      _expectNothingEchoed(result, <String>[path]);
    });

    test('a design id that names no recorded source', () async {
      final handler = await makeHandler();
      const path = 'top.zqsub.zqsig_missing';
      const designId = 'zqdesign-id-0123456789abcdef';
      final result = await highlight(
        handler,
        const ElementId(kind: ElementKind.signal, path: path),
        metadata: <String, Object?>{cxpDesignIdMetadataKey: designId},
      );
      _expectNothingEchoed(result, <String>[path, designId]);
    });
  });

  group('request_open_artifact refusals', () {
    Future<CruxCxpHandlerResult> open(
      NetcruxCxpRequestHandler handler, {
      required String designId,
      String artifactKind = kCxpSourceArtifactKind,
      String? path,
    }) => handler.openArtifact(
      RequestOpenArtifact(
        designId: designId,
        artifactKind: artifactKind,
        path: path,
      ),
      _sender,
    );

    File file(String name, [String content = 'zqjunk\n']) =>
        File('${workDir.path}/zqdir/$name')
          ..createSync(recursive: true)
          ..writeAsStringSync(content);

    test('a kind NetCrux does not open', () async {
      final handler = await makeHandler();
      const designId = 'zqdesign-kind-0123456789abcdef';
      const kind = 'zqkind_artifact';
      final hint = _abs('/zqdir/zqrun.vcd');
      final result = await open(
        handler,
        designId: designId,
        artifactKind: kind,
        path: hint,
      );
      _expectNothingEchoed(result, <String>[designId, kind, hint]);
    });

    test('a design with no recorded artifact and no hint', () async {
      final handler = await makeHandler();
      const designId = 'zqdesign-unrecorded-0123456789';
      for (final kind in <String>[
        kCxpSourceArtifactKind,
        kCxpProjectArtifactKind,
      ]) {
        final result = await open(
          handler,
          designId: designId,
          artifactKind: kind,
        );
        _expectNothingEchoed(result, <String>[designId]);
      }
    });

    test('a hint that is not an absolute path', () async {
      final handler = await makeHandler();
      const designId = 'zqdesign-relative-0123456789a';
      const hint = 'zqrelative/zqtop.v';
      final result = await open(handler, designId: designId, path: hint);
      _expectNothingEchoed(result, <String>[designId, hint]);
    });

    test('a hint that names no file here', () async {
      final handler = await makeHandler();
      const designId = 'zqdesign-missing-0123456789ab';
      final hint = _abs('/zqnowhere/zqdir/zqtop.v');
      final result = await open(handler, designId: designId, path: hint);
      _expectNothingEchoed(result, <String>[designId, hint]);
    });

    test('a file when no tab is active', () async {
      final handler = await makeHandler(withTab: false);
      const designId = 'zqdesign-notab-0123456789abc';
      final top = file('zqtop.v');
      final result = await open(handler, designId: designId, path: top.path);
      _expectNothingEchoed(result, <String>[designId, top.path]);
    });

    test('a project file NetCrux cannot read', () async {
      final handler = await makeHandler();
      const designId = 'zqdesign-project-0123456789ab';
      for (final name in <String>[
        'zqbroken.$kNetcruxProjectExtension',
        'zqbroken.crux-project',
        'zqnotaproject.txt',
      ]) {
        final broken = file(name);
        final result = await open(
          handler,
          designId: designId,
          artifactKind: kCxpProjectArtifactKind,
          path: broken.path,
        );
        _expectNothingEchoed(result, <String>[designId, broken.path, name]);
      }
    });

    test('a run or a timing report that is not here or not allowed', () async {
      final handler = await makeHandler();
      const designId = 'zqdesign-flow-0123456789abcde';
      final missing = _abs('/zqnowhere/zqrun');
      final report = file('zqtiming.rpt');
      final runDir = Directory('${workDir.path}/zqrundir')..createSync();
      final cases = <({String kind, String? path})>[
        (kind: kCxpFlowRunArtifactKind, path: null),
        (kind: kCxpFlowRunArtifactKind, path: 'zqrelative/zqrun'),
        (kind: kCxpFlowRunArtifactKind, path: missing),
        (kind: kCxpFlowRunArtifactKind, path: report.path),
        (kind: kCxpTimingReportArtifactKind, path: missing),
        (kind: kCxpFlowRunArtifactKind, path: runDir.path),
        (kind: kCxpTimingReportArtifactKind, path: report.path),
      ];
      for (final c in cases) {
        final result = await open(
          handler,
          designId: designId,
          artifactKind: c.kind,
          path: c.path,
        );
        _expectNothingEchoed(result, <String>[
          designId,
          ?c.path,
          report.path,
          runDir.path,
        ]);
      }
    });
  });

  group('request_open_source refusals', () {
    Future<CruxCxpHandlerResult> openSource(
      NetcruxCxpRequestHandler handler,
      String file,
    ) =>
        handler.openSource(RequestOpenSource(filePath: file, line: 3), _sender);

    test('no editor command configured', () async {
      final handler = await makeHandler();
      final file = _abs('/zqrtl/zqdir/zqalu.sv');
      _expectNothingEchoed(await openSource(handler, file), <String>[file]);
    });

    test('a file outside the directories the user has opened', () async {
      final handler = await makeHandler(editorCommand: 'zqeditor {file}');
      final file = _abs('/zqoutside/zqdir/zqpasswd.sv');
      _expectNothingEchoed(await openSource(handler, file), <String>[file]);
    });

    test('a file that is not an absolute path', () async {
      final handler = await makeHandler(editorCommand: 'zqeditor {file}');
      const file = 'zqrelative/zqalu.sv';
      _expectNothingEchoed(await openSource(handler, file), <String>[file]);
    });

    test(
      'an editor command that puts a placeholder in the executable',
      () async {
        final handler = await makeHandler(editorCommand: '{file} -g');
        final file = _abs('/zqrtl/zqdir/zqalu.sv');
        _expectNothingEchoed(await openSource(handler, file), <String>[file]);
      },
    );

    test('an editor that exits non-zero', () async {
      final handler = await makeHandler(
        editorCommand: '/zqbin/zqeditor {file}',
        editorService: EditorOpenService(
          processRunner: (_, _) async => ProcessResult(0, 7, 'zqout', 'zqerr'),
        ),
      );
      final file = _abs('/zqrtl/zqdir/zqalu.sv');
      _expectNothingEchoed(await openSource(handler, file), <String>[
        file,
        'zqeditor',
      ]);
    });

    test('an editor that cannot be started', () async {
      final handler = await makeHandler(
        editorCommand: '/zqbin/zqeditor {file}',
        editorService: EditorOpenService(
          processRunner: (executable, arguments) async =>
              throw ProcessException(
                executable,
                arguments,
                'No such file: ${arguments.join(' ')}',
              ),
        ),
      );
      final file = _abs('/zqrtl/zqdir/zqalu.sv');
      _expectNothingEchoed(await openSource(handler, file), <String>[
        file,
        'zqeditor',
        'zqbin',
      ]);
    });
  });
}
