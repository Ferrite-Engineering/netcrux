// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:netcrux/services/links/incoming_link_service.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'netcrux_link_providers.g.dart';

/// The `netcrux://` links found on this launch's command line: Windows and
/// Linux open a link by starting the application with it as an argument.
///
/// Empty for an ordinary launch. `bootstrap` overrides it with the links
/// `NetCruxLaunchArgs` took off the command line; the workspace screen hands
/// them to its link inbox once the launch intent has been applied. More than
/// one is refused as a whole.
@Riverpod(keepAlive: true)
List<String> initialNetCruxLinks(Ref ref) => const <String>[];

/// The [IncomingLinkService] the workspace screen listens to for links that
/// reach the running app. Tests override it with a stream they control.
@Riverpod(keepAlive: true)
IncomingLinkService incomingLinkService(Ref ref) => const IncomingLinkService();
