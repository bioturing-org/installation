# Sonya deployment template

Copy this folder per tenant.

## Rule

Never put a comment on the same line as a value in `.env` / `app-extra.env` —
docker env_file passes it verbatim into the container. Comments on their own
lines only. prepare + validate enforce this automatically (`--fix` strips).

## Flow

```bash
# fill .env + app-extra.env first (legacy values via docker inspect <legacy>)

sudo bash prepare_sonya.sh

sudo bash validate_sonya.sh   # --fix repairs, --legacy auto compares legacy env

sudo bash deploy_sonya.sh     # menu 1 = dry-run first, then 2
```

## deploy menu

```
1) dry-run   2) real   3) stop   4) start   5) restart
6) down      7) redeploy         8) exit
```

Non-interactive: `MODE=2 FORCE=YES CONFIRM=YES bash deploy_sonya.sh`

## Ports

- HAProxy in front: `APP_PORT=24000`, `BIND_ADDRESS=127.0.0.1`
- Direct: `APP_PORT=80`, `BIND_ADDRESS=0.0.0.0`

In-container: 8080 = plain HTTP (publish this), 4433 = HTTPS.
Health check: `GET /btstatus` returns 200 without auth.

`/sonya-gateway/*` is routed by the app image's internal haproxy to
`sonya-gateway:18020` over the shared docker network — no host proxy or
published ports needed.

## BioEngineX (separate compute service)

BioEngineX is NOT part of the compose stack — it runs as a standalone
docker container sharing the stack's network, user-data partition and JWT
secret. Four files manage it (same prepare/validate/deploy flow as the stack):

```bash
# after the sonya stack is UP (deploy_sonya.sh — it creates the network)

sudo bash prepare_bioenginex.sh

sudo bash validate_bioenginex.sh    # also usable post-deploy as a connectivity check

sudo bash deploy_bioenginex.sh      # menu 1 = dry-run first, then 2
```

### deploy menu

```
1) dry-run   2) deploy   3) status   4) stop   5) re-attach to network
```

### Contract (enforced by validate_bioenginex.sh)

- `BIOENGINEX_SHARED_VOLUME` in `bioenginex.env` MUST equal `STORAGE_DIR`
  in `.env` (both mounted at `/home/shared` — validate FAILS on drift)
- `BIOENGINEX_DATA_VOLUME` = private data, mounted at `/home/enginex`
  (default `<shared>/bioenginex`, legacy layout)
- mount targets `/home/shared` + `/home/enginex` are FIXED — the app hands
  BioEngineX absolute paths under `/home/shared`...
- `JWT_SECRET` is exported from `.env` at deploy time (single source of
  truth — never copied into `bioenginex.env`, drift is impossible)
- container name `bioturing-bioenginex` must appear in `NO_PROXY` in
  `app-extra.env`
- network: `<COMPOSE_PROJECT_NAME>_bioturing` (created by deploy_sonya.sh)
- ports: 35576 (HTTP) / 35577 (RPC), published on the host

### After any sonya `compose down` + `up`

The network is recreated and BioEngineX is silently dropped from it — run
`deploy_bioenginex.sh` menu option 5 to re-attach (or full re-deploy).

## Policies

- No external business DB (`DATABASE_PG_*` not shipped, not validated)
- BIOTURING_TOKEN expiry / empty = warning only, never blocks deploy
- Dirs: created if missing, never deleted
- JWT_SECRET / BIOTURING_TOKEN: carried from legacy, never changed
- SONYA_DB_PASSWORD / SONYA_GATEWAY_SECURITY__SECRET_KEY / WORKSPACE_JWT_SECRET:
  generated once by prepare, never regenerated
- root image = 8.0.12, nonroot = 8.0.10 — prepare asks and links the compose
