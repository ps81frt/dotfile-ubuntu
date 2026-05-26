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
)

USER_SCRIPTS=(
    "Personnalisation GNOME|personnalisation.sh"
    "Neovim & Tmux|nvim_tmux_setup.sh"
    "Fix LSP Server|fix-lsp-server.sh"
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

log "TERMINE"
