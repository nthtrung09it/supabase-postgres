# PG 18 Troubleshooting Guide

## Build Failures

### PostGIS: `postgis.pl line 90 missing file`

```
File postgis--TEMPLATED--TO--ANY.sql is missing at ../../loader/postgis.pl line 90
```

**Cause**: PostGIS 3.6.x added `install-extension-upgrades-from-known-versions` make target that calls `postgis.pl --pg_sharedir` pointing to PostgreSQL's read-only Nix store path instead of `$out`.

**Attempted fix**: `find . -name 'GNUmakefile' -o -name 'Makefile' | xargs sed -i 's/install-extension-upgrades-from-known-versions//g'` in `postConfigure`. This is in `nix/ext/postgis.nix` but doesn't fully work in the Nix sandbox.

**Resolution**: Exclude PostGIS from PG 18 until PostGIS upstream fixes the build system or a workaround is found.

### RUM: `conflicting types for 'PostingItem'`

```
src/rum.h:191:3: error: conflicting types for 'PostingItem'; have 'struct <anonymous>'
```

**Cause**: PG 18 changed GiST/GIN internal structures. RUM redefines `PostingItem` which now conflicts.

**Resolution**: Exclude RUM from PG 18 until upstream updates for PG 18 ABI.

### pg_stat_monitor: `no installation script for version "2.3.1"`

The extension binary builds but the SQL installation script may be missing at runtime.

**Workaround**: Extension is available but may fail `CREATE EXTENSION`. Shows as "not enabled" in tests.

### EXECUTE PROCEDURE errors during migration

```
ERROR: syntax error at or near "PROCEDURE"
```

**Cause**: PG 18 removed deprecated `EXECUTE PROCEDURE` trigger syntax.

**Fix**: Ensure all migration SQL files are patched:
- Dockerfile-18 line 179-180 handles this for Docker builds
- run-server.sh.in handles this for Nix dev server (copies to temp dir first)

## Configuration Issues

### `db_user_namespace` error on startup

```
FATAL: unrecognized configuration parameter "db_user_namespace"
```

**Cause**: PG 18 removed `db_user_namespace` GUC.

**Fix**: Comment it out in postgresql.conf:
```bash
sed -i 's/db_user_namespace = off/#db_user_namespace = off/g;' postgresql.conf
```

### `plan_filter` shared library not found

```
FATAL: could not access file "plan_filter": No such file or directory
```

**Cause**: `plan_filter` left in `shared_preload_libraries` but extension is excluded.

**Fix**: Remove from shared_preload_libraries:
```bash
sed -i 's/, plan_filter//g;' postgresql.conf
```

### `pg_plan_filter` sed pattern does nothing

The supautils.conf template uses `plan_filter.*` (in `privileged_role_allowed_configs`), NOT `pg_plan_filter`. A sed pattern targeting `pg_plan_filter` is a no-op.

**Correct**: `sed -i 's/ plan_filter\.[*],//g' supautils.conf`
**Wrong**: `sed -i 's/ pg_plan_filter,//g' supautils.conf`

## Docker Image Issues

### Image too large (>1GB)

Check if groonga profile removal is in the Dockerfile:
```dockerfile
nix profile remove --regex '.*supabase-groonga.*' && \
nix store gc
```

Without this, groonga build deps remain (~300MB extra).

### Nix binary cache not working

Verify the cache mount ID matches: `--mount=type=cache,target=/nix-binary-cache,id=nix-bc-pg18`

Different `id` values create separate caches. First build always takes ~40 min.

### sed -i fails on macOS in Nix dev server

macOS BSD sed requires `sed -i ''` (with empty backup suffix). The run-server.sh.in handles this by branching on `$CURRENT_SYSTEM`:
- Linux: `sed -i 's/...//g'`
- macOS: `perl -pi -e 's/...//g'`

## Test Failures

### z_18_ext_interface.out mismatch

The expected output file must be generated from a real PG 18 instance. If extensions change (added/removed), regenerate:

```bash
docker run -d --name pg18-test -e POSTGRES_PASSWORD=postgres supabase/postgres:18-local
# wait for ready
cat nix/tests/prime-18.sql | docker exec -i pg18-test psql -U supabase_admin -d postgres
cat nix/tests/sql/z_18_ext_interface.sql | docker exec -i pg18-test psql -U supabase_admin -d postgres > nix/tests/expected/z_18_ext_interface.out
docker rm -f pg18-test
```

### Nix store is read-only for migration patching

When using `nix run .#start-server 18`, migrations are in the Nix store (immutable). The EXECUTE PROCEDURE patch copies to a temp dir first:

```bash
TEMP_MIGRATIONS=$(mktemp -d)
cp -r "$MIGRATIONS_DIR"/* "$TEMP_MIGRATIONS"/
find "$TEMP_MIGRATIONS" -name '*.sql' -exec sed -i 's/EXECUTE PROCEDURE/EXECUTE FUNCTION/g' {} +
MIGRATIONS_DIR="$TEMP_MIGRATIONS"
```
