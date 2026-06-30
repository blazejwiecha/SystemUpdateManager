# 🛡️ System Update Manager

**Safe Linux Update & Recovery Framework**

![Platform](https://img.shields.io/badge/platform-Linux-blue)
![Language](https://img.shields.io/badge/language-Bash-orange)
![Version](https://img.shields.io/badge/version-v6.1-success)
![License](https://img.shields.io/badge/license-MIT-green)

---

## 📖 Overview

**System Update Manager** is a Bash-based utility designed to simplify and secure Linux system maintenance.

Instead of performing package upgrades blindly, the tool automatically creates a backup or snapshot (depending on the underlying filesystem), performs system validation, executes updates, and provides recovery mechanisms whenever possible.

The project was created as a portfolio and learning project focused on:

- Linux Administration
- DevOps
- Bash Automation
- Cybersecurity
- System Recovery

---

# ✨ Features

## 🔄 Safe Package Updates

- Automatic package updates
- Interactive menu
- Automatic mode
- Dry-run mode
- Pre-update validation
- Detailed logging
- Audit logging

---

## 💾 Smart Backup System

The script automatically detects the best backup strategy.

| Filesystem | Backup | Rollback |
|------------|---------|----------|
| **Btrfs** | Read-only Snapshot | Manual (distribution dependent) |
| **LVM** | Native LVM Snapshot | Supported |
| **Other** | rsync Configuration Backup | Supported |

The package database is also saved before updates.

---

## 🖥 Supported Linux Distributions

- Ubuntu
- Debian
- Fedora
- Rocky Linux
- AlmaLinux
- RHEL
- CentOS
- Arch Linux
- EndeavourOS
- Manjaro
- openSUSE

---

## 🚀 Release Upgrade Support

Supported where officially available.

Examples:

- Ubuntu LTS → newer LTS
- Ubuntu Development Release (`-d`)
- Fedora System Upgrade

Every release upgrade:

- performs a precheck
- creates a backup or snapshot
- requires explicit confirmation
- writes audit logs

---

## 🔍 Pre-flight Safety Checks

Before updating, the script verifies:

- Disk usage
- Available RAM
- System health
- Filesystem type
- Required utilities
- Backup location

---

## 📝 Logging

The following logs are created automatically:

- Application log
- Audit log
- Backup metadata
- Snapshot metadata

---

# 🚀 Usage

## Interactive Mode

```bash
chmod +x system-update-manager.sh
sudo ./system-update-manager.sh
```

---

## Safe Update

```bash
sudo ./system-update-manager.sh full
```

---

## Update Packages Only

```bash
sudo ./system-update-manager.sh update
```

---

## Create Backup / Snapshot

```bash
sudo ./system-update-manager.sh snapshot
```

---

## Rollback

```bash
sudo ./system-update-manager.sh rollback
```

---

## Distribution Upgrade

```bash
sudo ./system-update-manager.sh release-upgrade
```

---

## Automatic Mode

```bash
sudo ./system-update-manager.sh --auto
```

---

## Dry Run

```bash
sudo ./system-update-manager.sh --dry-run
```

---

# ⚙️ Workflow

```
           Precheck
               │
               ▼
      Filesystem Detection
               │
      ┌────────┼────────┐
      ▼        ▼        ▼
   Btrfs      LVM     Other FS
      │        │          │
      ▼        ▼          ▼
 Snapshot  Snapshot    rsync Backup
      │        │          │
      └────────┼──────────┘
               ▼
         Package Update
               │
        ┌──────┴──────┐
        ▼             ▼
     Success       Failure
        │             │
        ▼             ▼
      Finish     Rollback Helper
```

---

# 📂 Project Structure

```
.
├── system-update-manager.sh
├── README.md
└── LICENSE
```

---

# ⚠️ Important Notice

This project is intentionally conservative.

It avoids destructive operations that could permanently damage a Linux installation.

Some rollback procedures (especially on **Btrfs**) depend on the distribution, bootloader configuration and subvolume layout.

For this reason, automatic root rollback is intentionally **not** performed.

Always test the script in a virtual machine or laboratory environment before using it on production systems.

---

# 🎯 Project Goals

- Linux Administration
- Bash Scripting
- DevOps Automation
- Infrastructure Automation
- Backup Automation
- Recovery Planning
- Cybersecurity Best Practices

---

# 🤝 Contributing

Contributions, suggestions and bug reports are welcome.

Feel free to open an Issue or submit a Pull Request.

---

# 📜 License

Released under the **MIT License**.

---

# 👨‍💻 Author

**Błażej Wiecha**

Cybersecurity • Linux • DevOps • Automation

GitHub:
https://github.com/blazejwiecha
