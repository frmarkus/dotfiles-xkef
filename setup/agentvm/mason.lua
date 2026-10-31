-- Installs every Mason package that LazyVim asks for, for the image: its
-- tools, the language servers it configures, and the debug adapters. The
-- VM throws its disk away, so packages that Mason installs at runtime
-- would download again in every session. LazyVim starts the same installs
-- when Neovim starts, and a package already installing gets waited for.
local timeout_ms = 900000

local function opts(name)
  local plugin = require("lazy.core.config").plugins[name]
  return plugin and require("lazy.core.plugin").values(plugin, "opts", false) or {}
end

require("lazy").load({ plugins = { "mason.nvim", "mason-lspconfig.nvim" } })
local registry = require("mason-registry")
local servers = require("mason-lspconfig").get_mappings().lspconfig_to_package

local wanted = {}
vim.list_extend(wanted, opts("mason.nvim").ensure_installed or {})
vim.list_extend(wanted, opts("mason-nvim-dap.nvim").ensure_installed or {})
for server, server_opts in pairs(opts("nvim-lspconfig").servers or {}) do
  local managed = type(server_opts) ~= "table" or server_opts.mason ~= false
  if server_opts and managed and servers[server] then
    table.insert(wanted, servers[server])
  end
end

local function installing()
  return vim.iter(registry.get_all_packages()):any(function(package)
    return package:is_installing()
  end)
end

-- refresh() calls back once the registry is current, which may come after
-- the first check of the wait below.
local failed = {}
local pending = 0
local refreshed = false
registry.refresh(function()
  refreshed = true
  for _, name in ipairs(vim.fn.uniq(vim.fn.sort(wanted))) do
    local ok, package = pcall(registry.get_package, name)
    if not ok then
      table.insert(failed, name .. " (unknown)")
    elseif not package:is_installed() and not package:is_installing() then
      pending = pending + 1
      package:install({}, function(success, err)
        if not success then
          table.insert(failed, ("%s (%s)"):format(name, tostring(err)))
        end
        pending = pending - 1
      end)
    end
  end
end)

vim.wait(timeout_ms, function()
  return refreshed and pending == 0 and not installing()
end, 1000)
print(("mason: %d wanted, failed: %s"):format(#wanted, #failed > 0 and table.concat(failed, "; ") or "none"))
