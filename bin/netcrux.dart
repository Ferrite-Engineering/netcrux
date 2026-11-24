// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0

// The headless `netcrux` binary: `info`, `search` and `connections` with
// `--json`, and `mcp`, which serves them to an agent. Built by
// `tool/build_cli.sh`; its import closure holds no Flutter
// (`test/static/headless_cli_closure_test.dart`).

import 'dart:io';

import 'package:netcrux/headless/netcrux_cli.dart';

Future<void> main(List<String> args) async {
  final code = await NetCruxCli().run(args, out: stdout, err: stderr);
  await stdout.flush();
  await stderr.flush();
  // A parse worker or a Yosys child would keep the process alive otherwise.
  exit(code);
}
