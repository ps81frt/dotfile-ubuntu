#!/usr/bin/env bash
#===============================================================================
#  secure.sh — Secure Boot, état MOK, enrôlement clé, signature EFI/noyau
#  Sourcé automatiquement par Rep-Dem.sh
#===============================================================================

#-------------------------------------------------------------------------------
# ÉTAT SECURE BOOT
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
        if [[ "$sb_byte" == "1" ]]; then sb_state="enabled"; else sb_state="disabled"; fi
        log_info "Secure Boot (efivars) : $sb_state"
    fi

    if command_exists sbctl; then
        log_info "sbctl status :"
        sbctl status 2>/dev/null | while read -r l; do printf '  %s\n' "$l"; done
    fi

    echo "$sb_state"
}

#-------------------------------------------------------------------------------
# ENRÔLEMENT CLÉ MOK
#-------------------------------------------------------------------------------
enroll_mok_key() {
    log_header "ENRÔLEMENT CLÉ MOK (Secure Boot)"

    if [[ $(detect_boot_mode) != "uefi" ]]; then
        log_error "Secure Boot nécessite UEFI"; return 1
    fi

    if ! command_exists mokutil; then
        log_warning "mokutil non disponible — tentative d'installation..."
        install_packages mokutil || { log_error "mokutil requis pour la gestion MOK"; return 1; }
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
            mokutil --list-enrolled 2>/dev/null \
                | while read -r l; do printf '  %s\n' "$l"; done \
                || log_warning "Aucune clé MOK enrôlée"
            ;;

        2)
            read -r -p "Chemin vers la clé .der ou .cer à enrôler : " mok_cert
            [[ ! -f "$mok_cert" ]] && { log_error "Fichier introuvable : $mok_cert"; return 1; }
            echo ""
            printf "%b\n" "${YELLOW}Un redémarrage sera nécessaire pour finaliser l'enrôlement.${NC}"
            printf "%b\n" "${YELLOW}MokManager demandera la confirmation et le mot de passe.${NC}"
            echo ""
            if confirm_action "Enrôler $mok_cert dans la base MOK ?" yes; then
                mokutil --import "$mok_cert" 2>&1 \
                    | while read -r l; do log_info "mokutil: $l"; done
                log_success "Clé mise en file d'attente. Redémarrez pour finaliser dans MokManager."
            fi
            ;;

        3)
            local mok_dir="/etc/Rep-Dem/mok"
            mkdir -p "$mok_dir"; chmod 700 "$mok_dir"
            local mok_key="${mok_dir}/MOK.key" mok_crt="${mok_dir}/MOK.crt" mok_der="${mok_dir}/MOK.der"

            if [[ -f "$mok_key" && -f "$mok_der" ]]; then
                log_info "Clé MOK existante détectée dans $mok_dir"
                if ! confirm_action "Régénérer la paire de clés MOK ? (l'ancienne sera sauvegardée)" yes; then
                    read -r -p "Utiliser la clé existante pour l'enrôlement ? [O/n] : " use_existing
                    if [[ "${use_existing,,}" != "n" ]]; then
                        mokutil --import "$mok_der" 2>&1 \
                            | while read -r l; do log_info "mokutil: $l"; done
                        log_success "Clé existante mise en file d'attente."
                    fi
                    return 0
                fi
                local bts; bts=$(date +%H%M%S)
                cp -a "$mok_key" "${mok_key}.bak.${bts}" 2>/dev/null
                cp -a "$mok_der" "${mok_der}.bak.${bts}" 2>/dev/null
            fi

            if ! command_exists openssl; then
                log_warning "openssl requis — tentative d'installation..."
                install_packages openssl || { log_error "openssl requis"; return 1; }
            fi

            log_info "Génération d'une paire RSA-2048 + certificat auto-signé..."
            openssl req -new -x509 -newkey rsa:2048 -keyout "$mok_key" \
                -out "$mok_crt" -days 3650 -subj "/CN=Rep-Dem MOK/" \
                -nodes 2>/dev/null || { log_error "Échec openssl"; return 1; }
            openssl x509 -in "$mok_crt" -outform DER -out "$mok_der" 2>/dev/null \
                || { log_error "Conversion DER échouée"; return 1; }
            chmod 600 "$mok_key"
            log_success "Clé générée    : $mok_key"
            log_success "Certificat     : $mok_crt"
            log_success "Format DER     : $mok_der"

            mokutil --import "$mok_der" 2>&1 \
                | while read -r l; do log_info "mokutil: $l"; done
            echo ""
            printf "%b\n" "${GREEN}Clé MOK mise en file d'attente.${NC}"
            printf "%b\n" "${YELLOW}Au prochain démarrage, MokManager vous demandera de confirmer${NC}"
            printf "%b\n" "${YELLOW}l'enrôlement et de saisir le mot de passe indiqué ci-dessus.${NC}"
            echo ""
            ;;

        4)
            if ! command_exists sbsign && ! command_exists pesign; then
                log_warning "sbsign ou pesign requis — tentative d'installation..."
                install_packages sbsigntool 2>/dev/null \
                    || install_packages pesign 2>/dev/null \
                    || { log_error "Aucun outil de signature disponible"; return 1; }
            fi
            local mok_key="/etc/Rep-Dem/mok/MOK.key" mok_crt="/etc/Rep-Dem/mok/MOK.crt"
            [[ ! -f "$mok_key" || ! -f "$mok_crt" ]] && {
                log_error "Clé MOK non générée. Utilisez l'option 3 d'abord."; return 1; }
            read -r -p "Fichier EFI ou module .ko à signer : " file_to_sign
            [[ ! -f "$file_to_sign" ]] && { log_error "Fichier introuvable : $file_to_sign"; return 1; }

            local signed_file="${file_to_sign}.signed"
            if command_exists sbsign; then
                sbsign --key "$mok_key" --cert "$mok_crt" \
                    --output "$signed_file" "$file_to_sign" 2>&1 \
                    | while read -r l; do log_info "sbsign: $l"; done
            elif command_exists pesign; then
                pesign --sign --in="$file_to_sign" --out="$signed_file" \
                    --certificate="$mok_crt" 2>&1 \
                    | while read -r l; do log_info "pesign: $l"; done
            fi
            if [[ -f "$signed_file" ]]; then
                log_success "Fichier signé : $signed_file"
                if confirm_action "Remplacer l'original par le fichier signé ?" yes; then
                    mv "$signed_file" "$file_to_sign"
                    log_success "Original remplacé"
                fi
            fi
            ;;

        5)
            read -r -p "Fichier EFI à vérifier : " file_to_verify
            [[ ! -f "$file_to_verify" ]] && { log_error "Fichier introuvable : $file_to_verify"; return 1; }
            echo ""
            if command_exists sbverify; then
                sbverify --list "$file_to_verify" 2>&1 \
                    | while read -r l; do printf '  %s\n' "$l"; done
            elif command_exists pesign; then
                pesign --show-signatures --in="$file_to_verify" 2>&1 \
                    | while read -r l; do printf '  %s\n' "$l"; done
            else
                log_warning "sbverify / pesign non disponibles"
            fi
            ;;

        6) return 0 ;;
        *) log_warning "Choix invalide" ;;
    esac
}
