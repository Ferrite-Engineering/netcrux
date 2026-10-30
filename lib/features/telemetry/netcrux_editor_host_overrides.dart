// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_telemetry/crux_telemetry.dart';
import 'package:crux_updates/crux_updates.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:netcrux/domain/enums/editor_host_kind.dart';
import 'package:netcrux/services/host_bridge/editor_host_providers.dart';

/// Root-scope overrides for a build an editor extension hosts.
///
/// Binds [editorHostKindProvider] to [hostKind] so every dependent decides
/// from the first frame. Under a host it also takes this build out of the
/// networking and consent business, because the extension, not the page inside
/// it, answers for both:
///
/// - Telemetry. The editor has one telemetry switch for the user and the
///   extension host applies it. A page that kept its own pipeline would answer
///   to a different consent store, and a user who turned telemetry off in the
///   editor could still be reported on by a panel inside it. The service here
///   discards every event and the first-run disclosure is never shown, so no
///   code path leads from a `record()` call to an HTTP request.
/// - Update checks. The editor updates the extension, and the manifest request
///   would be blocked by the webview's content security policy anyway.
///
/// Nothing is overridden for [EditorHostKind.none] except the kind itself, so
/// the standalone app and the browser build are unchanged.
List<Override> netcruxEditorHostOverrides(EditorHostKind hostKind) =>
    <Override>[
      editorHostKindProvider.overrideWithValue(hostKind),
      if (hostKind != EditorHostKind.none) ...<Override>[
        telemetryServiceProvider.overrideWithValue(
          const NoopTelemetryService(),
        ),
        telemetryConsentPromptVisibleProvider.overrideWithValue(false),
        autoUpdateCheckEnabledProvider.overrideWith((ref) async => false),
      ],
    ];
