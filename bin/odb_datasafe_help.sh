#!/usr/bin/env bash
# ------------------------------------------------------------------------------
# OraDBA - Oracle Database Infrastructure and Security, 5630 Muri, Switzerland
# ------------------------------------------------------------------------------
# Script.....: odb_datasafe_help.sh
# Author.....: Stefan Oehrli (oes) stefan.oehrli@oradba.ch
# Date.......: 2026.02.11
# Version....: v0.7.0
# Purpose....: Display help overview of all available Data Safe tools
# License....: Apache License Version 2.0
# ------------------------------------------------------------------------------

# =============================================================================
# BOOTSTRAP & CONFIGURATION
# =============================================================================

# Strict mode
set -euo pipefail

# Script metadata
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"
readonly SCRIPT_NAME

# =============================================================================
# FUNCTIONS
# =============================================================================

usage() {
    cat << EOF
Usage: ${SCRIPT_NAME} [OPTIONS]

Description:
  Display an overview of all available Oracle Data Safe tools in this extension.
  Shows script name and purpose/description extracted from script headers.

Options:
  -h, --help              Show this help message
  -f, --format FMT        Output format: table|markdown|csv (default: table)
  -q, --quiet             Suppress header/footer messages

Examples:
  # Show all tools in table format (default)
  ${SCRIPT_NAME}

  # Show as markdown for documentation
  ${SCRIPT_NAME} -f markdown

  # Show as CSV for processing
  ${SCRIPT_NAME} -f csv

EOF
    exit 0
}

# ------------------------------------------------------------------------------
# Function: extract_purpose
# Purpose.: Extract purpose/description from script header
# Args....: $1 - script file path
# Returns.: 0 on success
# Output..: Purpose text to stdout
# ------------------------------------------------------------------------------
extract_purpose() {
    local script_file="$1"
    local purpose=""
    
    # Only search in the first 30 lines (header section) to avoid function docs
    local header
    header=$(head -30 "$script_file")

    # Format 1: "Purpose....:" (standard OraDBA format) - single line with content
    purpose=$(echo "$header" | grep -E "^# Purpose\.+:\s*.+" | head -1 | sed -E 's/^# Purpose\.+:\s*//' || echo "")
    
    # Format 2: "Description :" (alternative format) - single line with content
    if [[ -z "$purpose" ]]; then
        purpose=$(echo "$header" | grep -E "^# Description\s*:\s*.+" | head -1 | sed -E 's/^# Description\s*:\s*//' || echo "")
    fi
    
    # Format 3: Multi-line purpose section (look for "# Purpose:" with no content on same line)
    if [[ -z "$purpose" ]]; then
        # Find "# Purpose:" line (with nothing or only whitespace after colon)
        local line_num
        line_num=$(echo "$header" | grep -n "^# Purpose:\s*$" | head -1 | cut -d: -f1 || echo "0")
        
        if [[ "$line_num" -gt 0 ]]; then
            # Read lines after "# Purpose:" until we hit a non-comment or section header
            local current_line=$((line_num + 1))
            while IFS= read -r line; do
                # Stop if we hit a non-comment line or another section header
                [[ ! "$line" =~ ^#.*$ ]] && break
                [[ "$line" =~ ^#\ (Usage|Options|Examples|Arguments|Returns): ]] && break
                
                # Extract text after "#   " or "# "
                local text
                text=$(echo "$line" | sed -E 's/^#\s*//')
                
                # Skip empty lines
                [[ -z "$text" ]] && continue
                
                # Use first non-empty line as purpose
                if [[ -z "$purpose" ]]; then
                    purpose="$text"
                    break
                fi
            done < <(echo "$header" | tail -n +$current_line)
        fi
    fi
    
    # Default if nothing found
    if [[ -z "$purpose" ]]; then
        purpose="No description available"
    fi

    echo "$purpose"
}

# ------------------------------------------------------------------------------
# Function: show_table
# Purpose.: Display tools in table format
# Args....: None (reads from stdin)
# Returns.: 0 on success
# Output..: Formatted table to stdout
# ------------------------------------------------------------------------------
show_table() {
    printf "\n"
    printf "%-40s %s\n" "Script" "Purpose"
    printf "%-40s %s\n" "$(printf '%0.s-' {1..40})" "$(printf '%0.s-' {1..90})"
    
    while IFS='|' read -r script purpose; do
        # Truncate purpose if too long (max 87 chars to fit 130 char terminal)
        if [[ ${#purpose} -gt 87 ]]; then
            purpose="${purpose:0:84}..."
        fi
        printf "%-40s %s\n" "$script" "$purpose"
    done
    
    printf "\n"
}

# ------------------------------------------------------------------------------
# Function: show_markdown
# Purpose.: Display tools in markdown format
# Args....: None (reads from stdin)
# Returns.: 0 on success
# Output..: Markdown table to stdout
# ------------------------------------------------------------------------------
show_markdown() {
    printf "\n"
    printf "| %-38s | %s |\n" "Script" "Purpose"
    printf "| %-38s | %s |\n" "$(printf '%0.s-' {1..38})" "$(printf '%0.s-' {1..78})"
    
    while IFS='|' read -r script purpose; do
        printf "| %-38s | %s |\n" "$script" "$purpose"
    done
    
    printf "\n"
}

# ------------------------------------------------------------------------------
# Function: show_csv
# Purpose.: Display tools in CSV format
# Args....: None (reads from stdin)
# Returns.: 0 on success
# Output..: CSV data to stdout
# ------------------------------------------------------------------------------
show_csv() {
    printf "script,purpose\n"
    
    while IFS='|' read -r script purpose; do
        printf '"%s","%s"\n' "$script" "$purpose"
    done
}

# =============================================================================
# MAIN
# =============================================================================

main() {
    local output_format="table"
    local quiet=false

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                usage
                ;;
            -f|--format)
                [[ -z "${2:-}" ]] && { echo "Error: --format requires an argument" >&2; exit 1; }
                output_format="$2"
                shift 2
                ;;
            -q|--quiet)
                quiet=true
                shift
                ;;
            *)
                echo "Unknown option: $1 (use --help for usage)" >&2
                exit 1
                ;;
        esac
    done

    # Validate output format
    case "$output_format" in
        table|markdown|csv) : ;;
        *)
            echo "Error: Invalid output format: '$output_format'. Use table, markdown, or csv" >&2
            exit 1
            ;;
    esac

    # Show header
    if [[ "$quiet" != "true" ]]; then
        echo "Oracle Data Safe Extension - Available Tools"
    fi

    # Collect script information
    local -a script_data=()
    
    for script in "$SCRIPT_DIR"/*.sh; do
        # Skip this help script itself
        [[ "$(basename "$script")" == "$SCRIPT_NAME" ]] && continue
        
        # Skip if not readable
        [[ ! -r "$script" ]] && continue
        
        local script_name
        script_name="$(basename "$script")"
        
        local purpose
        purpose=$(extract_purpose "$script")
        
        script_data+=("$script_name|$purpose")
    done

    # Sort alphabetically
    local -a sorted_data
    mapfile -t sorted_data < <(printf '%s\n' "${script_data[@]}" | sort)

    # Display based on format
    case "$output_format" in
        markdown)
            printf '%s\n' "${sorted_data[@]}" | show_markdown
            ;;
        csv)
            printf '%s\n' "${sorted_data[@]}" | show_csv
            ;;
        table|*)
            printf '%s\n' "${sorted_data[@]}" | show_table
            ;;
    esac

    # Show footer
    if [[ "$quiet" != "true" ]]; then
        local count=${#sorted_data[@]}
        echo "Total: $count scripts available"
        echo ""
        echo "For more information:"
        echo "  - Quick Reference: doc/quickref.md"
        echo "  - Documentation:   doc/index.md"
        echo "  - Complete Guide:  README.md"
    fi
}

# Run main
main "$@"

# --- End of odb_datasafe_help.sh ----------------------------------------------
