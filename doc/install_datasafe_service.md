# Oracle Data Safe Connector Service Installer

## Overview

`install_datasafe_service.sh` is a comprehensive utility to install and manage
 Oracle Data Safe On-Premises Connectors as systemd services. It supports
 multiple connectors per server with automatic discovery and configuration.

## Features

- ✅ **Auto-discovery**: Automatically discovers available connectors
- ✅ **Interactive Mode**: Guided prompts for easy setup
- ✅ **Non-interactive Mode**: Full CLI support for automation
- ✅ **Dry-run Mode**: Preview changes before applying
- ✅ **Multiple Connectors**: Each connector gets a unique service
- ✅ **Auto-configuration**: Detects CMAN instance name from cman.ora
- ✅ **Sudo Integration**: Configures sudo for non-root management
- ✅ **Documentation**: Generates README for each connector
- ✅ **Validation**: Comprehensive checks before installation
- ✅ **Service Management**: Start, stop, check, and remove services

## Requirements

- **Root access**: Script must be run as root
- **Systemd**: Linux system with systemd
- **Oracle Data Safe Connector**: Already installed
- **Standard directory structure**:

  ```text
  /appl/oracle/product/dsconnect/
  ├── jdk/                          # Java Development Kit
  └── <connector-name>/             # One or more connectors
      ├── oracle_cman_home/
      │   ├── bin/cmctl
      │   └── network/admin/cman.ora
      └── log/
  ```

## Installation

1. Copy the script to your system:

   ```bash
   cp install_datasafe_service.sh /usr/local/sbin/
   chmod +x /usr/local/sbin/install_datasafe_service.sh
   ```

2. Or run directly from the repository:

   ```bash
   sudo ./bin/install_datasafe_service.sh
   ```

## Usage

### Quick Start (Interactive)

Simply run the script as root for interactive mode:

```bash
sudo install_datasafe_service.sh
```

The script will:

1. Discover available connectors
2. Present a selection menu
3. Validate the selected connector
4. Install and start the service
5. Generate documentation

### List Available Connectors

```bash
sudo install_datasafe_service.sh --list
```

Example output:

```text
Available connectors:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 1. ds-conn-oradba-prod                              [NOT INSTALLED]
    Path: /appl/oracle/product/dsconnect/ds-conn-oradba-prod
    CMAN: oradba_cman

 2. ds-conn-oradba-test                              [INSTALLED]
    Path: /appl/oracle/product/dsconnect/ds-conn-oradba-test
    CMAN: test_cman
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Total: 2 connector(s) found
```

### Non-Interactive Installation

Install a specific connector:

```bash
sudo install_datasafe_service.sh \
  --connector ds-conn-oradba-prod \
  --yes
```

With custom configuration:

```bash
sudo install_datasafe_service.sh \
  --connector my-connector \
  --user oracle \
  --group dba \
  --java-home /opt/java/jdk \
  --yes
```

### Dry-Run Mode

Preview what would be done without making changes:

```bash
sudo install_datasafe_service.sh \
  --connector my-connector \
  --dry-run
```

### Check Service Status

```bash
sudo install_datasafe_service.sh \
  --connector my-connector \
  --check
```

### Remove Service

```bash
sudo install_datasafe_service.sh \
  --connector my-connector \
  --remove
```

## Command-Line Options

```text
-n, --connector <name>    Connector name (directory name under base path)
-b, --base <path>         Connector base directory (default: /appl/oracle/product/dsconnect)
-u, --user <user>         OS user for service (default: oracle)
-g, --group <group>       OS group for service (default: dba)
-j, --java-home <path>    JAVA_HOME path (default: /appl/oracle/product/dsconnect/jdk)

-l, --list                List all available connectors
-c, --check               Check if service is installed for connector
-r, --remove              Remove service and sudo configuration

-y, --yes                 Non-interactive mode (use defaults/provided values)
-d, --dry-run             Show what would be done without making changes
-v, --verbose             Verbose output
-h, --help                Show this help message
```

## Environment Variables

Override defaults using environment variables:

```bash
export CONNECTOR_BASE="/custom/path/to/connectors"
export OS_USER="oracle"
export OS_GROUP="dba"
export JAVA_HOME="/opt/java/jdk"

sudo -E install_datasafe_service.sh
```

## What Gets Installed

For each connector, the script creates:

### 1. Systemd Service File

Location: `/etc/systemd/system/oracle_datasafe_<connector-name>.service`

Features:

- Automatic startup/shutdown
- Restart on failure
- Proper environment configuration
- Logging to journald

### 2. Sudo Configuration

Location: `/etc/sudoers.d/<user>-datasafe-<connector-name>`

Allows the specified user to manage the service:

- `systemctl start`
- `systemctl stop`
- `systemctl restart`
- `systemctl status`
- View logs with `journalctl`

### 3. Service Documentation

Location: `<connector-home>/SERVICE_README.md`

Comprehensive guide including:

- Service management commands
- Log viewing examples
- Troubleshooting tips
- Configuration file locations

## Service Management

### As Root

```bash
# Start service
systemctl start oracle_datasafe_my-connector.service

# Stop service
systemctl stop oracle_datasafe_my-connector.service

# Restart service
systemctl restart oracle_datasafe_my-connector.service

# Check status
systemctl status oracle_datasafe_my-connector.service

# Enable auto-start on boot
systemctl enable oracle_datasafe_my-connector.service

# View logs
journalctl -u oracle_datasafe_my-connector.service -f
```

### As Oracle User (with sudo)

```bash
# Start service
sudo systemctl start oracle_datasafe_my-connector.service

# Stop service
sudo systemctl stop oracle_datasafe_my-connector.service

# Restart service
sudo systemctl restart oracle_datasafe_my-connector.service

# Check status
sudo systemctl status oracle_datasafe_my-connector.service

# View logs
sudo journalctl -u oracle_datasafe_my-connector.service -f
```

## Verification

### Check if service is running

```bash
systemctl is-active oracle_datasafe_my-connector.service
```

### Check if service is enabled

```bash
systemctl is-enabled oracle_datasafe_my-connector.service
```

### Verify CMAN is listening

```bash
netstat -tlnp | grep cmgw
# or
ss -tlnp | grep cmgw
```

### Check process

```bash
ps aux | grep cmgw
```

## Troubleshooting

### Service won't start

1. Check service status:

   ```bash
   systemctl status oracle_datasafe_my-connector.service
   ```

2. Check logs:

   ```bash
   journalctl -u oracle_datasafe_my-connector.service --since "10 minutes ago"
   ```

3. Verify permissions:

   ```bash
   ls -la /appl/oracle/product/dsconnect/my-connector/
   ```

4. Check CMAN configuration:

   ```bash
   cat /appl/oracle/product/dsconnect/my-connector/oracle_cman_home/network/admin/cman.ora
   ```

### Connection issues

1. Verify CMAN is running:

   ```bash
   ps aux | grep cmgw
   ```

2. Check listener ports:

   ```bash
   netstat -tlnp | grep cmgw
   ```

3. Review CMAN logs:

   ```bash
   ls -ltr /appl/oracle/product/dsconnect/my-connector/log/
   ```

### Service file issues

Re-run installation to regenerate:

```bash
sudo install_datasafe_service.sh --connector my-connector --yes
```

## Advanced Usage

### Install Multiple Connectors

```bash
# Install connector 1
sudo install_datasafe_service.sh -n connector1 -y

# Install connector 2
sudo install_datasafe_service.sh -n connector2 -y

# Check all services
systemctl list-units 'oracle_datasafe_*' --all
```

### Custom Base Directory

```bash
sudo install_datasafe_service.sh \
  --base /custom/path/to/connectors \
  --connector my-connector \
  --yes
```

### Automation Script

```bash
#!/bin/bash
# install_all_connectors.sh

CONNECTORS=(
  "ds-conn-oradba-prod"
  "ds-conn-oradba-test"
  "ds-conn-oradba-dev"
)

for connector in "${CONNECTORS[@]}"; do
  echo "Installing $connector..."
  sudo install_datasafe_service.sh \
    --connector "$connector" \
    --user oracle \
    --group dba \
    --yes
done
```

## Security Considerations

### Sudo Configuration

The script creates minimal sudo permissions:

- Only specific systemctl commands
- Only for the specific service
- No password required (NOPASSWD)
- Read-only log access via journalctl

### File Permissions

- Service file: 644 (readable by all, writable by root)
- Sudoers file: 440 (readable by root, validated syntax)
- README: 644 (readable by all)

### Service Security

The generated service includes:

- `PrivateTmp=true`: Isolated /tmp directory
- `NoNewPrivileges=true`: Prevent privilege escalation
- Runs as specified non-root user
- Proper file ownership and permissions

## Migration from Old Scripts

If you have old manual service configurations:

1. **Backup existing configuration**:

   ```bash
   cp /etc/systemd/system/oracle_datasafe.service /tmp/oracle_datasafe.service.bak
   ```

2. **Remove old service**:

   ```bash
   systemctl stop oracle_datasafe.service
   systemctl disable oracle_datasafe.service
   rm /etc/systemd/system/oracle_datasafe.service
   systemctl daemon-reload
   ```

3. **Install with new script**:

   ```bash
   sudo install_datasafe_service.sh
   ```

## Examples

### Example 1: Quick Installation

```bash
# Root runs the script
[root@server]# install_datasafe_service.sh

Scanning for Data Safe connectors in: /appl/oracle/product/dsconnect

Available Data Safe On-Premises Connectors:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 1. ds-conn-oradba-prod
 2. ds-conn-oradba-test
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Select connector (1-2) or 'q' to quit: 1
✅ Selected connector: ds-conn-oradba-prod
✅ Connector validated: ds-conn-oradba-prod
▶  Installing Data Safe Connector Service
...
✅ Data Safe Connector Service Installation Complete
```

### Example 2: Automated Deployment

```bash
# Non-interactive installation
sudo install_datasafe_service.sh \
  --connector ds-conn-oradba-prod \
  --user oracle \
  --group dba \
  --java-home /appl/oracle/product/dsconnect/jdk \
  --yes

# Oracle user can now manage the service
[oracle@server]$ sudo systemctl status oracle_datasafe_ds-conn-oradba-prod.service
● oracle_datasafe_ds-conn-oradba-prod.service - Oracle Data Safe On-Premises Connector
   Loaded: loaded (/etc/systemd/system/oracle_datasafe_ds-conn-oradba-prod.service)
   Active: active (running) since Thu 2026-01-11 10:30:00 UTC
```

### Example 3: Dry-Run First

```bash
# Preview what will be done
sudo install_datasafe_service.sh \
  --connector my-connector \
  --dry-run

# If everything looks good, run for real
sudo install_datasafe_service.sh \
  --connector my-connector \
  --yes
```

## Support

For issues or questions:

1. Check the generated README: `<connector-home>/SERVICE_README.md`
2. Review service logs: `journalctl -u oracle_datasafe_<connector-name>.service`
3. Run with verbose output: `--verbose`
4. Check validation: `--check`

## License

Apache License Version 2.0

## Author

Stefan Oehrli (oes) - <stefan.oehrli@oradba.ch>
OraDBA - Oracle Database Infrastructure and Security
