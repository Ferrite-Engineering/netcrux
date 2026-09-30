// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/core/help_urls.dart';

/// A help icon lands on the section that answers it. Each contextual link
/// names a page of this repo's docs site and a heading anchor that page
/// declares, so renaming either fails here rather than on a user's click.
void main() {
  const contextual = <String, String>{
    'filesAndProjects': HelpUrls.filesAndProjects,
    'appearanceAndThemes': HelpUrls.appearanceAndThemes,
    'gettingStarted': HelpUrls.gettingStarted,
    'integrations': HelpUrls.integrations,
    'navigating': HelpUrls.navigating,
  };

  for (final MapEntry(key: name, value: url) in contextual.entries) {
    test('$name opens a docs-site section that exists', () {
      final uri = Uri.parse(url);
      expect(uri.origin, 'https://docs.netcrux.app');
      expect(uri.pathSegments, hasLength(1));
      expect(uri.fragment, isNotEmpty, reason: 'link to the section');

      final page = File('docs-site/docs/${uri.pathSegments.single}.md');
      expect(page.existsSync(), isTrue, reason: '${page.path} is missing');
      expect(page.readAsStringSync(), contains('{#${uri.fragment}}'));
    });
  }

  test('privacy and terms open the suite pages', () {
    expect(HelpUrls.privacyPolicy, 'https://edacrux.app/privacy');
    expect(HelpUrls.termsOfService, 'https://edacrux.app/terms');
  });
}
