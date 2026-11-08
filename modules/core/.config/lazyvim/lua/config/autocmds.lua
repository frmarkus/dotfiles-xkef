require("theme").setup()

-- Show markdown as plain highlighted text. LazyVim's global conceallevel
-- hides emphasis markers and link targets.
vim.api.nvim_create_autocmd("FileType", {
  group = vim.api.nvim_create_augroup("markdown_conceal", { clear = true }),
  pattern = { "markdown", "markdown.mdx" },
  callback = function()
    vim.opt_local.conceallevel = 0
  end,
})

-- Keep spell checking off in text filetypes. LazyVim's group also sets
-- wrap, which options.lua already sets everywhere. <leader>us toggles it.
vim.api.nvim_del_augroup_by_name("lazyvim_wrap_spell")
