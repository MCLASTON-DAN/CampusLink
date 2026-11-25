#!/usr/bin/env bash
# Build command for Cloudflare Workers Builds (Settings -> Build).
# Cloudflare has no Flutter, so we fetch it, build the web app into ./dist,
# then Cloudflare's deploy command (npx wrangler deploy) publishes ./dist.
# Needs build variables SUPABASE_URL and SUPABASE_ANON_KEY (the public anon key).
set -euo pipefail

if [ -z "${SUPABASE_URL:-}" ] || [ -z "${SUPABASE_ANON_KEY:-}" ]; then
  echo "ERROR: add SUPABASE_URL and SUPABASE_ANON_KEY under Settings -> Build -> Variables and secrets." >&2
  exit 1
fi

FLUTTER_DIR="${HOME}/flutter"
if [ ! -x "${FLUTTER_DIR}/bin/flutter" ]; then
  git clone --depth 1 -b stable https://github.com/flutter/flutter.git "${FLUTTER_DIR}"
fi
export PATH="${FLUTTER_DIR}/bin:${PATH}"
flutter --version
flutter config --no-analytics >/dev/null 2>&1 || true

flutter pub get
# Safety gate: never publish code that fails its checks or tests.
flutter analyze --no-fatal-infos
flutter test
flutter build web --release \
  --base-href "/" \
  --no-web-resources-cdn \
  --dart-define=SUPABASE_URL="${SUPABASE_URL}" \
  --dart-define=SUPABASE_ANON_KEY="${SUPABASE_ANON_KEY}"

test -f build/web/main.dart.js
if grep -q 'FLUTTER_BASE_HREF' build/web/index.html; then
  echo "ERROR: base href was not filled in." >&2
  exit 1
fi

rm -rf dist
cp -r build/web dist
echo "Built OK -> dist/"
