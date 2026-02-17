# Dockerfile-18 Build Pattern

## Multi-Stage Architecture

```
Stage 1: nix-builder (Alpine 3.21)
  - Install Nix 2.33.2
  - Build psql_18_slim/bin via nix profile add
  - Build supabase-groonga, copy plugins, remove profile, GC

Stage 2: gosu-builder (Alpine 3.21)
  - Download and verify gosu binary

Stage 3: production (Alpine 3.21)
  - Copy /nix from builder
  - Copy groonga plugins
  - Copy gosu
  - Symlink binaries and shares
  - Configure postgresql.conf and supautils.conf
  - Copy and patch migrations (EXECUTE PROCEDURE -> FUNCTION)
  - Setup entrypoint
```

## Nix Binary Cache

The build uses a Docker BuildKit cache mount for Nix binary cache:

```dockerfile
RUN --mount=type=cache,target=/nix-binary-cache,id=nix-bc-pg18 \
    nix profile add --accept-flake-config \
        --option extra-substituters "file:///nix-binary-cache?trusted=true" \
        --option require-sigs false \
        path:.#psql_18_slim/bin && \
    ...
    nix copy --to file:///nix-binary-cache --all --no-check-sigs && \
    ...
```

First build: ~40 min. Subsequent builds with cache: ~5 min.

## Groonga Image Size Optimization

Groonga/pgroonga adds ~300MB (kytea 123MB, mecab 141MB, groonga 33MB). To minimize image size:

1. Install groonga in a separate nix profile
2. Copy only the plugin `.so` files to `/groonga-plugins/`
3. Remove the groonga profile before `nix store gc`

```dockerfile
nix profile add ... path:.#supabase-groonga && \
mkdir -p /groonga-plugins && \
cp -rL /nix/var/nix/profiles/default/lib/groonga/plugins /groonga-plugins/ && \
nix copy --to file:///nix-binary-cache --all --no-check-sigs && \
nix profile remove --regex '.*supabase-groonga.*' && \
nix store gc
```

Then in the production stage:
```dockerfile
COPY --from=nix-builder /groonga-plugins/plugins /usr/lib/groonga/plugins
```

## Config Patching Order

1. Copy config templates from `ansible/files/`
2. Enable supautils, wal-g, pgsodium in postgresql.conf
3. Remove PG 18-incompatible extensions from shared_preload_libraries
4. Remove PG 18-incompatible extensions from supautils.conf
5. Remove `plan_filter.*` from privileged_role_allowed_configs
6. Copy migrations
7. Patch `EXECUTE PROCEDURE` -> `EXECUTE FUNCTION` in all migration SQL

## Image Size Reference

| Component | Size |
|-----------|------|
| Full image (uncompressed) | ~960MB |
| Full image (compressed) | ~297MB |
| /nix store | ~952MB |
| Official PG 17 (uncompressed) | ~1.29GB |
| Official PG 17 (compressed) | ~343MB |

PG 18 is smaller than PG 17 mainly due to missing PostGIS + spatial deps (~256MB).
