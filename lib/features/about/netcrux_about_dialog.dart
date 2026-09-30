// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:crux_about_dialog/crux_about_dialog.dart';
import 'package:crux_app_info/crux_app_info.dart';
import 'package:crux_ide_layout/crux_ide_layout.dart';
import 'package:crux_issue_reporter/crux_issue_reporter.dart';
import 'package:crux_updates/crux_updates.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:netcrux/core/about/netcrux_about_strings.dart';
import 'package:netcrux/core/app_info/about_providers.dart';
import 'package:netcrux/core/help_urls.dart';
import 'package:netcrux/l10n/generated/app_localizations.dart';
import 'package:netcrux/shared/widgets/glowing_app_icon.dart';
import 'package:url_launcher/url_launcher.dart';

/// The NetCrux About dialog.
///
/// A thin builder over the cross-suite [CruxAboutDialog] (from
/// `crux_about_dialog`): it maps NetCrux's branding / build-info / edition
/// providers and ARB strings onto the shared surface and supplies the
/// NetCrux-specific pieces — the glowing app icon, the elkjs attribution
/// section, and the canonical suite action row (Visit Website, Documentation,
/// Report Issue, Check for Updates, Privacy Policy, Terms of Service, Copy
/// Version Info). Tier and beta-period chips are driven by `crux_license`
/// providers inside the shared widget.
///
/// The [AboutAttributionSection] for elkjs (EPL-2.0, vendored as
/// `assets/elk/elk.bundled.js`) makes the attribution visible in-app; the
/// `NOTICES` file and `assets/elk/LICENSE.epl-2.0.txt` continue to ship the
/// full Agreement text per EPL-2.0 §3.1(b) (guarded by
/// `test/static/bundled_license_assets_test.dart`).
abstract final class NetcruxAboutDialog {
  /// Opens the About box: a modal dialog on desktop, a pushed route on mobile.
  ///
  /// Re-entrancy guarded ([ModalGuard]) inside the opener so every caller —
  /// menu item, command palette, keyboard shortcut — is covered: a repeated
  /// gesture while the box is open (or while its build info is still
  /// resolving) must not stack a second copy.
  static Future<void> openAdaptive(BuildContext context, WidgetRef ref) =>
      ModalGuard.run('about', () => _openAdaptive(context, ref));

  static Future<void> _openAdaptive(BuildContext context, WidgetRef ref) async {
    final l10n = L10N.of(context);

    final branding = ref.read(aboutBrandingProvider);

    // Resolve build info up front so the version section renders data rather
    // than a perpetual spinner. On failure the shared widget hides the
    // section and the Copy Version Info button stays disabled.
    ApplicationBuildInfo? pkgInfo;
    AsyncValue<ApplicationBuildInfo> buildInfo;
    try {
      final resolved = await ref.read(aboutBuildInfoProvider.future);
      pkgInfo = resolved;
      buildInfo = AsyncValue.data(resolved);
    } on Object catch (error, stackTrace) {
      buildInfo = AsyncValue.error(error, stackTrace);
    }

    if (!context.mounted) return;

    final edition = aboutEditionLabel(ref, l10n);
    // A non-null capture so the Copy Version Info closure stays type-promoted.
    final info = pkgInfo;

    await CruxAboutDialog.show(
      context,
      title: l10n.aboutDialogTitle,
      tagline: l10n.aboutTagline,
      companyTagline: l10n.aboutCompanyName,
      appIcon: const GlowingAppIcon(size: 80),
      branding: branding,
      buildInfo: buildInfo,
      // Hide the edition chip for the open-core edition.
      editionLabel: edition == l10n.aboutEditionOpenCore ? '' : edition,
      strings: NetcruxAboutStrings(l10n),
      attributions: [
        AboutAttributionSection(
          title: l10n.aboutSectionElkjs,
          description: l10n.aboutElkjsDescription,
          licenseHeader: l10n.aboutElkjsLicenseHeader,
          licenseText: _elkjsLicenseText,
        ),
      ],
      actions: [
        AboutAction(
          label: l10n.aboutButtonVisitWebsite,
          icon: Icons.language_outlined,
          onTap: (_) => unawaited(launchUrl(Uri.parse(branding.websiteUrl))),
        ),
        AboutAction(
          label: l10n.aboutButtonDocs,
          icon: Icons.menu_book_outlined,
          onTap: (_) => unawaited(launchUrl(Uri.parse(HelpUrls.docs))),
        ),
        // The beta feedback path, reachable from the box a user already opens
        // to find their version and build SHA — the two things every report
        // needs. Never tier-gated.
        AboutAction(
          label: l10n.actionSubmitIssue,
          icon: Icons.bug_report_outlined,
          onTap: (ctx) => unawaited(CruxIssueReporterDialog.openAdaptive(ctx)),
        ),
        // A manual check always runs, regardless of the Settings → General
        // auto-check toggle. The result surfaces as a snackbar from the root
        // ScaffoldMessenger (up to date / could not check) or as the
        // UpdateBanner behind the dialog.
        AboutAction(
          label: l10n.actionCheckForUpdates,
          icon: Icons.system_update_alt_outlined,
          onTap: (ctx) => unawaited(runManualUpdateCheck(ctx, ref)),
        ),
        AboutAction(
          label: l10n.aboutButtonPrivacy,
          icon: Icons.privacy_tip_outlined,
          onTap: (_) => unawaited(launchUrl(Uri.parse(HelpUrls.privacyPolicy))),
        ),
        AboutAction(
          label: l10n.aboutButtonTerms,
          icon: Icons.description_outlined,
          onTap: (_) =>
              unawaited(launchUrl(Uri.parse(HelpUrls.termsOfService))),
        ),
        // The full open-source license list: every transitive pub package
        // (collected by Flutter at build time) plus the vendored components
        // registered in `kNetcruxVendoredLicenses`. The inline elkjs
        // attribution section above is the prominent one because it carries
        // a redistribution obligation; this is the complete inventory.
        AboutAction(
          label: l10n.aboutButtonAcknowledgments,
          icon: Icons.workspace_premium_outlined,
          onTap: (ctx) => _showLicensePage(ctx, l10n, branding, pkgInfo),
        ),
        AboutAction(
          label: l10n.aboutButtonCopyVersionInfo,
          icon: Icons.copy_outlined,
          onTap: info == null
              ? null
              : (ctx) => unawaited(_copyVersionInfo(ctx, l10n, edition, info)),
        ),
      ],
    );
  }

  /// Pushes Flutter's built-in [LicensePage].
  ///
  /// Deliberately the framework's page rather than a hand-rolled list: it
  /// renders whatever `LicenseRegistry` holds, which is the build's own
  /// dependency inventory rather than a hand-maintained file that silently
  /// goes stale the first time a dependency is added.
  ///
  /// Routed on the [Navigator] that owns the About dialog, so on desktop it
  /// stacks above the modal and Back returns to it.
  static void _showLicensePage(
    BuildContext context,
    L10N l10n,
    ApplicationBranding branding,
    ApplicationBuildInfo? info,
  ) {
    showLicensePage(
      context: context,
      applicationName: 'NetCrux',
      applicationVersion: info?.version,
      applicationIcon: const Padding(
        padding: EdgeInsets.only(bottom: 8),
        child: GlowingAppIcon(size: 56),
      ),
      applicationLegalese: l10n.aboutCompanyName,
    );
  }

  static Future<void> _copyVersionInfo(
    BuildContext context,
    L10N l10n,
    String edition,
    ApplicationBuildInfo info,
  ) async {
    await Clipboard.setData(
      ClipboardData(
        text: aboutVersionInfoText(
          appName: 'NetCrux',
          editionLabel: edition,
          info: info,
        ),
      ),
    );
    if (context.mounted) {
      showCruxInfoSnack(context, l10n.aboutCopiedConfirmation);
    }
  }

  // Legal text is intentionally not localized. The opening Agreement notice
  // mirrors the first paragraph of the bundled license file
  // (`assets/elk/LICENSE.epl-2.0.txt`), which ships the full text per
  // EPL-2.0 §3.1(b) alongside the `NOTICES` file.
  static const _elkjsLicenseText = '''
Eclipse Public License - v 2.0

THE ACCOMPANYING PROGRAM IS PROVIDED UNDER THE TERMS OF THIS ECLIPSE PUBLIC
LICENSE ("AGREEMENT"). ANY USE, REPRODUCTION OR DISTRIBUTION OF THE PROGRAM
CONSTITUTES RECIPIENT'S ACCEPTANCE OF THIS AGREEMENT.

The full Eclipse Public License 2.0 text is bundled with the application
(assets/elk/LICENSE.epl-2.0.txt and NOTICES).''';
}
