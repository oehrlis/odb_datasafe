# Oracle Data Safe Connector Service - Quickstart for Administrators

**Quick setup guide** for Linux and Oracle administrators

## What This Does

Installs Oracle Data Safe On-Premises Connector as a systemd service that:

- Starts automatically on boot
- Can be managed by oracle user (with sudo)
- Logs to journald for easy monitoring

## Prerequisites

✅ Oracle Data Safe Connector already installed
✅ Connectors in: `$ORACLE_BASE/product/<connector-name>/`

## Two-Phase Workflow

### Phase 1: Prepare (as oracle user - NO root needed)

Generate service configuration files:

```bash
# List available connectors
./install_datasafe_service.sh --list

# Prepare service configs (interactive)
./install_datasafe_service.sh --prepare

# Or specify connector
./install_datasafe_service.sh --prepare -n my-connector
```

### Phase 2: Install (as root)

Install prepared configs to system:

```bash
# Install to system
sudo ./install_datasafe_service.sh --install -n my-connector

# Verify it's running
sudo systemctl status oracle_datasafe_my-connector.service
```

**Done!** The oracle user can now manage it.

## Quick Install (All-in-One)

```bash
# Prepare (as oracle user)
./install_datasafe_service.sh -n my-connector

# Install (as root)
sudo ./install_datasafe_service.sh --install -n my-connector
```

## Common Commands

### For Oracle User (Prepare Phase)

```bash
# List connectors
./install_datasafe_service.sh --list

# Prepare service config
./install_datasafe_service.sh --prepare -n my-connector

# Check if service is installed
./install_datasafe_service.sh --check -n my-connector

# Preview what would be done
./install_datasafe_service.sh --prepare -n my-connector --dry-run
```

### For Root Admin (Install Phase)

```bash
# Install to system
sudo ./install_datasafe_service.sh --install -n my-connector

# Preview install
sudo ./install_datasafe_service.sh --install -n my-connector --dry-run

# Uninstall service
sudo ./install_datasafe_service.sh --uninstall -n my-connector

# Check status
sudo systemctl status oracle_datasafe_my-connector.service
```

### For Oracle User (Service Management)

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

## Non-Interactive Workflow (For Scripts)

```bash
# As oracle user - prepare
./install_datasafe_service.sh --prepare -n ds-conn-prod --yes

# As root - install
sudo ./install_datasafe_service.sh --install -n ds-conn-prod --yes
```

## What Gets Created

### During Prepare Phase (in connector etc/ directory)

1. **Service file**: `<connector>/etc/systemd/oracle_datasafe_<name>.service`
2. **Sudo config**: `<connector>/etc/systemd/<user>-datasafe-<name>`
3. **Documentation**: `<connector>/SERVICE_README.md`

### During Install Phase (system locations)

1. **Service file**: `/etc/systemd/system/oracle_datasafe_<name>.service`
2. **Sudo config**: `/etc/sudoers.d/<user>-datasafe-<name>`

## Uninstall All Services

```bash
# List services (as oracle user)
./uninstall_all_datasafe_services.sh --list

# Uninstall all (as root)
sudo ./uninstall_all_datasafe_services.sh --uninstall
```

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
  -u oracle \
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

## Batch Uninstall

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
