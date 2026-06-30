# Runbook: Oracle Data Safe Connector Service Management

This runbook covers installation, management, and troubleshooting of Oracle Data Safe
On-Premises Connectors running as systemd services under the OraDBA framework.

## Architecture Overview

```text
oradba_dsctl.sh  <-->  systemd  <-->  Oracle CMAN (cmctl)
     |                    |
     |  (INVOCATION_ID    |
     |   set by systemd)  |
     +--- port check -----+--- ExecStart/ExecStop via oradba_dsctl.sh
```

Key design points:

- `oradba_dsctl.sh start/stop <alias>` delegates to `systemctl` when a service unit
  exists and `INVOCATION_ID` is not set (i.e. not already running inside systemd).
- When systemd calls `oradba_dsctl.sh` as `ExecStart`/`ExecStop`, `INVOCATION_ID` is
  set, so `oradba_dsctl.sh` calls `cmctl` directly - no infinite delegation loop.
- `status` always checks the actual port state, never delegates to systemd.
- Service name convention: `oracle_datasafe_<connector-dir-basename>.service`
  - Example: `/appl/oracle/product/exacc-wob-vwg-ha3` -> `oracle_datasafe_exacc-wob-vwg-ha3.service`

## Service Installation Workflow

### Step 1 - Prepare (as oracle/service user)

```bash
# List available connectors
install_datasafe_service.sh --list

# Prepare service config for a specific connector
install_datasafe_service.sh --prepare -n exacc-wob-vwg-ha3

# Prepare all connectors at once
install_datasafe_service.sh --prepare --all

# Dry-run to preview what will be generated
install_datasafe_service.sh --prepare -n exacc-wob-vwg-ha3 --dry-run
```

Generated files per connector:

- `<connector-home>/etc/systemd/oracle_datasafe_<name>.service`
- `<connector-home>/SERVICE_README.md`

### Step 2 - Install (as root)

```bash
# Install a specific connector service
sudo install_datasafe_service.sh --install -n exacc-wob-vwg-ha3

# Install all connectors
sudo install_datasafe_service.sh --install --all

# Dry-run install
sudo install_datasafe_service.sh --install -n exacc-wob-vwg-ha3 --dry-run
```

Install actions performed:

1. Copy service unit to `/etc/systemd/system/`
2. Validate and install `/etc/sudoers.d/oradba-datasafe`
3. `systemctl daemon-reload`
4. `systemctl enable <service>`
5. `systemctl start <service>`

### Step 3 - Verify

```bash
# Check installation status
install_datasafe_service.sh --check -n exacc-wob-vwg-ha3

# List all installed services and their state
oradba_dsctl.sh services
# or via alias:
dssvc
```

## Service Management

Three interfaces are available for managing connector services:

### Interface 1 - oradba_dsctl.sh (recommended)

```bash
# Start a connector (delegates to systemd if service unit exists)
oradba_dsctl.sh start dscon3

# Stop a connector (delegates to systemd if service unit exists)
oradba_dsctl.sh stop dscon3

# Restart a connector
oradba_dsctl.sh restart dscon3

# Check actual port-based status (always live, no systemd delegation)
oradba_dsctl.sh status dscon3

# List all installed oracle_datasafe_* service units
oradba_dsctl.sh services

# Operate on all registered connectors (requires justification)
oradba_dsctl.sh start
oradba_dsctl.sh stop --force
```

### Interface 2 - systemctl (direct)

```bash
# Start
sudo systemctl start oracle_datasafe_exacc-wob-vwg-ha3.service

# Stop
sudo systemctl stop oracle_datasafe_exacc-wob-vwg-ha3.service

# Restart
sudo systemctl restart oracle_datasafe_exacc-wob-vwg-ha3.service

# Status (systemd view - may differ from actual port state)
systemctl status oracle_datasafe_exacc-wob-vwg-ha3.service

# Enable auto-start on boot
sudo systemctl enable oracle_datasafe_exacc-wob-vwg-ha3.service

# Disable auto-start on boot
sudo systemctl disable oracle_datasafe_exacc-wob-vwg-ha3.service
```

### Interface 3 - oraup / u alias

```bash
# Show OraDBA environment overview including connector status
oraup
# or short alias:
u
```

### Listing Installed Services

```bash
# Via oradba_dsctl.sh subcommand
oradba_dsctl.sh services

# Via shell alias (defined in oradba_standard.conf)
dssvc

# Via systemctl directly
systemctl list-units "oracle_datasafe_*.service"
systemctl list-unit-files "oracle_datasafe_*.service"
```

## Sudoers Configuration

`/etc/sudoers.d/oradba-datasafe` is a shared file covering all connectors.
It is installed once and not removed on per-connector uninstall.

```
# /etc/sudoers.d/oradba-datasafe
Cmnd_Alias ORADBA_DATASAFE_CTL = \
    /usr/bin/systemctl start   oracle_datasafe_*.service, \
    /usr/bin/systemctl stop    oracle_datasafe_*.service, \
    /usr/bin/systemctl restart oracle_datasafe_*.service, \
    /usr/bin/systemctl reload  oracle_datasafe_*.service, \
    /usr/bin/systemctl enable  oracle_datasafe_*.service, \
    /usr/bin/systemctl disable oracle_datasafe_*.service

Cmnd_Alias ORADBA_DATASAFE_ADMIN = \
    /path/to/odb_datasafe/bin/install_datasafe_service.sh, \
    /path/to/odb_datasafe/bin/uninstall_all_datasafe_services.sh

oracle ALL=(root) NOPASSWD: ORADBA_DATASAFE_CTL
oracle ALL=(root) NOPASSWD: ORADBA_DATASAFE_ADMIN
```

Regenerate by re-running `--prepare` followed by `--install` after changing `OS_USER`.

## Service Lifecycle

### Full lifecycle commands

```bash
# 1. Prepare (oracle user)
install_datasafe_service.sh --prepare -n exacc-wob-vwg-ha3

# 2. Install and start (root)
sudo install_datasafe_service.sh --install -n exacc-wob-vwg-ha3

# 3. Enable/disable auto-start
sudo systemctl enable oracle_datasafe_exacc-wob-vwg-ha3.service
sudo systemctl disable oracle_datasafe_exacc-wob-vwg-ha3.service

# 4. Uninstall (root) - preserves shared sudoers file
sudo install_datasafe_service.sh --uninstall -n exacc-wob-vwg-ha3

# 5. Uninstall all connectors at once
sudo uninstall_all_datasafe_services.sh
```

## Troubleshooting

### systemd shows active (exited) but connector is actually stopped

**Cause**: `Type=oneshot + RemainAfterExit=yes` means systemd tracks only whether
`ExecStart` returned 0, not the live process state. If the connector was stopped
manually (not via systemd), systemd still shows `active (exited)`.

**Fix implemented in oradba_dsctl.sh**: `start` and `stop` now delegate to
`sudo systemctl start/stop` when a service unit exists and `INVOCATION_ID` is
not set. This ensures systemd always tracks the correct state after manual
`oradba_dsctl.sh start/stop` calls.

**Immediate workaround** (before fix is deployed):

```bash
# Reset systemd state manually after manual stop
sudo systemctl stop oracle_datasafe_exacc-wob-vwg-ha3.service
```

### `oradba_dsctl.sh status` returns no output or exits immediately

**Cause**: `set -euo pipefail` was active. `execute_plugin_function_v2` returns exit
code 1 when a connector is stopped. The assignment `status_exit_code=$?` was on a
separate line from the command, so `set -e` caused the script to exit at the
`execute_plugin_function_v2` call before the status could be captured.

**Fix implemented**: All three call sites (`show_status`, `start_connector`,
`stop_connector`) now use:

```bash
execute_plugin_function_v2 ... > /dev/null 2>&1 || status_exit_code=$?
```

The `|| status_exit_code=$?` idiom prevents `set -e` from triggering on a non-zero
exit while still capturing the exit code.

### Verify actual port state

The status check is port-based. To inspect directly:

```bash
# Show which port the connector is configured to use
grep -i port /appl/oracle/product/exacc-wob-vwg-ha3/oracle_cman_home/network/admin/cman.ora

# Check if that port is listening
ss -tnlp | grep :1563
# or on older systems:
netstat -tnlp | grep :1563
```

A listening port on the configured port confirms the connector is running.

### Service fails to start

1. Check service status: `systemctl status oracle_datasafe_<name>.service`
2. Check recent logs: `journalctl -u oracle_datasafe_<name>.service --since "10 minutes ago"`
3. Verify `ExecStart` binary exists: `grep ExecStart /etc/systemd/system/oracle_datasafe_<name>.service`
4. Check CMAN configuration: `<connector-home>/oracle_cman_home/network/admin/cman.ora`
5. Verify Java: `<JAVA_HOME>/bin/java -version`

### Service state mismatch between systemd and port check

```bash
# systemd view (may be stale for Type=oneshot)
systemctl is-active oracle_datasafe_<name>.service

# Live port check (authoritative)
oradba_dsctl.sh status <alias>

# Force systemd to re-evaluate
sudo systemctl stop oracle_datasafe_<name>.service
sudo systemctl start oracle_datasafe_<name>.service
```

## Log Access

```bash
# View all logs for a connector service
journalctl -u oracle_datasafe_exacc-wob-vwg-ha3.service

# Follow logs in real time
journalctl -u oracle_datasafe_exacc-wob-vwg-ha3.service -f

# Logs since last boot
journalctl -u oracle_datasafe_exacc-wob-vwg-ha3.service -b

# Logs from today only
journalctl -u oracle_datasafe_exacc-wob-vwg-ha3.service --since today

# Logs from the last hour
journalctl -u oracle_datasafe_exacc-wob-vwg-ha3.service --since "1 hour ago"

# oradba_dsctl.sh log file
tail -f /var/log/oracle/oradba_dsctl.log
```
