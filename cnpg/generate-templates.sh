#!/bin/sh
set -eu

#######################################
# Generate the dbmate-compatible processed templates + mapping.txt from the
# migration scripts actually baked into the image, then validate the result.
# Automates what hello-k3s-ansible's build-cnpg-postgres skill did by hand
# (processed-templates/*.sql + sha256 mapping.txt), so a newer upstream
# Supabase (base image migrations or self-hosted docker/volumes/db files) is
# picked up on every build instead of going stale.
#
# A file under init-scripts/ or migrations/ is processed when it
#   - has no `-- migrate:up` header (psql-style script), or
#   - contains psql meta-commands (\set, \c), or
#   - is a rename source in renames.txt, or
#   - demotes the postgres role (CNPG's bootstrap superuser).
# Rules (identical to the skill's hand-made templates):
#   \set NAME `echo "$VAR"`      -> line dropped; :'NAME' / :"NAME" / :NAME
#                                  -> '{{VAR}}' / "{{VAR}}" / {{VAR}}
#                                  (process-templates.sh fills {{VAR}} at deploy)
#   \c <db>                      -> line dropped: dbmate runs one file on one
#                                  connection, so the statements run in the
#                                  migration's database (postgres)
#   BEGIN; / COMMIT;             -> dropped (dbmate wraps each file in a txn)
#   no header                    -> `-- migrate:up` (+ transaction:false when it
#                                  runs CREATE DATABASE) ... `-- migrate:down`
#   ALTER ROLE postgres NOSUPERUSER -> commented out
#   renames.txt                  -> template written under the legacy name
# Anything else psql-specific fails the build instead of guessing.
#
# Usage: generate-templates.sh [origin_dir] [templates_dir] [renames_file]
#   defaults: /tmp/elearning-scripts-origin /tmp/processed-templates /tmp/renames.txt
#   PROCESS_TEMPLATES  path of process-templates.sh (default: next to this script)
#######################################

ORIGIN="${1:-/tmp/elearning-scripts-origin}"
TEMPLATES="${2:-/tmp/processed-templates}"
RENAMES="${3:-/tmp/renames.txt}"
PROCESS_TEMPLATES="${PROCESS_TEMPLATES:-$(dirname "$0")/process-templates.sh}"

fail() { echo "ERROR: $*" >&2; exit 1; }

[ -d "$ORIGIN/init-scripts" ] && [ -d "$ORIGIN/migrations" ] || fail "$ORIGIN has no init-scripts/ + migrations/"
[ -f "$RENAMES" ] || fail "renames file not found: $RENAMES"
[ -f "$PROCESS_TEMPLATES" ] || fail "process-templates.sh not found: $PROCESS_TEMPLATES"

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# renames.txt without comments/blank lines: "<source> <dest>"
awk '!/^[[:space:]]*(#|$)/ { print $1, $2 }' "$RENAMES" > "$WORK/renames"
while read -r src dest; do
    [ -f "$ORIGIN/$src" ] || fail "renames.txt source '$src' not found (upstream renamed or dropped it? review renames.txt)"
done < "$WORK/renames"

# --- psql script -> dbmate body converter ---
cat > "$WORK/convert.awk" <<'AWK'
function die(msg) { printf "ERROR: %s:%d: %s\n", FILENAME, FNR, msg > "/dev/stderr"; failed = 1; exit 1 }
function repl_bare(s, name, rep,    out, pos, prv, nxt) {
    out = ""
    while ((pos = index(s, ":" name)) > 0) {
        prv = (pos > 1) ? substr(s, pos - 1, 1) : ""
        nxt = substr(s, pos + 1 + length(name), 1)
        if (prv != ":" && nxt !~ /[A-Za-z0-9_]/) out = out substr(s, 1, pos - 1) rep
        else                                      out = out substr(s, 1, pos + length(name))
        s = substr(s, pos + 1 + length(name))
    }
    return out s
}
BEGIN { q = sprintf("%c", 39); dq = sprintf("%c", 34); nv = 0; started = 0 }
{
    line = $0
    if (line ~ /^[ \t]*\\/) {
        if (line ~ /^[ \t]*\\set[ \t]/) {
            rest = line; sub(/^[ \t]*\\set[ \t]+/, "", rest)
            name = rest; sub(/[ \t].*$/, "", name)
            if (name !~ /^[A-Za-z_][A-Za-z0-9_]*$/ || rest !~ /`[ \t]*echo[ \t]/ || !match(rest, /\$\{?[A-Za-z_][A-Za-z0-9_]*/))
                die("unsupported \\set form (expected: \\set name `echo \"$VAR\"`): " line)
            env = substr(rest, RSTART, RLENGTH); gsub(/[${}]/, "", env)
            names[++nv] = name; envs[nv] = env
            next
        }
        if (line ~ /^[ \t]*\\(c|connect)([ \t]|$)/) {
            printf "NOTE: %s: dropped \"%s\" (runs in the migration database instead)\n", FILENAME, line > "/dev/stderr"
            next
        }
        die("unsupported psql meta-command: " line)
    }
    if (!HAS_UP && toupper(line) ~ /^[ \t]*(BEGIN|COMMIT)[ \t]*;[ \t]*$/) next
    if (line !~ /^[ \t]*--/ && toupper(line) ~ /ALTER[ \t]+(ROLE|USER)[ \t]+"?POSTGRES"?[ \t].*NOSUPERUSER/) {
        print "-- Commented out to prevent error: The bootstrap superuser must have the SUPERUSER attribute"
        print "-- " line
        started = 1
        next
    }
    for (i = 1; i <= nv; i++) {
        gsub(":" q names[i] q, q "{{" envs[i] "}}" q, line)
        gsub(":" dq names[i] dq, dq "{{" envs[i] "}}" dq, line)
        line = repl_bare(line, names[i], "{{" envs[i] "}}")
    }
    if (nv > 0 && (line ~ (":" q "[A-Za-z_]") || line ~ (":" dq "[A-Za-z_]")))
        die("unresolved psql variable: " line)
    if (!started && line ~ /^[ \t]*$/) next   # drop blank lines left at the top by removed \set lines
    started = 1
    print line
}
END { if (failed) exit 1 }
AWK

rm -rf "$TEMPLATES"
mkdir -p "$TEMPLATES"
MAPPING="$TEMPLATES/mapping.txt"
cat > "$MAPPING" <<'EOF'
# GENERATED at image build time by generate-templates.sh -- do not edit.
# Format: sha256_of_upstream_file  source_path  dest_path
# process-templates.sh verifies each hash at deploy time, writes the template
# at dest_path and removes source_path when they differ (rename).
EOF

echo "=== Generating processed templates from $ORIGIN ==="
count=0
for f in $(cd "$ORIGIN" && find init-scripts migrations -type f -name '*.sql' | sort); do
    src="$ORIGIN/$f"
    dest=$(awk -v s="$f" '$1 == s { print $2; exit }' "$WORK/renames")
    has_up=0; grep -q '^-- migrate:up' "$src" && has_up=1
    has_meta=0
    # shellcheck disable=SC1003 # regex matches a literal backslash (psql meta-command)
    grep -Eq '^[[:space:]]*\\' "$src" && has_meta=1
    demote=0; grep -v -E '^[[:space:]]*--' "$src" | grep -Eiq 'ALTER[[:space:]]+(ROLE|USER)[[:space:]]+"?postgres"?[[:space:]].*NOSUPERUSER' && demote=1

    if [ "$has_up" = 1 ] && [ "$has_meta" = 0 ] && [ "$demote" = 0 ] && [ -z "$dest" ]; then
        continue
    fi
    [ -n "$dest" ] || dest="$f"
    out="$TEMPLATES/$dest"
    mkdir -p "$(dirname "$out")"

    awk -v HAS_UP="$has_up" -f "$WORK/convert.awk" "$src" > "$WORK/body"
    if [ "$has_up" = 1 ]; then
        cp "$WORK/body" "$out"
    else
        txn=""
        grep -Eiq 'CREATE[[:space:]]+DATABASE' "$WORK/body" && txn=" transaction:false"
        { echo "-- migrate:up$txn"; cat "$WORK/body"; echo; echo "-- migrate:down"; } > "$out"
    fi

    echo "$(sha256sum "$src" | cut -d' ' -f1)  $f  $dest" >> "$MAPPING"
    count=$((count + 1))
    if [ "$f" = "$dest" ]; then echo "--- $f"; else echo "--- $f -> $dest"; fi
    diff -u "$src" "$out" | sed '1,2d' || true
done
echo "=== $count templates generated ==="

# --- Validate: run the deploy-time pre-processor exactly as the pod will ---
echo "=== Validating (process-templates.sh dry run) ==="
TEMPLATES_DIR="$TEMPLATES" POSTGRES_USER=supabase_admin POSTGRES_PASSWORD=verify-password \
    JWT_SECRET=verify-jwt-secret JWT_EXP=3600 \
    sh "$PROCESS_TEMPLATES" "$ORIGIN" "$WORK/out"

for f in $(cd "$WORK/out" && find init-scripts migrations -type f -name '*.sql' | sort); do
    grep -q '^-- migrate:up' "$WORK/out/$f" || fail "$f has no '-- migrate:up' (dbmate would reject it)"
done
# shellcheck disable=SC1003 # regex matches a literal backslash (psql meta-command)
if grep -rnE '^[[:space:]]*\\' "$WORK/out/init-scripts" "$WORK/out/migrations"; then
    fail "psql meta-commands left in dbmate migrations (above)"
fi
if grep -rn '{{[A-Za-z_]*}}' "$WORK/out"; then
    fail "placeholders process-templates.sh does not substitute (above): extend it for the new variable"
fi
# dbmate keys migrations by leading digits; both dirs share one table
for f in "$WORK"/out/init-scripts/*.sql "$WORK"/out/migrations/*.sql; do
    v=$(basename "$f" | sed -n 's/^\([0-9][0-9]*\).*/\1/p')
    [ -n "$v" ] || fail "$(basename "$f") has no leading version digits"
    echo "$v $(basename "$f")"
done > "$WORK/versions"
dups=$(awk '{print $1}' "$WORK/versions" | sort | uniq -d)
if [ -n "$dups" ]; then
    for v in $dups; do awk -v v="$v" '$1 == v' "$WORK/versions"; done
    fail "duplicate dbmate versions (above): add a rename to renames.txt"
fi
# run-migrations.sh comments out migrate.sh's hard `create role postgres`
grep -q '^  create role postgres' "$WORK/out/migrate.sh" \
    || fail "migrate.sh no longer has '  create role postgres': run-migrations.sh's sed patch needs updating"

echo "=== Templates valid: $count processed, $(wc -l < "$WORK/versions" | tr -d ' ') dbmate migrations ==="
