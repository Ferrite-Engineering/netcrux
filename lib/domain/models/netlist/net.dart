// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

/// Re-export shim. The netlist model moved to the shared
/// `crux_netlist` package so LintCrux's CDC engine works over the same
/// structure NetCrux's schematic is drawn from.
///
/// Kept as a shim rather than rewriting ~130 imports: the import path is
/// not the interesting part of the change, and a mechanical sweep of that
/// size buries the actual lift in noise.
library;

export 'package:crux_netlist/crux_netlist.dart';
