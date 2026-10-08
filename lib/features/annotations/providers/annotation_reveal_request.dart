import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'annotation_reveal_request.g.dart';

/// The annotation the Annotations panel should scroll to and flash, or
/// `null` when no request is pending.
///
/// Written by the badge click and the *Show Annotation* context-menu entry
/// through the active tab's container, read by the docked panel in the same
/// tab, and cleared by the panel once the row is in view. Per tab (in
/// `netcruxTabOverridesFactory`), like the annotations it names.
@Riverpod(keepAlive: true)
class AnnotationRevealRequest extends _$AnnotationRevealRequest {
  @override
  String? build() => null;

  /// Asks the panel to reveal annotation [id]. A repeat request for the
  /// same id after the panel answered the first one is a new request.
  // Not a setter: an intent method on a Notifier, paired with
  // [acknowledge]; a setter would read as plain assignment at call sites.
  // ignore: use_setters_to_change_properties
  void request(String id) => state = id;

  /// Clears the request for [id] once it has been answered. A newer
  /// request for another annotation is left in place.
  void acknowledge(String id) {
    if (state == id) state = null;
  }
}
