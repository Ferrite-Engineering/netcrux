// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:netcrux/core/web/web_launch_params.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'web_launch_params_provider.g.dart';

/// Session-scope provider holding the parsed [WebLaunchParams] for the
/// active web session. Default value is [WebLaunchParams.empty]; the
/// bootstrap path on web overrides this with values parsed from
/// `window.location.search` and `window.location.hash` so feature code
/// reads the launch hints through Riverpod rather than a global.
///
/// Desktop builds keep the default `empty`, so the workspace's launch step
/// that opens a `?json=` netlist does nothing there.
@Riverpod(keepAlive: true)
WebLaunchParams webLaunchParams(Ref ref) => WebLaunchParams.empty;
