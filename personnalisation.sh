#!/bin/bash

########################################
# GNOME POST INSTALL - Ubuntu 26.04
########################################

# Vérification root
if [[ $(id -u) -eq 0 ]]
then
    echo -e "\033[31mATTENTION\033[0m"
    echo "Vous lancez ce script en root."
    echo "La session GNOME root sera modifiée."
    echo "Poursuite dans 10 secondes..."
    sleep 10
fi

########################################
# CONFIGURATION GÉNÉRALE
########################################

echo "Configuration générale de GNOME"

# Boutons fenêtres
gsettings set org.gnome.desktop.wm.preferences button-layout ':minimize,maximize,close'

# Volume >100%
gsettings set org.gnome.desktop.sound allow-volume-above-100-percent true

# Popup détachées
gsettings set org.gnome.mutter attach-modal-dialogs false

# Calendrier
gsettings set org.gnome.desktop.calendar show-weekdate true

# Horloge
gsettings set org.gnome.desktop.interface clock-show-date true
gsettings set org.gnome.desktop.interface clock-show-seconds true
gsettings set org.gnome.desktop.interface clock-show-weekday true
gsettings set org.gnome.desktop.interface clock-format '24h'

# Pointer locate
gsettings set org.gnome.desktop.interface locate-pointer true

# Touchpad
gsettings set org.gnome.desktop.peripherals.touchpad disable-while-typing true
gsettings set org.gnome.desktop.peripherals.touchpad click-method 'areas'
gsettings set org.gnome.desktop.peripherals.touchpad tap-to-click true

# Sons système
gsettings set org.gnome.desktop.wm.preferences audible-bell false

# Hot corner OFF
gsettings set org.gnome.desktop.interface enable-hot-corners false

# Timeout app freeze
gsettings set org.gnome.mutter check-alive-timeout 60000

# Night light
gsettings set org.gnome.settings-daemon.plugins.color night-light-enabled true

# Nettoyage auto
gsettings set org.gnome.desktop.privacy remove-old-temp-files true
gsettings set org.gnome.desktop.privacy remove-old-trash-files true
gsettings set org.gnome.desktop.privacy old-files-age 30

########################################
# CONFIDENTIALITÉ
########################################

echo "Configuration confidentialité"

gsettings set org.gnome.desktop.privacy report-technical-problems false
gsettings set org.gnome.desktop.privacy send-software-usage-stats false
gsettings set org.gnome.desktop.privacy remember-recent-files false
gsettings set org.gnome.desktop.privacy recent-files-max-age -1

########################################
# APPARENCE
########################################

echo "Personnalisation GNOME"

# Dark mode
gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark'

# Theme GTK
gsettings set org.gnome.desktop.interface gtk-theme 'Yaru-blue-dark'

# Icônes Ubuntu
gsettings set org.gnome.desktop.interface icon-theme 'Yaru-blue'

# Curseur
gsettings set org.gnome.desktop.interface cursor-theme 'Yaru'

# Animations
gsettings set org.gnome.desktop.interface enable-animations true

########################################
# NAUTILUS
########################################

echo "Configuration Nautilus"

# Vue liste
gsettings set org.gnome.nautilus.preferences default-folder-viewer 'list-view'

# Tree view
gsettings set org.gnome.nautilus.list-view use-tree-view true

# Zoom
gsettings set org.gnome.nautilus.list-view default-zoom-level 'small'

# DnD
gsettings set org.gnome.nautilus.preferences open-folder-on-dnd-hover false

# Double clic
gsettings set org.gnome.nautilus.preferences click-policy 'double'

# Tri dossiers
gsettings set org.gtk.Settings.FileChooser sort-directories-first true
gsettings set org.gtk.gtk4.Settings.FileChooser sort-directories-first true

########################################
# GNOME SOFTWARE
########################################

echo "Configuration GNOME Software"

gsettings set org.gnome.software download-updates false
gsettings set org.gnome.software show-only-free-apps false

########################################
# TEXT EDITOR
########################################

echo "Configuration Text Editor"

gsettings set org.gnome.TextEditor highlight-current-line false
gsettings set org.gnome.TextEditor restore-session false
gsettings set org.gnome.TextEditor show-line-numbers true

########################################
# GNOME WEB
########################################

echo "Configuration GNOME Web"

gsettings set org.gnome.Epiphany ask-for-default false
gsettings set org.gnome.Epiphany homepage-url 'about:blank'
gsettings set org.gnome.Epiphany start-in-incognito-mode true

########################################
# PTYXIS
########################################

echo "Configuration Ptyxis"

gsettings set org.gnome.Ptyxis use-system-font false
gsettings set org.gnome.Ptyxis font-name 'Ubuntu Mono 13'
gsettings set org.gnome.Ptyxis restore-session false

########################################
# FONTS
########################################

echo "Configuration polices"

gsettings set org.gnome.desktop.interface font-name 'Ubuntu 11'
gsettings set org.gnome.desktop.interface document-font-name 'Sans 11'
gsettings set org.gnome.desktop.interface monospace-font-name 'Ubuntu Mono 13'

########################################
# DASH TO DOCK
########################################

echo "Configuration Dash-to-Dock"

# Activation
gnome-extensions enable dash-to-dock@micxgx.gmail.com

# Position
gsettings set org.gnome.shell.extensions.dash-to-dock dock-position 'BOTTOM'

# Dock flottant
gsettings set org.gnome.shell.extensions.dash-to-dock extend-height false

# Auto hide intelligent
gsettings set org.gnome.shell.extensions.dash-to-dock dock-fixed false
gsettings set org.gnome.shell.extensions.dash-to-dock autohide true
gsettings set org.gnome.shell.extensions.dash-to-dock intellihide true
gsettings set org.gnome.shell.extensions.dash-to-dock autohide-in-fullscreen true

# Taille icônes
gsettings set org.gnome.shell.extensions.dash-to-dock dash-max-icon-size 42

# Transparence
gsettings set org.gnome.shell.extensions.dash-to-dock transparency-mode 'FIXED'
gsettings set org.gnome.shell.extensions.dash-to-dock background-opacity 0.80

# Coins arrondis
gsettings set org.gnome.shell.extensions.dash-to-dock border-radius 18

# Clic = réduire
gsettings set org.gnome.shell.extensions.dash-to-dock click-action 'minimize'

# Désactivation overview au boot
gsettings set org.gnome.shell.extensions.dash-to-dock disable-overview-on-startup true

# Pas de trash/mounts
gsettings set org.gnome.shell.extensions.dash-to-dock show-trash false
gsettings set org.gnome.shell.extensions.dash-to-dock show-mounts false

########################################
# APPINDICATOR
########################################

echo "Activation AppIndicator"

gnome-extensions enable appindicatorsupport@rgcjonas.gmail.com

########################################
# EXTENSIONS BONUS
########################################

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
