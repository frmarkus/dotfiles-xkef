-- File operations in an editable buffer of the current directory, next to
-- the neo-tree tree view.
return {
  {
    "stevearc/oil.nvim",
    cmd = "Oil",
    opts = {
      default_file_explorer = false,
      view_options = {
        show_hidden = true,
        is_always_hidden = function(name)
          return name == ".." or name == ".git" or name == ".jj" or name == ".DS_Store"
        end,
      },
    },
    keys = {
      { "-", "<cmd>Oil<cr>", desc = "Open parent directory (oil)" },
    },
  },
}
