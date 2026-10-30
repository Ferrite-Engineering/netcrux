// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_settings/crux_settings.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/enums/elaboration_time_limit.dart';
import 'package:netcrux/domain/interfaces/elaboration_timeout_policy.dart';
import 'package:netcrux/domain/models/app_settings.dart';
import 'package:netcrux/features/project/providers/elaboration_timeout_policy_provider.dart';
import 'package:netcrux/features/settings/providers/app_settings_provider.dart';
import 'package:netcrux/services/settings/netcrux_settings_codec.dart';
import 'package:shared_preferences/shared_preferences.dart';

ElaborationSizeEstimate _bytes(int bytes) =>
    ElaborationSizeEstimate(sourceFileCount: 1, totalSourceBytes: bytes);

const int _mb = 1024 * 1024;

void main() {
  group('elaborationTimeoutPolicyProvider', () {
    Future<ProviderContainer> container({String? stored}) async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'netcrux.elaborationTimeLimit': ?stored,
      });
      final prefs = await SharedPreferences.getInstance();
      final c = ProviderContainer(
        overrides: [
          settingsServiceProvider.overrideWithValue(
            SettingsService<AppSettings>(
              const NetcruxSettingsCodec(),
              prefsOverride: prefs,
            ),
          ),
        ],
      );
      addTearDown(c.dispose);
      await c.read(appSettingsProvider.future);
      return c;
    }

    test('follows the saved choice', () async {
      final c = await container(stored: 'none');
      expect(c.read(elaborationTimeoutPolicyProvider).killOnTimeout, isFalse);
    });

    test('is the automatic budget by default', () async {
      final c = await container();
      final policy = c.read(elaborationTimeoutPolicyProvider);
      expect(policy.killOnTimeout, isTrue);
      expect(
        policy.timeoutFor(_bytes(64 * _mb)),
        const Duration(seconds: 256),
      );
    });

    test('changing the setting changes the next budget', () async {
      final c = await container();
      expect(
        c.read(elaborationTimeoutPolicyProvider).timeoutFor(_bytes(64 * _mb)),
        const Duration(seconds: 256),
      );
      await c
          .read(appSettingsProvider.notifier)
          .setElaborationTimeLimit(ElaborationTimeLimit.extended);
      expect(
        c.read(elaborationTimeoutPolicyProvider).timeoutFor(_bytes(64 * _mb)),
        const Duration(seconds: 1024),
      );
    });
  });
}
