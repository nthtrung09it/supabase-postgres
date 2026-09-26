#!/bin/sh
set -eu

#######################################
# Boss script: orchestrates pre-processing + migration (dbmate only)
#
# Runs inside the database pod. Handles:
#   1. Pre-process templates (hash-verified file replacement + {{VAR}} substitution)
#   2. Create supabase_admin user if not exists + set password
#   3. Run upstream migrate.sh via dbmate
#   4. Post-migration: cnpg pooler setup + restore postgres superuser
#
# Env vars:
#   POSTGRES_DB, POSTGRES_HOST, POSTGRES_PORT, POSTGRES_PASSWORD
#   POSTGRES_USER, JWT_SECRET, JWT_EXP
#######################################

ORIGIN_DIR="${ORIGIN_DIR:-/tmp/elearning-scripts-origin}"
OUTPUT_DIR="${OUTPUT_DIR:-$(mktemp -d /tmp/elearning-scripts.XXXXXX)}"
trap 'rm -rf "$OUTPUT_DIR"' EXIT

export USE_DBMATE=1
export PGPASSWORD="${POSTGRES_PASSWORD:-}"
export DBMATE_MIGRATIONS_TABLE="internal.schema_migrations"

PGHOST="${POSTGRES_HOST:-localhost}"
PGPORT="${POSTGRES_PORT:-5432}"
PGDB="${POSTGRES_DB:-postgres}"

# Helper: run psql as postgres superuser
psql_postgres() {
    psql -v ON_ERROR_STOP=1 --no-password --no-psqlrc \
        -h "$PGHOST" -p "$PGPORT" -U postgres -d "$PGDB" "$@"
}

# Helper: run psql as supabase_admin
psql_admin() {
    psql -v ON_ERROR_STOP=1 --no-password --no-psqlrc \
        -h "$PGHOST" -p "$PGPORT" -U supabase_admin -d "$PGDB" "$@"
}

# === Step 1: Pre-process templates ===
echo "=== Step 1: Pre-processing templates ==="
/tmp/process-templates.sh "$ORIGIN_DIR" "$OUTPUT_DIR"

# === Step 2: Ensure postgres role exists ===
# CNPG creates this during cluster bootstrap. For local Docker testing the
# Nix-based image only ships supabase_admin, so we create it here.
# Uses EXCEPTION handler instead of IF NOT EXISTS to avoid TOCTOU race
# when multiple instances run concurrently (e.g. ArgoCD re-trigger).
echo "=== Step 2: Ensuring postgres role exists ==="
psql_admin <<EOSQL
DO \$\$
BEGIN
    CREATE ROLE postgres WITH LOGIN SUPERUSER PASSWORD '${POSTGRES_PASSWORD}';
EXCEPTION WHEN duplicate_object OR unique_violation THEN
    NULL;
END
\$\$;
DO \$\$
BEGIN
    EXECUTE 'ALTER DATABASE ${PGDB} OWNER TO postgres';
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'ALTER DATABASE owner skipped (concurrent update): %', SQLERRM;
END
\$\$;
EOSQL

# Patch: upstream migrate.sh (dbmate path) does a hard CREATE ROLE postgres
# which fails when the role already exists. Comment it out — we handle it above.
sed -i 's/^  create role postgres/  -- create role postgres/' "$OUTPUT_DIR/migrate.sh"

# === Step 3: Create supabase_admin user if not exists + set password ===
echo "=== Step 3: Setting up supabase_admin user ==="
psql_postgres <<'EOSQL'
DO $$
BEGIN
    CREATE USER supabase_admin WITH LOGIN SUPERUSER CREATEROLE CREATEDB REPLICATION BYPASSRLS;
EXCEPTION WHEN duplicate_object OR unique_violation THEN
    NULL;
END
$$;
EOSQL
psql_postgres <<EOSQL
DO \$\$
BEGIN
    EXECUTE 'ALTER ROLE supabase_admin WITH PASSWORD ''${POSTGRES_PASSWORD}''';
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'ALTER ROLE supabase_admin skipped: %', SQLERRM;
END
\$\$;
EOSQL

echo "Verifying supabase_admin..."
psql_postgres -t -c "SELECT rolname, rolsuper FROM pg_roles WHERE rolname='supabase_admin';"

# === Step 4: Run upstream migrate.sh (init-scripts + migrations via dbmate) ===
echo "=== Step 4: Running migrate.sh ==="
# Create internal schema for dbmate's schema_migrations table (keeps it out of public)
psql_postgres <<'EOSQL'
DO $$
BEGIN
    CREATE SCHEMA internal;
EXCEPTION WHEN duplicate_schema OR unique_violation THEN
    NULL;
END
$$;
EOSQL
"$OUTPUT_DIR/migrate.sh"

# === Step 5: Post-migration setup ===
echo "=== Step 5: Post-migration setup ==="

# Create cnpg_pooler_pgbouncer role + user_search function
psql_postgres <<EOSQL
DO \$\$
BEGIN
    CREATE ROLE cnpg_pooler_pgbouncer WITH LOGIN;
EXCEPTION WHEN duplicate_object OR unique_violation THEN
    NULL;
END
\$\$;

GRANT CONNECT ON DATABASE ${PGDB} TO cnpg_pooler_pgbouncer;

CREATE OR REPLACE FUNCTION public.user_search(uname TEXT)
    RETURNS TABLE (usename name, passwd text)
    LANGUAGE sql SECURITY DEFINER AS
    'SELECT usename, passwd FROM pg_shadow WHERE usename=\$1;';

REVOKE ALL ON FUNCTION public.user_search(text) FROM public;
GRANT EXECUTE ON FUNCTION public.user_search(text) TO cnpg_pooler_pgbouncer;
EOSQL

# Restore postgres superuser role (demoted during migration)
echo "Restoring superuser role for postgres user..."
psql_admin <<'EOSQL'
DO $$
BEGIN
    ALTER ROLE postgres WITH SUPERUSER;
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'ALTER ROLE postgres skipped: %', SQLERRM;
END
$$;
EOSQL

echo "=== All migrations complete ==="
