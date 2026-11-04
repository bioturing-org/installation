#!/usr/bin/env bash
# validate_sonya.sh — pre-flight validation for the GENERIC Sonya deployment.
#
# Usage:
#   bash validate_sonya.sh             read-only checks
#   bash validate_sonya.sh --fix        additionally: generates missing sonya
#                                      secrets, creates missing mount dirs,
#                                      strips inline comments from env values
#   bash validate_sonya.sh --legacy <container-name>
#                                      compare the legacy container's env with
#                                      this deployment's env (advisory)
#   bash validate_sonya.sh --legacy auto
#                                      auto-detect the legacy container (any
#                                      running bioturing-ecosystem container
#                                      that is not part of this stack)
#
# Design rules (operator decisions — do NOT change):
#   - NO external business DB anywhere: DATABASE_PG_* are NOT validated.
#   - BIOTURING_TOKEN: expiry / domain / even empty NEVER fails the deploy —
#     warning only. The token is carried from legacy and refreshed by Lens.
#   - env hygiene: value lines must NOT carry inline '#' comments (the
#     genentech 503 root cause — docker env_file passes them verbatim).
#   - compose missing -> install_compose.sh is run automatically.
#
# Exit 0 = ready for deploy_sonya.sh, exit 1 = [FAIL] items present.
set -uo pipefail

DEPLOY_DIR="$(cd "$(dirname "$0")" && pwd)"
FAILS=0; WARNS=0

ok()   { echo "  [ OK ] $*"; }
warn() { echo "  [WARN] $*"; WARNS=$((WARNS+1)); }
fail() { echo "  [FAIL] $*"; FAILS=$((FAILS+1)); }
hdr()  { echo; echo "== $* =="; }

cd "$DEPLOY_DIR" || { echo "ERROR: ${DEPLOY_DIR} not found"; exit 1; }
get() { grep "^${1}=" .env 2>/dev/null | head -1 | cut -d= -f2- | sed -e 's/[[:space:]]*#.*$//' | tr -d '\r' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//'; }

FIX=0
LEGACY=""
for arg in "$@"; do
    case "$arg" in
        --fix) FIX=1 ;;
        --legacy) : ;;
        auto) LEGACY="auto" ;;
        *) [ -z "$LEGACY" ] && LEGACY="$arg" ;;
    esac
done

# ------------------------------------------------ 0) docker compose present --
hdr "0. Docker compose"
COMPOSE_CMD=""
if docker compose version >/dev/null 2>&1; then
    COMPOSE_CMD="docker compose"
    ok "docker compose plugin available ($(docker compose version --short 2>/dev/null))"
elif command -v docker-compose >/dev/null 2>&1; then
    COMPOSE_CMD="docker-compose"
    ok "standalone docker-compose available ($(docker-compose version --short 2>/dev/null))"
elif [ -x ./install_compose.sh ]; then
    echo "  no compose command found — attempting install_compose.sh ..."
    if bash ./install_compose.sh && command -v docker-compose >/dev/null 2>&1; then
        COMPOSE_CMD="docker-compose"
        ok "docker-compose installed now"
    else
        warn "install_compose.sh failed — deploy will not be able to run"
    fi
else
    warn "no compose command and no install_compose.sh — image checks skipped"
fi

# ---------------------------------------------------------------- 1) files ----
hdr "1. Files"
for f in docker-compose.yml docker-compose.nonroot.yml docker-compose.root.yml \
         .env app-extra.env \
         prepare_sonya.sh deploy_sonya.sh; do
    [ -f "$f" ] && ok "$f present" || fail "$f MISSING"
done
[ -f .env ] && {
    m="$(stat -c %a .env)"
    [ "$m" = "600" ] && ok ".env mode 600 (root-only)" \
                     || warn ".env mode is $m, expected 600"
}
[ -f app-extra.env ] && {
    m="$(stat -c %a app-extra.env)"
    [ "$m" = "600" ] && ok "app-extra.env mode 600 (root-only)" \
                     || warn "app-extra.env mode is $m, expected 600"
}

# ------------------------------------------------- 1b) ENV HYGIENE (503 rule)
hdr "1b. Env hygiene (no inline comments on value lines)"
# The genentech incident: 'KEY=value # comment' — docker env_file passes the
# '#' text into the container verbatim -> the app's vhost/routing broke -> 503
# on every request. This check makes that class of bug impossible to miss.
env_hygiene() { # file
    local f="$1" bad
    [ -f "$f" ] || return 0
    bad="$(grep -nE '^[A-Za-z_][A-Za-z0-9_]*=.*#' "$f" || true)"
    if [ -n "$bad" ]; then
        echo "$bad" | sed -E "s/^([0-9]+):([A-Za-z_][A-Za-z0-9_]*)=.*/  [FAIL] $f:\\1  \\2=<value contains '#'>/" | head -10
        [ "$FIX" = "1" ] && {
            sed -i.bak -E 's/^([A-Za-z_][A-Za-z0-9_]*=[^#]*[^ #])[[:space:]]+#.*$/\1/' "$f" && rm -f "$f.bak"
            if grep -qE '^[A-Za-z_][A-Za-z0-9_]*=.*#' "$f"; then
                echo "    --fix could not fully clean $f — fix the lines above manually"
            else
                echo "    --fix: inline comments stripped from $f values"
            fi
        }
        return 1
    fi
    return 0
}
HYG=0
env_hygiene .env        || HYG=1
env_hygiene app-extra.env || HYG=1
[ "$HYG" = "0" ] && ok ".env and app-extra.env: no inline comments on value lines"

# ------------------------------------------------- 2) image mode consistency --
hdr "2. Image mode (root / non-root)"
MODE="$(get IMAGE_MODE)"
case "$MODE" in
    nonroot) ok "IMAGE_MODE=nonroot (8.0.10, www-data, storage-init needed)";;
    root)    ok "IMAGE_MODE=root (8.0.11, runs as root, NO storage-init)";;
    *)       fail "IMAGE_MODE='${MODE}' — run prepare_sonya.sh first (it asks root/non-root)";;
esac
IMG="$(get BIOTURING_IMAGE)"
if [ "$MODE" = "nonroot" ]; then
    echo "$IMG" | grep -q "8.0.10" \
        && ok "BIOTURING_IMAGE=${IMG} matches nonroot mode" \
        || fail "BIOTURING_IMAGE=${IMG} does not match nonroot mode (expected 8.0.10)"
    grep -q "^  storage-init:" docker-compose.yml 2>/dev/null \
        && ok "active compose HAS storage-init (required for non-root)" \
        || warn "active compose is MISSING storage-init — check docker-compose.yml"
else
    echo "$IMG" | grep -q "8.0.11" \
        && ok "BIOTURING_IMAGE=${IMG} matches root mode" \
        || fail "BIOTURING_IMAGE=${IMG} does not match root mode (expected 8.0.11)"
    grep -q "^  storage-init:" docker-compose.yml 2>/dev/null \
        && fail "active compose STILL HAS storage-init — for the ROOT image it must be REMOVED" \
        || ok "active compose has NO storage-init (correct for root image)"
fi
if [ -L docker-compose.yml ]; then
    tgt="$(readlink docker-compose.yml)"
    echo "$tgt" | grep -q "${MODE}" \
        && ok "docker-compose.yml -> ${tgt} (matches mode)" \
        || fail "docker-compose.yml -> ${tgt} does NOT match mode '${MODE}' — re-run prepare"
fi

# ------------------------------------------------------ 3) .env completeness --
hdr "3. .env completeness"
REQUIRED_KEYS="IMAGE_MODE BIOTURING_IMAGE APPLICATION_DOMAIN CONTAINER_NAME JUPYTER_CONTAINER_NAME COMPOSE_PROJECT_NAME BIND_ADDRESS APP_PORT APP_CPUS APP_MEMORY_LIMIT GPU_DRIVER STORAGE_DIR DATABASE_DIR GATEWAY_STORAGE_DIR WORKSPACE_DATA_DIR WORKSPACE_HOMES_DIR POSTGRES_DATA_DIR SSL_DIR JWT_SECRET"
# BIOTURING_TOKEN deliberately NOT here: empty/expired/mismatched must NEVER
# fail the deploy — section 7 reports it as warnings only (Lens refreshes it).
ENV_MISSING=0
for key in $REQUIRED_KEYS; do
    v="$(get "$key")"
    if [ -z "$v" ]; then fail "$key is empty/unset in .env"; ENV_MISSING=1; fi
done
[ "$ENV_MISSING" = "0" ] && ok "all required .env keys are filled"

# NO external business DB anywhere — DATABASE_PG_* are NOT validated (operator rule).
ok "no external business DB by design — DATABASE_PG_* not checked"

# ------------------------------------------------------------- 4) secrets ------
hdr "4. Secrets"
secret_value_ok() {
    local v
    v="$(get "$1")"
    [ -n "$v" ] || return 1
    case "$v" in
        REDACTED|change-me|CHANGE_ME|"<"*|"__"*) return 1;;
    esac
    return 0
}
for k in SONYA_DB_PASSWORD SONYA_GATEWAY_SECURITY__SECRET_KEY WORKSPACE_JWT_SECRET; do
    if secret_value_ok "$k"; then
        v="$(get "$k")"
        if [ "${#v}" -ge 16 ]; then ok "$k set (len ${#v})"
        else fail "$k too short (${#v} chars)"; fi
    elif [ "$FIX" = "1" ]; then
        NEW="$(openssl rand -base64 24 | tr -d '\n')"
        if grep -q "^${k}=" .env 2>/dev/null; then
            sed -i.bak "s|^${k}=.*|${k}=${NEW}|" .env && rm -f .env.bak
        else
            echo "${k}=${NEW}" >> .env
        fi
        ok "$k was missing/placeholder -> GENERATED and filled (--fix)"
    else
        fail "$k missing/placeholder — run: bash validate_sonya.sh --fix (or prepare_sonya.sh)"
    fi
done
JWT="$(get JWT_SECRET)"
[ -n "$JWT" ] && ok "JWT_SECRET set (carried verbatim from legacy — length not enforced, NEVER generated)" \
              || fail "JWT_SECRET empty (legacy-carried — copy verbatim from the legacy container/env)"

# ---------------------------------------------------- 4b) LEGACY ENV COMPARE --
# reads docker inspect of the legacy container and reports which env vars it
# has that this deployment does NOT configure yet (advisory — informational).
legacy_compare() { # container-name
    local LC_NAME="$1" LC_ENV OUR_KEYS extra
    LC_ENV="$(docker inspect "$LC_NAME" --format '{{range .Config.Env}}{{println .}}{{end}}' 2>/dev/null | grep -E '^[A-Za-z_][A-Za-z0-9_]*=')"
    [ -z "$LC_ENV" ] && { warn "could not read env of container '${LC_NAME}' (not running/accessible)"; return; }
    # keys we already configure (values stripped, so only KEY= lines)
    OUR_KEYS="$( { grep -E '^[A-Za-z_][A-Za-z0-9_]*=' .env 2>/dev/null | cut -d= -f1
                   grep -E '^[A-Za-z_][A-Za-z0-9_]*=' app-extra.env 2>/dev/null | cut -d= -f1
                   grep -oE '\$\{[A-Za-z_][A-Za-z0-9_]*[:?]?' docker-compose.*.yml 2>/dev/null | tr -d '${}:' | sed 's/?.*//'
                 } | sort -u )"
    echo "  legacy container : ${LC_NAME}"
    echo "  comparing its env with .env + app-extra.env + compose environment ..."
    local n=0
    while IFS= read -r kv; do
        key="${kv%%=*}"
        # skip pure image-default noise:
        case "$key" in
            PATH|CUDA_*|NODE_VERSION|TINI*|HOSTNAME|HOME|LANG|LC_*|TERM|PWD|SHLVL|_) continue ;;
        esac
        if ! echo "$OUR_KEYS" | grep -qx "$key"; then
            val="${kv#*=}"
            # do not print secret values
            case "$val" in
                '') echo "    ${key}=(empty)";;
                *)  echo "    ${key}=<set, $(echo "$val" | wc -c | tr -d ' ') chars>";;
            esac
            n=$((n+1))
        fi
    done <<< "$LC_ENV"
    if [ "$n" = "0" ]; then
        ok "legacy container has no extra env vars beyond this deployment's configuration"
    else
        warn "$n legacy env vars are NOT configured in this deployment (see list above)."
        echo "        -> Review each: if the 8.0.x app still needs it, add it to"
        echo "           app-extra.env (value VERBATIM, no inline comments)."
        echo "        -> If it is obsolete/image-default, ignore it."
    fi
    # reverse check: warn if a value we set carries a '#' (pollution on copy)
    if echo "$LC_ENV" | grep -qE '^[A-Za-z_][A-Za-z0-9_]*=.*#'; then
        warn "legacy container itself has '#' in env values — copy carefully (strip comments)"
    fi
}
if [ -n "$LEGACY" ]; then
    hdr "4b. Legacy container env comparison"
    if [ "$LEGACY" = "auto" ]; then
        LEG_AUTO="$(docker ps --format '{{.Names}}\t{{.Image}}' 2>/dev/null \
                    | grep -E 'bioturing.*ecosystem' \
                    | grep -v "$(get CONTAINER_NAME)" \
                    | grep -v "$(get COMPOSE_PROJECT_NAME)" \
                    | head -1 | cut -f1)"
        if [ -n "$LEG_AUTO" ]; then
            legacy_compare "$LEG_AUTO"
        else
            warn "no other bioturing-ecosystem container running — nothing to compare"
        fi
    else
        legacy_compare "$LEGACY"
    fi
fi

# --------------------------------------------------------- 5) mount points -----
hdr "5. Mount points"
check_dir() { # VAR  create-if-fix
    local v; v="$(get "$1")"
    if [ -z "$v" ]; then fail "$1 empty"; return; fi
    if [ -d "$v" ]; then ok "$1 -> $v (exists)"
    elif [ "$FIX" = "1" ]; then
        mkdir -p "$v" && ok "$1 -> $v (CREATED by --fix)" || fail "$1 -> $v : mkdir failed"
    else
        fail "$1 -> $v : directory does not exist (validate --fix creates it)"
    fi
}
check_dir STORAGE_DIR
check_dir DATABASE_DIR
check_dir GATEWAY_STORAGE_DIR
check_dir WORKSPACE_DATA_DIR
check_dir WORKSPACE_HOMES_DIR
check_dir POSTGRES_DATA_DIR
dirs=("$(get STORAGE_DIR)" "$(get DATABASE_DIR)" "$(get GATEWAY_STORAGE_DIR)" \
      "$(get WORKSPACE_DATA_DIR)" "$(get WORKSPACE_HOMES_DIR)" "$(get POSTGRES_DATA_DIR)")
if [ "$(printf '%s\n' "${dirs[@]}" | sort -u | wc -l | tr -d '[:space:]')" = "${#dirs[@]}" ]; then
    ok "all mount dirs are distinct"
else
    fail "two or more mount dirs point to the same path"
fi

# 5b) compose volume mounts vs. dirs configured
hdr "5b. Volume mounts (docker compose config)"
if [ -n "$COMPOSE_CMD" ]; then
    VOL_LIST="$($COMPOSE_CMD config 2>/dev/null | grep -E '^\s+- [^-].*:/' | sed 's/^\s*- //' | sort -u)"
    if [ -n "$VOL_LIST" ]; then
        MISSING_MNT=0
        while IFS= read -r mnt; do
            host="${mnt%%:*}"
            # skip named volumes (no leading /) and anonymous
            case "$host" in /*) ;; *) continue ;; esac
            if [ -d "$host" ]; then
                ok "mount ${host} -> ${mnt#*:} (exists)"
            else
                if [ "$FIX" = "1" ]; then
                    mkdir -p "$host" && ok "mount ${host} -> ${mnt#*:} (CREATED by --fix)" || fail "mkdir failed: $host"
                else
                    warn "mount source ${host} does not exist (validate --fix creates it)"
                    MISSING_MNT=1
                fi
            fi
        done <<< "$VOL_LIST"
        [ "$MISSING_MNT" = "0" ] && [ -n "$VOL_LIST" ] && ok "all compose mount sources exist"
    else
        warn "could not parse mounts from compose config — verify manually"
    fi
else
    warn "compose unavailable — mount checks limited to .env dirs"
fi

# ----------------------------------------------------------- 6) networking -----
hdr "6. Networking"
APP_PORT="$(get APP_PORT)"; BIND_ADDRESS="$(get BIND_ADDRESS)"
if ss -tln | awk '{print $4}' | grep -qE ":${APP_PORT}\$"; then
    HOLDER="$(docker ps --format '{{.Names}} {{.Ports}}' | grep -E ":${APP_PORT}->" | awk '{print $1}' | head -1)"
    if [ "$HOLDER" = "$(get CONTAINER_NAME)" ]; then
        ok "port ${APP_PORT} is held by the deployed app container — stack is live"
    else
        fail "port ${APP_PORT} already in use (holder: ${HOLDER:-unknown})"
    fi
else
    ok "APP_PORT ${APP_PORT} is free"
fi
case "$APP_PORT" in
    80|443)
        if [ "$BIND_ADDRESS" = "127.0.0.1" ]; then
            fail "APP_PORT=${APP_PORT} with BIND_ADDRESS=127.0.0.1 — direct pattern needs 0.0.0.0 (or the intended interface)"
        else
            ok "direct pattern: ${BIND_ADDRESS}:${APP_PORT} (no HAProxy in front)"
            warn "app serves PLAIN HTTP on 8080 in-container — TLS must terminate in front (edge LB / HAProxy)"
        fi ;;
    *)
        [ "$BIND_ADDRESS" = "127.0.0.1" ] && ok "BIND_ADDRESS=127.0.0.1 + APP_PORT=${APP_PORT} (fronted by HAProxy)" \
                                                || warn "BIND_ADDRESS=${BIND_ADDRESS} — confirm exposure is intended" ;;
esac

# ------------------------------------------------------------ 7) license ------
hdr "7. License token (BIOTURING_TOKEN)"
# Operator rule: the token NEVER fails the deploy. Expiry / domain mismatch /
# even empty are WARNINGS only — the token is legacy-carried and refreshed by
# Lens; deployment must not be blocked on it.
BT="$(get BIOTURING_TOKEN)"
if [ -n "$BT" ]; then
    EXP="$(python3 - "$BT" <<'PY' 2>/dev/null
import sys, base64, json
p = sys.argv[1].split('.')[1]
p += '=' * (-len(p) % 4)
try:
    print(json.loads(base64.urlsafe_b64decode(p)).get('expired_at', ''))
except Exception:
    print('')
PY
)"
    DOM="$(python3 - "$BT" <<'PY' 2>/dev/null
import sys, base64, json
p = sys.argv[1].split('.')[1]
p += '=' * (-len(p) % 4)
try:
    print(json.loads(base64.urlsafe_b64decode(p)).get('allow_domain', ''))
except Exception:
    print('')
PY
)"
    fmt_exp() { date -u -d @"$1" '+%Y-%m-%d %H:%M UTC' 2>/dev/null || date -u -r "$1" '+%Y-%m-%d %H:%M UTC' 2>/dev/null || echo "epoch $1"; }
    if [ -z "$EXP" ]; then
        warn "could not decode BIOTURING_TOKEN expiry (deploy allowed)"
    elif [ "$EXP" -lt "$(date +%s)" ]; then
        warn "BIOTURING_TOKEN EXPIRED ($(fmt_exp "$EXP")) — deploy ALLOWED; ask Lens for a fresh token"
    else
        ok "BIOTURING_TOKEN valid until $(fmt_exp "$EXP")"
    fi
    if [ "$DOM" = "$(get APPLICATION_DOMAIN)" ]; then
        ok "token allow_domain == $(get APPLICATION_DOMAIN)"
    else
        warn "token allow_domain is '${DOM}', expected $(get APPLICATION_DOMAIN) — deploy allowed"
    fi
else
    warn "BIOTURING_TOKEN empty — deploy ALLOWED; paste the legacy token in .env when available"
fi

# ------------------------------------------------------------- 8) images ------
hdr "8. Images (docker compose config)"
if [ -n "$COMPOSE_CMD" ]; then
    IMGS="$($COMPOSE_CMD config --images 2>/dev/null | sort -u)"
    if [ -n "$IMGS" ]; then
        while IFS= read -r img; do
            if docker image inspect "$img" >/dev/null 2>&1; then
                ok "$img (present locally)"
            else
                warn "$img not local yet — deploy script pulls it"
            fi
        done <<< "$IMGS"
    else
        warn "could not read images from $COMPOSE_CMD config — check manually"
    fi
fi

# ------------------------------------------------------------- GPU driver -----
GPU_DRIVER="$(get GPU_DRIVER)"
case "$GPU_DRIVER" in
    nvidia) ok "GPU_DRIVER=nvidia — all GPUs (count: all)" ;;
    cdi)    ok "GPU_DRIVER=cdi" ;;
    *)      fail "GPU_DRIVER must be 'nvidia' or 'cdi' (got: ${GPU_DRIVER})" ;;
esac

# ------------------------------------------------------- VALIDATION_STRING (always required)
if grep -qE '^VALIDATION_STRING=' app-extra.env 2>/dev/null; then
    if ! grep -qE '^VALIDATION_STRING=..' app-extra.env 2>/dev/null; then
        warn "VALIDATION_STRING is EMPTY — legit for open-access tenants, but confirm it matches the legacy env exactly (allowed login email-domain list)"
    else
        ok "VALIDATION_STRING present (login email-domain allow-list)"
    fi
else
    fail "VALIDATION_STRING line missing from app-extra.env — required (allowed login email-domain list, carried VERBATIM from legacy; keep the line even if legitimately empty)"
fi

# ------------------------------------------------------- SSO block completeness
if grep -qE '^[^#]*(OIDC_[A-Z_]+|T2DPROXY_OIDC_[A-Z_]+)=' app-extra.env 2>/dev/null; then
    if ! grep -qE '^[^#]*VALIDATION_STRING=' app-extra.env 2>/dev/null; then
        fail "SSO: OIDC_* vars set but VALIDATION_STRING line missing — carry it VERBATIM from the legacy env (SSO login breaks without it)"
    elif ! grep -qE '^[^#]*VALIDATION_STRING=..' app-extra.env 2>/dev/null; then
        warn "SSO: VALIDATION_STRING is EMPTY — legit in some tenants, but confirm it matches the legacy env exactly"
    else
        ok "SSO: OIDC_* block present and VALIDATION_STRING kept"
    fi
fi

# ------------------------------------------------------------- summary --------
hdr "Summary"
[ "$WARNS" -gt 0 ] && echo "  warnings: $WARNS (advisory — never block a deploy)"
if [ "$FAILS" = "0" ] && [ "$FIX" = "1" ]; then
    echo "  (--fix applied: secrets generated / missing dirs created where needed)"
fi
if [ "$FAILS" -gt 0 ]; then
    echo "  FAILURES: $FAILS"
    echo "  RESULT: NOT READY — fix [FAIL] items first"
    exit 1
fi
echo "  RESULT: READY for deploy_sonya.sh (menu 1 = dry-run first)"
exit 0
