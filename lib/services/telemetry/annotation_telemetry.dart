// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_telemetry/crux_telemetry.dart';
import 'package:netcrux/services/telemetry/netcrux_telemetry_vocabulary.dart';

/// Records that the user added a bookmark or an annotation.
///
/// Emitted after the dialog returns a created object, so a cancelled dialog
/// counts nothing. Nothing about the annotation itself is reported — its label,
/// its commentary and the element it is anchored to are all design data.
///
/// The event name is a literal here on purpose: the catalog conformance
/// scanner reads the quoted first argument of every telemetry event
/// construction out of the source, so a name assembled from a variable would
/// be invisible to it.
void recordAnnotationAdded(
  TelemetryService telemetry,
  NetcruxAnnotationKind kind,
) {
  telemetry.record(
    TelemetryEvent(
      'annotation.added',
      properties: <String, Object?>{'kind': telemetryEnumToken(kind)},
    ),
  );
}
