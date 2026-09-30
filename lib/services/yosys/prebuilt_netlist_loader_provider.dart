// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:netcrux/services/yosys/prebuilt_netlist_loader.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'prebuilt_netlist_loader_provider.g.dart';

/// The [PrebuiltNetlistLoader] the elaboration pipeline uses for a netlist
/// JSON design. Test code overrides this to feed a document without touching
/// the filesystem or the network.
@Riverpod(keepAlive: true)
PrebuiltNetlistLoader prebuiltNetlistLoader(Ref ref) =>
    const PrebuiltNetlistLoader();

/// Whether this build can elaborate HDL at all.
///
/// `false` in the browser, which cannot spawn the Yosys or GHDL subprocess:
/// there every design is a pre-built netlist, whatever its location is
/// called, and nothing probes for Yosys. Overridable so the browser branch is
/// testable on the VM.
@Riverpod(keepAlive: true)
bool hdlElaborationSupported(Ref ref) => !kIsWeb;
