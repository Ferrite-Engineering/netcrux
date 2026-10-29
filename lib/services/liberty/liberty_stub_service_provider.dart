// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:netcrux/services/liberty/liberty_stub_service.dart';
import 'package:path_provider/path_provider.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'liberty_stub_service_provider.g.dart';

/// The [LibertyStubService] the elaboration pipeline turns a project's cell
/// libraries into Verilog stubs with, caching under the OS app-support
/// directory (`<appSupport>/liberty-cache/`). `keepAlive`, so every tab
/// shares one cache.
@Riverpod(keepAlive: true)
LibertyStubService libertyStubService(Ref ref) =>
    LibertyStubService(cacheBaseDirectory: getApplicationSupportDirectory);
