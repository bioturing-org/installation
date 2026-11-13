#!/bin/bash
# backup_sonya_pg.sh — safety backup of the sonya-postgres container.
# Called from deploy_sonya.sh (modes 2 and 7) right after the DATABASE_DIR
# backup, before any container is touched. Reads the RUNNING postgres via
# pg_dumpall (consistent snapshot, no stop needed) and writes a dump to
# $(dirname POSTGRES_DATA_DIR)/postgres_backups/<UTC timestamp>/.
# Copy-only: never deletes, prunes, restarts, or modifies ANYTHING.
# Restore: docker exec -i <pg-container> psql -U sonya < gunzip -c <dump>
set -o pipefail
cd "$(dirname "$0")"

[ -f .env ] || { echo "ERROR: run from the tenant folder (needs .env)"; exit 1; }

PG_DIR="$(grep '^POSTGRES_DATA_DIR=' .env | head -1 | cut -d= -f2- | tr -d '"')"
PROJ="$(grep '^COMPOSE_PROJECT_NAME=' .env | head -1 | cut -d= -f2- | tr -d '"')"
PGPASS="$(grep '^SONYA_DB_PASSWORD=' .env | head -1 | cut -d= -f2- | tr -d '"')"

# locate the RUNNING sonya-postgres container (fresh install -> skip)
PG_C="$(docker ps --filter name="${PROJ}-sonya-postgres" --format '{{.Names}}' | head -1)"
if [ -z "${PG_C}" ]; then
    echo "[backup-pg] no running sonya-postgres found — nothing to back up"
    exit 0
fi

ts="$(date -u +%Y%m%dT%H%M%SZ)"
dst="${PG_BACKUP_DIR:-$(dirname "${PG_DIR}")/postgres_backups}"
out="${dst}/${ts}/sonya_all_${ts}.sql.gz"

# space check — abort rather than write a partial dump
free="$(df -Pm "${dst:-.}" 2>/dev/null | awk 'NR==2{print $4}')"
[ -n "$free" ] && [ "$free" -lt 1024 ] && { echo "!! under 1GB free at ${dst} — abort"; exit 1; }

mkdir -p "${dst}/${ts}"
echo "[backup-pg] dumping ${PG_C} -> ${out}"
if docker exec -e PGPASSWORD="${PGPASS}" "${PG_C}" pg_dumpall -U sonya | gzip > "${out}"; then
    echo "[backup-pg] complete: ${out} ($(du -h "${out}" | cut -f1))"
    exit 0
fi
echo "!! backup FAILED — partial file may exist at ${out}"
exit 1
