-- Builds the Tree-sitter parsers that LazyVim lists, for the image. The VM
-- throws its disk away, so parsers that LazyVim builds at runtime would
-- build again in every session.
--
-- LazyVim starts its own install when Neovim starts, and the two race on
-- the same build folders. An install skips the parsers already there, so
-- a few rounds leave none missing.
local plugin = require("lazy.core.config").plugins["nvim-treesitter"]
local wanted = require("lazy.core.plugin").values(plugin, "opts", false).ensure_installed or {}
local treesitter = require("nvim-treesitter")
local rounds = 3

for _ = 1, rounds do
  local installed = treesitter.get_installed()
  local missing = vim.tbl_filter(function(lang)
    return not vim.list_contains(installed, lang)
  end, wanted)
  if #missing == 0 then
    break
  end
  treesitter.install(missing):wait(600000)
end
