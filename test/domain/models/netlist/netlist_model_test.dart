// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/models/netlist/netlist_model.dart';

const _topJson = <String, Object?>{
  'creator': 'Yosys 0.50 (test)',
  'modules': <String, Object?>{
    'top': <String, Object?>{
      'attributes': <String, Object?>{'top': '1'},
      'ports': <String, Object?>{},
      'cells': <String, Object?>{},
      'netnames': <String, Object?>{},
    },
    'inner': <String, Object?>{
      'attributes': <String, Object?>{},
      'ports': <String, Object?>{},
      'cells': <String, Object?>{},
      'netnames': <String, Object?>{},
    },
  },
};

void main() {
  group('NetlistModel', () {
    test('fromJson parses creator and modules', () {
      final model = NetlistModel.fromJson(_topJson);
      expect(model.creator, 'Yosys 0.50 (test)');
      expect(model.modules.keys, containsAll(<String>['top', 'inner']));
    });

    test('topModule returns the module marked top', () {
      final model = NetlistModel.fromJson(_topJson);
      expect(model.topModule, isNotNull);
      expect(model.topModule!.name, 'top');
    });

    test('topModule returns null when no module is top', () {
      const json = <String, Object?>{
        'creator': 'x',
        'modules': <String, Object?>{
          'a': <String, Object?>{
            'attributes': <String, Object?>{},
            'ports': <String, Object?>{},
            'cells': <String, Object?>{},
            'netnames': <String, Object?>{},
          },
        },
      };
      final model = NetlistModel.fromJson(json);
      expect(model.topModule, isNull);
    });

    test('fromJson throws FormatException when modules is missing', () {
      expect(
        () => NetlistModel.fromJson(const <String, Object?>{'creator': 'x'}),
        throwsFormatException,
      );
    });

    test('toJson round-trips through fromJson', () {
      final model = NetlistModel.fromJson(_topJson);
      final round = NetlistModel.fromJson(model.toJson());
      expect(round, equals(model));
    });

    test('equality and hashCode are value-based', () {
      final a = NetlistModel.fromJson(_topJson);
      final b = NetlistModel.fromJson(_topJson);
      const c = NetlistModel(creator: 'x', modules: {});
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(equals(c)));
    });

    test('copyWith replaces only specified fields', () {
      final model = NetlistModel.fromJson(_topJson);
      final renamed = model.copyWith(creator: 'newer');
      expect(renamed.creator, 'newer');
      expect(renamed.modules, model.modules);
    });
  });
}
