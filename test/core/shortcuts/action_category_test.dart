// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/core/shortcuts/action_category.dart';
import 'package:netcrux/l10n/generated/app_localizations.dart';

/// Coverage for the [ActionCategoryLabel] localization extension. Surface
/// membership and visibility live in the descriptor table — see
/// `netcrux_action_descriptors_test.dart` and
/// `action_surface_conformance_test.dart`.
void main() {
  test('every category resolves a non-empty localized label in every '
      'supported locale', () async {
    for (final locale in L10N.supportedLocales) {
      final l10n = await L10N.delegate.load(locale);
      final seen = <String>{};
      for (final category in ActionCategory.values) {
        final label = category.label(l10n);
        expect(label, isNotEmpty, reason: '$category in $locale');
        seen.add(label);
      }
      expect(
        seen.length,
        ActionCategory.values.length,
        reason: 'category labels must be distinct in $locale',
      );
    }
  });
}
