// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_about_dialog/crux_about_dialog.dart';

/// Third-party components NetCrux ships that are **not** pub packages, and
/// so never reach Flutter's automatic `LicenseRegistry` collection.
///
/// Everything in the pub dependency graph is picked up by the build already.
/// This list is the remainder — the vendored files under `assets/` — and it
/// is deliberately short: adding an entry means someone decided to commit a
/// third-party binary or bundle into the repository, which should be rare
/// and visible.
///
/// The asset paths here are the same files that satisfy the redistribution
/// obligations, and `test/static/bundled_license_assets_test.dart` fails the
/// build if one goes missing or stops being a declared Flutter asset.
const List<CruxVendoredLicense> kNetcruxVendoredLicenses =
    <CruxVendoredLicense>[
      // The Eclipse Layout Kernel's JavaScript build, vendored as
      // `assets/elk/elk.bundled.js` and executed by `ElkLayoutService`
      // through flutter_js on desktop. EPL-2.0 §3.1(b) requires the
      // Agreement to accompany the Program in object-code form; the text
      // ships as an asset and is now also listed in-app.
      CruxVendoredLicense(
        packageName: 'elkjs (Eclipse Layout Kernel)',
        licenseAssetPath: 'assets/elk/LICENSE.epl-2.0.txt',
      ),
    ];
