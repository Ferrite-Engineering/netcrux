// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:netcrux/services/file_open/file_open_service.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'file_open_service_provider.g.dart';

/// Returns the [FileOpenService] used by the Welcome screen and the
/// project viewer's file-open actions. Test code overrides this provider
/// to inject a fake `FilePicker`.
@Riverpod(keepAlive: true)
FileOpenService fileOpenService(Ref ref) => FileOpenService();
