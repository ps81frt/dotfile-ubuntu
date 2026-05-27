#!/bin/bash
# =============================================================
# VARIABLES — modifier uniquement cette section
# =============================================================

HOSTNAME="ubuntoutou"
USERNAME="cyber"
REALNAME=""                # nom complet affiché (laisser vide si inutile)
PASSWORD_USER="0"          # mot de passe utilisateur en clair
PASSWORD_ROOT="0"          # mot de passe root en clair

LOCALE="fr_FR.UTF-8"
KEYBOARD="fr"
KEYBOARD_VARIANT=""        # variante clavier ex: "latin9", laisser vide si aucune
TIMEZONE="Europe/Paris"

DISK="/dev/sda"
SIZE_EFI="512M"            # partition EFI (512M recommandé, 1G si dual-boot)
SIZE_BOOT="1G"             # partition /boot
SIZE_SWAP="4G"             # swap (généralement = RAM pour hibernate)
SIZE_ROOT="30G"            # partition /
# /home prend le reste automatiquement

LVM_VG="vg-ubuntu"        # nom du Volume Group
LVM_LV_SWAP="lv-swap"     # nom du Logical Volume swap
LVM_LV_ROOT="lv-root"     # nom du Logical Volume /
LVM_LV_HOME="lv-home"     # nom du Logical Volume /home

FS_EFI="vfat"             # filesystem EFI (fat32 obligatoire UEFI)
FS_BOOT="ext4"             # filesystem /boot
FS_ROOT="ext4"             # filesystem /
FS_HOME="ext4"             # filesystem /home

KERNEL_FLAVOR="hwe"        # flaveur kernel : "hwe" ou "generic"
NETWORK_RENDERER="NetworkManager"  # "NetworkManager" (desktop) ou "networkd" (server)

# --- GRUB ---
GRUB_CMDLINE="quiet splash"        # options kernel ex: "quiet splash", "" pour rien
GRUB_TIMEOUT="5"                   # délai menu GRUB en secondes (0 = pas de menu)
GRUB_TIMEOUT_STYLE="hidden"        # "hidden" (pas de menu sauf Shift) ou "menu"
GRUB_TERMINAL="console"            # "console" ou "gfxterm" (graphique)
GRUB_DISABLE_OS_PROBER="true"      # "true" = pas de détection dual-boot, "false" sinon

# Paquets supplémentaires (laisser vide si aucun)
EXTRA_PACKAGES=$'\n    - curl\n    - git\n    - vim\n    - htop\n    - net-tools\n    - open-vm-tools-desktop\n    - openssh-server\n    - bash-completion\n    - wget\n    - unzip\n    - zip\n    - tree\n    - lsof\n    - dnsutils\n    - traceroute\n    - whois\n    - nmap\n    - tcpdump\n    - gnome-tweaks'
# Snaps supplémentaires (laisser vide si aucun)
EXTRA_SNAPS=""

# SSH root login : "yes" ou "no"
SSH_ROOT_LOGIN="yes"

# Mises à jour auto : "security", "all" ou "none"
AUTO_UPDATES="security"

# =============================================================
# NE PAS MODIFIER EN DESSOUS
# =============================================================

HASH_USER=$(openssl passwd -6 "$PASSWORD_USER")
HASH_ROOT=$(openssl passwd -6 "$PASSWORD_ROOT")
HASH_USER_ESC=$(printf "%s" "$HASH_USER" | sed 's/[&/\]/\\&/g')
HASH_ROOT_ESC=$(printf "%s" "$HASH_ROOT" | sed 's/[&/\]/\\&/g')

OUTPUT="$(dirname "$0")/autoinstall.yaml"

cat > "$OUTPUT" << EOF
#cloud-config
# -------------------------------------------------------
# Généré par generate.sh — NE PAS MODIFIER DIRECTEMENT
# Modifier les variables dans generate.sh puis relancer
# Ubuntu 26.04 LTS Resolute Raccoon
# -------------------------------------------------------
autoinstall:
  version: 1

  packages:
    - ubuntu-desktop${EXTRA_PACKAGES}

  snaps:
    - name: firefox
    - name: gtk-common-themes
    - name: snap-store
    - name: snapd-desktop-integration${EXTRA_SNAPS}

  identity:
    realname: '${REALNAME}'
    username: ${USERNAME}
    password: "USERHASHPLACEHOLDER"
    hostname: ${HOSTNAME}

  keyboard:
    layout: ${KEYBOARD}
    variant: '${KEYBOARD_VARIANT}'

  locale: ${LOCALE}

  timezone: ${TIMEZONE}

  network:
    ethernets:
      any-eth:
        match:
          name: "e*"
        dhcp4: true
    version: 2

  storage:
    version: 1
    config:
      - type: disk
        id: disk0
        path: ${DISK}
        ptable: gpt
        wipe: superblock
        grub_device: false

      - type: partition
        id: part-efi
        device: disk0
        size: ${SIZE_EFI}
        flag: boot
        grub_device: true

      - type: partition
        id: part-boot
        device: disk0
        size: ${SIZE_BOOT}

      - type: partition
        id: part-lvm
        device: disk0
        size: -1
        flag: linux-lvm

      - type: lvm_volgroup
        id: vg0
        name: ${LVM_VG}
        devices:
          - part-lvm

      - type: lvm_partition
        id: ${LVM_LV_SWAP}
        volgroup: vg0
        name: ${LVM_LV_SWAP}
        size: ${SIZE_SWAP}

      - type: lvm_partition
        id: ${LVM_LV_ROOT}
        volgroup: vg0
        name: ${LVM_LV_ROOT}
        size: ${SIZE_ROOT}

      - type: lvm_partition
        id: ${LVM_LV_HOME}
        volgroup: vg0
        name: ${LVM_LV_HOME}
        size: -1

      - type: format
        id: fmt-efi
        volume: part-efi
        fstype: ${FS_EFI}
        label: EFI

      - type: format
        id: fmt-boot
        volume: part-boot
        fstype: ${FS_BOOT}
        label: boot

      - type: format
        id: fmt-swap
        volume: ${LVM_LV_SWAP}
        fstype: swap
        label: swap

      - type: format
        id: fmt-root
        volume: ${LVM_LV_ROOT}
        fstype: ${FS_ROOT}
        label: root

      - type: format
        id: fmt-home
        volume: ${LVM_LV_HOME}
        fstype: ${FS_HOME}
        label: home

      - type: mount
        id: mnt-efi
        device: fmt-efi
        path: /boot/efi

      - type: mount
        id: mnt-boot
        device: fmt-boot
        path: /boot

      - type: mount
        id: mnt-swap
        device: fmt-swap
        path: none

      - type: mount
        id: mnt-root
        device: fmt-root
        path: /

      - type: mount
        id: mnt-home
        device: fmt-home
        path: /home

  user-data:
    chpasswd:
      list: |
        root:ROOTHASHPLACEHOLDER
      expire: false
    users:
      - name: root
        lock_passwd: false

  kernel:
    flavor: ${KERNEL_FLAVOR}

  late-commands:
      - curtin in-target -- add-apt-repository universe -y
      - curtin in-target -- add-apt-repository multiverse -y
      - curtin in-target -- add-apt-repository restricted -y
      - curtin in-target -- apt-get update
      - >-
        curtin in-target -- apt-get install -y
        build-essential dkms linux-headers-generic linux-tools-common
        autoconf automake cmake ninja-build meson pkg-config
        gcc g++ gdb clang lldb llvm lld make patch fakeroot
        bc flex bison libssl-dev libelf-dev libncurses-dev ncurses-dev
        dwarves pahole debhelper ccache mold
        neovim nano tmux screen btop rsync cpio kmod file jq
        ripgrep fd-find bat
        tar gzip bzip2 xz-utils zstd lz4 p7zip-full p7zip-rar rar unrar
        openssh-client iputils-ping
        python3 python3-pip python3-venv
        ca-certificates gnupg lsb-release software-properties-common apt-transport-https
        ffmpeg imagemagick ufw fail2ban qtbase5-dev cloud-init
        smartmontools hdparm nvme-cli lshw dmidecode hwinfo inxi
        sysstat iotop iftop nethogs bmon
        strace ltrace valgrind
        pciutils usbutils ethtool iproute2 acpi
        lm-sensors stress stress-ng memtester fio
        linux-tools-generic
      - >-
        curtin in-target --
        sed -i /etc/default/grub -e
        's/GRUB_CMDLINE_LINUX_DEFAULT=".*/GRUB_CMDLINE_LINUX_DEFAULT="${GRUB_CMDLINE}"/'
      - >-
        curtin in-target --
        sed -i /etc/default/grub -e
        's/^#\?GRUB_TIMEOUT=.*/GRUB_TIMEOUT=${GRUB_TIMEOUT}/'
      - >-
        curtin in-target --
        sed -i /etc/default/grub -e
        's/^#\?GRUB_TIMEOUT_STYLE=.*/GRUB_TIMEOUT_STYLE=${GRUB_TIMEOUT_STYLE}/'
      - >-
        curtin in-target --
        sed -i /etc/default/grub -e
        's/^#\?GRUB_TERMINAL=.*/GRUB_TERMINAL=${GRUB_TERMINAL}/'
      - >-
        curtin in-target --
        sed -i /etc/default/grub -e
        's/^#\?GRUB_DISABLE_OS_PROBER=.*/GRUB_DISABLE_OS_PROBER=${GRUB_DISABLE_OS_PROBER}/'
      - curtin in-target -- update-grub
      - rm /target/etc/netplan/00-installer-config*yaml
      - >-
        printf "network:\n  version: 2\n  renderer: ${NETWORK_RENDERER}"
        > /target/etc/netplan/01-network-manager-all.yaml
      - sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin ${SSH_ROOT_LOGIN}/' /target/etc/ssh/sshd_config
      - >-
        curtin in-target -- apt-get remove -y
        ubuntu-server
        motd-news-config lxd-agent-loader
        landscape-common
      - curtin in-target -- apt-get autoremove -y


  updates: ${AUTO_UPDATES}

  shutdown: reboot
EOF

# Injection sécurisée des hashs (contiennent des $ qui casseraient le heredoc)
sed -i "s|USERHASHPLACEHOLDER|${HASH_USER}|g" "$OUTPUT"
sed -i "s|ROOTHASHPLACEHOLDER|${HASH_ROOT}|g" "$OUTPUT"

echo "✓ autoinstall.yaml généré pour : hostname=${HOSTNAME} user=${USERNAME} disk=${DISK}"
