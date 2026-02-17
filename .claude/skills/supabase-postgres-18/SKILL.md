---
name: supabase-postgres-18
description: >
  Build, configure, and troubleshoot PostgreSQL 18 support in supabase-postgres.
  Use when working on PG 18 Nix builds, Dockerfile-18, extension compatibility,
  migration issues, or Docker image optimization. Covers the full build pipeline
  from nix/config.nix to nix/ext/versions.json to nix/packages/postgres.nix to
  Dockerfile-18. Includes extension compatibility matrix, known build failures,
  and sed pattern fixes for config files.
---

# Supabase PostgreSQL 18 Build Guide

## Architecture Overview

PG 18 follows the same Nix + Docker multi-stage pattern as PG 15/17:

```
nix/config.nix           -> PG 18.2 version + hash
nix/overlays/default.nix -> postgresql_18 overlay
nix/ext/versions.json    -> "18" in each extension's postgresql array
nix/packages/postgres.nix -> dbExtensions18 filter + psql_18/psql_18_slim
nix/checks.nix           -> psql_18 test harness (ports 5541/5542)
Dockerfile-18            -> Alpine multi-stage build
```

## Key Files to Modify

| File | What to change |
|------|---------------|
| `nix/config.nix` | Add PG version entry with hash |
| `nix/overlays/default.nix` | Add `postgresql_18` to inherit |
| `nix/ext/versions.json` | Add `"18"` to each compatible extension |
| `nix/packages/postgres.nix` | `dbExtensions18` filter, `psql_18`, `psql_18_slim` |
| `nix/checks.nix` | Test harness, port assignments, version detection |
| `nix/packages/default.nix` | Wire `psql_18` through to lib/client/test packages |
| `nix/packages/lib.nix` | Add `PSQL18_BINDIR` substitution |
| `nix/tools/run-server.sh.in` | PG 18 config patching + EXECUTE PROCEDURE fix |
| `nix/tests/prime-18.sql` | Extension load test primer |
| `nix/tests/sql/z_18_ext_interface.sql` | PG 18-specific test |
| `nix/tests/expected/z_18_ext_interface.out` | Expected output (generate from real run) |
| `ansible/vars.yml` | Add `"18"` to `postgres_major`, add release version |
| `Dockerfile-18` | Alpine + Nix multi-stage build |
| `migrations/schema-18.sql` | Auto-generated schema dump |
| `.github/workflows/docker-image-test.yml` | Add `Dockerfile-18` to matrix |
| `.github/workflows/cli-smoke-test.yml` | Add `'18'` to `pg_version` matrix |

## Extension Compatibility

See [references/extensions.md](references/extensions.md) for the full compatibility matrix.

**Quick summary**: 69 extensions work on PG 18. Excluded:
- **PostGIS** + pgrouting: Build system issue (`install-extension-upgrades-from-known-versions`)
- **RUM**: `PostingItem` type conflict in PG 18 headers
- **pg_jsonschema**: Needs pgrx 0.16.1+ (stuck on 0.12.6)
- **plv8**: Deprecated on PG 17+
- **pg_plan_filter**: GitHub repo deleted
- **TimescaleDB**: Not yet added for PG 18

## Critical PG 18 Differences

### EXECUTE PROCEDURE Removed
PG 18 removed deprecated `EXECUTE PROCEDURE` trigger syntax. Must use `EXECUTE FUNCTION`.
- **Dockerfile-18**: `find /docker-entrypoint-initdb.d -name '*.sql' -exec sed -i 's/EXECUTE PROCEDURE/EXECUTE FUNCTION/g' {} +`
- **run-server.sh.in**: Copy migrations to writable temp dir first (Nix store is read-only), then sed/perl replace. Use `perl -pi -e` on macOS, `sed -i` on Linux.

### db_user_namespace Removed
PG 18 removed the `db_user_namespace` GUC. Must comment it out:
```bash
sed -i 's/db_user_namespace = off/#db_user_namespace = off/g;' postgresql.conf
```

### supautils.conf Sed Patterns

Remove unavailable extensions from config. Common mistake: using `pg_plan_filter` instead of `plan_filter.*` for the `privileged_role_allowed_configs` entry.

Correct patterns:
```bash
# postgresql.conf shared_preload_libraries
sed -i 's/ timescaledb,//g;' postgresql.conf
sed -i 's/, plan_filter//g;' postgresql.conf

# supautils.conf privileged_extensions + comment
sed -i -e 's/ timescaledb,//g' -e 's/ plv8,//g' -e 's/ pg_jsonschema,//g' supautils.conf

# supautils.conf privileged_role_allowed_configs (note: plan_filter.* not pg_plan_filter)
sed -i 's/ plan_filter\.[*],//g' supautils.conf
```

## Dockerfile-18 Build

See [references/dockerfile.md](references/dockerfile.md) for the full Dockerfile pattern.

Key points:
- Uses `--mount=type=cache,target=/nix-binary-cache,id=nix-bc-pg18` for fast rebuilds
- Installs groonga separately, copies plugins, then removes groonga profile before GC to save ~300MB
- Image size: ~960MB uncompressed, ~297MB compressed (smaller than official PG 17)

Build command:
```bash
docker build -f Dockerfile-18 -t supabase/postgres:18-local .
```

## Generating Test/Schema Files

```bash
# schema-18.sql (start container, let migrations run, dump)
docker run -d --name pg18-schema -e POSTGRES_PASSWORD=postgres supabase/postgres:18-local
# wait for ready, then:
docker exec pg18-schema pg_dump -U supabase_admin -d postgres --schema-only --no-owner --no-privileges --restrict-key=SupabaseTestDumpKey123 > migrations/schema-18.sql

# z_18_ext_interface.out (run prime-18.sql then test SQL, capture output)
cat nix/tests/prime-18.sql | docker exec -i pg18-test psql -U supabase_admin -d postgres
cat nix/tests/sql/z_18_ext_interface.sql | docker exec -i pg18-test psql -U supabase_admin -d postgres > nix/tests/expected/z_18_ext_interface.out
```

## Troubleshooting

See [references/troubleshooting.md](references/troubleshooting.md) for known issues and fixes.
