// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_telemetry/crux_telemetry.dart';
import 'package:crux_updates/crux_updates.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/enums/editor_host_kind.dart';
import 'package:netcrux/features/telemetry/netcrux_editor_host_overrides.dart';
import 'package:netcrux/services/host_bridge/editor_host_providers.dart';

void main() {
  test('under a host the build sends nothing and checks nothing', () async {
    final container = ProviderContainer(
      overrides: netcruxEditorHostOverrides(EditorHostKind.vscode),
    );
    addTearDown(container.dispose);

    expect(container.read(editorHostKindProvider), EditorHostKind.vscode);
    expect(container.read(isEditorHostedProvider), isTrue);
    // The editor's own telemetry switch governs; the page records nothing.
    expect(
      container.read(telemetryServiceProvider),
      isA<NoopTelemetryService>(),
    );
    expect(container.read(telemetryConsentPromptVisibleProvider), isFalse);
    expect(
      await container.read(autoUpdateCheckEnabledProvider.future),
      isFalse,
    );
  });

  test('with no host only the kind is bound', () {
    final overrides = netcruxEditorHostOverrides(EditorHostKind.none);
    expect(overrides, hasLength(1));
    final container = ProviderContainer(overrides: overrides);
    addTearDown(container.dispose);
    expect(container.read(editorHostKindProvider), EditorHostKind.none);
    expect(container.read(isEditorHostedProvider), isFalse);
  });
}
