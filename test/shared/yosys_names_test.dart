// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/shared/yosys_names.dart';

void main() {
  group('YosysNames.displayName', () {
    test('a generated cell reads as type and file:line', () {
      expect(
        YosysNames.displayName(
          r'$mul$/Users/me/Getting$20Started/dsp_mac.v:25$1',
        ),
        r'$mul  dsp_mac.v:25',
      );
    });

    test('a net named after a cell pin adds the pin', () {
      expect(
        YosysNames.displayName(r'$add$/src/rtl/gray_counter.v:15$5_Y'),
        r'$add  gray_counter.v:15  (Y)',
      );
    });

    test('other generated shapes keep their form, paths cut', () {
      expect(YosysNames.displayName(r'$procmux$17_Y'), r'$procmux$17_Y');
      expect(YosysNames.displayName(r'$0\acc[35:0]'), r'$0\acc[35:0]');
    });

    test('a user-written name is unchanged', () {
      expect(YosysNames.displayName('acc'), 'acc');
      expect(YosysNames.displayName('top.u_alu'), 'top.u_alu');
    });

    test('an escape in the file name itself is decoded', () {
      expect(
        YosysNames.displayName(r'$add$/a/my$20file.v:3$1'),
        r'$add  my file.v:3',
      );
    });
  });
}
