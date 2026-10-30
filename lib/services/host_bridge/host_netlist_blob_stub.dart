// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';

/// A `data:` location holding [text], labelled [name] by its fragment.
String createHostNetlistLocation(String name, String text) {
  final data = Uri.dataFromString(
    text,
    mimeType: 'application/json',
    encoding: utf8,
  );
  return '$data#${Uri.encodeComponent(name)}';
}

/// Nothing to release for a `data:` location.
void releaseHostNetlistLocation(String location) {}
