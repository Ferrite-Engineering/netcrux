import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/features/annotations/providers/annotation_reveal_request.dart';

void main() {
  late ProviderContainer container;
  setUp(() => container = ProviderContainer());
  tearDown(() => container.dispose());

  test('starts with no request', () {
    expect(container.read(annotationRevealRequestProvider), isNull);
  });

  test('request then acknowledge clears it', () {
    container.read(annotationRevealRequestProvider.notifier).request('a1');
    expect(container.read(annotationRevealRequestProvider), 'a1');
    container.read(annotationRevealRequestProvider.notifier).acknowledge('a1');
    expect(container.read(annotationRevealRequestProvider), isNull);
  });

  test('acknowledging an older request leaves a newer one in place', () {
    container.read(annotationRevealRequestProvider.notifier)
      ..request('a1')
      ..request('a2')
      ..acknowledge('a1');
    expect(container.read(annotationRevealRequestProvider), 'a2');
  });
}
