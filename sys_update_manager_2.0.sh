#!/bin/bash

# ==========================================================
#  System Update Manager v2.0
#  Author: Błażej Wiecha
# ==========================================================

# ===== AUTO ROOT =====
if [ "$EUID" -ne 0 ]; then
    SUDO="sudo"
else
    SUDO=""
fi

# ===== CONFIG =====
BASE_BACKUP_DIR="/var/backups/sys_manager"
LOG_FILE="/var/log/sys_update_manager.log"

if [ ! -w "/var/log" ]; then
    BASE_BACKUP_DIR="$HOME/sys_manager_backups"
    LOG_FILE="$HOME/sys_update_manager.log"
fi

TIMESTAMP=$(date +%F_%H-%M-%S)
BACKUP_DIR="$BASE_BACKUP_DIR/backup_$TIMESTAMP"

# ===== COLORS =====
GREEN="\e[32m"
RED="\e[31m"
YELLOW="\e[33m"
NC="\e[0m"

# ===== LOG =====
log() {
    echo -e "$1"
    echo "$(date) | $1" >> "$LOG_FILE" 2>/dev/null
}

error_exit() {
    log "${RED}[ERROR] $1${NC}"
    exit 1
}

# ===== DISTRO =====
detect_distro() {
    . /etc/os-release
    DISTRO=$ID
    log "${GREEN}[INFO] System: $DISTRO${NC}"
}

# ===== BACKUP (IMPROVED) =====
create_backup() {
    log "${YELLOW}[INFO] Backup start...${NC}"

    $SUDO mkdir -p "$BACKUP_DIR" || error_exit "mkdir fail"

    # backup ważnych rzeczy (lepiej niż samo /etc)
    $SUDO rsync -a /etc "$BACKUP_DIR/"
    $SUDO rsync -a /var/spool/cron "$BACKUP_DIR/" 2>/dev/null
    $SUDO rsync -a /home "$BACKUP_DIR/home_backup" 2>/dev/null

    # packages
    case $DISTRO in
        ubuntu|debian)
            $SUDO dpkg --get-selections > "$BACKUP_DIR/packages.list"
            ;;
        fedora|rhel|centos)
            $SUDO rpm -qa > "$BACKUP_DIR/packages.list"
            ;;
        arch)
            $SUDO pacman -Qqe > "$BACKUP_DIR/packages.list"
            ;;
    esac

    # integrity hash
    $SUDO tar -czf "$BACKUP_DIR.tar.gz" -C "$BASE_BACKUP_DIR" "backup_$TIMESTAMP"
    sha256sum "$BACKUP_DIR.tar.gz" > "$BACKUP_DIR.hash"

    echo "$BACKUP_DIR" | $SUDO tee "$BASE_BACKUP_DIR/last_backup" > /dev/null

    log "${GREEN}[INFO] Backup OK: $BACKUP_DIR${NC}"
}

# ===== UPDATE =====
update_system() {
    log "${YELLOW}[INFO] Updating...${NC}"

    case $DISTRO in
        ubuntu|debian)
            $SUDO apt update && $SUDO apt upgrade -y
            ;;
        fedora)
            $SUDO dnf upgrade -y
            ;;
        arch)
            $SUDO pacman -Syu --noconfirm
            ;;
        rhel|centos)
            $SUDO yum update -y
            ;;
    esac
}

# ===== VERIFY =====
verify_system() {
    log "${YELLOW}[INFO] Verify...${NC}"

    systemctl is-system-running &>/dev/null || error_exit "System unstable"

    df -h / | awk 'NR==2 {print $5}' | grep -qE '9[0-9]|100' && \
        error_exit "Disk full"

    log "${GREEN}[INFO] System OK${NC}"
}

# ===== ROLLBACK =====
rollback() {

    log "${YELLOW}[INFO] Rollback start${NC}"

    BACKUP_DIR=$(cat "$BASE_BACKUP_DIR/last_backup" 2>/dev/null)

    [ -z "$BACKUP_DIR" ] && error_exit "No backup"

    log "${YELLOW}Using: $BACKUP_DIR${NC}"

    # verify hash
    FILE="$BACKUP_DIR.tar.gz"
    HASH_FILE="$BACKUP_DIR.hash"

    if [ -f "$HASH_FILE" ]; then
        sha256sum -c "$HASH_FILE" --status || error_exit "Backup corrupted"
    fi

    # restore critical dirs
    $SUDO rsync -a "$BACKUP_DIR/etc/" /etc/

    log "${YELLOW}[WARN] restoring packages${NC}"

    case $DISTRO in
        ubuntu|debian)
            $SUDO dpkg --set-selections < "$BACKUP_DIR/packages.list"
            $SUDO apt-get dselect-upgrade -y
            ;;
        fedora)
            $SUDO dnf install -y $(cat "$BACKUP_DIR/packages.list") 2>/dev/null
            ;;
        arch)
            $SUDO pacman -S --noconfirm - < "$BACKUP_DIR/packages.list"
            ;;
    esac

    log "${GREEN}[INFO] Rollback DONE${NC}"
}

# ===== CHECK UPGRADE =====
check_upgrade_available() {
    if command -v do-release-upgrade >/dev/null; then
        do-release-upgrade -c | grep "New release" && return 0
    fi
    return 1
}

# ===== LTS UPGRADE =====
upgrade_lts() {

    [[ "$DISTRO" != "ubuntu" && "$DISTRO" != "debian" ]] && \
        error_exit "Only Ubuntu/Debian"

    check_upgrade_available
    if [ $? -ne 0 ]; then
        log "${RED}[INFO] No LTS available officially${NC}"
    fi

    log "${RED}[WARNING] FULL SYSTEM UPGRADE${NC}"
    echo "Type YES:"
    read A
    [ "$A" != "YES" ] && return

    echo "Type I_UNDERSTAND:"
    read B
    [ "$B" != "I_UNDERSTAND" ] && return

    create_backup

    log "${YELLOW}Upgrade start${NC}"

    $SUDO apt update
    $SUDO apt upgrade -y
    $SUDO apt dist-upgrade -y

    echo "1 normal | 2 dev"
    read mode

    if [ "$mode" == "2" ]; then
        $SUDO do-release-upgrade -d
    else
        $SUDO do-release-upgrade
    fi

    log "${GREEN}[INFO] Upgrade finished${NC}"
}

# ===== MENU =====
menu() {
    echo ""
    echo "=============================="
    echo " System Manager v2.0"
    echo " Author: Błażej Wiecha"
    echo "=============================="
    echo "1 Backup"
    echo "2 Update"
    echo "3 Full (backup+update)"
    echo "4 Rollback"
    echo "5 LTS Upgrade"
    echo "6 Exit"
    echo -n "> "
}

# ===== MAIN =====
detect_distro

while true; do
    menu
    read opt

    case $opt in
        1) create_backup ;;
        2) update_system && verify_system ;;
        3)
            create_backup
            update_system && verify_system || rollback
            ;;
        4) rollback ;;
        5) upgrade_lts ;;
        6) exit 0 ;;
        *) echo "bad option" ;;
    esac
done
