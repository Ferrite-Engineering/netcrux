// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

@TestOn('browser')
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/services/yosys/prebuilt_netlist_loader.dart';

final String _netlist = jsonEncode(<String, Object?>{
  'creator': 'NetlistSynthesizer (rohd)',
  'version': '0.1.0',
  'files': <String>['lib/design.dart'],
  'modules': <String, Object?>{
    'top': <String, Object?>{
      'attributes': <String, Object?>{
        'top': 1,
        'rohd.src_trace': <String, Object?>{
          'signals': <String, Object?>{
            's': <String>['0:12:3'],
          },
          'instances': <String, Object?>{
            'blk': <String>['0:20:5'],
          },
        },
      },
      'ports': <String, Object?>{},
      'cells': <String, Object?>{
        'blk': <String, Object?>{
          'type': 'Sequential',
          'port_directions': <String, Object?>{'d': 'input'},
          'connections': <String, Object?>{
            'd': <int>[2],
          },
        },
      },
      'netnames': <String, Object?>{
        's': <String, Object?>{
          'bits': <int>[2],
          'logic_type': <String, Object?>{
            'typeName': 'Beat',
            'fields': <Object>[
              <String, Object?>{'name': 'v', 'width': 1},
            ],
          },
        },
      },
    },
  },
});

/// The browser build has no file system and no isolate: a ROHD netlist is
/// read from text and parsed in place, and its source locations and types
/// still arrive.
void main() {
  test('a ROHD netlist opens in the browser with its extensions', () async {
    final loaded = await PrebuiltNetlistLoader(
      read: (_) async => _netlist,
      parseOnIsolate: false,
    ).loadWithReport('blob:https://app.netcrux.app/1#rohd.json');
    final top = loaded!.model.topModule!;
    expect(top.nets['s']!.attributes['src'], 'lib/design.dart:12.3');
    expect(top.nets['s']!.attributes['rohd.type'], 'Beat{v:1}');
    expect(top.cells['blk']!.attributes['src'], 'lib/design.dart:20.5');
    expect(top.attributes.containsKey('rohd.src_trace'), isFalse);
    expect(loaded.report.isEmpty, isTrue);
  });
}
