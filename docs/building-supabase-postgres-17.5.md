# Building Supabase PostgreSQL 17.5 on macOS

## Executive Summary

This document explains how the Supabase PostgreSQL build system works and provides instructions for updating from PostgreSQL 17.4 to 17.5 on macOS. The project uses Nix for reproducible builds and supports PostgreSQL 15, 17, and OrioleDB-17 variants with 45+ extensions.

## Table of Contents
1. [Current Architecture Overview](#current-architecture-overview)
2. [How the Build System Works](#how-the-build-system-works)
3. [GitHub Workflows](#github-workflows)
4. [Building on macOS](#building-on-macos)
5. [Updating to PostgreSQL 17.5](#updating-to-postgresql-175)

---

## Current Architecture Overview

### Technology Stack
- **Build System**: Nix Flakes (reproducible builds)
- **Supported PostgreSQL Versions**:
  - PostgreSQL 15.8 (45+ extensions)
  - PostgreSQL 17.4 (44+ extensions, excludes TimescaleDB and PLV8)
  - OrioleDB 17_11 (PostgreSQL 17 fork with OrioleDB storage engine)
- **Deployment Targets**: Docker images, AWS AMIs, Development environments
- **CI/CD**: GitHub Actions with Nix caching on S3

### Key File Locations
```
supabase-postgres/
├── flake.nix                    # Main Nix flake configuration
├── nix/
│   ├── config.nix               # PostgreSQL version definitions
│   ├── postgresql/default.nix   # PostgreSQL package generation
│   ├── packages/postgres.nix    # Extension bundling
│   ├── ext/                     # Individual extension definitions
│   └── checks.nix               # Test configurations
├── ansible/vars.yml             # Runtime version specifications
├── Dockerfile-15                # PostgreSQL 15 Docker image
├── Dockerfile-17                # PostgreSQL 17 Docker image
└── .github/workflows/           # CI/CD pipelines
```

---

## How the Build System Works

### 1. Version Definition Flow

The build system uses a multi-layered approach to define PostgreSQL versions:

#### Layer 1: Nix Configuration (`nix/config.nix:48-50`)
```nix
"17" = {
  version = "17.4";
  hash = "sha256-xGBbc/6hGWNAZpn5Sblm5dFzp+4Myu+JON7AyoqZX+c=";
};
```
This defines the PostgreSQL source version and its cryptographic hash for reproducible builds.

#### Layer 2: Ansible Variables (`ansible/vars.yml:13`)
```yaml
postgres17: "17.4.1.072"
```
This defines the Supabase-specific version string (includes build number).

#### Layer 3: Dynamic Package Generation (`nix/postgresql/default.nix`)
The system dynamically generates packages for each PostgreSQL version with:
- Standard builds (`postgresql_17`)
- JIT-enabled builds (`postgresql_17_jit`)
- Debug builds (Linux only)
- Source packages

### 2. Extension System

Extensions are defined in `nix/ext/` and bundled in `nix/packages/postgres.nix`:

**PostgreSQL 17 Extensions** (44+ extensions):
- Core: pgvector, PostGIS, pg_cron, pgsodium, vault, pg_graphql
- Excluded from v17: TimescaleDB, PLV8 (compatibility issues)
- Each extension specifies supported versions in `nix/ext/versions.json`

### 3. Build Outputs

The system produces multiple artifacts:
- **psql_17**: Complete PostgreSQL 17 bundle with extensions
- **Docker Images**: Using `Dockerfile-17` with Nix profile installation
- **AWS AMIs**: Built with Packer for production deployment
- **Development Packages**: For local testing and development

---

## GitHub Workflows

### Main Build Workflow (`nix-build.yml`)

**Trigger**: Push to develop/release branches, PRs, manual dispatch

**Process**:
1. **Multi-platform builds**: x86 Linux, ARM Linux, ARM macOS
2. **Nix installation** with S3 cache configuration
3. **Build command**:
   ```bash
   nix run "github:Mic92/nix-fast-build" -- --skip-cached --no-nom \
     --flake ".#checks.$(nix eval --raw --impure --expr 'builtins.currentSystem')"
   ```
4. **Artifacts uploaded** to S3 cache for reuse

### AMI Release Workflow (`ami-release-nix.yml`)

**Process**:
1. Reads PostgreSQL versions from `ansible/vars.yml`
2. Builds AMIs using Packer with Nix
3. Uploads to AWS S3 buckets (staging and production)

### Docker Release Workflow (`dockerhub-release-matrix.yml`)

**Process**:
1. Builds Docker images for each PostgreSQL version
2. Uses Dockerfile-15, Dockerfile-17, Dockerfile-orioledb-17
3. Pushes to Docker Hub with version tags

---

## Building on macOS

### Prerequisites

1. **Install Nix** (with Determinate Systems installer):
   ```bash
   curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | \
     sh -s -- install
   ```

2. **Configure Nix** to use Supabase cache:
   ```bash
   # Add to /etc/nix/nix.conf or ~/.config/nix/nix.conf
   substituters = https://cache.nixos.org https://nix-postgres-artifacts.s3.amazonaws.com
   trusted-public-keys = nix-postgres-artifacts:dGZlQOvKcNEjvT7QEAJbcV6b6uk7VF/hWMjhYleiaLI=% cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY=
   ```

### Build Commands

1. **Enter development environment**:
   ```bash
   cd supabase-postgres
   nix develop
   ```

2. **Build PostgreSQL 17 package**:
   ```bash
   nix build .#psql_17 -L
   ```

3. **Run tests for PostgreSQL 17**:
   ```bash
   nix build .#checks.aarch64-darwin.psql_17 -L
   ```

4. **Start PostgreSQL 17 server locally**:
   ```bash
   nix run .#start-server 17
   ```

5. **Build Docker image locally**:
   ```bash
   # Using Docker
   docker build -f Dockerfile-17 -t supabase-postgres:17.4 .
   
   # Using nerdctl (if you have it)
   sudo nerdctl build -f Dockerfile-17 -t supabase-postgres:17.4 .
   ```

---

## Updating to PostgreSQL 17.5

### Step 1: Get PostgreSQL 17.5 Hash

```bash
# Download PostgreSQL 17.5 source
curl -LO https://ftp.postgresql.org/pub/source/v17.5/postgresql-17.5.tar.gz

# Generate Nix hash
nix hash file postgresql-17.5.tar.gz
# Or use nix-prefetch-url
nix-prefetch-url --unpack https://ftp.postgresql.org/pub/source/v17.5/postgresql-17.5.tar.gz
```

### Step 2: Update Configuration Files

1. **Update `nix/config.nix`**:
   ```nix
   "17" = {
     version = "17.5";  # Changed from 17.4
     hash = "sha256-YOUR_NEW_HASH_HERE";  # Replace with hash from Step 1
   };
   ```

2. **Update `ansible/vars.yml`**:
   ```yaml
   postgres17: "17.5.1.001"  # Update version, reset build number
   ```

### Step 3: Test the Build

```bash
# Clean any cached builds
nix store gc

# Build PostgreSQL 17 with new version
nix build .#psql_17 -L --rebuild

# Run tests
nix build .#checks.aarch64-darwin.psql_17 -L

# Test server startup
nix run .#start-server 17
```

### Step 4: Build Docker Image

```bash
# Build Docker image with new version
docker build -f Dockerfile-17 -t supabase-postgres:17.5 .

# Test the image
docker run -d --name test-pg17 \
  -e POSTGRES_PASSWORD=postgres \
  -p 5432:5432 \
  supabase-postgres:17.5

# Verify version
docker exec test-pg17 psql -U supabase_admin -c "SELECT version();"

# Clean up
docker stop test-pg17 && docker rm test-pg17
```

### Step 5: Update Version Checks (Optional)

If there are any version-specific checks or migrations:

1. Check `migrations/db/migrations/` for version-specific migrations
2. Update any version checks in `nix/checks.nix`
3. Review extension compatibility in `nix/ext/versions.json`

### Step 6: Create Pull Request

```bash
# Create a new branch
git checkout -b update-postgres-17.5

# Commit changes
git add nix/config.nix ansible/vars.yml
git commit -m "chore: update PostgreSQL 17 to version 17.5

- Update PostgreSQL 17 from 17.4 to 17.5
- Update Nix hash for reproducible builds
- Reset build number in ansible vars"

# Push and create PR
git push origin update-postgres-17.5
```

---

## Troubleshooting

### Common Issues

1. **Hash Mismatch Error**:
   ```
   error: hash mismatch in fixed-output derivation
   ```
   Solution: Ensure you're using the correct hash from `nix-prefetch-url --unpack`

2. **Extension Compatibility**:
   - Some extensions may not be compatible with 17.5
   - Check extension logs during build
   - May need to update extension versions in `nix/ext/`

3. **Build Failures on macOS**:
   - Ensure you have enough disk space (>20GB free)
   - For DuckDB extension: May need `--max-jobs 1` flag
   - Check Xcode Command Line Tools are installed

4. **Cache Issues**:
   ```bash
   # Clear Nix store cache
   nix store gc
   
   # Rebuild without cache
   nix build .#psql_17 --rebuild
   ```

### Verification Commands

```bash
# Check built PostgreSQL version
./result/bin/postgres --version

# List included extensions
./result/bin/psql -c "SELECT * FROM pg_available_extensions ORDER BY name;"

# Check specific extension versions
./result/bin/psql -c "SELECT name, default_version FROM pg_available_extensions WHERE name IN ('pgvector', 'pgsodium', 'pg_graphql');"
```

---

## Additional Resources

- **PostgreSQL Release Notes**: https://www.postgresql.org/docs/release/17.5/
- **Nix Documentation**: https://nixos.org/manual/nix/
- **Supabase Postgres GitHub**: https://github.com/supabase/postgres
- **Extension Documentation**: See individual extension docs in `nix/ext/`

---

## Summary

The Supabase PostgreSQL build system is a sophisticated Nix-based infrastructure that:
1. Uses declarative configuration for reproducible builds
2. Supports multiple PostgreSQL versions with version-specific extension filtering
3. Provides automated CI/CD through GitHub Actions
4. Generates multiple deployment artifacts (Docker, AMI, local packages)

To update to PostgreSQL 17.5:
1. Get the new source hash
2. Update `nix/config.nix` and `ansible/vars.yml`
3. Test the build locally
4. Build and test Docker images
5. Create a pull request with your changes

The system is designed for maintainability and consistency across different deployment targets while managing complex extension compatibility requirements.