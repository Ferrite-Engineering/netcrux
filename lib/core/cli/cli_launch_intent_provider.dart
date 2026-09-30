// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:netcrux/core/cli/cli_launch_intent.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'cli_launch_intent_provider.g.dart';

/// Holds the [CliLaunchIntent] computed by [CliArgParser] in
/// [bootstrap]. The Welcome screen and the (future) auto-open path read
/// this provider on first build to decide whether to land on the Welcome
/// screen or jump straight into the project viewer.
///
/// Defaults to [CliLaunchIntent.empty]. `bootstrap` overrides it with
/// the parsed value before the app starts; widget tests can override it
/// directly to simulate a specific launch shape.
@Riverpod(keepAlive: true)
CliLaunchIntent cliLaunchIntent(Ref ref) => const CliLaunchIntent.empty();
