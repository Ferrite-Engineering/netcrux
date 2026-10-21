#!/usr/bin/env bash
# Copyright 2026 Ferrite Engineering LLC
# SPDX-License-Identifier: Apache-2.0

# Run the browser-only tests under headless Chrome via
# `flutter test --platform chrome`.
#
# The default VM `flutter test` compiles with `kIsWeb == false`, so the web
# viewer's branches — no Yosys, no isolate, no CXP transport — are unreachable
# there. Every test file under test/ that opts in with `@TestOn('browser')` is
# skipped by the VM runner and runs here instead; nothing else runs them.
#
# Usage:
#   tool/run_web_tests.sh                     # every @TestOn('browser') file
#   tool/run_web_tests.sh test/a_web_test.dart [more...]
#
# Requires a Chrome that `flutter test --platform chrome` can launch, and the
# web layout engine built into web/wasm/ (`dart run tool/build_web_wasm.dart`).
# The browser test server serves test/ and nothing of web/, so the engine is
# staged into test/.web_wasm/ (git-ignored), where the layout tests load it.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

for f in elk_wasm_worker.js elk_wasm.js elk_wasm_bg.wasm; do
  if [[ ! -f "web/wasm/$f" ]]; then
    echo "web/wasm/$f is missing: run 'dart run tool/build_web_wasm.dart' first." >&2
    exit 1
  fi
done
rm -rf test/.web_wasm
mkdir -p test/.web_wasm/no_module
cp web/wasm/elk_wasm_worker.js web/wasm/elk_wasm.js web/wasm/elk_wasm_bg.wasm test/.web_wasm/
# The worker without its module, for the load-failure fallback test.
cp web/wasm/elk_wasm_worker.js test/.web_wasm/no_module/

if [[ $# -gt 0 ]]; then
  files=("$@")
else
  files=()
  while IFS= read -r f; do
    files+=("$f")
  done < <(grep -rl --include='*_test.dart' "@TestOn('browser')" test | sort)
fi

if [[ ${#files[@]} -eq 0 ]]; then
  echo "No @TestOn('browser') tests found under test/." >&2
  exit 1
fi

flutter test --platform chrome "${files[@]}"
