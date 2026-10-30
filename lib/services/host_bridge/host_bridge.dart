// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

/// Conditional re-export of `HostBridgeChannel`.
///
/// On Flutter Web this resolves to the `window.postMessage` transport in
/// `host_bridge_web.dart`. On every other host (desktop, the analyzer and the
/// VM test runner) it resolves to the inert stub in `host_bridge_stub.dart`,
/// which reports no host, never emits and drops what it is asked to post.
///
/// Production code imports this file, never `_web.dart` or `_stub.dart`. Only
/// the transport is split: what crosses the boundary
/// (`host_bridge_messages.dart`) and what is done about it
/// (`editor_host_bridge.dart`) are platform-neutral.
library;

export 'host_bridge_stub.dart'
    if (dart.library.js_interop) 'host_bridge_web.dart';
