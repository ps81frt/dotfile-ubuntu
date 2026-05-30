#!/bin/bash

mkdir -p "${HOME}/Images/wallpapers"
mkdir -p "${HOME}/.config/fastfetch"

cp raccoon-fastfetch.png "${HOME}/Images/wallpapers/"
cp config.jsonc "${HOME}/.config/fastfetch/"

if command -v fastfetch &> /dev/null; then
    fastfetch
else
    echo "Installation terminee ! Veuillez installer fastfetch pour voir le resultat."
fi
