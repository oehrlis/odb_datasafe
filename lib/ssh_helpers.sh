#!/usr/bin/env bash
# ------------------------------------------------------------------------------
# OraDBA - Oracle Database Infrastructure and Security, 5630 Muri, Switzerland
# ------------------------------------------------------------------------------
# Module.....: ssh_helpers.sh
# Author.....: Stefan Oehrli (oes) stefan.oehrli@oradba.ch
# Date.......: 2026.02.11
# Version....: v0.9.0
# Purpose.: SSH/SCP helper functions for remote execution and file transfer
# License....: Apache License Version 2.0
# ------------------------------------------------------------------------------

# Guard against multiple sourcing
[[ -n "${SSH_HELPERS_SH_LOADED:-}" ]] && return 0
readonly SSH_HELPERS_SH_LOADED=1

# Require common.sh
if [[ -z "${COMMON_SH_LOADED:-}" ]]; then
    echo "ERROR: ssh_helpers.sh requires common.sh to be loaded first" >&2
    exit 1
fi

# =============================================================================
# DEFAULTS
# =============================================================================

: "${SSH_CONNECT_TIMEOUT:=10}"
: "${SSH_SERVER_ALIVE_INTERVAL:=30}"
: "${SSH_SERVER_ALIVE_COUNT_MAX:=3}"
: "${SSH_STRICT_HOST_KEY_CHECKING:=accept-new}"
: "${SSH_KNOWN_HOSTS_FILE:=}"
: "${SSH_EXTRA_OPTS:=}"

# =============================================================================
# FUNCTIONS
# =============================================================================

# ------------------------------------------------------------------------------
# Function: ssh_require_tools
# Purpose.: Ensure ssh/scp are available locally
# Returns.: 0 on success, exits on missing tools
# ------------------------------------------------------------------------------
ssh_require_tools() {
    require_cmd ssh scp
}

# ------------------------------------------------------------------------------
# Function: ssh_exec
# Purpose.: Execute a command on a remote host via SSH
# Args....: $1 - Host
#           $2 - User
#           $3 - Port
#           $4 - Command (string)
# Returns.: 0 on success, non-zero on failure
# Output..: Command output to stdout/stderr
# ------------------------------------------------------------------------------
ssh_exec() {
    local host="$1"
    local user="$2"
    local port="$3"
    local cmd="$4"

    local -a opts=()
    [[ -n "${SSH_CONNECT_TIMEOUT}" ]] && opts+=(-o "ConnectTimeout=${SSH_CONNECT_TIMEOUT}")
    [[ -n "${SSH_SERVER_ALIVE_INTERVAL}" ]] && opts+=(-o "ServerAliveInterval=${SSH_SERVER_ALIVE_INTERVAL}")
    [[ -n "${SSH_SERVER_ALIVE_COUNT_MAX}" ]] && opts+=(-o "ServerAliveCountMax=${SSH_SERVER_ALIVE_COUNT_MAX}")
    [[ -n "${SSH_STRICT_HOST_KEY_CHECKING}" ]] && opts+=(-o "StrictHostKeyChecking=${SSH_STRICT_HOST_KEY_CHECKING}")
    [[ -n "${SSH_KNOWN_HOSTS_FILE}" ]] && opts+=(-o "UserKnownHostsFile=${SSH_KNOWN_HOSTS_FILE}")

    if [[ -n "${SSH_EXTRA_OPTS}" ]]; then
        local -a extra_opts=()
        read -r -a extra_opts <<< "${SSH_EXTRA_OPTS}"
        opts+=("${extra_opts[@]}")
    fi

    ssh -p "${port}" "${opts[@]}" "${user}@${host}" -- bash -lc "${cmd}"
}

# ------------------------------------------------------------------------------
# Function: ssh_scp_to
# Purpose.: Copy a local file to a remote host via SCP
# Args....: $1 - Local file
#           $2 - Host
#           $3 - User
#           $4 - Port
#           $5 - Remote path
# Returns.: 0 on success, non-zero on failure
# ------------------------------------------------------------------------------
ssh_scp_to() {
    local local_file="$1"
    local host="$2"
    local user="$3"
    local port="$4"
    local remote_path="$5"

    local -a opts=()
    [[ -n "${SSH_CONNECT_TIMEOUT}" ]] && opts+=(-o "ConnectTimeout=${SSH_CONNECT_TIMEOUT}")
    [[ -n "${SSH_STRICT_HOST_KEY_CHECKING}" ]] && opts+=(-o "StrictHostKeyChecking=${SSH_STRICT_HOST_KEY_CHECKING}")
    [[ -n "${SSH_KNOWN_HOSTS_FILE}" ]] && opts+=(-o "UserKnownHostsFile=${SSH_KNOWN_HOSTS_FILE}")

    if [[ -n "${SSH_EXTRA_OPTS}" ]]; then
        local -a extra_opts=()
        read -r -a extra_opts <<< "${SSH_EXTRA_OPTS}"
        opts+=("${extra_opts[@]}")
    fi

    scp -P "${port}" "${opts[@]}" "${local_file}" "${user}@${host}:${remote_path}"
}

# ------------------------------------------------------------------------------
# Function: ssh_check
# Purpose.: Verify SSH connectivity to a remote host
# Args....: $1 - Host
#           $2 - User
#           $3 - Port
# Returns.: 0 on success, non-zero on failure
# ------------------------------------------------------------------------------
ssh_check() {
    local host="$1"
    local user="$2"
    local port="$3"

    ssh_exec "$host" "$user" "$port" "true" > /dev/null 2>&1
}

# ssh_helpers.sh loaded
