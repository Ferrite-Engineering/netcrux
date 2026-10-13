// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Open-core extension point for the localized sentence every policy-locked
/// setting shows.
///
/// `NetcruxApp` mounts one `CruxPolicyLockScope` above the root navigator, so
/// a locked control in a dialog reads the same sentence as one in Settings.
/// The scope's message is this builder's result for the app's context. The
/// open-core default is null, which leaves the shared English sentence; the
/// overlay supplies its licence panel strings' localized sentence.
final policyLockMessageProvider = Provider<String Function(BuildContext)?>(
  (_) => null,
);
