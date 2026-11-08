return {
  {
    "JavaHello/spring-boot.nvim",
    ft = { "java", "jproperties" },
    dependencies = { "mfussenegger/nvim-jdtls" },
    init = function()
      vim.api.nvim_create_autocmd({ "BufReadPost", "BufNewFile" }, {
        pattern = { "**/application*.yml", "**/application*.yaml" },
        callback = function(args)
          local root = vim.fs.root(args.buf, { "pom.xml", "build.gradle", "build.gradle.kts" })
          if root then
            require("lazy").load({ plugins = { "spring-boot.nvim" } })
            return true
          end
        end,
      })
    end,
    config = function()
      local ls_jar = vim.fn.glob(
        "$MASON/packages/vscode-spring-boot-tools/extension/language-server/spring-boot-language-server-*.jar"
      )
      if ls_jar == "" then
        vim.notify("spring-boot-tools not installed, run :MasonInstall spring-boot-tools", vim.log.levels.WARN)
        return
      end
      require("spring_boot").setup({ ls_path = ls_jar, exploded_ls_jar_data = false })
    end,
  },

  {
    "mason-org/mason.nvim",
    opts = { ensure_installed = { "google-java-format", "vscode-spring-boot-tools", "vscode-java-dependency" } },
  },

  -- Java Projects view: modules, packages, and dependencies as jdtls sees
  -- them, through the vscode-java-dependency bundle below.
  {
    "JavaHello/java-deps.nvim",
    ft = "java",
    dependencies = { "mfussenegger/nvim-jdtls" },
    keys = {
      {
        "<leader>cj",
        function()
          require("java-deps").toggle_outline()
        end,
        ft = "java",
        desc = "Java Projects",
      },
    },
    opts = {},
  },

  {
    "stevearc/conform.nvim",
    opts = { formatters_by_ft = { java = { "google-java-format" } } },
  },

  {
    "mfussenegger/nvim-jdtls",
    opts = function(_, opts)
      -- jdtls reads this flag only as a JVM system property, not from LSP
      -- settings. It keeps .project and .classpath out of the project root.
      table.insert(opts.cmd, "--jvm-arg=-Djava.import.generatesMetadataFilesAtProjectRoot=false")

      opts.jdtls = function(config)
        local ok, spring_boot = pcall(require, "spring_boot")
        if ok then
          vim.list_extend(config.init_options.bundles, spring_boot.java_extensions())
        end
        vim.list_extend(
          config.init_options.bundles,
          vim.fn.glob("$MASON/share/vscode-java-dependency/com.microsoft.jdtls.ext.core-*.jar", false, true)
        )
        return config
      end

      -- jdtls organizes imports in its reply to willSaveWaitUntil, which
      -- Neovim sends before each write.
      opts.settings = vim.tbl_deep_extend("force", opts.settings or {}, {
        java = {
          saveActions = { organizeImports = true },
          signatureHelp = { enabled = true },
          contentProvider = { preferred = "fernflower" },
          completion = {
            favoriteStaticMembers = {
              "org.junit.Assert.*",
              "org.junit.jupiter.api.Assertions.*",
              "org.mockito.Mockito.*",
              "java.util.Objects.requireNonNull",
              "java.util.Objects.requireNonNullElse",
            },
          },
          sources = {
            organizeImports = {
              starThreshold = 9999,
              staticStarThreshold = 9999,
            },
          },
        },
      })

      opts.on_attach = function(args)
        local bufnr = args.buf
        local client = vim.lsp.get_client_by_id(args.data.client_id)
        local root_dir = client and client.config.root_dir

        if root_dir then
          vim.api.nvim_set_current_dir(root_dir)

          local mvn = vim.fn.executable("mvnd") == 1 and "mvnd" or "mvn"
          local m = function(keys, func, desc)
            vim.keymap.set("n", keys, func, { buffer = bufnr, desc = desc })
          end
          m("<leader>cB", function()
            vim.cmd(
              "split | terminal cd "
                .. vim.fn.fnameescape(root_dir)
                .. " && "
                .. mvn
                .. " clean package -DskipTests -q && exec java -jar target/*.jar"
            )
            vim.cmd.startinsert()
          end, "Run Spring Boot")
          m("<leader>cD", function()
            require("dap").continue()
          end, "Debug Spring Boot")
        end
      end
    end,
  },
}
