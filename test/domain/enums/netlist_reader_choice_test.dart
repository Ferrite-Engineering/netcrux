// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/enums/netlist_reader_choice.dart';

void main() {
  group('NetlistReaderChoice.parse', () {
    test('reads the three names, ignoring case and white space', () {
      expect(NetlistReaderChoice.parse('native'), NetlistReaderChoice.native);
      expect(NetlistReaderChoice.parse(' YOSYS '), NetlistReaderChoice.yosys);
      expect(NetlistReaderChoice.parse('Auto'), NetlistReaderChoice.auto);
    });

    test('anything else is null', () {
      expect(NetlistReaderChoice.parse(null), isNull);
      expect(NetlistReaderChoice.parse(''), isNull);
      expect(NetlistReaderChoice.parse('verilator'), isNull);
    });
  });

  group('NetlistReaderChoice.resolve', () {
    NetlistReaderDecision decide({
      NetlistReaderChoice? cli,
      NetlistReaderChoice project = NetlistReaderChoice.auto,
      bool setting = true,
    }) => NetlistReaderChoice.resolve(
      cli: cli,
      project: project,
      settingEnabled: setting,
    );

    test('with nothing said above it, the setting decides', () {
      final on = decide();
      expect(on.native, isTrue);
      expect(on.source, NetlistReaderSource.setting);
      final off = decide(setting: false);
      expect(off.native, isFalse);
      expect(off.source, NetlistReaderSource.setting);
    });

    test('the project overrides the setting both ways', () {
      final off = decide(project: NetlistReaderChoice.yosys);
      expect(off.native, isFalse);
      expect(off.source, NetlistReaderSource.project);
      final on = decide(project: NetlistReaderChoice.native, setting: false);
      expect(on.native, isTrue);
      expect(on.source, NetlistReaderSource.project);
    });

    test('the command line overrides the project and the setting', () {
      final off = decide(
        cli: NetlistReaderChoice.yosys,
        project: NetlistReaderChoice.native,
      );
      expect(off.native, isFalse);
      expect(off.source, NetlistReaderSource.commandLine);
      final on = decide(
        cli: NetlistReaderChoice.native,
        project: NetlistReaderChoice.yosys,
        setting: false,
      );
      expect(on.native, isTrue);
      expect(on.source, NetlistReaderSource.commandLine);
    });

    test('auto on the command line defers to the next level', () {
      final d = decide(
        cli: NetlistReaderChoice.auto,
        project: NetlistReaderChoice.yosys,
      );
      expect(d.native, isFalse);
      expect(d.source, NetlistReaderSource.project);
    });
  });
}
