// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

import 'package:netcrux/domain/enums/netlist_reader_choice.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'netlist_reader_provider.g.dart';

/// Session-scope choice of netlist reader, set by `bootstrap()` from the
/// `--netlist-reader <yosys|native>` CLI flag.
///
/// When it names a reader it wins over a project's `netlistReader` key and
/// over Settings → Engines → Native gate-level reader, so one file can be
/// opened both ways from the command line to compare them. `null` means the
/// flag was not given (or named nothing this build knows).
@Riverpod(keepAlive: true)
NetlistReaderChoice? cliNetlistReaderOverride(Ref ref) => null;
