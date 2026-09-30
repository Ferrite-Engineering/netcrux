// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/models/netlist/netlist_model.dart';
import 'package:netcrux/services/collaboration/netlist_fingerprint.dart';

Module _module(String name, {int cells = 0, bool top = false}) => Module(
  name: name,
  attributes: top
      ? const {'top': '00000000000000000000000000000001'}
      : const {},
  ports: const {},
  cells: {
    for (var i = 0; i < cells; i++)
      'u$i': Cell(
        name: 'u$i',
        type: 'AND',
        parameters: const {},
        attributes: const {},
        portDirections: const {},
        connections: const {},
      ),
  },
  nets: const {},
);

void main() {
  test('the same design fingerprints the same', () {
    final a = NetlistModel(
      creator: 'yosys 0.40',
      modules: {
        'top': _module('top', cells: 3, top: true),
      },
    );
    final b = NetlistModel(
      creator: 'yosys 0.40',
      modules: {
        'top': _module('top', cells: 3, top: true),
      },
    );
    expect(netlistFingerprint(a), netlistFingerprint(b));
  });

  test('a Yosys upgrade does not look like a different design', () {
    final before = NetlistModel(
      creator: 'yosys 0.40',
      modules: {
        'top': _module('top', cells: 3, top: true),
      },
    );
    final after = NetlistModel(
      creator: 'yosys 0.55 (git sha1 abcdef)',
      modules: {
        'top': _module('top', cells: 3, top: true),
      },
    );
    expect(
      netlistFingerprint(before),
      netlistFingerprint(after),
      reason:
          'a digest that fired every time somebody upgraded their toolchain '
          'would be ignored inside a week',
    );
  });

  test('module order does not change the answer', () {
    final a = NetlistModel(
      creator: 't',
      modules: {
        'top': _module('top', cells: 1, top: true),
        'alu': _module('alu', cells: 2),
      },
    );
    final b = NetlistModel(
      creator: 't',
      modules: {
        'alu': _module('alu', cells: 2),
        'top': _module('top', cells: 1, top: true),
      },
    );
    expect(netlistFingerprint(a), netlistFingerprint(b));
  });

  test('a structural difference is visible', () {
    final a = NetlistModel(
      creator: 't',
      modules: {
        'top': _module('top', cells: 3, top: true),
      },
    );
    final b = NetlistModel(
      creator: 't',
      modules: {
        'top': _module('top', cells: 4, top: true),
      },
    );
    expect(netlistFingerprint(a), isNot(netlistFingerprint(b)));
  });

  test('the digest reveals nothing about the design', () {
    final model = NetlistModel(
      creator: 't',
      modules: {
        'secret_ip_block': _module('secret_ip_block', cells: 2, top: true),
      },
    );
    final digest = netlistFingerprint(model);
    expect(digest, hasLength(64));
    expect(
      digest.contains('secret'),
      isFalse,
      reason: 'only the digest crosses the wire; a module name is design IP',
    );
  });
}
