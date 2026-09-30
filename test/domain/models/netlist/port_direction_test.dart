// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/models/netlist/port_direction.dart';

void main() {
  group('PortDirection', () {
    test('fromJson parses the three canonical strings', () {
      expect(PortDirection.fromJson('input'), PortDirection.input);
      expect(PortDirection.fromJson('output'), PortDirection.output);
      expect(PortDirection.fromJson('inout'), PortDirection.inout);
    });

    test('fromJson is case-insensitive', () {
      expect(PortDirection.fromJson('INPUT'), PortDirection.input);
      expect(PortDirection.fromJson('Output'), PortDirection.output);
    });

    test('fromJson falls back to inout on unrecognised strings', () {
      expect(PortDirection.fromJson('weird'), PortDirection.inout);
      expect(PortDirection.fromJson(''), PortDirection.inout);
    });

    test('toJsonString round-trips through fromJson', () {
      for (final direction in PortDirection.values) {
        expect(PortDirection.fromJson(direction.toJsonString()), direction);
      }
    });
  });
}
