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
set background=dark
colorscheme desert
set cursorline
set showmatch
set hlsearch
set incsearch
set ignorecase
set smartcase

" Mapping pratiques
nnoremap <space> :
nnoremap <C-s> :w<CR>
inoremap <C-s> <Esc>:w<CR>
nnoremap <C-q> :q!<CR>
