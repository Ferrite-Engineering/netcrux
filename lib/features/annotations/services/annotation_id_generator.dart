import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Riverpod provider exposing a per-app [AnnotationIdGenerator]. Tests
/// override this with a deterministic-clock generator so generated ids
/// are stable.
final annotationIdGeneratorProvider = Provider<AnnotationIdGenerator>(
  (_) => AnnotationIdGenerator(),
  name: 'annotationIdGeneratorProvider',
);

/// Generates stable per-session annotation ids.
///
/// Uses `millisecondsSinceEpoch` + a per-instance counter so two
/// creates in the same millisecond don't collide. The id is opaque to
/// the rest of the system — anything string-valued is fine — but a
/// time-prefix makes ids sort naturally by creation order during
/// debugging. The `Annotation.id` field is forward-compatible with a
/// move to a true UUID because the contract is just "opaque non-empty
/// string."
class AnnotationIdGenerator {
  /// Creates a fresh generator. Per-instance counter starts at 0.
  AnnotationIdGenerator({
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final DateTime Function() _clock;
  int _counter = 0;

  /// Returns a fresh annotation id.
  String nextAnnotationId() {
    final ms = _clock().millisecondsSinceEpoch;
    final c = _counter++;
    return 'an-$ms-$c';
  }
}
