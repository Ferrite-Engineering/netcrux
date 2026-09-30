// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The web template is what a browser tab, a search snippet and an installed
/// PWA show for app.netcrux.app. `flutter create` writes the package name as
/// the title and "A new Flutter project." as the description, and a deployed
/// build once served exactly that. These checks fail on the generator
/// defaults so the product name and a real description cannot regress.
void main() {
  const flutterDefaultDescription = 'A new Flutter project.';

  final packageName = RegExp(
    r'^name:\s*(\S+)',
    multiLine: true,
  ).firstMatch(File('pubspec.yaml').readAsStringSync())!.group(1)!;
  final indexHtml = File('web/index.html').readAsStringSync();
  final manifest =
      jsonDecode(File('web/manifest.json').readAsStringSync())
          as Map<String, dynamic>;

  String? metaContent(String attribute, String key) => RegExp(
    '<meta\\s+$attribute="${RegExp.escape(key)}"\\s+content="([^"]*)"',
  ).firstMatch(indexHtml)?.group(1);

  group('web/index.html', () {
    test('the tab title is the product name, not the package name', () {
      final title = RegExp(
        '<title>([^<]*)</title>',
      ).firstMatch(indexHtml)?.group(1);
      expect(title, 'NetCrux');
      expect(title, isNot(packageName));
    });

    test('the description is a real one', () {
      final description = metaContent('name', 'description');
      expect(description, isNotNull);
      expect(description, isNot(flutterDefaultDescription));
      expect(description, contains('NetCrux'));
    });

    test('the home-screen title is the product name', () {
      final title = metaContent('name', 'apple-mobile-web-app-title');
      expect(title, 'NetCrux');
      expect(title, isNot(packageName));
    });

    test('the page declares its language and a social preview', () {
      expect(indexHtml, contains('<html lang="en">'));
      expect(metaContent('property', 'og:title'), 'NetCrux');
      expect(
        metaContent('property', 'og:description'),
        allOf(isNotNull, isNot(flutterDefaultDescription)),
      );
    });
  });

  group('web/manifest.json', () {
    test('the PWA is named after the product', () {
      expect(manifest['name'], 'NetCrux');
      expect(manifest['short_name'], 'NetCrux');
      expect(manifest['name'], isNot(packageName));
    });

    test('the PWA description is a real one', () {
      expect(manifest['description'], isA<String>());
      expect(manifest['description'], isNot(flutterDefaultDescription));
      expect(manifest['description'], isNot(isEmpty));
    });
  });
}
