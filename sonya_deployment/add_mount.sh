#!/usr/bin/env bash
# ============================================================
# add_mount.sh — add an EXTRA host mount to the deployment stack
#
# Usage:  sudo bash add_mount.sh [/data_new]
#
# Asks for: host path, container path (default = same path),
# variable name (default = derived). Then prints the COMPLETE set of
# lines for every file (.env + both compose variants) and, if you
# confirm, applies them automatically (with .bak backups, idempotent,
# never deletes anything).
# ============================================================
set -u
cd "$(dirname "$0")"

[ -f .env ] && [ -f docker-compose.root.yml ] && [ -f docker-compose.nonroot.yml ] \
  || { echo "run this in the deployment folder (.env + compose files)"; exit 1; }

# ---------- input ----------
HOST_PATH="${1:-}"
[ -n "$HOST_PATH" ] || read -rp "host path to mount (e.g. /data_new): " HOST_PATH
[ -n "$HOST_PATH" ] || { echo "no path given — abort"; exit 1; }
HOST_PATH="${HOST_PATH%/}"

read -rp "container path [default: same as host = ${HOST_PATH}]: " CONTAINER_PATH
CONTAINER_PATH="${CONTAINER_PATH:-$HOST_PATH}"

# derive variable name: /data_new -> DATA_NEW_DIR
DEFAULT_VAR="$(echo "$HOST_PATH" | sed -e 's|^/||' -e 's|/|_|g' -e 's|[^A-Za-z0-9_]|_|g' | tr '[:lower:]' '[:upper:]')_DIR"
read -rp "env variable name [default: ${DEFAULT_VAR}]: " VAR
VAR="${VAR:-$DEFAULT_VAR}"
echo "$VAR" | grep -qE '^[A-Za-z_][A-Za-z0-9_]*$' || { echo "invalid variable name: $VAR"; exit 1; }

# ---------- idempotency ----------
if grep -q "^${VAR}=" .env; then
  echo "[SKIP] ${VAR} already exists in .env:"
  grep "^${VAR}=" .env
  exit 0
fi

# ---------- the complete set of lines ----------
ENV_BLOCK="# extra mount: host ${HOST_PATH} -> container ${CONTAINER_PATH}
${VAR}=${HOST_PATH}"
COMPOSE_LINE="      - \${${VAR}:?set ${VAR}}:${CONTAINER_PATH}"

echo
echo "================= WHAT GETS ADDED WHERE ================="
echo
echo "1) .env  (after the SSL_VOLUME line):"
echo "   ${ENV_BLOCK}"
echo
echo "2) docker-compose.root.yml  (app service -> volumes:,"
echo "   after the SSL mount line):"
echo "   ${COMPOSE_LINE}"
echo
echo "3) docker-compose.nonroot.yml  (same place, same line):"
echo "   ${COMPOSE_LINE}"
echo
echo "Default container port mappings and everything else stay as-is."
echo "=========================================================="
echo

read -rp "Apply these edits automatically? [y/N] " ANS
case "$ANS" in
  y|Y|yes|YES) ;;
  *) echo "nothing changed — apply the lines above manually"; exit 0 ;;
esac

TS="$(date +%Y%m%dT%H%M%S)"
cp .env ".env.bak.${TS}"
cp docker-compose.root.yml "docker-compose.root.yml.bak.${TS}"
cp docker-compose.nonroot.yml "docker-compose.nonroot.yml.bak.${TS}"
echo "backups: *.bak.${TS}"

# 1) .env — insert after the SSL_VOLUME line (mount vars stay grouped)
ENV_COMMENT="# extra mount: host ${HOST_PATH} -> container ${CONTAINER_PATH}"
if grep -q '^SSL_VOLUME=' .env; then
  awk -v c="$ENV_COMMENT" -v v="${VAR}=${HOST_PATH}" '
    /^SSL_VOLUME=/ && !done { print; print ""; print c; print v; done=1; next }
    { print }
  ' .env > .env.new && mv .env.new .env
else
  printf '\n%s\n%s\n' "$ENV_COMMENT" "${VAR}=${HOST_PATH}" >> .env
fi
grep -q "^${VAR}=" .env && echo "[OK] .env: ${VAR} added" || echo "[FAIL] .env"

# 2+3) compose files — insert after the SSL mount line in the app volumes block
COMPOSE_LINE="      - \${${VAR}:?set ${VAR}}:${CONTAINER_PATH}"
for f in docker-compose.root.yml docker-compose.nonroot.yml; do
  if grep -qF "${COMPOSE_LINE}" "$f"; then
    echo "[SKIP] $f already has the mount"
  elif grep -qF '${SSL_VOLUME:-/config/ssl}:${SSL_VOLUME:-/config/ssl}' "$f"; then
    awk -v line="${COMPOSE_LINE}" '
      /ssl_volume.*\/config\/ssl.*\/config\/ssl/ || /\$\{SSL_VOLUME:-\/config\/ssl\}:\$\{SSL_VOLUME:-\/config\/ssl\}/ {
        print; print line; added=1; next }
      { print }
      END { if (!added) exit 3 }
    ' "$f" > "$f.new" && mv "$f.new" "$f" && echo "[OK] $f: mount added" || { rm -f "$f.new"; echo "[FAIL] $f"; }
  else
    echo "[WARN] $f: SSL mount anchor not found — add this line manually under the app volumes:"
    echo "       ${COMPOSE_LINE}"
  fi
done

# ---------- verify ----------
echo
echo "--- verify (rendered compose, mount section) ---"
COMPOSE_CMD="$(docker compose version >/dev/null 2>&1 && echo 'docker compose' || (docker-compose version >/dev/null 2>&1 && echo docker-compose || echo ''))"
if [ -n "$COMPOSE_CMD" ]; then
  $COMPOSE_CMD -f docker-compose.root.yml config 2>/dev/null \
    | grep -B2 -A2 "${CONTAINER_PATH}" | head -12 || echo "(render check: grep found nothing — check ${VAR})"
else
  echo "no compose binary on this host — check the files manually"
fi
echo
echo "done. If the stack is already running, apply it:"
echo "  sudo docker compose up -d --force-recreate bioturing-ecosystem"
