#!/usr/bin/env bash
# Build a distributable tarball for the OraDBA extension template.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE_DIR="$ROOT_DIR"
DIST_DIR="${ROOT_DIR}/dist"
VERSION_FILE="${ROOT_DIR}/VERSION"

CHECKSUM=true
DRY_RUN=false
VERSION=""
EXT_CHECKSUM_FILE=".extension.checksum"
CLEANUP_CHECKSUM=false

usage() {
    cat << 'USAGE'
Usage: ./scripts/build.sh [options]

Builds a tarball for the extension and writes a SHA256 checksum.
Options:
  --source <path>     Path to the extension root (default: repo root)
  --dist <path>       Output directory for artifacts (default: dist/)
  --version <value>   Override version (default: read from VERSION or .extension)
  --skip-checksum     Do not create checksum file
  --dry-run           Show actions without writing files
  --help              Show this help
USAGE
    exit 0
}

command_exists() {
    command -v "$1" > /dev/null 2>&1
}

checksum_cmd() {
    if command_exists sha256sum; then
        sha256sum "$1"
    else
        shasum -a 256 "$1"
    fi
}

read_metadata_value() {
    local key="$1" file="$2"
    if [[ -f "$file" ]]; then
        awk -F':' -v k="$key" '$1 ~ "^"k"$" {gsub(/^[ \t]+|[ \t]+$/, "", $2); gsub(/^[ \t]+/, "", $2); print $2}' "$file" | head -n1
    fi
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --source)
            SOURCE_DIR="$(cd "$2" && pwd)"
            shift 2
            ;;
        --dist)
            DIST_DIR="$2"
            shift 2
            ;;
        --version)
            VERSION="$2"
            shift 2
            ;;
        --skip-checksum)
            CHECKSUM=false
            shift
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

if [[ ! -d "$DIST_DIR" ]]; then
    mkdir -p "$DIST_DIR"
fi
DIST_DIR="$(cd "$DIST_DIR" && pwd)"

if [[ ! -f "${SOURCE_DIR}/.extension" ]]; then
    echo "Missing .extension file in ${SOURCE_DIR}" >&2
    exit 1
fi

META_NAME="$(read_metadata_value "name" "${SOURCE_DIR}/.extension")"
META_VERSION="$(read_metadata_value "version" "${SOURCE_DIR}/.extension")"
EXTENSION_NAME="${META_NAME:-$(basename "$SOURCE_DIR")}"

if [[ -z "$VERSION" ]]; then
    if [[ -f "$VERSION_FILE" ]]; then
        VERSION="$(tr -d '[:space:]' < "$VERSION_FILE")"
    elif [[ -n "$META_VERSION" ]]; then
        VERSION="$META_VERSION"
    else
        echo "Version not provided and VERSION file missing" >&2
        exit 1
    fi
fi

TARBALL="${DIST_DIR}/${EXTENSION_NAME}-${VERSION}.tar.gz"
CHECKSUM_FILE="${TARBALL}.sha256"

CONTENT_PATHS=(
    .extension
    .checksumignore
    README.md
    CHANGELOG.md
    LICENSE
    VERSION
    bin
    sql
    rcv
    etc
    lib
)
FILES=()
for path in "${CONTENT_PATHS[@]}"; do
    if [[ -e "${SOURCE_DIR}/${path}" ]]; then
        FILES+=("${path}")
    fi
done

if [[ ${#FILES[@]} -eq 0 ]]; then
    echo "No content found to package" >&2
    exit 1
fi

# ------------------------------------------------------------------------------
# Generate checksum file (added to tarball, not kept in source)
# ------------------------------------------------------------------------------
generate_checksum_file() {
    local checksum_path="${SOURCE_DIR}/${EXT_CHECKSUM_FILE}"
    CLEANUP_CHECKSUM=true

    {
        echo "# OraDBA Extension Checksums"
        echo "# Generated: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
        echo "# Version: ${VERSION}"
        echo "#"

        cd "${SOURCE_DIR}" || exit 1

        # Collect files included in the package (excluding the checksum itself)
        mapfile -t checksum_list < <(
            for entry in "${FILES[@]}"; do
                [[ "$entry" == "$EXT_CHECKSUM_FILE" ]] && continue
                [[ "$entry" == ".extension" ]] && continue
                if [[ -d "$entry" ]]; then
                    find "$entry" -type f
                elif [[ -f "$entry" ]]; then
                    echo "$entry"
                fi
            done | sort
        )

        for f in "${checksum_list[@]}"; do
            checksum_cmd "$f"
        done
    } > "$checksum_path"

    local count
    count=$(grep -c '^[^#]' "$checksum_path" || true)
    echo "Created checksum file ${EXT_CHECKSUM_FILE} with ${count} entries"
}

trap '[[ "$CLEANUP_CHECKSUM" == true ]] && rm -f "${SOURCE_DIR}/${EXT_CHECKSUM_FILE}"' EXIT

generate_checksum_file
FILES+=("$EXT_CHECKSUM_FILE")

echo "Extension : ${EXTENSION_NAME}"
zip_list=$(printf '\n  - %s' "${FILES[@]}")
echo "Includes   :${zip_list}"
echo "Version   : ${VERSION}"
echo "Artifacts :"
echo "  - ${TARBALL}"
if [[ "$CHECKSUM" == true ]]; then
    echo "  - ${CHECKSUM_FILE}"
fi

if [[ "$DRY_RUN" == true ]]; then
    echo "Dry run enabled; no files written."
    exit 0
fi

mkdir -p "$DIST_DIR"

tar -czf "$TARBALL" -C "$SOURCE_DIR" "${FILES[@]}"
echo "Created tarball: $TARBALL"

if [[ "$CHECKSUM" == true ]]; then
    if command_exists sha256sum; then
        sha256sum "$TARBALL" > "$CHECKSUM_FILE"
    else
        shasum -a 256 "$TARBALL" > "$CHECKSUM_FILE"
    fi
    echo "Created checksum: $CHECKSUM_FILE"
fi
