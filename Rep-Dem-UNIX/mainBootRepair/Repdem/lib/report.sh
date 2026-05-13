#!/usr/bin/env bash
#===============================================================================
#  report.sh — Génération rapport brut, Boot-Info structuré, upload en ligne
#  Sourcé automatiquement par Rep-Dem.sh
#===============================================================================

#-------------------------------------------------------------------------------
# HELPERS RAPPORT
#-------------------------------------------------------------------------------
prepare_output_file() {
    local file="$1"
    [[ -z "$file" ]] && return 1
    mkdir -p "$(dirname "$file")" 2>/dev/null || true

    if [[ -e "$file" ]]; then
        if ! confirm_action "Le fichier de sortie existe déjà : $file. Voulez-vous le remplacer ?" yes; then
            log_error "Export annulé."; exit 1
        fi
        local backup
        backup="${file}.bak.$(date +%Y%m%d_%H%M%S)"
        cp -a "$file" "$backup" 2>/dev/null || true
    fi
    : > "$file"
}

report_line() {
    local line="$1"
    printf '%s\n' "$line"
    [[ -n "$OUTPUT_FILE" ]] && printf '%s\n' "$line" >> "$OUTPUT_FILE"
}

raw_command_output() {
    local cmd="$1"
    local exe; exe=$(printf '%s' "$cmd" | awk '{print $1}')
    if ! command_exists "$exe"; then echo "indisponible"; return; fi
    local output
    if output=$(eval "$cmd" 2>/dev/null); then
        if [[ -n "$output" ]]; then printf '%s\n' "$output"; else echo "indisponible"; fi
    else
        echo "indisponible"
    fi
}

report_section() {
    report_line ""
    report_line "================================================================"
    report_line " $1"
    report_line "================================================================"
    report_line ""
}

report_command() {
    local cmd="$1"
    report_line "$cmd"
    local out; out=$(raw_command_output "$cmd")
    printf '%s\n' "$out"
    [[ -n "$OUTPUT_FILE" ]] && printf '%s\n' "$out" >> "$OUTPUT_FILE"
}

#-------------------------------------------------------------------------------
# RAPPORT BRUT LECTURE SEULE
#-------------------------------------------------------------------------------
generate_raw_report() {
    [[ -n "$OUTPUT_FILE" ]] && prepare_output_file "$OUTPUT_FILE"

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
    report_command "findmnt -n -o SOURCE,TARGET,FSTYPE,OPTIONS /boot/efi"
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
    report_command "ls /boot/efi/EFI 2>/dev/null | grep -i Microsoft || echo 'Aucune entrée Microsoft EFI'"
    report_command "find /boot/efi -maxdepth 4 -type f | grep -i 'bootmgfw.efi\|bcd' 2>/dev/null || echo 'Aucun fichier BCD trouvé'"

    report_section "GRUB"
    report_command "grub-install --version"
    report_command "grub2-install --version"
    report_command "cat /etc/default/grub"
    report_command "ls -l /etc/grub.d"

    report_section "SECUREBOOT"
    report_command "mokutil --sb-state"
    report_command "sbctl status"
    report_command "dmesg | grep -iE 'secureboot|efi' | tail -20"

    report_section "TPM"
    report_command "ls /sys/class/tpm/"
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
    report_command "btrfs filesystem show"
    report_command "zpool status"
    report_command "cat /etc/fstab"
    report_command "zramctl --output-all"
    report_command "swapon --show"
    report_command "lsblk -o NAME,FSTYPE,MOUNTPOINT,SIZE,UUID"

    report_section "LOGS"
    report_command "journalctl -p 3 -xb --no-pager -n 50"
    report_command "dmesg | tail -50"
}

#-------------------------------------------------------------------------------
# RAPPORT BOOT-INFO STRUCTURÉ
#-------------------------------------------------------------------------------
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
        if [[ -d /sys/firmware/efi ]]; then echo "UEFI"; else echo "BIOS/Legacy"; fi
        echo ""
        echo "=== PARTITIONS (fdisk) ==="
        fdisk -l 2>/dev/null || echo "indisponible"
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
        lsblk -f 2>/dev/null | grep -i ntfs || echo "Aucune partition NTFS détectée"
        echo ""
        echo "=== RAID ==="
        cat /proc/mdstat 2>/dev/null || echo "indisponible"
        command_exists mdadm && { mdadm --detail --scan 2>/dev/null || echo "aucun RAID mdadm"; }
        echo ""
        echo "=== LVM ==="
        pvs 2>/dev/null || echo "aucun PV"
        vgs 2>/dev/null || echo "aucun VG"
        lvs 2>/dev/null || echo "aucun LV"
        echo ""
        echo "=== SECUREBOOT ==="
        mokutil --sb-state 2>/dev/null || echo "indisponible"
        echo ""
        echo "=== MBR SIGNATURES ==="
        if command_exists hexdump || command_exists xxd; then
            while read -r disk; do
                echo "/dev/$disk:"
                portable_hexdump "/dev/$disk" | tail -4 || echo "indisponible"
            done < <(lsblk -dn -o NAME 2>/dev/null | grep -vE '^(loop|ram|zram)')
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
    echo "  Pour partager ce rapport : sudo $SCRIPT_NAME --advanced → option 6 (upload)"
    echo ""
}

#-------------------------------------------------------------------------------
# UPLOAD RAPPORT EN LIGNE (3 services en parallèle)
#-------------------------------------------------------------------------------
upload_report() {
    local report_file="${1:-${BACKUP_DIR}/boot-info.txt}"
    [[ ! -f "$report_file" ]] && { log_error "Rapport introuvable : $report_file"; return 1; }
    if ! command_exists curl; then
        log_warning "curl non disponible — impossible d'uploader."
        log_info "Rapport local : $report_file"; return 1
    fi
    if ! curl -sf --max-time 5 --head https://paste.ubuntu.com > /dev/null 2>&1; then
        log_warning "Pas de connexion internet. Upload ignoré."
        log_info "Rapport local : $report_file"; return 1
    fi

    local tmp_u tmp_d tmp_g
    tmp_u=$(mktemp /tmp/rd_up_ubuntu_XXXXXX)
    tmp_d=$(mktemp /tmp/rd_up_dpaste_XXXXXX)
    tmp_g=$(mktemp /tmp/rd_up_gofile_XXXXXX)
    log_info "Upload en parallèle sur 3 services..."

    ( curl -sf --max-time 30 \
        -F "poster=Rep-Dem" -F "syntax=text" -F "content=<${report_file}" \
        https://paste.ubuntu.com/ 2>/dev/null \
        | grep -oE 'href="/[0-9]+' | cut -d'/' -f2 | head -1 > "$tmp_u" ) &
    local pid_u=$!

    ( curl -sf --max-time 30 -X POST https://dpaste.com/api/v2/ \
        --data-urlencode "content@${report_file}" -d "syntax=text" -d "expiry_days=7" \
        2>/dev/null > "$tmp_d" ) &
    local pid_d=$!

    ( curl -sf --max-time 60 -X POST \
          -F "file=@${report_file}" \
          "https://upload.gofile.io/uploadfile" 2>/dev/null \
          | grep -oE '"downloadPage":"([^"]+)' | cut -d'"' -f3 | head -1 > "$tmp_g" ) &
    local pid_g=$!

    wait $pid_u $pid_d $pid_g 2>/dev/null

    local url_ubuntu="" url_dpaste="" url_gofile=""
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
    printf "%b\n" "${GREEN}${BOLD}╚══════════════════════════════════════════════════════════════════╝${NC}"
    echo ""

    {
        echo ""
        echo "=== LIENS UPLOAD ==="
        [[ -n "$url_ubuntu" ]] && echo "paste.ubuntu.com : $url_ubuntu"
        [[ -n "$url_dpaste" ]] && echo "dpaste.com       : $url_dpaste"
        [[ -n "$url_gofile" ]] && echo "gofile.io        : $url_gofile"
    } >> "$report_file"

    if [[ "$any_ok" == false ]]; then
        log_error "Tous les services d'upload ont échoué."
        log_info "Uploadez manuellement : https://paste.ubuntu.com  https://dpaste.com  https://gofile.io"
        return 1
    fi
}
