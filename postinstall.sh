#!/bin/bash
# postinstall.sh - Script d'optimisation post-installation Debian/Ubuntu

set -e
set -o pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}[ERROR] Ce script doit être exécuté en tant que root (sudo)${NC}"
    exit 1
fi

print_info "Début de la post-installation..."

apt update && apt upgrade -y
apt autoremove -y

print_info "Installation des paquets..."
apt-get install -y \
    build-essential dkms linux-headers-generic linux-tools-generic linux-tools-common \
    autoconf automake cmake ninja-build meson pkg-config \
    gcc g++ gdb clang lldb llvm lld make patch fakeroot devscripts \
    bc flex bison libssl-dev libelf-dev libncurses-dev ncurses-dev \
    dwarves pahole debhelper ccache mold \
    neovim nano tmux screen btop rsync cpio kmod file jq \
    ripgrep fd-find bat \
    tar gzip bzip2 xz-utils zstd lz4 lzop p7zip-full rar unrar \
    openssh-client openssh-server iputils-ping \
    python3 python3-pip python3-venv \
    ca-certificates gnupg lsb-release software-properties-common apt-transport-https \
    ffmpeg imagemagick ufw fail2ban qtbase5-dev cloud-init \
    smartmontools hdparm nvme-cli lshw dmidecode hwinfo inxi \
    sysstat iotop iftop nethogs bmon \
    strace ltrace valgrind \
    pciutils usbutils ethtool iproute2 acpi \
    lm-sensors stress stress-ng memtester fio \
    curl wget git git-delta vim nano htop ncdu tree net-tools nmap \
    lsof sqlite3 pastebinit fastfetch fzf duf \
    libpci-dev libudev-dev libiberty-dev openssl dkms \
    zip unzip gawk kmod openssl u-boot-tools sassc \
    libncurses-dev libelf-dev libssl-dev \
    flex bison bc cpio kmod gawk openssl dkms \
    gnome-shell-extensions gnome-tweaks colordiff

snap install core
snap refresh
snap install micro --classic

apt install libarchive-tools
mkdir -p /usr/local/share/fonts/redhat
#curl -fsSL https://github.com/RedHatOfficial/RedHatFont/archive/refs/tags/5.0.0.zip
#sudo bsdtar -xvf- -C /usr/local/share/fonts/redhat/ --include="*.ttf" --include="*.otf" --strip-components=3
curl -fsSL https://github.com/RedHatOfficial/RedHatFont/archive/refs/tags/5.0.0.zip -o /tmp/redhat-font.zip
bsdtar -xvf /tmp/redhat-font.zip -C /usr/local/share/fonts/redhat/ --include="*.ttf" --include="*.otf" --strip-components=3
rm -f /tmp/redhat-font.zip

curl -fsSL https://github.com/ryanoasis/nerd-fonts/raw/master/patched-fonts/Hack/Regular/HackNerdFontMono-Regular.ttf \
    -o /usr/local/share/fonts/HackNerdFontMono-Regular.ttf
fc-cache -fv

# install fastfetch
if [ -n "$SUDO_USER" ]; then
    USER_HOME=$(eval echo "~$SUDO_USER")

    print_info "Configuration de Fastfetch pour $SUDO_USER..."

    mkdir -p "$USER_HOME/Images/wallpapers"
    mkdir -p "$USER_HOME/.config/fastfetch"

    cp ".config/fastfetch/raccoon-fastfetch.png" "$USER_HOME/Images/wallpapers/"
    cp ".config/fastfetch/config.jsonc" "$USER_HOME/.config/fastfetch/"

    chown -R "$SUDO_USER":"$SUDO_USER" "$USER_HOME/Images" "$USER_HOME/.config/fastfetch"
fi

#curl -fsSL https://apt.fury.io/wez/gpg.key | gpg --dearmor -o /usr/share/keyrings/wezterm-fury.gpg
#echo 'deb [signed-by=/usr/share/keyrings/wezterm-fury.gpg] https://apt.fury.io/wez/ * *' >/etc/apt/sources.list.d/wezterm.list

#apt update
#apt install -y wezterm-nightly
print_info "Installation de WezTerm (dépôt officiel)..."

rm -f /etc/apt/sources.list.d/wezterm.list /usr/share/keyrings/wezterm-fury.gpg

curl -fsSL https://apt.fury.io/wez/gpg.key | gpg --yes --dearmor -o /usr/share/keyrings/wezterm-fury.gpg
echo 'deb [signed-by=/usr/share/keyrings/wezterm-fury.gpg] https://apt.fury.io/wez/ * *' >/etc/apt/sources.list.d/wezterm.list
chmod 644 /usr/share/keyrings/wezterm-fury.gpg

cp ./raccoon.png "${USER_HOME}/Images/wallpapers/"
gsettings set org.gnome.desktop.background picture-uri "file:///home/${USER}/Images/wallpapers/raccoon.png"
gsettings set org.gnome.desktop.background picture-uri-dark "file:///home/${USER}/Images/wallpapers/raccoon.png"

# Installe WezTerm
apt update
apt install -y wezterm-nightly

WEZTERM_CONFIG_URL="https://raw.githubusercontent.com/ps81frt/dotfile-ubuntu/refs/heads/main/wezterm.lua"
curl -fsSL "$WEZTERM_CONFIG_URL" -o /tmp/wezterm.lua

mkdir -p /root/.config/wezterm
cp /tmp/wezterm.lua /root/.config/wezterm/wezterm.lua

while IFS=: read -r username _ uid _ _ homedir _; do
    if [[ $uid -ge 1000 && $uid -lt 65534 && -d "$homedir" ]]; then
        mkdir -p "$homedir/.config/wezterm"
        cp /tmp/wezterm.lua "$homedir/.config/wezterm/wezterm.lua"
        chown -R "$username":"$username" "$homedir/.config/wezterm"
    fi
done </etc/passwd

rm -f /tmp/wezterm.lua

if [ -n "$SUDO_USER" ]; then
    USER_HOME=$(eval echo "~$SUDO_USER")

    mkdir -p "$USER_HOME/.config/wezterm/colors"

    curl -Lo "$USER_HOME/.config/wezterm/colors/nightfox.toml" \
        https://raw.githubusercontent.com/mbadolato/iTerm2-Color-Schemes/master/wezterm/Nightfox.toml

    sed -i 's#config.color_scheme = "Gruvbox dark, medium (base16)"#---config.color_scheme = "Gruvbox dark, medium (base16)"#' \
        "$USER_HOME/.config/wezterm/wezterm.lua"

    sed -i '/---config.color_scheme = "Gruvbox dark, medium (base16)"/a config.color_scheme = "nightfox"' \
        "$USER_HOME/.config/wezterm/wezterm.lua"
fi

sed -i '/config.font = wezterm.font_with_fallback/,/})/c\
config.font = wezterm.font_with_fallback({\
    "Red Hat Mono",\
    "Hack Nerd Font Mono",\
    "JetBrains Mono",\
})' "$USER_HOME/.config/wezterm/wezterm.lua"

echo 'config.color_scheme = "nightfox" ~/.config/wezterm/wezterm.lua'

rm -f /root/.vimrc /home/"$SUDO_USER"/.vimrc

TARGET_USER_VIMRC="/home/$SUDO_USER/.vimrc"
TARGET_ROOT_VIMRC="/root/.vimrc"

if [ ! -f "$TARGET_USER_VIMRC" ]; then
    cat >"$TARGET_USER_VIMRC" <<'EOF'
" Améliorations VIM
set number
set relativenumber
set tabstop=4
set shiftwidth=4
set expandtab
set autoindent
set smartindent
set mouse=a
set encoding=utf-8
syntax on
set showmatch
set hlsearch
set incsearch
set ignorecase
set smartcase
set hidden
set wildmenu
set showcmd
set scrolloff=5
set splitright
set splitbelow
set backspace=indent,eol,start
set termguicolors
set clipboard+=unnamedplus
set listchars=tab:>·,trail:·

" Mapping pratiques
nnoremap <space> :
nnoremap <C-s> :w<CR>
inoremap <C-s> <Esc>:w<CR>
nnoremap <C-q> :q!<CR>
nnoremap <space>s :saveas<Space>
EOF
    chown "$SUDO_USER":"$SUDO_USER" "$TARGET_USER_VIMRC"

    cp "$TARGET_USER_VIMRC" "$TARGET_ROOT_VIMRC"
    print_info "Configuration VIM installée."
else
    print_info "Configuration VIM déjà existante, aucune modification."
fi

mkdir -p /root/.config/htop
if [ ! -f "/root/.config/htop/htoprc" ]; then
    mkdir -p /root/.config/htop
    cat >/root/.config/htop/htoprc <<'EOF'
fields=0 48 17 18 38 39 40 2 46 47 49 1
sort_key=46
sort_direction=1
tree_view=0
tree_view_always_by_pid=0
all_branches_collapsed=0
hide_threads=0
hide_kernel_threads=0
hide_userland_threads=0
shadow_other_users=0
show_program_path=1
highlight_base_name=0
highlight_megabytes=1
highlight_threads=1
highlight_changes=1
highlight_changes_delay_secs=5
show_cpu_usage=1
show_cpu_frequency=0
show_cpu_temperature=0
tree_view_cpu_usage=0
update_process_names=0
account_guest_in_cpu_meter=1
color_scheme=0
enable_mouse=0
delay=15
left_meters=LeftCPUs2 Memory Swap
left_meter_modes=1 1 1
right_meters=RightCPUs2 Tasks LoadAverage Uptime
right_meter_modes=1 2 2 2
EOF
fi
print_info "Configuration du firewall..."

ufw default deny incoming
ufw default allow outgoing

ufw allow ssh
ufw allow 80/tcp
ufw allow 443/tcp

ufw --force enable
ufw reload

print_info "Configuration de fail2ban (SSH)..."

install -d /etc/fail2ban/jail.d

if [ ! -f "/etc/fail2ban/jail.d/sshd.local" ]; then
    cat >/etc/fail2ban/jail.d/sshd.local <<'EOF'
[sshd]                     # Jail SSH (protection des connexions SSH)
enabled = true            # Active la protection fail2ban pour SSH
backend = systemd         # Utilise systemd pour lire les logs
port = ssh                # Surveille le port SSH (22 par défaut)
maxretry = 10             # 10 tentatives échouées avant bannissement
findtime = 10m            # Fenêtre de 10 minutes pour compter les échecs
bantime = 10m             # Bannissement de 10 minutes après dépassement
bantime.increment = true  # Augmente le temps de ban si récidive
ignoreip = 127.0.0.1/8    # Ignore localhost (jamais banni)
EOF
    systemctl restart fail2ban
fi

systemctl enable fail2ban
systemctl restart fail2ban

print_info "Optimisations système..."

git config --global core.pager "delta"

cat >/etc/security/limits.conf <<'EOF'
* soft nofile 65535
* hard nofile 65535
* soft nproc 65535
* hard nproc 65535
EOF

if ! grep -q "net.ipv4.ip_forward = 1" /etc/sysctl.conf; then
    cat >>/etc/sysctl.conf <<'EOF'
net.core.somaxconn = 1024
net.core.netdev_max_backlog = 5000
net.ipv4.tcp_max_syn_backlog = 4096
net.ipv4.tcp_fin_timeout = 30
net.ipv4.tcp_keepalive_time = 300
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_syncookies = 1
net.ipv4.ip_forward = 1
EOF
    sysctl --system
fi

sudo tee -a /root/.bashrc <<'EOF'

if [ "$USER" = "root" ]; then
    PS1='${debian_chroot:+($debian_chroot)}\[\033[01;31m\]\u@\h\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]# '
    export PS1
fi
EOF
USER_HOME=$(eval echo "~${SUDO_USER:-root}")
BASHRC="$USER_HOME/.bashrc"

if ! grep -q "PS1_CONF_SET" "$BASHRC"; then
    cat >>"$BASHRC" <<'EOF'

export PS1

alias ll='ls -alF'
alias la='ls -A'
alias l='ls -CF'
alias update='apt update && apt upgrade -y'
alias install='apt install'
alias remove='apt remove'
alias search='apt search'
alias ports='netstat -tulpn'
alias meminfo='free -m -h'
alias disks='df -h'
alias myip='curl ifconfig.me'
alias weather='curl wttr.in'
alias cheat='curl cheat.sh'
alias hist='history | grep'
alias mkdir='mkdir -pv'
alias ..='cd ..'
alias ...='cd ../..'
alias grep='grep --color=auto'
alias diff='colordiff'
alias gdiff='git diff --no-index'
alias tree='tree -C'
alias htop='htop -C'
alias editp='gnome-text-editor'
alias fetch='fastfetch'
alias cls='clear'
alias v='nvim'
alias lf='ls -alp | grep -v "/$"'
alias ldir='ls -alp | grep "/$"'
alias latr='ls -latr'
alias ldat='ls -lta --color=auto'
alias gdiff='git diff --no-index'


histdel() {
    history -c
    history -w
    rm -f ~/.bash_history
    source ~/.bashrc
}

alias logout='gnome-session-quit --logout --no-prompt'

if command -v bat &> /dev/null; then alias cat='bat'; fi
if command -v exa &> /dev/null; then
    alias ls='exa --icons'; alias ll='exa -l --icons'; alias la='exa -la --icons'; alias tree='exa --tree --icons'
fi
if command -v duf &> /dev/null; then alias df='duf'; fi

mkcd() { mkdir -p "$1" && cd "$1"; }

ex() {
    if [ -f $1 ]; then
        case $1 in
            *.tar.bz2) tar xjf $1 ;; *.tar.gz) tar xzf $1 ;; *.bz2) bunzip2 $1 ;;
            *.rar) unrar e $1 ;; *.gz) gunzip $1 ;; *.tar) tar xf $1 ;;
            *.tbz2) tar xjf $1 ;; *.tgz) tar xzf $1 ;; *.zip) unzip $1 ;;
            *.Z) uncompress $1 ;; *.7z) 7z x $1 ;; *) echo "'$1' invalide" ;;
        esac
    else echo "'$1' invalide"; fi
}
compress() {
    local outdir=""
    while true; do
        case $1 in
        -h | --help | -help)
            echo "Usage: compress <archive> <fichiers/dossiers...> [options]"
            echo ""
            echo "Options:"
            echo "  -o, --output <dossier> dossier de destination de l'archive"
            echo ""
            echo "Formats supportés:"
            echo "  .tar.gz / .tgz    compression gzip"
            echo "  .tar.bz2 / .tbz2  compression bzip2"
            echo "  .tar              pas de compression"
            echo "  .gz               gzip (fichier unique)"
            echo "  .bz2              bzip2 (fichier unique)"
            echo "  .zip              zip"
            echo "  .7z               7-zip"
            echo ""
            echo "Exemples:"
            echo "  compress Ubuntu.tar *                           # archive tout le dossier courant"
            echo "  compress Ubuntu.tar.gz *                        # idem en gzip"
            echo "  compress Ubuntu.zip *                           # idem en zip"
            echo "  compress archive.tar.gz  mon_dossier/           # compresse le dossier"
            echo "  compress archive.tar.gz  mon_dossier/*          # compresse le contenu"
            echo "  compress archive.tar.gz  mon_dossier/* -o ~     # idem, archive dans ~"
            return 0
            ;;
        -o | --output)
            outdir="$2"
            shift 2
            ;;
        *) break ;;
        esac
    done
    if [ -z "$2" ]; then
        echo "Usage: compress <archive> <fichiers/dossiers...> [-o dossier]"
        return 1
    fi
    local archive="$1"
    shift
    local targets=("$@")
    if [ -n "$outdir" ]; then
        mkdir -p "$outdir"
        archive="$outdir/$archive"
    fi
    case $archive in
    *.tar.bz2 | *.tbz2) tar cjf "$archive" "${targets[@]}" ;;
    *.tar.gz | *.tgz) tar czf "$archive" "${targets[@]}" ;;
    *.tar) tar cf "$archive" "${targets[@]}" ;;
    *.bz2) bzip2 -k "${targets[0]}" ;;
    *.gz) gzip -k "${targets[0]}" ;;
    *.zip) zip -r "$archive" "${targets[@]}" ;;
    *.7z) 7z a "$archive" "${targets[@]}" ;;
    *) echo "'$archive' extension non supportée" ;;
    esac
}
convert_video_to_gif() {
    echo "--- CONVERSION VIDEO VERS GIF (MODE INTERACTIF) ---"
    echo ""
    read -rp "Chemin video: " input_path
    input_path="${input_path//\"/}"
    read -rp "FPS (ex: 15, 24, 30): " fps
    read -rp "Largeur (ex: 1920, 1280, 960): " width
    read -rp "Flag (lanczos, bilinear, bicubic, spline): " flag
    read -rp "GIF output: " gif_out
    [ ! -f "$input_path" ] && echo "Erreur: Fichier introuvable" && return 1
    ! command -v ffmpeg &>/dev/null && echo "Erreur: FFmpeg non trouvé dans PATH" && return 1
    [[ "$gif_out" != *.gif ]] && gif_out="${gif_out}.gif"
    parent_path="$(dirname "$input_path")"
    [ -z "$parent_path" ] && parent_path="$(pwd)"
    palette_path="${parent_path}/palette.png"
    clean_path="/tmp/input_clean_$$.mp4"
    ffmpeg_major=$(ffmpeg -version 2>&1 | grep -oP 'ffmpeg version \K[0-9]+' | head -1)
    [ "$ffmpeg_major" -ge 5 ] && vsync_flag="-fps_mode vfr" || vsync_flag="-vsync vfr"
    vf_palette="fps=${fps},scale=${width}:-1:flags=${flag},palettegen=stats_mode=diff"
    vf_gif="[0:v]setpts=PTS-STARTPTS,fps=${fps},scale=${width}:-1:flags=${flag}[x];[x][1:v]paletteuse=dither=bayer:bayer_scale=5:diff_mode=rectangle"
    echo ""
    echo "VERIFICATION timestamps..."
    frame_count=$(ffprobe -v quiet -show_entries frame=pkt_pts_time -select_streams v:0 -of csv=p=0 "$input_path" 2>&1 | grep -c '.')
    if [ "$frame_count" -lt 10 ]; then
        echo "PTS manquants ou format problematique -> re-encode intermediaire..."
        ffmpeg -fflags +genpts+discardcorrupt -err_detect ignore_err -hide_banner -loglevel warning -stats -y -i "$input_path" -c:v libx264 -preset ultrafast -crf 18 "$clean_path"
        if [ $? -ne 0 ]; then
            echo "Erreur: re-encode echoue"
            return 1
        fi
        input_path="$clean_path"
        echo "Re-encode OK -> utilisation de $clean_path"
    else echo "Timestamps OK -> conversion directe"; fi
    echo ""
    echo "ETAPE 1 : palette"
    ffmpeg -fflags +genpts+discardcorrupt -err_detect ignore_err -hide_banner -loglevel info -stats -y -i "$input_path" -vf "$vf_palette" -update 1 -frames:v 1 "$palette_path"
    [ $? -ne 0 ] && echo "Erreur: Palette erreur" && rm -f "$clean_path" && return 1
    echo ""
    echo "ETAPE 2 : GIF"
    ffmpeg -fflags +genpts+discardcorrupt -err_detect ignore_err -hide_banner -loglevel info -stats -y -i "$input_path" -i "$palette_path" -filter_complex "$vf_gif" $vsync_flag "$gif_out"
    [ $? -ne 0 ] && echo "Erreur: GIF erreur" && rm -f "$palette_path" "$clean_path" && return 1
    rm -f "$palette_path" "$clean_path"
    echo ""
    echo "OK -> $gif_out"
}


EOF
    chown "${SUDO_USER:-root}:${SUDO_USER:-root}" "$BASHRC"
fi

print_info "Correction des sources APT..."

if [ -f /etc/apt/sources.list.d/canonical.sources ]; then
    cat >/etc/apt/sources.list.d/canonical.sources <<'EOF'
Types: deb
URIs: http://archive.canonical.com/ubuntu/
Suites: jammy
Components: partner
Signed-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg
EOF
fi

if [ -f /etc/apt/sources.list.d/wezterm.sources ] && [ -f /etc/apt/sources.list.d/wezterm.list ]; then
    rm -f /etc/apt/sources.list.d/wezterm.list
fi

apt update

print_info "Nettoyage..."
apt autoclean
apt autoremove --purge -y
rm -rf /var/lib/apt/lists/*

print_info "Installation terminée !"
echo -e "${GREEN}================================${NC}"
echo -e "${GREEN}Paquets installés :${NC}"
echo -e "${YELLOW}• VIM + Neovim${NC}"
echo -e "${YELLOW}• HTOP${NC}"
echo -e "${YELLOW}• Git, Curl, Wget${NC}"
echo -e "${YELLOW}• Build essential${NC}"
echo -e "${YELLOW}• Outils réseau et sécurité${NC}"
echo -e "${YELLOW}• SSH Server (openssh-server)${NC}"
echo -e "${YELLOW}• Utilitaires système (tree, ncdu, tmux, screen)${NC}"
echo -e "${YELLOW}• Pastebinit + fastfetch${NC}"
echo ""
echo -e "${GREEN}Configs installées :${NC}"
echo -e "${YELLOW}• Fail2ban: /etc/fail2ban/jail.d/sshd.local${NC}"
echo -e "${YELLOW}• Sysctl: /etc/sysctl.conf + sysctl --system${NC}"
echo -e "${YELLOW}• Limits: /etc/security/limits.conf${NC}"
echo -e "${YELLOW}• Bash aliases: /home/\$SUDO_USER/.bashrc${NC}"
echo -e "${YELLOW}• Vim config: /root/.vimrc + user copy${NC}"
echo -e "${YELLOW}• WezTerm config: /root/.config/wezterm/ + user sync${NC}"
echo -e "${YELLOW}• Fonts: /usr/local/share/fonts/${NC}"
echo ""
echo -e "${GREEN}Services actifs :${NC}"
echo -e "${YELLOW}• UFW Firewall (ports 22/80/443)${NC}"
echo -e "${YELLOW}• Fail2ban SSH protection${NC}"
echo -e "${YELLOW}• OpenSSH server${NC}"
echo ""
echo -e "${GREEN}Optimisations :${NC}"
echo -e "${YELLOW}• Configuration VIM${NC}"
echo -e "${YELLOW}• Configuration HTOP${NC}"
echo -e "${YELLOW}• Limites système augmentées (ulimits)${NC}"
echo -e "${YELLOW}• Optimisations réseau (TCP/sysctl)${NC}"
echo ""
echo -e "${GREEN}Recommandations :${NC}"
echo -e "${YELLOW}• Reconnect session ou reboot si alias non chargés${NC}"
echo -e "${GREEN}================================${NC}"
print_info "Post-installation terminée avec succès !"
