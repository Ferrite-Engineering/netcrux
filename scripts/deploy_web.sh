#!/usr/bin/env bash
# Copyright 2026 Ferrite Engineering LLC
# SPDX-License-Identifier: Apache-2.0

# Build + deploy the OPEN-CORE NetCrux read-only web viewer to Cloudflare
# (app.netcrux.app).
#
# Cloudflare Workers Static Assets, same model as the WaveCrux app and the
# marketing sites. The viewer ships open-core with no beta expiry — redeploy to
# ship updates to everyone.
#
# One-time setup:
#   - `wrangler login` (OAuth) to authenticate this machine to the Cloudflare
#     account that holds the netcrux.app zone (it already hosts the marketing
#     site).
#   - app.netcrux.app is provisioned automatically from wrangler.jsonc on
#     first deploy.
#
# Run from the repo root:
#   ./scripts/deploy_web.sh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

# Refuse a release whose version disagrees with the beta flag compiled from
# the pinned crux-shared (a 1.x build with the beta still on ships every paid
# feature free). See scripts/check_beta_period.sh.
"$REPO_ROOT/scripts/check_beta_period.sh"

echo "=== pub get ==="
flutter pub get

echo "=== Code generation (Riverpod) ==="
dart run build_runner build --delete-conflicting-outputs

echo "=== l10n ==="
flutter gen-l10n

echo "=== Layout engine (Rust to WebAssembly) ==="
# Needs the wasm32-unknown-unknown target and wasm-pack. A deploy without it
# would still lay out, on the elkjs fallback, so it is a hard step here.
dart run tool/build_web_wasm.dart

echo "=== flutter build web (release) ==="
flutter build web --release
test -f build/web/wasm/elk_wasm_bg.wasm

echo "=== Deploy to Cloudflare (netcrux-app -> app.netcrux.app) ==="
if command -v wrangler >/dev/null 2>&1; then
  wrangler deploy
else
  npx --yes wrangler deploy
fi

echo ""
echo "Deployed. Live at https://app.netcrux.app/"
echo "(First deploy provisions the custom domain — DNS/SSL may take a minute.)"
