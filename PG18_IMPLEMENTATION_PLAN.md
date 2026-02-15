# PostgreSQL 18.2 Support — Implementation Plan

**Branch:** `pg-18-v2` (fresh from `origin/develop`)
**Commit:** `d0428b57`
**Date:** 2026-02-15
**PG Version:** 18.2 (current stable, GA Sep 25, 2025)

---

## Background

The original `pg-18` branch diverged from `develop` at commit `493bd39a` (Sep 2025) with only 4 commits targeting PG 18rc1. Meanwhile, `origin/develop` advanced 210 commits over 5 months with major architectural changes:

- Slim/CLI package variants with `latestOnly` and `variant` parameters
- Restructured extensions (directories instead of single .nix files)
- Rewritten `makeOurPostgresPkgs` function signature
- New `makeCheckHarness` with `isCliVariant`, `legacyPkgName` parameters
- Alpine-based Docker multi-stage builds replacing Ubuntu

The old branch had 11 conflicting files and couldn't be rebased. A fresh branch from `origin/develop` was created instead.

---

## Phase 1: Analysis & Research

### Extension Compatibility Assessment

Researched all 28+ extensions against PG 18. Results:

| Status | Count | Extensions |
|--------|-------|------------|
| **Ready** | ~20 | pgvector, PostGIS, pgRouting, pgaudit, pgroonga, pg_stat_monitor, HypoPG, pgsql-http, plpgsql_check, pg_tle, index_advisor, pgjwt, pgmq, pg_cron, pg_repack, pg_hashids, pg_partman, pg_graphql, pgtap, supautils |
| **Blocked** | 4 | pg_net (build failure), pg_jsonschema (needs pgrx 0.16.1+), wrappers (needs pgrx 0.16.1+), rum (compat issues) |
| **Excluded (pattern)** | 3 | timescaledb, timescaledb-2.9.1, plv8 (following PG 17 exclusion pattern) |

---

## Phase 2: Core Build System

### `nix/config.nix`
- Added PG 18.2 version entry under `supportedPostgresVersions.postgres`
- Computed source hash: `sha256-cvBXxA7/kEwDGxFv/YoZCIh17jzUujrCtfKAmtSxKTw=`

### `nix/packages/postgres.nix`
- Created `dbExtensions18` filter list excluding 7 incompatible extensions:
  - `timescaledb.nix`, `timescaledb-2.9.1.nix`, `plv8` (pattern exclusions)
  - `pg_net.nix`, `pg_jsonschema`, `wrappers/default.nix`, `rum.nix` (blocked)
- Added version `"18"` routing in `extensionsToUse` within `makeOurPostgresPkgs`
- Added `psql_18` to `basePackages` and `psql_18_slim` to `slimPackages`

### `nix/overlays/default.nix`
- Added `postgresql_18` to the inherit list for the flake overlay

### `nix/ext/versions.json`
- Added `"18"` to the `postgresql` compatibility arrays for all ~20 PG 18-compatible extensions
- Did NOT add `"18"` to blocked extensions (pg_net, pg_jsonschema, wrappers, rum, timescaledb, plv8)

---

## Phase 3: Package Wiring

### `nix/packages/default.nix`
- Added `psql_18` to `pkgs-lib` call (for `lib.nix`)
- Added `psql_18` to `start-client` call
- Added `psql_18` to `docker-image-test` call
- Added `psql_18_slim` to `docker-image-inputs` call

### `nix/packages/lib.nix`
- Added `psql_18` function parameter
- Added `PSQL18_BINDIR = "${psql_18}"` to substitutions map

### `nix/packages/start-client.nix`
- Added `psql_18` parameter and PG 18 case for client connections

### `nix/packages/docker-image-inputs.nix`
- Added `psql_18_slim` to function parameters
- Added `Dockerfile-18` to the fileset unions
- Added `psql_18_slim` to package manifest, `buildInputs`, store path manifest, and JSON output

### `nix/packages/docker-image-test.nix`
- Added `psql_18` to function parameters
- Added `Dockerfile-18` case in `get_version_info` (port 5438)
- Added `18)` case in `get_test_list` for `z_18_*` test filtering
- Added `psql_18` binary paths for `PSQL_PATH`/`PG_ISREADY_PATH`
- Added `prime-18.sql` selection when `VERSION == "18"`

### `nix/packages/dbmate-tool.nix`
- Added version `18` handling for migration tool

---

## Phase 4: Test Infrastructure

### `nix/checks.nix`
- **Version detection:** Added `isEighteenMatch` regex pattern (`^18[.][0-9]+$`)
- **Major version routing:** Added `"18"` to `majorVersion` conditional
- **Port assignments:** PG 18 slim gets port 5541, PG 18 full gets port 5542
- **Test filtering:** Added `z_18_` pattern in `filterTestFiles`
- **Version argument:** Added `"18"` in `getVersionArg`
- **Prime file:** Both pgtap and pg_regress test phases use `prime-18.sql` for PG 18 (via `lib.boolToString (majorVersion == "18")` conditional)
- **Check entries:** Added `psql_18` and `psql_18_slim` check derivations
- **CLI skip list:** Added `z_18_ext_interface` to `cliSkipTests`
- **Linux checks:** Added `postgresql_18_debug` and `postgresql_18_src` to Linux-only checks

### `nix/tests/prime-18.sql` (new file)
- Copy of `prime.sql` with 4 extensions commented out:
  - `pg_net` — not available for PG 18
  - `pg_jsonschema` — needs pgrx update
  - `rum` — PG 18 compatibility issues
  - `wrappers` — needs pgrx update
- Prevents `ON_ERROR_STOP` failures from trying to create unavailable extensions

### `nix/tests/sql/z_18_ext_interface.sql` (new file)
- PG 18-specific extension interface monitoring test
- Queries: available-but-not-installed extensions, installed extension relocatability, function interfaces, table/view interfaces

### `nix/tests/expected/z_18_ext_interface.out` (new file)
- Expected output for the extension interface test
- 70 installed extensions (vs 71 for PG 17 — excludes `pg_net`)
- Note: May need minor adjustments after first real test run due to PG 18 built-in extension differences

---

## Phase 5: Shell Tools

### `nix/tools/run-server.sh.in`
- Added PG 18 BINDIR case (`PSQL18=@PSQL18_BINDIR@`)
- Added PG 18 config patching for both Linux (`sed`) and macOS (`perl`):
  - Removes `timescaledb` from `shared_preload_libraries`
  - Removes `pg_net` from `shared_preload_libraries`
  - Comments out `db_user_namespace = off` (deprecated in PG 16+)
  - Removes `timescaledb`, `plv8`, `pg_net`, `rum`, `pg_jsonschema`, `wrappers` from supautils config
- Fixed help text: was `"15, 18, orioledb-17"` → now `"15, 17, 18, orioledb-17"`

### `nix/tools/run-client.sh.in` (via start-client.nix)
- Added `18` to version options

### `nix/tools/dbmate-tool.sh.in` (via dbmate-tool.nix)
- Added `18` to version handling

---

## Phase 6: Docker

### `Dockerfile-18` (new file)
- Follows the established Alpine 3.21 + Nix multi-stage pattern from `Dockerfile-17`
- **Stage 1 (nix-builder):** Installs Nix, builds `psql_18_slim/bin` and `supabase-groonga`
- **Stage 2 (gosu-builder):** Downloads and verifies gosu
- **Stage 3 (production):** Alpine 3.21 minimal runtime with:
  - Nix store + profiles copied from builder
  - Groonga plugins, gosu, PostgreSQL configs
  - `sed` commands to remove unavailable extensions from `shared_preload_libraries` and supautils config
  - ICU locale provider in `POSTGRES_INITDB_ARGS`
  - `LOCALE_ARCHIVE` pointing to minimal glibc locales in slim Nix package

---

## Phase 7: Other

### `ansible/vars.yml`
- Added PG 18 entries for AMI builds

---

## Bug Fixes (Post-Review)

A code review after the initial implementation identified 7 issues:

### Critical (4)
1. **`docker-image-inputs.nix` missing `psql_18_slim` parameter** — Nix eval would fail. Fixed by adding the parameter and all references.
2. **`docker-image-test.nix` missing `psql_18` parameter** — Nix eval would fail. Fixed by adding parameter, Dockerfile-18 case, version routing.
3. **`prime.sql` creates excluded extensions with `ON_ERROR_STOP=1`** — All PG 18 tests would fail. Fixed by creating `prime-18.sql` and routing PG 18 to it in both `checks.nix` and `docker-image-test.nix`.
4. **`z_18_ext_interface.out` references `pg_net`** — Test would fail on row count mismatch. Fixed by removing `pg_net` entry and correcting row count (71 → 70).

### Warnings (3)
5. **`run-server.sh.in` help text dropped "17"** — Restored to `"15, 17, 18, orioledb-17"`.
6. **`docker-image-inputs.nix` missing `Dockerfile-18` in fileset** — Docker input hash wouldn't track Dockerfile-18 changes. Added.
7. **`checks.nix` missing `postgresql_18_debug/src` in Linux checks** — Linux CI wouldn't build PG 18 debug packages. Added.

---

## Verification

All Nix evaluations pass on `aarch64-darwin`:

```
$ nix eval .#packages.aarch64-darwin.psql_18/bin.name
"postgresql-and-plugins-18.2"

$ nix eval .#packages.aarch64-darwin.psql_18_slim/bin.name
"postgresql-and-plugins-18.2"

$ nix eval .#packages.aarch64-darwin.docker-image-inputs.name
"docker-image-inputs-hash"

$ nix eval .#packages.aarch64-darwin.docker-image-test.name
"docker-image-test"

$ nix eval .#checks.aarch64-darwin.psql_18.name
"run-check-harness-psql-18"

$ nix eval .#checks.aarch64-darwin.psql_18_slim.name
"run-check-harness-psql-18-slim"
```

---

## Files Modified/Created Summary

| File | Action | Lines Changed |
|------|--------|---------------|
| `nix/config.nix` | Modified | +4 |
| `nix/packages/postgres.nix` | Modified | +16 |
| `nix/overlays/default.nix` | Modified | +1 |
| `nix/ext/versions.json` | Modified | +48 -24 |
| `nix/packages/default.nix` | Modified | +4 |
| `nix/packages/lib.nix` | Modified | +2 |
| `nix/packages/start-client.nix` | Modified | +10 -2 |
| `nix/packages/docker-image-inputs.nix` | Modified | +7 |
| `nix/packages/docker-image-test.nix` | Modified | +21 -2 |
| `nix/packages/dbmate-tool.nix` | Modified | +6 -2 |
| `nix/checks.nix` | Modified | +41 -2 |
| `nix/tools/run-server.sh.in` | Modified | +24 -1 |
| `ansible/vars.yml` | Modified | +2 |
| `Dockerfile-18` | **Created** | 191 lines |
| `nix/tests/prime-18.sql` | **Created** | 91 lines |
| `nix/tests/sql/z_18_ext_interface.sql` | **Created** | 114 lines |
| `nix/tests/expected/z_18_ext_interface.out` | **Created** | 194 lines |

**Total:** 17 files, +761 -39 lines

---

## Next Steps

1. **Full build:** `nix build .#psql_18/bin -L` — compiles PG 18.2 + all compatible extensions
2. **Run checks:** `nix build .#checks.aarch64-darwin.psql_18 -L` — runs pg_regress tests
3. **Docker build:** `docker build -f Dockerfile-18 -t supabase-postgres:18-test .`
4. **Generate schema:** `nix run .#dbmate-tool -- --version 18` — creates `migrations/schema-18.sql`
5. **Fix `z_18_ext_interface.out`** if test output differs from expected (likely needs minor adjustments)
6. **Regression check:** Verify PG 15/17/orioledb-17 builds and tests still pass
7. **Re-enable extensions** as upstream support lands (pg_net, pg_jsonschema, wrappers, rum)
