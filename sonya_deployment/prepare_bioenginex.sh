#!/usr/bin/env bash
# prepare_bioenginex.sh — one-time preparation for the BioEngineX service.
# Run AFTER prepare_sonya.sh (needs the tenant .env to exist and be filled).
#
#   - fills safe defaults into bioenginex.env (never overwrites set values)
#   - cross-checks BIOENGINEX_SHARED_VOLUME == .env STORAGE_DIR (hard fail)
#   - creates BIOENGINEX_DATA_VOLUME if missing (never deletes/touches data)
#   - verifies JWT_SECRET is present in .env (shared secret, never generated)
#   - verifies NO_PROXY in app-extra.env references the container name
#   - enforces env hygiene + 600 root-only on bioenginex.env
#
# NEVER touches the sonya stack, containers, or any other tenant.
set -euo pipefail

DEPLOY_DIR="$(cd "$(dirname "$0")" && pwd)"
LOG="${DEPLOY_DIR}/PROGRESS.log"
log() { echo "[$(date -u +"%Y-%m-%dT%H:%M:%SZ")] $*" | tee -a "$LOG"; }

cd "$DEPLOY_DIR"
[ "$(id -u)" -eq 0 ] || { echo "ERROR: run with sudo/root"; exit 1; }
[ -f .env ]            || { echo "ERROR: .env missing — run prepare_sonya.sh first (wrong folder?)"; exit 1; }
[ -f bioenginex.env ]  || { echo "ERROR: bioenginex.env missing (wrong folder?)"; exit 1; }

get()    { grep "^${1}=" .env 2>/dev/null | head -1 | cut -d= -f2- | sed -e 's/[[:space:]]*#.*$//' | tr -d '\r'; }
getx()   { grep "^${1}=" bioenginex.env 2>/dev/null | head -1 | cut -d= -f2- | sed -e 's/[[:space:]]*#.*$//' | tr -d '\r'; }
setenvx(){ if grep -q "^${1}=" bioenginex.env 2>/dev/null; then
             sed -i.bak "s|^${1}=.*|${1}=${2}|" bioenginex.env && rm -f bioenginex.env.bak
           else echo "${1}=${2}" >> bioenginex.env; fi; }

log "=== prepare_bioenginex started (by ${SUDO_USER:-root}) ==="

# ------------------------------------------------------- 0) env hygiene ----
if grep -qE '^[A-Za-z_][A-Za-z0-9_]*=.*#' bioenginex.env; then
    echo "!! inline comments found on value lines in bioenginex.env:"
    grep -nE '^[A-Za-z_][A-Za-z0-9_]*=.*#' bioenginex.env | sed 's/^/    /'
    echo "   (docker passes these VERBATIM — the '#' becomes part of the value)"
    exit 1
fi

# --------------------------------------------- 1) defaults (no clobber) ---
ensure_default() { # KEY DEFAULT
  if [ -z "$(getx "$1")" ]; then setenvx "$1" "$2"; log "$1 missing -> default '$2' written"
  else log "$1 already set (kept): $(getx "$1")"; fi
}
ensure_default BIOENGINEX_CONTAINER_NAME bioturing-bioenginex
ensure_default BIOENGINEX_VERSION        2.0.2
ensure_default BIOENGINEX_HTTP_PORT       35576
ensure_default BIOENGINEX_RPC_PORT        35577
ensure_default NVIDIA_DISABLE_REQUIRE    true

# fixed mount targets — never defaulted, never optional (absolute-path contract)
ensure_default BIOENGINEX_SHARED_MOUNT /home/shared
ensure_default BIOENGINEX_DATA_MOUNT   /home/enginex

# --------------------------------------- 2) cross-checks vs the sonya .env -
JWT_SECRET="$(get JWT_SECRET)"
if [ -z "$JWT_SECRET" ] || [ "$JWT_SECRET" = "REDACTED" ]; then
    echo "  [FAIL] JWT_SECRET missing/placeholder in .env"
    echo "         (shared auth app <-> BioEngineX — copy verbatim from"
    echo "          the legacy container; it can NEVER be generated)"
    exit 1
fi
log "JWT_SECRET present in .env (shared with the app — not duplicated here)"

STORAGE_DIR="$(get STORAGE_DIR)"
[ -n "$STORAGE_DIR" ] || { echo "  [FAIL] STORAGE_DIR empty in .env"; exit 1; }

# ---------------------------------------------------------- 3) volumes ----
BIOENGINEX_SHARED_VOLUME="$(getx BIOENGINEX_SHARED_VOLUME)"
if [ -z "$BIOENGINEX_SHARED_VOLUME" ]; then
    setenvx BIOENGINEX_SHARED_VOLUME "$STORAGE_DIR"
    BIOENGINEX_SHARED_VOLUME="$STORAGE_DIR"
    log "BIOENGINEX_SHARED_VOLUME missing -> defaulted to .env STORAGE_DIR: $STORAGE_DIR"
elif [ "$BIOENGINEX_SHARED_VOLUME" != "$STORAGE_DIR" ]; then
    echo "  [FAIL] BIOENGINEX_SHARED_VOLUME (${BIOENGINEX_SHARED_VOLUME})"
    echo "         != STORAGE_DIR in .env (${STORAGE_DIR})"
    echo "         The app and BioEngineX MUST share the same /home/shared"
    echo "         partition. Fix one of the two files — they must match."
    exit 1
else
    log "BIOENGINEX_SHARED_VOLUME matches .env STORAGE_DIR (no drift)"
fi

BIOENGINEX_DATA_VOLUME="$(getx BIOENGINEX_DATA_VOLUME)"
[ -z "$BIOENGINEX_DATA_VOLUME" ] && {
    setenvx BIOENGINEX_DATA_VOLUME "${BIOENGINEX_SHARED_VOLUME}/bioenginex"
    BIOENGINEX_DATA_VOLUME="${BIOENGINEX_SHARED_VOLUME}/bioenginex"
    log "BIOENGINEX_DATA_VOLUME missing -> default <SHARED>/bioenginex: ${BIOENGINEX_DATA_VOLUME}"
}

if [ "$BIOENGINEX_DATA_VOLUME" = "$BIOENGINEX_SHARED_VOLUME" ]; then
    echo "  [FAIL] BIOENGINEX_DATA_VOLUME == BIOENGINEX_SHARED_VOLUME"
    echo "         (private data must be a distinct path — legacy default is"
    echo "          <SHARED>/bioenginex)"
    exit 1
fi

if [ -d "$BIOENGINEX_DATA_VOLUME" ]; then
    log "data dir exists (never touched): $BIOENGINEX_DATA_VOLUME"
else
    mkdir -p "$BIOENGINEX_DATA_VOLUME"
    chown -R www-data:www-data "$BIOENGINEX_DATA_VOLUME" 2>/dev/null || true
    chmod -R 755 "$BIOENGINEX_DATA_VOLUME" 2>/dev/null || true
    log "created: $BIOENGINEX_DATA_VOLUME (uid 33 — www-data, legacy parity)"
fi

# ------------------------------------------------ 4) NO_PROXY consistency -
CN="$(getx BIOENGINEX_CONTAINER_NAME)"
if grep -q "$CN" app-extra.env 2>/dev/null; then
    log "app-extra.env references '$CN' (NO_PROXY) — app can reach BioEngineX by name"
else
    echo "  [WARN] NO_PROXY in app-extra.env does not mention '$CN'"
    echo "         -> app->BioEngineX calls may try a corporate proxy. Add the"
    echo "            container name to NO_PROXY in app-extra.env."
fi

# ------------------------------------------------------ 5) permissions ----
chmod 600 bioenginex.env; chown root:root bioenginex.env
log "permissions set: bioenginex.env -> 600 root:root"

log "=== prepare_bioenginex finished. Next: validate_bioenginex.sh, then deploy_bioenginex.sh ==="
cat <<EOS

PREPARE BIOENGINEX DONE.
  next steps:
    1) sudo bash ${DEPLOY_DIR}/validate_bioenginex.sh
    2) sudo bash ${DEPLOY_DIR}/deploy_bioenginex.sh   (menu: 1=dry-run first)
  NOTE: the sonya stack must be UP before deploying (docker network
        '${PROJECT:-<COMPOSE_PROJECT_NAME>}_bioturing' must exist —
        deploy_sonya.sh creates it).
EOS
