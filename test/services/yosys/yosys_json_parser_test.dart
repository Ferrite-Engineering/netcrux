// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/services/yosys/yosys_json_parser.dart';

const _validYosysJson = r'''
{
  "creator": "Yosys 0.50",
  "modules": {
    "and2": {
      "attributes": {"top": "1"},
      "ports": {
        "a": {"direction": "input", "bits": [2]},
        "b": {"direction": "input", "bits": [3]},
        "y": {"direction": "output", "bits": [4]}
      },
      "cells": {
        "u_and": {
          "hide_name": 0,
          "type": "$and",
          "parameters": {"A_WIDTH": "1", "B_WIDTH": "1", "Y_WIDTH": "1"},
          "attributes": {},
          "port_directions": {"A": "input", "B": "input", "Y": "output"},
          "connections": {"A": [2], "B": [3], "Y": [4]}
        }
      },
      "netnames": {
        "a": {"hide_name": 0, "bits": [2], "attributes": {}},
        "b": {"hide_name": 0, "bits": [3], "attributes": {}},
        "y": {"hide_name": 0, "bits": [4], "attributes": {}}
      }
    }
  }
}
''';

void main() {
  group('YosysJsonParser', () {
    const parser = YosysJsonParser();

    test('parses a typical Yosys document', () {
      final model = parser.parse(_validYosysJson);
      expect(model.creator, 'Yosys 0.50');
      expect(model.modules.keys, contains('and2'));
      expect(model.topModule, isNotNull);
      expect(model.topModule!.name, 'and2');
      expect(model.modules['and2']!.cells['u_and']!.type, r'$and');
    });

    test('throws on malformed JSON syntax', () {
      expect(
        () => parser.parse('not json at all'),
        throwsA(
          isA<YosysJsonParseException>().having(
            (e) => e.message,
            'message',
            contains('not valid JSON'),
          ),
        ),
      );
    });

    test('throws when the root is not an object', () {
      expect(
        () => parser.parse('[1, 2, 3]'),
        throwsA(
          isA<YosysJsonParseException>().having(
            (e) => e.message,
            'message',
            contains('not a JSON object'),
          ),
        ),
      );
    });

    test('throws when the document is missing `modules`', () {
      expect(
        () => parser.parse('{"creator": "Yosys"}'),
        throwsA(
          isA<YosysJsonParseException>().having(
            (e) => e.message,
            'message',
            contains('modules'),
          ),
        ),
      );
    });

    test('throws on unexpected types inside the document', () {
      const malformed = '{"creator": "Yosys", "modules": "not an object"}';
      expect(
        () => parser.parse(malformed),
        throwsA(isA<YosysJsonParseException>()),
      );
    });

    test('toString includes the message and (when present) the cause', () {
      const e1 = YosysJsonParseException('something broke');
      expect(e1.toString(), contains('something broke'));
      const e2 = YosysJsonParseException('with cause', cause: 'inner');
      expect(e2.toString(), allOf(contains('with cause'), contains('inner')));
    });
  });
}
