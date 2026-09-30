// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:netcrux/app.dart';

/// Open-core `netcrux` entry point. The Pro/Enterprise overlay
/// re-enters via the same `bootstrap` function exported from
/// `package:netcrux/app.dart`, layering `proOverrides` on top of the
/// open-core `ProviderScope`. See `docs/ARCHITECTURE.md` (Extension Points)
/// and WaveCrux's `lib/app.dart`, the reference implementation of the
/// pattern.
Future<void> main(List<String> args) => bootstrap(args: args);
