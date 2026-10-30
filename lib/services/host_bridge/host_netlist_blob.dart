// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

/// Where a netlist the host sent as text is read from.
///
/// The web netlist loader reads a location, not a string: a browser upload is
/// a `blob:` URL the loader fetches, with the file's own name riding on it as
/// the URL fragment (see `NetcruxProject.locationLabel`). A netlist the editor
/// host sends goes through the same route so it takes the same loader path as
/// an upload. On the web `createHostNetlistLocation` makes the blob; elsewhere
/// (the VM test runner) it makes a `data:` URL, which a test reads with its
/// own reader.
library;

export 'host_netlist_blob_stub.dart'
    if (dart.library.js_interop) 'host_netlist_blob_web.dart';
