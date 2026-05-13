#!/bin/bash
#===============================================================================
#
#          FILE: Rep-Dem.sh
#
#         UTILISATION: sudo ./Rep-Dem.sh [--boot|--recommended|--advanced|--boot-info|--analyze|--output <fichier>]
#
#   DESCRIPTION: Outil de réparation boot Linux multi-distro, sans GUI.
#                Équivalent CLI de Boot-Repair (YannUbuntu), maintenu et étendu.
#
#       OPTIONS:
#         --boot          Réparation boot interactive avec confirmations
#         --recommended   Réparation automatique 5 étapes (style Boot-Repair)
#         --advanced      Menu 12 options : disque, purge, chroot, GRUB config, RAID, EFI...
#         --boot-info     Génère un rapport Boot-Info structuré + upload en ligne optionnel
#         --analyze       Rapport brut système en lecture seule (stdout)
#         --output FILE   Exporte le rapport brut vers FILE
#         --help          Affiche l'aide complète
#         --version       Affiche la version
#
#  REQUIREMENTS: Root privileges, bash 4.0+, grub-install ou grub2-install
#     SUPPORTE:  Debian/Ubuntu/Mint · Fedora/RHEL/Rocky/Alma · Arch/Manjaro
#                openSUSE · Void Linux · Gentoo
#        AUTHOR: ps81frt
#       VERSION: 2.0.0
#       CREATED: 2026
#       LICENSE: MIT
#
#===============================================================================

set -uo pipefail
shopt -s nullglob

#-------------------------------------------------------------------------------
# GLOBAL CONSTANTS & VARIABLES
#-------------------------------------------------------------------------------
SCRIPT_NAME="$(basename "$0")"
readonly SCRIPT_NAME
readonly SCRIPT_VERSION="2.0.0"
BACKUP_DIR="/var/backup/Rep-Dem-$(date +%Y%m%d_%H%M%S)"
readonly BACKUP_DIR
readonly LOG_FILE="/var/log/Rep-Dem.log"
readonly MIN_BASH_VERSION=4

DISTRO=""
DISTRO_FAMILY=""
DISTRO_VERSION=""
PKG_MANAGER=""

declare -A COMPLETED_OPERATIONS
export MODE="interactive"
OUTPUT_FILE=""
ANALYZE_MODE=false
FORCE_DISK=""
export NONINTERACTIVE=false
CHROOT_TARGET=""     # point de montage auto-chroot (utilisé par le trap)
_INSIDE_CHROOT=false # true quand le script tourne à l'intérieur du chroot

#-------------------------------------------------------------------------------
# ANSI COLORS (désactivation auto hors terminal)
#-------------------------------------------------------------------------------

if [[ -t 1 && "${NO_COLOR:-0}" != "1" ]]; then
    readonly RED='\033[0;31m'
    readonly GREEN='\033[0;32m'
    readonly YELLOW='\033[1;33m'
    readonly BLUE='\033[0;34m'
    readonly MAGENTA='\033[0;35m'
    readonly CYAN='\033[0;36m'
    readonly WHITE='\033[1;37m'
    readonly NC='\033[0m'
    readonly BOLD='\033[1m'
    readonly DIM='\033[2m'
else
    readonly RED=''
    readonly GREEN=''
    readonly YELLOW=''
    readonly BLUE=''
    readonly MAGENTA=''
    readonly CYAN=''
    readonly WHITE=''
    readonly NC=''
    readonly BOLD=''
    readonly DIM=''
fi
#-------------------------------------------------------------------------------
# LOGGING FUNCTIONS
#-------------------------------------------------------------------------------
get_timestamp() {
    date '+%Y-%m-%d %H:%M:%S'
}

log_to_file() {
    local level="$1"
    local message="$2"

    if [[ -w "$(dirname "$LOG_FILE")" ]] || [[ -w "$LOG_FILE" ]]; then
        echo "[$(get_timestamp)] [$level] $message" >>"$LOG_FILE" 2>/dev/null
    fi
}

log_info() {
    local message="$1"
    printf "%b%s\n" "${BLUE}[INFO]${NC}" "$message"
    log_to_file "INFO" "$message"
}

log_success() {
    local message="$1"
    printf "%b%s\n" "${GREEN}[SUCCES]${NC}" "$message"
    log_to_file "SUCCÈS" "$message"
}

log_warning() {
    local message="$1"
    printf "%b%s\n" "${YELLOW}[ATTENTION]${NC}" "$message"
    log_to_file "ATTENTION" "$message"
}

log_error() {
    local message="$1"
    printf "%b%s\n" "${RED}[ERREUR]${NC}" "$message" >&2
    log_to_file "ERREUR" "$message"
}

log_debug() {
    local message="$1"
    if [[ "${DEBUG:-false}" == "true" ]]; then
        printf "%b%s\n" "${DIM}[DÉBOGAGE]${NC}" "$message"
        log_to_file "DÉBOGAGE" "$message"
    fi
}

log_header() {
    local title="$1"
    local width=78
    local padding=$(((width - ${#title} - 2) / 2))

    echo ""
    printf "%b\n" "${CYAN}${BOLD}$(printf '═%.0s' $(seq 1 $width))${NC}"
    printf "%b\n" "${CYAN}${BOLD}$(printf ' %.0s' $(seq 1 $padding)) $title $(printf ' %.0s' $(seq 1 $padding))${NC}"
    printf "%b\n" "${CYAN}${BOLD}$(printf '═%.0s' $(seq 1 $width))${NC}"
    echo ""
    log_to_file "HEADER" "=== $title ==="
}

log_subheader() {
    local title="$1"
    echo ""
    printf "%b\n" "${MAGENTA}${BOLD}─── $title ───${NC}"
    echo ""
}

#-------------------------------------------------------------------------------
# UTILITY FUNCTIONS
#-------------------------------------------------------------------------------
command_exists() {
    command -v "$1" &>/dev/null
}

portable_hexdump() {
    local file="$1"
    if command_exists hexdump; then
        hexdump -C -n 512 "$file" 2>/dev/null
    elif command_exists xxd; then
        xxd -g 1 -l 512 "$file" 2>/dev/null
    else
        return 1
    fi
}

prepare_output_file() {
    local file="$1"

    if [[ -z "$file" ]]; then
        return 1
    fi

    local dir
    dir=$(dirname "$file")
    mkdir -p "$dir" 2>/dev/null || true

    if [[ -e "$file" ]]; then
        if ! confirm_action "Le fichier de sortie existe déjà : $file. Voulez-vous le remplacer ?" yes; then
            log_error "Export annulé. Le fichier de sortie existe déjà : $file"
            exit 1
        fi

        local backup
        backup="${file}.bak.$(date +%Y%m%d_%H%M%S)"
        cp -a "$file" "$backup" 2>/dev/null || true
    fi

    : >"$file"
}

report_line() {
    local line="$1"
    printf '%s\n' "$line"
    if [[ -n "$OUTPUT_FILE" ]]; then
        printf '%s\n' "$line" >>"$OUTPUT_FILE"
    fi
}

raw_command_output() {
    local cmd="$1"
    local exe
    exe=$(printf '%s' "$cmd" | awk '{print $1}')

    if ! command_exists "$exe"; then
        echo "indisponible"
        return
    fi

    local output
    if output=$(eval "$cmd" 2>/dev/null); then
        if [[ -n "$output" ]]; then
            printf '%s\n' "$output"
        else
            echo "indisponible"
        fi
    else
        echo "indisponible"
    fi
}

report_section() {
    local title="$1"
    report_line ""
    report_line "================================================================"
    report_line " $title"
    report_line "================================================================"
    report_line ""
}

report_command() {
    local cmd="$1"
    report_line "$cmd"
    local out
    out=$(raw_command_output "$cmd")
    printf '%s\n' "$out"
    if [[ -n "$OUTPUT_FILE" ]]; then
        printf '%s\n' "$out" >>"$OUTPUT_FILE"
    fi
}

is_operation_completed() {
    local operation="$1"
    [[ "${COMPLETED_OPERATIONS[$operation]:-}" == "true" ]]
}

mark_operation_completed() {
    local operation="$1"
    COMPLETED_OPERATIONS[$operation]="true"
}

confirm_action() {
    local prompt="$1"
    local mode="${2:-standard}"
    local response

    echo ""
    printf "%b\n" "${YELLOW}${BOLD}╔══════════════════════════════════════════════════════════════════╗${NC}"
    printf "%b\n" "${YELLOW}${BOLD}║  CONFIRMATION REQUISE                                            ║${NC}"
    printf "%b\n" "${YELLOW}${BOLD}╚══════════════════════════════════════════════════════════════════╝${NC}"
    printf "%b\n" "${WHITE}$prompt${NC}"
    echo ""

    if [[ "$mode" == "strict" ]]; then
        read -r -p "Confirmer en tapant OUI : " response
        if [[ "$response" == "OUI" ]]; then
            log_to_file "CONFIRM" "Utilisateur confirmé avec OUI : $prompt"
            return 0
        fi
        log_info "Opération annulée par l'utilisateur"
        return 1
    fi

    if [[ "$mode" == "yes" ]]; then
        read -r -p "Continuer ? [O/n] : " response
        response="${response:-o}"
    else
        read -r -p "Continuer ? [o/N] : " response
        response="${response:-n}"
    fi

    case "$response" in
    [YyOo] | [YyOo][Ee][Ss])
        log_to_file "CONFIRM" "Utilisateur confirmé : $prompt"
        return 0
        ;;
    *)
        log_info "Opération annulée par l'utilisateur"
        return 1
        ;;
    esac
}

backup_file() {
    local source_file="$1"
    local description="${2:-configuration file}"

    if [[ ! -e "$source_file" ]]; then
        log_debug "Sauvegarde ignorée (fichier introuvable) : $source_file"
        return 1
    fi

    if [[ ! -d "$BACKUP_DIR" ]]; then
        if ! mkdir -p "$BACKUP_DIR"; then
            log_error "Impossible de créer le répertoire de sauvegarde : $BACKUP_DIR"
            return 1
        fi
        chmod 700 "$BACKUP_DIR"
        log_info "Répertoire de sauvegarde créé : $BACKUP_DIR"
    fi

    local backup_subdir
    backup_subdir="$BACKUP_DIR$(dirname "$source_file")"

    mkdir -p "$backup_subdir"

    local backup_path
    backup_path="${backup_subdir}/$(basename "$source_file")"

    if [[ -e "$backup_path" ]]; then
        backup_path="${backup_path}.$(date +%H%M%S)"
    fi

    if cp -a "$source_file" "$backup_path" 2>/dev/null; then
        log_success "Sauvegarde effectuée pour $description : $source_file"
        log_debug "Emplacement de sauvegarde : $backup_path"
        return 0
    else
        log_error "Échec de la sauvegarde : $source_file"
        return 1
    fi
}

restore_backup() {
    local original_file="$1"
    local backup_path="${BACKUP_DIR}${original_file}"

    if [[ ! -f "$backup_path" ]]; then
        log_error "Aucune sauvegarde trouvée pour : $original_file"
        return 1
    fi

    if cp -a "$backup_path" "$original_file"; then
        log_success "Restauré à partir de la sauvegarde : $original_file"
        return 0
    else
        log_error "Échec de la restauration : $original_file"
        return 1
    fi
}

check_bash_version() {
    if [[ "${BASH_VERSINFO[0]}" -lt "$MIN_BASH_VERSION" ]]; then
        log_error "Ce script requiert Bash version $MIN_BASH_VERSION ou supérieure"
        log_error "Version actuelle : ${BASH_VERSION}"
        exit 1
    fi
}

cleanup() {
    local exit_code=$?
    log_debug "Nettoyage appelé avec code de sortie : $exit_code"
    rm -f /tmp/Rep-Dem-*.tmp 2>/dev/null
    exit $exit_code
}

trap '_autochroot_cleanup 2>/dev/null; cleanup' EXIT INT TERM

#-------------------------------------------------------------------------------
# MODULE : VÉRIFICATIONS D'ENVIRONNEMENT
#-------------------------------------------------------------------------------
check_root_privileges() {
    log_info "Vérification des privilèges root..."

    if [[ $EUID -ne 0 ]]; then
        log_error "Ce script doit être exécuté en tant que root"
        echo ""
        echo "Veuillez exécuter avec : sudo $SCRIPT_NAME"
        echo "           ou : su -c './$SCRIPT_NAME'"
        exit 1
    fi

    log_success "Exécution avec les privilèges root (UID : $EUID)"
}

detect_distribution() {
    log_info "Détection de la distribution Linux..."

    if [[ -f /etc/os-release ]]; then
        # shellcheck source=/dev/null
        source /etc/os-release
        DISTRO="${ID:-unknown}"
        DISTRO_VERSION="${VERSION_ID:-unknown}"

        case "${ID,,}" in
        ubuntu | debian | linuxmint | pop | elementary | zorin | kali | raspbian | mx)
            DISTRO_FAMILY="debian"
            PKG_MANAGER="apt"
            ;;
        fedora)
            DISTRO_FAMILY="rhel"
            PKG_MANAGER="dnf"
            ;;
        rhel | centos | rocky | alma | ol | scientific)
            DISTRO_FAMILY="rhel"
            if command_exists dnf; then
                PKG_MANAGER="dnf"
            else
                PKG_MANAGER="yum"
            fi
            ;;
        arch | manjaro | endeavouros | garuda | artix)
            DISTRO_FAMILY="arch"
            PKG_MANAGER="pacman"
            ;;
        opensuse* | sles | suse)
            DISTRO_FAMILY="suse"
            PKG_MANAGER="zypper"
            ;;
        gentoo)
            DISTRO_FAMILY="gentoo"
            PKG_MANAGER="emerge"
            ;;
        void)
            DISTRO_FAMILY="void"
            PKG_MANAGER="xbps"
            ;;
        *)
            DISTRO_FAMILY="unknown"
            if command_exists apt; then
                PKG_MANAGER="apt"
                DISTRO_FAMILY="debian"
            elif command_exists dnf; then
                PKG_MANAGER="dnf"
                DISTRO_FAMILY="rhel"
            elif command_exists yum; then
                PKG_MANAGER="yum"
                DISTRO_FAMILY="rhel"
            elif command_exists pacman; then
                PKG_MANAGER="pacman"
                DISTRO_FAMILY="arch"
            elif command_exists zypper; then
                PKG_MANAGER="zypper"
                DISTRO_FAMILY="suse"
            else
                PKG_MANAGER="unknown"
            fi
            log_warning "Distribution inconnue : ${ID}. Certaines fonctionnalités peuvent ne pas fonctionner."
            ;;
        esac

        log_success "Détecté : ${PRETTY_NAME:-$ID} (Famille : $DISTRO_FAMILY)"
        log_info "Gestionnaire de paquets : $PKG_MANAGER"

    elif [[ -f /etc/debian_version ]]; then
        DISTRO="debian"
        DISTRO_FAMILY="debian"
        PKG_MANAGER="apt"
        DISTRO_VERSION=$(cat /etc/debian_version)
        log_success "Détecté : Debian $DISTRO_VERSION"

    elif [[ -f /etc/redhat-release ]]; then
        DISTRO="rhel"
        DISTRO_FAMILY="rhel"
        PKG_MANAGER=$(command_exists dnf && echo "dnf" || echo "yum")
        DISTRO_VERSION=$(cat /etc/redhat-release)
        log_success "Détecté : $DISTRO_VERSION"

    elif [[ -f /etc/arch-release ]]; then
        DISTRO="arch"
        DISTRO_FAMILY="arch"
        PKG_MANAGER="pacman"
        log_success "Détecté : Arch Linux"

    else
        log_error "Impossible de détecter la distribution Linux"
        log_error "Ce script prend en charge : Debian/Ubuntu, RHEL/Fedora/CentOS, Arch Linux"
        exit 1
    fi
}

detect_init_system() {
    log_info "Détection du système d'initialisation..."

    if [[ -d /run/systemd/system ]]; then
        log_success "Init system: systemd"
        echo "systemd"
    elif [[ -f /sbin/init ]] && /sbin/init --version 2>&1 | grep -q upstart; then
        log_success "Init system: upstart"
        echo "upstart"
    elif [[ -f /etc/init.d/cron ]] && [[ ! -d /run/systemd/system ]]; then
        log_success "Init system: sysvinit"
        echo "sysvinit"
    elif command_exists openrc; then
        log_success "Init system: OpenRC"
        echo "openrc"
    else
        log_warning "Système d'initialisation : inconnu"
        echo "unknown"
    fi
}

detect_boot_mode() {
    log_info "Détection du mode de démarrage..." >&2

    if [[ -d /sys/firmware/efi ]]; then
        log_success "Boot mode: UEFI" >&2
        echo "uefi"
        return
    fi

    if [[ -d /boot/efi/EFI ]] || [[ -d /efi/EFI ]]; then
        log_warning "Firmware EFI inactif, mais un répertoire EFI existe sur le disque" >&2
        log_success "Boot mode présumé : UEFI" >&2
        echo "uefi"
        return
    fi

    log_success "Boot mode: BIOS/Legacy" >&2
    echo "bios"
}

detect_bootloader() {
    local found_grub=false found_sd=false

    if command_exists bootctl && bootctl is-installed 2>/dev/null; then
        found_sd=true
    fi
    for _esp in /boot/efi /efi /boot; do
        if [[ -f "${_esp}/EFI/systemd/systemd-bootx64.efi" ]] ||
            [[ -f "${_esp}/EFI/systemd/systemd-bootia32.efi" ]]; then
            found_sd=true
            break
        fi
    done
    for _esp in /boot/efi /efi /boot; do
        [[ -f "${_esp}/loader/loader.conf" ]] && found_sd=true && break
    done
    if [[ -f /etc/os-release ]]; then
        local _id
        _id=$(grep -m1 '^ID=' /etc/os-release | cut -d= -f2 | tr -d '"')
        [[ "${_id,,}" == "pop" ]] && [[ -d /sys/firmware/efi ]] && found_sd=true
    fi
    if command_exists efibootmgr; then
        efibootmgr -v 2>/dev/null | grep -qi 'systemd\|sd-boot\|systemd-boot' && found_sd=true
    fi

    if [[ -f /boot/grub/grub.cfg ]] || [[ -f /boot/grub2/grub.cfg ]]; then
        found_grub=true
    fi
    if command_exists grub-install || command_exists grub2-install; then
        if [[ "$found_grub" == false ]] && [[ "$found_sd" == true ]]; then
            :
        else
            found_grub=true
        fi
    fi
    if [[ "$found_grub" == false ]] && command_exists efibootmgr; then
        efibootmgr -v 2>/dev/null | grep -qi 'grub' && found_grub=true
    fi

    if [[ "$found_sd" == true && "$found_grub" == true ]]; then
        echo "both"
    elif [[ "$found_sd" == true ]]; then
        echo "systemd-boot"
    elif [[ "$found_grub" == true ]]; then
        echo "grub"
    else
        echo "unknown"
    fi
}

initialize_logging() {
    local log_dir
    log_dir=$(dirname "$LOG_FILE")

    if [[ ! -d "$log_dir" ]]; then
        mkdir -p "$log_dir" 2>/dev/null
    fi

    if touch "$LOG_FILE" 2>/dev/null; then
        chmod 640 "$LOG_FILE"
        log_info "Fichier journal initialisé : $LOG_FILE"
    else
        log_warning "Impossible d'écrire dans le fichier journal : $LOG_FILE"
    fi

    {
        echo ""
        echo "==============================================================================="
        echo "Session started: $(get_timestamp)"
        echo "Version du script : $SCRIPT_VERSION"
        echo "==============================================================================="
    } >>"$LOG_FILE" 2>/dev/null
}

run_environment_checks() {
    log_header "VÉRIFICATIONS D'ENVIRONNEMENT"

    check_bash_version
    check_root_privileges
    detect_distribution
    detect_init_system >/dev/null
    detect_boot_mode >/dev/null
    if [[ "$ANALYZE_MODE" != true ]]; then
        initialize_logging
    fi

    if [[ "$ANALYZE_MODE" != true ]]; then
        log_subheader "Informations système"
        log_info "Kernel : $(uname -r)"
        log_info "Architecture : $(uname -m)"
        log_info "Nom d'hôte : $(hostname)"
        echo ""
        printf "%b\n" "${BOLD}${CYAN}┌─────────────────────────────────────────────────────────────┐${NC}"
        printf "%b  %-60s%b\n" "${BOLD}${CYAN}│${NC}" "Sauvegardes  :  $BACKUP_DIR" "${BOLD}${CYAN}│${NC}"
        printf "%b  %-60s%b\n" "${BOLD}${CYAN}│${NC}" "Journaux     :  $LOG_FILE" "${BOLD}${CYAN}│${NC}"
        printf "%b\n" "${BOLD}${CYAN}└─────────────────────────────────────────────────────────────┘${NC}"
        echo ""
    fi

    mark_operation_completed "environment_checks"
}

generate_raw_report() {
    if [[ -n "$OUTPUT_FILE" ]]; then
        prepare_output_file "$OUTPUT_FILE"
    fi

    report_section "SYSTEM"
    report_command "uname -a"
    report_command "hostname"
    report_command "cat /etc/os-release"
    report_command "uname -m"
    report_command "uname -r"
    report_command "grep -m1 'model name' /proc/cpuinfo"
    report_command "free -h"
    report_command "cat /proc/meminfo | head -5"

    report_section "DISKS"
    report_command "lsblk -f"
    report_command "lsblk -o NAME,FSTYPE,MOUNTPOINT,SIZE,UUID,LABEL,PARTUUID"
    report_command "cat /proc/partitions"
    report_command "fdisk -l"
    report_command "parted -l"
    report_command "blkid"
    report_command "df -hT"
    report_command "findmnt --fstab --raw"
    if command_exists sgdisk; then
        while read -r disk; do
            report_line "sgdisk --print /dev/$disk"
            sgdisk --print "/dev/$disk" 2>/dev/null || report_line "indisponible"
        done < <(lsblk -dn -o NAME 2>/dev/null | grep -vE '^(loop|ram)')
    fi

    report_section "BOOT-INFO"
    report_command "cat /proc/cmdline"
    report_line "--- EFI entries ---"
    report_command "efibootmgr -v"
    report_line "--- EFI partition ---"
    report_command "findmnt -n -o SOURCE,TARGET,FSTYPE,OPTIONS /boot/efi"
    report_command "findmnt -n -o SOURCE,TARGET,FSTYPE,OPTIONS /efi"
    report_command "ls -la /boot/efi/EFI"
    report_command "ls -la /efi/EFI"
    report_line "--- GRUB config ---"
    report_command "cat /boot/grub/grub.cfg"
    report_command "cat /boot/grub2/grub.cfg"
    report_line "--- MBR signature ---"
    if command_exists hexdump || command_exists xxd; then
        while read -r disk; do
            report_line "MBR /dev/$disk:"
            portable_hexdump "/dev/$disk" | tail -4 || report_line "indisponible"
        done < <(lsblk -dn -o NAME 2>/dev/null | grep -vE '^(loop|ram|zram)')
    fi

    report_section "WINDOWS/BCD"
    report_command "lsblk -f | grep -i ntfs"
    report_command "blkid | grep -i ntfs"
    report_command "ls /boot/efi/EFI 2>/dev/null | grep -i Microsoft || echo 'Aucune entrée Microsoft EFI détectée'"
    report_command "ls /efi/EFI 2>/dev/null | grep -i Microsoft || echo 'Aucune entrée Microsoft EFI détectée'"
    report_command "find /boot/efi -maxdepth 4 -type f | grep -i 'bootmgfw.efi\|bcd' 2>/dev/null || echo 'Aucun fichier Windows BCD/bootmgfw.efi trouvé'"
    report_command "find /efi -maxdepth 4 -type f | grep -i 'bootmgfw.efi\|bcd' 2>/dev/null || echo 'Aucun fichier Windows BCD/bootmgfw.efi trouvé'"

    report_section "GRUB"
    report_command "command -v grub-install"
    report_command "command -v grub2-install"
    report_command "grub-install --version"
    report_command "grub2-install --version"
    report_command "cat /etc/default/grub"
    report_command "ls -l /etc/grub.d"
    report_command "findmnt -n -o SOURCE /boot/grub"
    report_command "findmnt -n -o SOURCE /boot/grub2"

    report_section "SECUREBOOT"
    report_command "mokutil --sb-state"
    report_command "sbctl status"
    report_command "dmesg | grep -iE 'secureboot|efi' | tail -20"

    report_section "TPM"
    report_command "ls /sys/class/tpm/"
    report_command "dmesg | grep -i tpm | tail -20"
    report_command "tpm2_getcap -l"

    report_section "LUKS"
    report_command "lsblk -f | grep crypto_LUKS"
    report_command "cat /etc/crypttab"
    report_command "dmsetup table"

    report_section "RAID"
    report_command "cat /proc/mdstat"
    if command_exists mdadm; then
        report_command "mdadm --detail --scan"
        while read -r arr; do
            report_line "mdadm --detail $arr"
            mdadm --detail "$arr" 2>/dev/null || report_line "indisponible"
        done < <(mdadm --detail --scan 2>/dev/null | grep -oE '/dev/md\w+')
    fi

    report_section "FILESYSTEM"
    report_command "pvs"
    report_command "vgs"
    report_command "lvs"
    report_command "dmsetup table"
    report_command "findmnt -n -o SOURCE -t ext2,ext3,ext4 | sort -u | while read -r dev; do tune2fs -l \"$dev\" 2>/dev/null || echo 'indisponible'; done"
    # shellcheck disable=SC2154
    report_command "findmnt -n -t xfs -o TARGET | while read -r mnt; do xfs_info \"$mnt\" 2>/dev/null || echo 'indisponible'; done"
    report_command "btrfs filesystem show"
    report_command "command -v f2fs > /dev/null && findmnt -n -t f2fs -o SOURCE | while read -r dev; do f2fs info \"$dev\" 2>/dev/null || echo 'indisponible'; done"
    report_command "zpool status"
    report_command "lsblk -f | grep -E 'vfat|ntfs'"
    report_command "blkid | grep -E 'TYPE=\"(vfat|ntfs)\"'"
    report_command "lsblk -f | grep crypto_LUKS"
    report_command "cat /etc/crypttab"
    report_command "cat /etc/fstab"
    report_command "command -v genfstab"
    report_command "zramctl --output-all"
    report_command "cat /sys/block/zram*/comp_algorithm"
    report_command "swapon --show"
    report_command "findmnt --fstab --raw"
    report_command "lsblk -o NAME,FSTYPE,MOUNTPOINT,SIZE,UUID"

    report_section "LOGS"
    report_command "journalctl -p 3 -xb --no-pager -n 50"
    report_command "dmesg | tail -50"
}

#-------------------------------------------------------------------------------
# MODULE : RÉPARATION BOOT
#-------------------------------------------------------------------------------
detect_boot_device() {
    local boot_device=""
    local boot_partition=""

    log_info "Détection du périphérique de démarrage..." >&2

    if [[ -d /sys/firmware/efi ]]; then
        boot_partition=$(findmnt -n -o SOURCE /boot/efi 2>/dev/null | head -1)
        if [[ -z "$boot_partition" ]]; then
            boot_partition=$(findmnt -n -o SOURCE /boot 2>/dev/null | head -1)
        fi
    fi

    if [[ -z "$boot_partition" ]]; then
        boot_partition=$(findmnt -n -o SOURCE / 2>/dev/null | head -1)
    fi

    if [[ -n "$boot_partition" ]]; then
        if [[ "$boot_partition" =~ ^/dev/nvme ]]; then
            boot_device=$(echo "$boot_partition" | sed -E 's/p[0-9]+$//')
        elif [[ "$boot_partition" =~ ^/dev/(sd|vd|xvd) ]]; then
            boot_device=$(echo "$boot_partition" | sed -E 's/[0-9]+$//')
        else
            boot_device=$(lsblk -no PKNAME "$boot_partition" 2>/dev/null | head -1)
            [[ -n "$boot_device" ]] && boot_device="/dev/$boot_device"
        fi
    fi

    if [[ -n "$boot_device" ]] && [[ -b "$boot_device" ]]; then
        log_info "Périphérique de démarrage détecté : $boot_device" >&2
        echo "$boot_device"
    else
        log_warning "Impossible de détecter automatiquement le périphérique de démarrage" >&2
        echo ""
    fi
}

backup_grub_configuration() {
    echo ""
    printf "%b\n" "${YELLOW}${BOLD}[BACKUP]${NC} Configuration GRUB → ${BACKUP_DIR}/etc/"

    local grub_files=(
        "/etc/default/grub"
        "/boot/grub/grub.cfg"
        "/boot/grub2/grub.cfg"
    )

    for file in "${grub_files[@]}"; do
        if [[ -f "$file" ]]; then
            backup_file "$file" "Configuration GRUB"
            log_success "  sauvegardé : $file"
        fi
    done

    if [[ -d /etc/grub.d ]]; then
        local backup_target="${BACKUP_DIR}/etc/grub.d"
        mkdir -p "$backup_target"
        cp -a /etc/grub.d/* "$backup_target/" 2>/dev/null
        log_success "  sauvegardé : /etc/grub.d/ → ${backup_target}"
    fi

    printf "%b\n" "${GREEN}${BOLD}[BACKUP OK]${NC} Config GRUB sauvegardée dans : ${BACKUP_DIR}/etc/"
    echo ""
}

backup_partition_tables() {
    local bpt_dir="${BACKUP_DIR}/partition-tables"
    mkdir -p "$bpt_dir"
    echo ""
    printf "%b\n" "${YELLOW}${BOLD}[BACKUP]${NC} Tables de partitions → ${bpt_dir}"
    while read -r disk; do
        local dev="/dev/$disk"
        [[ ! -b "$dev" ]] && continue
        command_exists sgdisk && sgdisk --backup="${bpt_dir}/${disk}-sgdisk.bin" "$dev" 2>/dev/null &&
            log_success "  sgdisk  : ${bpt_dir}/${disk}-sgdisk.bin"
        command_exists sfdisk && sfdisk --dump "$dev" >"${bpt_dir}/${disk}-sfdisk.dump" 2>/dev/null &&
            log_success "  sfdisk  : ${bpt_dir}/${disk}-sfdisk.dump"
        dd if="$dev" of="${bpt_dir}/${disk}-mbr512.bin" bs=512 count=1 status=none 2>/dev/null &&
            log_success "  MBR 512B: ${bpt_dir}/${disk}-mbr512.bin"
    done < <(lsblk -dn -o NAME 2>/dev/null | grep -vE '^(loop|ram)')
    echo ""
    printf "%b\n" "${GREEN}${BOLD}[BACKUP OK]${NC} Tables sauvegardées dans : ${bpt_dir}"
    echo ""
}

#-------------------------------------------------------------------------------
# MODULE : DÉTECTION ARCHITECTURE EFI
#-------------------------------------------------------------------------------
detect_efi_arch() {
    local machine
    machine=$(uname -m)
    case "$machine" in
    x86_64) echo "x86_64-efi" ;;
    aarch64 | arm64) echo "arm64-efi" ;;
    armv7l | armhf) echo "arm-efi" ;;
    riscv64) echo "riscv64-efi" ;;
    loongarch64) echo "loongarch64-efi" ;;
    *)
        log_warning "Architecture inconnue : $machine — utilisation de x86_64-efi par défaut" >&2
        echo "x86_64-efi"
        ;;
    esac
}

detect_efi_binary_name() {
    local machine
    machine=$(uname -m)
    case "$machine" in
    x86_64) echo "grubx64.efi" ;;
    aarch64 | arm64) echo "grubaa64.efi" ;;
    armv7l | armhf) echo "grubarm.efi" ;;
    riscv64) echo "grubriscv64.efi" ;;
    *) echo "grubx64.efi" ;;
    esac
}

detect_shim_packages() {
    local machine
    machine=$(uname -m)
    case "$DISTRO_FAMILY" in
    debian)
        case "$machine" in
        x86_64) echo "shim-signed grub-efi-amd64-signed grub-efi-amd64" ;;
        aarch64 | arm64) echo "shim-signed grub-efi-arm64-signed grub-efi-arm64" ;;
        *) echo "grub-efi-${machine}" ;;
        esac
        ;;
    rhel)
        case "$machine" in
        x86_64) echo "shim-x64 grub2-efi-x64" ;;
        aarch64 | arm64) echo "shim-aa64 grub2-efi-aa64" ;;
        *) echo "grub2-efi" ;;
        esac
        ;;
    arch)
        echo "grub efibootmgr"
        ;;
    *)
        echo ""
        ;;
    esac
}

check_esp_offset_arm() {
    local efi_dir="$1"
    local machine
    machine=$(uname -m)

    [[ "$machine" != "aarch64" && "$machine" != "arm64" ]] && return 0

    local esp_dev
    esp_dev=$(findmnt -n -o SOURCE "$efi_dir" 2>/dev/null | head -1)
    if [[ -z "$esp_dev" || ! -b "$esp_dev" ]]; then
        log_warning "ARM ESP check: périphérique ESP introuvable sur $efi_dir — vérification ignorée"
        return 0
    fi

    local esp_name disk_name
    esp_name=$(basename "$esp_dev")
    disk_name=$(lsblk -no PKNAME "$esp_dev" 2>/dev/null | head -1)
    if [[ -z "$disk_name" ]]; then
        log_warning "ARM ESP check: disque parent de $esp_dev introuvable"
        return 0
    fi

    local start_path="/sys/block/${disk_name}/${esp_name}/start"
    if [[ ! -r "$start_path" ]]; then
        log_warning "ARM ESP check: $start_path illisible — vérification ignorée"
        return 0
    fi

    local start_sectors start_bytes start_mb
    start_sectors=$(cat "$start_path")
    start_bytes=$((start_sectors * 512))
    start_mb=$((start_bytes / 1024 / 1024))

    local limit_mb=256
    local limit_bytes=$((limit_mb * 1024 * 1024))

    if [[ "$start_bytes" -gt "$limit_bytes" ]]; then
        echo ""
        printf "%b\n" "${YELLOW}${BOLD}╔══════════════════════════════════════════════════════════════════╗${NC}"
        printf "%b\n" "${YELLOW}${BOLD}║  AVERTISSEMENT ARM — Contrainte offset ESP (Tianocore / RPi)    ║${NC}"
        printf "%b\n" "${YELLOW}${BOLD}╚══════════════════════════════════════════════════════════════════╝${NC}"
        echo ""
        printf "%b\n" "${YELLOW}  L'ESP ($esp_dev) démarre à ${start_mb} Mo sur /dev/${disk_name}.${NC}"
        printf "%b\n" "${YELLOW}  Certains firmwares ARM (Raspberry Pi Tianocore, Ampere eMAG...)${NC}"
        printf "%b\n" "${YELLOW}  exigent que l'ESP soit dans les ${limit_mb} premiers Mo du disque.${NC}"
        printf "%b\n" "${YELLOW}  Offset actuel : ${start_mb} Mo > ${limit_mb} Mo → risque de non-démarrage.${NC}"
        echo ""
        echo "  Solutions :"
        echo "    1) Repartitionner pour placer l'ESP avant ${limit_mb} Mo"
        echo "       (nécessite un live USB + sauvegarde préalable)"
        echo "    2) Mettre à jour le firmware UEFI (les versions récentes Tianocore"
        echo "       peuvent ne plus avoir cette limite)"
        echo "    3) Continuer — si votre firmware ne souffre pas de cette contrainte"
        echo ""
        if ! confirm_action "Continuer l'installation de GRUB malgré l'offset ESP > ${limit_mb} Mo ?" yes; then
            return 1
        fi
    else
        log_info "ARM ESP check: offset OK — $esp_dev à ${start_mb} Mo sur /dev/${disk_name} (< ${limit_mb} Mo)"
    fi

    return 0
}

reinstall_grub_debian() {
    local boot_device="$1"
    local boot_mode
    boot_mode=$(detect_boot_mode)
    local efi_target
    efi_target=$(detect_efi_arch)

    log_info "Réinstallation de GRUB pour système Debian (cible EFI : $efi_target)..."

    apt-get update -qq

    if [[ "$boot_mode" == "uefi" ]]; then
        log_info "Installation de GRUB pour UEFI..."
        local shim_pkgs
        shim_pkgs=$(detect_shim_packages)
        if [[ -n "$shim_pkgs" ]]; then
            log_info "Paquets UEFI : $shim_pkgs"
            # shellcheck disable=SC2086
            apt-get install --reinstall -y $shim_pkgs 2>&1 | while read -r line; do
                log_debug "$line"
            done
        fi

        local efi_dir="/boot/efi"
        [[ ! -d "$efi_dir/EFI" ]] && efi_dir="/efi"
        if [[ ! -d "$efi_dir" ]]; then
            log_error "Répertoire EFI introuvable"
            return 1
        fi

        check_esp_offset_arm "$efi_dir" || return 1
        grub-install --target="$efi_target" --efi-directory="$efi_dir" \
            --bootloader-id="GRUB" --recheck 2>&1 || {
            log_error "Échec de grub-install (target=$efi_target)"
            return 1
        }
    else
        log_info "Installation de GRUB pour BIOS/Legacy..."
        apt-get install --reinstall -y grub-pc 2>&1 | while read -r line; do
            log_debug "$line"
        done
        grub-install --target=i386-pc --recheck "$boot_device" 2>&1 || {
            log_error "Échec de grub-install BIOS"
            return 1
        }
    fi

    log_info "Regenerating GRUB configuration..."
    update-grub 2>&1 || {
        log_error "Échec de update-grub"
        return 1
    }

    return 0
}

reinstall_grub_rhel() {
    local boot_device="$1"
    local boot_mode
    boot_mode=$(detect_boot_mode)
    local efi_target
    efi_target=$(detect_efi_arch)

    log_info "Réinstallation de GRUB pour système RHEL (cible EFI : $efi_target)..."

    if [[ "$boot_mode" == "uefi" ]]; then
        log_info "Installation de GRUB pour UEFI..."
        local shim_pkgs
        shim_pkgs=$(detect_shim_packages)
        if [[ -n "$shim_pkgs" ]]; then
            log_info "Paquets UEFI : $shim_pkgs"
            # shellcheck disable=SC2086
            $PKG_MANAGER reinstall -y $shim_pkgs 2>&1 | while read -r line; do
                log_debug "$line"
            done
        fi

        local efi_dir="/boot/efi"
        [[ ! -d "$efi_dir" ]] && efi_dir="/efi"

        check_esp_offset_arm "$efi_dir" || return 1
        grub2-install --target="$efi_target" --efi-directory="$efi_dir" \
            --bootloader-id=rhel --recheck 2>&1 || {
            log_error "Échec de grub2-install (target=$efi_target)"
            return 1
        }
    else
        log_info "Installation de GRUB pour BIOS/Legacy..."
        $PKG_MANAGER reinstall -y grub2-pc 2>&1 | while read -r line; do
            log_debug "$line"
        done
        grub2-install --target=i386-pc --recheck "$boot_device" 2>&1 || {
            log_error "Échec de grub2-install BIOS"
            return 1
        }
    fi

    log_info "Regenerating GRUB configuration..."
    grub2-mkconfig -o /boot/grub2/grub.cfg 2>&1 || {
        log_error "Échec de grub2-mkconfig"
        return 1
    }

    return 0
}

reinstall_grub_arch() {
    local boot_device="$1"
    local boot_mode
    boot_mode=$(detect_boot_mode)
    local efi_target
    efi_target=$(detect_efi_arch)

    log_info "Réinstallation de GRUB pour système Arch (cible EFI : $efi_target)..."

    local grub_pkgs
    grub_pkgs=$(detect_shim_packages)
    # shellcheck disable=SC2086
    pacman -S --noconfirm --needed ${grub_pkgs:-grub efibootmgr} 2>&1 | while read -r line; do
        log_debug "$line"
    done

    if [[ "$boot_mode" == "uefi" ]]; then
        log_info "Installation de GRUB pour UEFI..."

        local efi_dir="/boot/efi"
        [[ ! -d "$efi_dir" ]] && efi_dir="/boot"

        check_esp_offset_arm "$efi_dir" || return 1
        grub-install --target="$efi_target" --efi-directory="$efi_dir" --bootloader-id=GRUB --recheck 2>&1 || {
            log_error "Échec de grub-install (target=$efi_target)"
            return 1
        }
    else
        log_info "Installation de GRUB pour BIOS/Legacy..."
        if ! repair_bios_mbr "$boot_device"; then
            return 1
        fi
    fi

    log_info "Regenerating GRUB configuration..."
    grub-mkconfig -o /boot/grub/grub.cfg 2>&1 || {
        log_error "Échec de grub-mkconfig"
        return 1
    }

    return 0
}

#-------------------------------------------------------------------------------
# MODULE : RESTAURATION GPT BINAIRE (sgdisk --load-backup)
#-------------------------------------------------------------------------------
restore_partition_table_sgdisk() {
    local bpt_dir="${BACKUP_DIR}/partition-tables"

    if [[ ! -d "$bpt_dir" ]]; then
        log_error "Aucune sauvegarde sgdisk disponible dans $bpt_dir"
        return 1
    fi

    echo ""
    printf "%b\n" "${CYAN}${BOLD}Sauvegardes sgdisk disponibles :${NC}"
    echo "───────────────────────────────────────────────────────────"
    find "$bpt_dir" -maxdepth 1 -name '*-sgdisk.bin' \
        -printf '  %f  (%s bytes)\n' 2>/dev/null | sort
    echo "───────────────────────────────────────────────────────────"
    echo ""

    read -r -p "Fichier .bin sgdisk à restaurer : " bin_file
    local full_path="${bpt_dir}/${bin_file}"

    if [[ ! -f "$full_path" ]]; then
        log_error "Fichier introuvable : $full_path"
        return 1
    fi

    local suggested_disk
    suggested_disk="/dev/$(basename "$bin_file" | sed 's/-sgdisk\.bin$//')"

    echo ""
    lsblk -d -o NAME,SIZE,TYPE,TRAN,MODEL 2>/dev/null | grep -v loop |
        awk 'NR==1{print "  "$0} NR>1{print "  /dev/"$0}'
    echo ""

    read -r -p "Disque cible (Entrée = $suggested_disk) : " target_disk
    target_disk="${target_disk:-$suggested_disk}"

    if [[ ! -b "$target_disk" ]]; then
        log_error "Périphérique invalide : $target_disk"
        return 1
    fi

    echo ""
    printf "%b\n" "${RED}${BOLD}╔══════════════════════════════════════════════════════════════╗${NC}"
    printf "%b\n" "${RED}${BOLD}║  AVERTISSEMENT CRITIQUE                                      ║${NC}"
    printf "%b\n" "${RED}${BOLD}║                                                              ║${NC}"
    printf "%b\n" "${RED}${BOLD}║  sgdisk --load-backup écrase la table GPT PRINCIPALE         ║${NC}"
    printf "%b\n" "${RED}${BOLD}║  ET DE SAUVEGARDE du disque cible.                           ║${NC}"
    printf "%b\n" "${RED}${BOLD}║  Les données des partitions elles-mêmes ne sont pas          ║${NC}"
    printf "%b\n" "${RED}${BOLD}║  effacées, mais un mauvais disque cible est irrécupérable.  ║${NC}"
    printf "%b\n" "${RED}${BOLD}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    log_info "Source  : $full_path"
    log_info "Cible   : $target_disk"
    echo ""

    if ! confirm_action \
        "Restaurer la table GPT de $full_path sur $target_disk ? Action IRRÉVERSIBLE." strict; then
        return 0
    fi

    local ts
    ts=$(date +%H%M%S)
    local emergency_backup="${bpt_dir}/${target_disk##*/}-sgdisk-pre-restore-${ts}.bin"
    if command_exists sgdisk; then
        sgdisk --backup="$emergency_backup" "$target_disk" 2>/dev/null &&
            log_success "Sauvegarde d'urgence GPT créée : $emergency_backup"
    fi
    dd if="$target_disk" of="${bpt_dir}/${target_disk##*/}-mbr-pre-restore-${ts}.bin" \
        bs=512 count=1 status=none 2>/dev/null &&
        log_success "MBR d'urgence sauvegardé"

    log_info "Restauration GPT via sgdisk --load-backup..."
    sgdisk --load-backup="$full_path" "$target_disk" 2>&1 |
        while read -r line; do log_info "sgdisk: $line"; done
    if [[ ${PIPESTATUS[0]} -eq 0 ]]; then
        log_success "Table GPT restaurée sur $target_disk"

        log_info "Mise à jour des partitions noyau..."
        if command_exists partprobe; then
            partprobe "$target_disk" 2>/dev/null && log_success "partprobe OK"
        elif command_exists blockdev; then
            blockdev --rereadpt "$target_disk" 2>/dev/null && log_success "blockdev --rereadpt OK"
        else
            log_warning "Aucun outil pour recharger la table — redémarrage recommandé"
        fi

        echo ""
        log_info "Table restaurée :"
        sgdisk --print "$target_disk" 2>/dev/null |
            while read -r line; do printf '  %s\n' "$line"; done
        return 0
    else
        log_error "Échec de sgdisk --load-backup"
        log_info "Vous pouvez tenter manuellement : sudo sgdisk --load-backup=\"$full_path\" $target_disk"
        return 1
    fi
}

#-------------------------------------------------------------------------------
# MODULE : SECURE BOOT / MOK ENROLLMENT
#-------------------------------------------------------------------------------
check_secure_boot_status() {
    log_subheader "État Secure Boot"

    local sb_state="inconnu"
    if command_exists mokutil; then
        sb_state=$(mokutil --sb-state 2>/dev/null || echo "indisponible")
        log_info "Secure Boot : $sb_state"
    elif [[ -f /sys/firmware/efi/efivars/SecureBoot-8be4df61-93ca-11d2-aa0d-00e098032b8c ]]; then
        local sb_byte
        sb_byte=$(od -An -j4 -N1 -tu1 \
            /sys/firmware/efi/efivars/SecureBoot-8be4df61-93ca-11d2-aa0d-00e098032b8c \
            2>/dev/null | tr -d ' ')
        [[ "$sb_byte" == "1" ]] && sb_state="enabled" || sb_state="disabled"
        log_info "Secure Boot (efivars) : $sb_state"
    fi

    if command_exists sbctl; then
        log_info "sbctl status :"
        sbctl status 2>/dev/null | while read -r l; do printf '  %s\n' "$l"; done
    fi

    echo "$sb_state"
}

enroll_mok_key() {
    log_header "ENRÔLEMENT CLÉ MOK (Secure Boot)"

    if [[ $(detect_boot_mode) != "uefi" ]]; then
        log_error "Secure Boot nécessite UEFI"
        return 1
    fi

    if ! command_exists mokutil; then
        log_warning "mokutil non disponible — tentative d'installation..."
        install_packages mokutil || {
            log_error "mokutil requis pour la gestion MOK"
            return 1
        }
    fi

    echo ""
    echo "  Options MOK :"
    echo "  1)  Afficher les clés MOK actuelles"
    echo "  2)  Enrôler une clé MOK existante (.der / .cer)"
    echo "  3)  Générer + enrôler une nouvelle paire de clés MOK"
    echo "  4)  Signer manuellement un fichier EFI ou module noyau"
    echo "  5)  Vérifier la signature d'un fichier EFI"
    echo "  6)  Retour"
    echo ""
    read -r -p "Choix [1-6] : " mok_choice

    case "$mok_choice" in
    1)
        echo ""
        mokutil --list-enrolled 2>/dev/null |
            while read -r l; do printf '  %s\n' "$l"; done ||
            log_warning "Aucune clé MOK enrôlée"
        ;;
    2)
        read -r -p "Chemin vers la clé .der ou .cer à enrôler : " mok_cert
        if [[ ! -f "$mok_cert" ]]; then
            log_error "Fichier introuvable : $mok_cert"
            return 1
        fi
        echo ""
        printf "%b\n" "${YELLOW}Un redémarrage sera nécessaire pour finaliser l'enrôlement.${NC}"
        printf "%b\n" "${YELLOW}MokManager demandera la confirmation et le mot de passe.${NC}"
        echo ""
        if confirm_action "Enrôler $mok_cert dans la base MOK ?" yes; then
            mokutil --import "$mok_cert" 2>&1 |
                while read -r l; do log_info "mokutil: $l"; done
            log_success "Clé mise en file d'attente. Redémarrez pour finaliser dans MokManager."
        fi
        ;;
    3)
        local mok_dir="/etc/Rep-Dem/mok"
        mkdir -p "$mok_dir"
        chmod 700 "$mok_dir"

        local mok_key="${mok_dir}/MOK.key"
        local mok_crt="${mok_dir}/MOK.crt"
        local mok_der="${mok_dir}/MOK.der"

        if [[ -f "$mok_key" && -f "$mok_der" ]]; then
            log_info "Clé MOK existante détectée dans $mok_dir"
            if ! confirm_action "Régénérer la paire de clés MOK ? (l'ancienne sera sauvegardée)" yes; then
                read -r -p "Utiliser la clé existante pour l'enrôlement ? [O/n] : " use_existing
                if [[ "${use_existing,,}" != "n" ]]; then
                    mokutil --import "$mok_der" 2>&1 |
                        while read -r l; do log_info "mokutil: $l"; done
                    log_success "Clé existante mise en file d'attente. Redémarrez pour MokManager."
                fi
                return 0
            fi
            local bts
            bts=$(date +%H%M%S)
            cp -a "$mok_key" "${mok_key}.bak.${bts}" 2>/dev/null
            cp -a "$mok_der" "${mok_der}.bak.${bts}" 2>/dev/null
        fi

        if ! command_exists openssl; then
            log_warning "openssl requis — tentative d'installation..."
            install_packages openssl || {
                log_error "openssl requis"
                return 1
            }
        fi

        log_info "Génération d'une paire RSA-2048 + certificat auto-signé..."
        openssl req -new -x509 -newkey rsa:2048 -keyout "$mok_key" \
            -out "$mok_crt" -days 3650 -subj "/CN=Rep-Dem MOK/" \
            -nodes 2>/dev/null || {
            log_error "Échec openssl"
            return 1
        }
        openssl x509 -in "$mok_crt" -outform DER -out "$mok_der" 2>/dev/null || {
            log_error "Conversion DER échouée"
            return 1
        }
        chmod 600 "$mok_key"
        log_success "Clé générée    : $mok_key"
        log_success "Certificat     : $mok_crt"
        log_success "Format DER     : $mok_der"

        mokutil --import "$mok_der" 2>&1 |
            while read -r l; do log_info "mokutil: $l"; done
        echo ""
        printf "%b\n" "${GREEN}Clé MOK mise en file d'attente.${NC}"
        printf "%b\n" "${YELLOW}Au prochain démarrage, MokManager vous demandera de confirmer${NC}"
        printf "%b\n" "${YELLOW}l'enrôlement et de saisir le mot de passe indiqué ci-dessus.${NC}"
        echo ""
        ;;
    4)
        if ! command_exists sbsign && ! command_exists pesign; then
            log_warning "sbsign ou pesign requis — tentative d'installation..."
            install_packages sbsigntool 2>/dev/null ||
                install_packages pesign 2>/dev/null ||
                {
                    log_error "Aucun outil de signature disponible"
                    return 1
                }
        fi

        local mok_key="/etc/Rep-Dem/mok/MOK.key"
        local mok_crt="/etc/Rep-Dem/mok/MOK.crt"

        if [[ ! -f "$mok_key" || ! -f "$mok_crt" ]]; then
            log_error "Clé MOK non générée. Utilisez l'option 3 d'abord."
            return 1
        fi

        read -r -p "Fichier EFI ou module .ko à signer : " file_to_sign
        if [[ ! -f "$file_to_sign" ]]; then
            log_error "Fichier introuvable : $file_to_sign"
            return 1
        fi

        local signed_file="${file_to_sign}.signed"
        if command_exists sbsign; then
            sbsign --key "$mok_key" --cert "$mok_crt" \
                --output "$signed_file" "$file_to_sign" 2>&1 |
                while read -r l; do log_info "sbsign: $l"; done
            if [[ -f "$signed_file" ]]; then
                log_success "Fichier signé : $signed_file"
                if confirm_action "Remplacer l'original par le fichier signé ?" yes; then
                    mv "$signed_file" "$file_to_sign"
                    log_success "Original remplacé"
                fi
            fi
        elif command_exists pesign; then
            pesign --sign --in="$file_to_sign" --out="$signed_file" \
                --certificate="$mok_crt" 2>&1 |
                while read -r l; do log_info "pesign: $l"; done
            if [[ -f "$signed_file" ]]; then
                log_success "Fichier signé : $signed_file"
                if confirm_action "Remplacer l'original par le fichier signé ?" yes; then
                    mv "$signed_file" "$file_to_sign"
                    log_success "Original remplacé"
                fi
            fi
        fi
        ;;
    5)
        read -r -p "Fichier EFI à vérifier : " file_to_verify
        if [[ ! -f "$file_to_verify" ]]; then
            log_error "Fichier introuvable : $file_to_verify"
            return 1
        fi
        echo ""
        if command_exists sbverify; then
            sbverify --list "$file_to_verify" 2>&1 |
                while read -r l; do printf '  %s\n' "$l"; done
        elif command_exists pesign; then
            pesign --show-signatures --in="$file_to_verify" 2>&1 |
                while read -r l; do printf '  %s\n' "$l"; done
        else
            log_warning "sbverify / pesign non disponibles"
        fi
        ;;
    6) return 0 ;;
    *) log_warning "Choix invalide" ;;
    esac
}

repair_initramfs() {
    if is_operation_completed "initramfs_repair"; then
        log_info "Régénération initramfs déjà effectuée durant cette session"
        return 0
    fi

    local cmd=""
    local manual_help=""

    case "$DISTRO_FAMILY" in
    debian)
        cmd="update-initramfs -u -k all"
        manual_help=""
        ;;
    rhel)
        cmd="dracut -f"
        manual_help=""
        ;;
    arch)
        cmd="mkinitcpio -P"
        manual_help=""
        ;;
    suse)
        cmd=""
        manual_help="Commande manuelle : sudo mkinitrd"
        ;;
    void)
        cmd=""
        manual_help="Commande manuelle : sudo dracut --force"
        ;;
    gentoo)
        cmd=""
        manual_help="Commande manuelle : sudo genkernel --install initramfs"
        ;;
    *)
        manual_help="Famille inconnue : $DISTRO_FAMILY. Régénérez l'initramfs manuellement selon votre distribution."
        ;;
    esac

    if [[ -n "$cmd" ]]; then
        local tool
        tool=$(printf '%s' "$cmd" | awk '{print $1}')
        if ! command_exists "$tool"; then
            log_warning "Outil introuvable : $tool"
            echo ""
            echo "  Pour régénérer l'initramfs manuellement :"
            echo "  - Debian/Ubuntu : sudo update-initramfs -u -k all"
            echo "  - RHEL/Fedora   : sudo dracut -f"
            echo "  - Arch Linux    : sudo mkinitcpio -P"
            echo ""
            if confirm_action "Voulez-vous que le script essaie d'installer $tool ?" yes; then
                install_packages "$tool" || return 1
            else
                return 1
            fi
        fi

        log_info "Mise à jour de l'initramfs avec : $cmd"
        eval "$cmd" 2>&1 | while read -r line; do log_debug "$line"; done
        if [[ ${PIPESTATUS[0]} -eq 0 ]]; then
            log_success "Initramfs régénéré avec succès"
            mark_operation_completed "initramfs_repair"
            return 0
        fi

        log_error "Échec de la régénération de l'initramfs"
        return 1
    else
        log_warning "Régénération automatique non disponible pour $DISTRO_FAMILY"
        echo ""
        echo "╔══════════════════════════════════════════════════════════════════╗"
        echo "║  INITRAMFS : ACTION MANUELLE REQUISE                             ║"
        echo "╚══════════════════════════════════════════════════════════════════╝"
        echo ""
        echo "  $manual_help"
        echo ""
        echo "  Pourquoi c'est important ?"
        echo "  Un initramfs obsolète peut causer :"
        echo "    - Noyau qui ne démarre pas (kernel panic)"
        echo "    - Modules manquants (disque, chiffrement, RAID)"
        echo "    - UUID root introuvable"
        echo ""

        if confirm_action "Souhaitez-vous que le script tente une méthode alternative ?" yes; then
            if command_exists dracut; then
                log_info "Tentative avec dracut (méthode générique)..."
                dracut -f 2>&1 | while read -r line; do log_debug "$line"; done
                if [[ ${PIPESTATUS[0]} -eq 0 ]]; then
                    log_success "Initramfs régénéré via dracut"
                    mark_operation_completed "initramfs_repair"
                    return 0
                fi
                log_error "Échec de dracut"
            fi
            if command_exists mkinitramfs; then
                log_info "Tentative avec mkinitramfs (méthode générique)..."
                mkinitramfs -o "/boot/initrd.img-$(uname -r)" "$(uname -r)" 2>&1 | while read -r line; do log_debug "$line"; done
                if [[ ${PIPESTATUS[0]} -eq 0 ]]; then
                    log_success "Initramfs régénéré via mkinitramfs"
                    mark_operation_completed "initramfs_repair"
                    return 0
                fi
                log_error "Échec de mkinitramfs"
            fi
            log_error "Aucune méthode générique n'a réussi"
            echo ""
            echo "  Veuillez régénérer l'initramfs manuellement :"
            echo "  $manual_help"
            echo ""
            read -r -p "Appuyez sur Entrée après avoir effectué la régénération manuelle..."
            mark_operation_completed "initramfs_repair"
            return 0
        else
            log_warning "Régénération initramfs ignorée. Le système pourrait ne pas démarrer."
            return 1
        fi
    fi
}

package_install_command() {
    case "$PKG_MANAGER" in
    apt)
        echo "apt-get install -y"
        ;;
    dnf)
        echo "dnf install -y"
        ;;
    yum)
        echo "yum install -y"
        ;;
    pacman)
        echo "pacman -S --noconfirm --needed"
        ;;
    zypper)
        echo "zypper install -y"
        ;;
    emerge)
        echo "emerge --noreplace"
        ;;
    xbps)
        echo "xbps-install -y"
        ;;
    *)
        return 1
        ;;
    esac
}

package_refresh_command() {
    case "$PKG_MANAGER" in
    apt)
        echo "apt-get update"
        ;;
    dnf)
        echo "dnf makecache --refresh"
        ;;
    yum)
        echo "yum makecache"
        ;;
    pacman)
        echo "pacman -Sy --noconfirm"
        ;;
    zypper)
        echo "zypper refresh"
        ;;
    xbps)
        echo "xbps-install -Sy"
        ;;
    emerge)
        echo "emerge --sync"
        ;;
    *)
        return 1
        ;;
    esac
}

install_packages() {
    local packages=("$@")
    local installer
    installer=$(package_install_command) || {
        log_warning "Gestionnaire de paquets non pris en charge : $PKG_MANAGER"
        return 1
    }

    log_info "Installation des paquets requis : ${packages[*]}"
    local refresh_cmd
    if refresh_cmd=$(package_refresh_command 2>/dev/null); then
        if [[ -n "$refresh_cmd" ]]; then
            log_info "Actualisation des métadonnées des paquets avant installation"
            if ! eval "$refresh_cmd" 2>&1 | while read -r line; do log_debug "$line"; done; then
                log_warning "Impossible d'actualiser le cache des paquets. Tentative d'installation directe."
            fi
        fi
    fi

    if eval "$installer ${packages[*]}" 2>&1 | while read -r line; do log_debug "$line"; done; then
        log_success "Paquets installés : ${packages[*]}"
        return 0
    fi

    log_error "Échec de l'installation des paquets requis"
    return 1
}

package_installed() {
    local pkg="$1"
    case "$PKG_MANAGER" in
    apt)
        dpkg -s "$pkg" &>/dev/null
        ;;
    dnf | yum | zypper)
        rpm -q "$pkg" &>/dev/null
        ;;
    pacman)
        pacman -Q "$pkg" &>/dev/null
        ;;
    xbps)
        xbps-query -l "$pkg" &>/dev/null
        ;;
    emerge)
        command -v equery >/dev/null 2>&1 && equery list "$pkg" >/dev/null 2>&1
        ;;
    *)
        return 1
        ;;
    esac
}

install_repair_dependencies() {
    local boot_mode
    boot_mode=$(detect_boot_mode)
    local required_packages=()
    local required_commands=()

    case "$DISTRO_FAMILY" in
    debian)
        if [[ "$boot_mode" == "uefi" ]]; then
            required_packages+=(grub-efi-amd64 grub-efi-amd64-signed shim-signed efibootmgr)
            required_commands+=(grub-install efibootmgr)
        else
            required_packages+=(grub-pc)
            required_commands+=(grub-install)
        fi
        required_packages+=(initramfs-tools)
        required_commands+=(update-initramfs)
        if command_exists bootctl || [[ -f /boot/efi/loader/loader.conf ]] || [[ -f /efi/loader/loader.conf ]] || [[ -f /boot/loader/loader.conf ]] || [[ -f /boot/efi/EFI/systemd/systemd-bootx64.efi ]] || [[ -f /efi/EFI/systemd/systemd-bootx64.efi ]]; then
            required_commands+=(bootctl)
        fi
        ;;
    rhel)
        required_packages+=(grub2 dracut)
        required_commands+=(grub2-install dracut)
        if [[ "$boot_mode" == "uefi" ]]; then
            required_packages+=(efibootmgr)
            required_commands+=(efibootmgr)
        fi
        ;;
    arch)
        required_packages+=(grub mkinitcpio)
        required_commands+=(grub-install mkinitcpio)
        if [[ "$boot_mode" == "uefi" ]]; then
            required_packages+=(efibootmgr)
            required_commands+=(efibootmgr)
        fi
        if command_exists bootctl || [[ -f /boot/loader/loader.conf ]]; then
            required_commands+=(bootctl)
        fi
        ;;
    *)
        log_warning "Installation automatique des dépendances non prise en charge pour $DISTRO_FAMILY"
        return 1
        ;;
    esac

    local missing_packages=()
    local missing_commands=()
    local pkg
    local cmd

    for cmd in "${required_commands[@]}"; do
        if ! command_exists "$cmd"; then
            missing_commands+=("$cmd")
        fi
    done

    for pkg in "${required_packages[@]}"; do
        if ! package_installed "$pkg"; then
            missing_packages+=("$pkg")
        fi
    done

    if [[ ${#missing_packages[@]} -eq 0 ]] && [[ ${#missing_commands[@]} -eq 0 ]]; then
        log_success "Toutes les dépendances requises sont présentes"
        return 0
    fi

    if [[ ${#missing_commands[@]} -gt 0 ]]; then
        log_warning "Outils manquants détectés : ${missing_commands[*]}"
    fi
    if [[ ${#missing_packages[@]} -gt 0 ]]; then
        log_warning "Dépendances manquantes : ${missing_packages[*]}"
    fi

    if ! confirm_action "Installer les dépendances manquantes avant la réparation ?" yes; then
        return 1
    fi

    if [[ ${#missing_packages[@]} -eq 0 ]]; then
        log_error "Des outils nécessaires sont manquants mais aucun paquet n'a été identifié pour installation automatique. Vérifiez le système ou installez manuellement : ${missing_commands[*]}"
        return 1
    fi

    install_packages "${missing_packages[@]}"
}

#-------------------------------------------------------------------------------
# MODULE : RÉPARATION SYSTEMD-BOOT
#-------------------------------------------------------------------------------
repair_systemd_boot() {
    log_header "RÉPARATION SYSTEMD-BOOT"

    if ! command_exists bootctl; then
        log_warning "bootctl introuvable. Tentative d'installation..."
        case "$DISTRO_FAMILY" in
        debian) install_packages systemd-boot-efi 2>/dev/null ||
            install_packages systemd 2>/dev/null ;;
        arch) install_packages systemd 2>/dev/null ;;
        rhel) install_packages systemd-udev 2>/dev/null ;;
        *)
            log_error "Installation automatique de bootctl non supportée pour $DISTRO_FAMILY"
            return 1
            ;;
        esac
        if ! command_exists bootctl; then
            log_error "bootctl toujours introuvable après tentative d'installation"
            return 1
        fi
    fi

    if [[ $(detect_boot_mode) != "uefi" ]]; then
        log_error "systemd-boot nécessite un système UEFI. Mode BIOS/Legacy détecté."
        return 1
    fi

    local esp_dir=""
    for d in /boot/efi /efi /boot; do
        if findmnt -n "$d" &>/dev/null && [[ "$(findmnt -n -o FSTYPE "$d" 2>/dev/null)" == "vfat" ]]; then
            esp_dir="$d"
            break
        fi
    done
    if [[ -z "$esp_dir" ]]; then
        log_error "Partition EFI (ESP) non montée. Montez-la sur /boot/efi ou /efi avant de continuer."
        echo ""
        echo "Partitions vfat disponibles :"
        blkid | grep -i vfat || lsblk -f | grep -i vfat || echo "aucune"
        return 1
    fi
    log_info "ESP détectée : $esp_dir"

    echo ""
    echo "  Options systemd-boot :"
    echo "  1)  Réinstaller bootctl (bootctl install)"
    echo "  2)  Mettre à jour bootctl (bootctl update)"
    echo "  3)  Afficher statut (bootctl status)"
    echo "  4)  Lister les entrées de boot (bootctl list)"
    echo "  5)  Créer une entrée boot manquante"
    echo "  6)  Valider UUID entrées boot (fix BusyBox / ALERT UUID)"
    echo "  7)  Vérifier crypttab (fix suffix _XXXXX qui casse initramfs)"
    echo "  8)  Retour"
    echo ""
    read -r -p "Choix [1-8] : " sd_choice

    case "$sd_choice" in
    1)
        if ! confirm_action "Réinstaller systemd-boot dans $esp_dir. Écrase le bootloader EFI existant." strict; then
            return 0
        fi
        local esp_bak
        esp_bak="${BACKUP_DIR}/esp-backup-$(date +%H%M%S).tar.gz"
        mkdir -p "$BACKUP_DIR"
        if tar -czf "$esp_bak" -C "$(dirname "$esp_dir")" "$(basename "$esp_dir")" 2>/dev/null; then
            log_success "[BACKUP OK] ESP sauvegardée : $esp_bak"
        else
            log_warning "Sauvegarde ESP échouée"
        fi

        if bootctl install --esp-path="$esp_dir" 2>&1 | while read -r l; do log_info "bootctl: $l"; done; then
            log_success "systemd-boot réinstallé dans $esp_dir"
        else
            log_error "Échec de bootctl install"
            return 1
        fi

        local loader_conf="${esp_dir}/loader/loader.conf"
        if [[ ! -f "$loader_conf" ]]; then
            mkdir -p "${esp_dir}/loader"
            printf 'timeout 5\ndefault @saved\nconsole-mode auto\n' >"$loader_conf"
            log_success "loader.conf créé : $loader_conf"
        fi

        if [[ "$DISTRO_FAMILY" == "arch" ]] && command_exists mkinitcpio; then
            mkinitcpio -P 2>&1 | while read -r l; do log_debug "$l"; done
            log_success "initramfs régénéré"
        elif [[ "$DISTRO_FAMILY" == "debian" ]] && command_exists update-initramfs; then
            update-initramfs -u -k all 2>&1 | while read -r l; do log_debug "$l"; done
            log_success "initramfs régénéré"
        fi

        if command_exists kernel-install; then
            log_info "Réinstallation des entrées noyau via kernel-install..."
            local kver
            kver=$(uname -r)
            kernel-install add "$kver" "/boot/vmlinuz-${kver}" 2>&1 |
                while read -r l; do log_debug "$l"; done &&
                log_success "Entrée noyau $kver installée"
        fi
        ;;
    2)
        if bootctl update --esp-path="$esp_dir" 2>&1 | while read -r l; do log_info "bootctl: $l"; done; then
            log_success "systemd-boot mis à jour"
        else
            log_error "Échec de bootctl update"
            return 1
        fi
        ;;
    3)
        echo ""
        bootctl status 2>&1 | while read -r l; do printf '  %s\n' "$l"; done
        ;;
    4)
        echo ""
        bootctl list 2>&1 | while read -r l; do printf '  %s\n' "$l"; done
        ;;
    5)
        _create_sd_boot_entry "$esp_dir"
        ;;
    6)
        _validate_sd_boot_uuids "$esp_dir"
        ;;
    7)
        _check_crypttab_suffix
        ;;
    8) return 0 ;;
    *) log_warning "Choix invalide" ;;
    esac
}

_validate_sd_boot_uuids() {
    local esp_dir="$1"
    local entries_dir="${esp_dir}/loader/entries"
    if [[ ! -d "$entries_dir" ]]; then
        log_error "Répertoire d'entrées introuvable : $entries_dir"
        return 1
    fi

    log_subheader "Validation UUID entrées systemd-boot"
    local any_mismatch=false

    for conf in "${entries_dir}/"*.conf; do
        [[ -f "$conf" ]] || continue
        local entry_uuid
        entry_uuid=$(sed -n 's/.*root=UUID="\?\([0-9A-Za-z-]*\)"\?.*/\1/p' "$conf" | head -1)
        [[ -z "$entry_uuid" ]] && continue

        local real_dev
        real_dev=$(blkid -t UUID="$entry_uuid" -o device 2>/dev/null | head -1)

        echo ""
        printf "  Entrée : %s\n" "$(basename "$conf")"
        printf "  UUID dans .conf : %s\n" "$entry_uuid"
        if [[ -n "$real_dev" ]]; then
            printf "%b  OK : UUID trouvé sur %s%b\n" "${GREEN}" "$real_dev" "${NC}"
        else
            printf "%b  MISMATCH : aucun device avec UUID=%s%b\n" "${RED}" "$entry_uuid" "${NC}"
            any_mismatch=true
            local real_uuid
            real_uuid=$(findmnt -n -o UUID / 2>/dev/null | head -1)
            [[ -z "$real_uuid" ]] && real_uuid=$(blkid /dev/mapper/data-root -s UUID -o value 2>/dev/null | head -1)
            if [[ -n "$real_uuid" ]]; then
                printf "  UUID correct détecté : %s\n" "$real_uuid"
                if confirm_action "Corriger UUID dans $(basename "$conf") : $entry_uuid → $real_uuid ?" yes; then
                    cp "$conf" "${conf}.bak.$(date +%H%M%S)"
                    sed -i "s|root=UUID=${entry_uuid}|root=UUID=${real_uuid}|g" "$conf"
                    log_success "UUID corrigé dans $(basename "$conf")"
                fi
            fi
        fi
    done

    [[ "$any_mismatch" == false ]] && log_success "Tous les UUID des entrées boot sont valides"
}

_check_crypttab_suffix() {
    log_subheader "Vérification /etc/crypttab"
    if [[ ! -f /etc/crypttab ]]; then
        log_info "/etc/crypttab absent — pas de chiffrement LUKS configuré"
        return 0
    fi

    echo ""
    echo "Contenu actuel de /etc/crypttab :"
    cat /etc/crypttab | while read -r l; do printf '  %s\n' "$l"; done
    echo ""

    local fixed=false
    local new_crypttab
    new_crypttab=$(mktemp /tmp/rd_crypttab_XXXXXX)

    while IFS= read -r line; do
        if [[ "$line" =~ ^cryptdata_[A-Za-z0-9]+\s ]]; then
            local fixed_line
            fixed_line="cryptdata${line#cryptdata_}"
            printf "%b  Suffix parasite détecté :%b\n    avant : %s\n    après : %s\n" \
                "${YELLOW}" "${NC}" "$line" "$fixed_line"
            echo "$fixed_line" >>"$new_crypttab"
            fixed=true
        else
            echo "$line" >>"$new_crypttab"
        fi
    done </etc/crypttab

    if [[ "$fixed" == true ]]; then
        if confirm_action "Corriger /etc/crypttab (supprimer suffix _XXXXX sur cryptdata) ?" yes; then
            cp /etc/crypttab "/etc/crypttab.bak.$(date +%H%M%S)"
            cp "$new_crypttab" /etc/crypttab
            log_success "crypttab corrigé"
            if command_exists update-initramfs; then
                log_info "Régénération initramfs..."
                update-initramfs -c -k all 2>&1 | while read -r l; do log_debug "$l"; done
                log_success "initramfs régénéré"
            fi
        fi
    else
        log_success "Aucun suffix parasite détecté dans /etc/crypttab"
    fi
    rm -f "$new_crypttab"
}

_create_sd_boot_entry() {
    local esp_dir="$1"
    local entries_dir="${esp_dir}/loader/entries"
    mkdir -p "$entries_dir"

    local kver
    kver=$(uname -r)
    local vmlinuz=""
    local initrd_path=""
    for vml in "/boot/vmlinuz-${kver}" "/boot/vmlinuz" "/boot/Image"; do
        [[ -f "$vml" ]] && vmlinuz="$vml" && break
    done
    for ird in "/boot/initrd.img-${kver}" "/boot/initramfs-${kver}.img" "/boot/initrd.img"; do
        [[ -f "$ird" ]] && initrd_path="$ird" && break
    done

    if [[ -z "$vmlinuz" ]]; then
        log_error "vmlinuz introuvable pour le noyau $kver"
        return 1
    fi

    local root_uuid
    root_uuid=$(findmnt -n -o UUID / 2>/dev/null | head -1)
    if [[ -z "$root_uuid" ]]; then
        log_error "UUID partition root introuvable"
        return 1
    fi

    local esp_kdir="${esp_dir}/${DISTRO_FAMILY:-linux}"
    mkdir -p "$esp_kdir"
    local esp_vmlinuz="${esp_kdir}/vmlinuz-${kver}"
    local esp_initrd="${esp_kdir}/initrd-${kver}.img"
    if cp "$vmlinuz" "$esp_vmlinuz" 2>/dev/null; then
        log_success "vmlinuz copié dans ESP : $esp_vmlinuz"
    else
        log_warning "Échec copie vmlinuz vers ESP"
    fi
    if [[ -n "$initrd_path" ]]; then
        if cp "$initrd_path" "$esp_initrd" 2>/dev/null; then
            log_success "initrd copié dans ESP : $esp_initrd"
        else
            log_warning "Échec copie initrd vers ESP"
        fi
    fi

    local entry_file="${entries_dir}/${DISTRO:-linux}-${kver}.conf"
    {
        echo "title   ${PRETTY_NAME:-Linux ${kver}}"
        echo "linux   /${DISTRO_FAMILY:-linux}/vmlinuz-${kver}"
        [[ -n "$initrd_path" ]] && echo "initrd  /${DISTRO_FAMILY:-linux}/initrd-${kver}.img"
        echo "options root=UUID=${root_uuid} rw quiet splash"
    } >"$entry_file"

    log_success "Entrée boot créée : $entry_file"
    echo ""
    cat "$entry_file" | while read -r l; do printf '  %s\n' "$l"; done
    echo ""
}

#-------------------------------------------------------------------------------
# MODULE : RÉPARATION EN CHROOT (live USB → système installé)
#-------------------------------------------------------------------------------
_chroot_cleanup() {
    local chroot_dir="$1"
    log_info "Démontage du chroot $chroot_dir..."
    for sub in /sys/firmware/efi/efivars /run /sys /proc /dev/pts /dev /boot/efi /boot; do
        umount "${chroot_dir}${sub}" 2>/dev/null || true
    done
    umount "$chroot_dir" 2>/dev/null || true
    rmdir "$chroot_dir" 2>/dev/null || true
    log_info "Chroot démonté"
}

repair_in_chroot() {
    log_header "RÉPARATION EN CHROOT"
    echo ""
    log_info "Scan des partitions Linux disponibles..."

    local tmp_mnt
    tmp_mnt=$(mktemp -d /tmp/rd_probe_XXXXXX)
    local idx=0
    declare -A inst_map
    local -a installs=()

    while read -r part; do
        local dev="/dev/$part"
        if mount -o ro "$dev" "$tmp_mnt" 2>/dev/null; then
            if [[ -f "$tmp_mnt/etc/os-release" ]]; then
                local name
                name=$(grep -m1 '^PRETTY_NAME=' "$tmp_mnt/etc/os-release" 2>/dev/null |
                    tr -d '"' | cut -d= -f2-)
                idx=$((idx + 1))
                inst_map[$idx]="$dev"
                installs+=("  $idx) $dev  —  ${name:-inconnu}")
            fi
            umount "$tmp_mnt" 2>/dev/null
        fi
    done < <(lsblk -lno NAME,TYPE,FSTYPE |
        awk '$2=="part" && ($3=="ext4"||$3=="ext3"||$3=="ext2"||$3=="btrfs"||$3=="xfs") {print $1}')
    rmdir "$tmp_mnt" 2>/dev/null

    if ((${#installs[@]} == 0)); then
        log_warning "Aucun système Linux installé détecté sur les partitions disponibles."
        return 1
    fi

    echo ""
    printf "%b\n" "${CYAN}${BOLD}Installations Linux détectées :${NC}"
    echo "───────────────────────────────────────────────────────────"
    printf '%s\n' "${installs[@]}"
    echo "───────────────────────────────────────────────────────────"
    echo ""
    read -r -p "Numéro de l'installation à réparer : " chosen

    local root_dev="${inst_map[$chosen]:-}"
    if [[ -z "$root_dev" || ! -b "$root_dev" ]]; then
        log_error "Sélection invalide"
        return 1
    fi

    local chroot_dir
    chroot_dir=$(mktemp -d /tmp/rd_chroot_XXXXXX)
    log_info "Montage de $root_dev sur $chroot_dir..."

    if ! mount "$root_dev" "$chroot_dir"; then
        log_error "Impossible de monter $root_dev"
        rmdir "$chroot_dir"
        return 1
    fi

    if [[ -f "$chroot_dir/etc/fstab" ]]; then
        local boot_dev efi_dev
        boot_dev=$(awk '$2=="/boot" && $1!~/^#/{print $1}' "$chroot_dir/etc/fstab" | head -1)
        efi_dev=$(awk '$2=="/boot/efi" && $1!~/^#/{print $1}' "$chroot_dir/etc/fstab" | head -1)
        if [[ -n "$boot_dev" && -b "$boot_dev" ]]; then
            log_info "Montage /boot séparé : $boot_dev"
            mount "$boot_dev" "$chroot_dir/boot" 2>/dev/null ||
                log_warning "Impossible de monter /boot"
        fi
        if [[ -n "$efi_dev" && -b "$efi_dev" ]]; then
            mkdir -p "$chroot_dir/boot/efi"
            log_info "Montage EFI : $efi_dev"
            mount "$efi_dev" "$chroot_dir/boot/efi" 2>/dev/null ||
                log_warning "Impossible de monter /boot/efi"
        fi
    fi

    for d in /dev /dev/pts /proc /sys /run; do
        mkdir -p "${chroot_dir}${d}"
        mount -R "$d" "${chroot_dir}${d}" 2>/dev/null ||
            mount --bind "$d" "${chroot_dir}${d}" 2>/dev/null ||
            log_warning "mount $d échoué"
    done
    if [[ -d /sys/firmware/efi/efivars ]]; then
        mkdir -p "$chroot_dir/sys/firmware/efi/efivars"
        mount --bind /sys/firmware/efi/efivars \
            "$chroot_dir/sys/firmware/efi/efivars" 2>/dev/null || true
    fi

    local chroot_family="debian"
    if [[ -f "$chroot_dir/etc/os-release" ]]; then
        local chroot_id
        chroot_id=$(grep -m1 '^ID_LIKE=' "$chroot_dir/etc/os-release" 2>/dev/null |
            cut -d= -f2 | tr -d '"')
        [[ -z "$chroot_id" ]] && chroot_id=$(grep -m1 '^ID=' "$chroot_dir/etc/os-release" |
            cut -d= -f2 | tr -d '"')
        case "${chroot_id,,}" in
        *debian* | *ubuntu* | *mint*) chroot_family="debian" ;;
        *fedora* | *rhel* | *centos* | *rocky* | *alma*) chroot_family="rhel" ;;
        *arch* | *manjaro* | *endeavour*) chroot_family="arch" ;;
        *suse*) chroot_family="suse" ;;
        esac
    fi

    local grub_disk boot_mode grub_cmd
    grub_disk=$(detect_boot_device)
    if [[ -z "$grub_disk" ]]; then
        echo ""
        lsblk -d -o NAME,SIZE,TYPE,TRAN,MODEL 2>/dev/null |
            grep -v loop |
            awk 'NR==1{print "  "$0} NR>1{print "  /dev/"$0}'
        echo ""
        read -r -p "Disque cible pour GRUB (ex. /dev/sda) : " grub_disk
    fi

    if [[ ! -b "$grub_disk" ]]; then
        log_error "Disque invalide : $grub_disk"
        _chroot_cleanup "$chroot_dir"
        return 1
    fi

    boot_mode=$(detect_boot_mode)
    local target_uefi=false
    if [[ -f "$chroot_dir/boot/efi/loader/loader.conf" ]] ||
        [[ -f "$chroot_dir/boot/loader/loader.conf" ]] ||
        [[ -f "$chroot_dir/efi/loader/loader.conf" ]] ||
        [[ -d "$chroot_dir/boot/efi/EFI" ]] ||
        [[ -d "$chroot_dir/efi/EFI" ]]; then
        target_uefi=true
    fi

    local chroot_uses_sd=false
    if [[ "$boot_mode" == "uefi" || "$target_uefi" == true ]]; then
        local _id_chroot
        _id_chroot=$(grep -m1 '^ID=' "$chroot_dir/etc/os-release" 2>/dev/null | cut -d= -f2 | tr -d '"')
        if [[ "${_id_chroot,,}" == "pop" ]]; then
            chroot_uses_sd=true
        elif [[ -f "$chroot_dir/boot/efi/loader/loader.conf" ]] ||
            [[ -f "$chroot_dir/boot/loader/loader.conf" ]] ||
            [[ -f "$chroot_dir/efi/loader/loader.conf" ]]; then
            chroot_uses_sd=true
        fi
    fi

    if [[ "$chroot_uses_sd" == true ]]; then
        log_info "Système cible utilise systemd-boot — réparation via bootctl"
        local sd_cmd
        sd_cmd="apt install --reinstall linux-image-generic linux-headers-generic 2>/dev/null; "
        sd_cmd+="update-initramfs -c -k all 2>/dev/null || mkinitcpio -P 2>/dev/null; "
        sd_cmd+="exit"
        log_info "Commande chroot systemd-boot : $sd_cmd"
        chroot "$chroot_dir" /bin/bash -c "$sd_cmd" 2>&1 |
            while read -r line; do log_info "chroot: $line"; done
        local chroot_esp=""
        for _e in "$chroot_dir/boot/efi" "$chroot_dir/efi" "$chroot_dir/boot"; do
            [[ -d "$_e/EFI" || -f "$_e/loader/loader.conf" ]] && chroot_esp="$_e" && break
        done
        if [[ -n "$chroot_esp" ]]; then
            if bootctl install --esp-path="$chroot_esp" 2>&1 |
                while read -r line; do log_info "bootctl: $line"; done; then
                log_success "systemd-boot réinstallé via chroot sur $chroot_dir (esp=$chroot_esp)"
            else
                log_error "Échec bootctl install via chroot"
            fi
        else
            log_warning "ESP introuvable dans le chroot — bootctl non installé"
        fi
        _chroot_cleanup "$chroot_dir"
        return 0
    fi

    case "$chroot_family" in
    debian)
        if [[ "$boot_mode" == "uefi" || "$target_uefi" == true ]]; then
            grub_cmd="grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=GRUB --recheck && update-grub"
        else
            grub_cmd="grub-install --target=i386-pc --recheck ${grub_disk} && update-grub"
        fi
        ;;
    rhel)
        if [[ "$boot_mode" == "uefi" || "$target_uefi" == true ]]; then
            grub_cmd="grub2-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=GRUB --recheck && grub2-mkconfig -o /boot/grub2/grub.cfg"
        else
            grub_cmd="grub2-install --target=i386-pc --recheck ${grub_disk} && grub2-mkconfig -o /boot/grub2/grub.cfg"
        fi
        ;;
    arch)
        if [[ "$boot_mode" == "uefi" || "$target_uefi" == true ]]; then
            grub_cmd="grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=GRUB --recheck && grub-mkconfig -o /boot/grub/grub.cfg"
        else
            grub_cmd="grub-install --target=i386-pc --recheck ${grub_disk} && grub-mkconfig -o /boot/grub/grub.cfg"
        fi
        ;;
    suse)
        if [[ "$boot_mode" == "uefi" || "$target_uefi" == true ]]; then
            grub_cmd="grub2-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=grub --recheck && grub2-mkconfig -o /boot/grub2/grub.cfg"
        else
            grub_cmd="grub2-install --target=i386-pc --recheck ${grub_disk} && grub2-mkconfig -o /boot/grub2/grub.cfg"
        fi
        ;;
    *)
        grub_cmd="grub-install --recheck ${grub_disk} 2>/dev/null; update-grub 2>/dev/null || grub-mkconfig -o /boot/grub/grub.cfg 2>/dev/null"
        ;;
    esac

    log_info "Commande chroot : $grub_cmd"
    if chroot "$chroot_dir" /bin/bash -c "$grub_cmd" 2>&1 |
        while read -r line; do log_info "chroot: $line"; done; then
        log_success "GRUB réinstallé avec succès via chroot sur $chroot_dir"
    else
        log_error "Échec de la réinstallation GRUB dans le chroot"
    fi

    _chroot_cleanup "$chroot_dir"
}

#-------------------------------------------------------------------------------
# MODULE : UPLOAD RAPPORT EN LIGNE
#-------------------------------------------------------------------------------
upload_report() {
    local report_file="${1:-${BACKUP_DIR}/boot-info.txt}"
    if [[ ! -f "$report_file" ]]; then
        log_error "Fichier rapport introuvable : $report_file"
        return 1
    fi
    if ! command_exists curl; then
        log_warning "curl non disponible — impossible d'uploader."
        log_info "Rapport local : $report_file"
        return 1
    fi
    if ! curl -sf --max-time 5 --head https://paste.ubuntu.com >/dev/null 2>&1; then
        log_warning "Pas de connexion internet détectée. Upload ignoré."
        log_info "Rapport local : $report_file"
        return 1
    fi

    local url_ubuntu="" url_dpaste="" url_gofile=""
    local tmp_u tmp_d tmp_g
    tmp_u=$(mktemp /tmp/rd_up_ubuntu_XXXXXX)
    tmp_d=$(mktemp /tmp/rd_up_dpaste_XXXXXX)
    tmp_g=$(mktemp /tmp/rd_up_gofile_XXXXXX)

    log_info "Upload en parallèle sur les 3 services..."

    # paste.ubuntu.com
    (curl -sf --max-time 30 \
        -F "poster=Rep-Dem" \
        -F "syntax=text" \
        -F "content=<${report_file}" \
        https://paste.ubuntu.com/ 2>/dev/null |
        grep -oE 'href="/[0-9]+' | cut -d'/' -f2 | head -1 >"$tmp_u") &
    local pid_u=$!

    # dpaste.com
    (curl -sf --max-time 30 -X POST https://dpaste.com/api/v2/ \
        --data-urlencode "content@${report_file}" \
        -d "syntax=text" \
        -d "expiry_days=7" 2>/dev/null >"$tmp_d") &
    local pid_d=$!

    # gofile.io
    (
        curl -sf --max-time 60 \
            -X POST \
            -F "file=@${report_file}" \
            "https://upload.gofile.io/uploadfile" 2>/dev/null |
            grep -oE '"downloadPage":"([^"]+)' | cut -d'"' -f3 | head -1 >"$tmp_g"
    ) &
    local pid_g=$!

    wait $pid_u $pid_d $pid_g 2>/dev/null

    local raw_u raw_d
    raw_u=$(cat "$tmp_u" 2>/dev/null)
    raw_d=$(cat "$tmp_d" 2>/dev/null)
    [[ -n "$raw_u" ]] && url_ubuntu="https://paste.ubuntu.com/${raw_u}/"
    [[ -n "$raw_d" ]] && url_dpaste="$raw_d"
    url_gofile=$(cat "$tmp_g" 2>/dev/null)
    rm -f "$tmp_u" "$tmp_d" "$tmp_g"

    local any_ok=false
    echo ""
    printf "%b\n" "${GREEN}${BOLD}╔══════════════════════════════════════════════════════════════════╗${NC}"
    printf "%b  %-66s%b\n" "${GREEN}${BOLD}║${NC}" "LIENS DU RAPPORT BOOT-INFO" "${GREEN}${BOLD}║${NC}"
    printf "%b  %-66s%b\n" "${GREEN}${BOLD}║${NC}" "" "${GREEN}${BOLD}║${NC}"
    if [[ -n "$url_ubuntu" ]]; then
        any_ok=true
        printf "%b  %-66s%b\n" "${GREEN}${BOLD}║${NC}" "  paste.ubuntu.com : $url_ubuntu" "${GREEN}${BOLD}║${NC}"
    else
        printf "%b  %-66s%b\n" "${GREEN}${BOLD}║${NC}" "  paste.ubuntu.com : échec" "${GREEN}${BOLD}║${NC}"
    fi
    if [[ -n "$url_dpaste" ]]; then
        any_ok=true
        printf "%b  %-66s%b\n" "${GREEN}${BOLD}║${NC}" "  dpaste.com       : $url_dpaste" "${GREEN}${BOLD}║${NC}"
    else
        printf "%b  %-66s%b\n" "${GREEN}${BOLD}║${NC}" "  dpaste.com       : échec" "${GREEN}${BOLD}║${NC}"
    fi
    if [[ -n "$url_gofile" ]]; then
        any_ok=true
        printf "%b  %-66s%b\n" "${GREEN}${BOLD}║${NC}" "  gofile.io        : $url_gofile" "${GREEN}${BOLD}║${NC}"
    else
        printf "%b  %-66s%b\n" "${GREEN}${BOLD}║${NC}" "  gofile.io        : échec" "${GREEN}${BOLD}║${NC}"
    fi
    printf "%b  %-66s%b\n" "${GREEN}${BOLD}║${NC}" "" "${GREEN}${BOLD}║${NC}"
    printf "%b  %-66s%b\n" "${GREEN}${BOLD}║${NC}" "  Fichier local : $report_file" "${GREEN}${BOLD}║${NC}"
    printf "%b  %-66s%b\n" "${GREEN}${BOLD}║${NC}" "  Tous les liens sont écrits à la fin du rapport." "${GREEN}${BOLD}║${NC}"
    printf "%b\n" "${GREEN}${BOLD}╚══════════════════════════════════════════════════════════════════╝${NC}"
    echo ""

    {
        echo ""
        echo "=== LIENS UPLOAD ==="
        [[ -n "$url_ubuntu" ]] && echo "paste.ubuntu.com : $url_ubuntu"
        [[ -n "$url_dpaste" ]] && echo "dpaste.com       : $url_dpaste"
        [[ -n "$url_gofile" ]] && echo "gofile.io        : $url_gofile"
    } >>"$report_file"

    if [[ "$any_ok" == false ]]; then
        log_error "Tous les services d'upload ont échoué."
        log_info "Uploadez manuellement sur : https://paste.ubuntu.com  https://dpaste.com  https://gofile.io"
        return 1
    fi
}

#-------------------------------------------------------------------------------
# MODULE : CONFIGURATION OPTIONS MENU GRUB
#-------------------------------------------------------------------------------
configure_grub_menu_options() {
    log_header "CONFIGURATION GRUB"
    local grub_default="/etc/default/grub"
    if [[ ! -f "$grub_default" ]]; then
        log_error "Fichier introuvable : $grub_default — GRUB installé ?"
        return 1
    fi

    backup_file "$grub_default"

    echo ""
    echo "Configuration actuelle de $grub_default :"
    echo "───────────────────────────────────────────────────────────"
    grep -E '^GRUB_(TIMEOUT|DEFAULT|CMDLINE_LINUX_DEFAULT|GFXMODE|HIDDEN_TIMEOUT)' \
        "$grub_default" | awk '{print "  "$0}'
    echo "───────────────────────────────────────────────────────────"
    echo ""
    echo "  1)  Afficher le menu GRUB (désactiver timeout caché)"
    echo "  2)  Modifier le délai d'attente (GRUB_TIMEOUT)"
    echo "  3)  Ajouter une option noyau"
    echo "  4)  Supprimer une option noyau"
    echo "  5)  Modifier la résolution (GRUB_GFXMODE)"
    echo "  6)  Régénérer grub.cfg maintenant"
    echo "  7)  Retour"
    echo ""
    read -r -p "Choix [1-7] : " grub_opt

    case "$grub_opt" in
    1)
        sed -i '/^GRUB_HIDDEN_TIMEOUT=/d' "$grub_default" 2>/dev/null
        local cur_t
        cur_t=$(grep '^GRUB_TIMEOUT=' "$grub_default" 2>/dev/null | head -1 | cut -d= -f2)
        if [[ "$cur_t" == "0" || "$cur_t" == "-1" || -z "$cur_t" ]]; then
            sed -i 's/^GRUB_TIMEOUT=.*/GRUB_TIMEOUT=10/' "$grub_default" 2>/dev/null ||
                echo 'GRUB_TIMEOUT=10' >>"$grub_default"
            log_success "GRUB_TIMEOUT réglé à 10 secondes — le menu s'affichera"
        else
            log_info "GRUB_TIMEOUT déjà à $cur_t — aucune modification"
        fi
        ;;
    2)
        read -r -p "Délai en secondes (ex. 10, -1=infini, 0=caché) : " new_t
        if grep -q '^GRUB_TIMEOUT=' "$grub_default"; then
            sed -i "s/^GRUB_TIMEOUT=.*/GRUB_TIMEOUT=${new_t}/" "$grub_default"
        else
            echo "GRUB_TIMEOUT=${new_t}" >>"$grub_default"
        fi
        log_success "GRUB_TIMEOUT=${new_t}"
        ;;
    3)
        echo "Exemples : nomodeset  acpi=off  acpi_osi=  noapic  nolapic  rootdelay=90  quiet splash"
        read -r -p "Option(s) à ajouter (séparées par des espaces) : " new_opt
        local cur_cmd
        cur_cmd=$(grep '^GRUB_CMDLINE_LINUX_DEFAULT=' "$grub_default" |
            sed 's/^GRUB_CMDLINE_LINUX_DEFAULT=//' | tr -d '"')
        local new_cmd="${cur_cmd:+$cur_cmd }${new_opt}"
        sed -i "s|^GRUB_CMDLINE_LINUX_DEFAULT=.*|GRUB_CMDLINE_LINUX_DEFAULT=\"${new_cmd}\"|" \
            "$grub_default"
        log_success "Options noyau : \"$new_cmd\""
        ;;
    4)
        local cur_cmd
        cur_cmd=$(grep '^GRUB_CMDLINE_LINUX_DEFAULT=' "$grub_default" |
            sed 's/^GRUB_CMDLINE_LINUX_DEFAULT=//' | tr -d '"')
        echo "Options actuelles : $cur_cmd"
        read -r -p "Option à supprimer : " rm_opt
        local new_cmd
        new_cmd=$(echo "$cur_cmd" | sed "s/\b${rm_opt}\b//g" |
            tr -s ' ' | sed 's/^ //;s/ $//')
        sed -i "s|^GRUB_CMDLINE_LINUX_DEFAULT=.*|GRUB_CMDLINE_LINUX_DEFAULT=\"${new_cmd}\"|" \
            "$grub_default"
        log_success "Options noyau après suppression : \"$new_cmd\""
        ;;
    5)
        read -r -p "Résolution (ex. 1024x768, 1920x1080, auto) : " new_gfx
        if grep -q '^GRUB_GFXMODE=' "$grub_default"; then
            sed -i "s|^GRUB_GFXMODE=.*|GRUB_GFXMODE=${new_gfx}|" "$grub_default"
        else
            echo "GRUB_GFXMODE=${new_gfx}" >>"$grub_default"
        fi
        log_success "GRUB_GFXMODE=${new_gfx}"
        ;;
    6) ;;
    7) return 0 ;;
    *)
        log_warning "Choix invalide"
        return 0
        ;;
    esac

    if [[ "$grub_opt" != "7" ]]; then
        local regenerate=false
        [[ "$grub_opt" == "6" ]] && regenerate=true
        if [[ "$grub_opt" != "6" ]] && confirm_action "Régénérer grub.cfg maintenant ?"; then
            regenerate=true
        fi
        if [[ "$regenerate" == "true" ]]; then
            if command_exists update-grub; then
                update-grub 2>&1 | while read -r line; do log_info "$line"; done
            elif command_exists grub-mkconfig; then
                grub-mkconfig -o /boot/grub/grub.cfg 2>&1 | while read -r line; do log_info "$line"; done
            elif command_exists grub2-mkconfig; then
                grub2-mkconfig -o /boot/grub2/grub.cfg 2>&1 | while read -r line; do log_info "$line"; done
            else
                log_error "Aucun outil grub-mkconfig / update-grub trouvé"
            fi
        fi
    fi
}

repair_bios_mbr() {
    local boot_device="$1"
    if ! command_exists grub-install; then
        log_warning "grub-install introuvable : impossible de restaurer le MBR via GRUB"
        return 1
    fi
    log_info "Restauration du MBR GRUB sur $boot_device"
    if grub-install --target=i386-pc --boot-directory=/boot --recheck "$boot_device" 2>&1 | while read -r line; do log_debug "$line"; done; then
        log_success "MBR GRUB restauré sur $boot_device"
        return 0
    fi
    log_error "Échec de la restauration du MBR GRUB sur $boot_device"
    return 1
}

purge_grub() {
    log_subheader "Purge GRUB"
    case "$DISTRO_FAMILY" in
    debian)
        apt-get purge -y grub-pc grub-efi-amd64 grub-efi-amd64-bin grub-efi-amd64-signed grub-common grub2-common 2>&1 | while read -r line; do log_debug "$line"; done
        apt-get autoremove -y 2>&1 | while read -r line; do log_debug "$line"; done
        ;;
    rhel)
        $PKG_MANAGER remove -y grub2 grub2-efi-x64 grub2-pc 2>&1 | while read -r line; do log_debug "$line"; done
        ;;
    arch)
        pacman -Rns --noconfirm grub 2>&1 | while read -r line; do log_debug "$line"; done
        ;;
    *)
        log_warning "Purge GRUB non prise en charge pour : $DISTRO_FAMILY"
        return 1
        ;;
    esac
    log_success "Purge GRUB terminée"
}

generate_boot_info() {
    local output_file="${1:-${BACKUP_DIR}/boot-info.txt}"
    mkdir -p "$(dirname "$output_file")"
    log_info "Génération du rapport Boot-Info : $output_file"
    {
        echo "==============================================================================="
        echo " Boot-Info v${SCRIPT_VERSION}  |  $(date)"
        echo " Host: $(hostname)  |  Kernel: $(uname -r)  |  Arch: $(uname -m)"
        echo "==============================================================================="
        echo ""
        echo "=== DISTRO ==="
        cat /etc/os-release 2>/dev/null || echo "indisponible"
        echo ""
        echo "=== BOOT MODE ==="
        [[ -d /sys/firmware/efi ]] && echo "UEFI" || echo "BIOS/Legacy"
        echo ""
        echo "=== PARTITIONS (fdisk) ==="
        fdisk -l 2>/dev/null || echo "indisponible"
        echo ""
        echo "=== PARTITIONS (parted) ==="
        parted -l 2>/dev/null || echo "indisponible"
        echo ""
        echo "=== BLOCK DEVICES ==="
        lsblk -o NAME,FSTYPE,MOUNTPOINT,SIZE,UUID,LABEL,PARTUUID 2>/dev/null || echo "indisponible"
        echo ""
        echo "=== BLKID ==="
        blkid 2>/dev/null || echo "indisponible"
        echo ""
        echo "=== FSTAB ==="
        cat /etc/fstab 2>/dev/null || echo "indisponible"
        echo ""
        echo "=== EFI BOOT MANAGER ==="
        efibootmgr -v 2>/dev/null || echo "indisponible ou non-UEFI"
        echo ""
        echo "=== EFI PARTITION CONTENTS ==="
        for efi_dir in /boot/efi /efi; do
            if [[ -d "$efi_dir/EFI" ]]; then
                echo "$efi_dir/EFI:"
                find "$efi_dir/EFI" -maxdepth 3 | sort
            fi
        done
        echo ""
        echo "=== GRUB CONFIGURATION ==="
        for cfg in /etc/default/grub /boot/grub/grub.cfg /boot/grub2/grub.cfg; do
            [[ -f "$cfg" ]] && echo "--- $cfg ---" && cat "$cfg"
        done
        echo ""
        echo "=== SYSTEMD-BOOT ==="
        if command_exists bootctl; then
            bootctl status 2>/dev/null || echo "systemd-boot non installé"
            echo ""
            bootctl list 2>/dev/null || echo "aucune entrée"
        else
            echo "bootctl non disponible"
        fi
        for esp in /boot/efi /efi /boot; do
            if [[ -f "${esp}/loader/loader.conf" ]]; then
                echo "--- ${esp}/loader/loader.conf ---"
                cat "${esp}/loader/loader.conf" 2>/dev/null
                echo "--- ${esp}/loader/entries/ ---"
                ls -la "${esp}/loader/entries/" 2>/dev/null || echo "vide"
                for e in "${esp}/loader/entries/"*.conf; do
                    [[ -f "$e" ]] && echo "=== $e ===" && cat "$e"
                done
            fi
        done
        echo ""
        echo "=== WINDOWS / BCD ==="
        for efi_dir in /boot/efi /efi; do
            find "$efi_dir" -maxdepth 4 \( -iname 'bootmgfw.efi' -o -iname 'bcd' \) 2>/dev/null
        done
        lsblk -f 2>/dev/null | grep -i ntfs || echo "Aucune partition NTFS detectée"
        echo ""
        echo "=== RAID ==="
        cat /proc/mdstat 2>/dev/null || echo "indisponible"
        if command_exists mdadm; then
            mdadm --detail --scan 2>/dev/null || echo "aucun RAID mdadm détecté"
        fi
        echo ""
        echo "=== LVM ==="
        pvs 2>/dev/null || echo "aucun PV"
        vgs 2>/dev/null || echo "aucun VG"
        lvs 2>/dev/null || echo "aucun LV"
        echo ""
        echo "=== SECUREBOOT ==="
        mokutil --sb-state 2>/dev/null || echo "indisponible"
        echo ""
        echo "=== PROC/CMDLINE ==="
        cat /proc/cmdline 2>/dev/null
        echo ""
        echo "=== MBR SIGNATURES ==="
        if command_exists hexdump || command_exists xxd; then
            while read -r disk; do
                echo "/dev/$disk:"
                portable_hexdump "/dev/$disk" | tail -4 || echo "indisponible"
            done < <(lsblk -dn -o NAME 2>/dev/null | grep -vE '^(loop|ram|zram)')
        fi
        echo ""
        echo "=== SGDISK ==="
        if command_exists sgdisk; then
            while read -r disk; do
                echo "--- /dev/$disk ---"
                sgdisk --print "/dev/$disk" 2>/dev/null || echo "indisponible"
            done < <(lsblk -dn -o NAME 2>/dev/null | grep -vE '^(loop|ram)')
        fi
        echo ""
        echo "=== JOURNAL (errors) ==="
        journalctl -p 3 -xb --no-pager -n 30 2>/dev/null || echo "indisponible"
        echo ""
        echo "=== DMESG (errors) ==="
        dmesg --level=err,crit,alert,emerg 2>/dev/null | tail -30 || echo "indisponible"
    } | tee "$output_file"
    echo ""
    printf "%b\n" "${GREEN}${BOLD}╔══════════════════════════════════════════════════════════════════╗${NC}"
    printf "%b  %-66s%b\n" "${GREEN}${BOLD}║${NC}" "Boot-Info généré avec succès" "${GREEN}${BOLD}║${NC}"
    printf "%b  %-66s%b\n" "${GREEN}${BOLD}║${NC}" "Fichier local : $output_file" "${GREEN}${BOLD}║${NC}"
    printf "%b  %-66s%b\n" "${GREEN}${BOLD}║${NC}" "Journaux      : $LOG_FILE" "${GREEN}${BOLD}║${NC}"
    printf "%b  %-66s%b\n" "${GREEN}${BOLD}║${NC}" "Sauvegardes   : $BACKUP_DIR" "${GREEN}${BOLD}║${NC}"
    printf "%b\n" "${GREEN}${BOLD}╚══════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo "  Pour partager ce rapport sur un forum, lancez :"
    echo "  sudo $SCRIPT_NAME --advanced  → option 6 (upload en ligne)"
    echo ""
}

repair_windows_efi() {
    log_subheader "Restauration EFI Microsoft"
    local efi_dir=""
    for d in /boot/efi /efi; do
        [[ -d "$d/EFI" ]] && efi_dir="$d" && break
    done
    if [[ -z "$efi_dir" ]]; then
        log_error "Aucun répertoire EFI monté détecté"
        return 1
    fi
    local ms_efi="${efi_dir}/EFI/Microsoft/Boot/bootmgfw.efi"
    if [[ ! -f "$ms_efi" ]]; then
        log_info "bootmgfw.efi introuvable — aucun Windows dans la partition EFI"
        return 0
    fi
    if command_exists efibootmgr; then
        local ms_entry
        ms_entry=$(efibootmgr -v 2>/dev/null | grep -i 'Windows Boot Manager' | head -1 | grep -oE 'Boot[0-9A-Fa-f]{4}' | head -1)
        if [[ -n "$ms_entry" ]]; then
            local boot_num="${ms_entry#Boot}"
            if efibootmgr --bootnum "$boot_num" --active 2>/dev/null; then
                log_success "Entrée EFI Microsoft activée : $ms_entry"
            else
                log_warning "Impossible d'activer $ms_entry"
            fi
        else
            log_info "Entrée 'Windows Boot Manager' absente — création..."
            local disk part_src disk_dev part_num
            part_src=$(findmnt -n -o SOURCE "${efi_dir}" 2>/dev/null | head -1)
            disk_dev=$(lsblk -no PKNAME "$part_src" 2>/dev/null | head -1)
            part_num=$(lsblk -no PARTN "$part_src" 2>/dev/null | head -1)
            if [[ -z "$disk_dev" || -z "$part_num" ]]; then
                log_error "Impossible de déterminer le disque/numéro de partition EFI (disk_dev='${disk_dev}' part_num='${part_num}')"
            else
                if efibootmgr --create \
                    --disk "/dev/${disk_dev}" \
                    --part "${part_num}" \
                    --loader '\EFI\Microsoft\Boot\bootmgfw.efi' \
                    --label 'Windows Boot Manager' 2>/dev/null; then
                    log_success "Entrée EFI Windows Boot Manager créée"
                else
                    log_error "Échec de création de l'entrée EFI Windows"
                fi
            fi
        fi
    fi
    local efi_fallback="${efi_dir}/EFI/BOOT"
    mkdir -p "$efi_fallback"
    if ! diff -q "$ms_efi" "${efi_fallback}/bootx64.efi" &>/dev/null; then
        if cp "$ms_efi" "${efi_fallback}/bootx64.efi" 2>/dev/null; then
            log_success "bootmgfw.efi copié vers EFI/BOOT/bootx64.efi (fallback UEFI)"
        else
            log_warning "Échec copie fallback EFI"
        fi
    fi
    return 0
}

restore_windows_mbr() {
    local boot_device="$1"
    log_subheader "Restauration MBR compatible Windows"
    if command_exists ms-sys; then
        if ms-sys --mbr7 "$boot_device" 2>/dev/null; then
            log_success "MBR Windows 7/8/10/11 restauré sur $boot_device"
            return 0
        fi
    fi
    log_warning "ms-sys introuvable. Tentative d'installation..."
    if install_packages ms-sys 2>/dev/null; then
        if ms-sys --mbr7 "$boot_device" 2>/dev/null; then
            log_success "MBR Windows restauré sur $boot_device"
            return 0
        fi
    fi
    log_error "ms-sys non disponible : restauration MBR Windows impossible"
    return 1
}

repair_filesystem_health() {
    if ! command_exists fsck; then
        log_warning "fsck non disponible, réparation des systèmes de fichiers impossible"
        return 1
    fi

    log_subheader "Vérification des systèmes de fichiers"

    local root_device boot_device devices=()
    root_device=$(findmnt -n -o SOURCE / 2>/dev/null || true)
    boot_device=$(findmnt -n -o SOURCE /boot 2>/dev/null || true)

    if [[ -n "$root_device" ]]; then
        devices+=("$root_device")
    fi
    if [[ -n "$boot_device" ]] && [[ "$boot_device" != "$root_device" ]]; then
        devices+=("$boot_device")
    fi

    if [[ -f /etc/fstab ]]; then
        export point
        while read -r spec _mount point type rest; do
            [[ -z "$spec" || "$spec" == \#* ]] && continue
            case "$type" in
            swap | tmpfs | proc | sysfs | cgroup* | debugfs | devtmpfs | devpts | overlay)
                continue
                ;;
            esac
            if [[ "$spec" =~ ^/dev/ ]] && [[ " ${devices[*]} " != *" $spec "* ]]; then
                devices+=("$spec")
            fi
        done </etc/fstab
    fi

    local device mountpoint
    for device in "${devices[@]}"; do
        mountpoint=$(findmnt -n -o TARGET "$device" 2>/dev/null || true)

        if [[ -z "$mountpoint" ]]; then
            log_info "Périphérique non monté détecté : $device"
            if confirm_action "Exécuter fsck -f -y sur $device ? Cette opération peut réparer des erreurs sur le système de fichiers." strict; then
                fsck -f -y "$device" 2>&1 | while read -r line; do log_debug "$line"; done
                log_success "fsck appliqué sur $device"
            else
                log_warning "Réparation fsck annulée pour $device"
            fi
        else
            log_warning "$device est monté sur $mountpoint. Un fsck correct ne doit pas être exécuté sur un périphérique monté."
            log_info "Vérification en lecture seule du système de fichiers monté avec fsck -N sur $device"
            fsck -N "$device" 2>&1 | while read -r line; do log_debug "$line"; done
        fi
    done

    return 0
}

repair_grub() {
    local noninteractive="${1:-false}"
    log_subheader "Réparation du chargeur GRUB"

    if is_operation_completed "grub_repair"; then
        log_info "Réparation GRUB déjà effectuée durant cette session"
        return 0
    fi

    if [[ "$noninteractive" != "true" ]]; then
        if ! confirm_action "Cela va réinstaller et reconfigurer le chargeur GRUB.
Opération CRITIQUE. Assurez-vous d'avoir un support de récupération disponible." strict; then
            return 1
        fi
    fi

    if ! install_repair_dependencies; then
        log_error "Dépendances manquantes. Réparation annulée."
        return 1
    fi

    backup_partition_tables
    backup_grub_configuration

    local boot_device
    if [[ -n "$FORCE_DISK" ]]; then
        boot_device="$FORCE_DISK"
        log_info "Disque forcé par l'utilisateur : $boot_device"
    else
        boot_device=$(detect_boot_device)
    fi

    if [[ -z "$boot_device" ]]; then
        log_warning "Impossible de détecter automatiquement le périphérique de démarrage"
        echo ""
        echo "Périphériques de blocs disponibles :"
        lsblk -d -o NAME,SIZE,TYPE,MODEL | grep -E "^NAME|disk"
        echo ""
        read -r -p "Entrez le périphérique de démarrage (ex. /dev/sda) : " boot_device
        if [[ ! -b "$boot_device" ]]; then
            log_error "Périphérique invalide : $boot_device"
            return 1
        fi
    fi

    log_info "Utilisation du périphérique : $boot_device"

    local result=0
    case "$DISTRO_FAMILY" in
    debian)
        reinstall_grub_debian "$boot_device"
        result=$?
        ;;
    rhel)
        reinstall_grub_rhel "$boot_device"
        result=$?
        ;;
    arch)
        reinstall_grub_arch "$boot_device"
        result=$?
        ;;
    *)
        log_error "Réparation GRUB non prise en charge pour : $DISTRO_FAMILY"
        return 1
        ;;
    esac

    if [[ $result -eq 0 ]]; then
        log_success "Réparation du chargeur GRUB terminée avec succès"
        mark_operation_completed "grub_repair"
        repair_initramfs || log_warning "Régénération initramfs non disponible ou échouée"
        repair_filesystem_health
    else
        log_error "La réparation GRUB a échoué"
        log_info "Restauration possible depuis : $BACKUP_DIR"
    fi

    return $result
}

run_boot_repair() {
    log_header "RÉPARATION BOOT"
    repair_grub
}

run_recommended_repair() {
    log_header "RÉPARATION RECOMMANDÉE"
    log_info "Mode Recommended Repair — flux automatique sécurisé"
    echo ""
    run_environment_checks

    log_subheader "[1/5] Génération Boot-Info avant réparation"
    generate_boot_info "${BACKUP_DIR}/boot-info-pre-repair.txt"

    log_subheader "[2/5] Sauvegarde des tables de partitions"
    backup_partition_tables

    log_subheader "[3/5] Installation des dépendances"
    if ! install_repair_dependencies; then
        log_error "Dépendances manquantes. Réparation recommandée annulée."
        return 1
    fi

    log_subheader "[4/5] Réinstallation bootloader + initramfs"
    backup_grub_configuration
    local boot_device
    boot_device=$(detect_boot_device)
    if [[ -z "$boot_device" ]]; then
        log_error "Périphérique de démarrage introuvable. Réparation recommandée annulée."
        return 1
    fi
    log_info "Disque cible : $boot_device"

    local active_bl
    active_bl=$(detect_bootloader)
    log_info "Bootloader détecté : $active_bl"

    local boot_conf_present=false
    if [[ -f /boot/efi/loader/loader.conf ]] || [[ -f /efi/loader/loader.conf ]] || [[ -f /boot/loader/loader.conf ]]; then
        boot_conf_present=true
    fi

    local result=0
    if [[ "$active_bl" == "systemd-boot" ]] || { [[ "$active_bl" == "both" ]] && [[ "$boot_conf_present" == true ]]; }; then
        log_info "systemd-boot détecté — réparation via bootctl"
        repair_systemd_boot || result=$?
    elif [[ "$active_bl" == "both" ]]; then
        log_warning "Les deux bootloaders détectés (GRUB + systemd-boot) — réparation GRUB uniquement en mode recommandé"
        case "$DISTRO_FAMILY" in
        debian)
            reinstall_grub_debian "$boot_device"
            result=$?
            ;;
        rhel)
            reinstall_grub_rhel "$boot_device"
            result=$?
            ;;
        arch)
            reinstall_grub_arch "$boot_device"
            result=$?
            ;;
        *)
            log_error "Distribution non prise en charge : $DISTRO_FAMILY"
            result=1
            ;;
        esac
    else
        case "$DISTRO_FAMILY" in
        debian)
            reinstall_grub_debian "$boot_device"
            result=$?
            ;;
        rhel)
            reinstall_grub_rhel "$boot_device"
            result=$?
            ;;
        arch)
            reinstall_grub_arch "$boot_device"
            result=$?
            ;;
        *)
            log_error "Distribution non prise en charge : $DISTRO_FAMILY"
            result=1
            ;;
        esac
    fi

    if [[ $result -ne 0 ]]; then
        log_error "Réparation du chargeur a échoué"
        return $result
    fi

    repair_initramfs || log_warning "Initramfs : échec ou non disponible"
    mark_operation_completed "grub_repair"

    log_subheader "[4b/6] Vérification Secure Boot"
    local sb_state
    sb_state=$(check_secure_boot_status)
    if [[ "$sb_state" == *"enabled"* ]]; then
        log_warning "Secure Boot actif. Si le système ne démarre pas après réparation,"
        log_warning "lancez : sudo $0 --advanced → option 11 (MOK enrollment)"
    fi

    log_subheader "[5/6] Détection Windows / EFI Microsoft"
    local boot_mode
    boot_mode=$(detect_boot_mode)
    if [[ "$boot_mode" == "uefi" ]]; then
        repair_windows_efi
    else
        log_info "Mode BIOS/Legacy — vérification Windows MBR non applicable en mode automatique"
    fi

    log_subheader "[6/6] Génération Boot-Info post-réparation"
    generate_boot_info "${BACKUP_DIR}/boot-info-post-repair.txt"

    log_success "Recommended Repair terminé"
    log_info "Boot-Info avant : ${BACKUP_DIR}/boot-info-pre-repair.txt"
    log_info "Boot-Info après : ${BACKUP_DIR}/boot-info-post-repair.txt"
    log_info "Sauvegardes     : ${BACKUP_DIR}"
    echo ""
    read -r -p "Uploader les rapports en ligne pour partage forum ? [o/N] : " do_upload
    if [[ "${do_upload,,}" == "o" || "${do_upload,,}" == "oui" || "${do_upload,,}" == "y" ]]; then
        upload_report "${BACKUP_DIR}/boot-info-post-repair.txt"
    fi
}

run_advanced_repair() {
    log_header "MENU AVANCÉ"
    run_environment_checks

    _list_disks() {
        echo ""
        printf "%b\n" "${CYAN}${BOLD}Disques détectés sur ce système :${NC}"
        echo "───────────────────────────────────────────────────────────"
        lsblk -d -o NAME,SIZE,TYPE,TRAN,MODEL,SERIAL 2>/dev/null |
            grep -v "^loop" |
            awk 'NR==1 {print "  "$0} NR>1 {print "  /dev/"$0}'
        echo "───────────────────────────────────────────────────────────"
        echo ""
    }

    local boot_device
    while true; do
        echo ""
        printf "%b\n" "${BOLD}╔══════════════════════════════════════════════════════════════════════╗${NC}"
        printf "%b\n" "${BOLD}║                       OPTIONS AVANCÉES                              ║${NC}"
        printf "%b\n" "${BOLD}╠══════════════════════════════════════════════════════════════════════╣${NC}"
        printf "%b\n" "${BOLD}║${NC}  1)  Choisir le disque cible + réinstaller GRUB                    ${BOLD}║${NC}"
        printf "%b\n" "${BOLD}║${NC}  2)  Purge + réinstallation complète de GRUB                       ${BOLD}║${NC}"
        printf "%b\n" "${BOLD}║${NC}  3)  Restaurer table de partitions (sfdisk ou sgdisk)              ${BOLD}║${NC}"
        printf "%b\n" "${BOLD}║${NC}  4)  Restauration MBR compatible Windows                          ${BOLD}║${NC}"
        printf "%b\n" "${BOLD}║${NC}  5)  Restauration entrée EFI Microsoft                            ${BOLD}║${NC}"
        printf "%b\n" "${BOLD}║${NC}  6)  Générer Boot-Info + upload en ligne                          ${BOLD}║${NC}"
        printf "%b\n" "${BOLD}║${NC}  7)  Réparation via chroot (depuis live USB)                      ${BOLD}║${NC}"
        printf "%b\n" "${BOLD}║${NC}  8)  Configurer options menu GRUB                                 ${BOLD}║${NC}"
        printf "%b\n" "${BOLD}║${NC}  9)  Réparer systemd-boot                                          ${BOLD}║${NC}"
        printf "%b\n" "${BOLD}║${NC}  10) État RAID / LVM                                              ${BOLD}║${NC}"
        printf "%b\n" "${BOLD}║${NC}  11) Secure Boot — état, MOK enrollment, signature EFI            ${BOLD}║${NC}"
        printf "%b\n" "${BOLD}║${NC}  12) Retour                                                       ${BOLD}║${NC}"
        printf "%b\n" "${BOLD}╚══════════════════════════════════════════════════════════════════════╝${NC}"
        echo ""
        read -r -p "Choix [1-12] : " adv_choice
        case "$adv_choice" in
        1)
            _list_disks
            read -r -p "Disque cible pour GRUB (ex. /dev/sda) : " FORCE_DISK
            if [[ ! -b "$FORCE_DISK" ]]; then
                log_error "Périphérique invalide : $FORCE_DISK"
                FORCE_DISK=""
                return 1
            fi
            log_info "Disque sélectionné : $FORCE_DISK"
            repair_grub
            FORCE_DISK=""
            ;;
        2)
            _list_disks
            echo "La purge supprime tous les paquets GRUB puis les réinstalle."
            echo "Les tables de partitions et la config GRUB seront sauvegardées au préalable."
            echo ""
            if confirm_action "Purge GRUB puis réinstallation complète. Opération destructive." strict; then
                backup_partition_tables
                backup_grub_configuration
                purge_grub
                COMPLETED_OPERATIONS["grub_repair"]=""
                repair_grub
            fi
            ;;
        3)
            echo ""
            echo "  Format de sauvegarde à restaurer :"
            echo "  1)  sfdisk  (.dump) — recommandé pour MBR/DOS/GPT simple"
            echo "  2)  sgdisk  (.bin)  — GPT uniquement, restaure header + backup GPT"
            echo ""
            read -r -p "Choix [1-2] : " pt_fmt
            case "$pt_fmt" in
            1)
                local bpt_dir="${BACKUP_DIR}/partition-tables"
                if [[ ! -d "$bpt_dir" ]]; then
                    log_error "Aucune sauvegarde disponible dans $bpt_dir"
                    log_info "Exécutez d'abord une réparation pour créer une sauvegarde."
                    return 1
                fi
                echo ""
                printf "%b\n" "${CYAN}${BOLD}Sauvegardes de tables de partitions disponibles :${NC}"
                echo "───────────────────────────────────────────────────────────"
                find "$bpt_dir" -maxdepth 1 -name '*.dump' \
                    -printf '  %f  (%s bytes)\n' 2>/dev/null | sort
                echo "───────────────────────────────────────────────────────────"
                read -r -p "Nom du fichier .dump sfdisk à restaurer : " dump_file
                local full_path="${bpt_dir}/${dump_file}"
                if [[ ! -f "$full_path" ]]; then
                    log_error "Fichier introuvable : $full_path"
                    return 1
                fi
                _list_disks
                read -r -p "Disque cible pour la restauration (ex. /dev/sda) : " target_disk
                if [[ ! -b "$target_disk" ]]; then
                    log_error "Périphérique invalide : $target_disk"
                    return 1
                fi
                if confirm_action "Restaurer $full_path sur $target_disk ? Écrase entièrement la table de partitions." strict; then
                    if sfdisk "$target_disk" <"$full_path"; then
                        log_success "Table de partitions restaurée sur $target_disk"
                    else
                        log_error "Échec de restauration sfdisk"
                    fi
                fi
                ;;
            2)
                restore_partition_table_sgdisk
                ;;
            *)
                log_warning "Choix invalide"
                ;;
            esac
            ;;
        4)
            echo ""
            echo "La restauration MBR Windows remplace le MBR du disque par un"
            echo "MBR compatible Windows 7/8/10/11 via ms-sys."
            echo ""
            _list_disks
            boot_device=$(detect_boot_device)
            if [[ -n "$boot_device" ]]; then
                log_info "Disque détecté automatiquement : $boot_device"
                read -r -p "Confirmer ce disque ou saisir un autre (Entrée = $boot_device) : " override
                [[ -n "$override" ]] && boot_device="$override"
            else
                read -r -p "Disque cible pour MBR Windows (ex. /dev/sda) : " boot_device
            fi
            if [[ ! -b "$boot_device" ]]; then
                log_error "Périphérique invalide : $boot_device"
                return 1
            fi
            restore_windows_mbr "$boot_device"
            ;;
        5)
            echo ""
            echo "Détection et restauration de l'entrée EFI Microsoft (bootmgfw.efi)."
            echo "Nécessite une partition EFI montée sur /boot/efi ou /efi."
            echo ""
            repair_windows_efi
            ;;
        6)
            local bi_file="${BACKUP_DIR}/boot-info.txt"
            generate_boot_info "$bi_file"
            echo ""
            read -r -p "Uploader le rapport en ligne pour partage forum ? [o/N] : " do_upload
            if [[ "${do_upload,,}" == "o" || "${do_upload,,}" == "oui" || "${do_upload,,}" == "y" ]]; then
                upload_report "$bi_file"
            fi
            ;;
        7)
            echo ""
            echo "La réparation via chroot permet de réparer GRUB sur un système installé"
            echo "depuis un live USB, sans avoir à démarrer sur le système en panne."
            echo ""
            repair_in_chroot
            ;;
        8)
            configure_grub_menu_options
            ;;
        9)
            repair_systemd_boot
            ;;
        10)
            echo ""
            printf "%b\n" "${CYAN}${BOLD}État RAID (mdadm) :${NC}"
            echo "───────────────────────────────────────────────────────────"
            cat /proc/mdstat 2>/dev/null || echo "  /proc/mdstat indisponible"
            if command_exists mdadm; then
                echo ""
                mdadm --detail --scan 2>/dev/null || echo "  Aucun RAID mdadm"
            fi
            echo ""
            printf "%b\n" "${CYAN}${BOLD}État LVM :${NC}"
            echo "───────────────────────────────────────────────────────────"
            pvs 2>/dev/null || echo "  pvs : indisponible"
            vgs 2>/dev/null || echo "  vgs : indisponible"
            lvs 2>/dev/null || echo "  lvs : indisponible"
            echo "───────────────────────────────────────────────────────────"
            ;;
        11)
            enroll_mok_key
            ;;
        12)
            return 0
            ;;
        *)
            log_warning "Choix invalide"
            ;;
        esac
        echo ""
        read -r -p "Appuyez sur Entrée pour continuer..."
    done
}

#-------------------------------------------------------------------------------
# MAIN MENU AND EXECUTION
#-------------------------------------------------------------------------------
show_banner() {
    clear
    printf "%b\n" "${CYAN}${BOLD}"
    cat <<'BANNER'
░█████████  ░██████████ ░█████████          ░███████   ░██████████ ░███     ░███ 
░██     ░██ ░██         ░██     ░██         ░██   ░██  ░██         ░████   ░████ 
░██     ░██ ░██         ░██     ░██         ░██    ░██ ░██         ░██░██ ░██░██ 
░█████████  ░█████████  ░█████████  ░██████ ░██    ░██ ░█████████  ░██ ░████ ░██ 
░██   ░██   ░██         ░██                 ░██    ░██ ░██         ░██  ░██  ░██ 
░██    ░██  ░██         ░██                 ░██   ░██  ░██         ░██       ░██ 
░██     ░██ ░██████████ ░██                 ░███████   ░██████████ ░██       ░██ 
                                                                            
BANNER
    printf "%b\n" "${NC}"
    printf "%b\n" "${WHITE}   Outil de réparation boot Linux${NC}"
    printf "%b\n" "${DIM}   Version $SCRIPT_VERSION | Qualité production${NC}"
    echo ""
}

show_menu() {
    echo ""
    printf "%b\n" "${BOLD}╔════════════════════════════════════════════════════════════════════════╗${NC}"
    printf "%b\n" "${BOLD}║                         MENU PRINCIPAL                                ║${NC}"
    printf "%b\n" "${BOLD}╠════════════════════════════════════════════════════════════════════════╣${NC}"
    printf "%b\n" "${BOLD}║${NC}  1)  Réparation recommandée (automatique, sécurisée)                   ${BOLD}║${NC}"
    printf "%b\n" "${BOLD}║${NC}  2)  Réparation boot interactive                                       ${BOLD}║${NC}"
    printf "%b\n" "${BOLD}║${NC}  3)  Options avancées (disque, purge, chroot, EFI, RAID...)            ${BOLD}║${NC}"
    printf "%b\n" "${BOLD}║${NC}  4)  Générer Boot-Info (rapport + upload)                              ${BOLD}║${NC}"
    printf "%b\n" "${BOLD}║${NC}  5)  Rapport brut lecture seule                                        ${BOLD}║${NC}"
    if [[ "${_INSIDE_CHROOT}" == false ]]; then
        printf "%b\n" "${BOLD}║${NC}  6)  Live ISO — auto-chroot détection (réparer depuis live USB)       ${BOLD}║${NC}"
        printf "%b\n" "${BOLD}║${NC}  7)  Quitter                                                          ${BOLD}║${NC}"
    else
        printf "%b\n" "${BOLD}║${NC}  6)  Quitter                                                          ${BOLD}║${NC}"
        printf "%b\n" "${YELLOW}║${NC}      [Mode chroot actif — Live ISO non disponible ici]               ${BOLD}║${NC}"
    fi
    printf "%b\n" "${BOLD}╚════════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

show_help() {
    cat <<HELP
UTILISATION : $SCRIPT_NAME [OPTION]

Outil de réparation boot Linux – Version $SCRIPT_VERSION
Équivalent CLI de Boot-Repair, multi-distro, sans interface graphique.
Supportes : GRUB 2 (BIOS + UEFI) et systemd-boot (UEFI).

OPTIONS :
    --recommended       Réparation automatique en 6 étapes sécurisées
    --boot              Réparation GRUB interactive avec confirmations
    --advanced          Menu avancé 12 options
    --boot-info [FILE]  Génère un rapport Boot-Info complet (défaut : ${BACKUP_DIR}/boot-info.txt)
    --analyze           Rapport brut système en lecture seule (stdout)
    --output FILE       Exporte le rapport brut vers FILE
    --live-chroot       Scan auto + chroot depuis un Live ISO (réparer le système installé)
    --inside-chroot     Usage interne — lancé automatiquement par --live-chroot
    --help, -h          Affiche ce message d'aide
    --version, -v       Affiche la version du script

EXEMPLES :
    sudo $SCRIPT_NAME
        Lance le menu interactif principal

    sudo $SCRIPT_NAME --recommended
        Réparation sécurisée automatique :
        Boot-Info avant → sauvegarde tables → dépendances → bootloader → Windows/EFI → Boot-Info après

    sudo $SCRIPT_NAME --boot
        Réparation GRUB interactive avec confirmations

    sudo $SCRIPT_NAME --advanced
        Menu avancé : purge, disque, chroot (live USB), GRUB, systemd-boot, RAID, MBR Windows, EFI

    sudo $SCRIPT_NAME --boot-info /tmp/mon-rapport.txt
        Génère un rapport Boot-Info vers le fichier spécifié

    sudo $SCRIPT_NAME --analyze --output rapport.txt
        Rapport brut lecture seule enregistré dans rapport.txt

    sudo $SCRIPT_NAME --live-chroot
        Depuis un Live USB/ISO : scan auto des OS installés, montage, bind mounts,
        relancement du script à l'intérieur du chroot pour réparer le vrai système.

MENU AVANCÉ (--advanced) :
    1)   Choisir disque cible + réinstaller GRUB
    2)   Purge + réinstallation complète de GRUB
    3)   Restaurer table de partitions (sfdisk ou sgdisk)
    4)   Restauration MBR compatible Windows (ms-sys)
    5)   Restauration entrée EFI Microsoft (bootmgfw.efi)
    6)   Générer Boot-Info + upload en ligne
    7)   Réparation via chroot (depuis live USB)
    8)   Configurer options menu GRUB (timeout, nomodeset, résolution...)
    9)   Réparer systemd-boot (install, mise à jour, entrées, UUID, crypttab)
    10)  État RAID (mdadm) + LVM
    11)  Secure Boot — état, MOK enrollment, signature EFI
    12)  Retour

BOOTLOADERS SUPPORTÉS :
    GRUB 2     : Debian/Ubuntu/Mint, Fedora/RHEL/Rocky/Alma, Arch/Manjaro, openSUSE, Void, Gentoo
    systemd-boot : Pop!_OS 18.04+, Ubuntu 24.04+, Fedora (UEFI), Arch (UEFI)
    Détection automatique : grub.cfg, loader.conf, EFI binaires, efibootmgr, ID distro

DÉPENDANCES REQUISES (installées automatiquement si absentes) :
    GRUB/BIOS   : grub-pc
    GRUB/UEFI   : grub-efi-amd64, grub-efi-amd64-signed, shim-signed, efibootmgr
    systemd-boot: bootctl (inclus dans systemd), kernel-install (optionnel)
    initramfs   : update-initramfs (Debian), dracut (RHEL), mkinitcpio (Arch)
    Rapport     : curl, hexdump, sgdisk, sfdisk, parted, mdadm, lvm2
    Chroot      : mount, chroot, findmnt, blkid
    Windows MBR : ms-sys

UPLOAD RAPPORT (option 6) :
    3 services en parallèle, sans compte requis :
    paste.ubuntu.com  — texte, permanent
    dpaste.com        — texte, 7 jours
    gofile.io         — fichier, grand format
    Les 3 liens s'affichent à l'écran et sont écrits dans le rapport local.

SAUVEGARDES :
    $BACKUP_DIR
    Contenu : tables de partitions (sgdisk+sfdisk+dd MBR), config GRUB,
              ESP (pour systemd-boot), Boot-Info avant et après réparation.

JOURNAUX :
    $LOG_FILE

HELP
}

#-------------------------------------------------------------------------------
# MODULE : VÉRIFICATION OUTILS REQUIS (Live ISO)
#-------------------------------------------------------------------------------
check_required_tools() {
    local -a required=("lsblk" "blkid" "mount" "umount" "chroot" "findmnt")
    local -a recommended=("sgdisk" "curl" "efibootmgr" "rsync")
    local -a missing_req=() missing_rec=()

    log_subheader "Vérification des outils requis"
    for tool in "${required[@]}"; do
        command_exists "$tool" || missing_req+=("$tool")
    done
    for tool in "${recommended[@]}"; do
        command_exists "$tool" || missing_rec+=("$tool")
    done

    if ((${#missing_req[@]} > 0)); then
        log_error "Outils obligatoires manquants : ${missing_req[*]}"
        log_error "Impossible de continuer sans ces outils."
        return 1
    fi
    log_success "Outils obligatoires : tous présents"

    if ((${#missing_rec[@]} > 0)); then
        log_warning "Outils recommandés absents : ${missing_rec[*]}"
        confirm_action "Installer ces outils temporairement sur le Live ISO ?" yes || {
            log_warning "Certaines opérations pourraient être limitées."
            return 0
        }
        local live_pm=""
        command_exists apt-get && live_pm="apt-get"
        command_exists pacman && [[ -z "$live_pm" ]] && live_pm="pacman"
        command_exists dnf && [[ -z "$live_pm" ]] && live_pm="dnf"
        command_exists zypper && [[ -z "$live_pm" ]] && live_pm="zypper"
        if [[ -z "$live_pm" ]]; then
            log_warning "Gestionnaire de paquets introuvable sur le Live ISO."
            return 0
        fi
        log_info "Installation via $live_pm : ${missing_rec[*]}"
        case "$live_pm" in
        apt-get) apt-get install -y "${missing_rec[@]}" 2>&1 | while read -r l; do log_debug "$l"; done ;;
        pacman) pacman -Sy --noconfirm "${missing_rec[@]}" 2>&1 | while read -r l; do log_debug "$l"; done ;;
        dnf) dnf install -y "${missing_rec[@]}" 2>&1 | while read -r l; do log_debug "$l"; done ;;
        zypper) zypper install -y "${missing_rec[@]}" 2>&1 | while read -r l; do log_debug "$l"; done ;;
        esac
        log_success "Installation des outils recommandés terminée"
    else
        log_success "Outils recommandés : tous présents"
    fi
    return 0
}

#-------------------------------------------------------------------------------
# MODULE : NETTOYAGE AUTO-CHROOT (appelé par le trap global)
#-------------------------------------------------------------------------------
_autochroot_cleanup() {
    local target="${CHROOT_TARGET:-}"
    [[ -z "$target" || ! -d "$target" ]] && return 0
    log_info "Démontage du chroot automatique : $target"
    local -a submounts=(
        "${target}/sys/firmware/efi/efivars"
        "${target}/run"
        "${target}/sys"
        "${target}/proc"
        "${target}/dev/pts"
        "${target}/dev"
        "${target}/boot/efi"
        "${target}/boot"
    )
    for sub in "${submounts[@]}"; do
        mountpoint -q "$sub" 2>/dev/null &&
            { umount -lf "$sub" 2>/dev/null && log_info "  Démonté : $sub"; } || true
    done
    mountpoint -q "$target" 2>/dev/null &&
        { umount -lf "$target" 2>/dev/null && log_success "Partition root démontée : $target"; } || true
    CHROOT_TARGET=""
}

#-------------------------------------------------------------------------------
# MODULE : AUTO-SCAN ET CHROOT DEPUIS UN LIVE ISO
#-------------------------------------------------------------------------------
auto_scan_and_chroot() {
    log_header "AUTO-CHROOT DÉTECTION — MODE LIVE ISO"
    echo ""
    check_required_tools || return 1

    local target_dir="/mnt/target"

    # Si déjà monté, proposer de démonter
    if mountpoint -q "$target_dir" 2>/dev/null; then
        log_warning "$target_dir est déjà utilisé comme point de montage."
        confirm_action "Démonter et réutiliser $target_dir ?" strict || return 1
        CHROOT_TARGET="$target_dir"
        _autochroot_cleanup
    fi
    mkdir -p "$target_dir"

    log_info "Scan des partitions (ext2/3/4, btrfs, xfs, f2fs, jfs, reiserfs)..."
    echo ""

    local tmp_mnt
    tmp_mnt=$(mktemp -d /tmp/rd_scan_XXXXXX)
    local idx=0
    declare -A scan_map
    local -a found_systems=()

    while read -r dev; do
        [[ -b "$dev" ]] || continue
        local fstype
        fstype=$(blkid -s TYPE -o value "$dev" 2>/dev/null)
        case "$fstype" in
        ext2 | ext3 | ext4 | btrfs | xfs | f2fs | jfs | reiserfs) ;;
        *) continue ;;
        esac
        if mount -o ro,noatime "$dev" "$tmp_mnt" 2>/dev/null; then
            if [[ -f "$tmp_mnt/etc/os-release" ]]; then
                idx=$((idx + 1))
                local name uuid
                name=$(grep -m1 '^PRETTY_NAME=' "$tmp_mnt/etc/os-release" 2>/dev/null |
                    tr -d '"' | cut -d= -f2-)
                uuid=$(blkid -s UUID -o value "$dev" 2>/dev/null || echo "—")
                scan_map[$idx]="$dev"
                found_systems+=("$(printf "  %2d)  %-22s  %-30s  UUID: %s" \
                    "$idx" "$dev" "${name:-Linux}" "$uuid")")
            fi
            umount "$tmp_mnt" 2>/dev/null || true
        fi
    done < <(lsblk -lno PATH,TYPE 2>/dev/null | awk '$2=="part"{print $1}' | sort)
    rmdir "$tmp_mnt" 2>/dev/null || true

    if ((${#found_systems[@]} == 0)); then
        log_error "Aucun système Linux détecté sur les partitions disponibles."
        echo ""
        echo "  Partitions visibles :"
        lsblk -lno NAME,SIZE,FSTYPE,TYPE | awk '$4=="part"{print "  /dev/"$0}' || true
        return 1
    fi

    printf "%b\n" "${CYAN}${BOLD}Systèmes Linux détectés :${NC}"
    echo "────────────────────────────────────────────────────────────────────────────"
    printf '%s\n' "${found_systems[@]}"
    echo "────────────────────────────────────────────────────────────────────────────"
    echo ""

    local chosen_num root_dev
    while true; do
        read -r -p "Numéro du système à réparer [1-${idx}] : " chosen_num
        root_dev="${scan_map[$chosen_num]:-}"
        [[ -b "$root_dev" ]] && break
        log_warning "Sélection invalide. Entrez un numéro entre 1 et $idx."
    done

    log_info "Système sélectionné : $root_dev"

    # --- Montage partition root ---
    log_info "Montage de $root_dev sur $target_dir..."
    if ! mount "$root_dev" "$target_dir"; then
        log_error "Impossible de monter $root_dev sur $target_dir"
        return 1
    fi
    CHROOT_TARGET="$target_dir" # enregistré pour le trap global

    # --- Partitions séparées via /etc/fstab du système cible ---
    if [[ -f "$target_dir/etc/fstab" ]]; then
        log_info "Analyse de $target_dir/etc/fstab pour les partitions séparées..."
        while read -r spec mountpt fstype _opts _dump _pass; do
            [[ -z "$spec" || "$spec" == \#* ]] && continue
            [[ "$mountpt" == "/" ]] && continue
            case "$fstype" in
            swap | tmpfs | proc | sysfs | devtmpfs | devpts | overlay | cgroup* | none | auto) continue ;;
            esac
            local real_dev=""
            case "$spec" in
            UUID=*) real_dev=$(blkid -U "${spec#UUID=}" 2>/dev/null) ;;
            PARTUUID=*) real_dev=$(blkid -l -t PARTUUID="${spec#PARTUUID=}" -o device 2>/dev/null) ;;
            LABEL=*) real_dev=$(blkid -L "${spec#LABEL=}" 2>/dev/null) ;;
            /dev/*) real_dev="$spec" ;;
            esac
            if [[ -n "$real_dev" && -b "$real_dev" ]]; then
                local full_mp="${target_dir}${mountpt}"
                mkdir -p "$full_mp"
                if mount "$real_dev" "$full_mp" 2>/dev/null; then
                    log_info "  Monté : $real_dev → $mountpt"
                else
                    log_warning "  Échec montage : $real_dev → $mountpt"
                fi
            fi
        done <"$target_dir/etc/fstab"
    fi

    # --- Bind mounts : /dev /dev/pts /proc /sys /run ---
    log_info "Bind mounts des systèmes de fichiers virtuels..."
    for vfs in /dev /dev/pts /proc /sys /run; do
        local bind_tgt="${target_dir}${vfs}"
        mkdir -p "$bind_tgt"
        if mount --rbind "$vfs" "$bind_tgt" 2>/dev/null; then
            mount --make-rslave "$bind_tgt" 2>/dev/null || true
            log_info "  rbind : $vfs"
        else
            if mount --bind "$vfs" "$bind_tgt" 2>/dev/null; then
                log_info "  bind  : $vfs (fallback)"
            else
                log_warning "  Échec bind : $vfs"
            fi
        fi
    done

    # efivars si UEFI
    if [[ -d /sys/firmware/efi/efivars ]]; then
        local efivars_tgt="${target_dir}/sys/firmware/efi/efivars"
        mkdir -p "$efivars_tgt"
        if mount --bind /sys/firmware/efi/efivars "$efivars_tgt" 2>/dev/null; then
            log_info "  bind  : efivars"
        else
            log_warning "  Échec bind : efivars"
        fi
    fi

    # --- Copie du script dans le chroot ---
    local script_name
    script_name="$(basename "$0")"
    local script_in_chroot="${target_dir}/tmp/Rep-Dem"
    mkdir -p "$script_in_chroot"
    if ! cp "$0" "${script_in_chroot}/${script_name}"; then
        log_error "Impossible de copier le script dans le chroot"
        _autochroot_cleanup
        return 1
    fi
    chmod +x "${script_in_chroot}/${script_name}"

    echo ""
    log_success "Environnement chroot prêt. Lancement de la réparation sur $root_dev..."
    printf "%b\n" "${YELLOW}${BOLD}[CHROOT]${NC} Les commandes suivantes s'exécutent sur le système installé."
    echo ""

    # --- Relancement du script à l'intérieur du chroot ---
    chroot "$target_dir" /bin/bash "/tmp/Rep-Dem/${script_name}" --inside-chroot
    local chroot_exit=$?

    log_info "Session chroot terminée (code : $chroot_exit)"
    _autochroot_cleanup
    return $chroot_exit
}

main() {
    case "${1:-}" in
    --analyze)
        ANALYZE_MODE=true
        if [[ "${2:-}" == "--output" ]]; then
            OUTPUT_FILE="${3:-}"
            [[ -z "$OUTPUT_FILE" ]] && {
                log_error "Fichier de sortie manquant"
                exit 1
            }
        fi
        generate_raw_report
        exit 0
        ;;
    --output)
        OUTPUT_FILE="${2:-}"
        [[ -z "$OUTPUT_FILE" ]] && {
            log_error "Fichier de sortie manquant"
            exit 1
        }
        ANALYZE_MODE=true
        generate_raw_report
        exit 0
        ;;
    --help | -h)
        show_help
        exit 0
        ;;
    --version | -v)
        echo "$SCRIPT_NAME version $SCRIPT_VERSION"
        exit 0
        ;;
    --recommended)
        show_banner
        run_recommended_repair
        exit $?
        ;;
    --boot)
        show_banner
        run_environment_checks
        run_boot_repair
        exit $?
        ;;
    --advanced)
        show_banner
        run_advanced_repair
        exit $?
        ;;
    --boot-info)
        run_environment_checks
        generate_boot_info "${2:-${BACKUP_DIR}/boot-info.txt}"
        exit 0
        ;;
    --live-chroot)
        show_banner
        auto_scan_and_chroot
        exit $?
        ;;
    --inside-chroot)
        # Lancé automatiquement par auto_scan_and_chroot à l'intérieur du chroot
        _INSIDE_CHROOT=true
        show_banner
        printf "%b\n" "${YELLOW}${BOLD}[CHROOT]${NC} Vous opérez sur le système installé — pas sur le Live ISO."
        echo ""
        run_environment_checks
        while true; do
            show_menu
            read -r -p "Entrez votre choix [1-6] : " menu_choice
            case "$menu_choice" in
            1) run_recommended_repair ;;
            2) run_boot_repair ;;
            3) run_advanced_repair ;;
            4) generate_boot_info ;;
            5)
                ANALYZE_MODE=true
                generate_raw_report
                ;;
            6)
                echo ""
                log_info "Fermeture du chroot. À bientôt !"
                echo ""
                exit 0
                ;;
            *) log_warning "Choix invalide. Veuillez entrer 1-6." ;;
            esac
            echo ""
            read -r -p "Appuyez sur Entrée pour continuer..."
        done
        ;;
    "")
        show_banner
        run_environment_checks
        while true; do
            show_menu
            read -r -p "Entrez votre choix [1-7] : " menu_choice
            case "$menu_choice" in
            1) run_recommended_repair ;;
            2) run_boot_repair ;;
            3) run_advanced_repair ;;
            4) generate_boot_info ;;
            5)
                ANALYZE_MODE=true
                generate_raw_report
                ;;
            6) auto_scan_and_chroot ;;
            7)
                echo ""
                log_info "Fermeture. À bientôt !"
                echo ""
                exit 0
                ;;
            *) log_warning "Choix invalide. Veuillez entrer 1-7." ;;
            esac
            echo ""
            read -r -p "Appuyez sur Entrée pour continuer..."
        done
        ;;
    *)
        log_error "Option inconnue : $1"
        echo "Utilisez --help pour obtenir des informations d'utilisation"
        exit 1
        ;;
    esac
}

main "$@"
