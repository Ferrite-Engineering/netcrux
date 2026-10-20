// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// The Inspector is the one editor for an element's annotations, and it opens
// with focus from four places: the schematic's Properties entry,
// View > Properties and its shortcut, Add Annotation, and the Annotations
// panel's Edit. Each opener is a line of wiring that a green widget suite does
// not prove is reached, so this pins them against the sources, along with the
// per-tab bindings the Inspector's state needs and the absence of the dialog
// it replaced.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _read(String path) {
  final file = File(path);
  expect(file.existsSync(), isTrue, reason: '$path is missing');
  return file.readAsStringSync();
}

/// The text of the `case X:` arm in a switch statement, up to the next case.
String _caseArm(String source, String label) {
  final start = source.indexOf('case $label:');
  expect(start, isNonNegative, reason: 'no `case $label:`');
  final next = source.indexOf('case ', start + label.length + 6);
  return source.substring(start, next < 0 ? source.length : next);
}

void main() {
  test('the right dock mounts the Inspector', () {
    expect(
      _read('lib/features/workspace/widgets/netcrux_docks.dart'),
      contains('const InspectorPanel()'),
    );
  });

  test('the schematic Properties entry opens the Inspector with focus', () {
    final menu = _read(
      'lib/features/viewer/widgets/schematic_context_menu_controller.dart',
    );
    expect(menu, contains('l10n.contextMenuProperties'));
    expect(
      _caseArm(menu, 'SchematicContextMenuAction.openInInspector'),
      contains('ref.read(inspectorControllerProvider).open()'),
    );
  });

  test('View > Properties and its shortcut open the Inspector with focus', () {
    final dispatcher = _read(
      'lib/features/workspace/services/workspace_action_dispatcher.dart',
    );
    final arm = _caseArm(dispatcher, 'NetcruxAction.showProperties');
    expect(arm, contains('activeTabContainerOrNull(context)'));
    expect(arm, contains('read(inspectorControllerProvider)'));
    expect(arm, contains('.open()'));
    expect(
      _read('lib/core/shortcuts/menu_layout.dart'),
      contains('NetcruxAction.showProperties'),
    );
    expect(
      _read('lib/core/shortcuts/shortcut_bindings.dart'),
      contains('NetcruxAction.showProperties:'),
    );
  });

  test('Add Annotation and the panel Edit open the Inspector', () {
    final actions = _read(
      'lib/features/annotations/services/annotation_actions.dart',
    );
    expect(actions, contains('startAnnotationInInspector(tab, resolved)'));
    expect(actions, contains('openInspectorFor(tab,'));
    expect(actions, contains('read(inspectorControllerProvider).open()'));
    expect(
      _read('lib/features/annotations/services/annotation_openers.dart'),
      contains('(_) => openAddAnnotationDialog'),
    );
    expect(
      _read('lib/features/annotations/widgets/annotations_panel.dart'),
      contains('openAnnotationInInspector(tab, annotation)'),
    );
    expect(
      _read('lib/features/inspector/providers/inspector_providers.dart'),
      contains('.open();'),
    );
  });

  test('the Inspector state is per-tab', () {
    final overrides = _read(
      'lib/services/workspace/netcrux_tab_overrides.dart',
    );
    for (final provider in const <String>[
      'inspectorControllerProvider',
      'inspectorFocusRequestProvider',
      'annotationDraftsProvider',
    ]) {
      expect(
        overrides,
        contains('$provider.overrideWith('),
        reason: '$provider must be re-bound per tab',
      );
    }
  });

  test('no second path: the annotation dialog is gone', () {
    final offenders = <String>[
      for (final entity in Directory('lib').listSync(recursive: true))
        if (entity is File &&
            entity.path.endsWith('.dart') &&
            entity.readAsStringSync().contains('showAnnotationDialog'))
          entity.path,
    ];
    expect(offenders, isEmpty);
    expect(
      File(
        'lib/features/annotations/widgets/annotation_dialog.dart',
      ).existsSync(),
      isFalse,
    );
  });
}
