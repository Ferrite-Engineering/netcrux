// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/services/yosys/isolate_netlist_parser.dart';
import 'package:netcrux/services/yosys/yosys_json_parser.dart';

void main() {
  group('parseNetlistOnIsolate', () {
    const validDoc = '''
{
  "creator": "Yosys 0.40 (test)",
  "modules": {
    "and2": {
      "ports": {},
      "cells": {},
      "netnames": {}
    },
    "top": {
      "attributes": { "top": "1" },
      "ports": {},
      "cells": {},
      "netnames": {}
    }
  }
}
''';

    test(
      'parses a valid document on a worker isolate (send-safe round-trip)',
      () async {
        final model = await parseNetlistOnIsolate(validDoc);
        // The model came back across the isolate boundary intact — proving it
        // is send-safe pure-Dart data.
        expect(model, isNotNull);
        expect(model!.creator, 'Yosys 0.40 (test)');
        expect(model.modules.keys, containsAll(<String>['and2', 'top']));
      },
    );

    test('throws YosysJsonParseException on malformed input', () async {
      const malformed = '{"modules": { "a": { not valid json } }';
      await expectLater(
        parseNetlistOnIsolate(malformed),
        throwsA(isA<YosysJsonParseException>()),
      );
    });

    test(
      'a never-firing cancelSignal does not disturb the happy path',
      () async {
        final cancel = Completer<void>();
        addTearDown(() {
          if (!cancel.isCompleted) cancel.complete();
        });
        final model = await parseNetlistOnIsolate(
          validDoc,
          cancelSignal: cancel.future,
        );
        expect(model, isNotNull);
        expect(model!.modules.keys, containsAll(<String>['and2', 'top']));
      },
    );

    test('a cancelSignal fired before the parse yields null', () async {
      // Pre-completed cancel: the kill wins the race against the (tiny)
      // parse, so the result is the dropped-elaboration empty state.
      final model = await parseNetlistOnIsolate(
        validDoc,
        cancelSignal: Future<void>.value(),
      );
      expect(model, isNull);
    });
  });

  group('parseNetlistWithBlackBoxesOnIsolate', () {
    const doc = '''
{"creator":"test","modules":{"top":{"attributes":{"top":"1"},
"ports":{"a":{"direction":"input","bits":[2]},
"y":{"direction":"output","bits":[3]}},
"cells":{"u1":{"hide_name":0,"type":"INV","parameters":{},"attributes":{},
"connections":{"A":[2],"Y":[3]}}},"netnames":{}}}}
''';

    test('infers black-box pins on the worker and reports them', () async {
      final parsed = await parseNetlistWithBlackBoxesOnIsolate(doc);
      expect(parsed, isNotNull);
      expect(
        parsed!.model.modules['top']!.cells['u1']!.portDirections.keys,
        <String>['A', 'Y'],
      );
      expect(parsed.report.types, <String>['INV']);
      expect(parsed.report.pinCount, 2);
    });

    test('the plain parse leaves the pins alone', () async {
      final model = await parseNetlistOnIsolate(doc);
      expect(model!.modules['top']!.cells['u1']!.portDirections, isEmpty);
    });

    test('malformed input still throws the parse exception', () {
      expect(
        parseNetlistWithBlackBoxesOnIsolate('{"modules": 3}'),
        throwsA(isA<YosysJsonParseException>()),
      );
    });
  });
}
