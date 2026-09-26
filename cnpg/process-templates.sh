#!/bin/sh
set -eu

#######################################
# Pre-processor: copies elearning-scripts-origin/ to elearning-scripts/,
# replaces non-dbmate-compatible files with pre-processed templates,
# optionally renames files (source -> dest), and substitutes {{VAR}}
# placeholders with env var values.
#
# Uses hash-based mapping for idempotency:
#   - Each non-dbmate-compatible file has a known sha256 hash
#   - If the hash matches, the file is replaced with its processed template
#   - If source_path != dest_path, the source is removed (rename)
#   - If the hash doesn't match, upstream changed and the template is stale
#
# Usage: process-templates.sh [origin_dir] [output_dir]
#   origin_dir       defaults to /tmp/elearning-scripts-origin
#   output_dir       defaults to /tmp/elearning-scripts
#   TEMPLATES_DIR    defaults to /tmp/processed-templates
#######################################

ORIGIN_DIR="${1:-/tmp/elearning-scripts-origin}"
OUTPUT_DIR="${2:-/tmp/elearning-scripts}"
TEMPLATES_DIR="${TEMPLATES_DIR:-/tmp/processed-templates}"

# Fresh copy each time (safe for re-runs)
rm -rf "$OUTPUT_DIR"
cp -r "$ORIGIN_DIR" "$OUTPUT_DIR"

# --- Step 1: Replace files using hash-based mapping ---
MAPPING="$TEMPLATES_DIR/mapping.txt"
if [ ! -f "$MAPPING" ]; then
    echo "ERROR: mapping file not found: $MAPPING"
    exit 1
fi

while IFS= read -r line; do
    # Skip comments and blank lines
    case "$line" in
        '#'*|'') continue ;;
    esac

    expected_hash=$(echo "$line" | awk '{print $1}')
    source_path=$(echo "$line" | awk '{print $2}')
    dest_path=$(echo "$line" | awk '{print $3}')

    source_file="$OUTPUT_DIR/$source_path"
    dest_file="$OUTPUT_DIR/$dest_path"
    template_file="$TEMPLATES_DIR/$dest_path"

    if [ ! -f "$source_file" ]; then
        echo "ERROR: source file not found: $source_path"
        exit 1
    fi

    if [ ! -f "$template_file" ]; then
        echo "ERROR: processed template not found: $template_file"
        exit 1
    fi

    # Verify hash -- exit immediately on mismatch
    actual_hash=$(sha256sum "$source_file" | cut -d' ' -f1)
    if [ "$actual_hash" != "$expected_hash" ]; then
        echo "ERROR: hash mismatch for $source_path"
        echo "  expected: $expected_hash"
        echo "  actual:   $actual_hash"
        echo "  Upstream file changed! Update processed-templates/$dest_path and mapping.txt"
        exit 1
    fi

    # Place processed template at dest; remove source if rename (source != dest)
    mkdir -p "$(dirname "$dest_file")"
    cp "$template_file" "$dest_file"
    if [ "$source_path" != "$dest_path" ]; then
        rm "$source_file"
        echo "OK: $source_path -> $dest_path"
    else
        echo "OK: $source_path"
    fi
done < "$MAPPING"

# --- Step 2: Substitute {{VAR}} placeholders with env var values ---
find "$OUTPUT_DIR" -name '*.sql' -type f | while read -r f; do
    sed -i \
        -e "s|{{POSTGRES_USER}}|${POSTGRES_USER:-supabase_admin}|g" \
        -e "s|{{POSTGRES_PASSWORD}}|${POSTGRES_PASSWORD:-}|g" \
        -e "s|{{JWT_SECRET}}|${JWT_SECRET:-}|g" \
        -e "s|{{JWT_EXP}}|${JWT_EXP:-}|g" \
        "$f"
done
