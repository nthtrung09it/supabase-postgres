# PostgreSQL 18.2 Support — Implementation Plan

**Branch:** `pg-18-v2` (fresh from `origin/develop`)
**Date:** 2026-02-15
**PG Version:** 18.2 (current stable, GA Sep 25, 2025)
**Tag:** `pg18-v2-stack-tested` (Docker image + full Supabase stack verified)

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

## Extension Compatibility — Current Status

### Extensions Available for PG 18 (28+ extensions)

| Extension | Version | Notes |
|-----------|---------|-------|
| http (pgsql-http) | **1.7.0** | Upgraded from 1.6.1 (pqsignal void fix) |
| hypopg | **1.4.2** | Upgraded from 1.4.1 (CompareType API fix) |
| index_advisor | 0.2.0 | |
| pg_cron | **1.6.7** | Upgraded from 1.6.4 |
| pg_graphql | **1.5.12** | Upgraded from 1.5.11 |
| pg_hashids | 1.3.0 | |
| pg_net | **0.20.0** | Re-enabled — PG 18 fix in PR #205 (v0.18.0+) |
| pg_partman | 5.3.1 | |
| pg_repack | 1.5.2 | |
| pg_stat_monitor | **2.3.1** | Upgraded from 2.1 |
| pg_tle | **1.5.2** | Upgraded from 1.4.0 |
| pgaudit | **18.0** | New PG 18-specific version |
| pgjwt | 0.2.0 | Pure SQL, always works |
| pgmq | **1.8.0** | Upgraded from 1.5.1 |
| pgroonga | **4.0.5** | Re-enabled — groonga bumped 14.0.5 → 14.1.2 |
| pgrouting | **4.0.1** | Re-enabled — new PG 18-specific version |
| pgsodium | 3.1.8 | |
| pgtap | **1.3.4** | Upgraded from 1.3.3 |
| plpgsql_check | 2.7 | |
| postgis | **3.6.2** | Re-enabled — major version bump from 3.3.7 |
| rum | **1.3** (rev 1.3.14) | Re-enabled — PG 18 confirmed compatible |
| safeupdate | 1.4 | |
| supabase_vault | 0.3.1 | |
| vector (pgvector) | **0.8.1** | Upgraded from 0.8.0 (vacuum_delay_point fix) |
| wal2json | 2.6 | |
| wrappers | **0.5.7** | Re-enabled — pgrx 0.16.1 supports PG 18 |

### Extensions Still Excluded from PG 18

| Extension | Reason | Tracking |
|-----------|--------|----------|
| pg_jsonschema | Current 0.3.3 uses pgrx 0.12.6, needs 0.16.1+ | No upstream release yet |
| pg_plan_filter | GitHub repo deleted, unmaintained | N/A |
| timescaledb | Following PG 17 exclusion pattern | TimescaleDB 2.23+ has PG 18 |
| plv8 | Deprecated on PG 17+ | |

### supautils

Updated from **3.0.1 → 3.1.0** (fixes `PG_MODULE_MAGIC_EXT` and `static` keyword issues for PG 18). This is a separate `.nix` file, not in `versions.json`.

---

## PG 18 Breaking Changes Encountered

| Change | Impact | Fix |
|--------|--------|-----|
| `pqsignal()` returns `void` instead of `pqsigfunc` | Breaks pgsql-http 1.6.1, pg_net < 0.18.0 | Upgraded http to 1.7.0, pg_net already at 0.20.0 |
| `get_ordering_op_properties` 4th param changed to `CompareType*` | Breaks HypoPG 1.4.1 | Upgraded to 1.4.2 |
| `EXECUTE PROCEDURE` removed (deprecated since PG 11) | Breaks migration SQL triggers | `sed` fixup in Dockerfile-18 |
| `db_user_namespace` GUC removed | Config error on startup | Commented out in config |
| `PG_MODULE_MAGIC_EXT` macro change | Breaks supautils 3.0.1, pgroonga 3.x | Updated supautils to 3.1.0, pgroonga to 4.0.5 |
| `vacuum_delay_point()` signature change | Breaks pgvector 0.8.0 | Upgraded to 0.8.1 |

---

## Implementation Details

### Phase 1: Core Build System [DONE]

- **`nix/config.nix`**: Added PG 18.2 version entry, hash `sha256-cvBXxA7/kEwDGxFv/YoZCIh17jzUujrCtfKAmtSxKTw=`
- **`nix/packages/postgres.nix`**: Created `dbExtensions18` filter. Now only excludes 4 extension groups (timescaledb, plv8, pg_jsonschema, pg_plan_filter). Added `psql_18`/`psql_18_slim` packages.
- **`nix/overlays/default.nix`**: Added `postgresql_18`
- **`nix/ext/versions.json`**: Added `"18"` to all compatible extensions, added new PG 18-specific versions
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
- **`nix/tests/prime-18.sql`**: Extensions priming — now includes pg_net, pgroonga, postgis, pgrouting, rum, wrappers (only pg_jsonschema commented out)
- **`nix/tests/sql/z_18_ext_interface.sql`**: PG 18-specific extension interface test
- **`nix/tests/expected/z_18_ext_interface.out`**: Expected output (needs regeneration after extension re-enablement)

### Phase 4: Shell Tools [DONE]

- **`nix/tools/run-server.sh.in`**: PG 18 BINDIR, config patching for Linux/macOS. Now only removes timescaledb, plv8, pg_jsonschema, pg_plan_filter from shared_preload_libraries and supautils.conf.

### Phase 5: Docker [DONE]

- **`Dockerfile-18`**: Alpine 3.21 + Nix multi-stage build
  - Groonga build step **re-enabled** (pgroonga 4.0.5 now available)
  - `EXECUTE PROCEDURE → EXECUTE FUNCTION` sed fixup for migrations
  - Extension removal from supautils.conf — only timescaledb, plv8, pg_jsonschema, pg_plan_filter
  - `GRN_PLUGINS_DIR` env var **re-enabled**

### Phase 6: Extension Re-enablement [DONE]

Re-enabled 7 previously-excluded extensions:

| Extension | Change | Details |
|-----------|--------|---------|
| pg_net | Added "18" to versions.json 0.20.0 | PR #205 fixed pqsignal API for PG 18 |
| rum | Added "18" to versions.json 1.3 | 1.3.14 confirmed PG 18 compatible |
| wrappers | Added "18" to versions.json 0.5.7 | Already uses pgrx 0.16.1 (PG 18 ready) |
| pgroonga | Added 4.0.5 entry (PG 15/17/18) | Supports PG 18 natively |
| groonga | Bumped 14.0.5 → 14.1.2 | Required by pgroonga 4.0.5 |
| postgis | Added 3.6.2 entry (PG 15/17/18) | Full PG 18 support |
| pgrouting | Already had 4.0.1 (PG 18) | Added in earlier commit |

### Phase 7: Other [DONE]

- **`ansible/vars.yml`**: PG 18 entries for AMI builds
- **`docker-test/`**: Full Supabase stack test harness (13 services)

---

## Docker Build & Test Results

### Docker Image Build
```bash
# Build command (completed successfully, ~35 min)
DOCKER_BUILDKIT=1 docker buildx build \
  --builder supabase-postgres-builder \
  --platform linux/arm64 \
  -f Dockerfile-18 \
  -t supabase/postgres:18-local \
  --load --progress=plain .

# Result: 476MB image, PostgreSQL 18.2, 66 available extensions
```

### Supabase Stack Test
```bash
# Start full stack (13 services)
cd docker-test && docker compose up -d

# All services verified healthy:
# studio, kong, auth, rest, realtime, storage, imgproxy,
# meta, functions, analytics, db, vector, supavisor

# Verified working:
# - PostgREST API (CRUD operations)
# - GraphQL endpoint (pg_graphql)
# - Auth signup (GoTrue)
# - Vault extension
# - pgvector extension
# - All 13 Supabase roles present
```

### Nix Cache Proxy (for faster rebuilds)
```bash
# Export runtime paths from Docker image (~3930 paths, 107MB)
docker run --rm \
  -v /path/to/nix-cache:/cache \
  supabase/postgres:18-local \
  sh -c "nix --extra-experimental-features 'nix-command flakes' copy --all --to file:///cache"

# Serve cache: python3 -m http.server 9999
# Note: Only contains runtime closure, not build-time deps.
# For build caching, use BuildKit layer cache or nix store gc removal.
```

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
19. Excluded postgis, pgrouting, pgroonga (needed complex build chain updates)

### Extension Re-enablement Round
20. pg_net 0.20.0: added "18" to postgresql array (PR #205 fixed pqsignal)
21. rum 1.3 (1.3.14): added "18" to postgresql array
22. wrappers 0.5.7: added "18" to postgresql array (pgrx 0.16.1 ready)
23. pgroonga 4.0.5: new version entry with PG 18 support
24. groonga 14.0.5 → 14.1.2: required by pgroonga 4.0.5
25. postgis 3.6.2: new version entry with PG 18 support
26. Removed exclusions from postgres.nix, Dockerfile-18, run-server.sh.in

---

## Git Commits

| Hash | Message |
|------|---------|
| `d0428b57` | feat: add PostgreSQL 18.2 support |
| `878cb33e` | docs: add PG 18.2 implementation plan |
| `9fc64a8a` | fix: handle EXECUTE PROCEDURE removal in PG 18 migrations |
| `78779c33` | fix: add pgsql-http v1.7.0 for PG 18 compatibility |
| `85059ad9` | fix: update extension versions for PG 18 compatibility |
| `c86c9a4f` | fix: exclude postgis/pgrouting/pgroonga from PG 18, update supautils to 3.1.0 |
| `cd1390ef` | fix: add missing rust/pgrx fields to pg_graphql 1.5.12 |
| `24b1a01a` | fix: add missing revision field to pg_stat_monitor 2.3.1 |
| `eeb9b958` | fix: add plpgsql_check 2.8.9 for PG 18 compatibility |
| `b48c3f99` | fix: correct plpgsql_check 2.8 revision |
| `b44a1c69` | fix: exclude pg_plan_filter from PG 18 (GitHub repo deleted) |
| `ac45489f` | fix: restore postgis/pgrouting/pgroonga exclusions in PG 18 filter |
| `c1bc8f07` | fix: correct supautils.conf sed patterns for PG 18 |
| `d045af8d` | feat: add pgrouting 4.0.1 for PG 18, fix extension filtering |
| `994ad43a` | fix: correct plan_filter and wrappers sed patterns for PG 18 |
| `1f520373` | fix: add --accept-flake-config to Dockerfile-18 nix build |
| `45612bea` | docs: add local nix binary cache proxy setup for faster Docker builds |
| `9b3ed670` | feat: add Supabase stack test harness for PG 18 |
| *(pending)* | feat: re-enable pg_net, rum, wrappers, pgroonga, postgis for PG 18 |

---

## Files Modified/Created Summary

| File | Action |
|------|--------|
| `nix/config.nix` | Modified — PG 18.2 version entry |
| `nix/packages/postgres.nix` | Modified — dbExtensions18 (now only 4 exclusions) |
| `nix/overlays/default.nix` | Modified — postgresql_18 |
| `nix/ext/versions.json` | Modified — PG 18 compat arrays + new versions (pg_net, rum, wrappers, pgroonga 4.0.5, postgis 3.6.2) |
| `nix/ext/supautils.nix` | Modified — 3.0.1 → 3.1.0 |
| `nix/ext/pgroonga/groonga.nix` | Modified — 14.0.5 → 14.1.2 |
| `nix/packages/default.nix` | Modified — psql_18 references |
| `nix/packages/lib.nix` | Modified — PSQL18_BINDIR |
| `nix/packages/start-client.nix` | Modified — PG 18 client |
| `nix/packages/docker-image-inputs.nix` | Modified — psql_18_slim + Dockerfile-18 |
| `nix/packages/docker-image-test.nix` | Modified — PG 18 test routing |
| `nix/packages/dbmate-tool.nix` | Modified — version 18 |
| `nix/checks.nix` | Modified — PG 18 checks |
| `nix/tools/run-server.sh.in` | Modified — PG 18 config patching (reduced exclusions) |
| `ansible/vars.yml` | Modified — PG 18 AMI entries |
| `Dockerfile-18` | **Created** — Alpine + Nix multi-stage (groonga re-enabled) |
| `nix/tests/prime-18.sql` | **Created** — PG 18 extension priming (most extensions enabled) |
| `nix/tests/sql/z_18_ext_interface.sql` | **Created** — Extension interface test |
| `nix/tests/expected/z_18_ext_interface.out` | **Created** — Expected test output |
| `docker-test/` | **Created** — Full Supabase stack test harness (29 files) |
| `docker-test/nix-cache-proxy.md` | **Created** — Nix cache proxy setup docs |

---

## Remaining Tasks

### Immediate (Docker Image Rebuild)
- [ ] Commit all current changes (extension re-enablement)
- [ ] Rebuild Docker image with re-enabled extensions: `DOCKER_BUILDKIT=1 docker buildx build --builder supabase-postgres-builder --platform linux/arm64 -f Dockerfile-18 -t supabase/postgres:18-local --load --progress=plain .`
- [ ] Verify image starts and all new extensions load correctly

### Validation
- [ ] Regenerate `nix/tests/expected/z_18_ext_interface.out` with actual extension count
- [ ] `nix eval` all PG 18 packages (psql_18, psql_18_slim, checks, docker-image-inputs)
- [ ] Run `nix build .#checks.aarch64-darwin.psql_18 -L` (pg_regress tests)
- [ ] Verify PG 15/17/orioledb-17 builds are unaffected (no regressions)
- [ ] Generate `migrations/schema-18.sql` with dbmate-tool

### Integration Testing
- [ ] Start Supabase stack with new image (13 services)
- [ ] Run smoke tests: SQL queries, extension creation, migration verification
- [ ] Run Playwright E2E tests against Supabase Studio

### Future Work
- [ ] Re-enable pg_jsonschema when pgrx 0.16.1+ release happens upstream
- [ ] Add TimescaleDB 2.23+ for PG 18 (currently excluded by pattern)
- [ ] Squash commits for clean PR
- [ ] Create PR to upstream `supabase/postgres` once all tests pass
