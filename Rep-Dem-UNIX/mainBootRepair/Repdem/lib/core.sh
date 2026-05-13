#!/usr/bin/env bash
#===============================================================================
#  core.sh — Logging, utilitaires, détection système, gestion paquets
#  Sourcé automatiquement par Rep-Dem.sh
#===============================================================================

#-------------------------------------------------------------------------------
# COULEURS
#-------------------------------------------------------------------------------
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

#-------------------------------------------------------------------------------
# LOGGING
#-------------------------------------------------------------------------------
get_timestamp() { date '+%Y-%m-%d %H:%M:%S'; }

log_to_file() {
    local level="$1" message="$2"
    if [[ -w "$(dirname "$LOG_FILE")" ]] || [[ -w "$LOG_FILE" ]]; then
        echo "[$(get_timestamp)] [$level] $message" >> "$LOG_FILE" 2>/dev/null
    fi
}

log_info()    { printf "%b%s\n" "${BLUE}[INFO]${NC}"      "$1"; log_to_file "INFO"      "$1"; }
log_success() { printf "%b%s\n" "${GREEN}[SUCCES]${NC}"   "$1"; log_to_file "SUCCÈS"    "$1"; }
log_warning() { printf "%b%s\n" "${YELLOW}[ATTENTION]${NC}" "$1"; log_to_file "ATTENTION" "$1"; }
log_error()   { printf "%b%s\n" "${RED}[ERREUR]${NC}"    "$1" >&2; log_to_file "ERREUR"   "$1"; }

log_debug() {
    [[ "${DEBUG:-false}" == "true" ]] || return 0
    printf "%b%s\n" "${DIM}[DÉBOGAGE]${NC}" "$1"
    log_to_file "DÉBOGAGE" "$1"
}

log_header() {
    local title="$1" width=78
    local padding=$(( (width - ${#title} - 2) / 2 ))
    echo ""
    printf "%b\n" "${CYAN}${BOLD}$(printf '═%.0s' $(seq 1 $width))${NC}"
    printf "%b\n" "${CYAN}${BOLD}$(printf ' %.0s' $(seq 1 $padding)) $title $(printf ' %.0s' $(seq 1 $padding))${NC}"
    printf "%b\n" "${CYAN}${BOLD}$(printf '═%.0s' $(seq 1 $width))${NC}"
    echo ""
    log_to_file "HEADER" "=== $title ==="
}

log_subheader() {
    echo ""
    printf "%b\n" "${MAGENTA}${BOLD}─── $1 ───${NC}"
    echo ""
}

#-------------------------------------------------------------------------------
# UTILITAIRES GÉNÉRIQUES
#-------------------------------------------------------------------------------
command_exists() { command -v "$1" &>/dev/null; }

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

is_operation_completed()  { [[ "${COMPLETED_OPERATIONS[$1]:-}" == "true" ]]; }
mark_operation_completed() { COMPLETED_OPERATIONS[$1]="true"; }

confirm_action() {
    local prompt="$1" mode="${2:-standard}" response
    echo ""
    printf "%b\n" "${YELLOW}${BOLD}╔══════════════════════════════════════════════════════════════════╗${NC}"
    printf "%b\n" "${YELLOW}${BOLD}║  CONFIRMATION REQUISE                                            ║${NC}"
    printf "%b\n" "${YELLOW}${BOLD}╚══════════════════════════════════════════════════════════════════╝${NC}"
    printf "%b\n" "${WHITE}$prompt${NC}"
    echo ""

    if [[ "$mode" == "strict" ]]; then
        read -r -p "Confirmer en tapant OUI : " response
        if [[ "$response" == "OUI" ]]; then
            log_to_file "CONFIRM" "Utilisateur confirmé avec OUI : $prompt"; return 0
        fi
        log_info "Opération annulée par l'utilisateur"; return 1
    fi

    if [[ "$mode" == "yes" ]]; then
        read -r -p "Continuer ? [O/n] : " response; response="${response:-o}"
    else
        read -r -p "Continuer ? [o/N] : " response; response="${response:-n}"
    fi

    case "$response" in
        [YyOo]|[YyOo][Ee][Ss])
            log_to_file "CONFIRM" "Utilisateur confirmé : $prompt"; return 0 ;;
        *) log_info "Opération annulée par l'utilisateur"; return 1 ;;
    esac
}

check_bash_version() {
    if [[ "${BASH_VERSINFO[0]}" -lt "$MIN_BASH_VERSION" ]]; then
        log_error "Ce script requiert Bash version $MIN_BASH_VERSION ou supérieure (actuelle : ${BASH_VERSION})"
        exit 1
    fi
}

cleanup() {
    local exit_code=$?
    log_debug "Nettoyage appelé avec code de sortie : $exit_code"
    rm -f /tmp/Rep-Dem-*.tmp 2>/dev/null
    exit $exit_code
}

#-------------------------------------------------------------------------------
# DÉTECTION DISTRIBUTION / INIT / BOOT
#-------------------------------------------------------------------------------
detect_distribution() {
    log_info "Détection de la distribution Linux..."

    if [[ -f /etc/os-release ]]; then
        # shellcheck source=/dev/null
        source /etc/os-release
        # shellcheck disable=SC2034  # utilisé dans lib/boot.sh
        DISTRO="${ID:-unknown}"
        DISTRO_VERSION="${VERSION_ID:-unknown}"

        case "${ID,,}" in
            ubuntu|debian|linuxmint|pop|elementary|zorin|kali|raspbian|mx)
                DISTRO_FAMILY="debian"; PKG_MANAGER="apt" ;;
            fedora)
                DISTRO_FAMILY="rhel";  PKG_MANAGER="dnf" ;;
            rhel|centos|rocky|alma|ol|scientific)
                DISTRO_FAMILY="rhel"
                if command_exists dnf; then PKG_MANAGER="dnf"; else PKG_MANAGER="yum"; fi ;;
            arch|manjaro|endeavouros|garuda|artix)
                DISTRO_FAMILY="arch";  PKG_MANAGER="pacman" ;;
            opensuse*|sles|suse)
                DISTRO_FAMILY="suse";  PKG_MANAGER="zypper" ;;
            gentoo)
                DISTRO_FAMILY="gentoo"; PKG_MANAGER="emerge" ;;
            void)
                DISTRO_FAMILY="void";  PKG_MANAGER="xbps" ;;
            *)
                DISTRO_FAMILY="unknown"
                if command_exists apt;    then PKG_MANAGER="apt";    DISTRO_FAMILY="debian"
                elif command_exists dnf;  then PKG_MANAGER="dnf";    DISTRO_FAMILY="rhel"
                elif command_exists yum;  then PKG_MANAGER="yum";    DISTRO_FAMILY="rhel"
                elif command_exists pacman; then PKG_MANAGER="pacman"; DISTRO_FAMILY="arch"
                elif command_exists zypper; then PKG_MANAGER="zypper"; DISTRO_FAMILY="suse"
                else PKG_MANAGER="unknown"
                fi
                log_warning "Distribution inconnue : ${ID}. Certaines fonctionnalités peuvent ne pas fonctionner."
                ;;
        esac
        log_success "Détecté : ${PRETTY_NAME:-$ID} (Famille : $DISTRO_FAMILY)"

    elif [[ -f /etc/debian_version ]]; then
        # shellcheck disable=SC2034  # utilisé dans lib/boot.sh
        DISTRO="debian"; DISTRO_FAMILY="debian"; PKG_MANAGER="apt"
        DISTRO_VERSION=$(cat /etc/debian_version)
        log_success "Détecté : Debian $DISTRO_VERSION"

    elif [[ -f /etc/redhat-release ]]; then
        # shellcheck disable=SC2034  # utilisé dans lib/boot.sh
        DISTRO="rhel"; DISTRO_FAMILY="rhel"
        if command_exists dnf; then PKG_MANAGER="dnf"; else PKG_MANAGER="yum"; fi
        DISTRO_VERSION=$(cat /etc/redhat-release)
        log_success "Détecté : $DISTRO_VERSION"

    elif [[ -f /etc/arch-release ]]; then
        # shellcheck disable=SC2034  # utilisé dans lib/boot.sh
        DISTRO="arch"; DISTRO_FAMILY="arch"; PKG_MANAGER="pacman"
        log_success "Détecté : Arch Linux"

    else
        log_error "Impossible de détecter la distribution Linux"
        exit 1
    fi
    log_info "Gestionnaire de paquets : $PKG_MANAGER"
}

detect_init_system() {
    if [[ -d /run/systemd/system ]]; then echo "systemd"
    elif [[ -f /sbin/init ]] && /sbin/init --version 2>&1 | grep -q upstart; then echo "upstart"
    elif [[ -f /etc/init.d/cron ]] && [[ ! -d /run/systemd/system ]]; then echo "sysvinit"
    elif command_exists openrc; then echo "openrc"
    else echo "unknown"
    fi
}

detect_boot_mode() {
    if [[ -d /sys/firmware/efi ]]; then
        echo "uefi"; return
    fi
    if [[ -d /boot/efi/EFI ]] || [[ -d /efi/EFI ]]; then
        log_warning "Firmware EFI inactif, mais répertoire EFI présent sur le disque"
        echo "uefi"; return
    fi
    echo "bios"
}

detect_bootloader() {
    local found_grub=false found_sd=false

    if command_exists bootctl && bootctl is-installed 2>/dev/null; then found_sd=true; fi
    for _esp in /boot/efi /efi /boot; do
        if [[ -f "${_esp}/EFI/systemd/systemd-bootx64.efi" ]] \
        || [[ -f "${_esp}/EFI/systemd/systemd-bootia32.efi" ]]; then
            found_sd=true; break
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
    command_exists efibootmgr && \
        efibootmgr -v 2>/dev/null | grep -qi 'systemd\|sd-boot\|systemd-boot' && found_sd=true

    if [[ -f /boot/grub/grub.cfg ]] || [[ -f /boot/grub2/grub.cfg ]]; then found_grub=true; fi
    if command_exists grub-install || command_exists grub2-install; then
        [[ "$found_grub" == false && "$found_sd" == true ]] || found_grub=true
    fi
    command_exists efibootmgr && \
        efibootmgr -v 2>/dev/null | grep -qi 'grub' && found_grub=true

    if [[ "$found_sd" == true && "$found_grub" == true ]]; then echo "both"
    elif [[ "$found_sd" == true ]]; then echo "systemd-boot"
    elif [[ "$found_grub" == true ]]; then echo "grub"
    else echo "unknown"
    fi
}

#-------------------------------------------------------------------------------
# GESTION DES PAQUETS
#-------------------------------------------------------------------------------
package_install_command() {
    case "$PKG_MANAGER" in
        apt)    echo "apt-get install -y" ;;
        dnf)    echo "dnf install -y" ;;
        yum)    echo "yum install -y" ;;
        pacman) echo "pacman -S --noconfirm --needed" ;;
        zypper) echo "zypper install -y" ;;
        emerge) echo "emerge --noreplace" ;;
        xbps)   echo "xbps-install -y" ;;
        *)      return 1 ;;
    esac
}

package_refresh_command() {
    case "$PKG_MANAGER" in
        apt)    echo "apt-get update" ;;
        dnf)    echo "dnf makecache --refresh" ;;
        yum)    echo "yum makecache" ;;
        pacman) echo "pacman -Sy --noconfirm" ;;
        zypper) echo "zypper refresh" ;;
        xbps)   echo "xbps-install -Sy" ;;
        emerge) echo "emerge --sync" ;;
        *)      return 1 ;;
    esac
}

install_packages() {
    local packages=("$@")
    local installer
    installer=$(package_install_command) || {
        log_warning "Gestionnaire de paquets non pris en charge : $PKG_MANAGER"; return 1
    }
    log_info "Installation des paquets requis : ${packages[*]}"
    local refresh_cmd
    if refresh_cmd=$(package_refresh_command 2>/dev/null) && [[ -n "$refresh_cmd" ]]; then
        eval "$refresh_cmd" 2>&1 | while read -r line; do log_debug "$line"; done \
            || log_warning "Impossible d'actualiser le cache des paquets."
    fi
    if eval "$installer ${packages[*]}" 2>&1 | while read -r line; do log_debug "$line"; done; then
        log_success "Paquets installés : ${packages[*]}"; return 0
    fi
    log_error "Échec de l'installation des paquets requis"; return 1
}

package_installed() {
    local pkg="$1"
    case "$PKG_MANAGER" in
        apt)          dpkg -s "$pkg" &>/dev/null ;;
        dnf|yum|zypper) rpm -q "$pkg" &>/dev/null ;;
        pacman)       pacman -Q "$pkg" &>/dev/null ;;
        xbps)         xbps-query -l "$pkg" &>/dev/null ;;
        emerge)       command -v equery >/dev/null 2>&1 && equery list "$pkg" >/dev/null 2>&1 ;;
        *)            return 1 ;;
    esac
}

install_repair_dependencies() {
    local boot_mode
    boot_mode=$(detect_boot_mode)
    local required_packages=() required_commands=()

    case "$DISTRO_FAMILY" in
        debian)
            if [[ "$boot_mode" == "uefi" ]]; then
                required_packages+=(grub-efi-amd64 grub-efi-amd64-signed shim-signed efibootmgr)
                required_commands+=(grub-install efibootmgr)
            else
                required_packages+=(grub-pc); required_commands+=(grub-install)
            fi
            required_packages+=(initramfs-tools); required_commands+=(update-initramfs)
            if command_exists bootctl || [[ -f /boot/efi/EFI/systemd/systemd-bootx64.efi ]]; then
                required_commands+=(bootctl)
            fi ;;
        rhel)
            required_packages+=(grub2 dracut); required_commands+=(grub2-install dracut)
            [[ "$boot_mode" == "uefi" ]] && required_packages+=(efibootmgr) && \
                required_commands+=(efibootmgr) ;;
        arch)
            required_packages+=(grub mkinitcpio); required_commands+=(grub-install mkinitcpio)
            [[ "$boot_mode" == "uefi" ]] && required_packages+=(efibootmgr) && \
                required_commands+=(efibootmgr) ;;
        *)
            log_warning "Installation automatique non prise en charge pour $DISTRO_FAMILY"; return 1 ;;
    esac

    local missing_packages=() missing_commands=()
    for cmd in "${required_commands[@]}"; do
        command_exists "$cmd" || missing_commands+=("$cmd")
    done
    for pkg in "${required_packages[@]}"; do
        package_installed "$pkg" || missing_packages+=("$pkg")
    done

    if [[ ${#missing_packages[@]} -eq 0 && ${#missing_commands[@]} -eq 0 ]]; then
        log_success "Toutes les dépendances requises sont présentes"; return 0
    fi

    [[ ${#missing_commands[@]} -gt 0 ]] && log_warning "Outils manquants : ${missing_commands[*]}"
    [[ ${#missing_packages[@]} -gt 0 ]] && log_warning "Paquets manquants : ${missing_packages[*]}"

    confirm_action "Installer les dépendances manquantes avant la réparation ?" yes || return 1

    if [[ ${#missing_packages[@]} -eq 0 ]]; then
        log_error "Outils manquants sans paquet identifié : ${missing_commands[*]}"; return 1
    fi
    install_packages "${missing_packages[@]}"
}

#-------------------------------------------------------------------------------
# VÉRIFICATIONS ENVIRONNEMENT
#-------------------------------------------------------------------------------
check_root_privileges() {
    log_info "Vérification des privilèges root..."
    if [[ $EUID -ne 0 ]]; then
        log_error "Ce script doit être exécuté en tant que root"
        echo ""; echo "Veuillez exécuter avec : sudo $SCRIPT_NAME"
        exit 1
    fi
    log_success "Exécution avec les privilèges root (UID : $EUID)"
}

initialize_logging() {
    local log_dir; log_dir=$(dirname "$LOG_FILE")
    [[ ! -d "$log_dir" ]] && mkdir -p "$log_dir" 2>/dev/null
    if touch "$LOG_FILE" 2>/dev/null; then
        chmod 640 "$LOG_FILE"
        log_info "Fichier journal initialisé : $LOG_FILE"
    else
        log_warning "Impossible d'écrire dans le fichier journal : $LOG_FILE"
    fi
    local sep; sep=$(printf '=%.0s' $(seq 1 79))
    { echo ""; echo "$sep"
      echo "Session started: $(get_timestamp)  |  Version : $SCRIPT_VERSION"
      echo "$sep"; } >> "$LOG_FILE" 2>/dev/null
}

run_environment_checks() {
    log_header "VÉRIFICATIONS D'ENVIRONNEMENT"
    check_bash_version
    check_root_privileges
    detect_distribution
    detect_init_system > /dev/null
    detect_boot_mode   > /dev/null
    [[ "$ANALYZE_MODE" != true ]] && initialize_logging

    if [[ "$ANALYZE_MODE" != true ]]; then
        log_subheader "Informations système"
        log_info "Kernel : $(uname -r)"
        log_info "Architecture : $(uname -m)"
        log_info "Nom d'hôte : $(hostname)"
        echo ""
        printf "%b\n" "${BOLD}${CYAN}┌─────────────────────────────────────────────────────────────┐${NC}"
        printf "%b  %-60s%b\n" "${BOLD}${CYAN}│${NC}" "Sauvegardes  :  $BACKUP_DIR" "${BOLD}${CYAN}│${NC}"
        printf "%b  %-60s%b\n" "${BOLD}${CYAN}│${NC}" "Journaux     :  $LOG_FILE"   "${BOLD}${CYAN}│${NC}"
        printf "%b\n" "${BOLD}${CYAN}└─────────────────────────────────────────────────────────────┘${NC}"
        echo ""
    fi
    mark_operation_completed "environment_checks"
}
