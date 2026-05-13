return {

  -- Theme TokyoNight night
  { "folke/tokyonight.nvim", opts = { style = "night" } },

  -- LSP moderne : ts_ls (remplace tsserver deprecie)
  {
    "neovim/nvim-lspconfig",
    opts = {
      servers = {
        pyright = {},
        ts_ls   = {},
        lua_ls  = {
          settings = {
            Lua = {
              workspace = { checkThirdParty = false },
              telemetry = { enable = false },
            },
          },
        },
        bashls = {},
        html   = {},
        cssls  = {},
        jsonls = {},
        yamlls = {},
      },
    },
  },

  -- Treesitter
  {
    "nvim-treesitter/nvim-treesitter",
    opts = {
      ensure_installed = {
        "lua", "python", "javascript", "typescript",
        "c", "cpp", "go", "rust", "bash",
        "html", "css", "json", "yaml", "toml",
        "markdown", "markdown_inline",
      },
    },
  },

  { "windwp/nvim-autopairs", event = "InsertEnter", opts = {} },
  { "folke/todo-comments.nvim", opts = { signs = true } },
  { "folke/zen-mode.nvim", cmd = "ZenMode" },
  { "kylechui/nvim-surround", event = "VeryLazy", opts = {} },

  -- Harpoon2
  {
    "ThePrimeagen/harpoon",
    branch       = "harpoon2",
    dependencies = { "nvim-lua/plenary.nvim" },
    keys = {
      { "<leader>ha", function() require("harpoon"):list():add() end,                                 desc = "Harpoon: ajouter"   },
      { "<C-e>",      function() local h=require("harpoon"); h.ui:toggle_quick_menu(h:list()) end,    desc = "Harpoon: menu"      },
      { "<leader>h1", function() require("harpoon"):list():select(1) end,                             desc = "Harpoon: fichier 1" },
      { "<leader>h2", function() require("harpoon"):list():select(2) end,                             desc = "Harpoon: fichier 2" },
      { "<leader>h3", function() require("harpoon"):list():select(3) end,                             desc = "Harpoon: fichier 3" },
      { "<leader>h4", function() require("harpoon"):list():select(4) end,                             desc = "Harpoon: fichier 4" },
    },
  },

  -- Gitsigns
  {
    "lewis6991/gitsigns.nvim",
    opts = {
      signs = {
        add          = { text = "+" },
        change       = { text = "~" },
        delete       = { text = "-" },
        topdelete    = { text = "-" },
        changedelete = { text = "~" },
      },
    },
  },
}
