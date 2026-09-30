// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:netcrux/core/web/web_launch_params.dart';

/// Non-web implementation: returns [WebLaunchParams.empty] because
/// desktop / VM hosts have no `window.location` to consult. Tests that
/// want to exercise the launch-param wiring inject values via
/// `webLaunchParamsProvider.overrideWithValue`.
WebLaunchParams readWebLaunchParams() => WebLaunchParams.empty;
