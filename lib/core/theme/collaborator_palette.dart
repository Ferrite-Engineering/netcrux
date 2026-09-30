// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/material.dart';

/// Eight visually distinct colours (one per `colorIndex` value 0–7) for
/// collaboration presence — remote cursors, their name labels, and the outline
/// drawn around what a remote participant has selected.
///
/// **Deliberately not byte-identical to WaveCrux's palette**, and the reason is
/// the surface rather than taste. WaveCrux's list opens with amber
/// (`0xFFFFB300`) and carries a light blue (`0xFF42A5F5`); on a schematic those
/// are the two colours a reader is already trained to read as something else —
/// [NetcruxColors.selectionAccent] is amber `0xFFFFB627` and
/// [NetcruxColors.coneAccent] is blue `0xFF3DA5FF`. A colleague's cursor the
/// same colour as your own selection is not a cosmetic problem: it makes "what
/// is highlighted, and did I do it?" unanswerable at a glance, which is the one
/// question a shared schematic has to keep answerable.
///
/// So the *shape* is WaveCrux's — eight slots, `colorIndex` 0–7, the same
/// [collaboratorColor] helper, wrapping modulo the length — and only the hues
/// move.
///
/// Lives under `core/theme/` rather than beside the overlay that first needed
/// it: it is a palette, not a widget, and the import-layering guard refuses a
/// feature reaching into a sibling's `widgets/`.
const kCollaboratorPalette = <Color>[
  Color(0xFF66BB6A), // light green
  Color(0xFFEC407A), // pink / rose
  Color(0xFFAB47BC), // purple
  Color(0xFF26C6DA), // teal
  Color(0xFFD4E157), // lime
  Color(0xFFFF7043), // coral
  Color(0xFF7986CB), // indigo
  Color(0xFF8D6E63), // warm grey-brown
];

/// The palette colour for a participant's `colorIndex`.
///
/// Wraps modulo the palette length, so an index that arrived over the wire from
/// a peer running a build with a longer palette can never throw.
Color collaboratorColor(int colorIndex) =>
    kCollaboratorPalette[colorIndex % kCollaboratorPalette.length];
