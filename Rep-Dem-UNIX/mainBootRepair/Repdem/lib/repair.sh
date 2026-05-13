#!/usr/bin/env bash
#===============================================================================
#  repair.sh — Réparation initramfs, vérification filesystème (fsck),
#              et réparation via chroot depuis un live USB
#  Sourcé automatiquement par Rep-Dem.sh
#===============================================================================

#-------------------------------------------------------------------------------
# INITRAMFS
#-------------------------------------------------------------------------------
repair_initramfs() {
    if is_operation_completed "initramfs_repair"; then
        log_info "Régénération initramfs déjà effectuée durant cette session"; return 0
    fi

    local cmd="" manual_help=""
    case "$DISTRO_FAMILY" in
        debian)  cmd="update-initramfs -u -k all" ;;
        rhel)    cmd="dracut -f" ;;
        arch)    cmd="mkinitcpio -P" ;;
        suse)    manual_help="Commande manuelle : sudo mkinitrd" ;;
        void)    manual_help="Commande manuelle : sudo dracut --force" ;;
        gentoo)  manual_help="Commande manuelle : sudo genkernel --install initramfs" ;;
        *)       manual_help="Famille inconnue : $DISTRO_FAMILY. Régénérez l'initramfs manuellement." ;;
    esac

    if [[ -n "$cmd" ]]; then
        local tool; tool=$(printf '%s' "$cmd" | awk '{print $1}')
        if ! command_exists "$tool"; then
            log_warning "Outil introuvable : $tool"
            echo ""
            echo "  Pour régénérer l'initramfs manuellement :"
            echo "  - Debian/Ubuntu : sudo update-initramfs -u -k all"
            echo "  - RHEL/Fedora   : sudo dracut -f"
            echo "  - Arch Linux    : sudo mkinitcpio -P"
            echo ""
            confirm_action "Voulez-vous que le script essaie d'installer $tool ?" yes \
                || return 1
            install_packages "$tool" || return 1
        fi

        log_info "Mise à jour de l'initramfs avec : $cmd"
        eval "$cmd" 2>&1 | while read -r line; do log_debug "$line"; done
        if [[ ${PIPESTATUS[0]} -eq 0 ]]; then
            log_success "Initramfs régénéré avec succès"
            mark_operation_completed "initramfs_repair"; return 0
        fi
        log_error "Échec de la régénération de l'initramfs"; return 1
    else
        log_warning "Régénération automatique non disponible pour $DISTRO_FAMILY"
        echo ""
        echo "╔══════════════════════════════════════════════════════════════════╗"
        echo "║  INITRAMFS : ACTION MANUELLE REQUISE                             ║"
        echo "╚══════════════════════════════════════════════════════════════════╝"
        echo ""
        echo "  $manual_help"
        echo ""
        echo "  Pourquoi c'est important ? Un initramfs obsolète peut causer :"
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
                    mark_operation_completed "initramfs_repair"; return 0
                fi
                log_error "Échec de dracut"
            fi
            if command_exists mkinitramfs; then
                log_info "Tentative avec mkinitramfs..."
                mkinitramfs -o "/boot/initrd.img-$(uname -r)" "$(uname -r)" 2>&1 \
                    | while read -r line; do log_debug "$line"; done
                if [[ ${PIPESTATUS[0]} -eq 0 ]]; then
                    log_success "Initramfs régénéré via mkinitramfs"
                    mark_operation_completed "initramfs_repair"; return 0
                fi
                log_error "Échec de mkinitramfs"
            fi
            log_error "Aucune méthode générique n'a réussi"
            echo "  $manual_help"
            echo ""
            read -r -p "Appuyez sur Entrée après avoir effectué la régénération manuelle..."
            mark_operation_completed "initramfs_repair"; return 0
        else
            log_warning "Régénération initramfs ignorée. Le système pourrait ne pas démarrer."
            return 1
        fi
    fi
}

#-------------------------------------------------------------------------------
# VÉRIFICATION SYSTÈMES DE FICHIERS (FSCK)
#-------------------------------------------------------------------------------
repair_filesystem_health() {
    if ! command_exists fsck; then
        log_warning "fsck non disponible, réparation des systèmes de fichiers impossible"
        return 1
    fi

    log_subheader "Vérification des systèmes de fichiers"

    local root_device boot_device devices=()
    root_device=$(findmnt -n -o SOURCE / 2>/dev/null || true)
    boot_device=$(findmnt -n -o SOURCE /boot 2>/dev/null || true)
    [[ -n "$root_device" ]] && devices+=("$root_device")
    [[ -n "$boot_device" && "$boot_device" != "$root_device" ]] && devices+=("$boot_device")

    if [[ -f /etc/fstab ]]; then
        while read -r spec _mount _point type rest; do
            [[ -z "$spec" || "$spec" == \#* ]] && continue
            case "$type" in
                swap|tmpfs|proc|sysfs|cgroup*|debugfs|devtmpfs|devpts|overlay) continue ;;
            esac
            if [[ "$spec" =~ ^/dev/ ]] && [[ " ${devices[*]} " != *" $spec "* ]]; then
                devices+=("$spec")
            fi
        done < /etc/fstab
    fi

    local device mountpoint
    for device in "${devices[@]}"; do
        mountpoint=$(findmnt -n -o TARGET "$device" 2>/dev/null || true)
        if [[ -z "$mountpoint" ]]; then
            log_info "Périphérique non monté détecté : $device"
            if confirm_action \
                "Exécuter fsck -f -y sur $device ? Cette opération peut réparer des erreurs." strict; then
                fsck -f -y "$device" 2>&1 | while read -r line; do log_debug "$line"; done
                log_success "fsck appliqué sur $device"
            else
                log_warning "Réparation fsck annulée pour $device"
            fi
        else
            log_warning "$device est monté sur $mountpoint. fsck en lecture seule uniquement."
            fsck -N "$device" 2>&1 | while read -r line; do log_debug "$line"; done
        fi
    done
    return 0
}

#-------------------------------------------------------------------------------
# RÉPARATION VIA CHROOT (live USB → système installé)
#-------------------------------------------------------------------------------
_chroot_cleanup() {
    local chroot_dir="$1"
    log_info "Démontage du chroot $chroot_dir..."
    for sub in /sys/firmware/efi/efivars /run /sys /proc /dev/pts /dev /boot/efi /boot; do
        umount "${chroot_dir}${sub}" 2>/dev/null || true
    done
    umount "$chroot_dir" 2>/dev/null || true
    rmdir  "$chroot_dir" 2>/dev/null || true
    log_info "Chroot démonté"
}

repair_in_chroot() {
    log_header "RÉPARATION EN CHROOT"
    echo ""
    log_info "Scan des partitions Linux disponibles..."

    local tmp_mnt; tmp_mnt=$(mktemp -d /tmp/rd_probe_XXXXXX)
    local idx=0
    declare -A inst_map
    local -a installs=()

    while read -r part; do
        local dev="/dev/$part"
        if mount -o ro "$dev" "$tmp_mnt" 2>/dev/null; then
            if [[ -f "$tmp_mnt/etc/os-release" ]]; then
                local name
                name=$(grep -m1 '^PRETTY_NAME=' "$tmp_mnt/etc/os-release" 2>/dev/null \
                       | tr -d '"' | cut -d= -f2-)
                idx=$(( idx + 1 ))
                inst_map[$idx]="$dev"
                installs+=( "  $idx) $dev  —  ${name:-inconnu}" )
            fi
            umount "$tmp_mnt" 2>/dev/null
        fi
    done < <(lsblk -lno NAME,TYPE,FSTYPE \
             | awk '$2=="part" && ($3~/^(ext[234]|btrfs|xfs)$/) {print $1}')
    rmdir "$tmp_mnt" 2>/dev/null

    if (( ${#installs[@]} == 0 )); then
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
        log_error "Sélection invalide"; return 1
    fi

    local chroot_dir; chroot_dir=$(mktemp -d /tmp/rd_chroot_XXXXXX)
    log_info "Montage de $root_dev sur $chroot_dir..."
    if ! mount "$root_dev" "$chroot_dir"; then
        log_error "Impossible de monter $root_dev"; rmdir "$chroot_dir"; return 1
    fi

    if [[ -f "$chroot_dir/etc/fstab" ]]; then
        local boot_dev efi_dev
        boot_dev=$(awk '$2=="/boot" && $1!~/^#/{print $1}' "$chroot_dir/etc/fstab" | head -1)
        efi_dev=$(awk '$2=="/boot/efi" && $1!~/^#/{print $1}' "$chroot_dir/etc/fstab" | head -1)
        if [[ -n "$boot_dev" && -b "$boot_dev" ]]; then
            mount "$boot_dev" "$chroot_dir/boot" 2>/dev/null \
                || log_warning "Impossible de monter /boot"
        fi
        if [[ -n "$efi_dev" && -b "$efi_dev" ]]; then
            mkdir -p "$chroot_dir/boot/efi"
            mount "$efi_dev" "$chroot_dir/boot/efi" 2>/dev/null \
                || log_warning "Impossible de monter /boot/efi"
        fi
    fi

    for d in /dev /dev/pts /proc /sys /run; do
        mkdir -p "${chroot_dir}${d}"
        mount -R "$d" "${chroot_dir}${d}" 2>/dev/null \
            || mount --bind "$d" "${chroot_dir}${d}" 2>/dev/null \
            || log_warning "mount $d échoué"
    done
    if [[ -d /sys/firmware/efi/efivars ]]; then
        mkdir -p "$chroot_dir/sys/firmware/efi/efivars"
        mount --bind /sys/firmware/efi/efivars \
              "$chroot_dir/sys/firmware/efi/efivars" 2>/dev/null || true
    fi

    local chroot_family="debian"
    if [[ -f "$chroot_dir/etc/os-release" ]]; then
        local chroot_id
        chroot_id=$(grep -m1 '^ID_LIKE=' "$chroot_dir/etc/os-release" 2>/dev/null \
                    | cut -d= -f2 | tr -d '"')
        [[ -z "$chroot_id" ]] && \
            chroot_id=$(grep -m1 '^ID=' "$chroot_dir/etc/os-release" | cut -d= -f2 | tr -d '"')
        case "${chroot_id,,}" in
            *debian*|*ubuntu*|*mint*)                chroot_family="debian" ;;
            *fedora*|*rhel*|*centos*|*rocky*|*alma*) chroot_family="rhel"   ;;
            *arch*|*manjaro*|*endeavour*)            chroot_family="arch"   ;;
            *suse*)                                  chroot_family="suse"   ;;
        esac
    fi

    local grub_disk; grub_disk=$(detect_boot_device)
    if [[ -z "$grub_disk" ]]; then
        echo ""
        lsblk -d -o NAME,SIZE,TYPE,TRAN,MODEL 2>/dev/null \
            | grep -v loop | awk 'NR==1{print "  "$0} NR>1{print "  /dev/"$0}'
        echo ""
        read -r -p "Disque cible pour GRUB (ex. /dev/sda) : " grub_disk
    fi
    if [[ ! -b "$grub_disk" ]]; then
        log_error "Disque invalide : $grub_disk"
        _chroot_cleanup "$chroot_dir"; return 1
    fi

    local boot_mode; boot_mode=$(detect_boot_mode)
    local target_uefi=false
    { [[ -d "$chroot_dir/boot/efi/EFI" ]] || [[ -d "$chroot_dir/efi/EFI" ]] \
      || [[ -f "$chroot_dir/boot/efi/loader/loader.conf" ]]; } && target_uefi=true

    local chroot_uses_sd=false
    if [[ "$boot_mode" == "uefi" || "$target_uefi" == true ]]; then
        local _id_chroot
        _id_chroot=$(grep -m1 '^ID=' "$chroot_dir/etc/os-release" 2>/dev/null \
                     | cut -d= -f2 | tr -d '"')
        [[ "${_id_chroot,,}" == "pop" ]] && chroot_uses_sd=true
        { [[ -f "$chroot_dir/boot/efi/loader/loader.conf" ]] \
          || [[ -f "$chroot_dir/efi/loader/loader.conf" ]]; } && chroot_uses_sd=true
    fi

    if [[ "$chroot_uses_sd" == true ]]; then
        log_info "Système cible utilise systemd-boot — réparation via bootctl"
        local sd_cmd="update-initramfs -c -k all 2>/dev/null || mkinitcpio -P 2>/dev/null; exit"
        chroot "$chroot_dir" /bin/bash -c "$sd_cmd" 2>&1 \
            | while read -r line; do log_info "chroot: $line"; done
        local chroot_esp=""
        for _e in "$chroot_dir/boot/efi" "$chroot_dir/efi" "$chroot_dir/boot"; do
            { [[ -d "$_e/EFI" ]] || [[ -f "$_e/loader/loader.conf" ]]; } \
                && chroot_esp="$_e" && break
        done
        if [[ -n "$chroot_esp" ]]; then
            if bootctl install --esp-path="$chroot_esp" 2>&1 \
                | while read -r line; do log_info "bootctl: $line"; done; then
                log_success "systemd-boot réinstallé via chroot (esp=$chroot_esp)"
            else
                log_error "Échec bootctl install via chroot"
            fi
        else
            log_warning "ESP introuvable dans le chroot"
        fi
        _chroot_cleanup "$chroot_dir"; return 0
    fi

    local grub_cmd
    case "$chroot_family" in
        debian)
            if [[ "$boot_mode" == "uefi" || "$target_uefi" == true ]]; then
                grub_cmd="grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=GRUB --recheck && update-grub"
            else
                grub_cmd="grub-install --target=i386-pc --recheck ${grub_disk} && update-grub"
            fi ;;
        rhel)
            if [[ "$boot_mode" == "uefi" || "$target_uefi" == true ]]; then
                grub_cmd="grub2-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=GRUB --recheck && grub2-mkconfig -o /boot/grub2/grub.cfg"
            else
                grub_cmd="grub2-install --target=i386-pc --recheck ${grub_disk} && grub2-mkconfig -o /boot/grub2/grub.cfg"
            fi ;;
        arch)
            if [[ "$boot_mode" == "uefi" || "$target_uefi" == true ]]; then
                grub_cmd="grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=GRUB --recheck && grub-mkconfig -o /boot/grub/grub.cfg"
            else
                grub_cmd="grub-install --target=i386-pc --recheck ${grub_disk} && grub-mkconfig -o /boot/grub/grub.cfg"
            fi ;;
        suse)
            if [[ "$boot_mode" == "uefi" || "$target_uefi" == true ]]; then
                grub_cmd="grub2-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=grub --recheck && grub2-mkconfig -o /boot/grub2/grub.cfg"
            else
                grub_cmd="grub2-install --target=i386-pc --recheck ${grub_disk} && grub2-mkconfig -o /boot/grub2/grub.cfg"
            fi ;;
        *)
            grub_cmd="grub-install --recheck ${grub_disk} 2>/dev/null; update-grub 2>/dev/null || grub-mkconfig -o /boot/grub/grub.cfg 2>/dev/null" ;;
    esac

    log_info "Commande chroot : $grub_cmd"
    if chroot "$chroot_dir" /bin/bash -c "$grub_cmd" 2>&1 \
       | while read -r line; do log_info "chroot: $line"; done; then
        log_success "GRUB réinstallé avec succès via chroot"
    else
        log_error "Échec de la réinstallation GRUB dans le chroot"
    fi

    _chroot_cleanup "$chroot_dir"
}

#-------------------------------------------------------------------------------
# VÉRIFICATION DES OUTILS REQUIS (Live ISO)
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

    if (( ${#missing_req[@]} > 0 )); then
        log_error "Outils obligatoires manquants : ${missing_req[*]}"
        log_error "Impossible de continuer sans ces outils."
        return 1
    fi
    log_success "Outils obligatoires : tous présents"

    if (( ${#missing_rec[@]} > 0 )); then
        log_warning "Outils recommandés absents : ${missing_rec[*]}"
        confirm_action "Installer ces outils temporairement sur le Live ISO ?" yes || {
            log_warning "Certaines opérations pourraient être limitées."; return 0
        }
        local live_pm=""
        command_exists apt-get && live_pm="apt-get"
        command_exists pacman  && [[ -z "$live_pm" ]] && live_pm="pacman"
        command_exists dnf     && [[ -z "$live_pm" ]] && live_pm="dnf"
        command_exists zypper  && [[ -z "$live_pm" ]] && live_pm="zypper"
        if [[ -z "$live_pm" ]]; then
            log_warning "Gestionnaire de paquets introuvable sur le Live ISO."
            return 0
        fi
        log_info "Installation via $live_pm : ${missing_rec[*]}"
        case "$live_pm" in
            apt-get) apt-get install -y "${missing_rec[@]}" 2>&1 | while read -r l; do log_debug "$l"; done ;;
            pacman)  pacman -Sy --noconfirm "${missing_rec[@]}" 2>&1 | while read -r l; do log_debug "$l"; done ;;
            dnf)     dnf install -y "${missing_rec[@]}" 2>&1 | while read -r l; do log_debug "$l"; done ;;
            zypper)  zypper install -y "${missing_rec[@]}" 2>&1 | while read -r l; do log_debug "$l"; done ;;
        esac
        log_success "Installation des outils recommandés terminée"
    else
        log_success "Outils recommandés : tous présents"
    fi
    return 0
}

#-------------------------------------------------------------------------------
# NETTOYAGE AUTO-CHROOT (appelé par le trap global)
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
        if mountpoint -q "$sub" 2>/dev/null; then
            if umount -lf "$sub" 2>/dev/null; then
                log_info "  Démonté : $sub"
            fi
        fi
    done
    if mountpoint -q "$target" 2>/dev/null; then
        if umount -lf "$target" 2>/dev/null; then
            log_success "Partition root démontée : $target"
        fi
    fi
    CHROOT_TARGET=""
}

#-------------------------------------------------------------------------------
# AUTO-SCAN ET CHROOT DEPUIS UN LIVE ISO
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
        CHROOT_TARGET="$target_dir"; _autochroot_cleanup
    fi
    mkdir -p "$target_dir"

    log_info "Scan des partitions (ext2/3/4, btrfs, xfs, f2fs, jfs, reiserfs)..."
    echo ""

    local tmp_mnt; tmp_mnt=$(mktemp -d /tmp/rd_scan_XXXXXX)
    local idx=0
    declare -A scan_map
    local -a found_systems=()

    while read -r dev; do
        [[ -b "$dev" ]] || continue
        local fstype; fstype=$(blkid -s TYPE -o value "$dev" 2>/dev/null)
        case "$fstype" in
            ext2|ext3|ext4|btrfs|xfs|f2fs|jfs|reiserfs) ;;
            *) continue ;;
        esac
        if mount -o ro,noatime "$dev" "$tmp_mnt" 2>/dev/null; then
            if [[ -f "$tmp_mnt/etc/os-release" ]]; then
                idx=$(( idx + 1 ))
                local name uuid
                name=$(grep -m1 '^PRETTY_NAME=' "$tmp_mnt/etc/os-release" 2>/dev/null \
                       | tr -d '"' | cut -d= -f2-)
                uuid=$(blkid -s UUID -o value "$dev" 2>/dev/null || echo "—")
                scan_map[$idx]="$dev"
                found_systems+=( "$(printf "  %2d)  %-22s  %-30s  UUID: %s" \
                    "$idx" "$dev" "${name:-Linux}" "$uuid")" )
            fi
            umount "$tmp_mnt" 2>/dev/null || true
        fi
    done < <(lsblk -lno PATH,TYPE 2>/dev/null | awk '$2=="part"{print $1}' | sort)
    rmdir "$tmp_mnt" 2>/dev/null || true

    if (( ${#found_systems[@]} == 0 )); then
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
    CHROOT_TARGET="$target_dir"  # enregistré pour le trap global

    # --- Partitions séparées via /etc/fstab du système cible ---
    if [[ -f "$target_dir/etc/fstab" ]]; then
        log_info "Analyse de $target_dir/etc/fstab pour les partitions séparées..."
        while read -r spec mountpt fstype _opts _dump _pass; do
            [[ -z "$spec" || "$spec" == \#* ]] && continue
            [[ "$mountpt" == "/" ]] && continue
            case "$fstype" in
                swap|tmpfs|proc|sysfs|devtmpfs|devpts|overlay|cgroup*|none|auto) continue ;;
            esac
            local real_dev=""
            case "$spec" in
                UUID=*)     real_dev=$(blkid -U "${spec#UUID=}" 2>/dev/null) ;;
                PARTUUID=*) real_dev=$(blkid -l -t PARTUUID="${spec#PARTUUID=}" -o device 2>/dev/null) ;;
                LABEL=*)    real_dev=$(blkid -L "${spec#LABEL=}" 2>/dev/null) ;;
                /dev/*)     real_dev="$spec" ;;
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
        done < "$target_dir/etc/fstab"
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
    local script_in_chroot="${target_dir}/tmp/Rep-Dem"
    mkdir -p "$script_in_chroot"
    if ! cp -r "$SCRIPT_DIR/." "$script_in_chroot/"; then
        log_error "Impossible de copier le script dans le chroot : $script_in_chroot"
        _autochroot_cleanup; return 1
    fi
    chmod +x "${script_in_chroot}/Rep-Dem.sh" 2>/dev/null

    echo ""
    log_success "Environnement chroot prêt. Lancement de la réparation sur $root_dev..."
    printf "%b\n" "${YELLOW}${BOLD}[CHROOT]${NC} Les commandes suivantes s'exécutent sur le système installé."
    echo ""

    # --- Relancement du script à l'intérieur du chroot ---
    chroot "$target_dir" /bin/bash /tmp/Rep-Dem/Rep-Dem.sh --inside-chroot
    local chroot_exit=$?

    log_info "Session chroot terminée (code : $chroot_exit)"
    _autochroot_cleanup
    return $chroot_exit
}
