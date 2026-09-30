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

echo "=== pub get ==="
flutter pub get

echo "=== Code generation (Riverpod) ==="
dart run build_runner build --delete-conflicting-outputs

echo "=== l10n ==="
flutter gen-l10n

echo "=== flutter build web (release) ==="
flutter build web --release

echo "=== Deploy to Cloudflare (netcrux-app -> app.netcrux.app) ==="
if command -v wrangler >/dev/null 2>&1; then
  wrangler deploy
else
  npx --yes wrangler deploy
fi

echo ""
echo "Deployed. Live at https://app.netcrux.app/"
echo "(First deploy provisions the custom domain — DNS/SSL may take a minute.)"
