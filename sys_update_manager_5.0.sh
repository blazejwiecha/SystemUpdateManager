#!/bin/bash

# ==========================================================
#  System Manager v5.0 (Pro / DevSecOps Ready)
#  Author: Błażej Wiecha
# ==========================================================

# ===== FLAGS =====
AUTO_MODE=0
[ "$1" == "--auto" ] && AUTO_MODE=1

# ===== ROOT =====
[ "$EUID" -ne 0 ] && SUDO="sudo" || SUDO=""

# ===== CONFIG =====
BASE="/var/backups/sys_manager"
LOG="/var/log/sys_manager.log"
AUDIT="/var/log/sys_manager_audit.log"

if [ ! -w "/var/log" ]; then
    BASE="$HOME/sys_manager"
    LOG="$HOME/sys_manager.log"
    AUDIT="$HOME/sys_manager_audit.log"
fi

TS=$(date +%F_%H-%M-%S)
SNAP="snap_$TS"
BACKUP="$BASE/backup_$TS"

# ===== LOG =====
log() { echo -e "$1"; echo "$(date)|$1" >> "$LOG"; }
audit() { echo "$(date)|$USER|$1" >> "$AUDIT"; }
fail() { log "[ERROR] $1"; audit "FAIL:$1"; exit 1; }

# ===== DISTRO =====
detect() {
    . /etc/os-release || fail "no os-release"
    DISTRO=$ID
    log "[INFO] Distro: $DISTRO"
}

# ===== SYSTEM CHECK =====
precheck() {
    FREE=$(df / | awk 'NR==2{print $5}' | tr -d '%')
    [ "$FREE" -gt 90 ] && fail "disk usage >90%"

    RAM=$(free -m | awk '/Mem:/ {print $7}')
    [ "$RAM" -lt 200 ] && log "[WARN] low RAM"

    systemctl is-system-running &>/dev/null || \
        log "[WARN] system not fully ready"
}

# ===== FS DETECTION =====
detect_fs() {
    FS=$(findmnt -n -o FSTYPE /)

    if [[ "$FS" == "btrfs" ]]; then
        MODE="BTRFS"
    else
        ROOT_DEV=$(findmnt -n -o SOURCE /)
        if echo "$ROOT_DEV" | grep -q "mapper"; then
            MODE="LVM"
        else
            MODE="RSYNC"
        fi
    fi

    log "[INFO] Mode: $MODE"
}

# ===== BTRFS SNAP =====
btrfs_snap() {
    log "[INFO] Btrfs snapshot"

    $SUDO btrfs subvolume snapshot / /.snapshots/$SNAP || \
        fail "btrfs snapshot fail"

    echo "$SNAP" | $SUDO tee "$BASE/LAST_SNAP" > /dev/null
}

btrfs_rollback() {
    SNAP_NAME=$(cat "$BASE/LAST_SNAP")

    [ -z "$SNAP_NAME" ] && fail "no snapshot"

    log "[WARN] reboot needed"

    $SUDO btrfs subvolume delete /
    $SUDO btrfs subvolume snapshot /.snapshots/$SNAP_NAME /

    $SUDO reboot
}

# ===== LVM SNAP =====
lvm_snap() {
    ROOT_DEV=$(findmnt -n -o SOURCE /)

    SIZE=$(df --output=avail -m / | tail -1)
    SIZE=$((SIZE/4))M

    $SUDO lvcreate -L $SIZE -s -n "$SNAP" "$ROOT_DEV" || \
        fail "lvm snapshot fail"

    echo "$SNAP" | $SUDO tee "$BASE/LAST_SNAP" > /dev/null
}

lvm_rollback() {
    SNAP_NAME=$(cat "$BASE/LAST_SNAP")

    [ -z "$SNAP_NAME" ] && fail "no snapshot"

    echo "TYPE YES TO REBOOT"
    [ "$AUTO_MODE" -ne 1 ] && read X
    [ "$AUTO_MODE" -ne 1 ] && [ "$X" != "YES" ] && return

    VG=$(lvs --noheadings -o vg_name | head -1 | xargs)

    $SUDO lvconvert --merge "/dev/$VG/$SNAP_NAME" || fail "merge fail"

    $SUDO reboot
}

# ===== RSYNC BACKUP =====
rsync_backup() {
    log "[INFO] fallback backup"

    $SUDO mkdir -p "$BACKUP"
    $SUDO rsync -a /etc "$BACKUP/"
    $SUDO rsync -a /home "$BACKUP/home" 2>/dev/null

    echo "$BACKUP" | $SUDO tee "$BASE/LAST" > /dev/null
}

rsync_rollback() {
    LAST=$(cat "$BASE/LAST")
    [ -z "$LAST" ] && fail "no backup"

    $SUDO rsync -a "$LAST/etc/" /etc/
}

# ===== UPDATE =====
update() {
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

# ===== SNAPSHOT SELECTOR =====
snapshot() {
    case $MODE in
        BTRFS) btrfs_snap ;;
        LVM) lvm_snap ;;
        RSYNC) rsync_backup ;;
    esac

    audit "SNAPSHOT:$MODE"
}

rollback() {
    case $MODE in
        BTRFS) btrfs_rollback ;;
        LVM) lvm_rollback ;;
        RSYNC) rsync_rollback ;;
    esac

    audit "ROLLBACK:$MODE"
}

# ===== FULL =====
full() {
    precheck
    snapshot

    if update; then
        log "[OK] update success"
        audit "UPDATE:OK"
    else
        log "[FAIL] update -> rollback"
        audit "UPDATE:FAIL"
        rollback
    fi
}

# ===== MENU =====
menu() {
    echo ""
    echo "===== System Manager v5.0 ====="
    echo "Author: Błażej Wiecha"
    echo "1 Snapshot"
    echo "2 Update"
    echo "3 Full (safe upgrade)"
    echo "4 Rollback"
    echo "5 Exit"
    echo -n "> "
}

# ===== MAIN =====
detect
detect_fs

while true; do

    if [ "$AUTO_MODE" -eq 1 ]; then
        full
        exit 0
    fi

    menu
    read opt

    case $opt in
        1) snapshot ;;
        2) update ;;
        3) full ;;
        4) rollback ;;
        5) exit 0 ;;
        *) echo "bad" ;;
    esac
done