vim.g.mapleader = " "
vim.g.maplocalleader = "\\"

-- The python extra reads this when lazy.setup() imports its spec, so it must
-- come first. LazyVim defaults to pyright. basedpyright is the maintained fork
-- and reports the stricter diagnostics these projects type for.
vim.g.lazyvim_python_lsp = "basedpyright"

-- TypeScript 7 drops the tsserver that vtsls drives. Its native compiler,
-- tsc, serves LSP itself, from the project's node_modules or from Mason.
vim.g.lazyvim_ts_lsp = "tsc"

-- Debug helpers from folke/dot: dd(value) inspects, bt() prints a backtrace.
_G.dd = function(...)
  Snacks.debug.inspect(...)
end
_G.bt = function()
  Snacks.debug.backtrace()
end
vim.print = _G.dd

local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not vim.uv.fs_stat(lazypath) then
  vim.fn.system({
    "git",
    "clone",
    "--filter=blob:none",
    "https://github.com/folke/lazy.nvim.git",
    "--branch=stable",
    lazypath,
  })
end
vim.opt.rtp:prepend(lazypath)

require("lazy").setup({
  spec = {
    {
      "LazyVim/LazyVim",
      import = "lazyvim.plugins",
      opts = {
        colorscheme = require("theme").apply,
      },
    },
    { import = "plugins" },
  },
})
