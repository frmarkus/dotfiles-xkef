-- Options loaded after all plugins (after/plugin/ runs last).

vim.opt.number = true
vim.opt.relativenumber = true
vim.opt.list = true
vim.opt.listchars = {
  tab = "→ ",
  trail = "·",
  nbsp = "␣",
  extends = "»",
  precedes = "«",
  lead = "·",
}

vim.opt.signcolumn = "yes"
vim.opt.cursorline = true
vim.opt.scrolloff = 10
vim.opt.inccommand = "split"
vim.opt.ignorecase = true
vim.opt.smartcase = true
vim.opt.splitright = true
vim.opt.splitbelow = true
vim.opt.undofile = true

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
end
vim.opt.clipboard = "unnamedplus"
