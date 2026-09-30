// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/core/app_info/about_providers.dart';
import 'package:netcrux/domain/models/app_settings.dart';
import 'package:netcrux/features/remote/providers/cxp_server_provider.dart';
import 'package:netcrux/features/settings/providers/app_settings_provider.dart';
import 'package:package_info_plus/package_info_plus.dart';

class _EnabledSettings extends AppSettingsNotifier {
  @override
  Future<AppSettings> build() async =>
      const AppSettings.defaults().copyWith(cxpServerEnabled: true);
}

void main() {
  group('the version a peer sees', () {
    tearDown(
      () => PackageInfo.setMockInitialValues(
        appName: '',
        packageName: '',
        version: '',
        buildNumber: '',
        buildSignature: '',
      ),
    );

    test("is the running build's version", () async {
      PackageInfo.setMockInitialValues(
        appName: 'netcrux',
        packageName: 'com.ferriteengineering.netcrux',
        version: '9.9.9',
        buildNumber: '42',
        buildSignature: '',
      );
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(
        await container.read(netcruxProductVersionProvider.future),
        '9.9.9',
      );
    });

    test('is "dev" when the platform cannot report one', () async {
      final container = ProviderContainer(
        overrides: [
          aboutBuildInfoProvider.overrideWith(
            (ref) async => throw StateError('no platform channel'),
          ),
        ],
      );
      addTearDown(container.dispose);
      expect(
        await container.read(netcruxProductVersionProvider.future),
        'dev',
      );
    });
  });

  test('the VM build has a CXP transport', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(container.read(cxpTransportAvailableProvider), isTrue);
  });

  test(
    'without a transport no server starts and discovery is never resolved',
    () async {
      var manifestDirectoryRead = false;
      final container = ProviderContainer(
        overrides: [
          cxpTransportAvailableProvider.overrideWithValue(false),
          // Enabled in settings, so only the transport gate stands between
          // the host and a real server.
          appSettingsProvider.overrideWith(_EnabledSettings.new),
          cxpManifestDirectoryProvider.overrideWith((ref) async {
            manifestDirectoryRead = true;
            throw UnsupportedError('no host platform in a browser');
          }),
        ],
      );
      addTearDown(container.dispose);
      expect(await container.read(cxpServerHostProvider.future), isNull);
      expect(manifestDirectoryRead, isFalse);
    },
  );
}
