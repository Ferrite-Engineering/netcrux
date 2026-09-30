// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

@TestOn('browser')
library;

import 'package:crux_audit/crux_audit.dart';
import 'package:crux_license/crux_license.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/core/policy/netcrux_policy_keys.dart';
import 'package:netcrux/domain/models/project/netcrux_project.dart';
import 'package:netcrux/features/project/providers/current_project_provider.dart';

/// Runs in a real browser (`flutter test --platform chrome`), which has no
/// environment variable and no file to discover an organization policy from.
///
/// Every project open records an audit event through the policy-configured
/// sink, so the default policy wiring has to work there with no override:
/// no policy, a no-op sink, and an open that completes.
void main() {
  test('a project opens under no policy, with no override', () async {
    final container = ProviderContainer(
      overrides: [
        cruxAuditProductIdProvider.overrideWithValue(
          NetCruxPolicyKeys.productId,
        ),
      ],
    );
    addTearDown(container.dispose);

    final policy = container.read(cruxPolicyProvider);
    expect(policy.document.isPresent, isFalse);
    expect(policy.wasRejected, isFalse);
    expect(container.read(cruxAuditSinkProvider), isA<NoopAuditSink>());

    const upload = 'blob:https://app.netcrux.app/5b0c#top.json';
    container
        .read(currentProjectProvider.notifier)
        .setProject(
          NetcruxProject.create(sourceFiles: const <String>[upload]),
        );
    await pumpEventQueue();

    expect(container.read(currentProjectProvider).sourceFiles, <String>[
      upload,
    ]);
  });
}
