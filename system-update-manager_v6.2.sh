#!/usr/bin/env bash
set -Eeuo pipefail

APP="sys_manager"
VERSION="6.2"

AUTO_MODE=0
YES_MODE=0
DRY_RUN=0
COMMAND="menu"

for arg in "$@"; do
    case "$arg" in
        --auto) AUTO_MODE=1; COMMAND="full" ;;
        --yes|-y) YES_MODE=1 ;;
        --dry-run) DRY_RUN=1 ;;
        snapshot|backup|update|full|rollback|status|menu|release-upgrade|dist-upgrade|deps)
            COMMAND="$arg"
            ;;
        --help|-h)
            echo "System Update Manager v${VERSION}"
            echo "Usage: sudo ./system-update-manager_v6.2.sh [command] [options]"
            echo ""
            echo "Commands:"
            echo "  menu              Interactive menu"
            echo "  deps              Install/check dependencies"
            echo "  snapshot          Create snapshot / backup"
            echo "  update            Update packages only"
            echo "  full              Backup/snapshot + update"
            echo "  release-upgrade   Distribution release upgrade"
            echo "  rollback          Rollback helper"
            echo "  status            Show status"
            echo ""
            echo "Options:"
            echo "  --auto            Run full safe update and exit"
            echo "  --yes, -y         Auto-confirm normal prompts"
            echo "  --dry-run         Show commands without executing"
            exit 0
            ;;
        *) echo "Unknown option: $arg"; exit 1 ;;
    esac
done

if [[ "${EUID}" -ne 0 ]]; then
    SUDO="sudo"
else
    SUDO=""
fi

if [[ -w "/var/log" ]]; then
    BASE="/var/backups/${APP}"
    LOG="/var/log/${APP}.log"
    AUDIT="/var/log/${APP}_audit.log"
else
    BASE="${HOME}/${APP}"
    LOG="${HOME}/${APP}.log"
    AUDIT="${HOME}/${APP}_audit.log"
fi

TS="$(date +%F_%H-%M-%S)"
SNAP="snap_${TS}"
BACKUP="${BASE}/backup_${TS}"

log() {
    echo -e "$1"
    mkdir -p "$(dirname "$LOG")" 2>/dev/null || true
    echo "$(date '+%F %T') | $1" >> "$LOG" 2>/dev/null || true
}

audit() {
    mkdir -p "$(dirname "$AUDIT")" 2>/dev/null || true
    echo "$(date '+%F %T') | user=${SUDO_USER:-$USER} | $1" >> "$AUDIT" 2>/dev/null || true
}

fail() {
    log "[ERROR] $1"
    audit "FAIL: $1"
    exit 1
}

run() {
    if [[ "$DRY_RUN" -eq 1 ]]; then
        log "[DRY-RUN] $*"
    else
        "$@"
    fi
}

confirm() {
    local msg="$1"

    if [[ "$YES_MODE" -eq 1 || "$AUTO_MODE" -eq 1 ]]; then
        return 0
    fi

    echo ""
    echo "$msg"
    echo -n "Type YES to continue: "
    read -r answer
    [[ "$answer" == "YES" ]]
}

danger_confirm() {
    local msg="$1"

    echo ""
    echo "===== DANGEROUS OPERATION ====="
    echo "$msg"
    echo ""
    echo "This operation can make the system unbootable."
    echo "Make sure you have external backups or console access."
    echo ""
    echo -n "Type UPGRADE to continue: "
    read -r answer
    [[ "$answer" == "UPGRADE" ]]
}

need_cmd() {
    command -v "$1" >/dev/null 2>&1 || fail "Missing required command: $1"
}

prepare_dirs() {
    if [[ "$DRY_RUN" -eq 1 ]]; then
        mkdir -p "$(dirname "$LOG")" "$(dirname "$AUDIT")" 2>/dev/null || true
        touch "$LOG" "$AUDIT" 2>/dev/null || true
    else
        $SUDO mkdir -p "$BASE"
        $SUDO touch "$LOG" "$AUDIT" 2>/dev/null || true
    fi
}

detect_distro() {
    [[ -r /etc/os-release ]] || fail "Cannot read /etc/os-release"

    # shellcheck disable=SC1091
    . /etc/os-release

    DISTRO="${ID:-unknown}"
    DISTRO_LIKE="${ID_LIKE:-}"
    DISTRO_NAME="${PRETTY_NAME:-unknown}"

    log "[INFO] Distro: $DISTRO_NAME"
    log "[INFO] ID: $DISTRO"
    log "[INFO] Like: ${DISTRO_LIKE:-none}"
}

detect_fs() {
    ROOT_FS="$(findmnt -n -o FSTYPE /)"
    ROOT_SRC="$(findmnt -n -o SOURCE /)"

    MODE="RSYNC"

    if [[ "$ROOT_FS" == "btrfs" ]] && command -v btrfs >/dev/null 2>&1; then
        MODE="BTRFS"
    elif command -v lvs >/dev/null 2>&1 && lvs "$ROOT_SRC" >/dev/null 2>&1; then
        MODE="LVM"
    fi

    log "[INFO] Root FS: $ROOT_FS"
    log "[INFO] Root source: $ROOT_SRC"
    log "[INFO] Backup mode: $MODE"
}

install_dependencies() {
    log "[INFO] Checking dependencies"

    local missing=()

    command -v rsync >/dev/null 2>&1 || missing+=("rsync")

    if [[ "${ROOT_FS:-}" == "btrfs" ]]; then
        command -v btrfs >/dev/null 2>&1 || missing+=("btrfs-tools")
    fi

    if [[ "${MODE:-}" == "LVM" ]]; then
        command -v lvs >/dev/null 2>&1 || missing+=("lvm-tools")
    fi

    if [[ "${#missing[@]}" -eq 0 ]]; then
        log "[OK] Required dependencies are installed"
        return 0
    fi

    log "[WARN] Missing dependencies: ${missing[*]}"

    confirm "Install missing dependencies automatically?" || {
        fail "Missing required dependencies: ${missing[*]}"
    }

    case "$DISTRO" in
        ubuntu|debian)
            run $SUDO apt-get update

            command -v rsync >/dev/null 2>&1 || run $SUDO apt-get install -y rsync

            if [[ "${ROOT_FS:-}" == "btrfs" ]] && ! command -v btrfs >/dev/null 2>&1; then
                run $SUDO apt-get install -y btrfs-progs
            fi

            if [[ "${MODE:-}" == "LVM" ]] && ! command -v lvs >/dev/null 2>&1; then
                run $SUDO apt-get install -y lvm2
            fi
            ;;

        fedora)
            command -v rsync >/dev/null 2>&1 || run $SUDO dnf install -y rsync

            if [[ "${ROOT_FS:-}" == "btrfs" ]] && ! command -v btrfs >/dev/null 2>&1; then
                run $SUDO dnf install -y btrfs-progs
            fi

            if [[ "${MODE:-}" == "LVM" ]] && ! command -v lvs >/dev/null 2>&1; then
                run $SUDO dnf install -y lvm2
            fi
            ;;

        rhel|centos|rocky|almalinux)
            local PM="yum"
            command -v dnf >/dev/null 2>&1 && PM="dnf"

            command -v rsync >/dev/null 2>&1 || run $SUDO "$PM" install -y rsync

            if [[ "${ROOT_FS:-}" == "btrfs" ]] && ! command -v btrfs >/dev/null 2>&1; then
                run $SUDO "$PM" install -y btrfs-progs || true
            fi

            if [[ "${MODE:-}" == "LVM" ]] && ! command -v lvs >/dev/null 2>&1; then
                run $SUDO "$PM" install -y lvm2
            fi
            ;;

        arch|endeavouros|manjaro)
            command -v rsync >/dev/null 2>&1 || run $SUDO pacman -Sy --noconfirm rsync

            if [[ "${ROOT_FS:-}" == "btrfs" ]] && ! command -v btrfs >/dev/null 2>&1; then
                run $SUDO pacman -Sy --noconfirm btrfs-progs
            fi

            if [[ "${MODE:-}" == "LVM" ]] && ! command -v lvs >/dev/null 2>&1; then
                run $SUDO pacman -Sy --noconfirm lvm2
            fi
            ;;

        opensuse*|sles)
            command -v rsync >/dev/null 2>&1 || run $SUDO zypper --non-interactive install rsync

            if [[ "${ROOT_FS:-}" == "btrfs" ]] && ! command -v btrfs >/dev/null 2>&1; then
                run $SUDO zypper --non-interactive install btrfsprogs
            fi

            if [[ "${MODE:-}" == "LVM" ]] && ! command -v lvs >/dev/null 2>&1; then
                run $SUDO zypper --non-interactive install lvm2
            fi
            ;;

        *)
            fail "Cannot auto-install dependencies on unsupported distro: $DISTRO"
            ;;
    esac

    log "[OK] Dependency installation completed"
    audit "DEPENDENCIES:INSTALLED"
}

precheck() {
    log "[INFO] Running precheck"

    local used
    used="$(df / | awk 'NR==2{print $5}' | tr -d '%')"
    [[ "$used" -gt 90 ]] && fail "Disk usage on / is above 90%"

    local avail_ram
    avail_ram="$(free -m | awk '/Mem:/ {print $7}')"
    [[ "$avail_ram" -lt 200 ]] && log "[WARN] Available RAM below 200 MB"

    if command -v systemctl >/dev/null 2>&1; then
        systemctl is-system-running >/dev/null 2>&1 || log "[WARN] systemd reports system not fully healthy"
    fi

    audit "PRECHECK:OK"
}

backup_package_state() {
    local out="${BACKUP}/package_state"
    run $SUDO mkdir -p "$out"

    if command -v dpkg >/dev/null 2>&1; then
        run bash -c "dpkg --get-selections > '${out}/dpkg-selections.txt'"
        run bash -c "apt-mark showmanual > '${out}/apt-manual.txt' 2>/dev/null || true"
    fi

    if command -v rpm >/dev/null 2>&1; then
        run bash -c "rpm -qa > '${out}/rpm-packages.txt'"
    fi

    if command -v pacman >/dev/null 2>&1; then
        run bash -c "pacman -Qqe > '${out}/pacman-explicit.txt'"
        run bash -c "pacman -Qq > '${out}/pacman-all.txt'"
    fi

    if command -v zypper >/dev/null 2>&1; then
        run bash -c "zypper se --installed-only > '${out}/zypper-installed.txt' 2>/dev/null || true"
    fi

    log "[INFO] Package state saved"
}

rsync_backup() {
    install_dependencies
    need_cmd rsync

    log "[INFO] Creating rsync backup: $BACKUP"

    run $SUDO mkdir -p "$BACKUP"
    run $SUDO rsync -aAX --numeric-ids /etc/ "${BACKUP}/etc/"
    run $SUDO rsync -aAX --numeric-ids /root/ "${BACKUP}/root/" 2>/dev/null || true

    if [[ -d /usr/local ]]; then
        run $SUDO rsync -aAX --numeric-ids /usr/local/ "${BACKUP}/usr_local/" 2>/dev/null || true
    fi

    backup_package_state

    echo "$BACKUP" | run $SUDO tee "${BASE}/LAST_RSYNC_BACKUP" >/dev/null

    log "[OK] Rsync backup created"
    audit "BACKUP:RSYNC:${BACKUP}"
}

rsync_rollback() {
    install_dependencies
    need_cmd rsync

    local last
    last="$(cat "${BASE}/LAST_RSYNC_BACKUP" 2>/dev/null || true)"
    [[ -n "$last" && -d "$last" ]] || fail "No valid rsync backup found"

    log "[WARN] Rsync rollback restores /etc, /root and /usr/local only"
    log "[WARN] It does not downgrade packages automatically"

    confirm "Restore configuration backup from: $last ?" || {
        log "[INFO] Rollback cancelled"
        return 0
    }

    run $SUDO rsync -aAX --delete "${last}/etc/" /etc/

    if [[ -d "${last}/root" ]]; then
        run $SUDO rsync -aAX --delete "${last}/root/" /root/
    fi

    if [[ -d "${last}/usr_local" ]]; then
        run $SUDO rsync -aAX --delete "${last}/usr_local/" /usr/local/
    fi

    log "[OK] Rsync rollback completed"
    audit "ROLLBACK:RSYNC:${last}"
}

btrfs_snapshot() {
    install_dependencies
    need_cmd btrfs

    local snap_dir="/.snapshots"
    local target="${snap_dir}/${SNAP}"

    log "[INFO] Creating Btrfs read-only snapshot: $target"

    run $SUDO mkdir -p "$snap_dir"
    run $SUDO btrfs subvolume snapshot -r / "$target"

    echo "$target" | run $SUDO tee "${BASE}/LAST_BTRFS_SNAPSHOT" >/dev/null

    log "[OK] Btrfs snapshot created"
    audit "SNAPSHOT:BTRFS:${target}"
}

btrfs_rollback() {
    local last
    last="$(cat "${BASE}/LAST_BTRFS_SNAPSHOT" 2>/dev/null || true)"
    [[ -n "$last" && -d "$last" ]] || fail "No valid Btrfs snapshot found"

    log "[WARN] Automatic Btrfs root rollback is intentionally disabled"
    log "[INFO] Last snapshot: $last"

    echo ""
    echo "Useful commands:"
    echo "  sudo btrfs subvolume list /"
    echo "  sudo btrfs subvolume show '$last'"
    echo ""
    echo "Use distro-native tooling where possible:"
    echo "  openSUSE: snapper"
    echo "  Fedora/Bazzite/Silverblue: rpm-ostree rollback if applicable"
    echo "  Ubuntu/Debian Btrfs: verify subvolume layout manually"

    audit "ROLLBACK:BTRFS:MANUAL_REQUIRED:${last}"
}

lvm_snapshot() {
    install_dependencies
    need_cmd lvcreate
    need_cmd lvs
    need_cmd vgs

    local origin="$ROOT_SRC"

    lvs "$origin" >/dev/null 2>&1 || fail "Root device is not a valid LVM logical volume: $origin"

    local vg
    vg="$(lvs --noheadings -o vg_name "$origin" | xargs)"
    [[ -n "$vg" ]] || fail "Cannot detect VG for root LV"

    local free_mb
    free_mb="$(vgs --noheadings --units m --nosuffix -o vg_free "$vg" | awk '{print int($1)}')"

    local size_mb=$(( free_mb / 4 ))

    if [[ "$size_mb" -lt 1024 ]]; then
        fail "Not enough free space in VG for safe LVM snapshot."
    fi

    [[ "$size_mb" -gt 8192 ]] && size_mb=8192

    log "[INFO] Creating LVM snapshot ${SNAP}, size ${size_mb}M, origin ${origin}"

    run $SUDO lvcreate -L "${size_mb}M" -s -n "$SNAP" "$origin"

    echo "$origin|$SNAP" | run $SUDO tee "${BASE}/LAST_LVM_SNAPSHOT" >/dev/null

    log "[OK] LVM snapshot created"
    audit "SNAPSHOT:LVM:${origin}:${SNAP}"
}

lvm_rollback() {
    install_dependencies
    need_cmd lvconvert
    need_cmd lvs

    local entry origin snap_name vg snap_path
    entry="$(cat "${BASE}/LAST_LVM_SNAPSHOT" 2>/dev/null || true)"
    [[ -n "$entry" ]] || fail "No LVM snapshot record found"

    origin="${entry%%|*}"
    snap_name="${entry##*|}"

    vg="$(lvs --noheadings -o vg_name "$origin" | xargs)"
    [[ -n "$vg" ]] || fail "Cannot detect VG for origin: $origin"

    snap_path="/dev/${vg}/${snap_name}"
    [[ -e "$snap_path" ]] || fail "Snapshot LV does not exist: $snap_path"

    log "[WARN] LVM rollback will merge snapshot and requires reboot"
    log "[WARN] Origin: $origin"
    log "[WARN] Snapshot: $snap_path"

    confirm "Merge LVM snapshot and reboot?" || {
        log "[INFO] Rollback cancelled"
        return 0
    }

    run $SUDO lvconvert --merge "$snap_path"
    audit "ROLLBACK:LVM:${snap_path}"

    if [[ "$DRY_RUN" -eq 0 ]]; then
        log "[INFO] Rebooting"
        $SUDO reboot
    fi
}

snapshot() {
    prepare_dirs

    case "$MODE" in
        BTRFS) btrfs_snapshot ;;
        LVM) lvm_snapshot ;;
        RSYNC) rsync_backup ;;
        *) fail "Unknown backup mode: $MODE" ;;
    esac
}

rollback() {
    prepare_dirs

    case "$MODE" in
        BTRFS) btrfs_rollback ;;
        LVM) lvm_rollback ;;
        RSYNC) rsync_rollback ;;
        *) fail "Unknown rollback mode: $MODE" ;;
    esac
}

update_system() {
    log "[INFO] Starting system update"

    case "$DISTRO" in
        ubuntu|debian)
            need_cmd apt-get
            run $SUDO apt-get update
            run $SUDO apt-get -y upgrade
            ;;
        fedora)
            need_cmd dnf
            run $SUDO dnf -y upgrade
            ;;
        rhel|centos|rocky|almalinux)
            if command -v dnf >/dev/null 2>&1; then
                run $SUDO dnf -y update
            else
                need_cmd yum
                run $SUDO yum -y update
            fi
            ;;
        arch|endeavouros|manjaro)
            need_cmd pacman
            run $SUDO pacman -Syu --noconfirm
            ;;
        opensuse*|sles)
            need_cmd zypper
            run $SUDO zypper --non-interactive update
            ;;
        *)
            fail "Unsupported distro: $DISTRO"
            ;;
    esac

    log "[OK] Update completed"
    audit "UPDATE:OK:${DISTRO}"
}

release_upgrade() {
    prepare_dirs
    precheck

    log "[WARN] Distribution release upgrade requested"
    audit "RELEASE_UPGRADE:REQUESTED:${DISTRO}"

    echo ""
    echo "Release upgrade is a major operation."
    echo "A backup/snapshot will be created before continuing."

    confirm "Create backup/snapshot before release upgrade?" || {
        log "[INFO] Release upgrade cancelled before snapshot"
        return 0
    }

    snapshot

    case "$DISTRO" in
        ubuntu)
            need_cmd do-release-upgrade

            echo ""
            echo "===== Ubuntu Release Upgrade ====="
            echo "1) Stable upgrade"
            echo "2) Development upgrade (-d)"
            echo "3) Cancel"
            echo -n "> "
            read -r relopt

            case "$relopt" in
                1)
                    danger_confirm "Stable Ubuntu release upgrade will be started." || return 0
                    run $SUDO do-release-upgrade
                    ;;
                2)
                    danger_confirm "Development Ubuntu upgrade with -d will be started." || return 0
                    run $SUDO do-release-upgrade -d
                    ;;
                *)
                    log "[INFO] Release upgrade cancelled"
                    return 0
                    ;;
            esac
            ;;

        fedora)
            need_cmd dnf

            if ! dnf system-upgrade --help >/dev/null 2>&1; then
                run $SUDO dnf -y install dnf-plugin-system-upgrade
            fi

            echo ""
            echo "===== Fedora System Upgrade ====="
            echo -n "Target Fedora version: "
            read -r target_version

            [[ "$target_version" =~ ^[0-9]+$ ]] || fail "Invalid Fedora version"

            danger_confirm "Fedora system-upgrade to version ${target_version} will be started." || return 0

            run $SUDO dnf system-upgrade download --releasever="$target_version" -y

            confirm "Download completed. Reboot into upgrade now?" || return 0

            run $SUDO dnf system-upgrade reboot
            ;;

        debian)
            fail "Debian release upgrade intentionally unsupported"
            ;;

        arch|endeavouros|manjaro)
            log "[INFO] Arch-based systems are rolling release. Use normal update."
            ;;

        opensuse*|sles)
            fail "openSUSE/SLES release upgrade intentionally unsupported"
            ;;

        rhel|centos|rocky|almalinux)
            fail "Enterprise Linux release upgrade intentionally unsupported"
            ;;

        *)
            fail "Release upgrade not supported for distro: $DISTRO"
            ;;
    esac

    audit "RELEASE_UPGRADE:STARTED:${DISTRO}"
}

full() {
    prepare_dirs
    precheck
    snapshot

    if update_system; then
        log "[OK] Full safe update completed"
        audit "FULL:OK"
    else
        log "[FAIL] Update failed"
        audit "FULL:UPDATE_FAILED"
        exit 1
    fi
}

status() {
    echo ""
    echo "===== ${APP} v${VERSION} status ====="
    echo "Distro: ${DISTRO_NAME}"
    echo "ID: ${DISTRO}"
    echo "Root FS: ${ROOT_FS}"
    echo "Root source: ${ROOT_SRC}"
    echo "Mode: ${MODE}"
    echo "Base: ${BASE}"
    echo "Log: ${LOG}"
    echo "Audit: ${AUDIT}"

    echo ""
    echo "Last rsync backup:"
    cat "${BASE}/LAST_RSYNC_BACKUP" 2>/dev/null || echo "none"

    echo ""
    echo "Last Btrfs snapshot:"
    cat "${BASE}/LAST_BTRFS_SNAPSHOT" 2>/dev/null || echo "none"

    echo ""
    echo "Last LVM snapshot:"
    cat "${BASE}/LAST_LVM_SNAPSHOT" 2>/dev/null || echo "none"
}

menu() {
    while true; do
        echo ""
        echo "===== System Update Manager v${VERSION} ====="
        echo "Author: Błażej Wiecha"
        echo ""
        echo "1) Install/check dependencies"
        echo "2) Snapshot / backup"
        echo "3) Update only"
        echo "4) Full safe update"
        echo "5) Release upgrade / dist upgrade"
        echo "6) Rollback"
        echo "7) Status"
        echo "8) Exit"
        echo -n "> "

        read -r opt

        case "$opt" in
            1) install_dependencies ;;
            2) snapshot ;;
            3) update_system ;;
            4) full ;;
            5) release_upgrade ;;
            6) rollback ;;
            7) status ;;
            8) exit 0 ;;
            *) echo "Bad option" ;;
        esac
    done
}

prepare_dirs
detect_distro
detect_fs

case "$COMMAND" in
    deps) install_dependencies ;;
    snapshot|backup) snapshot ;;
    update) update_system ;;
    full) full ;;
    rollback) rollback ;;
    release-upgrade|dist-upgrade) release_upgrade ;;
    status) status ;;
    menu) menu ;;
    *) fail "Unknown command: $COMMAND" ;;
esac