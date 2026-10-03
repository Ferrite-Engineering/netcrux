// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/models/netlist/bit_ref.dart';
import 'package:netcrux/domain/models/netlist/module.dart';
import 'package:netcrux/domain/models/netlist/net.dart';
import 'package:netcrux/domain/models/schematic/pin_tie.dart';
import 'package:netcrux/features/inspector/services/pin_tie_text.dart';
import 'package:netcrux/l10n/generated/app_localizations.dart';

const _module = Module(
  name: 'm',
  attributes: <String, String>{},
  ports: {},
  cells: {},
  nets: <String, Net>{
    'add_cy_r': Net(
      name: 'add_cy_r',
      bits: <BitRef>[NetBit(576)],
      attributes: <String, String>{},
    ),
  },
);

void main() {
  late L10N l10n;

  setUpAll(() async {
    l10n = await L10N.delegate.load(const Locale('en'));
  });

  test('names the net a pin is on', () {
    expect(
      pinTieText(l10n, PinTie.net, const <BitRef>[NetBit(576)], _module),
      'add_cy_r',
    );
  });

  test('falls back to the net id for an unnamed net', () {
    expect(
      pinTieText(l10n, PinTie.net, const <BitRef>[NetBit(9)], _module),
      'Net 9',
    );
  });

  test('lists a bus most-significant first, each name once', () {
    expect(
      pinTieText(
        l10n,
        PinTie.net,
        const <BitRef>[
          NetBit(576),
          ConstantBit(ConstantBitValue.x),
          ConstantBit(ConstantBitValue.x),
          NetBit(9),
        ],
        _module,
      ),
      'Net 9, x, add_cy_r',
    );
  });

  test('says what a constant, an x, an undriven and an open pin are', () {
    expect(
      pinTieText(l10n, const PinTie.constant('0'), const <BitRef>[], null),
      'Constant 0',
    );
    expect(
      pinTieText(l10n, const PinTie.constant('x'), const <BitRef>[], null),
      'x (unknown value)',
    );
    expect(
      pinTieText(l10n, PinTie.undriven, const <BitRef>[NetBit(7)], null),
      'Undriven (no driver in this scope)',
    );
    expect(
      pinTieText(l10n, PinTie.unconnected, const <BitRef>[], null),
      'Unconnected',
    );
  });

  test('every locale has the words', () async {
    for (final locale in L10N.supportedLocales) {
      final other = await L10N.delegate.load(locale);
      expect(
        pinTieText(other, PinTie.undriven, const <BitRef>[], null),
        isNotEmpty,
        reason: '$locale',
      );
    }
  });
}
