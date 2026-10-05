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
      expect(label.title, r'$xor  gray_counter.v:15  (Y)');
      expect(label.subtitle, 'top');
    });

    // Yosys escapes a space in a source path as `$20`. The
    // label read the `$` of `$20` as the end of the path, and showed
    // `$add$/Users/me/Getting$20Started$gray_counter.v:15$5_Y`.
    group(r'a source path with spaces ($20 escapes)', () {
      const dir = r'/Users/me/Desktop/Getting$20Started$20Videos/NetCrux';

      test('a generated net reads like a cell row', () {
        const change = ElementChange(
          kind: ElementChangeKind.removed,
          elementKind: NetlistDiffElementKind.net,
          elementId: ElementId(
            kind: ElementKind.net,
            path: 'gray_counter:net:\$add\$$dir/gray_counter.v:15\$5_Y',
          ),
        );
        final label = DiffRowLabel.of(change);
        expect(label.title, r'$add  gray_counter.v:15  (Y)');
        expect(label.subtitle, 'gray_counter');
        expect(
          label.tooltip,
          'gray_counter:net:\$add\$$dir/gray_counter.v:15\$5_Y',
          reason: 'the full name stays in the tooltip',
        );
      });

      test('a generated cell without src takes its location from the name', () {
        final label = DiffRowLabel.of(
          _cell(
            'gray_counter.\$xor\$$dir/gray_counter.v:15\$7:cell',
            type: r'$xor',
          ),
        );
        expect(label.title, r'$xor  gray_counter.v:15');
      });

      test('an escape in the file name itself is decoded', () {
        final label = DiffRowLabel.of(
          _cell('top.\$add\$$dir/my\$20counter.v:3\$1:cell'),
        );
        expect(label.title, r'$add  my counter.v:3');
      });

      test('shortSourceLocation decodes the path', () {
        expect(
          DiffRowLabel.shortSourceLocation(
            '\$xor\$$dir/gray_counter.v:15\$7',
          ),
          'gray_counter.v:15',
        );
        expect(
          DiffRowLabel.decodeEscapes(r'Getting$20Started$2Cnow'),
          'Getting Started,now',
        );
      });
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
