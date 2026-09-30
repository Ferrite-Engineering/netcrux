// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:netcrux/services/file_open/incoming_document_service.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'incoming_document_service_provider.g.dart';

/// The [IncomingDocumentService] the workspace screen listens to for
/// documents macOS opens while NetCrux is running. Tests override it with a
/// stream they control.
@Riverpod(keepAlive: true)
IncomingDocumentService incomingDocumentService(Ref ref) =>
    const IncomingDocumentService();
