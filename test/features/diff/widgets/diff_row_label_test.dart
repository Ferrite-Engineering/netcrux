// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_cxp/crux_cxp.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/models/diff/element_change.dart';
import 'package:netcrux/domain/models/diff/netlist_diff_element_kind.dart';
import 'package:netcrux/features/diff/widgets/diff_row_label.dart';

ElementChange _cell(
  String path, {
  String type = r'$add',
  String? src,
  String? comparisonName,
}) => ElementChange(
  kind: ElementChangeKind.unchanged,
  elementKind: NetlistDiffElementKind.instance,
  elementId: ElementId(kind: ElementKind.instance, path: path),
  baselineSnapshot: <String, String>{'type': type},
  comparisonSnapshot: <String, String>{'type': type},
  sourceLocation: src,
  comparisonName: comparisonName,
);

void main() {
  group('DiffRowLabel.of', () {
    test('a user-named cell shows its name over its path', () {
      final label = DiffRowLabel.of(_cell('top.u_alu:cell', type: 'alu'));
      expect(label.title, 'u_alu');
      expect(label.subtitle, 'top.u_alu:cell');
    });

    test('a generated cell shows its type and file:line from src', () {
      final label = DiffRowLabel.of(
        _cell(
          r'top.$add$/home/me/rtl/gray_counter.v:14$3:cell',
          src: '/home/me/rtl/gray_counter.v:14.21-14.31',
          comparisonName: r'$add$/home/me/rtl/gray_counter_regressed.v:17$3',
        ),
      );
      expect(label.title, r'$add  gray_counter.v:14');
      expect(label.subtitle, 'top');
      expect(
        label.tooltip,
        r'top.$add$/home/me/rtl/gray_counter.v:14$3:cell'
        '\n'
        r'= $add$/home/me/rtl/gray_counter_regressed.v:17$3'
        '\n'
        '/home/me/rtl/gray_counter.v:14.21-14.31',
      );
    });

    test('without src the location comes from the name', () {
      final label = DiffRowLabel.of(
        _cell(r'top.$add$/home/me/My Designs/counter.v:9$1:cell'),
      );
      expect(label.title, r'$add  counter.v:9');
    });

    test("a location in Yosys's own sources is not a design location", () {
      final label = DiffRowLabel.of(
        _cell(r'top.$auto$proc_dff.cc:220:proc_dff$13:cell', type: r'$not'),
      );
      expect(label.title, r'$not');
    });

    test('a generated net shows its name with the path cut to the file', () {
      const change = ElementChange(
        kind: ElementChangeKind.removed,
        elementKind: NetlistDiffElementKind.net,
        elementId: ElementId(
          kind: ElementKind.net,
          path: r'top:net:$xor$/home/me/rtl/gray_counter.v:15$7_Y',
        ),
        baselineSnapshot: <String, String>{'width': '8'},
        sourceLocation: '/home/me/rtl/gray_counter.v:15.21-15.55',
      );
      final label = DiffRowLabel.of(change);
      expect(label.title, r'$xor$gray_counter.v:15$7_Y');
      expect(label.subtitle, 'top');
    });

    test('a generated net without a location in its name gets one', () {
      const change = ElementChange(
        kind: ElementChangeKind.unchanged,
        elementKind: NetlistDiffElementKind.net,
        elementId: ElementId(
          kind: ElementKind.net,
          path: r'top:net:$0\gray[7:0]',
        ),
        sourceLocation: '/home/me/rtl/gray_counter.v:9.5-17.8',
      );
      expect(DiffRowLabel.of(change).title, r'$0\gray[7:0]  gray_counter.v:9');
    });
  });
}
