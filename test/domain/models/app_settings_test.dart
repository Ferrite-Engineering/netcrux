// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_settings/crux_settings.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/enums/yosys_path_mode.dart';
import 'package:netcrux/domain/models/app_settings.dart';

void main() {
  group('AppSettings', () {
    test('defaults compose CoreSettings.defaults with empty recent lists', () {
      const settings = AppSettings.defaults();
      expect(settings.core, const CoreSettings.defaults());
      expect(settings.recentProjectPaths, isEmpty);
      expect(settings.recentSourceFilePaths, isEmpty);
      expect(settings.yosysPathMode, YosysPathMode.autoDetect);
      expect(settings.yosysCustomPath, '');
      // The update check is on out of the box — a user running a stale beta
      // build is exactly the failure mode it exists to prevent.
      expect(settings.autoCheckForUpdates, isTrue);
    });

    test('copyWith toggles the automatic update check', () {
      const settings = AppSettings.defaults();
      final off = settings.copyWith(autoCheckForUpdates: false);
      expect(off.autoCheckForUpdates, isFalse);
      expect(off.core, settings.core);
      expect(off.copyWith(autoCheckForUpdates: true), settings);
    });

    test('autoCheckForUpdates participates in equality and hashCode', () {
      const on = AppSettings.defaults();
      final off = on.copyWith(autoCheckForUpdates: false);
      expect(off, isNot(on));
      expect(off.hashCode, isNot(on.hashCode));
    });

    test('copyWith preserves unspecified fields', () {
      const settings = AppSettings.defaults();
      final updated = settings.copyWith(
        recentProjectPaths: const ['/tmp/demo.netcrux'],
      );
      expect(updated.recentProjectPaths, const ['/tmp/demo.netcrux']);
      expect(updated.recentSourceFilePaths, settings.recentSourceFilePaths);
      expect(updated.core, settings.core);
      expect(updated.yosysPathMode, settings.yosysPathMode);
    });

    test('copyWith updates yosys knobs', () {
      const settings = AppSettings.defaults();
      final updated = settings.copyWith(
        yosysPathMode: YosysPathMode.custom,
        yosysCustomPath: '/opt/yosys/bin/yosys',
      );
      expect(updated.yosysPathMode, YosysPathMode.custom);
      expect(updated.yosysCustomPath, '/opt/yosys/bin/yosys');
    });

    test('equality matches structurally', () {
      const a = AppSettings(
        core: CoreSettings.defaults(),
        recentProjectPaths: ['x'],
        recentSourceFilePaths: ['y'],
        recentWorkspacePaths: <String>[],
        yosysPathMode: YosysPathMode.autoDetect,
        yosysCustomPath: '',
      );
      const b = AppSettings(
        core: CoreSettings.defaults(),
        recentProjectPaths: ['x'],
        recentSourceFilePaths: ['y'],
        recentWorkspacePaths: <String>[],
        yosysPathMode: YosysPathMode.autoDetect,
        yosysCustomPath: '',
      );
      const c = AppSettings(
        core: CoreSettings.defaults(),
        recentProjectPaths: ['x'],
        recentSourceFilePaths: ['z'],
        recentWorkspacePaths: <String>[],
        yosysPathMode: YosysPathMode.autoDetect,
        yosysCustomPath: '',
      );
      expect(a, equals(b));
      expect(a, isNot(equals(c)));
      expect(a.hashCode, b.hashCode);
    });

    test('inequality on yosys fields', () {
      const a = AppSettings.defaults();
      final b = a.copyWith(yosysPathMode: YosysPathMode.custom);
      final cPath = a.copyWith(yosysCustomPath: '/x');
      expect(a, isNot(equals(b)));
      expect(a, isNot(equals(cPath)));
    });

    test('recentPathsLimit is the documented cap', () {
      // Suite-canonical cap (10 everywhere; NetCrux was the lone 12).
      expect(AppSettings.recentPathsLimit, 10);
    });
  });
}
