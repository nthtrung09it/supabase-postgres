# Supabase Postgres 18 for CloudNativePG

Builds `harbor.trungnguyen.dev/elearning/cnpg-supabase-postgres` from the
Supabase Postgres 18 base image (`Dockerfile-18` →
`harbor.trungnguyen.dev/elearning/supabase-postgres`), adding:

- **barman-cloud** — CNPG's in-tree `barmanObjectStore` WAL archiving / base backups
- **dbmate** — runs the Supabase migrations idempotently (`internal.schema_migrations`)
- **migration scripts** at `/tmp/elearning-scripts-origin` + `/tmp/run-migrations.sh`,
  which the CNPG migration job runs inside the primary pod

Port of hello-k3s-ansible's `build-cnpg-postgres` skill (steps 1–2), automated.

## Build

`.github/workflows/build-cnpg-supabase-postgres-18.yml`, on an ephemeral DO droplet:

- push to `pg-18-6` with `[ci cnpg]` in the commit message, or
- `workflow_dispatch` (inputs: `base_image`, `supabase_ref`)

Tag: `<postgres18 release from ansible/vars.yml>-<sha8>` and `18-latest`.

## What stays current automatically

Every build:

1. `fetch-supabase-selfhosted.sh` pulls the official self-hosted DB files from
   [supabase/supabase `docker/`](https://github.com/supabase/supabase/tree/master/docker)
   at `master` (resolved to a commit SHA, recorded as the image label
   `dev.trungnguyen.supabase-selfhosted.revision`). The file list and their
   `initdb.d` names are read from `docker/docker-compose.yml`, not hard-coded.
2. The Dockerfile combines them with the base image's own
   `/docker-entrypoint-initdb.d` (this repo's `migrations/db`).
3. `generate-templates.sh` generates the dbmate-compatible templates +
   `mapping.txt` (the skill's hand-made `processed-templates/`) and validates
   them with a `process-templates.sh` dry run.

The build **fails** — rather than shipping something wrong — on: psql syntax
the generator doesn't know, a dbmate version clash, a variable
`process-templates.sh` doesn't substitute, a `renames.txt` source that no longer
exists, or a `migrate.sh` change that breaks `run-migrations.sh`'s patch.

## What is maintained by hand

| File | When to change it |
|---|---|
| `base-image` | a new base image was built (bump the pinned ref) |
| `renames.txt` | the build reports a dbmate version clash or a missing rename source |
| `process-templates.sh`, `run-migrations.sh` | deploy-time behaviour (unchanged from the skill) |

## Known deviation from official self-hosting

Upstream `logs.sql` / `pooler.sql` run `\c _supabase` to create the `_analytics`
and `_supavisor` schemas **in the `_supabase` database**. dbmate runs a file on a
single connection, so (as in the skill's templates) the `\c` lines are dropped
and those schemas are created in the migration database (`postgres`).

## Local build

```bash
sh cnpg/fetch-supabase-selfhosted.sh master cnpg/.upstream
docker buildx build --platform linux/amd64 -f cnpg/Dockerfile \
  --build-arg BASE_IMAGE="$(cat cnpg/base-image)" \
  --build-arg SUPABASE_SHA="$(cat cnpg/.upstream/supabase-sha)" \
  -t cnpg-supabase-postgres:local --load cnpg
```
