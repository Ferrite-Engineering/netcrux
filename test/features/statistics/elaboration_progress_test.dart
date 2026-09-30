// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/features/statistics/providers/elaboration_progress_provider.dart';

void main() {
  group('parseYosysPassName', () {
    test('reads a top-level pass banner', () {
      expect(
        parseYosysPassName('4. Executing PROC pass (convert processes).'),
        'PROC',
      );
    });

    test('reads a nested pass banner', () {
      expect(
        parseYosysPassName(
          '2.1. Executing HIERARCHY pass (managing design hierarchy).',
        ),
        'HIERARCHY',
      );
    });

    test('reads a deeply nested banner', () {
      expect(
        parseYosysPassName('2.3.1. Executing OPT_EXPR pass (const fold).'),
        'OPT_EXPR',
      );
    });

    test('tolerates surrounding whitespace', () {
      expect(
        parseYosysPassName('   3. Executing FLATTEN pass.   '),
        'FLATTEN',
      );
    });

    test('ignores an Executing line with no section number', () {
      // Yosys prints these for frontends. Matching them would make the
      // readout jump between real passes and incidental mentions.
      expect(
        parseYosysPassName('Executing Verilog-2005 frontend: top.v'),
        isNull,
      );
    });

    test('ignores ordinary warnings and chatter', () {
      for (final line in <String>[
        r'Warning: Wire top.\unused is unused.',
        '',
        'Removed 3 unused cells and 7 unused wires.',
        '-- Running command `hierarchy -check` --',
      ]) {
        expect(parseYosysPassName(line), isNull, reason: line);
      }
    });
  });

  group('ElaborationProgressNotifier', () {
    late ProviderContainer container;

    setUp(() => container = ProviderContainer());
    tearDown(() => container.dispose());

    ElaborationProgressNotifier notifier() =>
        container.read(elaborationProgressProvider.notifier);
    String? pass() => container.read(elaborationProgressProvider);

    test('starts with no pass', () {
      expect(pass(), isNull);
    });

    test('advances as banners arrive', () {
      notifier()
        ..consumeStderrLine('1. Executing VERILOG frontend.')
        ..consumeStderrLine('2. Executing HIERARCHY pass.');
      expect(pass(), 'HIERARCHY');
    });

    test('a non-banner line does not blank the readout', () {
      notifier()
        ..consumeStderrLine('2. Executing HIERARCHY pass.')
        ..consumeStderrLine('Warning: something unrelated');
      expect(
        pass(),
        'HIERARCHY',
        reason:
            'the warnings Yosys prints between passes are not a reason '
            'to blank the current phase',
      );
    });

    test('clear resets it when the run ends', () {
      notifier()
        ..consumeStderrLine('2. Executing HIERARCHY pass.')
        ..clear();
      expect(pass(), isNull);
    });
  });
}
