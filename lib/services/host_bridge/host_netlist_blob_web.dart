// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:js_interop';

@JS('Blob')
extension type _Blob._(JSObject _) implements JSObject {
  external factory _Blob(JSArray<JSAny> parts, _BlobOptions options);
}

extension type _BlobOptions._(JSObject _) implements JSObject {
  external factory _BlobOptions({String type});
}

@JS('URL.createObjectURL')
external JSString _createObjectUrl(JSObject blob);

@JS('URL.revokeObjectURL')
external void _revokeObjectUrl(JSString url);

/// A `blob:` URL holding [text], with [name] as its fragment. The fragment is
/// ignored when the blob is fetched and is what the tab shows instead of the
/// blob's opaque id.
String createHostNetlistLocation(String name, String text) {
  final blob = _Blob(
    <JSAny>[text.toJS].toJS,
    _BlobOptions(type: 'application/json'),
  );
  return '${_createObjectUrl(blob).toDart}#${Uri.encodeComponent(name)}';
}

/// Releases the blob behind [location]. Safe to call once the loader has read
/// it; a location that is not a blob is ignored.
void releaseHostNetlistLocation(String location) {
  if (!location.startsWith('blob:')) return;
  final hash = location.indexOf('#');
  final url = hash < 0 ? location : location.substring(0, hash);
  _revokeObjectUrl(url.toJS);
}
