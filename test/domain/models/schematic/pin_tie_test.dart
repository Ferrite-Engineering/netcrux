// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/models/netlist/port_direction.dart';
import 'package:netcrux/domain/models/schematic/pin_tie.dart';
import 'package:netcrux/domain/models/schematic/schematic_graph.dart';

void main() {
  group('PinTie', () {
    test('the named ties carry no constant', () {
      for (final tie in <PinTie>[
        PinTie.net,
        PinTie.undriven,
        PinTie.unconnected,
      ]) {
        expect(tie.constantText, isNull);
        expect(tie.isX, isFalse);
      }
      expect(PinTie.net.kind, PinTieKind.net);
      expect(PinTie.undriven.kind, PinTieKind.undriven);
      expect(PinTie.unconnected.kind, PinTieKind.unconnected);
    });

    test('a constant compares by value', () {
      expect(const PinTie.constant('0'), const PinTie.constant('0'));
      expect(
        const PinTie.constant('0').hashCode,
        const PinTie.constant('0').hashCode,
      );
      expect(const PinTie.constant('0'), isNot(const PinTie.constant('1')));
      expect(const PinTie.constant('0'), isNot(PinTie.net));
      expect(const PinTie.constant('0').kind, PinTieKind.constant);
    });

    test('isX is true only for an all-x constant', () {
      expect(const PinTie.constant('x').isX, isTrue);
      expect(const PinTie.constant('0x').isX, isFalse);
      expect(const PinTie.constant('0').isX, isFalse);
    });

    test('toString names the kind and the constant', () {
      expect(PinTie.undriven.toString(), 'PinTie(undriven)');
      expect(const PinTie.constant('1').toString(), 'PinTie(constant 1)');
    });
  });

  group('SchematicPort.tie', () {
    const base = SchematicPort(
      id: 'c:A',
      name: 'A',
      direction: PortDirection.input,
      side: SchematicPortSide.west,
    );

    test('defaults to net', () {
      expect(base.tie, PinTie.net);
    });

    test('takes part in equality', () {
      const tied = SchematicPort(
        id: 'c:A',
        name: 'A',
        direction: PortDirection.input,
        side: SchematicPortSide.west,
        tie: PinTie.undriven,
      );
      expect(tied, isNot(base));
      expect(
        tied,
        const SchematicPort(
          id: 'c:A',
          name: 'A',
          direction: PortDirection.input,
          side: SchematicPortSide.west,
          tie: PinTie.undriven,
        ),
      );
    });
  });
}
