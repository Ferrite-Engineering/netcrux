// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_cxp/crux_cxp.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/models/fsm/fsm_detection_options.dart';
import 'package:netcrux/domain/models/fsm/fsm_encoding_hint.dart';

void main() {
  group('FsmDetectionOptions', () {
    test('defaults are sensible', () {
      const opts = FsmDetectionOptions.defaults;
      expect(opts.maxDepthHint, isNull);
      expect(opts.includeUnreachableStates, false);
      expect(opts.encodingHints, isEmpty);
    });

    test('equality reflects every field', () {
      const a = FsmDetectionOptions(maxDepthHint: 500);
      const b = FsmDetectionOptions(maxDepthHint: 500);
      const c = FsmDetectionOptions(maxDepthHint: 1000);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(c));
    });

    test('encoding hints equality is map-based', () {
      const reg1 = ElementId(kind: ElementKind.signal, path: 'top.reg1');
      final a = FsmDetectionOptions(
        encodingHints: <ElementId, FsmEncodingHint>{
          reg1: FsmEncodingHint.oneHot,
        },
      );
      final b = FsmDetectionOptions(
        encodingHints: <ElementId, FsmEncodingHint>{
          reg1: FsmEncodingHint.oneHot,
        },
      );
      final c = FsmDetectionOptions(
        encodingHints: <ElementId, FsmEncodingHint>{
          reg1: FsmEncodingHint.binary,
        },
      );
      expect(a, b);
      expect(a, isNot(c));
    });

    test('copyWith clearMaxDepthHint resets the bound', () {
      const opts = FsmDetectionOptions(maxDepthHint: 500);
      expect(opts.copyWith(clearMaxDepthHint: true).maxDepthHint, isNull);
      expect(opts.copyWith(maxDepthHint: 2000).maxDepthHint, 2000);
    });
  });
}
