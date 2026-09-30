// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

/// Canonical URLs for NetCrux documentation and web pages.
///
/// Defined in one place so the full URL list stays maintainable, mirroring
/// WaveCrux's `HelpUrls`.
abstract final class HelpUrls {
  static const _base = 'https://docs.netcrux.app';

  /// NetCrux documentation home — the Help → Documentation target.
  static const String docs = _base;

  /// NetCrux marketing / home page.
  static const website = 'https://netcrux.app';

  // Contextual documentation sections: a page of the docs site (served
  // extensionless) and the heading anchor that answers the control. Targets
  // of the in-app `CruxHelpLink` icons; `test/core/help_urls_test.dart`
  // checks each anchor against `docs-site/docs/`.

  /// Docs — workspaces and restoring tabs on launch.
  static const filesAndProjects = '$_base/files-and-projects#workspaces';

  /// Docs — the color theme presets.
  static const appearanceAndThemes = '$_base/appearance-and-themes#presets';

  /// Docs — pointing NetCrux at a specific Yosys binary.
  static const gettingStarted = '$_base/getting-started#yosys-path';

  /// Docs — CXP cross-probe server settings.
  static const integrations = '$_base/integrations#cxp-settings';

  /// Docs — Search Design.
  static const navigating = '$_base/navigating#search';

  /// Download page for the latest build.
  static const download = 'https://netcrux.app/download';

  /// Privacy policy — one policy covers the whole EDACrux suite.
  static const privacyPolicy = 'https://edacrux.app/privacy';

  /// Terms of service — shared by the whole EDACrux suite.
  static const termsOfService = 'https://edacrux.app/terms';

  /// Suite home — the target of the welcome screen's suite-membership line.
  ///
  /// A per-product path rather than the shared `/products` page, and that is
  /// the whole point: the site's page-view beacon records the path and
  /// deliberately drops the query string, so `?from=netcrux` would be
  /// invisible and a desktop app sends no referrer. The path is how the visit
  /// is attributed to the app that sent it.
  static const suiteHome = 'https://edacrux.app/from/netcrux';

  /// The suite landing path, scrolled to one peer product's card.
  ///
  /// The fragment is free: the site's beacon drops it before sending, so this
  /// is still recorded as `/from/netcrux` and the per-product attribution is
  /// unaffected — while the reader still lands on the product the row named
  /// rather than at the top of a page listing three.
  static String suitePeer(String slug) => '$suiteHome#$slug';
}
