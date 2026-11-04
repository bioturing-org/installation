#!/usr/bin/env bash
# prepare_sonya.sh — one-time preparation for a GENERIC Sonya deployment.
#
# Interactive: FIRST asks root / non-root image mode, then:
#   - writes IMAGE_MODE + BIOTURING_IMAGE into .env
#   - links the matching docker-compose.<mode>.yml as docker-compose.yml
#   - CREATES every missing dir from .env (data dirs + sonya dirs) — NEVER
#     deletes or modifies anything that already exists
#   - generates NEW sonya-stack secrets if missing — NEVER regenerated
#     after the first deploy
#   - enforces env hygiene (no inline '#' on value lines — genentech 503 rule)
#   - installs docker-compose if missing (install_compose.sh)
#   - sets permissions 600/root-only on .env / app-extra.env
#
# NEVER touches any container, any postgres, any other tenant.
set -euo pipefail

DEPLOY_DIR="$(cd "$(dirname "$0")" && pwd)"
LOG="${DEPLOY_DIR}/PROGRESS.log"

log() { echo "[$(date -u +"%Y-%m-%dT%H:%M:%SZ")] $*" | tee -a "$LOG"; }

cd "$DEPLOY_DIR"
[ "$(id -u)" -eq 0 ] || { echo "ERROR: run with sudo/root"; exit 1; }
# the templates ship AS the real names (.env + app-extra.env) so that
# docker compose picks them up directly — no rename step needed.
[ -f .env ] || { echo "ERROR: .env missing (wrong folder?)"; exit 1; }
[ -f docker-compose.nonroot.yml ] || { echo "ERROR: docker-compose.nonroot.yml missing"; exit 1; }
[ -f docker-compose.root.yml ]     || { echo "ERROR: docker-compose.root.yml missing"; exit 1; }

get() { grep "^${1}=" .env 2>/dev/null | head -1 | cut -d= -f2- | sed -e 's/[[:space:]]*#.*$//' | tr -d '\r' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//'; }

log "=== prepare started (by ${SUDO_USER:-root}) ==="

# ------------------------------------------- 0a) docker compose availability --
if docker compose version >/dev/null 2>&1; then
    log "docker compose plugin available"
elif command -v docker-compose >/dev/null 2>&1; then
    log "standalone docker-compose available"
elif [ -x ./install_compose.sh ]; then
    echo "docker-compose not found — running install_compose.sh ..."
    bash ./install_compose.sh || { echo "ERROR: docker-compose install failed — install manually and re-run"; exit 1; }
else
    echo "WARN: no compose command and no install_compose.sh — continuing, validate will re-check"
fi

# ------------------------------------------- 0b) env hygiene (genentech rule) --
# value lines with inline '#' comments break docker env_file (values are
# passed verbatim) — the genentech 503 root cause. Strip them automatically.
for f in .env app-extra.env; do
    [ -f "$f" ] || continue
    if grep -qE '^[A-Za-z_][A-Za-z0-9_]*=.*#' "$f"; then
        echo
        echo "!! inline comments found on value lines in $f:"
        grep -nE '^[A-Za-z_][A-Za-z0-9_]*=.*#' "$f" | sed 's/^/    /'
        echo "   (docker passes these VERBATIM to the container — the '#' text"
        echo "    becomes part of the value and breaks the app; genentech 503)"
        read -rp "    Strip them now (comments on their own lines stay)? [Y/n] " ANS
        case "${ANS:-y}" in
            n|N) echo "aborted — fix $f manually (move comments to their own lines)"; exit 1 ;;
            *)
                sed -i.bak -E 's/^([A-Za-z_][A-Za-z0-9_]*=[^#]*[^ #])[[:space:]]+#.*$/\1/' "$f" && rm -f "$f.bak"
                if grep -qE '^[A-Za-z_][A-Za-z0-9_]*=.*#' "$f"; then
                    echo "ERROR: could not strip all inline comments in $f — fix manually"; exit 1
                fi
                log "env hygiene: inline comments stripped from $f values" ;;
        esac
    fi
done

# ----------------------------------------------------------- 0c) env files ----
DOM_CHECK="$(grep '^APPLICATION_DOMAIN=' .env | cut -d= -f2- | sed -e 's/[[:space:]]*#.*$//')"
case "$DOM_CHECK" in
  ""|mytenant*|"<"*|"__"*)
    echo "ERROR: .env still looks like an untouched template"
    echo "       (APPLICATION_DOMAIN='${DOM_CHECK}')"
    echo "       -> edit .env first: set APPLICATION_DOMAIN, ports, dirs,"
    echo "          resources, legacy secrets (JWT_SECRET, BIOTURING_TOKEN)."
    exit 1;;
esac
if [ ! -f app-extra.env ]; then
  echo "ERROR: app-extra.env missing (wrong folder?)"
  exit 1
fi

# ==================================================== 1) ROOT / NON-ROOT =====
echo
echo "===================================================================="
echo "  Which image mode for this tenant?"
echo "===================================================================="
echo "  1) non-root  (bioturing/bioturing-ecosystem12:8.0.10)"
echo "     - app runs as www-data (uid 33)"
echo "     - uses docker-compose.nonroot.yml (WITH storage-init chown helper)"
echo "     - this is the standard/default mode"
echo "  2) root      (bioturing/bioturing-ecosystem12:8.0.11)"
echo "     - app runs as root"
echo "     - uses docker-compose.root.yml (NO storage-init, no depends_on"
echo "       storage-init — per Lens's instruction)"
echo
MODE_CHOOSE="$(get IMAGE_MODE)"
if [ -z "$MODE_CHOOSE" ]; then
  read -rp "  Choose 1 / 2: " MODE_CHOOSE
fi
case "$MODE_CHOOSE" in
  1|nonroot) MODE_CHOOSE=nonroot ;;
  2|root)    MODE_CHOOSE=root ;;
  *) echo "aborted — nothing was changed"; exit 1;;
esac
log "image mode selected: ${MODE_CHOOSE}"

setenv() { # KEY VALUE — append or replace in .env
  if grep -q "^${1}=" .env 2>/dev/null; then
    sed -i.bak "s|^${1}=.*|${1}=${2}|" .env && rm -f .env.bak
  else
    echo "${1}=${2}" >> .env
  fi
}

if [ "$MODE_CHOOSE" = "nonroot" ]; then
  setenv IMAGE_MODE nonroot
  setenv BIOTURING_IMAGE bioturing/bioturing-ecosystem12:8.0.10
else
  setenv IMAGE_MODE root
  setenv BIOTURING_IMAGE bioturing/bioturing-ecosystem12:8.0.11
fi
# link the matching compose file as the active one (never overwrites a
# tenant-tailored regular docker-compose.yml — only the pair symlink)
if [ -e docker-compose.yml ] && [ ! -L docker-compose.yml ]; then
  log "docker-compose.yml is a regular (tenant-tailored) file — left untouched"
else
  ln -sf "docker-compose.${MODE_CHOOSE}.yml" docker-compose.yml
  log "active compose: docker-compose.${MODE_CHOOSE}.yml -> docker-compose.yml"
fi

# ------------------------------------------------------------------ 2) dirs --
# Folder structure: every dir from .env is validated; a MISSING one is
# CREATED. An EXISTING one is never touched (never deleted, never chowned
# unless it is a fresh empty sonya dir — data safety first).
log "=== folder structure check (create missing, never delete) ==="
for key in STORAGE_DIR DATABASE_DIR GATEWAY_STORAGE_DIR WORKSPACE_DATA_DIR WORKSPACE_HOMES_DIR POSTGRES_DATA_DIR; do
  d="$(get "$key")"
  if [ -z "$d" ]; then
    echo "  [FAIL] $key is empty in .env"
    exit 1
  fi
  if [ -d "$d" ]; then
    log "dir exists: $d"
  else
    mkdir -p "$d" && log "created: $d"
  fi
done
# sonya-side ownership (learned from the live roll-out):
#   gateway / workspace dirs -> 0:0 (sonya-gateway + jupyter volume-guard)
#   postgres dir -> leave as created (postgres chowns to uid 70 itself)
#   NEVER chown an initialized postgres data dir
PGDIR="$(get POSTGRES_DATA_DIR)"
if [ -d "$PGDIR" ] && [ -z "$(ls -A "$PGDIR" 2>/dev/null)" ]; then
  chown 0:0 "$(get GATEWAY_STORAGE_DIR)" "$(get WORKSPACE_DATA_DIR)" "$(get WORKSPACE_HOMES_DIR)" 2>/dev/null || true
  log "ownership set: gateway-storage/workspace-data/workspace-homes -> 0:0"
fi

# ------------------------------------- 3) secrets validation / generation ----
# Missing = empty, placeholder (<...>, __...__) or REDACTED.
# sonya-stack secrets: generated ONCE if missing, NEVER regenerated after
#   the first deploy (SONYA_GATEWAY_SECURITY__SECRET_KEY encrypts users'
#   LLM API keys — regenerating loses them all).
# Legacy-carried secrets (JWT_SECRET, BIOTURING_TOKEN, ...): NEVER generated
#   here — they must be carried verbatim from the legacy container/env.
gen() { openssl rand -base64 24 | tr -d '\n'; }

secret_value_ok() { # KEY — exits 0 if the value is a real (non-placeholder) secret
  local v
  v="$(grep "^${1}=" .env 2>/dev/null | head -1 | cut -d= -f2-)"
  [ -n "$v" ] || return 1
  case "$v" in
    REDACTED|change-me|CHANGE_ME|"<"*|"__"*) return 1;;   # placeholder detected
  esac
  return 0
}

for k in SONYA_DB_PASSWORD SONYA_GATEWAY_SECURITY__SECRET_KEY WORKSPACE_JWT_SECRET; do
  if secret_value_ok "$k"; then
    log "$k already present (kept — NEVER regenerate)"
  else
    setenv "$k" "$(gen)"
    log "$k was missing/placeholder -> GENERATED and filled"
  fi
done

# ------------------------------------------------------------------ 4) mode --
chmod 600 .env app-extra.env
chown root:root .env app-extra.env
log "permissions set: .env + app-extra.env -> 600 root:root"

# ------------------------------------- 4b) final secrets validation ----------
# fail if anything is still missing after the generation pass (e.g. a
# legacy-carried secret the operator forgot to fill)
MISSING=0
for k in SONYA_DB_PASSWORD SONYA_GATEWAY_SECURITY__SECRET_KEY WORKSPACE_JWT_SECRET \
         JWT_SECRET BIOTURING_TOKEN; do
  if secret_value_ok "$k"; then :; else
    echo "  [FAIL] $k is still missing/placeholder in .env"
    case "$k" in JWT_SECRET|BIOTURING_TOKEN)
      echo "         (legacy-carried secret — CANNOT be generated, copy it"
      echo "          verbatim from the legacy container/env)";; esac
    MISSING=1
  fi
done
[ "$MISSING" = "0" ] || { echo "ERROR: fix the [FAIL] items above and re-run"; exit 1; }
log "all secrets validated: present and non-placeholder"

# ------------------------------------------------- 5) compose render check ---
if docker compose config >/dev/null 2>&1; then
  log "docker compose config renders OK (mode: ${MODE_CHOOSE})"
elif docker-compose config >/dev/null 2>&1; then
  log "docker-compose config renders OK (mode: ${MODE_CHOOSE})"
else
  echo "ERROR: docker compose config failed:"; docker-compose config 2>/dev/null || docker compose config; exit 1
fi

log "=== prepare finished (mode: ${MODE_CHOOSE}). Next: validate_sonya.sh, then deploy_sonya.sh ==="
cat <<EOS

PREPARE DONE (mode: ${MODE_CHOOSE}).
  next steps:
    1) sudo bash ${DEPLOY_DIR}/validate_sonya.sh
       (optional: --legacy auto — compares the legacy container's env
        with this deployment and lists what may need adding)
    2) sudo bash ${DEPLOY_DIR}/deploy_sonya.sh   (menu: 1=dry-run first)
EOS
