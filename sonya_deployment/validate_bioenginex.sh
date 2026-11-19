#!/usr/bin/env bash
# validate_bioenginex.sh — pre-flight + post-deploy validation for BioEngineX.
# READ-ONLY: never starts/stops/removes anything, never modifies any file.
#
# Checks (pre-deploy): files, env hygiene, all bioenginex.env values, shared
#   values cross-checked vs .env, volume mount safety (drift + targets),
#   network existence, host ports, GPU, image presence, container name.
# Checks (post-deploy): running container's ACTUAL mounts vs the env files,
#   mutual DNS resolution (app <-> BioEngineX), TCP reachability on the
#   internal path, shared-volume hand-off probe.
#
# Exit 0 = ready, exit 1 = [FAIL] items present.
set -uo pipefail

DEPLOY_DIR="$(cd "$(dirname "$0")" && pwd)"
FAILS=0; WARNS=0
ok()   { echo "  [ OK ] $*"; }
warn() { echo "  [WARN] $*"; WARNS=$((WARNS+1)); }
fail() { echo "  [FAIL] $*"; FAILS=$((FAILS+1)); }
hdr()  { echo; echo "== $* =="; }
get()  { grep "^${1}=" .env 2>/dev/null | head -1 | cut -d= -f2- | sed -e 's/[[:space:]]*#.*$//' | tr -d '\r' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//'; }
getx() { grep "^${1}=" bioenginex.env 2>/dev/null | head -1 | cut -d= -f2- | sed -e 's/[[:space:]]*#.*$//' | tr -d '\r' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//'; }
cd "$DEPLOY_DIR" || { echo "ERROR: ${DEPLOY_DIR} not found"; exit 1; }

# ------------------------------------------------------------ 1) files ------
hdr "1. Files"
for f in .env app-extra.env bioenginex.env deploy_bioenginex.sh; do
    [ -f "$f" ] && ok "$f present" || fail "$f MISSING"
done
[ -f bioenginex.env ] && {
    m="$(stat -f %Lp bioenginex.env 2>/dev/null || stat -c %a bioenginex.env 2>/dev/null)"
    [ "$m" = "600" ] && ok "bioenginex.env mode 600 (root-only)" \
                     || warn "bioenginex.env mode is $m, expected 600"
}

# ------------------------------------------------------ 2) env hygiene ------
hdr "2. Env hygiene (no inline comments on value lines)"
if grep -qE '^[A-Za-z_][A-Za-z0-9_]*=.*#' bioenginex.env; then
    fail "bioenginex.env has inline '#' on value lines (docker passes it verbatim)"
    grep -nE '^[A-Za-z_][A-Za-z0-9_]*=.*#' bioenginex.env | sed 's/^/        /'
else
    ok "bioenginex.env clean"
fi

# --------------------------------------------------- 3) required values ------
hdr "3. bioenginex.env values"
CN="$(getx BIOENGINEX_CONTAINER_NAME)"
for k in BIOENGINEX_CONTAINER_NAME BIOENGINEX_VERSION BIOENGINEX_HTTP_PORT \
         BIOENGINEX_RPC_PORT BIOENGINEX_SHARED_VOLUME BIOENGINEX_DATA_VOLUME \
         BIOENGINEX_SHARED_MOUNT BIOENGINEX_DATA_MOUNT; do
    v="$(getx "$k")"
    [ -n "$v" ] && ok "$k=$v" || fail "$k is empty"
done
for k in BIOENGINEX_HTTP_PORT BIOENGINEX_RPC_PORT; do
    v="$(getx "$k")"
    [ "$v" -ge 1 ] 2>/dev/null && [ "$v" -le 65535 ] 2>/dev/null \
        && ok "$k numeric ($v)" || fail "$k='$v' is not a valid port number"
done

# ------------------------------------- 4) shared values from the sonya .env -
hdr "4. Shared values (single source of truth in .env)"
JWT_SECRET="$(get JWT_SECRET)"
[ -n "$JWT_SECRET" ] && [ "$JWT_SECRET" != "REDACTED" ] \
    && ok "JWT_SECRET present in .env (exported to BioEngineX at deploy time)" \
    || fail "JWT_SECRET missing in .env — copy verbatim from legacy"
STORAGE_DIR="$(get STORAGE_DIR)"
[ -n "$STORAGE_DIR" ] && ok "STORAGE_DIR=$STORAGE_DIR (app's /home/shared)" \
                        || fail "STORAGE_DIR empty in .env"
PROJECT="$(get COMPOSE_PROJECT_NAME)"
[ -n "$PROJECT" ] && ok "COMPOSE_PROJECT_NAME=$PROJECT" || fail "COMPOSE_PROJECT_NAME empty in .env"
APP_CN="$(get CONTAINER_NAME)"
[ -n "$APP_CN" ] && ok "app container: $APP_CN" || fail "CONTAINER_NAME empty in .env"

# ------------------------------------------------------ 5) volume mounts ----
hdr "5. Volume mounts"
SHARED_V="$(getx BIOENGINEX_SHARED_VOLUME)"; DATA_V="$(getx BIOENGINEX_DATA_VOLUME)"
SHARED_M="$(getx BIOENGINEX_SHARED_MOUNT)";  DATA_M="$(getx BIOENGINEX_DATA_MOUNT)"

# 5a) drift check — shared volume MUST be the same partition the app uses
[ "$SHARED_V" = "$STORAGE_DIR" ] \
    && ok "BIOENGINEX_SHARED_VOLUME == .env STORAGE_DIR (same partition as app)" \
    || fail "BIOENGINEX_SHARED_VOLUME ('$SHARED_V') != .env STORAGE_DIR ('$STORAGE_DIR') — they MUST match"

# 5b) mount targets must be the legacy paths (absolute-path contract)
[ "$SHARED_M" = "/home/shared" ] && ok "shared mount target: /home/shared" \
    || fail "BIOENGINEX_SHARED_MOUNT='$SHARED_M' — must be /home/shared (absolute-path contract)"
[ "$DATA_M" = "/home/enginex" ] && ok "data mount target: /home/enginex" \
    || fail "BIOENGINEX_DATA_MOUNT='$DATA_M' — must be /home/enginex"

# 5c) private data must be a distinct path from the shared volume
[ "$DATA_V" != "$SHARED_V" ] && ok "data volume is a distinct path" \
    || fail "BIOENGINEX_DATA_VOLUME == BIOENGINEX_SHARED_VOLUME (same dir mounted twice)"

# 5d) existence + writability
for d in "$SHARED_V" "$DATA_V"; do
    [ -d "$d" ] && ok "dir exists: $d" || fail "dir missing: $d (run prepare_bioenginex.sh)"
    [ -w "$d" ] && ok "dir writable: $d" || fail "dir not writable: $d"
done

# 5e) if BioEngineX is already running — verify its ACTUAL mounts match the env
if docker ps --format '{{.Names}}' 2>/dev/null | grep -qx "$CN"; then
    M="$(docker inspect -f '{{range .Mounts}}{{.Source}}->{{.Destination}} {{end}}' "$CN" 2>/dev/null)"
    echo "$M" | grep -q "${SHARED_V}->${SHARED_M}" && ok "running container mounts shared volume correctly" \
                                                    || fail "running container shared mount mismatch: $M"
    echo "$M" | grep -q "${DATA_V}->${DATA_M}" && ok "running container mounts data volume correctly" \
                                                  || fail "running container data mount mismatch: $M"
    docker inspect -f '{{range .Mounts}}{{if eq .Destination "/home/shared"}}RW={{.RW}} {{end}}{{end}}' "$CN" 2>/dev/null \
        | grep -q 'RW=true' && ok "shared mount is rw" || warn "shared mount is not rw"
else
    ok "BioEngineX not running (pre-deploy mode) — live mount checks skipped"
fi

# ------------------------------------------------------- 6) network --------
hdr "6. Network & mutual reachability"
NETWORK="${PROJECT}_bioturing"
if docker network inspect "$NETWORK" >/dev/null 2>&1; then
    ok "network '$NETWORK' exists"
    ON_NET="$(docker network inspect -f '{{range .Containers}}{{.Name}} {{end}}' "$NETWORK" 2>/dev/null)"
    echo "$ON_NET" | tr ' ' '\n' | grep -qx "$APP_CN" \
        && ok "app container is on the network" \
        || fail "app container NOT on network — is the sonya stack up?"
    if echo "$ON_NET" | tr ' ' '\n' | grep -qx "$CN"; then
        ok "BioEngineX container is on the network"
        # DNS resolution each way — the real proof they can reach each other
        docker exec "$CN" getent hosts "$APP_CN" >/dev/null 2>&1 \
            && ok "BioEngineX resolves the app by name" \
            || fail "BioEngineX cannot resolve '$APP_CN' (DNS on the shared network)"
        docker exec "$APP_CN" getent hosts "$CN" >/dev/null 2>&1 \
            && ok "app resolves BioEngineX by name ($CN)" \
            || fail "app cannot resolve '$CN' — check container name vs NO_PROXY in app-extra.env"
        # TCP on the internal path (the traffic path — NOT the host ports)
        if docker exec "$APP_CN" timeout 3 bash -c "</dev/tcp/${CN}/35576" 2>/dev/null; then
            ok "app can open TCP to BioEngineX :35576 (internal path)"
        else
            warn "app TCP probe to ${CN}:35576 failed (no bash in app container, or blocked) — verify from the UI"
        fi
        # shared-volume hand-off probe
        docker exec "$APP_CN" sh -c 'echo ok > /home/shared/.bt_conn_test' 2>/dev/null \
          && docker exec "$CN" sh -c 'cat /home/shared/.bt_conn_test >/dev/null 2>&1; rm -f /home/shared/.bt_conn_test' 2>/dev/null \
          && ok "shared volume visible to both containers" \
          || fail "shared volume hand-off failed — containers see different /home/shared"
    else
        warn "BioEngineX not attached yet — deploy will attach it (re-attach via deploy menu 5 after any sonya redeploy)"
    fi
else
    fail "network '$NETWORK' not found — start the sonya stack first (deploy_sonya.sh), then re-run"
fi

# --------------------------------------------------------- 7) ports --------
hdr "7. Host ports"
for p in "$(getx BIOENGINEX_HTTP_PORT)" "$(getx BIOENGINEX_RPC_PORT)"; do
    if ss -tln 2>/dev/null | awk '{print $4}' | grep -qE ":${p}\$"; then
        HOLDER="$(docker ps --format '{{.Names}} {{.Ports}}' | grep -E ":${p}->" | awk '{print $1}' | head -1)"
        if [ "$HOLDER" = "$CN" ]; then
            ok "port ${p} held by our own BioEngineX container (redeploy path)"
        else
            fail "port ${p} already in use (holder: ${HOLDER:-unknown host process})"
        fi
    else
        ok "port ${p} free"
    fi
done

# --------------------------------------------------------- 8) GPU ---------
hdr "8. GPU (BioEngineX runs --gpus all)"
if command -v nvidia-smi >/dev/null 2>&1; then
    N="$(nvidia-smi --list-gpus 2>/dev/null | wc -l | tr -d ' ')"
    [ "$N" -ge 1 ] && ok "nvidia-smi sees ${N} GPU(s)" || fail "nvidia-smi present but no GPUs visible"
    docker info 2>/dev/null | grep -qi nvidia \
        && ok "nvidia runtime available to docker" \
        || warn "nvidia runtime not detected in docker info — check 'nvidia-container-toolkit'"
else
    warn "nvidia-smi not found — BioEngineX needs GPUs (fine if this machine is just for editing the config)"
fi

# --------------------------------------------- 9) image + name + NO_PROXY --
hdr "9. Image, container name, NO_PROXY"
IMAGE="bioturing/bioenginex:$(getx BIOENGINEX_VERSION)"
if docker image inspect "$IMAGE" >/dev/null 2>&1; then
    ok "image present locally: $IMAGE"
else
    warn "image not local yet: $IMAGE — deploy will pull it (needs registry access/proxy)"
fi
if docker ps -a --format '{{.Names}}' 2>/dev/null | grep -qx "$CN"; then
    ok "container '$CN' already exists (deploy will stop+replace it — idempotent)"
else
    ok "container name '$CN' free"
fi
grep -q "$CN" app-extra.env 2>/dev/null \
    && ok "app-extra.env (NO_PROXY) references '$CN'" \
    || fail "app-extra.env does not reference '$CN' — app->BioEngineX calls may try a proxy"

# --------------------------------------------------------- summary --------
echo
if [ "$FAILS" -gt 0 ]; then
    echo "RESULT: NOT READY — ${FAILS} FAIL(s), ${WARNS} WARN(s). Fix the [FAIL] items and re-run."
    exit 1
fi
echo "RESULT: READY — 0 FAIL(s), ${WARNS} WARN(s). Next: sudo bash deploy_bioenginex.sh (menu: 1=dry-run first)"
exit 0
