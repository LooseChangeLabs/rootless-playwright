#!/usr/bin/env bash
# rootless-playwright: install Playwright's browser system dependencies without root.
#
# Problem: `playwright install --with-deps` and `playwright install-deps` both
# shell out to `apt-get install`, which requires root. In containers, CI
# runners, and restricted dev sandboxes without passwordless sudo, that fails
# outright. This script gets the same libraries onto disk using
# `apt-get download` + `dpkg-deb -x` (both work unprivileged), then points
# the browser at them via LD_LIBRARY_PATH. No root, no sudo, nothing touched
# outside the prefix directory.
#
# Usage:
#   ./install.sh [browser] [prefix]
#   browser: chromium (default) | firefox | webkit
#   prefix:  install directory (default: ~/.local/rootless-playwright)
set -euo pipefail

BROWSER="${1:-chromium}"
PREFIX="${2:-$HOME/.local/rootless-playwright}"
WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT

log() { printf '\033[1;34m==>\033[0m %s\n' "$1"; }
err() { printf '\033[1;31merror:\033[0m %s\n' "$1" >&2; }

command -v npx >/dev/null 2>&1 || { err "npx not found — Node.js must already be installed"; exit 1; }
command -v apt-get >/dev/null 2>&1 || { err "apt-get not found — this script targets Debian/Ubuntu-based systems"; exit 1; }
command -v dpkg-deb >/dev/null 2>&1 || { err "dpkg-deb not found"; exit 1; }

if sudo -n true 2>/dev/null; then
  log "Passwordless sudo is available — you don't need this script."
  log "Just run: npx playwright install --with-deps $BROWSER"
  exit 0
fi

log "Discovering required system packages for $BROWSER..."
DEPS_OUTPUT="$(npx --yes playwright install-deps "$BROWSER" --dry-run 2>&1 || true)"

mapfile -t PKGS < <(printf '%s\n' "$DEPS_OUTPUT" | sed -n '/Missing system dependencies/,$p' | tail -n +2 | sed 's/^[[:space:]]*//' | grep -v '^$')

if [ "${#PKGS[@]}" -eq 0 ]; then
  log "No missing packages reported (or already satisfied). Proceeding to browser binary install."
else
  log "Found ${#PKGS[@]} missing packages. Downloading (unprivileged, via apt-get download)..."
  mkdir -p "$PREFIX"
  cd "$WORKDIR"
  FAILED=()
  for pkg in "${PKGS[@]}"; do
    if ! apt-get download "$pkg" >/dev/null 2>&1; then
      FAILED+=("$pkg")
    fi
  done
  if [ "${#FAILED[@]}" -gt 0 ]; then
    err "Could not download: ${FAILED[*]}"
    err "These may be virtual/meta packages or unavailable in your apt sources — continuing with the rest."
  fi

  log "Extracting packages into $PREFIX (no root — just unpacking .deb contents)..."
  for deb in *.deb; do
    [ -e "$deb" ] || continue
    dpkg-deb -x "$deb" "$PREFIX"
  done
  cd - >/dev/null
fi

log "Computing library search path..."
LIB_DIRS="$(find "$PREFIX" -name '*.so*' -exec dirname {} \; 2>/dev/null | sort -u | tr '\n' ':')"
LIB_DIRS="${LIB_DIRS%:}"

mkdir -p "$PREFIX"
ENV_FILE="$PREFIX/env.sh"
cat > "$ENV_FILE" <<EOF
# Source this file (or add to your shell rc) to use the rootless browser libs:
#   source "$ENV_FILE"
export LD_LIBRARY_PATH="$LIB_DIRS\${LD_LIBRARY_PATH:+:\$LD_LIBRARY_PATH}"
EOF
log "Wrote $ENV_FILE"

# shellcheck disable=SC1090
source "$ENV_FILE"

log "Installing $BROWSER binary via Playwright (downloads the browser itself, not system libs)..."
npx --yes playwright install "$BROWSER"

log "Verifying $BROWSER launches headlessly..."
VERIFY_JS="$WORKDIR/verify.js"
cat > "$VERIFY_JS" <<'EOF'
const { chromium, firefox, webkit } = require('playwright-core');
const engines = { chromium, firefox, webkit };
const which = process.argv[2] || 'chromium';
(async () => {
  const browser = await engines[which].launch({ headless: true });
  const page = await browser.newPage();
  await page.goto('about:blank');
  await browser.close();
  console.log('OK');
})().catch((e) => { console.error('FAIL:', e.message); process.exit(1); });
EOF

if ! npm ls playwright-core --prefix "$WORKDIR" >/dev/null 2>&1; then
  (cd "$WORKDIR" && npm install playwright-core --no-save --silent >/dev/null 2>&1) || true
fi

if node "$VERIFY_JS" "$BROWSER" 2>&1 | grep -q OK; then
  log "Success — $BROWSER launches without root."
  log "Add this to your shell profile so it's automatic next time:"
  echo ""
  echo "    source \"$ENV_FILE\""
  echo ""
else
  err "Browser did not launch. Run with the libraries sourced and check the error:"
  echo "    source \"$ENV_FILE\" && node \"$VERIFY_JS\" \"$BROWSER\""
fi
