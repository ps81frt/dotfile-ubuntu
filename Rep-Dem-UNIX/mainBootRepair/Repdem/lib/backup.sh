#!/usr/bin/env bash
#===============================================================================
#  backup.sh — Gestion des sauvegardes : fichiers, config GRUB, tables de
#              partitions, et restauration GPT via sgdisk
#  Sourcé automatiquement par Rep-Dem.sh
#===============================================================================

#-------------------------------------------------------------------------------
# SAUVEGARDE DE FICHIERS INDIVIDUELS
#-------------------------------------------------------------------------------
backup_file() {
    local source_file="$1" description="${2:-configuration file}"

    if [[ ! -e "$source_file" ]]; then
        log_debug "Sauvegarde ignorée (fichier introuvable) : $source_file"; return 1
    fi

    if [[ ! -d "$BACKUP_DIR" ]]; then
        if ! mkdir -p "$BACKUP_DIR"; then
            log_error "Impossible de créer le répertoire de sauvegarde : $BACKUP_DIR"; return 1
        fi
        chmod 700 "$BACKUP_DIR"
        log_info "Répertoire de sauvegarde créé : $BACKUP_DIR"
    fi

    local backup_subdir
    backup_subdir="${BACKUP_DIR}$(dirname "$source_file")"
    mkdir -p "$backup_subdir"

    local backup_path
    backup_path="${backup_subdir}/$(basename "$source_file")"
    [[ -e "$backup_path" ]] && backup_path="${backup_path}.$(date +%H%M%S)"

    if cp -a "$source_file" "$backup_path" 2>/dev/null; then
        log_success "Sauvegarde effectuée pour $description : $source_file"
        log_debug "Emplacement : $backup_path"
        return 0
    else
        log_error "Échec de la sauvegarde : $source_file"; return 1
    fi
}

restore_backup() {
    local original_file="$1"
    local backup_path="${BACKUP_DIR}${original_file}"

    if [[ ! -f "$backup_path" ]]; then
        log_error "Aucune sauvegarde trouvée pour : $original_file"; return 1
    fi

    if cp -a "$backup_path" "$original_file"; then
        log_success "Restauré à partir de la sauvegarde : $original_file"; return 0
    else
        log_error "Échec de la restauration : $original_file"; return 1
    fi
}

#-------------------------------------------------------------------------------
# SAUVEGARDE DE LA CONFIGURATION GRUB
#-------------------------------------------------------------------------------
backup_grub_configuration() {
    echo ""
    printf "%b\n" "${YELLOW}${BOLD}[BACKUP]${NC} Configuration GRUB → ${BACKUP_DIR}/etc/"

    local grub_files=("/etc/default/grub" "/boot/grub/grub.cfg" "/boot/grub2/grub.cfg")
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

#-------------------------------------------------------------------------------
# SAUVEGARDE DES TABLES DE PARTITIONS
#-------------------------------------------------------------------------------
backup_partition_tables() {
    local bpt_dir="${BACKUP_DIR}/partition-tables"
    mkdir -p "$bpt_dir"
    echo ""
    printf "%b\n" "${YELLOW}${BOLD}[BACKUP]${NC} Tables de partitions → ${bpt_dir}"

    while read -r disk; do
        local dev="/dev/$disk"
        [[ ! -b "$dev" ]] && continue
        command_exists sgdisk && \
            sgdisk --backup="${bpt_dir}/${disk}-sgdisk.bin" "$dev" 2>/dev/null \
            && log_success "  sgdisk  : ${bpt_dir}/${disk}-sgdisk.bin"
        command_exists sfdisk && \
            sfdisk --dump "$dev" > "${bpt_dir}/${disk}-sfdisk.dump" 2>/dev/null \
            && log_success "  sfdisk  : ${bpt_dir}/${disk}-sfdisk.dump"
        dd if="$dev" of="${bpt_dir}/${disk}-mbr512.bin" bs=512 count=1 status=none 2>/dev/null \
            && log_success "  MBR 512B: ${bpt_dir}/${disk}-mbr512.bin"
    done < <(lsblk -dn -o NAME 2>/dev/null | grep -vE '^(loop|ram)')

    echo ""
    printf "%b\n" "${GREEN}${BOLD}[BACKUP OK]${NC} Tables sauvegardées dans : ${bpt_dir}"
    echo ""
}

#-------------------------------------------------------------------------------
# RESTAURATION TABLE GPT VIA SGDISK --LOAD-BACKUP
#-------------------------------------------------------------------------------
restore_partition_table_sgdisk() {
    local bpt_dir="${BACKUP_DIR}/partition-tables"

    if [[ ! -d "$bpt_dir" ]]; then
        log_error "Aucune sauvegarde sgdisk disponible dans $bpt_dir"; return 1
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
        log_error "Fichier introuvable : $full_path"; return 1
    fi

    local suggested_disk
    suggested_disk="/dev/$(basename "$bin_file" | sed 's/-sgdisk\.bin$//')"
    echo ""
    lsblk -d -o NAME,SIZE,TYPE,TRAN,MODEL 2>/dev/null | grep -v loop \
        | awk 'NR==1{print "  "$0} NR>1{print "  /dev/"$0}'
    echo ""
    read -r -p "Disque cible (Entrée = $suggested_disk) : " target_disk
    target_disk="${target_disk:-$suggested_disk}"

    if [[ ! -b "$target_disk" ]]; then
        log_error "Périphérique invalide : $target_disk"; return 1
    fi

    echo ""
    printf "%b\n" "${RED}${BOLD}╔══════════════════════════════════════════════════════════════╗${NC}"
    printf "%b\n" "${RED}${BOLD}║  AVERTISSEMENT CRITIQUE                                      ║${NC}"
    printf "%b\n" "${RED}${BOLD}║  sgdisk --load-backup écrase la table GPT PRINCIPALE         ║${NC}"
    printf "%b\n" "${RED}${BOLD}║  ET DE SAUVEGARDE du disque cible.                           ║${NC}"
    printf "%b\n" "${RED}${BOLD}║  Un mauvais disque cible est IRRÉCUPÉRABLE.                  ║${NC}"
    printf "%b\n" "${RED}${BOLD}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    log_info "Source  : $full_path"
    log_info "Cible   : $target_disk"
    echo ""

    if ! confirm_action \
        "Restaurer la table GPT de $full_path sur $target_disk ? Action IRRÉVERSIBLE." strict; then
        return 0
    fi

    local ts; ts=$(date +%H%M%S)
    local emergency_backup="${bpt_dir}/${target_disk##*/}-sgdisk-pre-restore-${ts}.bin"
    command_exists sgdisk && \
        sgdisk --backup="$emergency_backup" "$target_disk" 2>/dev/null \
        && log_success "Sauvegarde d'urgence GPT créée : $emergency_backup"
    dd if="$target_disk" of="${bpt_dir}/${target_disk##*/}-mbr-pre-restore-${ts}.bin" \
        bs=512 count=1 status=none 2>/dev/null \
        && log_success "MBR d'urgence sauvegardé"

    log_info "Restauration GPT via sgdisk --load-backup..."
    sgdisk --load-backup="$full_path" "$target_disk" 2>&1 \
        | while read -r line; do log_info "sgdisk: $line"; done
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
        sgdisk --print "$target_disk" 2>/dev/null \
            | while read -r line; do printf '  %s\n' "$line"; done
        return 0
    else
        log_error "Échec de sgdisk --load-backup"
        log_info "Tentative manuelle : sudo sgdisk --load-backup=\"$full_path\" $target_disk"
        return 1
    fi
}
