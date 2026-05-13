local map = vim.keymap.set

-- Sauvegarde / Quitter
map("n", "<C-s>", "<cmd>w<CR>",      { desc = "Sauvegarder" })
map("i", "<C-s>", "<Esc><cmd>w<CR>", { desc = "Sauvegarder (insert)" })
map("n", "<C-q>", "<cmd>q<CR>",      { desc = "Quitter" })

-- Navigation splits — Ctrl+Fleches
map("n", "<C-Left>",  "<C-w>h", { desc = "Split gauche" })
map("n", "<C-Down>",  "<C-w>j", { desc = "Split bas" })
map("n", "<C-Up>",    "<C-w>k", { desc = "Split haut" })
map("n", "<C-Right>", "<C-w>l", { desc = "Split droite" })

-- Resize splits — Alt+Fleches
map("n", "<A-Left>",  "<C-w><", { desc = "Reduire largeur" })
map("n", "<A-Right>", "<C-w>>", { desc = "Augmenter largeur" })
map("n", "<A-Up>",    "<C-w>+", { desc = "Augmenter hauteur" })
map("n", "<A-Down>",  "<C-w>-", { desc = "Reduire hauteur" })

-- Buffers
map("n", "<Tab>",      "<cmd>bnext<CR>",     { desc = "Buffer suivant" })
map("n", "<S-Tab>",    "<cmd>bprevious<CR>", { desc = "Buffer precedent" })
map("n", "<leader>bd", "<cmd>bdelete<CR>",   { desc = "Fermer buffer" })

-- Deplacer lignes (visuel)
map("v", "<A-Down>", ":m '>+1<CR>gv=gv", { desc = "Ligne bas" })
map("v", "<A-Up>",   ":m '<-2<CR>gv=gv", { desc = "Ligne haut" })

-- Indentation
map("v", "<", "<gv", { desc = "Desindenter" })
map("v", ">", ">gv", { desc = "Indenter" })

-- Recherche centree
map("n", "n", "nzzzv")
map("n", "N", "Nzzzv")

-- Diagnostic
map("n", "[d", vim.diagnostic.goto_prev, { desc = "Diagnostic precedent" })
map("n", "]d", vim.diagnostic.goto_next, { desc = "Diagnostic suivant" })
