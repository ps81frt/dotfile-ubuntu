#!/bin/bash
echo "Installation dotfiles..."
DIR=$(cd "$(dirname "$0")" && pwd)
# backup si fichier existant avant symlink
bak() { [ -e "$1" ] && [ ! -L "$1" ] && mv "$1" "$1.bak"; }
# bash home
bak ~/.bashrc            && ln -sf $DIR/bash/.bashrc ~/.bashrc
bak ~/.bash_aliases      && ln -sf $DIR/bash/.bash_aliases ~/.bash_aliases
bak ~/.bash_profile      && ln -sf $DIR/bash/.bash_profile ~/.bash_profile
bak ~/.zshrc             && ln -sf $DIR/bash/.zshrc ~/.zshrc
bak ~/.wezterm.lua       && ln -sf $DIR/bash/.wezterm.lua ~/.wezterm.lua
# git
bak ~/.gitconfig         && ln -sf $DIR/git/.gitconfig ~/.gitconfig
bak ~/.gitignore_global  && ln -sf $DIR/git/.gitignore_global ~/.gitignore_global
# tout ~/.config d'un coup
bak ~/.config && ln -sf $DIR/config ~/.config
echo "Termine"
