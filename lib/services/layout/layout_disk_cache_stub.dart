// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:netcrux/services/layout/elk_layout_service.dart'
    show LayoutDiskCache;

/// No disk cache on platforms without `dart:io` (web). Layout caching is
/// desktop-only: the web viewer solves each layout in the browser, and has no
/// file system to persist the result to. Selected by the conditional import in
/// `elk_layout_service_provider.dart` whenever `dart.library.io` is absent.
LayoutDiskCache? createDefaultLayoutDiskCache() => null;
