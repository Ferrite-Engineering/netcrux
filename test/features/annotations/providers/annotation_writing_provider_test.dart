// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/features/annotations/providers/annotation_writing_provider.dart';

void main() {
  test('writing while any dialog is open', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final writing = container.read(annotationWritingProvider.notifier);

    expect(container.read(annotationWritingProvider), isFalse);
    writing
      ..start()
      ..start();
    expect(container.read(annotationWritingProvider), isTrue);
    writing.stop();
    expect(
      container.read(annotationWritingProvider),
      isTrue,
      reason: 'one dialog is still open',
    );
    writing.stop();
    expect(container.read(annotationWritingProvider), isFalse);
    writing.stop();
    expect(container.read(annotationWritingProvider), isFalse);
  });
}
