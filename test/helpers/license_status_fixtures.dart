// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_license/crux_license.dart';

/// The address the educational fixture licence is issued to.
const String kFixtureEduEmail = 'student@example.edu';

/// An active licence status at [tier], as a Pro overlay's licence service
/// would publish it through `licenseStatusProvider`.
///
/// Open core has no such service, so these stand in for one: the open-core
/// surfaces that react to the licence (the educational-licence chip, the
/// export mark) are driven from them.
CruxLicenseStatus activeLicenseStatus(
  LicenseTier tier, {
  String? email = kFixtureEduEmail,
}) => CruxLicenseStatus(
  activation: CruxLicenseActivation.active,
  grant: LicenseGrant(
    issuerId: kEduLicenseIssuerId,
    tier: tier,
    products: CruxProduct.values.toSet(),
    licenseId: 'lic-fixture',
    email: email,
    expiry: DateTime.utc(2027, 9, 30, 12),
  ),
);
