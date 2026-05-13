#!/usr/bin/env bash
#===============================================================================
#  arch.sh — Support multi-architectures : ARM, RISC-V, LoongArch, EFI
#  Sourcé automatiquement par Rep-Dem.sh
#===============================================================================

#-------------------------------------------------------------------------------
# DÉTECTION ARCHITECTURE EFI
#-------------------------------------------------------------------------------
detect_efi_arch() {
    local machine; machine=$(uname -m)
    case "$machine" in
        x86_64)              echo "x86_64-efi"        ;;
        aarch64|arm64)       echo "arm64-efi"          ;;
        armv7l|armhf)        echo "arm-efi"            ;;
        riscv64)             echo "riscv64-efi"        ;;
        loongarch64)         echo "loongarch64-efi"    ;;
        *)
            log_warning "Architecture inconnue : $machine — utilisation de x86_64-efi par défaut" >&2
            echo "x86_64-efi"
            ;;
    esac
}

detect_efi_binary_name() {
    local machine; machine=$(uname -m)
    case "$machine" in
        x86_64)              echo "grubx64.efi"       ;;
        aarch64|arm64)       echo "grubaa64.efi"      ;;
        armv7l|armhf)        echo "grubarm.efi"       ;;
        riscv64)             echo "grubriscv64.efi"   ;;
        *)                   echo "grubx64.efi"       ;;
    esac
}

detect_shim_packages() {
    local machine; machine=$(uname -m)
    case "$DISTRO_FAMILY" in
        debian)
            case "$machine" in
                x86_64)        echo "shim-signed grub-efi-amd64-signed grub-efi-amd64" ;;
                aarch64|arm64) echo "shim-signed grub-efi-arm64-signed grub-efi-arm64" ;;
                *)             echo "grub-efi-${machine}" ;;
            esac ;;
        rhel)
            case "$machine" in
                x86_64)        echo "shim-x64 grub2-efi-x64"   ;;
                aarch64|arm64) echo "shim-aa64 grub2-efi-aa64" ;;
                *)             echo "grub2-efi"                 ;;
            esac ;;
        arch)
            echo "grub efibootmgr" ;;
        *)
            echo "" ;;
    esac
}

#-------------------------------------------------------------------------------
# VÉRIFICATION OFFSET ESP POUR ARM (Tianocore / Raspberry Pi)
#-------------------------------------------------------------------------------
check_esp_offset_arm() {
    local efi_dir="$1"
    local machine; machine=$(uname -m)

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
        log_warning "ARM ESP check: disque parent de $esp_dev introuvable"; return 0
    fi

    local start_path="/sys/block/${disk_name}/${esp_name}/start"
    if [[ ! -r "$start_path" ]]; then
        log_warning "ARM ESP check: $start_path illisible — vérification ignorée"; return 0
    fi

    local start_sectors start_bytes start_mb limit_mb=256
    start_sectors=$(cat "$start_path")
    start_bytes=$(( start_sectors * 512 ))
    start_mb=$(( start_bytes / 1024 / 1024 ))

    if [[ "$start_bytes" -gt $(( limit_mb * 1024 * 1024 )) ]]; then
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
        echo "    2) Mettre à jour le firmware UEFI (Tianocore récent peut lever cette limite)"
        echo "    3) Continuer — si votre firmware ne souffre pas de cette contrainte"
        echo ""
        if ! confirm_action "Continuer malgré l'offset ESP > ${limit_mb} Mo ?" yes; then
            return 1
        fi
    else
        log_info "ARM ESP check: offset OK — $esp_dev à ${start_mb} Mo sur /dev/${disk_name} (< ${limit_mb} Mo)"
    fi
    return 0
}
