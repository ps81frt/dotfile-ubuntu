# ~/.bashrc: executed by bash(1) for non-login shells.
# see /usr/share/doc/bash/examples/startup-files (in the package bash-doc)
# for examples

# If not running interactively, don't do anything
case $- in
*i*) ;;
*) return ;;
esac

# don't put duplicate lines or lines starting with space in the history.
# See bash(1) for more options
HISTCONTROL=ignoreboth

# append to the history file, don't overwrite it
shopt -s histappend

# for setting history length see HISTSIZE and HISTFILESIZE in bash(1)
HISTSIZE=1000
HISTFILESIZE=2000

# check the window size after each command and, if necessary,
# update the values of LINES and COLUMNS.
shopt -s checkwinsize

# If set, the pattern "**" used in a pathname expansion context will
# match all files and zero or more directories and subdirectories.
#shopt -s globstar

# make less more friendly for non-text input files, see lesspipe(1)
[ -x /usr/bin/lesspipe ] && eval "$(SHELL=/bin/sh lesspipe)"

# set variable identifying the chroot you work in (used in the prompt below)
if [ -z "${debian_chroot:-}" ] && [ -r /etc/debian_chroot ]; then
    debian_chroot=$(cat /etc/debian_chroot)
fi

# set a fancy prompt (non-color, unless we know we "want" color)
case "$TERM" in
xterm-color | *-256color) color_prompt=yes ;;
esac

# uncomment for a colored prompt, if the terminal has the capability; turned
# off by default to not distract the user: the focus in a terminal window
# should be on the output of commands, not on the prompt
#force_color_prompt=yes

if [ -n "$force_color_prompt" ]; then
    if [ -x /usr/bin/tput ] && tput setaf 1 >&/dev/null; then
        # We have color support; assume it's compliant with Ecma-48
        # (ISO/IEC-6429). (Lack of such support is extremely rare, and such
        # a case would tend to support setf rather than setaf.)
        color_prompt=yes
    else
        color_prompt=
    fi
fi

if [ "$color_prompt" = yes ]; then
    PS1='${debian_chroot:+($debian_chroot)}\[\033[01;32m\]\u@\h\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]\$ '
else
    PS1='${debian_chroot:+($debian_chroot)}\u@\h:\w\$ '
fi
unset color_prompt force_color_prompt

# If this is an xterm set the title to user@host:dir
case "$TERM" in
xterm* | rxvt*)
    PS1="\[\e]0;${debian_chroot:+($debian_chroot)}\u@\h: \w\a\]$PS1"
    ;;
*)
    ;;
esac

# enable color support of ls and also add handy aliases
if [ -x /usr/bin/dircolors ]; then
    if test -r ~/.dircolors; then
        eval "$(dircolors -b ~/.dircolors)"
    else
        eval "$(dircolors -b)"
    fi
    alias ls='ls --color=auto'
    #alias dir='dir --color=auto'
    #alias vdir='vdir --color=auto'

    alias grep='grep --color=auto'
    alias fgrep='fgrep --color=auto'
    alias egrep='egrep --color=auto'
fi

# colored GCC warnings and errors
#export GCC_COLORS='error=01;31:warning=01;35:note=01;36:caret=01;32:locus=01:quote=01'

# some more ls aliases
alias ll='ls -alF'
alias la='ls -A'
alias l='ls -CF'

# Add an "alert" alias for long running commands.  Use like so:
#   sleep 10; alert
alias alert='notify-send --urgency=low -i "$([ $? = 0 ] && echo terminal || echo error)" "$(history|tail -n1|sed -e '\''s/^\s*[0-9]\+\s*//;s/[;&|]\s*alert$//'\'')"'

# Alias definitions.
# You may want to put all your additions into a separate file like
# ~/.bash_aliases, instead of adding them here directly.
# See /usr/share/doc/bash-doc/examples in the bash-doc package.

if [ -f ~/.bash_aliases ]; then
    # shellcheck source=/dev/null
    . ~/.bash_aliases
fi

# enable programmable completion features (you don't need to enable
# this, if it's already enabled in /etc/bash.bashrc and /etc/profile
# sources /etc/bash.bashrc).
if ! shopt -oq posix; then
    if [ -f /usr/share/bash-completion/bash_completion ]; then
        . /usr/share/bash-completion/bash_completion
    elif [ -f /etc/bash_completion ]; then
        . /etc/bash_completion
    fi
fi

# PS1_CONF_SET
if [ "$USER" = "root" ]; then
    PS1='${debian_chroot:+($debian_chroot)}\[\033[01;31m\]\u@\h\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]# '
fi
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
alias tree='tree -C'
#alias htop='htop -G'
alias editp='gnome-text-editor'
alias fetch='fastfetch'
alias cls='clear'
alias v='nvim'

histdel() {
    history -c
    history -w
    rm -f ~/.bash_history
    # shellcheck source=/dev/null
    source ~/.bashrc
}

alias logout='gnome-session-quit --logout --no-prompt'

if command -v bat &>/dev/null; then alias cat='bat'; fi
if command -v exa &>/dev/null; then
    alias ls='exa --icons'
    alias ll='exa -l --icons'
    alias la='exa -la --icons'
    alias tree='exa --tree --icons'
fi
if command -v duf &>/dev/null; then alias df='duf'; fi

mkcd() { mkdir -p "$1" && cd $1; }

ex() {
    if [ -f "$1" ]; then
        case $1 in
        *.tar.bz2) tar xjf "$1" ;; *.tar.gz) tar xzf $1 ;; *.bz2) bunzip2 $1 ;;
        *.rar) unrar e "$1" ;; *.gz) gunzip $1 ;; *.tar) tar xf $1 ;;
        *.tbz2) tar xjf "$1" ;; *.tgz) tar xzf $1 ;; *.zip) unzip $1 ;;
        *.Z) uncompress "$1" ;; *.7z) 7z x $1 ;; *) echo "'$1' invalide" ;;
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

if [ "$USER" = "root" ]; then
    PS1='${debian_chroot:+($debian_chroot)}\[\033[01;31m\]\u@\h\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]# '
    export PS1
fi
alias gdiff='git diff --no-index'
convert_video_to_gif(){ echo "--- CONVERSION VIDEO VERS GIF (MODE INTERACTIF) ---"; echo ""; read -rp "Chemin video: " input_path; input_path="${input_path//\"/}"; read -rp "FPS (ex: 15, 24, 30): " fps; read -rp "Largeur (ex: 1920, 1280, 960): " width; read -rp "Flag (lanczos, bilinear, bicubic, spline): " flag; read -rp "GIF output: " gif_out; [ ! -f "$input_path" ] && echo "Erreur: Fichier introuvable" && return 1; ! command -v ffmpeg &>/dev/null && echo "Erreur: FFmpeg non trouvé dans PATH" && return 1; [[ "$gif_out" != *.gif ]] && gif_out="${gif_out}.gif"; parent_path="$(dirname "$input_path")"; [ -z "$parent_path" ] && parent_path="$(pwd)"; palette_path="${parent_path}/palette.png"; clean_path="/tmp/input_clean_$$.mp4"; ffmpeg_major=$(ffmpeg -version 2>&1 | grep -oP 'ffmpeg version \K[0-9]+' | head -1); [ "$ffmpeg_major" -ge 5 ] && vsync_flag="-fps_mode vfr" || vsync_flag="-vsync vfr"; vf_palette="fps=${fps},scale=${width}:-1:flags=${flag},palettegen=stats_mode=diff"; vf_gif="[0:v]setpts=PTS-STARTPTS,fps=${fps},scale=${width}:-1:flags=${flag}[x];[x][1:v]paletteuse=dither=bayer:bayer_scale=5:diff_mode=rectangle"; echo ""; echo "VERIFICATION timestamps..."; frame_count=$(ffprobe -v quiet -show_entries frame=pkt_pts_time -select_streams v:0 -of csv=p=0 "$input_path" 2>&1 | grep -c '.'); if [ "$frame_count" -lt 10 ]; then echo "PTS manquants ou format problematique -> re-encode intermediaire..."; ffmpeg -fflags +genpts+discardcorrupt -err_detect ignore_err -hide_banner -loglevel warning -stats -y -i "$input_path" -c:v libx264 -preset ultrafast -crf 18 "$clean_path"; if [ $? -ne 0 ]; then echo "Erreur: re-encode echoue"; return 1; fi; input_path="$clean_path"; echo "Re-encode OK -> utilisation de $clean_path"; else echo "Timestamps OK -> conversion directe"; fi; echo ""; echo "ETAPE 1 : palette"; ffmpeg -fflags +genpts+discardcorrupt -err_detect ignore_err -hide_banner -loglevel info -stats -y -i "$input_path" -vf "$vf_palette" -update 1 -frames:v 1 "$palette_path"; [ $? -ne 0 ] && echo "Erreur: Palette erreur" && rm -f "$clean_path" && return 1; echo ""; echo "ETAPE 2 : GIF"; ffmpeg -fflags +genpts+discardcorrupt -err_detect ignore_err -hide_banner -loglevel info -stats -y -i "$input_path" -i "$palette_path" -filter_complex "$vf_gif" $vsync_flag "$gif_out"; [ $? -ne 0 ] && echo "Erreur: GIF erreur" && rm -f "$palette_path" "$clean_path" && return 1; rm -f "$palette_path" "$clean_path"; echo ""; echo "OK -> $gif_out"; }
