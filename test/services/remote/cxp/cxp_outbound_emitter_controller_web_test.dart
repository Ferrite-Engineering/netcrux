// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

@TestOn('browser')
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/models/netlist/netlist_model.dart';
import 'package:netcrux/domain/models/selection/selected_element.dart';
import 'package:netcrux/features/hierarchy/providers/hierarchy_tree_notifier.dart';
import 'package:netcrux/features/viewer/providers/selected_element_notifier.dart';
import 'package:netcrux/services/remote/cxp/cxp_outbound_emitter_controller.dart';

/// Runs in a real browser, where there is no socket to broadcast a selection
/// on and no file system to derive a design id from: selecting an element must
/// not reach either. It used to throw an unsupported-operation error out of the
/// listener on every selection, which an editor hosting the viewer reports as a
/// failure of the page.
void main() {
  test('selecting an element in the browser build throws nothing', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container
        .read(hierarchyTreeProvider.notifier)
        .setModel(
          NetlistModel.fromJson(const <String, Object?>{
            'creator': 'test',
            'modules': <String, Object?>{
              'top': <String, Object?>{
                'attributes': <String, Object?>{'top': '1'},
                'cells': <String, Object?>{
                  'u_a': <String, Object?>{
                    'type': r'$and',
                    'port_directions': <String, Object?>{},
                    'connections': <String, Object?>{},
                  },
                },
              },
            },
          }),
        );
    final controller = CxpOutboundEmitterController(container);
    addTearDown(controller.dispose);

    container
        .read(selectedElementProvider.notifier)
        .select(const SelectedElement.cell(cellId: 'u_a'));
  });
}
