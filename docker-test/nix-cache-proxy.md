# Local Nix Binary Cache Proxy for Docker Builds

## Problem

Each `docker build` runs nix inside a fresh container, re-downloading ~3930 store paths (~107MB compressed) from remote S3/nixos caches. This adds ~10-15 min to every build.

## Quick Setup

```bash
# 1. Serve the local cache (already exported to supabase-postgres-codebase-nix-cache/)
cd /Users/kernel/Projects/RESEARCH/CODEBASES/supabase-postgres-codebase-nix-cache
python3 -m http.server 9999

# 2. In Dockerfile-18, add to the extra-nix.conf heredoc:
extra-substituters = http://host.docker.internal:9999
trusted-substituters = http://host.docker.internal:9999
require-sigs = false

# 3. Build as usual — nix will fetch from localhost first
DOCKER_BUILDKIT=1 docker build -f Dockerfile-18 -t supabase/postgres:18-local .
```

## Refreshing the Cache

After a successful Docker build with new extensions:

```bash
docker run --rm \
  -v /Users/kernel/Projects/RESEARCH/CODEBASES/supabase-postgres-codebase-nix-cache:/cache \
  supabase/postgres:18-local \
  sh -c "nix --extra-experimental-features 'nix-command flakes' copy --all --to file:///cache"
```

## Notes

- `require-sigs = false` is needed because local cache paths are unsigned
- For production, sign paths with `nix store sign --key-file` instead
- Alternative: use `RUN --mount=type=cache,target=/nix` in Dockerfile for BuildKit cache persistence
