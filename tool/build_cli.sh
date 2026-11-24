#!/usr/bin/env bash
# Copyright 2026 Ferrite Engineering LLC
# SPDX-License-Identifier: Apache-2.0

# Build the headless `netcrux` binary: `info`, `search`, `connections` and
# `mcp`.
#
# The binary reads Yosys JSON netlists itself and elaborates HDL with the
# Yosys on PATH, as the app does; it loads no native library of its own, so
# the archive is the executable and whatever `dart build cli` puts beside it:
#
#   <output-dir>/bundle/bin/netcrux        (netcrux.exe on Windows)
#   <output-dir>/bundle/lib/               (hook assets, if any)
#
# Why `dart build cli` and not `dart compile exe`: `dart compile` refuses to
# run when any package in the resolution declares a native build hook, and
# `objective_c` does, pulled in by a Flutter plugin the desktop app needs and
# this binary never touches (resolution is per package, not per entry point).
# `dart build cli` compiles the same AOT executable. WaveCrux, LintCrux and
# SimCrux build their binaries the same way.
#
# This script is also a proof that the binary's import closure is
# Flutter-free: a `package:flutter/...` import anywhere in it fails the
# compile here (`test/static/headless_cli_closure_test.dart` catches it
# sooner).
#
# Usage:
#   tool/build_cli.sh [output-dir]        # default: build/cli
set -euo pipefail

cd "$(dirname "$0")/.."

OUT_DIR="${1:-build/cli}"
BUNDLE="${OUT_DIR}/bundle"

case "$(uname -s)" in
  Darwin|Linux) EXE="netcrux" ;;
  MINGW*|MSYS*|CYGWIN*) EXE="netcrux.exe" ;;
  *) echo "error: no build for $(uname -s)" >&2; exit 1 ;;
esac

echo "==> dart build cli -t bin/netcrux.dart -o ${OUT_DIR}"
dart build cli -t bin/netcrux.dart -o "${OUT_DIR}"

BIN="${BUNDLE}/bin/${EXE}"
if [[ ! -x "${BIN}" ]]; then
  echo "error: expected executable at ${BIN}" >&2
  exit 1
fi

echo "==> smoke test"
"${BIN}" --version
"${BIN}" --help > /dev/null
# Reads the fixture netlist on the parse worker, so the isolate code runs.
"${BIN}" info spec/fixtures/counter.json --json > /dev/null

echo "==> built ${BIN}"
