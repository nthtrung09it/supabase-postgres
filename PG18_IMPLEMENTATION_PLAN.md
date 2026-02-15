# PostgreSQL 18.2 Support — Implementation Plan

**Branch:** `pg-18-v2` (fresh from `origin/develop`)
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

## Extension Compatibility — Final Assessment

After running parallel agents to check every extension against PG 18, performing iterative Docker builds, and fixing build failures one-by-one:

### Extensions Available for PG 18 (21 extensions)

| Extension | Version | Notes |
|-----------|---------|-------|
| http (pgsql-http) | **1.7.0** | Upgraded from 1.6.1 (pqsignal void fix) |
| hypopg | **1.4.2** | Upgraded from 1.4.1 (CompareType API fix) |
| index_advisor | 0.2.0 | |
| pg_cron | **1.6.7** | Upgraded from 1.6.4 |
| pg_graphql | **1.5.12** | Upgraded from 1.5.11 |
| pg_hashids | 1.3.0 | |
| pg_partman | 5.3.1 | |
| pg_plan_filter | 0.1 | |
| pg_repack | 1.5.2 | |
| pg_stat_monitor | **2.3.1** | Upgraded from 2.1 |
| pg_tle | **1.5.2** | Upgraded from 1.4.0 |
| pgaudit | **18.0** | New PG 18-specific version |
| pgjwt | 0.2.0 | Pure SQL, always works |
| pgmq | **1.8.0** | Upgraded from 1.5.1 |
| pgsodium | 3.1.8 | |
| pgtap | **1.3.4** | Upgraded from 1.3.3 |
| plpgsql_check | 2.7 | |
| safeupdate | 1.4 | |
| supabase_vault | 0.3.1 | |
| vector (pgvector) | **0.8.1** | Upgraded from 0.8.0 (vacuum_delay_point fix) |
| wal2json | 2.6 | |

### Extensions Excluded from PG 18

| Extension | Reason | Tracking |
|-----------|--------|----------|
| pg_net | Build failure (pqsignal API) | Issue #204 |
| pg_jsonschema | Needs pgrx 0.16.1+ | Awaiting pgrx release |
| wrappers | Needs pgrx 0.16.1+ | Awaiting pgrx release |
| rum | PG 18 compat issues | Extension Bugs wiki #156 |
| postgis (+ raster, sfcgal, topology, tiger_geocoder) | Needs 3.5.3+ (complex build with GEOS/GDAL) | PostGIS 3.6.2 has PG 18 support |
| pgrouting | Needs 3.8.0+ (depends on PostGIS) | pgRouting 3.8.0 has PG 18 support |
| pgroonga (+ pgroonga_database) | Needs 4.0.4+ (PG_MODULE_MAGIC_EXT) | PGroonga 4.0.5 available |
| address_standardizer (+ data_us) | Part of PostGIS, excluded with it | |
| timescaledb | Following PG 17 exclusion pattern | TimescaleDB 2.23+ has PG 18 |
| plv8 | Deprecated on PG 17+ | |

### supautils

Updated from **3.0.1 → 3.1.0** (fixes `PG_MODULE_MAGIC_EXT` and `static` keyword issues for PG 18). This is a separate `.nix` file, not in `versions.json`.

---

## PG 18 Breaking Changes Encountered

| Change | Impact | Fix |
|--------|--------|-----|
| `pqsignal()` returns `void` instead of `pqsigfunc` | Breaks pgsql-http 1.6.1 | Upgraded to 1.7.0 |
| `get_ordering_op_properties` 4th param changed to `CompareType*` | Breaks HypoPG 1.4.1 | Upgraded to 1.4.2 |
| `EXECUTE PROCEDURE` removed (deprecated since PG 11) | Breaks migration SQL triggers | `sed` fixup in Dockerfile-18 |
| `db_user_namespace` GUC removed | Config error on startup | Commented out in config |
| `PG_MODULE_MAGIC_EXT` macro change | Breaks supautils 3.0.1, pgroonga 3.x | Updated supautils to 3.1.0, excluded pgroonga |
| `vacuum_delay_point()` signature change | Breaks pgvector 0.8.0 | Upgraded to 0.8.1 |

---

## Implementation Details

### Phase 1: Core Build System [DONE]

- **`nix/config.nix`**: Added PG 18.2 version entry, hash `sha256-cvBXxA7/kEwDGxFv/YoZCIh17jzUujrCtfKAmtSxKTw=`
- **`nix/packages/postgres.nix`**: Created `dbExtensions18` filter excluding 10 extension groups (timescaledb, plv8, pg_net, pg_jsonschema, wrappers, rum, postgis, pgrouting, pgroonga). Added `psql_18`/`psql_18_slim` packages.
- **`nix/overlays/default.nix`**: Added `postgresql_18`
- **`nix/ext/versions.json`**: Added `"18"` to compatible extensions, added new PG 18-specific versions (pgvector 0.8.1, pg_graphql 1.5.12, pg_tle 1.5.2, pgmq 1.8.0, pgtap 1.3.4, pg_stat_monitor 2.3.1, pgaudit 18.0, http 1.7.0, hypopg 1.4.2, pg_cron 1.6.7)
- **`nix/ext/supautils.nix`**: Updated 3.0.1 → 3.1.0

### Phase 2: Package Wiring [DONE]

- **`nix/packages/default.nix`**: Added `psql_18` references
- **`nix/packages/lib.nix`**: Added `psql_18`, `PSQL18_BINDIR`
- **`nix/packages/start-client.nix`**: Added PG 18 client support
- **`nix/packages/docker-image-inputs.nix`**: Added `psql_18_slim`, `Dockerfile-18`
- **`nix/packages/docker-image-test.nix`**: Added PG 18 test routing
- **`nix/packages/dbmate-tool.nix`**: Added version 18 handling

### Phase 3: Test Infrastructure [DONE]

- **`nix/checks.nix`**: Version detection, ports 5541/5542, `z_18_` filter, prime-18.sql routing
- **`nix/tests/prime-18.sql`**: Extensions priming with unavailable ones commented out (pg_net, pg_jsonschema, rum, wrappers, postgis suite, pgrouting, pgroonga suite, address_standardizer suite)
- **`nix/tests/sql/z_18_ext_interface.sql`**: PG 18-specific extension interface test
- **`nix/tests/expected/z_18_ext_interface.out`**: Expected output (60 installed extensions)

### Phase 4: Shell Tools [DONE]

- **`nix/tools/run-server.sh.in`**: PG 18 BINDIR, config patching for Linux/macOS, removal of unavailable extensions from shared_preload_libraries and supautils.conf (including postgis, pgrouting, pgroonga and their sub-extensions)

### Phase 5: Docker [DONE]

- **`Dockerfile-18`**: Alpine 3.21 + Nix multi-stage build
  - Groonga build step removed (pgroonga excluded)
  - `EXECUTE PROCEDURE → EXECUTE FUNCTION` sed fixup for migrations
  - Extension removal from supautils.conf (all excluded extensions)
  - `GRN_PLUGINS_DIR` env var removed

### Phase 6: Other [DONE]

- **`ansible/vars.yml`**: PG 18 entries for AMI builds

---

## Bug Fixes (Post-Review)

### Code Review Round 1 (7 issues — 4 critical, 3 warning)
1. `docker-image-inputs.nix` missing `psql_18_slim` parameter
2. `docker-image-test.nix` missing `psql_18` parameter
3. `prime.sql` creates excluded extensions with `ON_ERROR_STOP=1`
4. `z_18_ext_interface.out` references `pg_net`
5. `run-server.sh.in` help text dropped "17"
6. `docker-image-inputs.nix` missing `Dockerfile-18` in fileset
7. `checks.nix` missing `postgresql_18_debug/src` in Linux checks

### Docker Build Failures (iterative discovery)
8. pgsql-http 1.6.1: `pqsignal()` void return — added v1.7.0
9. HypoPG 1.4.1: `get_ordering_op_properties` CompareType — added v1.4.2
10. pgaudit: no PG 18 version existed — added v18.0
11. pg_cron: needed migration files for PG 18 — added v1.6.7

### Extension Compatibility Round (parallel agent analysis)
12. pgvector 0.8.0 → 0.8.1 (vacuum_delay_point)
13. pg_graphql 1.5.11 → 1.5.12
14. pg_tle 1.4.0 → 1.5.2
15. pgmq 1.5.1 → 1.8.0
16. pgtap 1.3.3 → 1.3.4
17. pg_stat_monitor 2.1 → 2.3.1
18. supautils 3.0.1 → 3.1.0
19. Excluded postgis, pgrouting, pgroonga (need complex build chain updates)

---

## Git Commits

| Hash | Message |
|------|---------|
| `d0428b57` | feat: add PostgreSQL 18.2 support |
| `878cb33e` | docs: add PG 18.2 implementation plan |
| `9fc64a8a` | fix: handle EXECUTE PROCEDURE removal in PG 18 migrations |
| `78779c33` | fix: add pgsql-http v1.7.0 for PG 18 compatibility |
| `85059ad9` | fix: update extension versions for PG 18 compatibility |
| *(pending)* | fix: exclude postgis/pgrouting/pgroonga, update supautils to 3.1.0 |

---

## Files Modified/Created Summary

| File | Action |
|------|--------|
| `nix/config.nix` | Modified — PG 18.2 version entry |
| `nix/packages/postgres.nix` | Modified — dbExtensions18 with 10 exclusions |
| `nix/overlays/default.nix` | Modified — postgresql_18 |
| `nix/ext/versions.json` | Modified — PG 18 compat arrays + new versions |
| `nix/ext/supautils.nix` | Modified — 3.0.1 → 3.1.0 |
| `nix/packages/default.nix` | Modified — psql_18 references |
| `nix/packages/lib.nix` | Modified — PSQL18_BINDIR |
| `nix/packages/start-client.nix` | Modified — PG 18 client |
| `nix/packages/docker-image-inputs.nix` | Modified — psql_18_slim + Dockerfile-18 |
| `nix/packages/docker-image-test.nix` | Modified — PG 18 test routing |
| `nix/packages/dbmate-tool.nix` | Modified — version 18 |
| `nix/checks.nix` | Modified — PG 18 checks |
| `nix/tools/run-server.sh.in` | Modified — PG 18 config patching |
| `ansible/vars.yml` | Modified — PG 18 AMI entries |
| `Dockerfile-18` | **Created** — Alpine + Nix multi-stage |
| `nix/tests/prime-18.sql` | **Created** — PG 18 extension priming |
| `nix/tests/sql/z_18_ext_interface.sql` | **Created** — Extension interface test |
| `nix/tests/expected/z_18_ext_interface.out` | **Created** — Expected test output |

---

## Remaining Tasks

### Immediate (Docker Image Build)
- [ ] Commit all current changes (extensions update + supautils 3.1.0 + exclusion fixes)
- [ ] Build Docker image: `docker buildx build --builder supabase-postgres-builder --platform linux/arm64 -f Dockerfile-18 -t supabase/postgres:18-local --load --progress=plain .`
- [ ] Verify image starts and accepts connections

### Integration Testing
- [ ] Start Supabase stack with `docker compose up` using PG 18 image
- [ ] Run Playwright E2E tests against Supabase Studio (use haiku model for cost)
- [ ] Run smoke tests: SQL queries, extension creation, migration verification

### Validation
- [ ] `nix eval` all PG 18 packages (psql_18, psql_18_slim, checks, docker-image-inputs)
- [ ] Verify PG 15/17/orioledb-17 builds are unaffected (no regressions)
- [ ] Generate `migrations/schema-18.sql` with dbmate-tool

### Future Work (When Upstream Support Lands)
- [ ] Re-enable PostGIS when 3.5.3+ version is added to `versions.json` + Nix build
- [ ] Re-enable pgRouting when 3.8.0+ version is added (depends on PostGIS)
- [ ] Re-enable PGroonga when 4.0.4+ version is added + groonga build
- [ ] Re-enable pg_net when build failure is resolved (issue #204)
- [ ] Re-enable pg_jsonschema when pgrx 0.16.1+ releases
- [ ] Re-enable wrappers when pgrx 0.16.1+ releases
- [ ] Re-enable rum when PG 18 compat issues are fixed (wiki #156)
- [ ] Add TimescaleDB 2.23+ for PG 18 (currently excluded by pattern)
- [ ] Add Dockerfile-18 groonga build step back when pgroonga is re-enabled
- [ ] Create PR to upstream `supabase/postgres` once all tests pass
