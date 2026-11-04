#!/usr/bin/env bash
# install_compose.sh — install docker-compose (standalone v2) if missing.
# Used by the generic Sonya deployment scripts (validate/deploy call it automatically).
#
# Order:
#   1. already available ('docker compose' plugin or standalone docker-compose)?
#      -> nothing to do, exit 0
#   2. try to download from github (direct, then via HTTPS_PROXY/http_proxy if set)
#   3. if no internet -> print the exact manual steps (download on a laptop + scp)
#      and exit 1
#
# Version can be pinned: COMPOSE_VERSION=v2.39.2 bash install_compose.sh
set -euo pipefail

COMPOSE_VERSION="${COMPOSE_VERSION:-v2.39.2}"          # same as elephant
TARGET="/usr/local/bin/docker-compose"
[ "$(id -u)" -eq 0 ] || { echo "ERROR: run with sudo/root"; exit 1; }

# ---------------------------------------------------------------- 1) present? --
if docker compose version >/dev/null 2>&1; then
    echo "[OK] docker compose plugin already available:"
    docker compose version
    exit 0
fi
if command -v docker-compose >/dev/null 2>&1; then
    echo "[OK] standalone docker-compose already available:"
    docker-compose version
    exit 0
fi

ARCH="$(uname -m)"
case "$ARCH" in
    x86_64|amd64)  DL_ARCH="x86_64" ;;
    aarch64|arm64) DL_ARCH="aarch64" ;;
    *) echo "ERROR: unsupported arch ${ARCH}"; exit 1 ;;
esac

# ------------------------------------------------------------- 2) download -----
URL="https://github.com/docker/compose/releases/download/${COMPOSE_VERSION}/docker-compose-linux-${DL_ARCH}"
echo "docker-compose not found — installing standalone ${COMPOSE_VERSION} -> ${TARGET}"
PROXY_ARGS=()
if [ -n "${HTTPS_PROXY:-}${https_proxy:-}" ]; then
    P="${HTTPS_PROXY:-${https_proxy}}"
    PROXY_ARGS=(-x "$P")
    echo "using proxy: ${P}"
fi

if curl "${PROXY_ARGS[@]}" -fSL --connect-timeout 15 "$URL" -o "${TARGET}.tmp" 2>/dev/null \
   || curl "${PROXY_ARGS[@]}" -fSL --connect-timeout 15 "https://github.com/docker/compose/releases/latest/download/docker-compose-linux-${DL_ARCH}" -o "${TARGET}.tmp" 2>/dev/null; then
    mv "${TARGET}.tmp" "$TARGET"
    chmod +x "$TARGET"
    echo "[OK] installed:"
    "$TARGET" version
    exit 0
fi
rm -f "${TARGET}.tmp"

# ------------------------------------------------------ 3) no internet -> help -
echo
echo "ERROR: could not download docker-compose (no internet / no proxy configured)."
echo
echo "MANUAL INSTALL (on a laptop WITH internet):"
echo "  curl -SL \"$URL\" -o /tmp/docker-compose"
echo "  scp /tmp/docker-compose root@$(hostname -I 2>/dev/null | awk '{print $1}' || echo '<this-host>'):${TARGET}"
echo
echo "then on this host:"
echo "  chmod +x ${TARGET}"
echo "  ${TARGET} version"
exit 1
