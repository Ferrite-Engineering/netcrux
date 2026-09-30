// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/services/file_open/file_open_service.dart';

void main() {
  group('FileOpenResult', () {
    test('a result with paths is not cancelled and exposes them in order', () {
      const result = FileOpenResult(<String>['/a.v', '/b.sv']);
      expect(result.isCancelled, isFalse);
      expect(result.paths, <String>['/a.v', '/b.sv']);
    });

    test('the cancelled factory is empty and reports cancellation', () {
      const result = FileOpenResult.cancelled();
      expect(result.isCancelled, isTrue);
      expect(result.paths, isEmpty);
    });

    test('an empty path list collapses to the cancelled state', () {
      // "picked nothing" and "cancelled" are the same observable state.
      const result = FileOpenResult(<String>[]);
      expect(result.isCancelled, isTrue);
      expect(result.paths, isEmpty);
    });

    test('a single-path result is not cancelled', () {
      const result = FileOpenResult(<String>['/only.v']);
      expect(result.isCancelled, isFalse);
      expect(result.paths.single, '/only.v');
    });
  });
}
