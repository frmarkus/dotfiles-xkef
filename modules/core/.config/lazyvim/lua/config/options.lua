-- Over SSH, yanks reach the host clipboard through OSC 52. WezTerm ignores
-- OSC 52 reads, so a put returns the last yank instead of waiting 10 seconds
-- for a reply. Cmd-V pastes from the host.
if vim.env.SSH_TTY then
  local osc52 = require("vim.ui.clipboard.osc52")
  local last = { {}, "v" }
  local function copy(reg)
    local send = osc52.copy(reg)
    return function(lines, regtype)
      last = { lines, regtype }
      send(lines)
    end
  end
  local function paste()
    return last
  end
  vim.g.clipboard = {
    name = "OSC 52",
    copy = { ["+"] = copy("+"), ["*"] = copy("*") },
    paste = { ["+"] = paste, ["*"] = paste },
  }
  vim.opt.clipboard = "unnamedplus"
end

vim.opt.wrap = true
vim.opt.listchars = {
  tab = "→ ",
  trail = "·",
  nbsp = "␣",
  extends = "»",
  precedes = "«",
  lead = "·",
}

-- A project's .nvim.lua carries settings that belong to it alone, such as a
-- formatter's config path. nvim asks once before trusting a new file.
vim.opt.exrc = true
