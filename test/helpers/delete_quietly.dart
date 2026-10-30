// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

/// Deletes [dir] and what is in it, ignoring a file the platform still holds
/// open (Windows keeps a file a killed worker was reading until the handle is
/// collected). A leftover temporary directory is not what a test is about.
void deleteQuietly(Directory dir) {
  try {
    dir.deleteSync(recursive: true);
  } on FileSystemException {
    // Best effort.
  }
}
