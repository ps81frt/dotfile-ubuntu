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
colorscheme desert
set cursorline
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
