# PG 18 Extension Compatibility Matrix

## Working Extensions (69)

All extensions below build and install on PG 18.2:

| Extension | Version | Notes |
|-----------|---------|-------|
| amcheck | built-in | |
| autoinc | built-in | |
| bloom | built-in | |
| btree_gin | built-in | |
| btree_gist | built-in | |
| citext | built-in | |
| cube | built-in | |
| dblink | built-in | |
| dict_int | built-in | |
| dict_xsyn | built-in | |
| earthdistance | built-in | |
| file_fdw | built-in | |
| fuzzystrmatch | built-in | |
| hstore | built-in | |
| insert_username | built-in | |
| intagg | built-in | |
| intarray | built-in | |
| isn | built-in | |
| lo | built-in | |
| ltree | built-in | |
| moddatetime | built-in | |
| pageinspect | built-in | |
| pg_buffercache | built-in | |
| pg_freespacemap | built-in | |
| pg_logicalinspect | built-in | New in PG 18 |
| pg_overexplain | built-in | New in PG 18 |
| pg_prewarm | built-in | |
| pg_stat_statements | built-in | |
| pg_surgery | built-in | |
| pg_trgm | built-in | |
| pg_visibility | built-in | |
| pg_walinspect | built-in | |
| pgcrypto | built-in | |
| pgrowlocks | built-in | |
| pgstattuple | built-in | |
| postgres_fdw | built-in | |
| refint | built-in | |
| seg | built-in | |
| sslinfo | built-in | |
| tablefunc | built-in | |
| tcn | built-in | |
| tsm_system_rows | built-in | |
| unaccent | built-in | |
| uuid-ossp | built-in | |
| xml2 | built-in | |
| http | 1.7.0 | pgsql-http |
| hypopg | 1.4.2 | |
| index_advisor | 0.2.0 | |
| pg_cron | 1.6.7 | Needs shared_preload_libraries |
| pg_graphql | 1.5.12 | pgrx 0.16.1 based |
| pg_hashids | 1.3.0 | |
| pg_net | 0.20.0 | Needs shared_preload_libraries |
| pg_partman | 5.3.1 | |
| pg_repack | 1.5.2 | |
| pg_stat_monitor | 2.3.1 | SQL install script may be missing - verify |
| pg_tle | 1.5.2 | |
| pgaudit | 18.0 | Major version tracks PG version |
| pgjwt | 0.2.0 | Pure SQL |
| pgmq | 1.8.0 | |
| pgroonga | 4.0.5 | Requires groonga 16.0.0 |
| pgroonga_database | 4.0.5 | |
| pgsodium | 3.1.8 | |
| pgtap | 1.3.4 | |
| plpgsql_check | 2.8 | |
| safeupdate | 1.4 | pg-safeupdate |
| supabase_vault | 0.3.1 | |
| supautils | 3.1.0 | Not in versions.json, builds for any PG |
| vector | 0.8.1 | pgvector |
| wal2json | 2.6 | Logical decoding plugin |
| wrappers | 0.5.7 | pgrx 0.16.1 based |

## Excluded Extensions

| Extension | Reason | Error/Details |
|-----------|--------|---------------|
| **postgis** 3.6.2 | Build failure | `install-extension-upgrades-from-known-versions` make target calls `postgis.pl --pg_sharedir` pointing to read-only Nix store. Attempted fix (sed to remove target) didn't work in sandbox. |
| **pgrouting** 4.0.1 | Depends on PostGIS | Cannot build without PostGIS |
| **rum** 1.3 | PG 18 ABI change | `src/rum.h:191:3: error: conflicting types for 'PostingItem'` — PG 18 changed GiST/GIN internal structs |
| **pg_jsonschema** 0.3.3 | Needs pgrx update | Latest version uses pgrx 0.12.6. Needs 0.16.1+ for PG 18. No upstream release yet. |
| **plv8** | Deprecated | Only supports PG 15 in supabase-postgres |
| **pg_plan_filter** | Repo deleted | GitHub repository was deleted entirely |
| **timescaledb** | Not added | PG 15 only in current versions.json. PG 18 support available in 2.23+ but not yet integrated. |

## Extension Exclusion in Nix

In `nix/packages/postgres.nix`, the `dbExtensions18` filter:

```nix
dbExtensions18 = builtins.filter (
  x:
  x != ../ext/timescaledb.nix
  && x != ../ext/timescaledb-2.9.1.nix
  && x != ../ext/plv8
  && x != ../ext/pg_jsonschema
  && x != ../ext/pg_plan_filter.nix
  && x != ../ext/postgis.nix
  && x != ../ext/pgrouting
  && x != ../ext/rum.nix
) ourExtensions;
```

## Adding an Extension for PG 18

1. Add `"18"` to the extension's `postgresql` array in `nix/ext/versions.json`
2. Verify the extension is NOT in the `dbExtensions18` exclusion filter
3. Add `create extension if not exists <name>;` to `nix/tests/prime-18.sql`
4. Rebuild and test: `nix build .#psql_18/exts/<name> -L`
5. Regenerate `z_18_ext_interface.out` from a real PG 18 instance
