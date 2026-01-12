# Oracle Data Safe Connector Service - Quickstart for Root Admins

**Quick 5-minute** setup guide for Linux administrators

## What This Does

Installs Oracle Data Safe On-Premises Connector as a systemd service that:

- Starts automatically on boot
- Can be managed by oracle user (with sudo)
- Logs to journald for easy monitoring

## Prerequisites

✅ Oracle Data Safe Connector already installed
✅ Root access
✅ Connectors in: `/appl/oracle/product/dsconnect/<connector-name>/`

## Quick Install (3 commands)

### 1. List available connectors

```bash
sudo install_datasafe_service.sh --list
```

### 2. Install service (interactive - script will ask which connector)

```bash
sudo install_datasafe_service.sh
```

### 3. Verify it's running

```bash
sudo systemctl status oracle_datasafe_<connector-name>.service
```

**Done!** The oracle user can now manage it.

## Common Commands

### For Root Admin

```bash
# Install
sudo install_datasafe_service.sh

# Check what would be done (preview)
sudo install_datasafe_service.sh -n my-connector --dry-run

# Remove service
sudo install_datasafe_service.sh -n my-connector --remove

# Check status
sudo systemctl status oracle_datasafe_my-connector.service
```

### For Oracle User (after installation)

```bash
# Start
sudo systemctl start oracle_datasafe_my-connector.service

# Stop
sudo systemctl stop oracle_datasafe_my-connector.service

# Restart
sudo systemctl restart oracle_datasafe_my-connector.service

# Check status
sudo systemctl status oracle_datasafe_my-connector.service

# View logs
sudo journalctl -u oracle_datasafe_my-connector.service -f
```

## Non-Interactive Install (For Scripts)

```bash
# Install specific connector without prompts
sudo install_datasafe_service.sh \
  --connector ds-conn-exacc-p1312-wob-vwg \
  --yes
```

## What Gets Created

1. **Service file**: `/etc/systemd/system/oracle_datasafe_<name>.service`
2. **Sudo config**: `/etc/sudoers.d/oracle-datasafe-<name>` (allows oracle user to manage service)
3. **Documentation**: `<connector-home>/SERVICE_README.md` (detailed guide for operations)

## Troubleshooting

### Service won't start

```bash
# Check status
sudo systemctl status oracle_datasafe_my-connector.service

# Check logs
sudo journalctl -u oracle_datasafe_my-connector.service --since "10 minutes ago"
```

### Need to reinstall

```bash
# Remove and reinstall
sudo install_datasafe_service.sh -n my-connector --remove
sudo install_datasafe_service.sh -n my-connector --yes
```

### Check if CMAN is running

```bash
ps aux | grep cmgw
netstat -tlnp | grep cmgw
```

## Advanced Options

```bash
# Custom user/group
sudo install_datasafe_service.sh \
  -n my-connector \
  -u oravw \
  -g dba \
  --yes

# Skip sudo configuration (if you manage sudo externally)
sudo install_datasafe_service.sh \
  -n my-connector \
  --skip-sudo \
  --yes

# Test mode (preview without needing root)
install_datasafe_service.sh -n my-connector --test
```

## Uninstall All Services

```bash
# Remove all Data Safe services at once
sudo uninstall_all_datasafe_services.sh

# Preview what would be removed
sudo uninstall_all_datasafe_services.sh --dry-run
```

## Multiple Connectors

Each connector gets its own service:

```bash
# Install connector 1
sudo install_datasafe_service.sh -n connector1 -y

# Install connector 2
sudo install_datasafe_service.sh -n connector2 -y

# List all
systemctl list-units 'oracle_datasafe_*' --all
```

## Help & Documentation

```bash
# Show all options
install_datasafe_service.sh --help

# Read detailed docs
cat <connector-home>/SERVICE_README.md
```

## Summary

**Install**: `sudo install_datasafe_service.sh`
**Status**: `sudo systemctl status oracle_datasafe_<name>.service`
**Logs**: `sudo journalctl -u oracle_datasafe_<name>.service -f`
**Remove**: `sudo install_datasafe_service.sh -n <name> --remove`

That's it! Simple, automated, and production-ready.

---
For detailed documentation see: `doc/install_datasafe_service.md`
