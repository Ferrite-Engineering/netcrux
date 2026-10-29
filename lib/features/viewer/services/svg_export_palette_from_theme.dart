// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';
import 'package:netcrux/services/export/svg_exporter.dart';

/// The [SvgExportPalette] of [theme]: each mark in the colour the canvas
/// paints it in under that theme, so an export matches the canvas.
SvgExportPalette svgExportPaletteFromTheme(ThemeData theme) {
  final scheme = theme.colorScheme;
  return SvgExportPalette(
    background: cssHexColor(scheme.surface),
    body: cssHexColor(scheme.surfaceContainerHighest),
    stroke: cssHexColor(scheme.onSurface),
    label: cssHexColor(scheme.onSurface),
    wire: cssHexColor(scheme.onSurfaceVariant),
    port: cssHexColor(scheme.tertiary),
    pin: cssHexColor(scheme.primary),
    undriven: cssHexColor(scheme.error),
  );
}

/// [color] as a CSS `#RRGGBB` string; the alpha channel is dropped, since
/// every colour scheme role is opaque.
String cssHexColor(Color color) {
  final rgb = color.toARGB32() & 0xFFFFFF;
  return '#${rgb.toRadixString(16).padLeft(6, '0').toUpperCase()}';
}
