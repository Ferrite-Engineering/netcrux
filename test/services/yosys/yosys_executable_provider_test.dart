// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/enums/yosys_path_mode.dart';
import 'package:netcrux/domain/models/app_settings.dart';
import 'package:netcrux/features/settings/providers/app_settings_provider.dart';
import 'package:netcrux/services/engines/bundled_binary_resolver.dart';
import 'package:netcrux/services/yosys/yosys_executable_provider.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('effectiveYosysExecutableProvider', () {
    late ProviderContainer container;

    ProviderContainer makeContainer({
      AppSettings? initial,
      String? cliOverride,
      BundledBinaryResolver? resolver,
    }) {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      return ProviderContainer(
        overrides: <Override>[
          if (cliOverride != null)
            cliYosysPathOverrideProvider.overrideWithValue(cliOverride),
          if (resolver != null)
            bundledBinaryResolverProvider.overrideWithValue(resolver),
          appSettingsProvider.overrideWith(_FakeAppSettings.new),
        ],
      );
    }

    tearDown(() {
      container.dispose();
    });

    test('returns null for autoDetect with no CLI override', () async {
      container = makeContainer();
      // Force the AppSettings stream to be in the data state.
      await container.read(appSettingsProvider.future);
      expect(container.read(effectiveYosysExecutableProvider), isNull);
    });

    test('CLI override wins over settings', () async {
      container = makeContainer(cliOverride: '/tmp/yosys-cli');
      await container.read(appSettingsProvider.future);
      // Even if settings later default to custom, the CLI override
      // wins. We don't set a custom path here; the CLI override is
      // present and non-empty so the provider returns it.
      expect(
        container.read(effectiveYosysExecutableProvider),
        '/tmp/yosys-cli',
      );
    });

    test('empty CLI override is treated as no override', () async {
      container = makeContainer(cliOverride: '');
      await container.read(appSettingsProvider.future);
      expect(container.read(effectiveYosysExecutableProvider), isNull);
    });

    test('custom mode with non-empty path returns it', () async {
      container = makeContainer();
      await container.read(appSettingsProvider.future);
      final notifier = container.read(appSettingsProvider.notifier);
      await notifier.setYosysPathMode(YosysPathMode.custom);
      await notifier.setYosysCustomPath('/opt/yosys/bin/yosys');
      expect(
        container.read(effectiveYosysExecutableProvider),
        '/opt/yosys/bin/yosys',
      );
    });

    test('custom mode with empty path returns null (fall through)', () async {
      container = makeContainer();
      await container.read(appSettingsProvider.future);
      await container
          .read(appSettingsProvider.notifier)
          .setYosysPathMode(YosysPathMode.custom);
      expect(container.read(effectiveYosysExecutableProvider), isNull);
    });

    test(
      'bundled mode falls through to null when resolver returns null',
      () async {
        container = makeContainer(
          // overrideRoot points to a directory that does not exist
          // → resolver returns null, the bundled-mode path falls
          // through to PATH lookup (the documented behavior).
          resolver: const BundledBinaryResolver(
            overrideRoot: '/does/not/exist/netcrux-bundled-test',
          ),
        );
        await container.read(appSettingsProvider.future);
        await container
            .read(appSettingsProvider.notifier)
            .setYosysPathMode(YosysPathMode.bundled);
        expect(container.read(effectiveYosysExecutableProvider), isNull);
      },
    );

    test('bundled mode returns resolver path when binary is present', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'netcrux_exec_bundled_',
      );
      try {
        final platformDir = _currentPlatformDir();
        final binDir = Directory(p.join(tempDir.path, platformDir));
        await binDir.create(recursive: true);
        final yosys = File(p.join(binDir.path, _exeName('yosys')));
        await yosys.writeAsString('#!/bin/sh\n');
        container = makeContainer(
          resolver: BundledBinaryResolver(overrideRoot: tempDir.path),
        );
        await container.read(appSettingsProvider.future);
        await container
            .read(appSettingsProvider.notifier)
            .setYosysPathMode(YosysPathMode.bundled);
        expect(
          container.read(effectiveYosysExecutableProvider),
          yosys.path,
        );
      } finally {
        if (tempDir.existsSync()) await tempDir.delete(recursive: true);
      }
    });
  });

  group('effectiveGhdlExecutableProvider', () {
    late ProviderContainer container;

    tearDown(() => container.dispose());

    test('returns null when not in bundled mode', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      container = ProviderContainer(
        overrides: <Override>[
          appSettingsProvider.overrideWith(_FakeAppSettings.new),
        ],
      );
      await container.read(appSettingsProvider.future);
      // Default mode is autoDetect — no ghdl path is offered; the OS PATH
      // lookup resolves `ghdl` for the standalone --synth step.
      expect(container.read(effectiveGhdlExecutableProvider), isNull);
    });

    test(
      'returns resolver path when bundled mode and binary present',
      () async {
        SharedPreferences.setMockInitialValues(<String, Object>{});
        final tempDir = await Directory.systemTemp.createTemp(
          'netcrux_ghdl_bundled_',
        );
        try {
          final platformDir = _currentPlatformDir();
          final binDir = Directory(p.join(tempDir.path, platformDir));
          await binDir.create(recursive: true);
          final ghdl = File(p.join(binDir.path, _exeName('ghdl')));
          await ghdl.writeAsString('#!/bin/sh\n');
          container = ProviderContainer(
            overrides: <Override>[
              bundledBinaryResolverProvider.overrideWithValue(
                BundledBinaryResolver(overrideRoot: tempDir.path),
              ),
              appSettingsProvider.overrideWith(_FakeAppSettings.new),
            ],
          );
          await container.read(appSettingsProvider.future);
          await container
              .read(appSettingsProvider.notifier)
              .setYosysPathMode(YosysPathMode.bundled);
          expect(
            container.read(effectiveGhdlExecutableProvider),
            ghdl.path,
          );
        } finally {
          if (tempDir.existsSync()) await tempDir.delete(recursive: true);
        }
      },
    );
  });
}

String _currentPlatformDir() {
  if (Platform.isLinux) return 'linux-x86_64';
  if (Platform.isMacOS) return 'macos-universal';
  if (Platform.isWindows) return 'windows-x86_64';
  throw StateError('Unsupported test host');
}

String _exeName(String engineId) =>
    Platform.isWindows ? '$engineId.exe' : engineId;

/// In-memory `AppSettingsNotifier` for tests. Backs onto a fresh
/// `SettingsService` with the same codec as production, but the
/// `SharedPreferences` is the mock seeded in `setUp`.
class _FakeAppSettings extends AppSettingsNotifier {
  @override
  Future<AppSettings> build() async {
    final service = ref.watch(settingsServiceProvider);
    return service.load();
  }
}
