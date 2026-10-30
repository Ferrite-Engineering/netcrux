// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:netcrux/domain/enums/elaboration_time_limit.dart';
import 'package:netcrux/domain/interfaces/elaboration_timeout_policy.dart';
import 'package:netcrux/features/settings/providers/app_settings_provider.dart';
import 'package:netcrux/services/yosys/elaboration_timeout_provider.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'elaboration_timeout_policy_provider.g.dart';

/// The [ElaborationTimeoutPolicy] consulted by the elaboration pipeline
/// before each Yosys run. Open-core registers [DefaultElaborationTimeoutPolicy]
/// for the choice in Settings, Engines; a Pro tier may override it in
/// `lib/overrides.dart`.
@Riverpod(keepAlive: true)
ElaborationTimeoutPolicy elaborationTimeoutPolicy(Ref ref) =>
    DefaultElaborationTimeoutPolicy(
      limit:
          ref.watch(appSettingsProvider).value?.elaborationTimeLimit ??
          ElaborationTimeLimit.automatic,
    );
