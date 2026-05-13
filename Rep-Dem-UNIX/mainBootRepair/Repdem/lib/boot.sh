#!/usr/bin/env bash
#===============================================================================
#  boot.sh — Réparation GRUB (Debian/RHEL/Arch), systemd-boot, configuration
#            menu GRUB, Windows EFI/MBR, menus principaux interactifs
#  Sourcé automatiquement par Rep-Dem.sh
#===============================================================================

#-------------------------------------------------------------------------------
# DÉTECTION DU PÉRIPHÉRIQUE DE DÉMARRAGE
#-------------------------------------------------------------------------------
detect_boot_device() {
    local boot_device="" boot_partition=""
    log_info "Détection du périphérique de démarrage..." >&2

    if [[ -d /sys/firmware/efi ]]; then
        boot_partition=$(findmnt -n -o SOURCE /boot/efi 2>/dev/null | head -1)
        [[ -z "$boot_partition" ]] && boot_partition=$(findmnt -n -o SOURCE /boot 2>/dev/null | head -1)
    fi
    [[ -z "$boot_partition" ]] && boot_partition=$(findmnt -n -o SOURCE / 2>/dev/null | head -1)

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

    if [[ -n "$boot_device" && -b "$boot_device" ]]; then
        log_info "Périphérique détecté : $boot_device" >&2; echo "$boot_device"
    else
        log_warning "Impossible de détecter automatiquement le périphérique de démarrage" >&2
        echo ""
    fi
}

#-------------------------------------------------------------------------------
# RÉINSTALLATION GRUB PAR FAMILLE DE DISTRIBUTION
#-------------------------------------------------------------------------------
reinstall_grub_debian() {
    local boot_device="$1"
    local boot_mode; boot_mode=$(detect_boot_mode)
    local efi_target; efi_target=$(detect_efi_arch)
    log_info "Réinstallation GRUB Debian (cible EFI : $efi_target)..."
    apt-get update -qq
    if [[ "$boot_mode" == "uefi" ]]; then
        local shim_pkgs; shim_pkgs=$(detect_shim_packages)
        if [[ -n "$shim_pkgs" ]]; then
            # shellcheck disable=SC2086
            apt-get install --reinstall -y $shim_pkgs 2>&1 | while read -r l; do log_debug "$l"; done
        fi
        local efi_dir="/boot/efi"
        [[ ! -d "$efi_dir/EFI" ]] && efi_dir="/efi"
        [[ ! -d "$efi_dir" ]] && { log_error "Répertoire EFI introuvable"; return 1; }
        check_esp_offset_arm "$efi_dir" || return 1
        grub-install --target="$efi_target" --efi-directory="$efi_dir" \
            --bootloader-id="GRUB" --recheck 2>&1 || { log_error "Échec grub-install"; return 1; }
    else
        apt-get install --reinstall -y grub-pc 2>&1 | while read -r l; do log_debug "$l"; done
        grub-install --target=i386-pc --recheck "$boot_device" 2>&1 \
            || { log_error "Échec grub-install BIOS"; return 1; }
    fi
    update-grub 2>&1 || { log_error "Échec update-grub"; return 1; }
    return 0
}

reinstall_grub_rhel() {
    local boot_device="$1"
    local boot_mode; boot_mode=$(detect_boot_mode)
    local efi_target; efi_target=$(detect_efi_arch)
    log_info "Réinstallation GRUB RHEL (cible EFI : $efi_target)..."
    if [[ "$boot_mode" == "uefi" ]]; then
        local shim_pkgs; shim_pkgs=$(detect_shim_packages)
        if [[ -n "$shim_pkgs" ]]; then
            # shellcheck disable=SC2086
            $PKG_MANAGER reinstall -y $shim_pkgs 2>&1 | while read -r l; do log_debug "$l"; done
        fi
        local efi_dir="/boot/efi"; [[ ! -d "$efi_dir" ]] && efi_dir="/efi"
        check_esp_offset_arm "$efi_dir" || return 1
        grub2-install --target="$efi_target" --efi-directory="$efi_dir" \
            --bootloader-id=rhel --recheck 2>&1 \
            || { log_error "Échec grub2-install"; return 1; }
    else
        $PKG_MANAGER reinstall -y grub2-pc 2>&1 | while read -r l; do log_debug "$l"; done
        grub2-install --target=i386-pc --recheck "$boot_device" 2>&1 \
            || { log_error "Échec grub2-install BIOS"; return 1; }
    fi
    grub2-mkconfig -o /boot/grub2/grub.cfg 2>&1 || { log_error "Échec grub2-mkconfig"; return 1; }
    return 0
}

reinstall_grub_arch() {
    local boot_device="$1"
    local boot_mode; boot_mode=$(detect_boot_mode)
    local efi_target; efi_target=$(detect_efi_arch)
    log_info "Réinstallation GRUB Arch (cible EFI : $efi_target)..."
    local grub_pkgs; grub_pkgs=$(detect_shim_packages)
    # shellcheck disable=SC2086
    pacman -S --noconfirm --needed ${grub_pkgs:-grub efibootmgr} 2>&1 \
        | while read -r l; do log_debug "$l"; done
    if [[ "$boot_mode" == "uefi" ]]; then
        local efi_dir="/boot/efi"; [[ ! -d "$efi_dir" ]] && efi_dir="/boot"
        check_esp_offset_arm "$efi_dir" || return 1
        grub-install --target="$efi_target" --efi-directory="$efi_dir" \
            --bootloader-id=GRUB --recheck 2>&1 \
            || { log_error "Échec grub-install"; return 1; }
    else
        repair_bios_mbr "$boot_device" || return 1
    fi
    grub-mkconfig -o /boot/grub/grub.cfg 2>&1 || { log_error "Échec grub-mkconfig"; return 1; }
    return 0
}

#-------------------------------------------------------------------------------
# RÉPARATION SYSTEMD-BOOT
#-------------------------------------------------------------------------------
repair_systemd_boot() {
    log_header "RÉPARATION SYSTEMD-BOOT"

    if ! command_exists bootctl; then
        log_warning "bootctl introuvable. Tentative d'installation..."
        case "$DISTRO_FAMILY" in
            debian) install_packages systemd-boot-efi 2>/dev/null || install_packages systemd 2>/dev/null ;;
            arch)   install_packages systemd 2>/dev/null ;;
            rhel)   install_packages systemd-udev 2>/dev/null ;;
            *)      log_error "Installation automatique de bootctl non supportée pour $DISTRO_FAMILY"; return 1 ;;
        esac
        command_exists bootctl || { log_error "bootctl toujours introuvable après installation"; return 1; }
    fi

    [[ $(detect_boot_mode) != "uefi" ]] && { log_error "systemd-boot nécessite UEFI."; return 1; }

    local esp_dir=""
    for d in /boot/efi /efi /boot; do
        if findmnt -n "$d" &>/dev/null && \
           [[ "$(findmnt -n -o FSTYPE "$d" 2>/dev/null)" == "vfat" ]]; then
            esp_dir="$d"; break
        fi
    done
    if [[ -z "$esp_dir" ]]; then
        log_error "Partition EFI (ESP) non montée. Montez-la sur /boot/efi ou /efi."
        echo "Partitions vfat :"
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
    echo "  7)  Vérifier crypttab (fix suffix _XXXXX)"
    echo "  8)  Retour"
    echo ""
    read -r -p "Choix [1-8] : " sd_choice

    case "$sd_choice" in
        1)
            confirm_action "Réinstaller systemd-boot dans $esp_dir. Écrase le bootloader EFI existant." strict \
                || return 0
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
                printf 'timeout 5\ndefault @saved\nconsole-mode auto\n' > "$loader_conf"
                log_success "loader.conf créé : $loader_conf"
            fi
            [[ "$DISTRO_FAMILY" == "debian" ]] && command_exists update-initramfs && \
                update-initramfs -u -k all 2>&1 | while read -r l; do log_debug "$l"; done \
                && log_success "initramfs régénéré"
            [[ "$DISTRO_FAMILY" == "arch" ]] && command_exists mkinitcpio && \
                mkinitcpio -P 2>&1 | while read -r l; do log_debug "$l"; done \
                && log_success "initramfs régénéré"
            command_exists kernel-install && {
                local kver; kver=$(uname -r)
                kernel-install add "$kver" "/boot/vmlinuz-${kver}" 2>&1 \
                    | while read -r l; do log_debug "$l"; done \
                    && log_success "Entrée noyau $kver installée"
            }
            ;;
        2)
            if bootctl update --esp-path="$esp_dir" 2>&1 | while read -r l; do log_info "bootctl: $l"; done; then
                log_success "systemd-boot mis à jour"
            else
                log_error "Échec bootctl update"
                return 1
            fi
            ;;
        3) echo ""; bootctl status 2>&1 | while read -r l; do printf '  %s\n' "$l"; done ;;
        4) echo ""; bootctl list  2>&1 | while read -r l; do printf '  %s\n' "$l"; done ;;
        5) _create_sd_boot_entry "$esp_dir" ;;
        6) _validate_sd_boot_uuids "$esp_dir" ;;
        7) _check_crypttab_suffix ;;
        8) return 0 ;;
        *) log_warning "Choix invalide" ;;
    esac
}

_validate_sd_boot_uuids() {
    local esp_dir="$1" entries_dir="${1}/loader/entries"
    [[ ! -d "$entries_dir" ]] && { log_error "Répertoire d'entrées introuvable : $entries_dir"; return 1; }
    log_subheader "Validation UUID entrées systemd-boot"
    local any_mismatch=false
    for conf in "${entries_dir}/"*.conf; do
        [[ -f "$conf" ]] || continue
        local entry_uuid
        entry_uuid=$(sed -n 's/.*root=UUID="\?\([0-9A-Za-z-]*\)"\?.*/\1/p' "$conf" | head -1)
        [[ -z "$entry_uuid" ]] && continue
        local real_dev; real_dev=$(blkid -t UUID="$entry_uuid" -o device 2>/dev/null | head -1)
        echo ""; printf "  Entrée : %s\n" "$(basename "$conf")"
        printf "  UUID dans .conf : %s\n" "$entry_uuid"
        if [[ -n "$real_dev" ]]; then
            printf "%b  OK : UUID trouvé sur %s%b\n" "${GREEN}" "$real_dev" "${NC}"
        else
            printf "%b  MISMATCH : aucun device avec UUID=%s%b\n" "${RED}" "$entry_uuid" "${NC}"
            any_mismatch=true
            local real_uuid; real_uuid=$(findmnt -n -o UUID / 2>/dev/null | head -1)
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
        log_info "/etc/crypttab absent — pas de chiffrement LUKS configuré"; return 0
    fi
    echo ""; echo "Contenu actuel de /etc/crypttab :"
    while read -r l; do printf '  %s\n' "$l"; done < /etc/crypttab
    echo ""
    local fixed=false new_crypttab; new_crypttab=$(mktemp /tmp/rd_crypttab_XXXXXX)
    while IFS= read -r line; do
        if [[ "$line" =~ ^cryptdata_[A-Za-z0-9]+[[:space:]] ]]; then
            local fixed_line; fixed_line="cryptdata${line#cryptdata_}"
            printf "%b  Suffix parasite : avant=%s  après=%s%b\n" "${YELLOW}" "$line" "$fixed_line" "${NC}"
            echo "$fixed_line" >> "$new_crypttab"; fixed=true
        else
            echo "$line" >> "$new_crypttab"
        fi
    done < /etc/crypttab
    if [[ "$fixed" == true ]]; then
        if confirm_action "Corriger /etc/crypttab (supprimer suffix _XXXXX sur cryptdata) ?" yes; then
            cp /etc/crypttab "/etc/crypttab.bak.$(date +%H%M%S)"
            cp "$new_crypttab" /etc/crypttab
            log_success "crypttab corrigé"
            command_exists update-initramfs && {
                update-initramfs -c -k all 2>&1 | while read -r l; do log_debug "$l"; done
                log_success "initramfs régénéré"
            }
        fi
    else
        log_success "Aucun suffix parasite détecté dans /etc/crypttab"
    fi
    rm -f "$new_crypttab"
}

_create_sd_boot_entry() {
    local esp_dir="$1" entries_dir="${1}/loader/entries"
    mkdir -p "$entries_dir"
    local kver; kver=$(uname -r)
    local vmlinuz="" initrd_path=""
    for vml in "/boot/vmlinuz-${kver}" "/boot/vmlinuz" "/boot/Image"; do
        [[ -f "$vml" ]] && vmlinuz="$vml" && break
    done
    for ird in "/boot/initrd.img-${kver}" "/boot/initramfs-${kver}.img" "/boot/initrd.img"; do
        [[ -f "$ird" ]] && initrd_path="$ird" && break
    done
    [[ -z "$vmlinuz" ]] && { log_error "vmlinuz introuvable pour $kver"; return 1; }
    local root_uuid; root_uuid=$(findmnt -n -o UUID / 2>/dev/null | head -1)
    [[ -z "$root_uuid" ]] && { log_error "UUID partition root introuvable"; return 1; }
    local esp_kdir="${esp_dir}/${DISTRO_FAMILY:-linux}"
    mkdir -p "$esp_kdir"
    if cp "$vmlinuz" "${esp_kdir}/vmlinuz-${kver}" 2>/dev/null; then
        log_success "vmlinuz copié dans ESP"
    else
        log_warning "Échec copie vmlinuz"
    fi
    if [[ -n "$initrd_path" ]]; then
        if cp "$initrd_path" "${esp_kdir}/initrd-${kver}.img" 2>/dev/null; then
            log_success "initrd copié dans ESP"
        else
            log_warning "Échec copie initrd"
        fi
    fi
    local entry_file="${entries_dir}/${DISTRO:-linux}-${kver}.conf"
    {   echo "title   ${PRETTY_NAME:-Linux ${kver}}"
        echo "linux   /${DISTRO_FAMILY:-linux}/vmlinuz-${kver}"
        [[ -n "$initrd_path" ]] && echo "initrd  /${DISTRO_FAMILY:-linux}/initrd-${kver}.img"
        echo "options root=UUID=${root_uuid} rw quiet splash"
    } > "$entry_file"
    log_success "Entrée boot créée : $entry_file"
    echo ""; cat "$entry_file" | while read -r l; do printf '  %s\n' "$l"; done; echo ""
}

#-------------------------------------------------------------------------------
# GRUB : UTILITAIRES ET CONFIGURATION
#-------------------------------------------------------------------------------
repair_bios_mbr() {
    local boot_device="$1"
    command_exists grub-install || { log_warning "grub-install introuvable"; return 1; }
    log_info "Restauration du MBR GRUB sur $boot_device"
    grub-install --target=i386-pc --boot-directory=/boot --recheck "$boot_device" 2>&1 \
        | while read -r l; do log_debug "$l"; done \
        && log_success "MBR GRUB restauré sur $boot_device" && return 0
    log_error "Échec restauration MBR GRUB sur $boot_device"; return 1
}

purge_grub() {
    log_subheader "Purge GRUB"
    case "$DISTRO_FAMILY" in
        debian)
            apt-get purge -y grub-pc grub-efi-amd64 grub-efi-amd64-bin \
                grub-efi-amd64-signed grub-common grub2-common 2>&1 \
                | while read -r l; do log_debug "$l"; done
            apt-get autoremove -y 2>&1 | while read -r l; do log_debug "$l"; done ;;
        rhel)
            $PKG_MANAGER remove -y grub2 grub2-efi-x64 grub2-pc 2>&1 \
                | while read -r l; do log_debug "$l"; done ;;
        arch)
            pacman -Rns --noconfirm grub 2>&1 | while read -r l; do log_debug "$l"; done ;;
        *)  log_warning "Purge GRUB non prise en charge pour : $DISTRO_FAMILY"; return 1 ;;
    esac
    log_success "Purge GRUB terminée"
}

configure_grub_menu_options() {
    log_header "CONFIGURATION GRUB"
    local grub_default="/etc/default/grub"
    [[ ! -f "$grub_default" ]] && { log_error "Fichier introuvable : $grub_default — GRUB installé ?"; return 1; }
    backup_file "$grub_default"
    echo ""
    echo "Configuration actuelle :"
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
        1)  sed -i '/^GRUB_HIDDEN_TIMEOUT=/d' "$grub_default" 2>/dev/null
            local cur_t; cur_t=$(grep '^GRUB_TIMEOUT=' "$grub_default" | head -1 | cut -d= -f2)
            if [[ "$cur_t" == "0" || "$cur_t" == "-1" || -z "$cur_t" ]]; then
                if grep -q '^GRUB_TIMEOUT=' "$grub_default"; then
                    sed -i 's/^GRUB_TIMEOUT=.*/GRUB_TIMEOUT=10/' "$grub_default"
                else
                    echo 'GRUB_TIMEOUT=10' >> "$grub_default"
                fi
                log_success "GRUB_TIMEOUT=10 — le menu s'affichera"
            else
                log_info "GRUB_TIMEOUT déjà à $cur_t — aucune modification"
            fi ;;
        2)  read -r -p "Délai en secondes (ex. 10, -1=infini, 0=caché) : " new_t
            if grep -q '^GRUB_TIMEOUT=' "$grub_default"; then
                sed -i "s/^GRUB_TIMEOUT=.*/GRUB_TIMEOUT=${new_t}/" "$grub_default"
            else
                echo "GRUB_TIMEOUT=${new_t}" >> "$grub_default"
            fi
            log_success "GRUB_TIMEOUT=${new_t}" ;;
        3)  echo "Exemples : nomodeset  acpi=off  acpi_osi=  noapic  quiet splash  rootdelay=90"
            read -r -p "Option(s) à ajouter : " new_opt
            local cur_cmd; cur_cmd=$(grep '^GRUB_CMDLINE_LINUX_DEFAULT=' "$grub_default" \
                | sed 's/^GRUB_CMDLINE_LINUX_DEFAULT=//' | tr -d '"')
            local new_cmd="${cur_cmd:+$cur_cmd }${new_opt}"
            sed -i "s|^GRUB_CMDLINE_LINUX_DEFAULT=.*|GRUB_CMDLINE_LINUX_DEFAULT=\"${new_cmd}\"|" \
                "$grub_default"
            log_success "Options noyau : \"$new_cmd\"" ;;
        4)  local cur_cmd; cur_cmd=$(grep '^GRUB_CMDLINE_LINUX_DEFAULT=' "$grub_default" \
                | sed 's/^GRUB_CMDLINE_LINUX_DEFAULT=//' | tr -d '"')
            echo "Options actuelles : $cur_cmd"
            read -r -p "Option à supprimer : " rm_opt
            local new_cmd; new_cmd=$(echo "$cur_cmd" \
                | sed "s/\b${rm_opt}\b//g" | tr -s ' ' | sed 's/^ //;s/ $//')
            sed -i "s|^GRUB_CMDLINE_LINUX_DEFAULT=.*|GRUB_CMDLINE_LINUX_DEFAULT=\"${new_cmd}\"|" \
                "$grub_default"
            log_success "Options après suppression : \"$new_cmd\"" ;;
        5)  read -r -p "Résolution (ex. 1024x768, 1920x1080, auto) : " new_gfx
            if grep -q '^GRUB_GFXMODE=' "$grub_default"; then
                sed -i "s|^GRUB_GFXMODE=.*|GRUB_GFXMODE=${new_gfx}|" "$grub_default"
            else
                echo "GRUB_GFXMODE=${new_gfx}" >> "$grub_default"
            fi
            log_success "GRUB_GFXMODE=${new_gfx}" ;;
        6)  : ;; # régénérer ci-dessous
        7)  return 0 ;;
        *)  log_warning "Choix invalide"; return 0 ;;
    esac

    if [[ "$grub_opt" != "7" ]]; then
        local regenerate=false
        [[ "$grub_opt" == "6" ]] && regenerate=true
        [[ "$grub_opt" != "6" ]] && confirm_action "Régénérer grub.cfg maintenant ?" \
            && regenerate=true
        if [[ "$regenerate" == "true" ]]; then
            if command_exists update-grub; then
                update-grub 2>&1 | while read -r l; do log_info "$l"; done
            elif command_exists grub-mkconfig; then
                grub-mkconfig -o /boot/grub/grub.cfg 2>&1 | while read -r l; do log_info "$l"; done
            elif command_exists grub2-mkconfig; then
                grub2-mkconfig -o /boot/grub2/grub.cfg 2>&1 | while read -r l; do log_info "$l"; done
            else
                log_error "Aucun outil grub-mkconfig / update-grub trouvé"
            fi
        fi
    fi
}

#-------------------------------------------------------------------------------
# WINDOWS : EFI ET MBR
#-------------------------------------------------------------------------------
repair_windows_efi() {
    log_subheader "Restauration EFI Microsoft"
    local efi_dir=""
    for d in /boot/efi /efi; do [[ -d "$d/EFI" ]] && efi_dir="$d" && break; done
    [[ -z "$efi_dir" ]] && { log_error "Aucun répertoire EFI monté détecté"; return 1; }
    local ms_efi="${efi_dir}/EFI/Microsoft/Boot/bootmgfw.efi"
    if [[ ! -f "$ms_efi" ]]; then
        log_info "bootmgfw.efi introuvable — aucun Windows dans la partition EFI"; return 0
    fi
    if command_exists efibootmgr; then
        local ms_entry
        ms_entry=$(efibootmgr -v 2>/dev/null | grep -i 'Windows Boot Manager' | head -1 \
                   | grep -oE 'Boot[0-9A-Fa-f]{4}' | head -1)
        if [[ -n "$ms_entry" ]]; then
            if efibootmgr --bootnum "${ms_entry#Boot}" --active 2>/dev/null; then
                log_success "Entrée EFI Microsoft activée : $ms_entry"
            else
                log_warning "Impossible d'activer $ms_entry"
            fi
        else
            log_info "Entrée 'Windows Boot Manager' absente — création..."
            local part_src disk_dev part_num
            part_src=$(findmnt -n -o SOURCE "${efi_dir}" 2>/dev/null | head -1)
            disk_dev=$(lsblk -no PKNAME "$part_src" 2>/dev/null | head -1)
            part_num=$(lsblk -no PARTN  "$part_src" 2>/dev/null | head -1)
            if [[ -n "$disk_dev" && -n "$part_num" ]]; then
                if efibootmgr --create --disk "/dev/${disk_dev}" --part "${part_num}" \
                    --loader '\EFI\Microsoft\Boot\bootmgfw.efi' \
                    --label 'Windows Boot Manager' 2>/dev/null; then
                    log_success "Entrée EFI Windows Boot Manager créée"
                else
                    log_error "Échec de création de l'entrée EFI Windows"
                fi
            else
                log_error "Impossible de déterminer le disque/partition EFI"
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
        ms-sys --mbr7 "$boot_device" 2>/dev/null \
            && { log_success "MBR Windows 7/8/10/11 restauré sur $boot_device"; return 0; }
    fi
    log_warning "ms-sys introuvable. Tentative d'installation..."
    if install_packages ms-sys 2>/dev/null; then
        ms-sys --mbr7 "$boot_device" 2>/dev/null \
            && { log_success "MBR Windows restauré sur $boot_device"; return 0; }
    fi
    log_error "ms-sys non disponible : restauration MBR Windows impossible"; return 1
}

#-------------------------------------------------------------------------------
# RÉPARATION GRUB PRINCIPALE + MENUS
#-------------------------------------------------------------------------------
repair_grub() {
    local noninteractive="${1:-false}"
    log_subheader "Réparation du chargeur GRUB"
    is_operation_completed "grub_repair" && { log_info "Réparation GRUB déjà effectuée."; return 0; }

    if [[ "$noninteractive" != "true" ]]; then
        confirm_action "Réinstaller et reconfigurer GRUB. Opération CRITIQUE." strict || return 1
    fi

    install_repair_dependencies || { log_error "Dépendances manquantes. Réparation annulée."; return 1; }
    backup_partition_tables
    backup_grub_configuration

    local boot_device
    if [[ -n "${FORCE_DISK:-}" ]]; then
        boot_device="$FORCE_DISK"; log_info "Disque forcé : $boot_device"
    else
        boot_device=$(detect_boot_device)
    fi
    if [[ -z "$boot_device" ]]; then
        log_warning "Périphérique de démarrage non détecté automatiquement"
        echo ""; lsblk -d -o NAME,SIZE,TYPE,MODEL | grep -E "^NAME|disk"; echo ""
        read -r -p "Entrez le périphérique de démarrage (ex. /dev/sda) : " boot_device
        [[ ! -b "$boot_device" ]] && { log_error "Périphérique invalide : $boot_device"; return 1; }
    fi
    log_info "Utilisation du périphérique : $boot_device"

    local result=0
    case "$DISTRO_FAMILY" in
        debian) reinstall_grub_debian "$boot_device"; result=$? ;;
        rhel)   reinstall_grub_rhel   "$boot_device"; result=$? ;;
        arch)   reinstall_grub_arch   "$boot_device"; result=$? ;;
        *)      log_error "Réparation GRUB non prise en charge pour : $DISTRO_FAMILY"; return 1 ;;
    esac

    if [[ $result -eq 0 ]]; then
        log_success "Réparation GRUB terminée avec succès"
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

    log_subheader "[1/6] Génération Boot-Info avant réparation"
    generate_boot_info "${BACKUP_DIR}/boot-info-pre-repair.txt"

    log_subheader "[2/6] Sauvegarde des tables de partitions"
    backup_partition_tables

    log_subheader "[3/6] Installation des dépendances"
    install_repair_dependencies || { log_error "Dépendances manquantes. Réparation annulée."; return 1; }

    log_subheader "[4/6] Réinstallation bootloader + initramfs"
    backup_grub_configuration
    local boot_device; boot_device=$(detect_boot_device)
    [[ -z "$boot_device" ]] && { log_error "Périphérique de démarrage introuvable."; return 1; }
    log_info "Disque cible : $boot_device"

    local active_bl; active_bl=$(detect_bootloader)
    log_info "Bootloader détecté : $active_bl"
    local boot_conf_present=false
    { [[ -f /boot/efi/loader/loader.conf ]] || [[ -f /efi/loader/loader.conf ]]; } \
        && boot_conf_present=true

    local result=0
    if [[ "$active_bl" == "systemd-boot" ]] || \
       { [[ "$active_bl" == "both" ]] && [[ "$boot_conf_present" == true ]]; }; then
        log_info "systemd-boot détecté — réparation via bootctl"
        repair_systemd_boot || result=$?
    else
        case "$DISTRO_FAMILY" in
            debian) reinstall_grub_debian "$boot_device"; result=$? ;;
            rhel)   reinstall_grub_rhel   "$boot_device"; result=$? ;;
            arch)   reinstall_grub_arch   "$boot_device"; result=$? ;;
            *)      log_error "Distribution non prise en charge : $DISTRO_FAMILY"; result=1 ;;
        esac
    fi
    [[ $result -ne 0 ]] && { log_error "Réparation du chargeur a échoué"; return $result; }
    repair_initramfs || log_warning "Initramfs : échec ou non disponible"
    mark_operation_completed "grub_repair"

    log_subheader "[4b/6] Vérification Secure Boot"
    local sb_state; sb_state=$(check_secure_boot_status)
    if [[ "$sb_state" == *"enabled"* ]]; then
        log_warning "Secure Boot actif. Si le système ne démarre pas, lancez :"
        log_warning "  sudo $SCRIPT_NAME --advanced → option 11 (MOK enrollment)"
    fi

    log_subheader "[5/6] Détection Windows / EFI Microsoft"
    if [[ $(detect_boot_mode) == "uefi" ]]; then
        repair_windows_efi
    else
        log_info "Mode BIOS/Legacy — vérification Windows non applicable"
    fi

    log_subheader "[6/6] Génération Boot-Info post-réparation"
    generate_boot_info "${BACKUP_DIR}/boot-info-post-repair.txt"

    log_success "Recommended Repair terminé"
    log_info "Boot-Info avant : ${BACKUP_DIR}/boot-info-pre-repair.txt"
    log_info "Boot-Info après : ${BACKUP_DIR}/boot-info-post-repair.txt"
    log_info "Sauvegardes     : ${BACKUP_DIR}"
    echo ""
    read -r -p "Uploader les rapports en ligne ? [o/N] : " do_upload
    [[ "${do_upload,,}" =~ ^[oyoui] ]] && upload_report "${BACKUP_DIR}/boot-info-post-repair.txt"
}

run_advanced_repair() {
    log_header "MENU AVANCÉ"
    run_environment_checks

    _list_disks() {
        echo ""
        printf "%b\n" "${CYAN}${BOLD}Disques détectés sur ce système :${NC}"
        echo "───────────────────────────────────────────────────────────"
        lsblk -d -o NAME,SIZE,TYPE,TRAN,MODEL,SERIAL 2>/dev/null | grep -v "^loop" \
            | awk 'NR==1 {print "  "$0} NR>1 {print "  /dev/"$0}'
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
    printf "%b\n" "${BOLD}║${NC}  9)  Réparer systemd-boot                                         ${BOLD}║${NC}"
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
            [[ ! -b "$FORCE_DISK" ]] && { log_error "Périphérique invalide : $FORCE_DISK"; FORCE_DISK=""; return 1; }
            log_info "Disque sélectionné : $FORCE_DISK"
            repair_grub; FORCE_DISK="" ;;
        2)
            _list_disks
            if confirm_action "Purge GRUB puis réinstallation complète. Opération destructive." strict; then
                backup_partition_tables; backup_grub_configuration
                purge_grub
                # shellcheck disable=SC2034  # déclaré dans Rep-Dem.sh, utilisé par mark/is_operation_completed
                COMPLETED_OPERATIONS["grub_repair"]=""
                repair_grub
            fi ;;
        3)
            echo ""
            echo "  Format à restaurer :"
            echo "  1)  sfdisk (.dump) — MBR/DOS/GPT"
            echo "  2)  sgdisk (.bin)  — GPT uniquement"
            echo ""; read -r -p "Choix [1-2] : " pt_fmt
            case "$pt_fmt" in
                1)
                    local bpt_dir="${BACKUP_DIR}/partition-tables"
                    [[ ! -d "$bpt_dir" ]] && { log_error "Aucune sauvegarde dans $bpt_dir"; return 1; }
                    echo ""; find "$bpt_dir" -maxdepth 1 -name '*.dump' \
                        -printf '  %f  (%s bytes)\n' 2>/dev/null | sort
                    read -r -p "Fichier .dump sfdisk : " dump_file
                    local full_path="${bpt_dir}/${dump_file}"
                    [[ ! -f "$full_path" ]] && { log_error "Fichier introuvable : $full_path"; return 1; }
                    _list_disks
                    read -r -p "Disque cible (ex. /dev/sda) : " target_disk
                    [[ ! -b "$target_disk" ]] && { log_error "Périphérique invalide : $target_disk"; return 1; }
                    if confirm_action "Restaurer $full_path sur $target_disk ? Écrase la table." strict; then
                        if sfdisk "$target_disk" < "$full_path"; then
                            log_success "Table restaurée sur $target_disk"
                        else
                            log_error "Échec sfdisk"
                        fi
                    fi ;;
                2) restore_partition_table_sgdisk ;;
                *) log_warning "Choix invalide" ;;
            esac ;;
        4)
            _list_disks
            boot_device=$(detect_boot_device)
            if [[ -n "$boot_device" ]]; then
                read -r -p "Confirmer le disque ou saisir un autre (Entrée = $boot_device) : " override
                [[ -n "$override" ]] && boot_device="$override"
            else
                read -r -p "Disque cible pour MBR Windows (ex. /dev/sda) : " boot_device
            fi
            [[ ! -b "$boot_device" ]] && { log_error "Périphérique invalide : $boot_device"; return 1; }
            restore_windows_mbr "$boot_device" ;;
        5)  echo ""; repair_windows_efi ;;
        6)
            local bi_file="${BACKUP_DIR}/boot-info.txt"
            generate_boot_info "$bi_file"
            echo ""
            read -r -p "Uploader le rapport en ligne ? [o/N] : " do_upload
            [[ "${do_upload,,}" =~ ^[oyoui] ]] && upload_report "$bi_file" ;;
        7)  echo ""; repair_in_chroot ;;
        8)  configure_grub_menu_options ;;
        9)  repair_systemd_boot ;;
        10)
            echo ""
            printf "%b\n" "${CYAN}${BOLD}État RAID (mdadm) :${NC}"
            echo "───────────────────────────────────────────────────────────"
            cat /proc/mdstat 2>/dev/null || echo "  /proc/mdstat indisponible"
            command_exists mdadm && { echo ""; mdadm --detail --scan 2>/dev/null || echo "  Aucun RAID"; }
            echo ""
            printf "%b\n" "${CYAN}${BOLD}État LVM :${NC}"
            echo "───────────────────────────────────────────────────────────"
            pvs 2>/dev/null || echo "  pvs : indisponible"
            vgs 2>/dev/null || echo "  vgs : indisponible"
            lvs 2>/dev/null || echo "  lvs : indisponible"
            echo "───────────────────────────────────────────────────────────" ;;
        11) enroll_mok_key ;;
        12) return 0 ;;
        *)  log_warning "Choix invalide" ;;
    esac
    echo ""
    read -r -p "Appuyez sur Entrée pour continuer..."
    done
}
