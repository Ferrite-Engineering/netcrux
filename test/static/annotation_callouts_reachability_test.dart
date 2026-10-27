// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// Reachability of the annotation callouts: every binding, opener, layer and
// claim has something in the app that calls it.
//
// A green suite does not say a feature can be reached: a layer can be written
// and its only mount deleted. So each link from the user to the callouts on
// the canvas is asserted as text in the file that makes the call, and a link
// that goes away fails here with the file named.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _read(String path) {
  final file = File(path);
  if (!file.existsSync()) fail('$path does not exist');
  return file.readAsStringSync();
}

void main() {
  const lib = 'lib';

  test('View > Show Annotation Callouts runs the toggle, with no gate', () {
    final dispatcher = _read(
      '$lib/features/workspace/services/workspace_action_dispatcher.dart',
    );
    expect(
      dispatcher,
      contains('case NetcruxAction.toggleAnnotationCallouts:'),
    );
    expect(dispatcher, contains('toggleAnnotationCallouts(context);'));
    expect(
      _read('$lib/core/shortcuts/menu_layout.dart'),
      contains('NetcruxAction.toggleAnnotationCallouts'),
    );
  });

  test(
    'the canvas mounts the layer over itself, inside the gesture handler',
    () {
      final tab = _read(
        '$lib/features/workspace/widgets/project_tab_content.dart',
      );
      expect(tab, contains('SchematicCalloutLayer()'));
      expect(
        tab.indexOf('SchematicGestureHandler('),
        lessThan(tab.indexOf('SchematicCalloutLayer()')),
        reason: "the layer is the gesture handler's descendant",
      );
    },
  );

  test('the gesture handler honours the claim a callout makes', () {
    final handler = _read(
      '$lib/features/viewer/widgets/schematic_gesture_handler.dart',
    );
    expect(
      RegExp(
        r'ref\.read\(canvasOverlayGestureClaimProvider\)',
      ).allMatches(handler),
      hasLength(3),
      reason: 'press, double click and context menu each check it',
    );
    expect(
      _read('$lib/features/annotation_callouts/schematic_callout_layer.dart'),
      contains('canvasOverlayGestureClaimProvider.notifier'),
    );
  });

  test('the layer reads the shared statuses and never the licence', () {
    final layer = _read(
      '$lib/features/annotation_callouts/schematic_callout_layer.dart',
    );
    for (final call in <String>[
      'ref.watch(annotationStatusesProvider)',
      'ref.watch(annotationCalloutsVisibleProvider)',
      'calloutAnchorInDesign(laidOut, note)',
      'calloutDetailFor(LodBandRouter.bandFor(transform.zoom))',
      'showAnnotationForTargetOpenerProvider',
      'annotationStoreProvider',
    ]) {
      expect(layer, contains(call), reason: call);
    }
    for (final gate in <String>['licenseTierProvider', 'betaPeriodProvider']) {
      expect(layer, isNot(contains(gate)), reason: gate);
    }
  });

  test('statuses are computed per tab from the recorded witness', () {
    expect(
      _read('$lib/services/workspace/netcrux_tab_overrides.dart'),
      contains(
        'annotationStatusesProvider.overrideWith(annotationStatusesForTab)',
      ),
    );
    expect(
      _read(
        '$lib/features/inspector/widgets/annotation_inspector_section.dart',
      ),
      contains('captureAnnotationWitness('),
    );
  });
}
