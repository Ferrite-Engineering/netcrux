// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_updates/crux_updates.dart';

/// NetCrux's binding of the cross-suite [CruxUpdateConfig].
///
/// The manifest is a public JSON document served from the release
/// infrastructure; "Update Now" deep-links to the download page rather than
/// downloading in place (see the `crux_updates` README — the manifest already
/// carries `downloads` / `checksums` for a future in-place transport).
///
/// No `appStoreUri` / `playStoreUri` and no `checkOnMobile`: NetCrux ships
/// macOS / Linux / Windows desktop builds plus a read-only web viewer, and has
/// no iOS or Android target (see `CLAUDE.md` → "Platform Targets"). The web
/// build still runs the *check* — the banner never renders there, but the
/// manifest's `server_time` is what hardens the beta-expiry clock against a
/// device-clock rollback.
final CruxUpdateConfig netcruxUpdateConfig = CruxUpdateConfig(
  productName: 'NetCrux',
  manifestUri: 'https://updates.netcrux.app/manifest.json',
  downloadPageUri: netcruxDownloadPageUrl,
);

/// The public NetCrux download page. Shared by the update banner's
/// "Update Now" action and the beta-expiry banner / blocking modal, so the
/// two can never drift onto different URLs.
const String netcruxDownloadPageUrl = 'https://netcrux.app/download';
