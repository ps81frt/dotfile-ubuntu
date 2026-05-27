#!/bin/bash
set -euo pipefail

VERBOSE="${VERBOSE:-1}"

log() {
    [ "$VERBOSE" -eq 1 ] && echo "INFO: $1"
}

error() {
    echo "ERREUR: $1"
}

run() {
    local name="$1"
    local script="$2"

    log "$name"
    if ! bash "$script"; then
        error "échec dans $script"
        exit 1
    fi
}

ROOT_SCRIPTS=(
    "Post-installation (admin)|postinstall.sh"
    "Neovim & Tmux|nvim_tmux_setup.sh"
)

USER_SCRIPTS=(
    "Personnalisation GNOME|personnalisation.sh"
    "Fix LSP Server|fix-lsp-server-ubuntu.sh"
)

if [ "$EUID" -eq 0 ] && [ "${1:-}" != "user" ]; then

    for item in "${ROOT_SCRIPTS[@]}"; do
        IFS="|" read -r name script <<<"$item"
        run "$name" "$script"
    done

    if [ -n "${SUDO_USER:-}" ]; then
        USER_ID=$(id -u "$SUDO_USER")
        USER_HOME="$(getent passwd "$SUDO_USER" | cut -d: -f6)"

        exec sudo -u "$SUDO_USER" \
            DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$USER_ID/bus" \
            XDG_RUNTIME_DIR="/run/user/$USER_ID" \
            HOME="$USER_HOME" \
            bash "$0" user
    else
        error "SUDO_USER absent"
        exit 1
    fi
fi

for item in "${USER_SCRIPTS[@]}"; do
    IFS="|" read -r name script <<<"$item"
    run "$name" "$script"
done
C='\033[0;36m'
G='\033[0;32m'
Y='\033[1;33m'
D='\033[2;37m'
B='\033[1m'
R='\033[0m'
#RED='\033[0;31m'
G='\033[0;32m'
NC='\033[0m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'
print_info() {
    echo -e "${G}[INFO]${NC} $1"
}

echo -e "${C}${B}"
echo -e "  ████████╗███╗   ███╗██╗   ██╗██╗  ██╗\n"
echo -e "     ██╔══╝████╗ ████║██║   ██║╚██╗██╔╝\n"
echo -e "     ██║   ██╔████╔██║██║   ██║ ╚███╔╝ \n"
echo -e "     ██║   ██║╚██╔╝██║██║   ██║ ██╔██╗ \n"
echo -e "     ██║   ██║ ╚═╝ ██║╚██████╔╝██╔╝ ██╗\n"
echo -e "     ╚═╝   ╚═╝     ╚═╝ ╚═════╝ ╚═╝  ╚═╝\n"
echo -e "${R}\n"
echo -e "${D}  ──────────────────────────────────────────────────────${R}\n"
echo -e "  ${Y}${B}PREFIX : Ctrl+A${R}\n"
echo -e "${D}  ──────────────────────────────────────────────────────${R}\n\n"
echo -e "${G}${B}  SPLITS${R}\n"
echo -e "  ${C}Ctrl+A v${R}   split vertical   (cote a cote)\n"
echo -e "  ${C}Ctrl+A b${R}   split horizontal (haut / bas)\n\n"
echo -e "${G}${B}  NAVIGATION panes${R}  ${D}(3 methodes)${R}\n"
echo -e "  ${C}Alt + Fleches${R}            sans prefix  ${D}[le plus rapide]${R}\n"
echo -e "  ${C}Ctrl+A + Fleches${R}         avec prefix\n"
echo -e "  ${C}Ctrl+A + h j k l${R}         vim-style\n\n"
echo -e "${G}${B}  RESIZE panes${R}\n"
echo -e "  ${C}Ctrl+A + Ctrl + Fleches${R}  +3  (repetable)\n"
echo -e "  ${C}Ctrl+A + Maj  + Fleches${R}  +10 (grand pas)\n\n"
echo -e "${G}${B}  FENETRES${R}\n"
echo -e "  ${C}Ctrl+A c${R}    nouvelle fenetre\n"
echo -e "  ${C}Ctrl+A Tab${R}  fenetre suivante\n"
echo -e "  ${C}Ctrl+A 1-9${R}  aller a la fenetre N\n"
echo -e "  ${C}Ctrl+A x${R}    fermer pane    ${C}Ctrl+A X${R}  fermer fenetre\n\n"
echo -e "${G}${B}  SESSIONS${R}\n"
echo -e "  ${C}Ctrl+A s${R}   choisir    ${C}Ctrl+A d${R}  detacher\n"
echo -e "  ${C}Ctrl+A N${R}   nouvelle session\n\n"
echo -e "${G}${B}  COPY MODE${R}\n"
echo -e "  ${C}Ctrl+A [${R}   entrer      Fleches ou hjkl pour naviguer\n"
echo -e "  ${C}v${R} selectionner    ${C}y${R} copier    ${C}q${R} quitter\n\n"
echo -e "${G}${B}  DIVERS${R}\n"
echo -e "  ${C}Ctrl+A r${R}   recharger tmux.conf\n"
echo -e "  ${C}Ctrl+A W${R}   reafficher cette aide\n"
echo -e "  ${C}Ctrl+A p${R}   coller depuis clipboard systeme\n\n"
echo -e "${D}  ──────────────────────────────────────────────────────${R}\n"
echo ""
echo -e "${C}╔══════════════════════════════════════════════════════╗${NC}"
echo -e "${C}║   ${G}${BOLD}Installation terminee !${NC}                          ${CYAN}║${NC}"
echo -e "${C}╚══════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${G}LazyVim :${NC} ts_ls + pyright + lua_ls + bashls (ShellCheck) | Treesitter | Harpoon2 | TokyoNight"
echo -e "${G}Tmux    :${NC} Welcome screen | Alt+Fleches | Ctrl+A v/b | Resize Ctrl+Fl."
echo ""
echo -e "${Y}Etapes suivantes :${NC}"
echo "  1. source ~/.bashrc"
echo "  2. nvim                     (LazyVim finit l'install)"
echo "  3. tmux                     (welcome screen auto)"
echo "     Ctrl+A + I               (installer plugins TPM)"
echo "  4. sudo install-lsp-servers (optionnel)"
echo ""
echo -e "${C}════════════════════════════════════════════════════════${NC}"
echo -e "${G}================================${NC}"
echo -e "${G}Paquets installés :${NC}"
echo -e "${Y}• VIM + Neovim${NC}"
echo -e "${Y}• HTOP${NC}"
echo -e "${Y}• Git, Curl, Wget${NC}"
echo -e "${Y}• Build essential${NC}"
echo -e "${Y}• Outils réseau et sécurité${NC}"
echo -e "${Y}• SSH Server (openssh-server)${NC}"
echo -e "${Y}• Utilitaires système (tree, ncdu, tmux, screen)${NC}"
echo -e "${Y}• Pastebinit + fastfetch${NC}"
echo ""
echo -e "${G}Configs installées :${NC}"
echo -e "${Y}• Fail2ban: /etc/fail2ban/jail.d/sshd.local${NC}"
echo -e "${Y}• Sysctl: /etc/sysctl.conf + sysctl --system${NC}"
echo -e "${Y}• Limits: /etc/security/limits.conf${NC}"
echo -e "${Y}• Bash aliases: /home/\$SUDO_USER/.bashrc${NC}"
echo -e "${Y}• Vim config: /root/.vimrc + user copy${NC}"
echo -e "${Y}• WezTerm config: /root/.config/wezterm/ + user sync${NC}"
echo -e "${Y}• Fonts: /usr/local/share/fonts/${NC}"
echo ""
echo -e "${G}Services actifs :${NC}"
echo -e "${Y}• UFW Firewall (ports 22/80/443)${NC}"
echo -e "${Y}• Fail2ban SSH protection${NC}"
echo -e "${Y}• OpenSSH server${NC}"
echo ""
echo -e "${G}Optimisations :${NC}"
echo -e "${Y}• Configuration VIM${NC}"
echo -e "${Y}• Configuration HTOP${NC}"
echo -e "${Y}• Limites système augmentées (ulimits)${NC}"
echo -e "${Y}• Optimisations réseau (TCP/sysctl)${NC}"
echo ""
echo -e "${G}Recommandations :${NC}"
echo -e "${Y}• Reconnect session ou reboot si alias non chargés${NC}"
echo -e "${G}================================${NC}"

echo "Extensions recommandées"

echo "Installer si absent :"
echo " - Blur My Shell"
echo " - Just Perfection"
echo " - Extension Manager"

########################################
# FINAL
########################################

echo ""
echo "===================================="
echo "Personnalisation terminée."
echo "Redémarrez votre session GNOME."
echo "===================================="
log "TERMINE"
