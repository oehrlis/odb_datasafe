# Quick Reference - Oracle Data Safe Connector Service (Root Admin)

Commands for Unix/root admins. DBA must have run `--prepare` first.

## Install

```bash
# Single connector
sudo install_datasafe_service.sh --install -n <connector-name>

# All connectors at once
sudo install_datasafe_service.sh --install --all

# Dry-run preview
sudo install_datasafe_service.sh --install -n <connector-name> --dry-run

# Non-interactive
sudo install_datasafe_service.sh --install -n <connector-name> --yes
```

## Uninstall

```bash
# Single connector
sudo install_datasafe_service.sh --uninstall -n <connector-name>

# All connectors (thin wrapper)
sudo uninstall_all_datasafe_services.sh --uninstall

# Dry-run
sudo uninstall_all_datasafe_services.sh --dry-run
```

## Status and Check

```bash
# Check install status (no root needed)
install_datasafe_service.sh --check -n <connector-name>
install_datasafe_service.sh --check --all

# List connectors and install state
install_datasafe_service.sh --list

# List installed systemd units
systemctl list-units "oracle_datasafe_*.service"
```

## Service Control

```bash
# Start / stop / restart
sudo systemctl start   oracle_datasafe_<connector-name>.service
sudo systemctl stop    oracle_datasafe_<connector-name>.service
sudo systemctl restart oracle_datasafe_<connector-name>.service

# Status
systemctl status oracle_datasafe_<connector-name>.service

# Enable / disable auto-start on boot
sudo systemctl enable  oracle_datasafe_<connector-name>.service
sudo systemctl disable oracle_datasafe_<connector-name>.service

# Follow logs
journalctl -u oracle_datasafe_<connector-name>.service -f

# Logs since last boot
journalctl -u oracle_datasafe_<connector-name>.service -b
```

---

Full documentation: [install_datasafe_service.md](install_datasafe_service.md)
