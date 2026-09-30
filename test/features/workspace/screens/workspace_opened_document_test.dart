// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/core/cli/cli_arg_parser.dart';
import 'package:netcrux/features/project/providers/current_project_provider.dart';
import 'package:netcrux/services/file_open/incoming_document_service.dart';
import 'package:netcrux/services/file_open/incoming_document_service_provider.dart';
import 'package:netcrux/services/workspace/netcrux_workspace_notifier.dart';
import 'package:path/path.dart' as p;

import '../../../helpers/workspace_app_harness.dart';

/// A document macOS opens — a Finder double-click, "Open With", a drop on
/// the Dock icon — lands in a tab exactly as the same path on the command
/// line does, and a project file whose contents are refused on the command
/// line is refused this way too.
///
/// The runner's Swift half cannot run under `flutter test`; this drives the
/// Dart half from the service the runner feeds, and the Swift is proven by
/// building the runner.
void main() {
  late Directory dir;
  // Resolved, because macOS reaches the temp directory through the
  // `/var` -> `/private/var` link.
  setUp(
    () => dir = Directory(
      Directory.systemTemp
          .createTempSync('netcrux_opened_document_')
          .resolveSymbolicLinksSync(),
    ),
  );
  tearDown(() => dir.deleteSync(recursive: true));
  final macOS = TargetPlatformVariant.only(TargetPlatform.macOS);

  String writeProject(String name, {List<String> commands = const []}) {
    final path = p.join(dir.path, '$name.netcrux-project');
    File(path).writeAsStringSync(
      jsonEncode(<String, Object?>{
        'version': 1,
        'sourceFiles': <String>['rtl/top.v'],
        'topModule': 'top',
        'defines': <String, String>{'WIDTH': '32'},
        'extraYosysCommands': commands,
      }),
    );
    return path;
  }

  /// A stream standing in for the runner's deliveries. Closed without
  /// awaiting: a single-subscription controller's `close` completes only once
  /// something has listened, so a workspace that never subscribed would hang
  /// the teardown instead of failing the test.
  StreamController<String> deliveries() {
    final documents = StreamController<String>();
    addTearDown(() => unawaited(documents.close()));
    return documents;
  }

  /// Boots the app with [documents] standing in for the runner's deliveries.
  Future<WorkspaceAppHarness> boot(
    WidgetTester tester,
    StreamController<String> documents,
  ) => WorkspaceAppHarness.boot(
    tester,
    overrides: <Override>[
      incomingDocumentServiceProvider.overrideWithValue(
        _Deliveries(documents.stream),
      ),
    ],
  );

  testWidgets('a project double-clicked while NetCrux runs opens with its '
      'project settings', (tester) async {
    final documents = deliveries();
    final h = await boot(tester, documents);
    expect(h.root.read(netcruxWorkspaceProvider).value!.tabs, isEmpty);

    final path = writeProject('demo', commands: const <String>['flatten']);
    documents.add(path);
    await WorkspaceAppHarness.settle(tester);

    final project = h.activeTab.read(currentProjectProvider);
    expect(project.sourceFiles, <String>[p.join(dir.path, 'rtl', 'top.v')]);
    expect(project.topModule, 'top');
    expect(project.defines, const <String, String>{'WIDTH': '32'});
    expect(project.extraYosysCommands, const <String>['flatten']);
    final tab = h.root.read(netcruxWorkspaceProvider).value!.tabs.single;
    expect(tab.displayName, 'demo');
    expect(tab.payload.projectFilePath, path);
    expect(tester.takeException(), isNull);
    await WorkspaceAppHarness.unmount(tester);
  }, variant: macOS);

  testWidgets('a project that asks to run an unvetted Yosys command is '
      'refused, as it is from the command line', (tester) async {
    final documents = deliveries();
    final h = await boot(tester, documents);

    documents.add(
      writeProject(
        'hostile',
        commands: const <String>['proc', 'exec -- touch /tmp/pwned'],
      ),
    );
    await WorkspaceAppHarness.settle(tester);

    expect(h.root.read(netcruxWorkspaceProvider).value!.tabs, isEmpty);
    expect(find.textContaining('custom Yosys command "exec"'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await WorkspaceAppHarness.unmount(tester);
  }, variant: macOS);

  testWidgets('several documents open one tab each, in the order they '
      'arrived', (tester) async {
    final documents = deliveries();
    final h = await boot(tester, documents);

    documents
      ..add(writeProject('alpha'))
      ..add(writeProject('beta'));
    await WorkspaceAppHarness.settle(tester);

    final tabs = h.root.read(netcruxWorkspaceProvider).value!.tabs;
    expect(tabs.map((t) => t.displayName), <String>['alpha', 'beta']);
    expect(tester.takeException(), isNull);
    await WorkspaceAppHarness.unmount(tester);
  }, variant: macOS);

  testWidgets('the project that launched NetCrux opens as the launch '
      'intent', (tester) async {
    final path = writeProject('demo', commands: const <String>['flatten']);
    // What `bootstrap` does with no arguments and a document from macOS.
    final intent = await const CliArgParser().parseLaunch(
      const <String>[],
      openedDocument: () async => path,
    );
    final h = await WorkspaceAppHarness.boot(tester, intent: intent);

    final project = h.activeTab.read(currentProjectProvider);
    expect(project.topModule, 'top');
    expect(project.extraYosysCommands, const <String>['flatten']);
    expect(
      h.root
          .read(netcruxWorkspaceProvider)
          .value!
          .tabs
          .single
          .payload
          .projectFilePath,
      path,
    );
    expect(tester.takeException(), isNull);
    await WorkspaceAppHarness.unmount(tester);
  }, variant: macOS);
}

/// The runner's deliveries, played by a stream the test controls.
class _Deliveries extends IncomingDocumentService {
  _Deliveries(this._documents) : super(isSupported: _always);

  final Stream<String> _documents;

  @override
  Stream<String> get documents => _documents;
}

bool _always() => true;
