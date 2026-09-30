// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

@TestOn('browser')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/domain/models/workspace/netcrux_tab_payload.dart';
import 'package:netcrux/services/workspace/netcrux_workspace_codec.dart';

/// Runs in a real browser (`flutter test --platform chrome`), where a tab's
/// location is a URL, a `blob:` id or an uploaded file's name — never a path
/// on a file system. Tab identity must key each one as given, without
/// throwing, so the first tab can open at all.
void main() {
  const codec = NetcruxWorkspaceCodec();

  String? identityOf(String location) =>
      codec.identityOf(NetcruxTabPayload(sourceFiles: <String>[location]));

  test('a netlist URL is one tab, and case tells two apart', () {
    const url = 'https://example.com/n/top.json';
    expect(identityOf(' $url '), identityOf(url));
    expect(identityOf(url), endsWith(url));
    expect(
      identityOf('https://example.com/n/TOP.json'),
      isNot(identityOf(url)),
    );
  });

  test('a browser upload keeps its blob id and name', () {
    const upload = 'blob:https://app.netcrux.app/5b0c#top.json';
    expect(identityOf(upload), endsWith(upload));
  });

  test('a bare name is not resolved against the page or normalised', () {
    expect(identityOf('design.json'), endsWith('design.json'));
    expect(identityOf('design.json'), isNot(contains('http')));
    expect(identityOf('a/../b.json'), endsWith('a/../b.json'));
  });

  test('case tells two bare names apart', () {
    expect(identityOf('Design.json'), isNot(identityOf('design.json')));
  });
}
