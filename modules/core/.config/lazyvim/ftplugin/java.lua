-- Java always uses 2-space indent (Google style)
vim.opt_local.shiftwidth = 2
vim.opt_local.tabstop = 2
vim.opt_local.makeprg = (vim.fn.executable("mvnd") == 1 and "mvnd" or "mvn") .. " clean compile"
vim.opt_local.errorformat = "[ERROR] %f:[%l\\,%c] %m"

local IMPORT_FOLD_LEVEL = 20

_G._kk = _G._kk or {}
_G._kk.java_foldexpr = function()
  local lnum = vim.v.lnum
  local line = vim.fn.getline(lnum)
  if line:match("^import ") then
    local prev = lnum > 1 and vim.fn.getline(lnum - 1) or ""
    return prev:match("^import ") and tostring(IMPORT_FOLD_LEVEL) or ">" .. IMPORT_FOLD_LEVEL
  end
  if lnum > 1 and vim.fn.getline(lnum - 1):match("^import ") then
    return "0"
  end
  local next_line = vim.fn.getline(lnum + 1)
  if next_line and next_line:match("^import ") then
    return "0"
  end
  local ok, result = pcall(vim.treesitter.foldexpr)
  return ok and result or "0"
end
vim.opt_local.foldexpr = "v:lua._kk.java_foldexpr()"

-- The ftplugin reruns on each :edit or filetype set, so a per-buffer group
-- keeps one autocmd per buffer.
local buf = vim.api.nvim_get_current_buf()
vim.api.nvim_create_autocmd("BufWinEnter", {
  group = vim.api.nvim_create_augroup("java_import_fold_" .. buf, { clear = true }),
  buffer = buf,
  callback = function()
    if vim.wo.foldlevel >= IMPORT_FOLD_LEVEL then
      vim.wo.foldlevel = IMPORT_FOLD_LEVEL - 1
    end
  end,
})
