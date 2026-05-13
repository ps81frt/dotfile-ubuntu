#!/usr/bin/env bash
# =============================================================================
#  lvm-manager.sh — Gestionnaire LVM interactif
# =============================================================================
#  Description : Script tout-en-un pour gérer LVM sur Debian/Ubuntu/RHEL/Rocky
#                Diagnostic, création, extension, réduction, déplacement à chaud,
#                migration OS, snapshots — accessible aux débutants.
#
#  Compatibilité : Debian 10+, Ubuntu 20.04+, RHEL 8+, Rocky/Alma 8+
#  Dépendances   : lvm2, util-linux, e2fsprogs (ext4), xfsprogs (xfs)
#  Exécution     : sudo bash lvm-manager.sh
#
#  Auteur        : <ton-nom>
#  Licence       : MIT
#  Version       : 1.0.0
# =============================================================================

set -euo pipefail

# ─── Couleurs & mise en forme ──────────────────────────────────────────────
RED='\033[0;31m'
YEL='\033[0;33m'
GRN='\033[0;32m'
BLU='\033[0;34m'
CYN='\033[0;36m'
WHT='\033[1;37m'
DIM='\033[2m'
BLD='\033[1m'
RST='\033[0m'

# ─── Fonctions d'affichage ─────────────────────────────────────────────────
info() { echo -e "${BLU}[INFO]${RST}  $*"; }
ok() { echo -e "${GRN}[  OK]${RST}  $*"; }
warn() { echo -e "${YEL}[WARN]${RST}  $*"; }
error() { echo -e "${RED}[ERREUR]${RST} $*" >&2; }
die() {
    error "$*"
    exit 1
}
sep() { echo -e "${DIM}────────────────────────────────────────────────────${RST}"; }
title() { echo -e "\n${BLD}${CYN}══ $* ══${RST}\n"; }
confirm() {
    local msg="${1:-Continuer ?}"
    echo -en "${YEL}[?]${RST} ${msg} ${DIM}(o/N)${RST} "
    read -r ans
    [[ "${ans,,}" == "o" || "${ans,,}" == "oui" || "${ans,,}" == "y" || "${ans,,}" == "yes" ]]
}

# ─── Vérifications préalables ──────────────────────────────────────────────
check_root() {
    [[ $EUID -eq 0 ]] || die "Ce script doit être exécuté en root (sudo bash $0)"
}

check_deps() {
    local missing=()
    for cmd in lvm pvs vgs lvs pvdisplay vgdisplay lvdisplay \
        pvcreate vgcreate lvcreate lvextend lvreduce lvremove \
        pvmove vgextend vgreduce pvremove lsblk blkid df; do
        command -v "$cmd" &>/dev/null || missing+=("$cmd")
    done
    if [[ ${#missing[@]} -gt 0 ]]; then
        warn "Commandes manquantes : ${missing[*]}"
        info "Installation de lvm2..."
        if command -v apt-get &>/dev/null; then
            apt-get install -y lvm2 e2fsprogs xfsprogs
        elif command -v dnf &>/dev/null; then
            dnf install -y lvm2 e2fsprogs xfsprogs
        elif command -v yum &>/dev/null; then
            yum install -y lvm2 e2fsprogs xfsprogs
        else
            die "Gestionnaire de paquets non reconnu. Installez lvm2 manuellement."
        fi
    fi
}

# ─── Bannière ──────────────────────────────────────────────────────────────
banner() {
    #clear
    echo -e "${BLD}${CYN}"
    cat <<'EOF'
  ██╗     ██╗   ██╗███╗   ███╗    ███╗   ███╗ ██████╗ ██████╗
  ██║     ██║   ██║████╗ ████║    ████╗ ████║██╔════╝ ██╔══██╗
  ██║     ██║   ██║██╔████╔██║    ██╔████╔██║██║  ███╗██████╔╝
  ██║     ╚██╗ ██╔╝██║╚██╔╝██║    ██║╚██╔╝██║██║   ██║██╔══██╗
  ███████╗ ╚████╔╝ ██║ ╚═╝ ██║    ██║ ╚═╝ ██║╚██████╔╝██║  ██║
  ╚══════╝  ╚═══╝  ╚═╝     ╚═╝    ╚═╝     ╚═╝ ╚═════╝ ╚═╝  ╚═╝
EOF
    echo -e "${RST}${DIM}  Gestionnaire LVM interactif v1.0.0 — Debian/Ubuntu/RHEL/Rocky${RST}"
    echo -e "${DIM}  Exécuté en tant que : $(whoami) | $(date '+%Y-%m-%d %H:%M:%S')${RST}\n"
}

# ═══════════════════════════════════════════════════════════════════════════
#  MODULE 1 — DIAGNOSTIC COMPLET
# ═══════════════════════════════════════════════════════════════════════════
diag_full() {
    title "DIAGNOSTIC LVM COMPLET"

    echo -e "${BLD}▶ Disques et partitions (lsblk)${RST}"
    sep
    lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT,UUID | head -60
    echo

    echo -e "${BLD}▶ Physical Volumes (PV)${RST}"
    sep
    pvs -o pv_name,pv_size,pv_free,pv_used,pv_uuid,vg_name 2>/dev/null || warn "Aucun PV trouvé"
    echo

    echo -e "${BLD}▶ Volume Groups (VG)${RST}"
    sep
    vgs -o vg_name,vg_size,vg_free,vg_extent_size,pv_count,lv_count 2>/dev/null || warn "Aucun VG trouvé"
    echo

    echo -e "${BLD}▶ Logical Volumes (LV)${RST}"
    sep
    lvs -o lv_path,lv_size,lv_attr,seg_type,origin,data_percent,metadata_percent,copy_percent 2>/dev/null || warn "Aucun LV trouvé"
    echo

    echo -e "${BLD}▶ Systèmes de fichiers montés${RST}"
    sep
    df -hT | grep -E "^/dev/mapper|^/dev/[sv]d|Filesystem" || true
    echo

    echo -e "${BLD}▶ Résumé rapide${RST}"
    sep
    local pv_count vg_count lv_count
    pv_count=$(pvs --noheadings 2>/dev/null | wc -l)
    vg_count=$(vgs --noheadings 2>/dev/null | wc -l)
    lv_count=$(lvs --noheadings 2>/dev/null | wc -l)
    echo -e "  PV : ${BLD}${pv_count}${RST}   VG : ${BLD}${vg_count}${RST}   LV : ${BLD}${lv_count}${RST}"
    echo

    echo -e "${BLD}▶ ZRAM (swap compressé)${RST}"
    sep
    if lsmod | grep -q zram; then
        echo -e "  ${GRN}Zram actif${RST}"
        echo -e "  Algorithmes dispo : $(cat /sys/block/zram0/comp_algorithm 2>/dev/null || echo 'N/A')"
        for dev in /sys/block/zram*/disksize; do
            if [[ -f "$dev" ]]; then
                size=$(cat "$dev" 2>/dev/null)
                name=$(echo "$dev" | cut -d/ -f4)
                echo "  $name : $(numfmt --to=iec $size 2>/dev/null || echo $size)"
            fi
        done
        echo -e "  Swaps actifs :"
        swapon --show | grep -E "zram|NAME" | sed 's/^/    /'
    else
        echo -e "  ${DIM}Aucun zram actif${RST}"
    fi
    echo

    ok "Diagnostic terminé."
    pause
}

# ═══════════════════════════════════════════════════════════════════════════
#  MODULE 2 — CRÉER UN NOUVEAU LV
# ═══════════════════════════════════════════════════════════════════════════
create_lv() {
    title "CRÉER UN LOGICAL VOLUME"

    echo -e "${BLD}▶ Volume Groups disponibles :${RST}"
    vgs --noheadings -o vg_name,vg_size,vg_free 2>/dev/null || die "Aucun VG trouvé. Créez d'abord un PV et un VG."
    echo

    read -rp "$(echo -e "${CYN}Nom du VG cible${RST} : ")" VG_NAME
    vgs "$VG_NAME" &>/dev/null || die "VG '$VG_NAME' introuvable."

    read -rp "$(echo -e "${CYN}Nom du nouveau LV${RST} (ex: data, backup) : ")" LV_NAME
    [[ -z "$LV_NAME" ]] && die "Nom de LV vide."

    local vg_free
    vg_free=$(vgs --noheadings --units g -o vg_free "$VG_NAME" | tr -d ' g')
    info "Espace libre dans $VG_NAME : ${vg_free}G"

    read -rp "$(echo -e "${CYN}Taille${RST} (ex: 10G, 500M, 100%FREE) : ")" LV_SIZE

    echo -e "\n${BLD}▶ Choisir le système de fichiers :${RST}"
    echo "  1) ext4  (recommandé, supporte shrink)"
    echo "  2) xfs   (performant, pas de shrink)"
    echo "  3) Aucun (raw, pas de formatage)"
    read -rp "$(echo -e "${CYN}Choix${RST} [1-3] : ")" fs_choice

    sep
    info "Création du LV '$LV_NAME' (${LV_SIZE}) dans VG '$VG_NAME'..."
    confirm "Confirmer ?" || {
        warn "Annulé."
        return
    }

    if [[ "$LV_SIZE" == *"%FREE"* ]]; then
        lvcreate -l "$LV_SIZE" -n "$LV_NAME" "$VG_NAME"
    else
        lvcreate -L "$LV_SIZE" -n "$LV_NAME" "$VG_NAME"
    fi

    local lv_path="/dev/$VG_NAME/$LV_NAME"

    case "$fs_choice" in
    1)
        info "Formatage en ext4..."
        mkfs.ext4 -L "$LV_NAME" "$lv_path"
        ;;
    2)
        info "Formatage en xfs..."
        mkfs.xfs -L "$LV_NAME" "$lv_path"
        ;;
    3)
        warn "Aucun formatage — volume raw créé."
        ;;
    esac

    ok "LV créé : $lv_path"

    if [[ "$fs_choice" != "3" ]]; then
        echo
        read -rp "$(echo -e "${CYN}Point de montage${RST} (laisser vide pour ne pas monter) : ")" MOUNT_PT
        if [[ -n "$MOUNT_PT" ]]; then
            mkdir -p "$MOUNT_PT"
            mount "$lv_path" "$MOUNT_PT"
            ok "Monté sur $MOUNT_PT"

            if confirm "Ajouter à /etc/fstab (montage permanent) ?"; then
                local uuid
                uuid=$(blkid -s UUID -o value "$lv_path")
                echo "UUID=$uuid  $MOUNT_PT  $(blkid -s TYPE -o value "$lv_path")  defaults  0  2" >>/etc/fstab
                ok "Entrée ajoutée dans /etc/fstab (UUID: $uuid)"
            fi
        fi
    fi
    pause
}

# ═══════════════════════════════════════════════════════════════════════════
#  MODULE 3 — ÉTENDRE UN LV (à chaud)
# ═══════════════════════════════════════════════════════════════════════════
extend_lv() {
    title "ÉTENDRE UN LOGICAL VOLUME (à chaud)"

    echo -e "${BLD}▶ Logical Volumes disponibles :${RST}"
    lvs --noheadings -o lv_path,lv_size,vg_free 2>/dev/null
    echo

    read -rp "$(echo -e "${CYN}Chemin du LV à étendre${RST} (ex: /dev/vg0/root) : ")" LV_PATH
    lvdisplay "$LV_PATH" &>/dev/null || die "LV '$LV_PATH' introuvable."

    local fs_type
    fs_type=$(blkid -o value -s TYPE "$LV_PATH" 2>/dev/null || echo "inconnu")
    info "Filesystem détecté : ${BLD}${fs_type}${RST}"

    local vg_name
    vg_name=$(lvs --noheadings -o vg_name "$LV_PATH" | tr -d ' ')
    local vg_free
    vg_free=$(vgs --noheadings --units g -o vg_free "$vg_name" | tr -d ' g')
    info "Espace libre dans VG ($vg_name) : ${BLD}${vg_free}G${RST}"

    echo -e "\n  Format : ${YEL}+10G${RST} (ajouter) ou ${YEL}50G${RST} (taille finale) ou ${YEL}+100%FREE${RST}"
    read -rp "$(echo -e "${CYN}Nouvelle taille / ajout${RST} : ")" NEW_SIZE

    sep
    confirm "Étendre $LV_PATH de $NEW_SIZE ?" || {
        warn "Annulé."
        return
    }

    if [[ "$NEW_SIZE" == +* ]]; then
        lvextend -L "$NEW_SIZE" "$LV_PATH" ||
            lvextend -l "$NEW_SIZE" "$LV_PATH" || die "Échec lvextend"
    else
        lvextend -L "$NEW_SIZE" "$LV_PATH" || die "Échec lvextend"
    fi

    info "Extension du système de fichiers..."
    case "$fs_type" in
    ext2 | ext3 | ext4)
        resize2fs "$LV_PATH"
        ok "resize2fs terminé."
        ;;
    xfs)
        local mount_pt
        mount_pt=$(findmnt -n -o TARGET --source "$LV_PATH" 2>/dev/null || true)
        if [[ -z "$mount_pt" ]]; then
            warn "XFS doit être monté pour xfs_growfs. Montez le LV puis relancez."
        else
            xfs_growfs "$mount_pt"
            ok "xfs_growfs terminé."
        fi
        ;;
    *)
        warn "FS '$fs_type' non géré automatiquement. Redimensionnez manuellement."
        ;;
    esac

    echo
    lvs "$LV_PATH"
    ok "Extension terminée."
    pause
}

# ═══════════════════════════════════════════════════════════════════════════
#  MODULE 4 — RÉDUIRE UN LV (ext4 uniquement, démontage requis)
# ═══════════════════════════════════════════════════════════════════════════
shrink_lv() {
    title "RÉDUIRE UN LOGICAL VOLUME"

    warn "⚠  Opération DESTRUCTIVE si mal utilisée."
    warn "   Uniquement ext4. XFS ne supporte PAS le shrink."
    warn "   Le LV doit être DÉMONTÉ (sauf /boot avec LiveUSB)."
    echo

    echo -e "${BLD}▶ Logical Volumes disponibles :${RST}"
    lvs --noheadings -o lv_path,lv_size 2>/dev/null
    echo

    read -rp "$(echo -e "${CYN}Chemin du LV à réduire${RST} : ")" LV_PATH
    lvdisplay "$LV_PATH" &>/dev/null || die "LV introuvable."

    local fs_type
    fs_type=$(blkid -o value -s TYPE "$LV_PATH" 2>/dev/null || echo "inconnu")
    [[ "$fs_type" == xfs ]] && die "XFS ne supporte pas le shrink. Opération impossible."
    [[ "$fs_type" != ext* ]] && warn "FS '$fs_type' non ext — procédez avec précaution."

    read -rp "$(echo -e "${CYN}Nouvelle taille cible${RST} (ex: 20G) : ")" TARGET_SIZE

    sep
    warn "ATTENTION : toutes les données au-delà de $TARGET_SIZE seront PERDUES."
    confirm "Vous avez un snapshot ou une sauvegarde ?" || {
        warn "Opération annulée — faites d'abord un snapshot !"
        return
    }
    confirm "Confirmer la réduction à $TARGET_SIZE ?" || {
        warn "Annulé."
        return
    }

    # Démontage
    local mount_pt
    mount_pt=$(findmnt -n -o TARGET --source "$LV_PATH" 2>/dev/null || true)
    if [[ -n "$mount_pt" ]]; then
        warn "LV monté sur $mount_pt — démontage..."
        umount "$LV_PATH" || die "Impossible de démonter $LV_PATH (processus actif ?)"
    fi

    info "Vérification et réduction du FS..."
    e2fsck -f "$LV_PATH"
    local e2fsck_rc=$?
    if [[ $e2fsck_rc -ge 4 ]]; then
        die "e2fsck a détecté des erreurs non corrigées (code $e2fsck_rc) — abandon."
    fi
    [[ $e2fsck_rc -gt 0 ]] && warn "e2fsck a corrigé des erreurs mineures (code $e2fsck_rc)."
    resize2fs "$LV_PATH" "$TARGET_SIZE"

    info "Réduction du LV..."
    lvreduce -L "$TARGET_SIZE" "$LV_PATH"

    info "Vérification finale..."
    e2fsck -f "$LV_PATH"
    e2fsck_rc=$?
    [[ $e2fsck_rc -ge 4 ]] && warn "e2fsck post-réduction : code $e2fsck_rc — vérifiez le volume."

    if [[ -n "$mount_pt" ]]; then
        mount "$LV_PATH" "$mount_pt"
        ok "LV remonté sur $mount_pt"
    fi

    lvs "$LV_PATH"
    ok "Réduction terminée."
    pause
}

# ═══════════════════════════════════════════════════════════════════════════
#  MODULE 5 — PVMOVE : DÉPLACER DES DONNÉES À CHAUD
# ═══════════════════════════════════════════════════════════════════════════
pvmove_data() {
    title "PVMOVE — DÉPLACER DES DONNÉES À CHAUD"

    info "pvmove déplace les extents LVM d'un PV vers un autre SANS démonter."
    info "Fonctionne même sur / (root), /home, /var en production."
    echo

    echo -e "${BLD}▶ Physical Volumes disponibles :${RST}"
    pvs -o pv_name,pv_size,pv_free,pv_used,vg_name 2>/dev/null
    echo

    read -rp "$(echo -e "${CYN}PV SOURCE à vider${RST} (ex: /dev/sdb) : ")" SRC_PV
    pvdisplay "$SRC_PV" &>/dev/null || die "PV '$SRC_PV' introuvable."

    local vg_name
    vg_name=$(pvs --noheadings -o vg_name "$SRC_PV" | tr -d ' ')
    [[ -z "$vg_name" ]] && die "Ce PV n'appartient à aucun VG."
    info "VG détecté : $vg_name"

    echo
    echo -e "  ${DIM}Laisser vide = répartition automatique sur tous les autres PV du VG${RST}"
    read -rp "$(echo -e "${CYN}PV DESTINATION${RST} (optionnel, ex: /dev/sdc) : ")" DST_PV

    sep
    if [[ -n "$DST_PV" ]]; then
        info "Déplacement : $SRC_PV → $DST_PV"
    else
        info "Déplacement : $SRC_PV → (automatique dans $vg_name)"
    fi

    # Estimation taille à déplacer
    local used_pe
    used_pe=$(pvs --noheadings -o pv_used "$SRC_PV" | tr -d ' ')
    warn "Données à déplacer : $used_pe — opération potentiellement longue."
    confirm "Démarrer pvmove ?" || {
        warn "Annulé."
        return
    }

    # Lancement en arrière-plan avec suivi
    if [[ -n "$DST_PV" ]]; then
        pvmove --verbose "$SRC_PV" "$DST_PV" &
    else
        pvmove --verbose "$SRC_PV" &
    fi
    local PVMOVE_PID=$!

    echo
    info "pvmove en cours (PID: $PVMOVE_PID) — progression :"
    sep
    while kill -0 "$PVMOVE_PID" 2>/dev/null; do
        local pct
        pct=$(lvs --noheadings -o copy_percent 2>/dev/null | grep -v '^$' | tail -1 | tr -d ' ')
        printf "\r  ${GRN}▶${RST} Progression : ${BLD}%s%%${RST}     " "${pct:-calcul...}"
        sleep 2
    done
    echo

    wait "$PVMOVE_PID" 2>/dev/null || true
    ok "pvmove terminé !"

    echo
    info "Le PV $SRC_PV est maintenant vide."
    if confirm "Retirer $SRC_PV du VG '$vg_name' et le supprimer ?"; then
        vgreduce "$vg_name" "$SRC_PV"
        pvremove "$SRC_PV"
        ok "$SRC_PV retiré du VG et nettoyé."
    else
        info "Pour le faire plus tard :"
        echo -e "  ${YEL}vgreduce $vg_name $SRC_PV${RST}"
        echo -e "  ${YEL}pvremove $SRC_PV${RST}"
    fi
    pause
}

# ═══════════════════════════════════════════════════════════════════════════
#  MODULE 6 — SNAPSHOT LVM
# ═══════════════════════════════════════════════════════════════════════════
snapshot_lv() {
    title "SNAPSHOT LVM"

    echo "  ${BLD}1)${RST} Créer un snapshot"
    echo "  ${BLD}2)${RST} Lister les snapshots existants"
    echo "  ${BLD}3)${RST} Restaurer (merger) un snapshot"
    echo "  ${BLD}4)${RST} Supprimer un snapshot"
    echo
    read -rp "$(echo -e "${CYN}Choix${RST} [1-4] : ")" snap_action

    case "$snap_action" in
    1)
        echo -e "\n${BLD}▶ LV disponibles :${RST}"
        lvs --noheadings -o lv_path,lv_size,vg_name | grep -v snap
        echo
        read -rp "$(echo -e "${CYN}LV source du snapshot${RST} (ex: /dev/vg0/root) : ")" LV_SRC
        lvdisplay "$LV_SRC" &>/dev/null || die "LV introuvable."

        local snap_name
        snap_name="snap_$(basename "$LV_SRC")_$(date +%Y%m%d_%H%M)"
        info "Nom du snapshot : $snap_name"

        local lv_size suggested
        lv_size=$(lvs --noheadings --units g -o lv_size "$LV_SRC" | tr -d ' g' | cut -d. -f1)
        suggested=$((lv_size / 5))
        [[ $suggested -lt 1 ]] && suggested=1
        info "Taille suggérée (20% du LV = ${suggested}G)"

        read -rp "$(echo -e "${CYN}Taille du snapshot${RST} (ex: ${suggested}G) : ")" SNAP_SIZE
        [[ -z "$SNAP_SIZE" ]] && SNAP_SIZE="${suggested}G"

        local vg_name
        vg_name=$(lvs --noheadings -o vg_name "$LV_SRC" | tr -d ' ')
        lvcreate -L "$SNAP_SIZE" -s -n "$snap_name" "$LV_SRC"
        ok "Snapshot créé : /dev/$vg_name/$snap_name"
        info "Pour restaurer ultérieurement :"
        echo -e "  ${YEL}lvconvert --merge /dev/$vg_name/$snap_name${RST}"
        ;;
    2)
        echo
        echo -e "${BLD}▶ Snapshots LVM :${RST}"
        lvs --noheadings -o lv_path,lv_size,data_percent,origin -S "lv_attr =~ ^s" 2>/dev/null ||
            warn "Aucun snapshot trouvé."
        ;;
    3)
        echo -e "\n${BLD}▶ Snapshots disponibles :${RST}"
        lvs --noheadings -o lv_path,origin -S "lv_attr =~ ^s" 2>/dev/null
        echo
        read -rp "$(echo -e "${CYN}Chemin du snapshot à restaurer${RST} : ")" SNAP_PATH
        warn "La restauration écrasera les données actuelles du LV source."
        confirm "Confirmer la restauration ?" || {
            warn "Annulé."
            return
        }
        lvconvert --merge "$SNAP_PATH"
        ok "Merge demandé. Si le LV est / (root), redémarrez pour finaliser."
        ;;
    4)
        echo -e "\n${BLD}▶ Snapshots disponibles :${RST}"
        lvs --noheadings -o lv_path -S "lv_attr =~ ^s" 2>/dev/null
        echo
        read -rp "$(echo -e "${CYN}Chemin du snapshot à supprimer${RST} : ")" SNAP_DEL
        confirm "Supprimer définitivement $SNAP_DEL ?" || {
            warn "Annulé."
            return
        }
        lvremove -f "$SNAP_DEL"
        ok "Snapshot supprimé."
        ;;
    *)
        warn "Choix invalide."
        ;;
    esac
    pause
}

# ═══════════════════════════════════════════════════════════════════════════
#  MODULE 7 — AJOUTER UN DISQUE / ÉTENDRE LE VG
# ═══════════════════════════════════════════════════════════════════════════
add_disk_to_vg() {
    title "AJOUTER UN DISQUE / ÉTENDRE LE VG"

    echo -e "${BLD}▶ Disques disponibles (non LVM) :${RST}"
    lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT | grep -E "disk|part" | head -30
    echo

    echo -e "${BLD}▶ Volume Groups existants :${RST}"
    vgs --noheadings -o vg_name,vg_size,vg_free 2>/dev/null || warn "Aucun VG trouvé."
    echo

    read -rp "$(echo -e "${CYN}Disque ou partition à ajouter${RST} (ex: /dev/sdc ou /dev/sdc1) : ")" NEW_DISK

    [[ -b "$NEW_DISK" ]] || die "$NEW_DISK n'est pas un périphérique bloc valide."

    # Vérifier si déjà utilisé
    local existing_use
    existing_use=$(blkid -o value -s TYPE "$NEW_DISK" 2>/dev/null || true)
    if [[ -n "$existing_use" ]]; then
        warn "$NEW_DISK contient déjà un filesystem : $existing_use"
        confirm "Continuer quand même (DONNÉES EFFACÉES) ?" || {
            warn "Annulé."
            return
        }
    fi

    read -rp "$(echo -e "${CYN}VG cible${RST} (laisser vide pour créer un nouveau VG) : ")" VG_TARGET

    sep
    info "Initialisation de $NEW_DISK en PV..."
    confirm "Confirmer pvcreate sur $NEW_DISK ?" || {
        warn "Annulé."
        return
    }
    pvcreate "$NEW_DISK"
    ok "PV créé : $NEW_DISK"

    if [[ -z "$VG_TARGET" ]]; then
        read -rp "$(echo -e "${CYN}Nom du nouveau VG${RST} : ")" NEW_VG
        [[ -z "$NEW_VG" ]] && die "Nom de VG vide."
        vgcreate "$NEW_VG" "$NEW_DISK"
        ok "VG '$NEW_VG' créé avec $NEW_DISK"
    else
        vgs "$VG_TARGET" &>/dev/null || die "VG '$VG_TARGET' introuvable."
        vgextend "$VG_TARGET" "$NEW_DISK"
        ok "$NEW_DISK ajouté au VG '$VG_TARGET'"
        vgs "$VG_TARGET"
    fi
    pause
}

# ═══════════════════════════════════════════════════════════════════════════
#  MODULE 8 — MIGRATION OS VERS NOUVEAU DISQUE
# ═══════════════════════════════════════════════════════════════════════════
migrate_os() {
    title "MIGRATION OS VERS NOUVEAU DISQUE (à chaud)"

    info "Ce module déplace l'intégralité d'un VG vers un nouveau disque."
    info "Aucun démontage requis — fonctionne en production."
    warn "Prévoyez ~1h pour un disque de 100Go selon les I/O."
    echo

    echo -e "${BLD}▶ Situation actuelle :${RST}"
    pvs -o pv_name,pv_size,pv_used,pv_free,vg_name
    echo

    read -rp "$(echo -e "${CYN}VG à migrer${RST} (ex: ubuntu-vg) : ")" VG_NAME
    vgs "$VG_NAME" &>/dev/null || die "VG '$VG_NAME' introuvable."

    echo -e "\n${BLD}▶ Disques et partitions disponibles :${RST}"
    lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT | grep -E "disk|part"
    echo
    echo -e "  ${DIM}Vous pouvez cibler un disque entier${RST} ${YEL}(ex: /dev/sdb)${RST}"
    echo -e "  ${DIM}ou une partition spécifique        ${RST} ${YEL}(ex: /dev/sda3)${RST}"
    echo -e "  ${YEL}⚠  Cibler une partition préserve EFI/boot sur les autres partitions${RST}"
    echo

    read -rp "$(echo -e "${CYN}Destination (disque ou partition)${RST} : ")" NEW_DISK
    [[ -b "$NEW_DISK" ]] || die "Périphérique '$NEW_DISK' invalide ou introuvable."

    # Déterminer si c'est un disque entier ou une partition
    local dev_type
    dev_type=$(lsblk -dn -o TYPE "$NEW_DISK" 2>/dev/null || echo "unknown")

    local existing_use
    existing_use=$(blkid -o value -s TYPE "$NEW_DISK" 2>/dev/null || true)

    if [[ "$dev_type" == "disk" ]]; then
        # Vérifier si le disque a des partitions EFI/boot à risque
        local has_efi has_boot
        has_efi=$(lsblk -ln -o NAME,PARTTYPE "$NEW_DISK" 2>/dev/null | grep -i "c12a7328\|efi" | wc -l)
        has_boot=$(lsblk -ln -o NAME,FSTYPE,MOUNTPOINT "$NEW_DISK" 2>/dev/null | grep -E "/boot|vfat" | wc -l)

        if [[ "$has_efi" -gt 0 || "$has_boot" -gt 0 ]]; then
            echo
            warn "⚠  ATTENTION : $NEW_DISK contient des partitions EFI ou /boot !"
            lsblk -o NAME,SIZE,FSTYPE,MOUNTPOINT "$NEW_DISK"
            echo
            warn "Écraser le disque entier DÉTRUIRA le bootloader."
            echo -e "  ${BLD}Conseil :${RST} ciblez uniquement la partition LVM (ex: ${YEL}/dev/sda3${RST})"
            echo
            confirm "Continuer quand même sur le disque ENTIER (dangereux) ?" || {
                warn "Annulé — relancez et choisissez une partition spécifique."
                return
            }
        else
            [[ -n "$existing_use" ]] && warn "$NEW_DISK contient : $existing_use — sera écrasé."
        fi

        sep
        warn "RÉSUMÉ : Migration de $VG_NAME vers $NEW_DISK (disque entier)"
        warn "Le disque $NEW_DISK sera ENTIÈREMENT écrasé."

    else
        # Cible = partition : vérifier qu'elle n'est pas montée
        local part_mount
        part_mount=$(findmnt -n -o TARGET --source "$NEW_DISK" 2>/dev/null || true)
        if [[ -n "$part_mount" ]]; then
            die "$NEW_DISK est actuellement monté sur $part_mount — démontez-la d'abord."
        fi

        local parent_disk
        parent_disk=$(lsblk -dn -o PKNAME "$NEW_DISK" 2>/dev/null | tr -d ' ')
        [[ -n "$parent_disk" ]] && parent_disk="/dev/$parent_disk" || parent_disk="(inconnu)"

        echo
        [[ -n "$existing_use" ]] && warn "$NEW_DISK contient : $existing_use — sera écrasé." ||
            info "$NEW_DISK est vide / non formatée."
        info "Disque parent : $parent_disk — les autres partitions ne seront PAS touchées."

        sep
        warn "RÉSUMÉ : Migration de $VG_NAME vers la partition $NEW_DISK uniquement"
        info "EFI, /boot et les autres partitions de $parent_disk sont préservées."
    fi

    confirm "Démarrer la migration ?" || {
        warn "Annulé."
        return
    }

    # Étape 1 : pvcreate sur le nouveau disque
    info "[1/5] Initialisation du nouveau PV..."
    pvcreate "$NEW_DISK"
    ok "$NEW_DISK initialisé en PV."

    # Étape 2 : Ajouter au VG
    info "[2/5] Ajout au VG '$VG_NAME'..."
    vgextend "$VG_NAME" "$NEW_DISK"
    ok "$NEW_DISK ajouté à $VG_NAME."

    # Étape 3 : Récupérer les anciens PV du VG (en excluant NEW_DISK)
    local old_pvs
    mapfile -t old_pvs < <(pvs --noheadings -o pv_name,vg_name | awk -v vg="$VG_NAME" -v nd="$NEW_DISK" '$2==vg && $1!=nd {print $1}')
    [[ ${#old_pvs[@]} -eq 0 ]] && die "Aucun PV source distinct de $NEW_DISK trouvé dans $VG_NAME."

    info "[3/5] PV source(s) détectés : ${old_pvs[*]}"

    # Étape 4 : pvmove pour chaque ancien PV
    local i=1
    for OLD_PV in "${old_pvs[@]}"; do
        info "[4/5] pvmove $OLD_PV → $NEW_DISK ($i/${#old_pvs[@]})..."
        pvmove --verbose "$OLD_PV" "$NEW_DISK" &
        local PID=$!
        while kill -0 "$PID" 2>/dev/null; do
            local pct
            pct=$(lvs --noheadings -o copy_percent 2>/dev/null | grep -v '^$' | tail -1 | tr -d ' ')
            printf "\r  ${GRN}▶${RST} %s : %s%%     " "$OLD_PV" "${pct:-...}"
            sleep 2
        done
        echo
        wait "$PID" 2>/dev/null || true
        ok "pvmove terminé pour $OLD_PV"
        ((i++))
    done

    # Étape 5 : Retirer les anciens PV
    info "[5/5] Retrait des anciens PV..."
    for OLD_PV in "${old_pvs[@]}"; do
        vgreduce "$VG_NAME" "$OLD_PV"
        pvremove "$OLD_PV"
        ok "$OLD_PV retiré."
    done

    echo
    ok "═══ MIGRATION TERMINÉE ═══"
    pvs
    vgs "$VG_NAME"

    warn "IMPORTANT — Dernières étapes manuelles requises :"
    echo
    echo -e "  ${BLD}Si /boot est sur l'ancien disque :${RST}"
    echo -e "    • Copiez /boot ou réinstallez GRUB sur $NEW_DISK"
    echo
    echo -e "  ${BLD}Debian/Ubuntu :${RST}"
    echo -e "    ${YEL}grub-install $NEW_DISK${RST}"
    echo -e "    ${YEL}update-grub${RST}"
    echo -e "    ${YEL}update-initramfs -u -k all${RST}"
    echo
    echo -e "  ${BLD}RHEL/Rocky/AlmaLinux :${RST}"
    echo -e "    ${YEL}grub2-install $NEW_DISK${RST}"
    echo -e "    ${YEL}grub2-mkconfig -o /boot/grub2/grub.cfg${RST}"
    echo -e "    ${YEL}dracut -f --regenerate-all${RST}"
    echo
    echo -e "  ${BLD}Vérifiez /etc/fstab${RST} si vous utilisez des noms de device (préférez UUID)"
    pause
}

# ═══════════════════════════════════════════════════════════════════════════
#  MODULE 9 — SUPPRIMER UN LV
# ═══════════════════════════════════════════════════════════════════════════
remove_lv() {
    title "SUPPRIMER UN LOGICAL VOLUME"

    warn "Opération IRRÉVERSIBLE. Les données seront perdues."
    echo
    echo -e "${BLD}▶ Logical Volumes disponibles :${RST}"
    lvs --noheadings -o lv_path,lv_size,lv_attr 2>/dev/null
    echo

    read -rp "$(echo -e "${CYN}Chemin du LV à supprimer${RST} : ")" LV_PATH
    lvdisplay "$LV_PATH" &>/dev/null || die "LV introuvable."

    confirm "Supprimer DÉFINITIVEMENT $LV_PATH ?" || {
        warn "Annulé."
        return
    }
    confirm "Dernière confirmation — toutes les données seront EFFACÉES ?" || {
        warn "Annulé."
        return
    }

    local lv_attr
    lv_attr=$(lvs --noheadings -o lv_attr "$LV_PATH" | tr -d ' ')
    if [[ "${lv_attr:0:1}" == 'o' ]]; then
        die "LV '$LV_PATH' est ouvert/actif (root ou swap en cours d'utilisation). Abandon."
    fi

    local mount_pt
    mount_pt=$(findmnt -n -o TARGET --source "$LV_PATH" 2>/dev/null || true)
    if [[ -n "$mount_pt" ]]; then
        umount "$LV_PATH" || die "Impossible de démonter (processus actif ?)"
    fi

    lvremove -f "$LV_PATH"
    ok "LV $LV_PATH supprimé."
    pause
}

# ═══════════════════════════════════════════════════════════════════════════
#  MODULE 10 — EXPORTER LE DIAGNOSTIC
# ═══════════════════════════════════════════════════════════════════════════

export_result() {
    title "EXPORTER LE DIAGNOSTIC LVM"

    local timestamp
    timestamp=$(date +%Y%m%d_%H%M%S)
    local default_path="/tmp/lvm-diag_${timestamp}.txt"

    read -rp "$(echo -e "${CYN}Fichier de destination${RST} [${default_path}] : ")" EXPORT_PATH
    [[ -z "$EXPORT_PATH" ]] && EXPORT_PATH="$default_path"

    local export_dir
    export_dir=$(dirname "$EXPORT_PATH")
    [[ -d "$export_dir" ]] || die "Répertoire '$export_dir' introuvable."

    {
        echo "=== LVM DIAGNOSTIC EXPORT ==="
        echo "Date    : $(date '+%Y-%m-%d %H:%M:%S')"
        echo "Hôte    : $(hostname -f 2>/dev/null || hostname)"
        echo "Kernel  : $(uname -r)"
        echo "Utilisateur : $(whoami)"
        echo ""

        echo "--- lsblk ---"
        lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT,UUID 2>/dev/null || true
        echo ""

        echo "--- Physical Volumes ---"
        pvs -o pv_name,pv_size,pv_free,pv_used,pv_uuid,vg_name 2>/dev/null || true
        echo ""

        echo "--- Physical Volumes (détaillé) ---"
        pvdisplay 2>/dev/null || true
        echo ""

        echo "--- Volume Groups ---"
        vgs -o vg_name,vg_size,vg_free,vg_extent_size,pv_count,lv_count 2>/dev/null || true
        echo ""

        echo "--- Volume Groups (détaillé) ---"
        vgdisplay 2>/dev/null || true
        echo ""

        echo "--- Logical Volumes ---"
        lvs -o lv_path,lv_size,lv_attr,seg_type,origin,data_percent,metadata_percent,copy_percent 2>/dev/null || true
        echo ""

        echo "--- Logical Volumes (détaillé) ---"
        lvdisplay 2>/dev/null || true
        echo ""

        echo "--- blkid ---"
        blkid 2>/dev/null || true
        echo ""

        echo "--- Systèmes de fichiers montés ---"
        df -hT | grep -E "^/dev/mapper|^/dev/[sv]d|Filesystem" || true
        echo ""

        echo "--- Résumé rapide ---"
        local pv_count vg_count lv_count
        pv_count=$(pvs --noheadings 2>/dev/null | wc -l)
        vg_count=$(vgs --noheadings 2>/dev/null | wc -l)
        lv_count=$(lvs --noheadings 2>/dev/null | wc -l)
        echo "  PV : ${pv_count}   VG : ${vg_count}   LV : ${lv_count}"

        echo "--- ZRAM (swap compressé) ---"
        if lsmod | grep -q zram; then
            echo "Zram actif"
            echo "Algorithmes : $(cat /sys/block/zram0/comp_algorithm 2>/dev/null)"
            for dev in /sys/block/zram*/disksize; do
                if [[ -f "$dev" ]]; then
                    size=$(cat "$dev" 2>/dev/null)
                    name=$(echo "$dev" | cut -d/ -f4)
                    echo "$name : $(numfmt --to=iec $size 2>/dev/null || echo $size)"
                fi
            done
            echo "Swaps :"
            swapon --show | grep -E "zram|NAME"
        else
            echo "Aucun zram actif"
        fi
        echo ""

    } >"$EXPORT_PATH"

    ok "Diagnostic exporté : $EXPORT_PATH"

    echo
    echo -e "  ${BLD}Partage rapide :${RST}"
    echo -e "  ${DIM}scp${RST}      : ${YEL}scp $EXPORT_PATH user@host:/tmp/${RST}"

    if ! command -v curl &>/dev/null; then
        warn "curl absent — installez-le pour activer le partage en ligne."
        pause
        return
    fi

    echo -e "  ${BLD}Service de partage :${RST}"
    echo -e "  ${CYN}1)${RST} dpaste.com       (paste texte, 7 jours)"
    echo -e "  ${CYN}2)${RST} paste.ubuntu.com (paste texte, canonique)"
    echo -e "  ${CYN}3)${RST} GoFile.io        (fichier, téléchargement direct)"
    echo -e "  ${CYN}4)${RST} Aucun"
    echo
    read -rp "$(echo -e "${CYN}Choix${RST} [1-4] : ")" share_choice

    local url
    case "$share_choice" in
    1)
        url=$(curl -s --max-time 20 \
            -X POST https://dpaste.com/api/v2/ \
            --data-urlencode "content@${EXPORT_PATH}" \
            -d "syntax=text" -d "expiry_days=7" | tr -d '"' || true)
        [[ "$url" == https* ]] && ok "dpaste.com : $url" || warn "Envoi dpaste échoué."
        ;;
    2)
        url=$(curl -s --max-time 20 \
            -F "poster=lvm-manager" -F "syntax=text" \
            -F "expiration=week" -F "content=<${EXPORT_PATH}" \
            https://paste.ubuntu.com/ \
            -w "%{url_effective}" -o /dev/null || true)
        [[ "$url" == https://paste.ubuntu.com/* ]] && ok "paste.ubuntu.com : $url" || warn "Envoi paste.ubuntu échoué."
        ;;
    3)
        local server token file_url
        server=$(curl -s --max-time 10 https://api.gofile.io/servers |
            grep -o '"name":"[^"]*"' | head -1 | cut -d'"' -f4 || true)
        [[ -z "$server" ]] && warn "GoFile : impossible de joindre l'API." && break
        token=$(curl -s --max-time 10 https://api.gofile.io/accounts |
            grep -o '"token":"[^"]*"' | cut -d'"' -f4 || true)
        file_url=$(curl -s --max-time 30 \
            -F "file=@${EXPORT_PATH}" \
            -F "token=${token}" \
            "https://${server}.gofile.io/uploadFile" |
            grep -o '"downloadPage":"[^"]*"' | cut -d'"' -f4 || true)
        [[ -n "$file_url" ]] && ok "GoFile.io : $file_url" || warn "Envoi GoFile échoué."
        ;;
    4)
        info "Partage annulé."
        ;;
    *)
        warn "Choix invalide."
        ;;
    esac

    pause
}

# ═══════════════════════════════════════════════════════════════════════════
#  MODULE 11 — GESTION DU SWAP (LVM)
# ═══════════════════════════════════════════════════════════════════════════
manage_swap() {
    title "GESTION DU SWAP SUR LVM"

    echo -e "  ${BLD}1)${RST} Afficher les swaps actifs"
    echo -e "  ${BLD}2)${RST} Créer un LV swap"
    echo -e "  ${BLD}3)${RST} Étendre un LV swap (à chaud)"
    echo -e "  ${BLD}4)${RST} Réduire un LV swap (désactivé requis)"
    echo -e "  ${BLD}5)${RST} Déplacer un LV swap vers un autre VG (à chaud)"
    echo -e "  ${BLD}6)${RST} Supprimer un LV swap"
    echo
    read -rp "$(echo -e "${CYN}Choix${RST} [1-6] : ")" swap_action

    case "$swap_action" in
    1)
        echo -e "\n${BLD}▶ Swaps actifs :${RST}"
        sep
        swapon --show 2>/dev/null || echo "Aucun swap actif"
        echo
        echo -e "${BLD}▶ LV avec type swap :${RST}"
        lvs -o lv_path,lv_size,lv_attr -S "lv_layout=swap" 2>/dev/null || echo "Aucun LV swap trouvé"
        ;;

    2)
        echo -e "\n${BLD}▶ Volume Groups disponibles :${RST}"
        vgs --noheadings -o vg_name,vg_size,vg_free 2>/dev/null
        echo
        read -rp "$(echo -e "${CYN}VG cible${RST} : ")" VG_SWAP
        vgs "$VG_SWAP" &>/dev/null || die "VG '$VG_SWAP' introuvable"

        read -rp "$(echo -e "${CYN}Nom du LV swap${RST} (ex: swap_vol) : ")" LV_SWAP_NAME
        [[ -z "$LV_SWAP_NAME" ]] && die "Nom vide"

        read -rp "$(echo -e "${CYN}Taille${RST} (ex: 2G, 4G) : ")" SWAP_SIZE
        [[ -z "$SWAP_SIZE" ]] && die "Taille vide"

        confirm "Créer /dev/$VG_SWAP/$LV_SWAP_NAME de taille $SWAP_SIZE ?" || return

        lvcreate -L "$SWAP_SIZE" -n "$LV_SWAP_NAME" "$VG_SWAP"
        mkswap "/dev/$VG_SWAP/$LV_SWAP_NAME"
        ok "LV swap créé : /dev/$VG_SWAP/$LV_SWAP_NAME"

        if confirm "Activer le swap maintenant ?"; then
            swapon "/dev/$VG_SWAP/$LV_SWAP_NAME"
            ok "Swap activé"
        fi

        if confirm "Ajouter à /etc/fstab (montage permanent) ?"; then
            local uuid
            uuid=$(blkid -s UUID -o value "/dev/$VG_SWAP/$LV_SWAP_NAME")
            echo "UUID=$uuid  none  swap  sw  0  0" >>/etc/fstab
            ok "Entrée ajoutée dans /etc/fstab (UUID: $uuid)"
        fi
        ;;

    3)
        echo -e "\n${BLD}▶ LV swap disponibles :${RST}"
        lvs -o lv_path,lv_size -S "lv_layout=swap" 2>/dev/null || die "Aucun LV swap trouvé"
        echo
        read -rp "$(echo -e "${CYN}LV swap à étendre${RST} : ")" SWAP_LV
        lvdisplay "$SWAP_LV" &>/dev/null || die "LV '$SWAP_LV' introuvable"

        local vg_name
        vg_name=$(lvs --noheadings -o vg_name "$SWAP_LV" | tr -d ' ')
        local vg_free
        vg_free=$(vgs --noheadings --units g -o vg_free "$vg_name" | tr -d ' g')
        info "Espace libre dans $vg_name : ${vg_free}G"

        read -rp "$(echo -e "${CYN}Nouvelle taille${RST} (ex: 4G, +2G) : ")" NEW_SIZE

        # Désactiver temporairement si actif
        local was_active=false
        if swapon --show | grep -q "$SWAP_LV"; then
            warn "Swap actif détecté — désactivation temporaire..."
            swapoff "$SWAP_LV"
            was_active=true
            ok "Swap désactivé"
        fi

        info "Extension du LV swap..."
        if [[ "$NEW_SIZE" == +* ]]; then
            lvextend -L "$NEW_SIZE" "$SWAP_LV"
        else
            lvextend -L "$NEW_SIZE" "$SWAP_LV"
        fi

        # Réinitialiser le swap (nécessaire après extension)
        mkswap "$SWAP_LV"
        ok "Swap étendu et reformaté"

        if [[ "$was_active" == true ]]; then
            swapon "$SWAP_LV"
            ok "Swap réactivé"
        fi

        lvs "$SWAP_LV"
        ;;

    4)
        echo -e "\n${BLD}▶ LV swap disponibles :${RST}"
        lvs -o lv_path,lv_size -S "lv_layout=swap" 2>/dev/null || die "Aucun LV swap trouvé"
        echo
        read -rp "$(echo -e "${CYN}LV swap à réduire${RST} : ")" SWAP_LV

        # Vérifier et désactiver
        if swapon --show | grep -q "$SWAP_LV"; then
            swapoff "$SWAP_LV"
            ok "Swap désactivé"
        else
            info "Swap déjà inactif"
        fi

        read -rp "$(echo -e "${CYN}Nouvelle taille${RST} (ex: 2G) : ")" NEW_SIZE

        # Vérifier la taille (ne pas réduire en dessous de ce qui est utilisé)
        warn "Réduction destructive — le swap sera reformaté après réduction"
        confirm "Continuer ?" || return

        lvreduce -L "$NEW_SIZE" "$SWAP_LV"
        mkswap "$SWAP_LV"
        ok "Swap réduit et reformaté"

        if confirm "Réactiver le swap ?"; then
            swapon "$SWAP_LV"
            ok "Swap réactivé"
        fi
        ;;

    5)
        echo -e "\n${BLD}▶ Déplacer un LV swap vers un autre VG (à chaud)${RST}"
        echo
        echo -e "${BLD}▶ LV swap disponibles :${RST}"
        lvs -o lv_path,lv_size,vg_name -S "lv_layout=swap" 2>/dev/null || die "Aucun LV swap trouvé"
        echo
        read -rp "$(echo -e "${CYN}LV swap à déplacer${RST} : ")" SWAP_LV
        lvdisplay "$SWAP_LV" &>/dev/null || die "LV introuvable"

        echo -e "\n${BLD}▶ VG disponibles :${RST}"
        vgs -o vg_name,vg_size,vg_free 2>/dev/null
        echo
        read -rp "$(echo -e "${CYN}VG de destination${RST} : ")" DST_VG
        vgs "$DST_VG" &>/dev/null || die "VG '$DST_VG' introuvable"

        local current_vg
        current_vg=$(lvs --noheadings -o vg_name "$SWAP_LV" | tr -d ' ')
        local lv_name
        lv_name=$(basename "$SWAP_LV")
        local lv_size
        lv_size=$(lvs --noheadings --units g -o lv_size "$SWAP_LV" | tr -d ' ' | sed 's/g//i')

        confirm "Déplacer $SWAP_LV ($lv_size G) vers $DST_VG ?" || return

        # Désactiver swap
        local was_active=false
        if swapon --show | grep -q "$SWAP_LV"; then
            swapoff "$SWAP_LV"
            was_active=true
            ok "Swap désactivé"
        fi

        # Méthode : créer nouveau LV, copier les données (mkswap = nouveau format)
        local new_lv_path="/dev/$DST_VG/$lv_name"
        info "Création du nouveau LV swap : $new_lv_path"
        lvcreate -L "${lv_size}G" -n "$lv_name" "$DST_VG"
        mkswap "$new_lv_path"

        # Mettre à jour fstab
        local old_uuid new_uuid
        old_uuid=$(blkid -s UUID -o value "$SWAP_LV")
        new_uuid=$(blkid -s UUID -o value "$new_lv_path")

        if [[ -f /etc/fstab ]] && grep -q "$old_uuid" /etc/fstab; then
            sed -i "s/$old_uuid/$new_uuid/g" /etc/fstab
            ok "/etc/fstab mis à jour"
        elif [[ -f /etc/fstab ]] && grep -q "$SWAP_LV" /etc/fstab; then
            sed -i "s|$SWAP_LV|$new_lv_path|g" /etc/fstab
            ok "/etc/fstab mis à jour"
        fi

        # Activer nouveau swap
        if [[ "$was_active" == true ]]; then
            swapon "$new_lv_path"
            ok "Nouveau swap activé"
        fi

        # Supprimer l'ancien
        lvremove -f "$SWAP_LV"
        ok "Ancien swap supprimé"

        echo -e "\n${GRN}Swap déplacé : $new_lv_path${RST}"
        lvs "$new_lv_path"
        ;;

    6)
        echo -e "\n${BLD}▶ LV swap disponibles :${RST}"
        lvs -o lv_path,lv_size -S "lv_layout=swap" 2>/dev/null || die "Aucun LV swap trouvé"
        echo
        read -rp "$(echo -e "${CYN}LV swap à supprimer${RST} : ")" SWAP_LV

        # Désactiver si actif
        if swapon --show | grep -q "$SWAP_LV"; then
            swapoff "$SWAP_LV"
            ok "Swap désactivé"
        fi

        # Retirer de fstab
        local uuid
        uuid=$(blkid -s UUID -o value "$SWAP_LV" 2>/dev/null)
        if [[ -f /etc/fstab ]] && [[ -n "$uuid" ]] && grep -q "$uuid" /etc/fstab; then
            sed -i "/$uuid/d" /etc/fstab
            ok "Entrée supprimée de /etc/fstab"
        elif [[ -f /etc/fstab ]] && grep -q "$SWAP_LV" /etc/fstab; then
            sed -i "\|$SWAP_LV|d" /etc/fstab
            ok "Entrée supprimée de /etc/fstab"
        fi

        confirm "Supprimer définitivement $SWAP_LV ?" || return
        lvremove -f "$SWAP_LV"
        ok "Swap supprimé"
        ;;

    *)
        warn "Choix invalide"
        ;;
    esac
    pause
}

# ═══════════════════════════════════════════════════════════════════════════
#  MODULE 11 — GESTION DU SWAP (LVM)
# ═══════════════════════════════════════════════════════════════════════════
manage_swap() {
    title "GESTION DU SWAP SUR LVM"

    echo -e "  ${BLD}1)${RST} Afficher les swaps actifs"
    echo -e "  ${BLD}2)${RST} Créer un LV swap"
    echo -e "  ${BLD}3)${RST} Étendre un LV swap (à chaud)"
    echo -e "  ${BLD}4)${RST} Réduire un LV swap (désactivé requis)"
    echo -e "  ${BLD}5)${RST} Déplacer un LV swap vers un autre VG (à chaud)"
    echo -e "  ${BLD}6)${RST} Supprimer un LV swap"
    echo -e "  ${BLD}7)${RST} Créer un swap mutualisé pour plusieurs OS"
    echo
    read -rp "$(echo -e "${CYN}Choix${RST} [1-6] : ")" swap_action

    case "$swap_action" in
    1)
        echo -e "\n${BLD}▶ Swaps actifs :${RST}"
        sep
        swapon --show 2>/dev/null || echo "Aucun swap actif"
        echo
        echo -e "${BLD}▶ LV avec type swap :${RST}"
        lvs -o lv_path,lv_size,lv_attr -S "lv_layout=swap" 2>/dev/null || echo "Aucun LV swap trouvé"
        ;;

    2)
        echo -e "\n${BLD}▶ Volume Groups disponibles :${RST}"
        vgs --noheadings -o vg_name,vg_size,vg_free 2>/dev/null
        echo
        read -rp "$(echo -e "${CYN}VG cible${RST} : ")" VG_SWAP
        vgs "$VG_SWAP" &>/dev/null || die "VG '$VG_SWAP' introuvable"

        read -rp "$(echo -e "${CYN}Nom du LV swap${RST} (ex: swap_vol) : ")" LV_SWAP_NAME
        [[ -z "$LV_SWAP_NAME" ]] && die "Nom vide"

        read -rp "$(echo -e "${CYN}Taille${RST} (ex: 2G, 4G) : ")" SWAP_SIZE
        [[ -z "$SWAP_SIZE" ]] && die "Taille vide"

        confirm "Créer /dev/$VG_SWAP/$LV_SWAP_NAME de taille $SWAP_SIZE ?" || return

        lvcreate -L "$SWAP_SIZE" -n "$LV_SWAP_NAME" "$VG_SWAP"
        mkswap "/dev/$VG_SWAP/$LV_SWAP_NAME"
        ok "LV swap créé : /dev/$VG_SWAP/$LV_SWAP_NAME"

        if confirm "Activer le swap maintenant ?"; then
            swapon "/dev/$VG_SWAP/$LV_SWAP_NAME"
            ok "Swap activé"
        fi

        if confirm "Ajouter à /etc/fstab (montage permanent) ?"; then
            local uuid
            uuid=$(blkid -s UUID -o value "/dev/$VG_SWAP/$LV_SWAP_NAME")
            echo "UUID=$uuid  none  swap  sw  0  0" >>/etc/fstab
            ok "Entrée ajoutée dans /etc/fstab (UUID: $uuid)"
        fi
        ;;

    3)
        echo -e "\n${BLD}▶ LV swap disponibles :${RST}"
        lvs -o lv_path,lv_size -S "lv_layout=swap" 2>/dev/null || die "Aucun LV swap trouvé"
        echo
        read -rp "$(echo -e "${CYN}LV swap à étendre${RST} : ")" SWAP_LV
        lvdisplay "$SWAP_LV" &>/dev/null || die "LV '$SWAP_LV' introuvable"

        local vg_name
        vg_name=$(lvs --noheadings -o vg_name "$SWAP_LV" | tr -d ' ')
        local vg_free
        vg_free=$(vgs --noheadings --units g -o vg_free "$vg_name" | tr -d ' g')
        info "Espace libre dans $vg_name : ${vg_free}G"

        read -rp "$(echo -e "${CYN}Nouvelle taille${RST} (ex: 4G, +2G) : ")" NEW_SIZE

        # Désactiver temporairement si actif
        local was_active=false
        if swapon --show | grep -q "$SWAP_LV"; then
            warn "Swap actif détecté — désactivation temporaire..."
            swapoff "$SWAP_LV"
            was_active=true
            ok "Swap désactivé"
        fi

        info "Extension du LV swap..."
        if [[ "$NEW_SIZE" == +* ]]; then
            lvextend -L "$NEW_SIZE" "$SWAP_LV"
        else
            lvextend -L "$NEW_SIZE" "$SWAP_LV"
        fi

        # Réinitialiser le swap (nécessaire après extension)
        mkswap "$SWAP_LV"
        ok "Swap étendu et reformaté"

        if [[ "$was_active" == true ]]; then
            swapon "$SWAP_LV"
            ok "Swap réactivé"
        fi

        lvs "$SWAP_LV"
        ;;

    4)
        echo -e "\n${BLD}▶ LV swap disponibles :${RST}"
        lvs -o lv_path,lv_size -S "lv_layout=swap" 2>/dev/null || die "Aucun LV swap trouvé"
        echo
        read -rp "$(echo -e "${CYN}LV swap à réduire${RST} : ")" SWAP_LV

        # Vérifier et désactiver
        if swapon --show | grep -q "$SWAP_LV"; then
            swapoff "$SWAP_LV"
            ok "Swap désactivé"
        else
            info "Swap déjà inactif"
        fi

        read -rp "$(echo -e "${CYN}Nouvelle taille${RST} (ex: 2G) : ")" NEW_SIZE

        # Vérifier la taille (ne pas réduire en dessous de ce qui est utilisé)
        warn "Réduction destructive — le swap sera reformaté après réduction"
        confirm "Continuer ?" || return

        lvreduce -L "$NEW_SIZE" "$SWAP_LV"
        mkswap "$SWAP_LV"
        ok "Swap réduit et reformaté"

        if confirm "Réactiver le swap ?"; then
            swapon "$SWAP_LV"
            ok "Swap réactivé"
        fi
        ;;

    5)
        echo -e "\n${BLD}▶ Déplacer un LV swap vers un autre VG (à chaud)${RST}"
        echo
        echo -e "${BLD}▶ LV swap disponibles :${RST}"
        lvs -o lv_path,lv_size,vg_name -S "lv_layout=swap" 2>/dev/null || die "Aucun LV swap trouvé"
        echo
        read -rp "$(echo -e "${CYN}LV swap à déplacer${RST} : ")" SWAP_LV
        lvdisplay "$SWAP_LV" &>/dev/null || die "LV introuvable"

        echo -e "\n${BLD}▶ VG disponibles :${RST}"
        vgs -o vg_name,vg_size,vg_free 2>/dev/null
        echo
        read -rp "$(echo -e "${CYN}VG de destination${RST} : ")" DST_VG
        vgs "$DST_VG" &>/dev/null || die "VG '$DST_VG' introuvable"

        local current_vg
        current_vg=$(lvs --noheadings -o vg_name "$SWAP_LV" | tr -d ' ')
        local lv_name
        lv_name=$(basename "$SWAP_LV")
        local lv_size
        lv_size=$(lvs --noheadings --units g -o lv_size "$SWAP_LV" | tr -d ' ' | sed 's/g//i')

        confirm "Déplacer $SWAP_LV ($lv_size G) vers $DST_VG ?" || return

        # Désactiver swap
        local was_active=false
        if swapon --show | grep -q "$SWAP_LV"; then
            swapoff "$SWAP_LV"
            was_active=true
            ok "Swap désactivé"
        fi

        # Méthode : créer nouveau LV, copier les données (mkswap = nouveau format)
        local new_lv_path="/dev/$DST_VG/$lv_name"
        info "Création du nouveau LV swap : $new_lv_path"
        lvcreate -L "${lv_size}G" -n "$lv_name" "$DST_VG"
        mkswap "$new_lv_path"

        # Mettre à jour fstab
        local old_uuid new_uuid
        old_uuid=$(blkid -s UUID -o value "$SWAP_LV")
        new_uuid=$(blkid -s UUID -o value "$new_lv_path")

        if [[ -f /etc/fstab ]] && grep -q "$old_uuid" /etc/fstab; then
            sed -i "s/$old_uuid/$new_uuid/g" /etc/fstab
            ok "/etc/fstab mis à jour"
        elif [[ -f /etc/fstab ]] && grep -q "$SWAP_LV" /etc/fstab; then
            sed -i "s|$SWAP_LV|$new_lv_path|g" /etc/fstab
            ok "/etc/fstab mis à jour"
        fi

        # Activer nouveau swap
        if [[ "$was_active" == true ]]; then
            swapon "$new_lv_path"
            ok "Nouveau swap activé"
        fi

        # Supprimer l'ancien
        lvremove -f "$SWAP_LV"
        ok "Ancien swap supprimé"

        echo -e "\n${GRN}Swap déplacé : $new_lv_path${RST}"
        lvs "$new_lv_path"
        ;;

    6)
        echo -e "\n${BLD}▶ LV swap disponibles :${RST}"
        lvs -o lv_path,lv_size -S "lv_layout=swap" 2>/dev/null || die "Aucun LV swap trouvé"
        echo
        read -rp "$(echo -e "${CYN}LV swap à supprimer${RST} : ")" SWAP_LV

        # Désactiver si actif
        if swapon --show | grep -q "$SWAP_LV"; then
            swapoff "$SWAP_LV"
            ok "Swap désactivé"
        fi

        # Retirer de fstab
        local uuid
        uuid=$(blkid -s UUID -o value "$SWAP_LV" 2>/dev/null)
        if [[ -f /etc/fstab ]] && [[ -n "$uuid" ]] && grep -q "$uuid" /etc/fstab; then
            sed -i "/$uuid/d" /etc/fstab
            ok "Entrée supprimée de /etc/fstab"
        elif [[ -f /etc/fstab ]] && grep -q "$SWAP_LV" /etc/fstab; then
            sed -i "\|$SWAP_LV|d" /etc/fstab
            ok "Entrée supprimée de /etc/fstab"
        fi

        confirm "Supprimer définitivement $SWAP_LV ?" || return
        lvremove -f "$SWAP_LV"
        ok "Swap supprimé"
        ;;
    7)
        echo -e "\n${BLD}▶ Créer un swap mutualisé pour plusieurs OS${RST}"
        echo -e "  ${DIM}Utile quand plusieurs distribs partagent le même disque/SSD${RST}"
        echo
        echo -e "  ${BLD}Principe :${RST}"
        echo "    - Un seul LV swap créé"
        echo "    - Tous les OS l'utilisent (même UUID)"
        echo "    - Un seul OS à la fois peut l'activer (risque sinon)"
        echo
        echo -e "${BLD}▶ Volume Groups disponibles :${RST}"
        vgs -o vg_name,vg_size,vg_free
        echo
        read -rp "$(echo -e "${CYN}VG cible${RST} (où créer le swap commun) : ")" VG_SHARED
        vgs "$VG_SHARED" &>/dev/null || die "VG '$VG_SHARED' introuvable"

        read -rp "$(echo -e "${CYN}Nom du LV swap${RST} (ex: swap_shared) : ")" SWAP_NAME
        [[ -z "$SWAP_NAME" ]] && SWAP_NAME="swap_shared"

        read -rp "$(echo -e "${CYN}Taille${RST} (ex: 4G, 8G) : ")" SWAP_SIZE
        [[ -z "$SWAP_SIZE" ]] && die "Taille vide"

        confirm "Créer /dev/$VG_SHARED/$SWAP_NAME (taille $SWAP_SIZE)" || return

        lvcreate -L "$SWAP_SIZE" -n "$SWAP_NAME" "$VG_SHARED"
        mkswap "/dev/$VG_SHARED/$SWAP_NAME"

        local SWAP_UUID
        SWAP_UUID=$(blkid -s UUID -o value "/dev/$VG_SHARED/$SWAP_NAME")

        ok "Swap créé : /dev/$VG_SHARED/$SWAP_NAME (UUID: $SWAP_UUID)"
        echo
        echo -e "${BLD}▶ Pour chaque OS, ajouter dans /etc/fstab :${RST}"
        echo -e "  ${DIM}UUID=$SWAP_UUID  none  swap  sw  0  0${RST}"
        echo
        warn "⚠  Attention : Un seul OS à la fois peut activer ce swap"
        echo "   Si deux OS bootent ensemble, corruption garantie"
        ;;
    *)
        warn "Choix invalide"
        ;;
    esac
    pause
}
# ═══════════════════════════════════════════════════════════════════════════
#  MODULE 11.5 — SWAP MUTUALISÉ
# ═══════════════════════════════════════════════════════════════════════════
manage_swap_mutualized() {
    title "MUTUALISER TOUS LES SWAPS EN UN SEUL"

    # 1. Afficher les VG disponibles
    echo -e "${BLD}▶ Volume Groups disponibles :${RST}"
    vgs -o vg_name,vg_size,vg_free
    echo

    # 2. Scanner tous les swaps actifs (zram + lvswap + partitions)
    echo -e "${BLD}▶ Swaps détectés sur ce système :${RST}"
    swapon --show 2>/dev/null || echo "  Aucun swap actif"
    lvs -o lv_path,lv_size,vg_name -S "lv_layout=swap" 2>/dev/null || echo "  Aucun LV swap"
    cat /proc/swaps 2>/dev/null | head -10
    echo

    # 3. Détecter les autres OS (partitions avec /etc/fstab)
    echo -e "\n${BLD}▶ Autres systèmes détectés :${RST}"
    for part in $(lsblk -o MOUNTPOINT -l | grep -v "^$" | grep -v "^/$"); do
        if [[ -f "$part/etc/fstab" ]]; then
            echo "  OS trouvé sur : $part"
        fi
    done
    echo

    # 4. Demander confirmation
    warn "⚠ Cette opération va :"
    echo "   - Désactiver TOUS les swaps"
    echo "   - Supprimer TOUS les LV swap existants"
    echo "   - Créer un UNIQUE swap mutualisé"
    echo "   - Mettre à jour TOUS les /etc/fstab trouvés"
    echo
    confirm "Continuer ?" || return

    # 5. Désactiver tous les swaps
    info "Désactivation de TOUS les swaps..."
    swapoff -a 2>/dev/null
    ok "Swaps désactivés"

    # 6. Supprimer les anciens LV swap
    info "Suppression des anciens LV swap..."
    for old_swap in $(lvs -o lv_path -S "lv_layout=swap" --noheadings 2>/dev/null); do
        echo "  Suppression : $old_swap"
        lvremove -f "$old_swap" 2>/dev/null
    done
    ok "Anciens LV swap supprimés"

    # 7. Créer le nouveau swap unique
    echo -e "${BLD}▶ Volume Groups disponibles :${RST}"
    vgs -o vg_name,vg_size,vg_free
    echo
    read -rp "$(echo -e "${CYN}VG pour le swap mutualisé${RST} : ")" VG_MUTUAL
    vgs "$VG_MUTUAL" &>/dev/null || die "VG '$VG_MUTUAL' introuvable"

    local total_ram=$(free -b | grep Mem | awk '{print $2}')
    local default_size=$((total_ram / 2))
    echo -e "  Taille recommandée : $(numfmt --to=iec $default_size) (50% de la RAM)"
    read -rp "$(echo -e "${CYN}Taille${RST} (ex: 4G, 8G) : ")" SWAP_SIZE
    [[ -z "$SWAP_SIZE" ]] && SWAP_SIZE="$(numfmt --to=iec $default_size)"

    info "Création du swap mutualisé..."
    lvcreate -L "$SWAP_SIZE" -n "swap_mutualized" "$VG_MUTUAL"
    mkswap "/dev/$VG_MUTUAL/swap_mutualized"
    SWAP_UUID=$(blkid -s UUID -o value "/dev/$VG_MUTUAL/swap_mutualized")
    ok "Swap créé : /dev/$VG_MUTUAL/swap_mutualized (UUID: $SWAP_UUID)"

    # 8. Mettre à jour fstab de TOUS les OS
    info "Mise à jour des /etc/fstab..."
    for fstab in $(find / -name "fstab" -path "*/etc/fstab" 2>/dev/null); do
        echo "  Mise à jour : $fstab"
        cp "$fstab" "$fstab.bak.$(date +%Y%m%d_%H%M%S)" 2>/dev/null
        sed -i '/swap/d' "$fstab" 2>/dev/null
        echo "UUID=$SWAP_UUID  none  swap  sw  0  0" >>"$fstab"
    done
    ok "Fichiers fstab mis à jour"

    # 9. Activer le nouveau swap
    swapon "/dev/$VG_MUTUAL/swap_mutualized"
    ok "Swap mutualisé activé"

    # 10. Résumé final
    echo
    sep
    echo -e "${GRN}✓ Migration terminée !${RST}"
    echo -e "  Nouveau swap : /dev/$VG_MUTUAL/swap_mutualized"
    echo -e "  UUID : $SWAP_UUID"
    echo -e "  Taille : $SWAP_SIZE"
    swapon --show | grep -E "NAME|swap_mutualized" || true

    pause
}
# ═══════════════════════════════════════════════════════════════════════════
#  MODULE 12 — GESTION ZRAM (swap compressé en RAM)
# ═══════════════════════════════════════════════════════════════════════════
manage_zram() {
    title "GESTION ZRAM (swap compressé en RAM)"

    echo -e "  ${BLD}1)${RST} Afficher l'état actuel de zram"
    echo -e "  ${BLD}2)${RST} Installer/configurer zram (permanent)"
    echo -e "  ${BLD}3)${RST} Modifier l'algorithme de compression (lzo/lz4/zstd)"
    echo -e "  ${BLD}4)${RST} Modifier la taille du zram (à chaud, temporaire)"
    echo -e "  ${BLD}5)${RST} Désactiver/arrêter zram"
    echo -e "  ${BLD}6)${RST} Réactiver zram"
    echo
    read -rp "$(echo -e "${CYN}Choix${RST} [1-6] : ")" zram_action

    case "$zram_action" in
    1)
        echo -e "\n${BLD}▶ Périphériques zram :${RST}"
        sep
        lsblk | grep zram || echo "Aucun zram détecté"
        echo
        echo -e "${BLD}▶ Swaps actifs (dont zram) :${RST}"
        swapon --show | grep -E "zram|NAME" || echo "Aucun swap zram actif"
        echo
        echo -e "${BLD}▶ Algorithmes disponibles :${RST}"
        cat /sys/block/zram0/comp_algorithm 2>/dev/null || echo "Zram non chargé"
        echo
        echo -e "${BLD}▶ Taille actuelle :${RST}"
        for dev in /sys/block/zram*/disksize; do
            if [[ -f "$dev" ]]; then
                size=$(cat "$dev" 2>/dev/null)
                name=$(echo "$dev" | cut -d/ -f4)
                echo "  $name : $(numfmt --to=iec $size 2>/dev/null || echo $size)"
            fi
        done
        ;;

    2)
        echo -e "\n${BLD}▶ Installation/configuraton permanente de zram${RST}"

        # Détection distrib
        if command -v apt-get &>/dev/null; then
            info "Installation zram-tools (Debian/Ubuntu)..."
            apt-get install -y zram-tools
            ZRAM_CONF="/etc/default/zramswap"
            ZRAM_SERVICE="zramswap"
        elif command -v dnf &>/dev/null; then
            info "Installation zram-generator (Fedora/RHEL/Rocky)..."
            dnf install -y zram-generator
            ZRAM_CONF="/etc/zram-generator.conf"
            ZRAM_SERVICE="systemd-zram-setup@zram0"
        else
            die "Distribution non supportée pour l'installation auto de zram"
        fi

        if [[ -f "$ZRAM_CONF" ]]; then
            info "Fichier de conf existant : $ZRAM_CONF"
        else
            info "Création de la configuration par défaut..."
        fi

        # Proposer taille et algo
        local total_ram
        total_ram=$(free -b | grep Mem | awk '{print $2}')
        local default_size=$((total_ram / 2))
        echo -e "\n  RAM totale : $(numfmt --to=iec $total_ram)"
        echo -e "  Taille zram recommandée : 50% soit $(numfmt --to=iec $default_size)"
        read -rp "$(echo -e "${CYN}Taille du zram${RST} (ex: 2G, 4096M, laisser vide pour 50%) : ")" ZRAM_SIZE
        [[ -z "$ZRAM_SIZE" ]] && ZRAM_SIZE="$(numfmt --to=iec $default_size)"

        # Convertir en megabytes pour zram-tools (évite l'erreur arithmétique)
        local ZRAM_SIZE_MB
        if [[ "$ZRAM_SIZE" =~ G$ ]]; then
            ZRAM_SIZE_MB=$(echo "$ZRAM_SIZE" | sed 's/G//' | awk '{print int($1 * 1024)}')
        elif [[ "$ZRAM_SIZE" =~ M$ ]]; then
            ZRAM_SIZE_MB=$(echo "$ZRAM_SIZE" | sed 's/M//')
        else
            ZRAM_SIZE_MB=$((ZRAM_SIZE / 1024 / 1024))
        fi

        echo -e "\n  ${BLD}Algorithmes disponibles :${RST}"
        echo -e "  lzo   (rapide, bonne compression)"
        echo -e "  lz4   (très rapide, compression moyenne)"
        echo -e "  zstd  (bonne compression, un peu plus lent)"
        echo -e "  lzo-rle (variante de lzo)"
        read -rp "$(echo -e "${CYN}Algorithme${RST} [lz4 par défaut] : ")" ZRAM_ALGO
        [[ -z "$ZRAM_ALGO" ]] && ZRAM_ALGO="lz4" # Configuration selon distrib
        if command -v apt-get &>/dev/null; then
            cat >"$ZRAM_CONF" <<EOF
# zram-tools configuration
PERCENT=50
SIZE=$ZRAM_SIZE_MB
ALGO=$ZRAM_ALGO
PRIORITY=100
EOF
            systemctl enable --now zramswap
            ok "Zram configuré et activé"
        elif command -v dnf &>/dev/null; then
            cat >"$ZRAM_CONF" <<EOF
[zram0]
zram-size = $ZRAM_SIZE
compression-algorithm = $ZRAM_ALGO
swap-priority = 100
EOF
            systemctl enable --now systemd-zram-setup@zram0
            ok "Zram configuré et activé"
        fi
        ;;

    3)
        echo -e "\n${BLD}▶ Modifier l'algorithme de compression${RST}"

        # Vérifier si zram actif
        if ! lsmod | grep -q zram; then
            warn "Zram non chargé. Installez/activez d'abord (option 2)"
            return
        fi

        echo -e "\n${BLD}Algorithmes supportés par le noyau :${RST}"
        cat /sys/block/zram0/comp_algorithm 2>/dev/null || die "Impossible de lire les algorithmes"

        echo -e "\n  ${BLD}Algorithmes disponibles :${RST}"
        echo -e "  lzo   (rapide)"
        echo -e "  lz4   (très rapide)"
        echo -e "  zstd  (meilleur ratio)"

        echo "  lzo-rle"
        read -rp "$(echo -e "${CYN}Nouvel algorithme${RST} : ")" NEW_ALGO

        # Pour changer à chaud, il faut réinitialiser zram
        warn "Changement d'algorithme nécessite la désactivation du swap zram"
        confirm "Continuer ?" || return

        # Désactiver tous les zram
        for dev in /dev/zram*; do
            [[ -b "$dev" ]] && swapoff "$dev" 2>/dev/null
        done
        rmmod zram
        modprobe zram

        # Réactiver avec le nouvel algo
        echo "$NEW_ALGO" >/sys/block/zram0/comp_algorithm 2>/dev/null || die "Algorithme non supporté"

        # Reconfigurer taille (récupérer l'ancienne config)
        local old_size
        old_size=$(cat /sys/block/zram0/disksize 2>/dev/null || echo "1G")

        echo "Configuration zram avec algo $NEW_ALGO..."
        # La taille sera restaurée par le service/systemd au reboot

        ok "Algorithme changé pour $NEW_ALGO (redémarrage nécessaire pour persistance)"
        ;;

    4)
        echo -e "\n${BLD}▶ Modifier la taille du zram (temporaire)${RST}"

        if ! lsmod | grep -q zram; then
            die "Zram non chargé"
        fi

        local current_size
        current_size=$(cat /sys/block/zram0/disksize 2>/dev/null)
        info "Taille actuelle : $(numfmt --to=iec $current_size 2>/dev/null)"

        read -rp "$(echo -e "${CYN}Nouvelle taille${RST} (ex: 2G, 4096M) : ")" ZRAM_NEW_SIZE

        warn "Changement de taille nécessite désactivation"
        confirm "Continuer ?" || return

        # Désactiver zram
        for dev in /dev/zram*; do
            [[ -b "$dev" ]] && swapoff "$dev" 2>/dev/null
        done

        # Reconfigurer taille
        echo 1 >/sys/block/zram0/reset 2>/dev/null
        echo "$ZRAM_NEW_SIZE" >/sys/block/zram0/disksize

        # Réactiver
        mkswap /dev/zram0
        swapon /dev/zram0 -p 100

        ok "Taille modifiée : $ZRAM_NEW_SIZE"
        swapon --show | grep zram
        ;;

    5)
        echo -e "\n${BLD}▶ Désactiver/arrêter zram${RST}"
        confirm "Désactiver tous les périphériques zram ?" || return

        for dev in /dev/zram*; do
            [[ -b "$dev" ]] && swapoff "$dev" 2>/dev/null
        done
        rmmod zram 2>/dev/null
        ok "Zram désactivé"

        if command -v systemctl &>/dev/null; then
            systemctl stop zramswap 2>/dev/null
            systemctl stop systemd-zram-setup@zram0 2>/dev/null
        fi
        ;;

    6)
        echo -e "\n${BLD}▶ Réactiver zram${RST}"

        if command -v systemctl &>/dev/null; then
            systemctl start zramswap 2>/dev/null ||
                systemctl start systemd-zram-setup@zram0 2>/dev/null ||
                warn "Service non trouvé, activation manuelle..."
        fi

        # Activation manuelle si service absent
        if ! lsmod | grep -q zram; then
            modprobe zram
            echo "lz4" >/sys/block/zram0/comp_algorithm
            echo "1G" >/sys/block/zram0/disksize
            mkswap /dev/zram0
            swapon /dev/zram0 -p 100
            ok "Zram réactivé manuellement (taille 1G, algo lz4)"
        else
            ok "Zram déjà actif"
        fi
        swapon --show | grep zram
        ;;

    *)
        warn "Choix invalide"
        ;;
    esac
    pause
}

# ─── Utilitaires ───────────────────────────────────────────────────────────
pause() {
    echo
    read -rp "$(echo -e "${DIM}  Appuyez sur Entrée pour continuer...${RST}")" _
}

# ═══════════════════════════════════════════════════════════════════════════
#  MENU PRINCIPAL
# ═══════════════════════════════════════════════════════════════════════════
main_menu() {
    while true; do
        banner
        echo -e "  ${BLD}MENU PRINCIPAL${RST}\n"
        echo -e "  ${CYN}1)${RST}  Diagnostic complet (état LVM)"
        echo -e "  ${CYN}2)${RST}  Créer un Logical Volume"
        echo -e "  ${CYN}3)${RST}  Étendre un LV + redimensionner FS  ${DIM}(à chaud)${RST}"
        echo -e "  ${CYN}4)${RST}  Réduire un LV                      ${DIM}(ext4, démontage requis)${RST}"
        echo -e "  ${CYN}5)${RST}  Déplacer des données (pvmove)       ${DIM}(à chaud, online)${RST}"
        echo -e "  ${CYN}6)${RST}  Snapshots LVM"
        echo -e "  ${CYN}7)${RST}  Ajouter un disque / étendre un VG"
        echo -e "  ${CYN}8)${RST}  Migrer l'OS vers un nouveau disque  ${DIM}(à chaud)${RST}"
        echo -e "  ${CYN}9)${RST}  Supprimer un LV"
        echo -e "  ${CYN}e)${RST}  Exporter le diagnostic"
        echo -e "  ${CYN}s)${RST}  Gestion du Swap (LVM)"
        echo -e "  ${CYN}z)${RST}  Gestion ZRAM (swap compressé)"
        echo -e "  ${CYN}q)${RST}  Quitter"
        echo
        sep
        read -rp "$(echo -e "  ${BLD}Votre choix${RST} : ")" choice
        echo

        case "$choice" in
        1) diag_full ;;
        2) create_lv ;;
        3) extend_lv ;;
        4) shrink_lv ;;
        5) pvmove_data ;;
        6) snapshot_lv ;;
        7) add_disk_to_vg ;;
        8) migrate_os ;;
        9) remove_lv ;;
        s | S) manage_swap ;;
        z | Z) manage_zram ;;
        e | E) export_result ;;
        q | Q | quit | exit)
            echo -e "\n${GRN}Au revoir !${RST}\n"
            exit 0
            ;;
        *)
            warn "Choix invalide : '$choice'"
            sleep 1
            ;;
        esac
    done
}

# ═══════════════════════════════════════════════════════════════════════════
#  POINT D'ENTRÉE
# ═══════════════════════════════════════════════════════════════════════════
check_root
check_deps
main_menu
