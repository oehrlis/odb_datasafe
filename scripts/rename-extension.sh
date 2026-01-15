#!/usr/bin/env bash
# Rename the extension metadata after cloning/forking.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKDIR="$ROOT_DIR"
NEW_NAME=""
DESCRIPTION=""
DRY_RUN=false

usage() {
    cat << 'USAGE'
Usage: ./scripts/rename-extension.sh --name <newname> [options]

Options:
  --name <newname>        New extension name (required)
  --description <text>    Update description in .extension
  --workdir <path>        Root directory containing the extension (default: repo root)
  --dry-run               Show actions without applying changes
  --help                  Show this help
USAGE
    exit 0
}

read_metadata_value() {
    local key="$1" file="$2"
    if [[ -f "$file" ]]; then
        awk -F':' -v k="$key" '$1 ~ "^"k"$" {gsub(/^[ \t]+|[ \t]+$/, "", $2); gsub(/^[ \t]+/, "", $2); print $2}' "$file" | head -n1
    fi
}

replace_tokens() {
    local file="$1" old="$2" new="$3" old_upper="$4" new_upper="$5" description="$6"
    python3 - "$file" "$old" "$new" "$old_upper" "$new_upper" "$description" << 'PY'
from pathlib import Path
import sys, re

path, old, new, old_upper, new_upper, description = sys.argv[1:]
text = Path(path).read_text()
text = text.replace(old, new).replace(old_upper, new_upper)

if description and Path(path).name == ".extension":
    if re.search(r"^description:", text, flags=re.MULTILINE):
        text = re.sub(r"^description:.*$", f"description: {description}", text, flags=re.MULTILINE)
    else:
        text = text.rstrip() + f"\ndescription: {description}\n"

Path(path).write_text(text)
PY
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --name)
            NEW_NAME="$2"
            shift 2
            ;;
        --description)
            DESCRIPTION="$2"
            shift 2
            ;;
        --workdir)
            WORKDIR="$(cd "$2" && pwd)"
            shift 2
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --help)
            usage
            ;;
        *)
            echo "Unknown option: $1" >&2
            usage
            ;;
    esac
done

META_FILE="$WORKDIR/.extension"
if [[ -z "$NEW_NAME" ]]; then
    echo "--name is required." >&2
    usage
fi

if [[ ! "$NEW_NAME" =~ ^[a-zA-Z0-9_-]+$ ]]; then
    echo "Invalid extension name. Use letters, numbers, hyphens, or underscores." >&2
    exit 1
fi

if [[ ! -f "$META_FILE" ]]; then
    echo "Missing .extension in $WORKDIR" >&2
    exit 1
fi

OLD_NAME="$(read_metadata_value "name" "$META_FILE")"
OLD_NAME="${OLD_NAME:-$(basename "$WORKDIR")}"
OLD_UPPER=$(echo "$OLD_NAME" | tr '[:lower:]-' '[:upper:]_')
NEW_UPPER=$(echo "$NEW_NAME" | tr '[:lower:]-' '[:upper:]_')

CONFIG_FILE="$WORKDIR/etc/${OLD_NAME}.conf.example"
NEW_CONFIG_FILE="$WORKDIR/etc/${NEW_NAME}.conf.example"

if [[ "$DRY_RUN" == true ]]; then
    echo "Dry run: would rename ${OLD_NAME} -> ${NEW_NAME} in ${WORKDIR}"
    echo "Files to update:"
    find "$WORKDIR" -type f \
        ! -path "$WORKDIR/dist/*" \
        ! -path "$WORKDIR/.git/*" \
        -print | sed "s|^|  - |"
    if [[ -f "$CONFIG_FILE" ]]; then
        echo "Config file rename: ${CONFIG_FILE} -> ${NEW_CONFIG_FILE}"
    fi
    exit 0
fi

while IFS= read -r -d '' file; do
    replace_tokens "$file" "$OLD_NAME" "$NEW_NAME" "$OLD_UPPER" "$NEW_UPPER" "$DESCRIPTION"
done < <(find "$WORKDIR" -type f \
    ! -path "$WORKDIR/dist/*" \
    ! -path "$WORKDIR/.git/*" \
    -print0)

if [[ -f "$CONFIG_FILE" && "$CONFIG_FILE" != "$NEW_CONFIG_FILE" ]]; then
    mv "$CONFIG_FILE" "$NEW_CONFIG_FILE"
fi

echo "Renamed extension to: $NEW_NAME"
if [[ -n "$DESCRIPTION" ]]; then
    echo "Updated description to: $DESCRIPTION"
fi
