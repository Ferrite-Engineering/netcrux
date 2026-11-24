// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

/// The headless binary's version: `pubspec.yaml`'s version without its build
/// number. A plain constant because the binary has no Flutter and so no
/// `package_info_plus`; `test/headless/cli_version_test.dart` fails when it
/// and the pubspec disagree.
const String kNetCruxCliVersion = '1.2.0';
