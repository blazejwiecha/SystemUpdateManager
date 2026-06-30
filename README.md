# 🛠️ System Update Manager

**Author:** Błażej Wiecha  
**Version:** v5.0  

---

## 📌 Description

System Update Manager is a Bash-based tool designed to automate system updates, backups, and rollback mechanisms across multiple Linux distributions.

The project focuses on **system reliability, security, and recovery**, making it useful for administrators, DevOps engineers, and cybersecurity workflows.

---

## 🚀 Features

- ✅ Multi-distro support (Ubuntu, Debian, Fedora, RHEL, Arch)
- ✅ Automatic system updates
- ✅ Backup system (rsync fallback)
- ✅ Real rollback support (LVM snapshots)
- ✅ Btrfs snapshot support
- ✅ Safe upgrade workflow
- ✅ Pre-flight system checks (disk, RAM, system state)
- ✅ Audit logging (security-oriented)
- ✅ Auto mode (non-interactive execution)

---

## 🧠 How It Works

The script automatically detects the system environment and selects the best strategy:

- **LVM detected → snapshot-based rollback**
- **Btrfs detected → native snapshot**
- **Other → rsync backup fallback**

---

## ⚙️ Usage

### 🔹 Run manually
```bash
chmod +x sys_update_manager_5.0.sh
./sys_update_manager_5.0.sh
```
### AUTO MODE
```bash
./sys_update_manager_5.0.sh --auto
