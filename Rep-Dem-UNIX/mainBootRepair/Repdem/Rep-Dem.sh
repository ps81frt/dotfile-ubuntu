#!/usr/bin/env bash
#===============================================================================
#
#          FILE: Rep-Dem.sh
#
#   UTILISATION: sudo ./Rep-Dem.sh [--boot|--recommended|--advanced|
#                                    --boot-info|--analyze|--output <fichier>]
#
#   DESCRIPTION: Outil de réparation boot Linux multi-distro, sans GUI.
#                Équivalent CLI de Boot-Repair (YannUbuntu), maintenu et étendu.
#                Architecture modulaire — modules dans lib/
#
#       OPTIONS: --boot           Réparation boot interactive
#                --recommended    Réparation automatique 6 étapes
#                --advanced       Menu avancé 11 options
#                --boot-info      Rapport Boot-Info + upload optionnel
#                --analyze        Rapport brut lecture seule (stdout)
#                --output FILE    Exporte le rapport vers FILE
#                --help           Aide complète
#                --version        Affiche la version
#
#      SUPPORTS: Debian/Ubuntu/Mint · Fedora/RHEL/Rocky/Alma · Arch/Manjaro
#                openSUSE · Void Linux · Gentoo
#                ARM (aarch64) · RISC-V · LoongArch · x86_64
#        AUTHOR: ps81frt
#       VERSION: 2.0.0
#       CREATED: 2026
#       LICENSE: MIT
#
#===============================================================================

set -uo pipefail
shopt -s nullglob

#-------------------------------------------------------------------------------
# CONSTANTES GLOBALES
#-------------------------------------------------------------------------------
SCRIPT_NAME="$(basename "$0")"
readonly SCRIPT_NAME
readonly SCRIPT_VERSION="2.0.0"
# shellcheck disable=SC2034  # utilisé dans lib/core.sh:check_bash_version()
readonly MIN_BASH_VERSION=4
readonly LOG_FILE="/var/log/Rep-Dem.log"
BACKUP_DIR="/var/backup/Rep-Dem-$(date +%Y%m%d_%H%M%S)"
readonly BACKUP_DIR

#-------------------------------------------------------------------------------
# VARIABLES GLOBALES MUTABLES
#-------------------------------------------------------------------------------
# shellcheck disable=SC2034  # utilisé dans lib/boot.sh
DISTRO=""
# shellcheck disable=SC2034  # utilisé dans lib/arch.sh, lib/boot.sh
DISTRO_FAMILY=""
# shellcheck disable=SC2034  # utilisé dans lib/core.sh
DISTRO_VERSION=""
# shellcheck disable=SC2034  # utilisé dans lib/boot.sh
PKG_MANAGER=""
# shellcheck disable=SC2034  # utilisé dans lib/core.sh, lib/boot.sh
declare -A COMPLETED_OPERATIONS
export MODE="interactive"
OUTPUT_FILE=""
ANALYZE_MODE=false
# shellcheck disable=SC2034  # utilisé dans lib/boot.sh
FORCE_DISK=""
export NONINTERACTIVE=false
# shellcheck disable=SC2034  # utilisé dans lib/repair.sh
CHROOT_TARGET=""           # point de montage auto-chroot (utilisé par _autochroot_cleanup)
_INSIDE_CHROOT=false       # true quand le script tourne dans un chroot

#-------------------------------------------------------------------------------
# CHARGEMENT DES MODULES
#-------------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR

for _lib in core arch backup repair secure report boot; do
    _lib_file="${SCRIPT_DIR}/lib/${_lib}.sh"
    if [[ ! -f "$_lib_file" ]]; then
        printf '[ERREUR] Module introuvable : %s\n' "$_lib_file" >&2
        exit 1
    fi
    # shellcheck source=/dev/null
    source "$_lib_file"
done
unset _lib _lib_file

trap '_autochroot_cleanup 2>/dev/null; cleanup' EXIT INT TERM

#-------------------------------------------------------------------------------
# BANNIÈRE
#-------------------------------------------------------------------------------
show_banner() {
    clear
    printf "%b\n" "${CYAN}${BOLD}"
    cat << 'BANNER'
░█████████  ░██████████ ░█████████          ░███████   ░██████████ ░███     ░███
░██     ░██ ░██         ░██     ░██         ░██   ░██  ░██         ░████   ░████
░██     ░██ ░██         ░██     ░██         ░██    ░██ ░██         ░██░██ ░██░██
░█████████  ░█████████  ░█████████  ░██████ ░██    ░██ ░█████████  ░██ ░████ ░██
░██   ░██   ░██         ░██                 ░██    ░██ ░██         ░██  ░██  ░██
░██    ░██  ░██         ░██                 ░██   ░██  ░██         ░██       ░██
░██     ░██ ░██████████ ░██                 ░███████   ░██████████ ░██       ░██
BANNER
    printf "%b\n" "${NC}"
    printf "%b\n" "${WHITE}   Outil de réparation boot Linux — Architecture modulaire${NC}"
    printf "%b\n" "${DIM}   Version $SCRIPT_VERSION | Qualité production${NC}"
    echo ""
}

#-------------------------------------------------------------------------------
# MENU PRINCIPAL
#-------------------------------------------------------------------------------
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
        printf "%b\n" "${BOLD}║${NC}      [Mode chroot — option Live ISO non disponible ici]               ${BOLD}║${NC}"
    fi
    printf "%b\n" "${BOLD}╚════════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

#-------------------------------------------------------------------------------
# AIDE
#-------------------------------------------------------------------------------
show_help() {
    cat << HELP
UTILISATION : $SCRIPT_NAME [OPTION]

Outil de réparation boot Linux — Version $SCRIPT_VERSION
Équivalent CLI de Boot-Repair, multi-distro, sans interface graphique.
Supporte GRUB 2 (BIOS + UEFI) et systemd-boot (UEFI).

OPTIONS :
    --recommended       Réparation automatique en 6 étapes sécurisées
    --boot              Réparation GRUB interactive avec confirmations
    --advanced          Menu avancé 11 options
    --boot-info [FILE]  Rapport Boot-Info complet (défaut : $BACKUP_DIR/boot-info.txt)
    --analyze           Rapport brut système lecture seule (stdout)
    --output FILE       Exporte le rapport brut vers FILE
    --live-chroot       Scan auto + chroot depuis un Live ISO (réparer le système installé)
    --inside-chroot     Usage interne — lancé automatiquement par --live-chroot
    --help, -h          Affiche ce message d'aide
    --version, -v       Affiche la version

EXEMPLES :
    sudo $SCRIPT_NAME
    sudo $SCRIPT_NAME --recommended
    sudo $SCRIPT_NAME --boot
    sudo $SCRIPT_NAME --advanced
    sudo $SCRIPT_NAME --boot-info /tmp/mon-rapport.txt
    sudo $SCRIPT_NAME --analyze --output rapport.txt
    sudo $SCRIPT_NAME --live-chroot        # depuis un Live USB/ISO

MODULES (lib/) :
    core.sh     Logging, utilitaires, détection, gestion paquets
    arch.sh     Support ARM / RISC-V / LoongArch / EFI multi-arch
    backup.sh   Sauvegardes fichiers, GRUB, tables de partitions, sgdisk
    repair.sh   Régénération initramfs, fsck, réparation via chroot
    secure.sh   Secure Boot, état MOK, enrôlement clé, signature EFI
    report.sh   Rapport brut, Boot-Info structuré, upload 3 services
    boot.sh     GRUB (Debian/RHEL/Arch), systemd-boot, menus interactifs

UPLOAD RAPPORT :
    3 services en parallèle, sans compte : paste.ubuntu.com · dpaste.com · gofile.io

SAUVEGARDES :  $BACKUP_DIR
JOURNAUX :     $LOG_FILE

HELP
}

#-------------------------------------------------------------------------------
# POINT D'ENTRÉE
#-------------------------------------------------------------------------------
main() {
    case "${1:-}" in
        --analyze)
            ANALYZE_MODE=true
            if [[ "${2:-}" == "--output" ]]; then
                OUTPUT_FILE="${3:-}"
                [[ -z "$OUTPUT_FILE" ]] && { log_error "Fichier de sortie manquant"; exit 1; }
            fi
            generate_raw_report; exit 0 ;;
        --output)
            OUTPUT_FILE="${2:-}"
            [[ -z "$OUTPUT_FILE" ]] && { log_error "Fichier de sortie manquant"; exit 1; }
            ANALYZE_MODE=true; generate_raw_report; exit 0 ;;
        --help|-h)   show_help; exit 0 ;;
        --version|-v) echo "$SCRIPT_NAME version $SCRIPT_VERSION"; exit 0 ;;
        --recommended)
            show_banner; run_recommended_repair; exit $? ;;
        --boot)
            show_banner; run_environment_checks; run_boot_repair; exit $? ;;
        --advanced)
            show_banner; run_advanced_repair; exit $? ;;
        --boot-info)
            run_environment_checks
            generate_boot_info "${2:-${BACKUP_DIR}/boot-info.txt}"; exit 0 ;;
        --live-chroot)
            show_banner
            auto_scan_and_chroot; exit $? ;;
        --inside-chroot)
            # Lancé par auto_scan_and_chroot à l'intérieur du chroot
            _INSIDE_CHROOT=true
            show_banner
            printf "%b\n" "${YELLOW}${BOLD}[CHROOT]${NC} Vous opérez sur le système installé — pas sur le Live ISO."
            echo ""
            run_environment_checks
            while true; do
                show_menu
                read -r -p "Entrez votre choix [1-6] : " menu_choice
                # shellcheck disable=SC2034  # ANALYZE_MODE lu dans lib/core.sh
                case "$menu_choice" in
                    1) run_recommended_repair ;;
                    2) run_boot_repair ;;
                    3) run_advanced_repair ;;
                    4) generate_boot_info ;;
                    5) ANALYZE_MODE=true; generate_raw_report ;;
                    6) echo ""; log_info "Fermeture du chroot. À bientôt !"; echo ""; exit 0 ;;
                    *) log_warning "Choix invalide. Veuillez entrer 1-6." ;;
                esac
                echo ""
                read -r -p "Appuyez sur Entrée pour continuer..."
            done ;;
        "")
            show_banner
            run_environment_checks
            while true; do
                show_menu
                read -r -p "Entrez votre choix [1-7] : " menu_choice
                # shellcheck disable=SC2034  # ANALYZE_MODE lu dans lib/core.sh
                case "$menu_choice" in
                    1) run_recommended_repair ;;
                    2) run_boot_repair ;;
                    3) run_advanced_repair ;;
                    4) generate_boot_info ;;
                    5) ANALYZE_MODE=true; generate_raw_report ;;
                    6) auto_scan_and_chroot ;;
                    7) echo ""; log_info "Fermeture. À bientôt !"; echo ""; exit 0 ;;
                    *) log_warning "Choix invalide. Veuillez entrer 1-7." ;;
                esac
                echo ""
                read -r -p "Appuyez sur Entrée pour continuer..."
            done ;;
        *)
            log_error "Option inconnue : $1"
            echo "Utilisez --help pour obtenir des informations d'utilisation"
            exit 1 ;;
    esac
}

main "$@"
