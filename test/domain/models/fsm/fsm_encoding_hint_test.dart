// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/models/fsm/fsm_encoding_hint.dart';

void main() {
  group('FsmEncodingHint', () {
    test('declares five values in stable order', () {
      expect(FsmEncodingHint.values, hasLength(5));
      expect(FsmEncodingHint.values, <FsmEncodingHint>[
        FsmEncodingHint.oneHot,
        FsmEncodingHint.binary,
        FsmEncodingHint.gray,
        FsmEncodingHint.johnson,
        FsmEncodingHint.unknown,
      ]);
    });

    test('exposes stable enum names for serialization round-trip', () {
      expect(FsmEncodingHint.oneHot.name, 'oneHot');
      expect(FsmEncodingHint.binary.name, 'binary');
      expect(FsmEncodingHint.gray.name, 'gray');
      expect(FsmEncodingHint.johnson.name, 'johnson');
      expect(FsmEncodingHint.unknown.name, 'unknown');
    });
  });
}
