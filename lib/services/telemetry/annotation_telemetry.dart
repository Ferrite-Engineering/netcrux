// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:crux_telemetry/crux_telemetry.dart';

/// Records that the user added an annotation.
///
/// Emitted after the dialog returns a created object, so a cancelled dialog
/// counts nothing. Nothing about the annotation itself is reported — its title,
/// its body and the element it is anchored to are all design data.
///
/// The event name is a literal here on purpose: the catalog conformance
/// scanner reads the quoted first argument of every telemetry event
/// construction out of the source, so a name assembled from a variable would
/// be invisible to it.
void recordAnnotationAdded(TelemetryService telemetry) {
  telemetry.record(TelemetryEvent('annotation.added'));
}
