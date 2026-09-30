// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:netcrux/services/layout/elk_layout_service.dart';
// Conditional import: desktop/VM gets a `dart:io`-backed disk cache; web gets
// none (a browser has no file system to persist a solved layout to; the
// service's in-memory cache still applies).
import 'package:netcrux/services/layout/layout_disk_cache_stub.dart'
    if (dart.library.io) 'package:netcrux/services/layout/layout_disk_cache_vm.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'elk_layout_service_provider.g.dart';

/// The [ElkLayoutService] used by the schematic pipeline. `keepAlive`
/// so the elkjs JS runtime survives across screens (initializing it is
/// a noticeable cost — ~half a second on a cold start — and re-using
/// the runtime across layouts is essential for interactive zoom/pan
/// performance later).
///
/// Wired with a disk-backed layout cache so a re-opened design skips the
/// multi-second elkjs solve — the result is keyed by a stable content hash
/// and persisted under the OS app-support directory.
@Riverpod(keepAlive: true)
ElkLayoutService elkLayoutService(Ref ref) {
  final service = ElkLayoutService(diskCache: createDefaultLayoutDiskCache());
  ref.onDispose(service.dispose);
  return service;
}
