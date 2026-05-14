sudo rm -f /usr/local/bin/install-lsp-servers
sudo tee /usr/local/bin/install-lsp-servers << 'EOF'
#!/bin/bash
echo "=== Installation des serveurs LSP ==="
sudo apt install -y lua5.4
npm install -g lua-language-server

# Python LSP servers with pipx (recommandé par Ubuntu)
if ! command -v pipx &> /dev/null; then
    apt install -y pipx
    pipx ensurepath
fi

pipx install python-lsp-server
pipx install pylsp-mypy
pipx install pylsp-black

# Node.js LSP servers
npm install -g typescript typescript-language-server
npm install -g vscode-langservers-extracted
npm install -g bash-language-server
npm install -g yaml-language-server

# Lua LSP
apt install -y lua-language-server

echo "=== Done ! ==="
EOF
sudo chmod +x /usr/local/bin/install-lsp-servers
sudo install-lsp-servers
