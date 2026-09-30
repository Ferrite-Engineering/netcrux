// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/core/web/web_launch_params.dart';

void main() {
  group('WebLaunchParams.parse', () {
    test('empty inputs produce empty', () {
      final params = WebLaunchParams.parse();
      expect(params, WebLaunchParams.empty);
      expect(params.isEmpty, isTrue);
    });

    test('extracts the json query parameter', () {
      final params = WebLaunchParams.parse(
        queryString: 'json=https%3A%2F%2Fexample.com%2Ftop.json',
      );
      expect(params.jsonUrl, 'https://example.com/top.json');
      expect(params.autoScope, isNull);
      expect(params.autoSignal, isNull);
    });

    test('extracts the scope fragment field', () {
      final params = WebLaunchParams.parse(fragment: 'scope=top.cpu.alu');
      expect(params.autoScope, 'top.cpu.alu');
      expect(params.autoSignal, isNull);
      expect(params.jsonUrl, isNull);
    });

    test('extracts the sig fragment field', () {
      final params = WebLaunchParams.parse(fragment: 'sig=u_alu.result');
      expect(params.autoSignal, 'u_alu.result');
    });

    test('handles combined fragment fields', () {
      final params = WebLaunchParams.parse(
        fragment: 'scope=top.cpu&sig=u_alu.result',
      );
      expect(params.autoScope, 'top.cpu');
      expect(params.autoSignal, 'u_alu.result');
    });

    test('json + scope + sig combine', () {
      final params = WebLaunchParams.parse(
        queryString: 'json=https%3A%2F%2Fhost%2Ftop.json',
        fragment: 'scope=top.alu&sig=result',
      );
      expect(params.jsonUrl, 'https://host/top.json');
      expect(params.autoScope, 'top.alu');
      expect(params.autoSignal, 'result');
    });

    test('unknown keys are silently dropped', () {
      final params = WebLaunchParams.parse(
        queryString: 'tracking=abc&json=https%3A%2F%2Fhost%2Fa.json',
        fragment: 'theme=dark&scope=top',
      );
      expect(params.jsonUrl, 'https://host/a.json');
      expect(params.autoScope, 'top');
    });

    test('empty values for present keys are treated as null', () {
      final params = WebLaunchParams.parse(
        queryString: 'json=',
        fragment: 'scope=&sig=',
      );
      expect(params.jsonUrl, isNull);
      expect(params.autoScope, isNull);
      expect(params.autoSignal, isNull);
      expect(params.isEmpty, isTrue);
    });

    test('equality is value-based', () {
      final a = WebLaunchParams.parse(
        queryString: 'json=https%3A%2F%2Fa',
        fragment: 'scope=top',
      );
      final b = WebLaunchParams.parse(
        queryString: 'json=https%3A%2F%2Fa',
        fragment: 'scope=top',
      );
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });
  });
}
