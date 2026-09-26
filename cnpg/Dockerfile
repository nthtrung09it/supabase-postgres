####################
# Supabase Postgres for CloudNativePG (Alpine + Nix)
#
# Layers barman-cloud (CNPG in-tree barmanObjectStore WAL archiving / base
# backups), dbmate and the Supabase migration scripts onto a Supabase Postgres
# base image (Dockerfile-18's output in Harbor). Ported from hello-k3s-ansible's
# build-cnpg-postgres skill; built by .github/workflows/build-cnpg-supabase-postgres-18.yml.
#
# Build context: this directory (cnpg/). Run fetch-supabase-selfhosted.sh
# first: it populates .upstream/ (gitignored) from supabase/supabase.
####################
# Full image reference. The workflow passes the ref pinned in cnpg/base-image.
# (The skill's `${BASE_TAG}_${TARGETARCH}` form only fits Docker Hub's
# per-arch upstream tags; our Harbor base is a plain single-arch amd64 tag.)
ARG BASE_IMAGE=harbor.trungnguyen.dev/elearning/supabase-postgres:18.6.0.001-rc1-dbc20562
FROM ${BASE_IMAGE}

ARG BASE_IMAGE
ARG BASE_DIGEST=""
ARG SUPABASE_SHA=""
ARG postgresql_major=18
ARG BARMAN_VERSION=3.20.0
ARG DBMATE_VERSION=v2.36.0

LABEL name="CloudNative Supabase Container Images" \
      vendor="nthtrung09it" \
      version="${postgresql_major}" \
      release="6" \
      summary="PostgreSQL Container images." \
      description="This Docker image contains PostgreSQL, Supabase and Barman Cloud based on Postgres ${postgresql_major}.Supabase with CloudNativePG" \
      org.opencontainers.image.description="This Docker image contains PostgreSQL, Supabase and Barman Cloud based on Postgres ${postgresql_major}.Supabase" \
      org.opencontainers.image.base.name="${BASE_IMAGE}" \
      org.opencontainers.image.base.digest="${BASE_DIGEST}" \
      dev.trungnguyen.supabase-selfhosted.revision="${SUPABASE_SHA}"

# Install barman-cli-cloud for CloudNativePG WAL archiving and base backups
# Pattern follows cloudnative-pg/postgres-containers Dockerfile:
#   1. System psycopg2 (avoids compiling against libpq)
#   2. Build deps needed for lz4/snappy wheels
#   3. pip install barman with cloud extras (pinned: barman >= 3.20 needs
#      Python >= 3.12; alpine 3.23 ships 3.12)
#   4. Remove build deps + compile Python bytecode
ENV PIP_BREAK_SYSTEM_PACKAGES=1
RUN apk add --no-cache python3 py3-pip py3-psycopg2 py3-setuptools && \
    apk add --no-cache --virtual .build-deps build-base python3-dev && \
    pip install --no-cache-dir "barman[cloud,snappy,zstandard,lz4]==${BARMAN_VERSION}" && \
    python3 -c "import sysconfig, compileall; compileall.compile_dir(sysconfig.get_path('stdlib'), quiet=1); compileall.compile_dir(sysconfig.get_path('purelib'), quiet=1); compileall.compile_dir(sysconfig.get_path('platlib'), quiet=1)" && \
    apk del .build-deps && \
    rm -rf /root/.cache /tmp/*

# Install dbmate for database migrations (pinned, not releases/latest)
RUN ARCH=$(uname -m); \
    case ${ARCH} in \
        x86_64) DBMATE_ARCH="linux-amd64" ;; \
        aarch64) DBMATE_ARCH="linux-arm64" ;; \
        *) echo "Unsupported architecture: ${ARCH}"; exit 1 ;; \
    esac && \
    curl -fsSL -o /usr/local/bin/dbmate \
    "https://github.com/amacneil/dbmate/releases/download/${DBMATE_VERSION}/dbmate-${DBMATE_ARCH}" && \
    chmod +x /usr/local/bin/dbmate

# Raw migration scripts (upstream supabase, untouched) = exactly what the base
# image would run at initdb: its own /docker-entrypoint-initdb.d (this repo's
# migrations/db + 00-schema.sql + 00-extension.sql, see Dockerfile-18) ...
RUN mkdir -p /tmp/elearning-scripts-origin && \
    cp -a /docker-entrypoint-initdb.d/. /tmp/elearning-scripts-origin/ && \
    rm -rf /docker-entrypoint-initdb.d/*
# ... plus the official Supabase self-hosted DB files (supabase/supabase
# docker/volumes/db), under the paths its docker-compose.yml mounts them at.
# Fetched fresh by fetch-supabase-selfhosted.sh into .upstream/ before the build.
COPY .upstream/initdb/ /tmp/elearning-scripts-origin/
# Our scripts (template generator, pre-processor, boss)
COPY renames.txt /tmp/renames.txt
COPY generate-templates.sh /tmp/generate-templates.sh
COPY process-templates.sh /tmp/process-templates.sh
COPY run-migrations.sh /tmp/run-migrations.sh

# Generate the dbmate-compatible processed templates + mapping.txt from the
# scripts above and validate them with a process-templates.sh dry run: an
# upstream change is picked up automatically, and anything unsafe (unknown
# psql syntax, dbmate version clash, unsubstituted variable, stale rename)
# fails the BUILD instead of a deploy.
RUN sh /tmp/generate-templates.sh /tmp/elearning-scripts-origin /tmp/processed-templates /tmp/renames.txt

# Tools CNPG and run-migrations.sh need (the skill's manual step 2.2a)
RUN set -e; \
    for b in barman-cloud-backup barman-cloud-wal-archive barman-cloud-restore dbmate; do \
      command -v "$b" >/dev/null || { echo "missing: $b"; exit 1; }; \
    done; \
    barman-cloud-backup --version; dbmate --version; \
    if find /tmp/elearning-scripts-origin -name '*.bak' | grep -q .; then \
      echo "stray .bak files in elearning-scripts-origin"; exit 1; \
    fi
