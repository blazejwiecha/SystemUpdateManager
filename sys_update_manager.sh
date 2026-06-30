#!/bin/bash

# ===== AUTO ROOT / SUDO =====
if [ "$EUID" -ne 0 ]; then
    SUDO="sudo"
else
    SUDO=""
fi

# ===== KONFIG =====
BASE_BACKUP_DIR="/var/backups"
LOG_FILE="/var/log/sys_update_manager.log"

if [ ! -w "/var/log" ]; then
    BASE_BACKUP_DIR="$HOME/backups"
    LOG_FILE="$HOME/sys_update_manager.log"
fi

BACKUP_DIR="$BASE_BACKUP_DIR/sys_update_$(date +%F_%H-%M)"

# ===== COLORS =====
GREEN="\e[32m"
RED="\e[31m"
YELLOW="\e[33m"
NC="\e[0m"

log() {
    echo -e "$1"
    echo "$(date) - $1" >> "$LOG_FILE" 2>/dev/null
}

error_exit() {
    log "${RED}[ERROR] $1${NC}"
    exit 1
}

# ===== DETEKCJA SYSTEMU =====
detect_distro() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        DISTRO=$ID
    else
        error_exit "Nie można wykryć dystrybucji"
    fi

    log "${GREEN}[INFO] Wykryto system: $DISTRO${NC}"
}

# ===== BACKUP =====
create_backup() {
    log "${YELLOW}[INFO] Tworzenie backupu...${NC}"

    $SUDO mkdir -p "$BACKUP_DIR" || error_exit "Nie można utworzyć katalogu backupu"

    $SUDO tar -czf "$BACKUP_DIR/etc_backup.tar.gz" /etc 2>>"$LOG_FILE"

    case $DISTRO in
        ubuntu|debian)
            $SUDO dpkg --get-selections > "$BACKUP_DIR/packages.list"
            ;;
        fedora|centos|rhel)
            $SUDO rpm -qa > "$BACKUP_DIR/packages.list"
            ;;
        arch)
            $SUDO pacman -Qqe > "$BACKUP_DIR/packages.list"
            ;;
        *)
            error_exit "Nieobsługiwana dystrybucja"
            ;;
    esac

    echo "$BACKUP_DIR" | $SUDO tee "$BASE_BACKUP_DIR/last_backup_path" > /dev/null

    log "${GREEN}[INFO] Backup zakończony: $BACKUP_DIR${NC}"
}

# ===== AKTUALIZACJA =====
update_system() {
    log "${YELLOW}[INFO] Aktualizacja systemu...${NC}"

    case $DISTRO in
        ubuntu|debian)
            $SUDO apt update && $SUDO apt upgrade -y || return 1
            ;;
        fedora)
            $SUDO dnf upgrade -y || return 1
            ;;
        centos|rhel)
            $SUDO yum update -y || return 1
            ;;
        arch)
            $SUDO pacman -Syu --noconfirm || return 1
            ;;
        *)
            error_exit "Nieobsługiwana dystrybucja"
            ;;
    esac

    log "${GREEN}[INFO] Aktualizacja zakończona${NC}"
    return 0
}

# ===== WERYFIKACJA =====
verify_system() {
    log "${YELLOW}[INFO] Weryfikacja systemu...${NC}"

    systemctl is-system-running &>/dev/null || error_exit "System nie jest w pełni sprawny"

    df -h / | awk 'NR==2 {print $5}' | grep -qE '9[0-9]%|100%' && \
        error_exit "Za mało miejsca na dysku"

    log "${GREEN}[INFO] System działa poprawnie${NC}"
}

# ===== ROLLBACK =====
rollback() {
    log "${YELLOW}[INFO] Przywracanie systemu...${NC}"

    if [ -f "$BASE_BACKUP_DIR/last_backup_path" ]; then
        BACKUP_DIR=$(cat "$BASE_BACKUP_DIR/last_backup_path")
    else
        BACKUP_DIR=$(ls -td $BASE_BACKUP_DIR/sys_update_* 2>/dev/null | head -n 1)
    fi

    if [ -z "$BACKUP_DIR" ] || [ ! -d "$BACKUP_DIR" ]; then
        error_exit "Brak backupu"
    fi

    log "${YELLOW}[INFO] Używany backup: $BACKUP_DIR${NC}"

    $SUDO tar -xzf "$BACKUP_DIR/etc_backup.tar.gz" -C / 2>>"$LOG_FILE"

    log "${YELLOW}[WARNING] Przywracanie pakietów może być niepełne${NC}"

    case $DISTRO in
        ubuntu|debian)
            $SUDO dpkg --set-selections < "$BACKUP_DIR/packages.list"
            $SUDO apt-get dselect-upgrade -y
            ;;
        fedora)
            $SUDO dnf install -y $(cat "$BACKUP_DIR/packages.list") 2>/dev/null
            ;;
        centos|rhel)
            $SUDO yum install -y $(cat "$BACKUP_DIR/packages.list") 2>/dev/null
            ;;
        arch)
            $SUDO pacman -S --noconfirm - < "$BACKUP_DIR/packages.list"
            ;;
    esac

    log "${GREEN}[INFO] Rollback zakończony${NC}"
}

# ===== LTS UPGRADE =====
upgrade_lts() {

    case $DISTRO in
        ubuntu|debian)
            ;;
        *)
            error_exit "LTS upgrade tylko Ubuntu/Debian"
            ;;
    esac

    log "${RED}[WARNING] FULL DIST UPGRADE${NC}"
    echo "Może rozwalić system."

    echo "Wpisz YES:"
    read c1
    [ "$c1" != "YES" ] && return

    echo "Wpisz I_UNDERSTAND:"
    read c2
    [ "$c2" != "I_UNDERSTAND" ] && return

    log "${YELLOW}Backup przed upgrade...${NC}"
    create_backup

    log "${YELLOW}Upgrade start...${NC}"

    $SUDO apt update
    $SUDO apt upgrade -y
    $SUDO apt dist-upgrade -y

    echo ""
    echo "1 - normalny upgrade (LTS only)"
    echo "2 - wymuś upgrade DEV (-d)"
    read mode

    if [ "$mode" == "2" ]; then
        log "${RED}[WARNING] TRYB DEV${NC}"
        $SUDO do-release-upgrade -d
    else
        $SUDO do-release-upgrade
    fi

    log "${GREEN}[INFO] Upgrade zakończony${NC}"
}

# ===== MENU =====
show_menu() {
    echo "=============================="
    echo "  System Update Manager"
    echo "=============================="
    echo "1. Backup systemu"
    echo "2. Aktualizacja"
    echo "3. Full proces"
    echo "4. Rollback"
    echo "5. Wyjście"
    echo "6. Upgrade LTS"
    echo -n "Opcja: "
}

# ===== MAIN =====
detect_distro

while true; do
    show_menu
    read c

    case $c in
        1) create_backup ;;
        2) update_system && verify_system ;;
        3)
            create_backup
            update_system && verify_system || rollback
            ;;
        4) rollback ;;
        5) exit 0 ;;
        6) upgrade_lts ;;
        *) echo "Zła opcja" ;;
    esac
done