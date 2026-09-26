#!/bin/sh
set -eu

#######################################
# Fetch the official Supabase self-hosted DB init files, exactly as
# supabase/supabase's docker/docker-compose.yml mounts them into the `db`
# service's /docker-entrypoint-initdb.d.
#
# The mount list is read from docker-compose.yml itself (not hard-coded), so an
# upstream rename or a newly mounted file is picked up automatically.
# Uses git ls-remote + raw.githubusercontent.com only (no GitHub REST API
# quota needed).
#
# Usage: fetch-supabase-selfhosted.sh [ref] [out_dir]
#   ref      branch, tag or full commit SHA of supabase/supabase (default: master)
#   out_dir  default: <this dir>/.upstream
#
# Output (out_dir):
#   initdb/<path under /docker-entrypoint-initdb.d>   the mounted files
#   supabase-sha             resolved commit SHA
#   official-postgres-image  image the upstream db service runs
#   mounts.txt               "<source> <initdb path>" per mount
#######################################

REPO_URL="https://github.com/supabase/supabase"
RAW_URL="https://raw.githubusercontent.com/supabase/supabase"
REF="${1:-master}"
OUT="${2:-$(cd "$(dirname "$0")" && pwd)/.upstream}"

# --- Resolve ref -> commit SHA ---
if printf '%s' "$REF" | grep -Eq '^[0-9a-f]{40}$'; then
    SHA="$REF"
else
    SHA=$(git ls-remote "$REPO_URL" "refs/heads/$REF" "refs/tags/$REF^{}" "refs/tags/$REF" | awk 'NR==1{print $1}')
fi
[ -n "$SHA" ] || { echo "ERROR: could not resolve supabase/supabase ref '$REF'"; exit 1; }
echo "supabase/supabase $REF -> $SHA"

rm -rf "$OUT"
mkdir -p "$OUT/initdb"

fetch() { # <repo path> <dest file>
    curl -fsSL --retry 3 --retry-delay 5 -o "$2" "$RAW_URL/$SHA/$1"
}

fetch docker/docker-compose.yml "$OUT/docker-compose.yml"

# --- Parse the db service: its image + bind mounts into initdb.d ---
awk '
    /^services:[[:space:]]*$/                         { in_services = 1; next }
    in_services && /^  db:[[:space:]]*$/              { in_db = 1; next }
    in_db && /^  [^[:space:]#][^:]*:[[:space:]]*$/    { in_db = 0 }
    in_db && /^[^[:space:]]/                          { in_db = 0 }
    in_db && /^    image:/ {
        img = $2; gsub(/["\047]/, "", img); print "IMAGE " img
    }
    in_db && /\/docker-entrypoint-initdb\.d\// {
        line = $0
        sub(/^[[:space:]]*-[[:space:]]*/, "", line)
        sub(/[[:space:]]+#.*$/, "", line)
        gsub(/["\047]/, "", line)
        n = split(line, part, ":")
        if (n < 2 || part[1] !~ /^\.\/volumes\/db\// || part[2] !~ /^\/docker-entrypoint-initdb\.d\//) next
        dst = part[2]; sub(/^\/docker-entrypoint-initdb\.d\//, "", dst)
        src = part[1]; sub(/^\.\//, "docker/", src)
        print "MOUNT " src " " dst
    }
' "$OUT/docker-compose.yml" > "$OUT/parsed.txt"

awk '$1 == "IMAGE" { print $2 }' "$OUT/parsed.txt" > "$OUT/official-postgres-image"
awk '$1 == "MOUNT" { print $2, $3 }' "$OUT/parsed.txt" > "$OUT/mounts.txt"
rm -f "$OUT/parsed.txt"

[ -s "$OUT/mounts.txt" ] || {
    echo "ERROR: found no ./volumes/db -> /docker-entrypoint-initdb.d mounts in the db service"
    echo "       of docker/docker-compose.yml@$SHA (did the compose layout change?)"
    exit 1
}

# --- Fetch every mounted file to its initdb.d path ---
while read -r src dst; do
    mkdir -p "$OUT/initdb/$(dirname "$dst")"
    fetch "$src" "$OUT/initdb/$dst"
    [ -s "$OUT/initdb/$dst" ] || { echo "ERROR: $src is empty"; exit 1; }
    echo "  $src -> $dst"
done < "$OUT/mounts.txt"

printf '%s\n' "$SHA" > "$OUT/supabase-sha"
echo "official db image: $(cat "$OUT/official-postgres-image")"
echo "fetched $(wc -l < "$OUT/mounts.txt" | tr -d ' ') files into $OUT/initdb"
