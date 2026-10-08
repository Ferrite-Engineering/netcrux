import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netcrux/features/annotations/services/annotation_id_generator.dart';

void main() {
  group('AnnotationIdGenerator', () {
    test('produces annotation ids with the expected prefix', () {
      final gen = AnnotationIdGenerator(
        clock: () => DateTime.fromMillisecondsSinceEpoch(1700000000000),
      );
      expect(gen.nextAnnotationId(), startsWith('an-1700000000000-'));
    });

    test('produces unique ids even at the same millisecond', () {
      final gen = AnnotationIdGenerator(
        clock: () => DateTime.fromMillisecondsSinceEpoch(1700000000000),
      );
      final ids = <String>{
        gen.nextAnnotationId(),
        gen.nextAnnotationId(),
        gen.nextAnnotationId(),
        gen.nextAnnotationId(),
      };
      expect(ids, hasLength(4));
    });

    test('the provider serves one generator per container', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(
        container.read(annotationIdGeneratorProvider),
        same(container.read(annotationIdGeneratorProvider)),
      );
    });
  });
}
