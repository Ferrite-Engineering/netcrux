// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:crux_workspace/crux_workspace.dart';
import 'package:flutter/material.dart';
import 'package:netcrux/core/help_urls.dart';
import 'package:netcrux/core/netcrux_url_launcher.dart';
import 'package:netcrux/l10n/generated/app_localizations.dart';

/// NetCrux's suite-membership line, for the foot of a start screen.
///
/// A wrapper over the shared [CruxSuiteFooter] because NetCrux has two start
/// screens — the desktop `EmptyCanvasContent` and the browser
/// `BrowserEmptyCanvasContent` — and the label lookup and the landing path
/// must not drift between them.
class NetCruxSuiteFooter extends StatelessWidget {
  /// Creates the suite-membership line.
  const NetCruxSuiteFooter({super.key});

  @override
  Widget build(BuildContext context) => CruxSuiteFooter(
    label: L10N.of(context).emptyCanvasSuiteFooter,
    onTap: () => unawaited(netcruxLaunchUrl(Uri.parse(HelpUrls.suiteHome))),
  );
}
