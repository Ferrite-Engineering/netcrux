// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';

/// NetCrux brand color tokens.
///
/// The accent color is a muted amber/orange, distinct from WaveCrux's
/// teal/cyan family and chosen because oscilloscope and logic-analyzer
/// convention puts amber on "trace" — fitting for a tool whose hero feature
/// is signal tracing through a netlist.
abstract final class NetcruxColors {
  /// Brand seed color used to derive the Material 3 [ColorScheme]. A muted
  /// amber/orange, deliberately darker and less saturated than Flutter's
  /// `Colors.amber` so it reads as an engineering-tool accent rather than
  /// a warning.
  static const Color brandSeed = Color(0xFFD4A017);

  /// Pure-black canvas background used by the schematic surface in dark
  /// mode. Matches the WaveCrux convention of near-black engineering-tool
  /// backgrounds.
  static const Color darkCanvasBackground = Color(0xFF0F0F10);

  /// Light-mode canvas background.
  static const Color lightCanvasBackground = Color(0xFFFAFAFA);

  /// Selection / focus accent — a saturated lift on the brand amber
  /// so selected cells and ports read at a glance against the canvas.
  /// Distinct from [brandSeed] (used for chrome) so the accent doesn't
  /// blend into the toolbar.
  static const Color selectionAccent = Color(0xFFFFB627);

  /// Faint fill applied over a selected cell's body so the
  /// outline alone isn't carrying the entire signal. Designed to read
  /// over both light and dark backgrounds.
  static const Color selectionFillTint = Color(0x33FFB627);

  /// Bright core stroke for a SELECTED wire. A warm near-white — a hair
  /// off pure white so it stays on-brand — deliberately far brighter than
  /// both the default warm-gold wire and the amber [selectionAccent],
  /// which sits almost on the brand-gold hue and made a selected bus
  /// nearly invisible. Painted on top of [selectedWireGlow] so a selected
  /// net reads as a "lit" wire without the user having to zoom in.
  static const Color selectedWireCore = Color(0xFFFFF3D0);

  /// Semi-transparent amber halo drawn UNDER [selectedWireCore] as a
  /// wider underlay stroke — the glow that makes a selected wire pop off
  /// the warm-gold-on-dark canvas. Low enough alpha that crossing/adjacent
  /// wires stay legible through it.
  static const Color selectedWireGlow = Color(0x66FFC24D);

  /// Positive cone-of-influence / trace accent — the color the painter
  /// POSITIVELY highlights cone (fanin/fanout) cells and their wires with
  /// while an overlay is active, so the cone reads as a lit sub-graph
  /// rather than merely "the part that wasn't dimmed". A bright azure,
  /// deliberately a different HUE from the amber [selectionAccent] and the
  /// warm-gold default wire so a cone element is unmistakable at normal
  /// zoom and never confused with a selection.
  static const Color coneAccent = Color(0xFF3DA5FF);

  /// Faint azure fill laid over a cone cell's body (all LOD bands) so the
  /// [coneAccent] outline isn't carrying the entire signal — the mid/detail
  /// symbol body is otherwise painted identically whether or not a cell is
  /// in the cone. Reads over both light and dark canvases.
  static const Color coneFillTint = Color(0x333DA5FF);

  /// Cone-of-influence dim — what every non-highlighted element is
  /// painted over while a fanin/fanout overlay is active. Low alpha so
  /// dimmed elements stay legible but visually fall behind.
  static const Color overlayDimVeil = Color(0xB31A1A1A);

  /// Dim text/stroke color applied to non-highlighted elements during
  /// trace overlays. Distinct from [overlayDimVeil] because some
  /// elements (boundary ports, dashed line indicators) draw colored
  /// strokes rather than a veil over a fill.
  static const Color overlayDimStroke = Color(0x66808080);
}
