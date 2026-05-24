#!/bin/bash
# postinstall.sh - Script d'optimisation post-installation Debian/Ubuntu

set -e

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
apt install -y \
    curl wget git build-essential software-properties-common \
    apt-transport-https ca-certificates gnupg lsb-release unzip zip \
    gzip tar vim nano neovim htop ncdu tree tmux screen \
    net-tools nmap ufw fail2ban openssh-server rsync jq fzf \
    ripgrep fd-find bat duf p7zip-full strace ltrace \
    lsof iotop nethogs iftop sqlite3 python3 python3-pip python3-venv \
    pastebinit fastfetch unrar fakeroot devscripts \
    libncurses-dev libelf-dev libssl-dev dwarves \
    flex bison bc cpio kmod gawk openssl dkms \
    libudev-dev libpci-dev libiberty-dev autoconf llvm \
    zstd lzop u-boot-tools rsync sassc
snap install core
snap install micro --classic

sudo apt install libarchive-tools
bash

sudo mkdir -p /usr/local/share/fonts/redhat
curl -fsSL https://github.com/RedHatOfficial/RedHatFont/archive/refs/tags/5.0.0.zip
sudo bsdtar -xvf- -C /usr/local/share/fonts/redhat/ --include="*.ttf" --include="*.otf" --strip-components=3

curl -fsSL https://github.com/ryanoasis/nerd-fonts/raw/master/patched-fonts/Hack/Regular/HackNerdFontMono-Regular.ttf \
    -o /usr/local/share/fonts/HackNerdFontMono-Regular.ttf
fc-cache -fv

curl -fsSL https://apt.fury.io/wez/gpg.key | gpg --dearmor -o /usr/share/keyrings/wezterm-fury.gpg
echo 'deb [signed-by=/usr/share/keyrings/wezterm-fury.gpg] https://apt.fury.io/wez/ * *' >/etc/apt/sources.list.d/wezterm.list

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

cat >/root/.vimrc <<'EOF'
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
set background=dark
colorscheme desert
set cursorline
set showmatch
set hlsearch
set incsearch
set ignorecase
set smartcase

nnoremap <space> :
nnoremap <C-s> :w<CR>
inoremap <C-s> <Esc>:w<CR>
nnoremap <C-q> :q!<CR>
EOF

if [ -n "$SUDO_USER" ]; then
    cp /root/.vimrc /home/"$SUDO_USER"/.vimrc
    chown "$SUDO_USER":"$SUDO_USER" /home/"$SUDO_USER"/.vimrc
fi

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

print_info "Configuration du firewall..."
ufw default deny incoming
ufw default allow outgoing
ufw allow ssh
ufw allow 80/tcp
ufw allow 443/tcp

print_info "Configuration de fail2ban..."
systemctl enable fail2ban
systemctl start fail2ban

print_info "Optimisations système..."

cat >>/etc/security/limits.conf <<'EOF'
* soft nofile 65535
* hard nofile 65535
* soft nproc 65535
* hard nproc 65535
EOF

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

sysctl -p

print_info "Création des alias..."
cat >>"/home/$SUDO_USER/.bashrc" <<'EOF'

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
alias tree='tree -C'
alias htop='htop -C'
alias editp='gnome-text-editor'
alias fetch='fastfetch'
alias cls='clear'
alias v='nvim'

histdel() {
    history -c
    history -w
    rm -f ~/.bash_history
    source ~/.bashrc
}

alias logout='gnome-session-quit --logout --no-prompt'

if command -v bat &> /dev/null; then
    alias cat='bat'
fi

if command -v exa &> /dev/null; then
    alias ls='exa --icons'
    alias ll='exa -l --icons'
    alias la='exa -la --icons'
    alias tree='exa --tree --icons'
fi

if command -v duf &> /dev/null; then
    alias df='duf'
fi

mkcd() {
    mkdir -p "$1" && cd "$1"
}

ex() {
    if [ -f $1 ]; then
        case $1 in
            *.tar.bz2) tar xjf $1 ;;
            *.tar.gz) tar xzf $1 ;;
            *.bz2) bunzip2 $1 ;;
            *.rar) unrar e $1 ;;
            *.gz) gunzip $1 ;;
            *.tar) tar xf $1 ;;
            *.tbz2) tar xjf $1 ;;
            *.tgz) tar xzf $1 ;;
            *.zip) unzip $1 ;;
            *.Z) uncompress $1 ;;
            *.7z) 7z x $1 ;;
            *) echo "'$1' ne peut pas être extrait" ;;
        esac
    else
        echo "'$1' n'est pas un fichier valide"
    fi
}
EOF

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
echo -e "${YELLOW}• Utilitaires système${NC}"
echo -e "${YELLOW}• Pastebinit + fastfetch${NC}"
echo ""
echo -e "${GREEN}Optimisations :${NC}"
echo -e "${YELLOW}• Configuration VIM${NC}"
echo -e "${YELLOW}• Configuration HTOP${NC}"
echo -e "${YELLOW}• Limites système augmentées${NC}"
echo -e "${YELLOW}• Optimisations réseau${NC}"
echo -e "${YELLOW}• Aliases bash pratiques${NC}"
echo ""
echo -e "${GREEN}Recommandations :${NC}"
echo -e "${YELLOW}• Redémarrez votre session pour profiter des alias${NC}"
echo -e "${YELLOW}• Activez le firewall: sudo ufw enable${NC}"
echo -e "${GREEN}================================${NC}"

print_info "Post-installation terminée avec succès !"
