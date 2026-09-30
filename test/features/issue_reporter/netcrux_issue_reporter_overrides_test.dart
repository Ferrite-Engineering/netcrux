// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_issue_reporter/crux_issue_reporter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/features/issue_reporter/netcrux_issue_reporter_overrides.dart';

/// NetCrux's binding of `crux_issue_reporter`. The package default for
/// `cruxIssueReporterConfigProvider` throws precisely so a missing binding
/// cannot silently file a user's bug report against the wrong repository —
/// these tests pin the binding that replaces it.
void main() {
  group('netcruxIssueReporterConfig', () {
    test('targets the open-core repository, not the beta tracker', () {
      expect(netcruxIssueReporterConfig.productName, 'NetCrux');
      expect(
        netcruxIssueReporterConfig.repositorySlug,
        'Ferrite-Engineering/netcrux',
      );
    });

    test('the slug does not track kBetaPeriod', () {
      // The tracker moved at the 1.0 launch; the gating flag flips on its own
      // schedule and must not drag the issue routing back to `-beta`.
      expect(
        netcruxIssueReporterConfig.repositorySlug,
        isNot(contains('-beta')),
      );
    });

    test('opens the structured bug-report issue form', () {
      expect(netcruxIssueReporterConfig.issueTemplate, 'bug_report.yml');
    });

    test('builds a well-formed GitHub new-issue URL', () {
      final url = netcruxIssueReporterConfig.newIssueUrl;
      expect(url.scheme, 'https');
      expect(url.host, 'github.com');
      expect(
        url.path,
        '/${netcruxIssueReporterConfig.repositorySlug}/issues/new',
      );
    });

    test('slugs the screenshot filename prefix from the product name', () {
      expect(
        netcruxIssueReporterConfig.resolvedScreenshotFilePrefix,
        'netcrux',
      );
    });

    test('carries the suite-standard beta labels', () {
      expect(
        netcruxIssueReporterConfig.defaultLabels,
        containsAll(<String>['bug', 'user-report']),
      );
    });
  });

  group('netcruxIssueReporterOverrides', () {
    test('binds the config the package would otherwise throw for', () {
      final bare = ProviderContainer();
      addTearDown(bare.dispose);
      // Riverpod wraps the provider body's throw; the cause is what matters.
      expect(
        () => bare.read(cruxIssueReporterConfigProvider),
        throwsA(
          predicate<Object>(
            (e) => e.toString().contains(
              'cruxIssueReporterConfigProvider has no value',
            ),
          ),
        ),
      );

      final wired = ProviderContainer(
        overrides: <Override>[...netcruxIssueReporterOverrides],
      );
      addTearDown(wired.dispose);
      expect(
        wired.read(cruxIssueReporterConfigProvider),
        netcruxIssueReporterConfig,
      );
    });

    test('leaves the overlay category seam at its open-core no-op', () {
      final container = ProviderContainer(
        overrides: <Override>[...netcruxIssueReporterOverrides],
      );
      addTearDown(container.dispose);
      // The "Pro State" category is the Pro overlay's contribution;
      // an open-core build must contribute nothing.
      expect(
        container
            .read(cruxIssueReporterDataProviderProvider)
            .extraCategories(CruxIssueSessionContext.empty),
        isEmpty,
      );
    });

    test('does not fold the Yosys diagnostics report into the body', () {
      final container = ProviderContainer(
        overrides: <Override>[...netcruxIssueReporterOverrides],
      );
      addTearDown(container.dispose);
      // Yosys stderr quotes source-file paths verbatim, so it is deliberately
      // NOT wired into `cruxIssueDiagnosticsReportProvider`. Wiring it would
      // put the user's filesystem layout in a public GitHub issue.
      expect(container.read(cruxIssueDiagnosticsReportProvider), isNull);
    });
  });
}
