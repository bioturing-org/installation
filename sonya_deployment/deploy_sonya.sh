#!/usr/bin/env bash
# deploy_sonya.sh — deploy & manage a GENERIC Sonya stack.
# Honors IMAGE_MODE from .env (root / non-root — set by prepare_sonya.sh);
# the active docker-compose.yml is the symlink prepare created.
#
# Menu:
#   1) dry-run   - validate + render compose + show plan (changes NOTHING)
#   2) real      - cutover deployment (stops ONLY the old main container)
#   3) stop      - stop the Sonya stack (nothing removed)
#   4) start     - start the Sonya stack
#   5) restart   - restart the Sonya stack
#   6) down      - docker-compose down: stop + REMOVE all stack containers
#                  (data on the NAS persists; nothing is deleted from disk)
#   7) redeploy  - COMPLETE remove (compose down) + fresh start
#
# IMPORTANT (ops decisions from the production roll-out):
#   - 'real' (2) NEVER stops/removes sonya-postgres, sonya-gateway or
#     jupyter-workspace. It only stops+removes the OLD main standalone
#     container (CONTAINER_NAME — compose reuses that name).
#   - 'redeploy' (6) is the ONLY action that removes the whole stack
#     (incl. sonya-postgres). Data on the NAS persists.
#
# Optional env overrides (not parameters):
#   SKIP_DOCKER_PULL=1   images pre-pulled, skip pull
#   CONFIRM=YES          skip the interactive YES confirmation
#   MODE=1..7            pre-select the menu choice

set -euo pipefail

DEPLOY_DIR="$(cd "$(dirname "$0")" && pwd)"
LOG="${DEPLOY_DIR}/PROGRESS.log"

log() { echo "[$(date -u +"%Y-%m-%dT%H:%M:%SZ")] $*" | tee -a "$LOG"; }

cd "$DEPLOY_DIR"
[ "$(id -u)" -eq 0 ] || { echo "ERROR: run with sudo/root"; exit 1; }
[ -f docker-compose.yml ] || { echo "ERROR: docker-compose.yml missing — run prepare_sonya.sh first"; exit 1; }
[ -f .env ] || { echo "ERROR: .env missing — run prepare_sonya.sh first"; exit 1; }

# compose command: plugin first, standalone docker-compose fallback (hosts
# without the plugin, e.g. genentech / elephant); install if missing
if docker compose version >/dev/null 2>&1; then
  COMPOSE="docker compose"
elif command -v docker-compose >/dev/null 2>&1; then
  COMPOSE="docker-compose"
elif [ -x ./install_compose.sh ]; then
  echo "no compose command found — running install_compose.sh ..."
  bash ./install_compose.sh || { echo "ERROR: docker-compose install failed"; exit 1; }
  COMPOSE="docker-compose"
else
  echo "ERROR: no compose command (neither plugin nor standalone docker-compose)"; exit 1
fi
log "compose command: ${COMPOSE}"

FQDN="$(grep '^APPLICATION_DOMAIN=' .env | cut -d= -f2-)"
CONTAINER_NAME="$(grep '^CONTAINER_NAME=' .env | cut -d= -f2-)"
APP_PORT="$(grep '^APP_PORT=' .env | cut -d= -f2-)"
IMAGE_MODE="$(grep '^IMAGE_MODE=' .env | cut -d= -f2-)"
BIOTURING_IMAGE="$(grep '^BIOTURING_IMAGE=' .env | cut -d= -f2-)"

confirm() {
  if [ "${CONFIRM:-}" = "YES" ]; then return 0; fi
  echo
  echo "  >>> $1"
  read -rp "  Type YES to continue: " a
  [ "$a" = "YES" ] || { echo "  aborted — nothing was changed"; return 1; }
}

# backup /database (DATABASE_DIR) to ONE safe place on the host before any
# cutover. Copy-only: never deletes or modifies anything in the source.
# Target: sibling 'database_backups' next to DATABASE_DIR (same volume) or
# BACKUP_DIR override. Timestamped, kept forever (no pruning).
backup_database() {
  local src dst ts size free
  src="$(grep '^DATABASE_DIR=' .env | head -1 | cut -d= -f2- | tr -d '\"')"
  if [ -z "$src" ] || [ ! -d "$src" ]; then
    log "backup: DATABASE_DIR '${src}' missing/empty — skipping backup"
    return 0
  fi
  if [ -z "$(ls -A "$src" 2>/dev/null)" ]; then
    log "backup: DATABASE_DIR empty (fresh install) — nothing to back up"
    return 0
  fi
  dst="${BACKUP_DIR:-$(dirname "$src")/database_backups}"
  ts="$(date -u +%Y%m%dT%H%M%SZ)"
  mkdir -p "${dst}/${ts}"
  size="$(du -sm "$src" 2>/dev/null | awk '{print $1}')"
  free="$(df -Pm "$(dirname "$dst")" 2>/dev/null | awk 'NR==2{print $4}')"
  if [ -n "$free" ] && [ -n "$size" ] && [ "$free" -lt "$size" ]; then
    echo "!! WARNING: backup target has only ${free}MB free, database is ${size}MB"
    read -rp "   Continue WITHOUT a safe backup? [y/N] " ANS
    case "$ANS" in y|Y|yes|YES) log "backup skipped by operator"; return 0;; *) return 1;; esac
  fi
  log "backup: ${src} -> ${dst}/${ts} (${size}MB)"
  if command -v rsync >/dev/null 2>&1; then
    rsync -a "$src"/ "${dst}/${ts}"/
  else
    cp -a "$src"/. "${dst}/${ts}"/
  fi
  if [ $? -ne 0 ]; then
    echo "!! WARNING: backup reported errors — check ${dst}/${ts}"
    read -rp "   Continue deploy anyway? [y/N] " ANS
    case "$ANS" in y|Y|yes|YES) return 0;; *) log "aborted by operator after backup failure"; return 1;; esac
  fi
  log "backup complete: ${dst}/${ts}"
}

# ------------------------------------------------------------------ menu ------
echo "===================================================================="
echo "  Sonya GENERIC deployment"
echo "  host: $(hostname)  |  deploy dir: ${DEPLOY_DIR}"
echo "  tenant: ${FQDN}"
echo "  image mode: ${IMAGE_MODE:-UNSET} (${BIOTURING_IMAGE:-?})"
echo "===================================================================="
echo
echo "  1) dry-run    - validate + render compose + show plan (changes NOTHING)"
echo "  2) real       - cutover deploy (stops ONLY the old main container"
echo "                  ${CONTAINER_NAME}; sonya containers keep running)"
echo "  3) stop       - stop the Sonya stack (no removal)"
echo "  4) start      - start the Sonya stack"
echo "  5) restart    - restart the Sonya stack"
echo "  6) down      - stop + REMOVE all stack containers (data persists)"
echo "  7) redeploy  - COMPLETE remove (incl. postgres) + fresh start"
echo "  8) exit"
echo
MODE="${MODE:-}"
if [ -z "$MODE" ]; then
  read -rp "  Choose 1-8: " MODE
fi
case "$MODE" in
  1|2|3|4|5|6|7) ;;
  *) echo "aborted — nothing was changed"; exit 0;;
esac

# ============================================================ 1) DRY-RUN ======
if [ "$MODE" = "1" ]; then
  echo
  echo "=============== DRY-RUN (nothing will be changed) ================="
  echo
  echo "--- validation ---"
  if bash "${DEPLOY_DIR}/validate_sonya.sh"; then
    VAL=0
  else
    VAL=1
    echo "(validation failed — modes 2 (real) and 6 (redeploy) will refuse to run until fixed)"
  fi
  echo
  echo "--- resolved compose (${COMPOSE} config) ---"
  ${COMPOSE} config
  echo
  echo "--- plan ---"
  echo "  deploy dir  : ${DEPLOY_DIR}"
  echo "  image mode  : ${IMAGE_MODE} (${BIOTURING_IMAGE})"
  [ "$IMAGE_MODE" = "root" ] && \
  echo "                (root image: storage-init NOT in the stack — correct)"
  echo "  old instance: container ${CONTAINER_NAME} (if still running)"
  echo "                -> mode 2 (real) stops+removes ONLY this container;"
  echo "                   sonya-postgres / sonya-gateway / jupyter-workspace"
  echo "                   are NEVER stopped or removed by mode 2"
  echo "  new stack   : ${COMPOSE} up -d, app on ${APP_PORT}"
  echo "  after real  : switch the host's HAProxy backend to the new port"
  echo "                and reload haproxy (manual — with a cfg backup first)"
  echo
  echo "This dry-run changed NOTHING on the server."
  exit "$VAL"
fi

# ============================================================== 2) REAL ========
if [ "$MODE" = "2" ]; then
  # pre-flight only: warnings never block (token expiry etc.); FAILs ask.
  if ! bash "${DEPLOY_DIR}/validate_sonya.sh"; then
    if [ "${FORCE:-NO}" = "YES" ]; then
      echo
      echo "[FORCE=YES] validation reported failures — deploying ANYWAY."
    else
      echo
      echo "NOTE: validation reported [FAIL] items above."
      read -rp "      Deploy anyway? [y/N] " ANS
      case "$ANS" in
          y|Y|yes|YES) echo "continuing (operator override)";;
          *) echo "aborted — nothing was changed"; exit 1;;
      esac
    fi
  fi

  echo
  echo "===================================================================="
  echo " REAL DEPLOYMENT — ${FQDN}"
  echo "   - stops+removes ONLY the old main container ${CONTAINER_NAME}"
  echo "     (NAS data persists; sonya containers are NOT touched)"
  echo "   - starts the Sonya compose stack, app on ${APP_PORT}"
  echo "===================================================================="
  confirm "This may cause downtime for ${FQDN}. Continue?" || exit 0

  log "=== real deployment started (by ${SUDO_USER:-root}, mode=${IMAGE_MODE}) ==="

  # 0) SAFETY BACKUP of /database (copy-only, never deletes anything)
  backup_database || { echo "aborted — no backup, no deploy"; exit 1; }

  # a) PULL FIRST — while the old container is still running (minimize downtime)
  [ "${SKIP_DOCKER_PULL:-0}" = "1" ] \
    && log "SKIP_DOCKER_PULL=1 — skipping pull (images pre-pulled)" \
    || { log "${COMPOSE} pull (old container still running, no downtime yet)"; ${COMPOSE} pull; }

  # b) pre-checks BEFORE touching the old container
  PORT_HOG="$(docker ps --format '{{.ID}} {{.Names}} {{.Ports}}' \
              | grep -E ":${APP_PORT}->" \
              | grep -vE "sonya-postgres|sonya-gateway|jupyter-workspace" \
              | awk '{print $1}' || true)"
  if [ -n "$PORT_HOG" ]; then
    log "WARNING: container(s) ${PORT_HOG} hold port ${APP_PORT} — will remove them below"
  fi

  # c) stop + remove ONLY the old standalone main app container + port hogs
  log "removing old containers (last step before starting the new stack)"
  if docker ps -a --format '{{.Names}}' | grep -qx "$CONTAINER_NAME"; then
    log "stopping + removing old main container ${CONTAINER_NAME} (data persists on NAS)"
    docker stop "$CONTAINER_NAME" || true
    docker rm   "$CONTAINER_NAME" || true
  else
    log "no existing container named ${CONTAINER_NAME} found (already removed)"
  fi
  if [ -n "${PORT_HOG}" ]; then
    for cid in $PORT_HOG; do
      log "stopping + removing port-holder ${cid}"
      docker stop "$cid" || true; docker rm "$cid" || true
    done
  fi

  # d) sanity: name and port are now free (compose needs them)
  if docker ps -a --format '{{.Names}}' | grep -qx "$CONTAINER_NAME" \
     || docker ps --format '{{.Ports}}' | grep -qE ":${APP_PORT}->"; then
    log "ERROR: conflicting containers still present after cleanup — aborting"
    exit 1
  fi
  log "cleanup complete — sonya containers (if any) were left running"

  # e) start the new stack immediately (downtime starts here)
  log "${COMPOSE} up -d (downtime starts NOW)"
  ${COMPOSE} up -d
  log "stack up; app boots in ~1-3 min, full update ~30 min until Sonya tab appears"

  # e2) GPU fix (post-deploy, our side — image stays official):
  #     disable the CUDA GDK stub ldconfig path inside the fresh container
  #     so nvidia-smi/GPU talks to the real driver lib. Runs as root; the
  #     app keeps running with its own user (www-data or root per mode).
  log "applying GPU stub fix inside fresh container (stubs.conf -> disabled, ldconfig)"
  docker exec --user root "$CONTAINER_NAME" bash -c "mv /etc/ld.so.conf.d/stubs.conf /etc/ld.so.conf.d/stubs.conf.disabled 2>/dev/null || true; ldconfig" || log "WARNING: GPU stub fix failed - nvidia-smi may not work inside the container"

  # f) WAIT for the stack to settle (max ~10 min)
  echo
  echo "waiting for all services to become healthy (max ~10 min)..."
  for i in $(seq 1 120); do
    BAD="$(${COMPOSE} ps --all --format '{{.Name}}: {{.State}} {{.Health}}' 2>/dev/null \
            | grep -E 'restarting|unhealthy|dead|paused' || true)"
    if [ -z "$BAD" ]; then
      log "all services settled/healthy after ~$((i*5))s"
      break
    fi
    if [ "$i" = "1" ] || [ $((i % 12)) -eq 0 ]; then
      echo "    still settling: $(echo "$BAD" | tr '\n' ';')"
    fi
    sleep 5
  done
  echo
  echo "--- stack status (${COMPOSE} ps) ---"
  ${COMPOSE} ps
  BAD="$(${COMPOSE} ps --all --format '{{.Name}}: {{.State}} {{.Health}}' 2>/dev/null \
          | grep -E 'restarting|unhealthy|dead|paused' || true)"
  if [ -n "$BAD" ]; then
    log "WARNING: some services are unhealthy/restarting:"
    echo "$BAD" | sed 's/^/    /'
  else
    log "all services healthy"
    # late-failure confirmation (crash-loops can start after the settle window)
    sleep 20
    BAD2="$(${COMPOSE} ps --all --format '{{.Name}}: {{.State}} {{.Health}}' 2>/dev/null \
            | grep -E 'restarting|unhealthy|dead|paused' || true)"
    GWERR="$(${COMPOSE} logs --since 1m sonya-gateway 2>&1 | grep -E 'Error:|FATAL' | head -3 || true)"
    if [ -n "$BAD2" ] || [ -n "$GWERR" ]; then
      log "WARNING: late failure detected (20s re-check) - stack is NOT healthy:"
      [ -n "$BAD2" ] && echo "$BAD2" | sed 's/^/    /'
      [ -n "$GWERR" ] && echo "$GWERR" | sed 's/^/    /'
    else
      log "confirmed stable after 20s re-check (no restarts, no gateway errors)"
    fi
  fi
  echo "--- last 10 log lines per container ---"
  for svc in app sonya-gateway sonya-postgres jupyter-workspace; do
    echo "===== $svc ====="
    ${COMPOSE} logs --tail 10 "$svc" 2>&1 | sed 's/^/  /'
    echo
  done
  # nonroot mode also has storage-init — show it if present
  if ${COMPOSE} config --services 2>/dev/null | grep -q storage-init; then
    echo "===== storage-init ====="
    ${COMPOSE} logs --tail 10 storage-init 2>&1 | sed 's/^/  /'
  fi
  echo

  # g) health-wait (warn only)
  echo "waiting for app on ${APP_PORT} (max ~5 min)..."
  CODE=""; OK=0
  for i in $(seq 1 60); do
    CODE=$(curl -s -o /dev/null -w "%{http_code}" -H "Host: ${FQDN}" \
           "http://127.0.0.1:${APP_PORT}" --max-time 5 2>/dev/null) || CODE="000"
    case "$CODE" in
      200|302|401) log "healthy after ~$((i*5))s (HTTP ${CODE})"; OK=1; break;;
      503|000|"")  sleep 5;;
      *)           log "responding HTTP ${CODE} after ~$((i*5))s (site is up)"; OK=1; break;;
    esac
  done
  [ "$OK" = "1" ] || log "WARNING: still not healthy (HTTP ${CODE}) — check: ${COMPOSE} logs --tail 50"

  cat <<EOS
====================================================================
NEXT STEPS (manual):
 1) HAProxy cutover (if fronted): backup cfg, switch the backend to
    127.0.0.1:${APP_PORT}, validate (haproxy -c), reload, verify 302.
 2) Wait ~30 min for apps to update until the Sonya tab appears in console.
 3) Track: ${LOG}
====================================================================
EOS
  log "=== real deployment finished (haproxy switch + console config pending) ==="
  exit 0
fi

# ==================================================== 3/4/5) stop/start/rst ====
if [ "$MODE" = "3" ]; then
  confirm "STOP the Sonya stack for ${FQDN}? (compose stop — nothing removed)" || exit 0
  log "=== stop (by ${SUDO_USER:-root}) ==="
  ${COMPOSE} stop
  log "stack stopped (data persists)"
  exit 0
fi
if [ "$MODE" = "4" ]; then
  log "=== start (by ${SUDO_USER:-root}) ==="
  ${COMPOSE} start
  ${COMPOSE} ps
  log "stack started"
  exit 0
fi
if [ "$MODE" = "5" ]; then
  confirm "RESTART the Sonya stack for ${FQDN}?" || exit 0
  log "=== restart (by ${SUDO_USER:-root}) ==="
  ${COMPOSE} restart
  ${COMPOSE} ps
  log "stack restarted"
  exit 0
fi

# ============================================================ 6) DOWN ==========
if [ "$MODE" = "6" ]; then
  echo
  echo "===================================================================="
  echo " DOWN — stop + remove ALL stack containers (compose down)"
  echo "   (data persists on the NAS / host dirs; nothing on disk is deleted)"
  echo "===================================================================="
  confirm "Remove the whole stack (containers only, data persists)?" || exit 0
  log "=== down (by ${SUDO_USER:-root}) ==="
  ${COMPOSE} down
  log "stack stopped and removed (data persists)"
  exit 0
fi

# ============================================================ 7) REDEPLOY ======
if [ "$MODE" = "7" ]; then
  echo
  echo "===================================================================="
  echo " REDEPLOY — COMPLETE stack removal + fresh start"
  echo "   removes sonya-postgres too (data persists on NAS)"
  echo "===================================================================="
  confirm "REALLY redeploy? This removes ALL stack containers first. Continue?" || exit 0
  log "=== redeploy started (by ${SUDO_USER:-root}, mode=${IMAGE_MODE}) ==="

  # SAFETY BACKUP of /database first (copy-only, never deletes anything)
  backup_database || { echo "aborted — no backup, no redeploy"; exit 1; }
  ${COMPOSE} down
  ${COMPOSE} up -d
  log "applying GPU stub fix inside fresh container"
  docker exec --user root "$CONTAINER_NAME" bash -c "mv /etc/ld.so.conf.d/stubs.conf /etc/ld.so.conf.d/stubs.conf.disabled 2>/dev/null || true; ldconfig" || true
  ${COMPOSE} ps
  log "=== redeploy finished ==="
  exit 0
fi