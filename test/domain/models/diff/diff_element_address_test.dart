// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/models/diff/diff_element_address.dart';
import 'package:netcrux/domain/models/diff/netlist_diff_element_kind.dart';

void main() {
  group('DiffElementAddress.parse', () {
    test('a user-named cell', () {
      expect(
        DiffElementAddress.parse(
          NetlistDiffElementKind.instance,
          'top.u_alu:cell',
        ),
        const DiffElementAddress(module: 'top', name: 'u_alu'),
      );
    });

    test('a generated cell name keeps its dots, slashes and colons', () {
      // Splitting on the last dot made Show in Schematic look for `v:14$3`.
      expect(
        DiffElementAddress.parse(
          NetlistDiffElementKind.instance,
          r'gray_counter.$add$/home/me/rtl/gray_counter.v:14$3:cell',
        ),
        const DiffElementAddress(
          module: 'gray_counter',
          name: r'$add$/home/me/rtl/gray_counter.v:14$3',
        ),
      );
    });

    test('a generated net', () {
      expect(
        DiffElementAddress.parse(
          NetlistDiffElementKind.net,
          r'gray_counter:net:$xor$/a/b.v:15$7_Y',
        ),
        const DiffElementAddress(
          module: 'gray_counter',
          name: r'$xor$/a/b.v:15$7_Y',
        ),
      );
    });

    test('a port and a module', () {
      expect(
        DiffElementAddress.parse(NetlistDiffElementKind.port, 'top.in_a'),
        const DiffElementAddress(module: 'top', name: 'in_a'),
      );
      expect(
        DiffElementAddress.parse(NetlistDiffElementKind.module, 'top:module'),
        const DiffElementAddress(module: 'top', name: 'top'),
      );
    });

    test('a path of another shape is null', () {
      expect(
        DiffElementAddress.parse(NetlistDiffElementKind.instance, 'top.alu'),
        isNull,
      );
      expect(
        DiffElementAddress.parse(NetlistDiffElementKind.net, 'top.foo'),
        isNull,
      );
      expect(
        DiffElementAddress.parse(NetlistDiffElementKind.port, 'in_a'),
        isNull,
      );
      expect(
        DiffElementAddress.parse(NetlistDiffElementKind.module, 'top'),
        isNull,
      );
    });
  });
}
