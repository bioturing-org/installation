#!/usr/bin/env bash
# deploy_bioenginex.sh — deploy / manage the BioEngineX compute service.
# Reads shared values (JWT_SECRET, STORAGE_DIR, COMPOSE_PROJECT_NAME, app
# container name) from .env AT RUNTIME and exports JWT_SECRET — the app and
# BioEngineX can never drift apart.
#
# Menu: 1=dry-run (show the exact docker run, touch nothing)
#       2=deploy  (idempotent: stops+replaces an existing instance)
#       3=status
#       4=stop
#       5=re-attach to the sonya network (run AFTER any 'compose down'+up
#         of the sonya stack — a recreated network silently drops BioEngineX)
set -uo pipefail

DEPLOY_DIR="$(cd "$(dirname "$0")" && pwd)"
LOG="${DEPLOY_DIR}/PROGRESS.log"
log() { echo "[$(date -u +"%Y-%m-%dT%H:%M:%SZ")] $*" | tee -a "$LOG"; }
cd "$DEPLOY_DIR"
[ "$(id -u)" -eq 0 ] || { echo "ERROR: run with sudo/root"; exit 1; }

get()  { grep "^${1}=" .env 2>/dev/null | head -1 | cut -d= -f2- | sed -e 's/[[:space:]]*#.*$//' | tr -d '\r' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//'; }
getx() { grep "^${1}=" bioenginex.env 2>/dev/null | head -1 | cut -d= -f2- | sed -e 's/[[:space:]]*#.*$//' | tr -d '\r' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//'; }

# ---- load all values (fail fast on anything missing) ----
JWT_SECRET="$(get JWT_SECRET)";            [ -n "$JWT_SECRET" ] || { echo "ERROR: JWT_SECRET empty in .env"; exit 1; }
STORAGE_DIR="$(get STORAGE_DIR)";          [ -n "$STORAGE_DIR" ] || { echo "ERROR: STORAGE_DIR empty in .env"; exit 1; }
PROJECT="$(get COMPOSE_PROJECT_NAME)";     [ -n "$PROJECT" ] || { echo "ERROR: COMPOSE_PROJECT_NAME empty in .env"; exit 1; }
APP_CN="$(get CONTAINER_NAME)";            [ -n "$APP_CN" ] || { echo "ERROR: CONTAINER_NAME empty in .env"; exit 1; }
CN="$(getx BIOENGINEX_CONTAINER_NAME)";    [ -n "$CN" ] || { echo "ERROR: BIOENGINEX_CONTAINER_NAME empty in bioenginex.env"; exit 1; }
VER="$(getx BIOENGINEX_VERSION)";          [ -n "$VER" ] || { echo "ERROR: BIOENGINEX_VERSION empty"; exit 1; }
HTTP_PORT="$(getx BIOENGINEX_HTTP_PORT)";  [ -n "$HTTP_PORT" ] || { echo "ERROR: BIOENGINEX_HTTP_PORT empty"; exit 1; }
RPC_PORT="$(getx BIOENGINEX_RPC_PORT)";    [ -n "$RPC_PORT" ] || { echo "ERROR: BIOENGINEX_RPC_PORT empty"; exit 1; }
SHARED_V="$(getx BIOENGINEX_SHARED_VOLUME)"; [ -n "$SHARED_V" ] || { echo "ERROR: BIOENGINEX_SHARED_VOLUME empty in bioenginex.env"; exit 1; }
DATA_V="$(getx BIOENGINEX_DATA_VOLUME)";    [ -n "$DATA_V" ] || { echo "ERROR: BIOENGINEX_DATA_VOLUME empty in bioenginex.env"; exit 1; }
SHARED_M="$(getx BIOENGINEX_SHARED_MOUNT)";  [ -n "$SHARED_M" ] || { echo "ERROR: BIOENGINEX_SHARED_MOUNT empty"; exit 1; }
DATA_M="$(getx BIOENGINEX_DATA_MOUNT)";      [ -n "$DATA_M" ] || { echo "ERROR: BIOENGINEX_DATA_MOUNT empty"; exit 1; }

NETWORK="${PROJECT}_bioturing"
IMAGE="bioturing/bioenginex:${VER}"

# drift guard at deploy time too (belt and suspenders — validate also checks)
[ "$SHARED_V" = "$STORAGE_DIR" ] \
    || { echo "ERROR: BIOENGINEX_SHARED_VOLUME ('$SHARED_V') != .env STORAGE_DIR ('$STORAGE_DIR') — they MUST match"; exit 1; }

# export the shared secret from the single source of truth (.env) —
# passed to the container as '-e JWT_SECRET' (name only, no value on the cmdline)
export JWT_SECRET

run_container() {
    docker run -d -t \
        -e JWT_SECRET \
        --env-file ./bioenginex.env \
        --network "$NETWORK" \
        -p "${HTTP_PORT}:35576" \
        -p "${RPC_PORT}:35577" \
        -v "${SHARED_V}:${SHARED_M}:rw" \
        -v "${DATA_V}:${DATA_M}:rw" \
        --name "$CN" \
        --shm-size="8gb" \
        --gpus all \
        --privileged --restart always \
        "$IMAGE"
}

echo "================ BioEngineX management ================"
echo "  image     : $IMAGE"
echo "  container : $CN"
echo "  network   : $NETWORK  (shared with the sonya stack)"
echo "  shared    : ${SHARED_V} -> ${SHARED_M} (same partition as the app)"
echo "  private   : ${DATA_V} -> ${DATA_M}"
echo "  ports     : ${HTTP_PORT}->35576 (HTTP), ${RPC_PORT}->35577 (RPC)"
echo "  auth      : JWT_SECRET exported from .env (same value as the app)"
echo "======================================================="
echo "  1) dry-run (show command, touch nothing)"
echo "  2) deploy (idempotent: stops + replaces existing)"
echo "  3) status"
echo "  4) stop"
echo "  5) re-attach to network (run AFTER any sonya compose down+up)"
read -rp "  choose: " MODE

case "$MODE" in
  1)
    echo
    echo "DRY-RUN — this exact command would run:"
    echo "  docker run -d -t \\"
    echo "      -e JWT_SECRET          (exported from .env — value NOT printed) \\"
    echo "      --env-file ./bioenginex.env \\"
    echo "      --network ${NETWORK} \\"
    echo "      -p ${HTTP_PORT}:35576 -p ${RPC_PORT}:35577 \\"
    echo "      -v ${SHARED_V}:${SHARED_M}:rw \\"
    echo "      -v ${DATA_V}:${DATA_M}:rw \\"
    echo "      --name ${CN} --shm-size=8gb --gpus all \\"
    echo "      --privileged --restart always ${IMAGE}"
    docker network inspect "$NETWORK" >/dev/null 2>&1 \
        || echo "  [WARN] network ${NETWORK} does not exist yet — deploy_sonya.sh must run FIRST"
    ;;

  2)
    docker network inspect "$NETWORK" >/dev/null 2>&1 \
        || { echo "ERROR: network ${NETWORK} not found — bring the sonya stack up first"; exit 1; }
    [ -d "$DATA_V" ] || mkdir -p "$DATA_V"
    log "=== bioenginex deploy started ==="
    echo "stopping/removing previous instance (if any) ..."
    docker stop "$CN" 2>/dev/null || true
    docker rm   "$CN" 2>/dev/null || true
    echo "pulling $IMAGE ..."
    docker pull "$IMAGE" || { echo "ERROR: pull failed"; exit 1; }
    echo "starting container ..."
    run_container || { echo "ERROR: docker run failed — see above"; exit 1; }
    log "bioenginex deployed: ${CN} (${IMAGE}) on network ${NETWORK}"
    sleep 5
    echo
    docker ps --filter "name=$CN" --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'
    echo
    echo "post-deploy connectivity check:"
    bash ./validate_bioenginex.sh || true
    echo
    echo "health: curl -m 5 http://127.0.0.1:${HTTP_PORT}/  (any HTTP code = listening)"
    echo "logs  : docker logs --tail 50 ${CN}"
    echo "final proof: login to the app UI and run a BioEngineX-backed tool"
    log "=== bioenginex deploy finished ==="
    ;;

  3)
    docker ps -a --filter "name=$CN" --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'
    docker inspect -f 'network: {{range $k,$v := .NetworkSettings.Networks}}{{$k}}{{end}}' "$CN" 2>/dev/null
    echo "--- last log lines ---"
    docker logs --tail 20 "$CN" 2>&1 | tail -20
    ;;

  4)
    docker stop "$CN" && log "bioenginex stopped: ${CN}" || echo "not running"
    ;;

  5)
    docker network inspect "$NETWORK" >/dev/null 2>&1 \
        || { echo "ERROR: network $NETWORK not found — bring the sonya stack up first"; exit 1; }
    if docker network inspect "$NETWORK" | grep -q "\"$CN\""; then
        echo "already attached — nothing to do"
    else
        docker network connect "$NETWORK" "$CN" \
            && log "BioEngineX re-attached to $NETWORK" \
            || { echo "ERROR: attach failed"; exit 1; }
    fi
    # verify reachability right away
    docker exec "$CN" getent hosts "$APP_CN" >/dev/null 2>&1 \
        && echo "  [ OK ] BioEngineX can resolve the app again" \
        || echo "  [WARN] resolution failed — restart BioEngineX: docker restart $CN"
    ;;

  *) echo "aborted — nothing was changed";;
esac
