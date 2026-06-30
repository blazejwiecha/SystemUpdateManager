#!/bin/bash

# ==========================================================
#  System Update Manager v3.0
#  Author: Błażej Wiecha
# ==========================================================

# ===== ROOT HANDLING =====
if [ "$EUID" -ne 0 ]; then
    SUDO="sudo"
else
    SUDO=""
fi

# ===== CONFIG =====
BASE="/var/backups/sys_manager"
LOG="/var/log/sys_manager.log"

if [ ! -w "/var/log" ]; then
    BASE="$HOME/sys_manager"
    LOG="$HOME/sys_manager.log"
fi

TS=$(date +%F_%H-%M-%S)
BACKUP="$BASE/backup_$TS"

# ===== COLORS =====
G="\e[32m"; R="\e[31m"; Y="\e[33m"; N="\e[0m"

# ===== LOG =====
log() {
    echo -e "$1"
    echo "$(date) | $1" >> "$LOG" 2>/dev/null
}

fail() {
    log "${R}[ERROR] $1${N}"
    exit 1
}

# ===== DISTRO =====
detect() {
    . /etc/os-release 2>/dev/null || fail "no os-release"
    DISTRO=$ID
    log "${G}[INFO] $DISTRO${N}"
}

# ===== SANITY =====
check_system() {
    systemctl is-system-running &>/dev/null || \
        log "${Y}[WARN] system not fully running${N}"

    df -h / | awk 'NR==2 {print $5}' | grep -qE '9[0-9]|100' && \
        fail "Disk almost full"
}

# ===== BACKUP =====
backup() {
    log "${Y}[INFO] backup start${N}"

    $SUDO mkdir -p "$BACKUP" || fail "mkdir"

    # CORE DATA
    $SUDO rsync -a /etc "$BACKUP/"
    $SUDO rsync -a /var/spool/cron "$BACKUP/" 2>/dev/null
    $SUDO rsync -a /home "$BACKUP/home" 2>/dev/null

    # packages
    case $DISTRO in
        ubuntu|debian)
            $SUDO dpkg --get-selections > "$BACKUP/pkg.list"
            ;;
        fedora|rhel|centos)
            $SUDO rpm -qa > "$BACKUP/pkg.list"
            ;;
        arch)
            $SUDO pacman -Qqe > "$BACKUP/pkg.list"
            ;;
    esac

    # metadata
    uname -a > "$BACKUP/system.info"
    date > "$BACKUP/date.info"

    # archive + hash
    $SUDO tar -czf "$BACKUP.tar.gz" -C "$BASE" "$(basename $BACKUP)"
    sha256sum "$BACKUP.tar.gz" > "$BACKUP.sha256"

    echo "$BACKUP" | $SUDO tee "$BASE/LAST" > /dev/null

    log "${G}[OK] backup done${N}"
}

# ===== UPDATE =====
update() {
    log "${Y}update...${N}"

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
        *) fail "unsupported distro"
    esac
}

# ===== VERIFY =====
verify() {
    check_system
    log "${G}[OK] system stable${N}"
}

# ===== ROLLBACK =====
rollback() {
    log "${Y}rollback...${N}"

    LAST=$(cat "$BASE/LAST" 2>/dev/null)

    [ -z "$LAST" ] && fail "no backup"

    ARCHIVE="$LAST.tar.gz"
    HASH="$LAST.sha256"

    [ ! -f "$ARCHIVE" ] && fail "no archive"

    if [ -f "$HASH" ]; then
        sha256sum -c "$HASH" --status || fail "corrupted backup"
    fi

    log "${Y}restoring etc${N}"
    $SUDO rsync -a "$LAST/etc/" /etc/

    log "${Y}restoring packages${N}"

    case $DISTRO in
        ubuntu|debian)
            $SUDO dpkg --set-selections < "$LAST/pkg.list"
            $SUDO apt-get dselect-upgrade -y
            ;;
        fedora)
            $SUDO dnf install -y $(cat "$LAST/pkg.list") 2>/dev/null
            ;;
        arch)
            $SUDO pacman -S --noconfirm - < "$LAST/pkg.list"
            ;;
    esac

    log "${G}[OK] rollback done${N}"
}

# ===== LTS CHECK =====
check_lts() {
    command -v do-release-upgrade >/dev/null || return 1
    do-release-upgrade -c 2>/dev/null | grep -q "New release"
}

# ===== UPGRADE =====
upgrade() {

    [[ "$DISTRO" != "ubuntu" && "$DISTRO" != "debian" ]] && \
        fail "only Ubuntu/Debian"

    check_lts || log "${Y}no official LTS yet${N}"

    echo "!!! FULL UPGRADE !!!"
    echo "type YES:"
    read A
    [ "$A" != "YES" ] && return

    echo "type I_UNDERSTAND:"
    read B
    [ "$B" != "I_UNDERSTAND" ] && return

    backup

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

    log "${G}upgrade done${N}"
}

# ===== MENU =====
menu() {
    echo ""
    echo "==== System Manager v3.0 ===="
    echo "Author: Błażej Wiecha"
    echo "1 backup"
    echo "2 update"
    echo "3 full(auto)"
    echo "4 rollback"
    echo "5 upgrade LTS"
    echo "6 exit"
    echo -n "> "
}

# ===== MAIN =====
detect

while true; do
    menu
    read o

    case $o in
        1) backup ;;
        2) update && verify ;;
        3)
            backup
            if update; then
                verify || rollback
            else
                rollback
            fi
            ;;
        4) rollback ;;
        5) upgrade ;;
        6) exit 0 ;;
        *) echo "bad" ;;
    esac
done