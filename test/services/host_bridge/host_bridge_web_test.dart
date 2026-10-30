// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

@TestOn('browser')
library;

import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/enums/editor_host_kind.dart';
import 'package:netcrux/services/host_bridge/host_bridge.dart';
import 'package:netcrux/services/host_bridge/host_bridge_messages.dart';

/// The `window.postMessage` transport in a real browser, with the two globals
/// the extension's page shim publishes set by hand.
///
/// This is the half of the host bridge no VM test can reach: the marker read,
/// the `message` listener and its origin filter, and the outbound seam.

@JS('postMessage')
external void _postMessage(JSAny? message, JSString targetOrigin);

@JS('dispatchEvent')
external void _dispatchEvent(JSObject event);

@JS('MessageEvent')
extension type _MessageEventCtor._(JSObject _) implements JSObject {
  external factory _MessageEventCtor(JSString type, JSObject init);
}

void _setGlobal(String name, JSAny? value) =>
    globalContext.setProperty(name.toJS, value);

void _clearGlobal(String name) => globalContext.delete(name.toJS);

JSObject _marker(String kind) {
  return JSObject()
    ..setProperty('kind'.toJS, kind.toJS)
    ..setProperty('protocol'.toJS, 1.toJS);
}

Future<void> _flush() => Future<void>.delayed(const Duration(milliseconds: 30));

void main() {
  tearDown(() {
    _clearGlobal(kEditorHostMarkerGlobal);
    _clearGlobal(kEditorHostSeamGlobal);
  });

  test('a page with no marker is not hosted and listens for nothing', () async {
    expect(HostBridgeChannel.detectHostKind(), EditorHostKind.none);
    final channel = HostBridgeChannel();
    addTearDown(channel.dispose);
    final frames = <Map<String, Object?>>[];
    channel.inbound.listen(frames.add);
    _postMessage(
      <String, Object?>{'type': kHostBridgeFrameType}.jsify(),
      '*'.toJS,
    );
    await _flush();
    expect(frames, isEmpty);
    expect(channel.canPost, isFalse);
  });

  test('a marker of another kind, or not an object, is not a host', () {
    _setGlobal(kEditorHostMarkerGlobal, _marker('emacs'));
    expect(HostBridgeChannel.detectHostKind(), EditorHostKind.none);
    _setGlobal(kEditorHostMarkerGlobal, 'vscode'.toJS);
    expect(HostBridgeChannel.detectHostKind(), EditorHostKind.none);
  });

  test('with the marker set, frames from the host arrive', () async {
    _setGlobal(kEditorHostMarkerGlobal, _marker(kEditorHostMarkerKindVscode));
    expect(HostBridgeChannel.detectHostKind(), EditorHostKind.vscode);
    final channel = HostBridgeChannel();
    addTearDown(channel.dispose);
    final frames = <Map<String, Object?>>[];
    channel.inbound.listen(frames.add);

    _postMessage(
      <String, Object?>{
        'type': kHostBridgeFrameType,
        'protocol': 1,
        'kind': kHostBridgeOpenNetlistKind,
        'name': 'top.json',
        'text': '{}',
      }.jsify(),
      '*'.toJS,
    );
    await _flush();

    expect(frames, hasLength(1));
    expect(frames.single['name'], 'top.json');
  });

  test('a frame from an origin that is not the editor is ignored', () async {
    _setGlobal(kEditorHostMarkerGlobal, _marker(kEditorHostMarkerKindVscode));
    final channel = HostBridgeChannel();
    addTearDown(channel.dispose);
    final frames = <Map<String, Object?>>[];
    channel.inbound.listen(frames.add);

    final init = JSObject()
      ..setProperty('data'.toJS, <String, Object?>{'a': 1}.jsify())
      ..setProperty('origin'.toJS, 'https://evil.example'.toJS);
    _dispatchEvent(_MessageEventCtor('message'.toJS, init));
    init.setProperty('origin'.toJS, 'vscode-webview://abc'.toJS);
    _dispatchEvent(_MessageEventCtor('message'.toJS, init));
    await _flush();

    expect(frames, hasLength(1));
  });

  test('a payload that is not an object is dropped', () async {
    _setGlobal(kEditorHostMarkerGlobal, _marker(kEditorHostMarkerKindVscode));
    final channel = HostBridgeChannel();
    addTearDown(channel.dispose);
    final frames = <Map<String, Object?>>[];
    channel.inbound.listen(frames.add);
    _postMessage('just a string'.toJS, '*'.toJS);
    _postMessage(null, '*'.toJS);
    await _flush();
    expect(frames, isEmpty);
  });

  test('outbound frames go through the seam, and only when it exists', () {
    _setGlobal(kEditorHostMarkerGlobal, _marker(kEditorHostMarkerKindVscode));
    final channel = HostBridgeChannel();
    addTearDown(channel.dispose);
    expect(channel.canPost, isFalse);
    channel.post(hostBridgeReadyFrame());

    final posted = <Object?>[];
    final seam = JSObject()
      ..setProperty(
        'postMessage'.toJS,
        ((JSAny? frame) => posted.add(frame.dartify())).toJS,
      );
    _setGlobal(kEditorHostSeamGlobal, seam);
    expect(channel.canPost, isTrue);
    channel.post(hostBridgeReadyFrame());
    expect(posted, <Object?>[hostBridgeReadyFrame()]);
  });
}
