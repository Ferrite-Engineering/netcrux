// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_issue_reporter/crux_issue_reporter.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:netcrux/core/app_info/about_providers.dart';
import 'package:netcrux/features/issue_reporter/providers/netcrux_issue_session_context.dart';

/// NetCrux's binding of the cross-suite [CruxIssueReporterConfig].
///
/// Reports are filed against the public open-core repository. The slug is
/// selected here rather than inside `crux_issue_reporter` so the package stays
/// free of per-product routing. It is deliberately *not* keyed off
/// `kBetaPeriod`: that flag governs tier gating and flips on its own schedule,
/// while the issue tracker moved to the open-core repo at the 1.0 launch.
///
/// The reporter is open to every tier: no `FeatureGate`, no tier badge. It is
/// the beta feedback mechanism, and a user who cannot report a bug is a user
/// whose bug never gets fixed.
const CruxIssueReporterConfig netcruxIssueReporterConfig =
    CruxIssueReporterConfig(
      productName: 'NetCrux',
      repositorySlug: 'Ferrite-Engineering/netcrux',
      issueTemplate: 'bug_report.yml',
    );

/// Root-scope overrides that bind the shared beta issue reporter to NetCrux's
/// configuration, build metadata, and privacy-scrubbed session snapshot.
///
/// Spread into the root `ProviderContainer` by `bootstrap`, ahead of the
/// Pro overlay's `proOverrides` — the overlay contributes its extra
/// "Pro State" category through `cruxIssueReporterDataProviderProvider`, whose
/// open-core default contributes nothing.
///
/// The localized string bundle is deliberately **not** here: it needs a
/// `BuildContext` for `L10N.of(context)`, so `NetcruxApp` overrides
/// `cruxIssueReporterStringsProvider` from inside `MaterialApp.builder`.
///
/// `cruxIssueDiagnosticsReportProvider` is deliberately left at its `null`
/// default. The obvious candidate — the tab diagnostics drawer's Yosys stderr
/// — quotes source-file paths verbatim, which the reporter's privacy contract
/// excludes. Folding it in would leak the user's filesystem layout into a
/// public GitHub issue.
final List<Override> netcruxIssueReporterOverrides = <Override>[
  cruxIssueReporterConfigProvider.overrideWithValue(netcruxIssueReporterConfig),
  cruxIssueReporterBuildInfoProvider.overrideWith(
    (ref) => ref.watch(aboutBuildInfoProvider).value,
  ),
  netcruxIssueSessionContextOverride,
];
