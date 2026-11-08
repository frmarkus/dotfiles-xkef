-- JetBrains' kotlin-lsp, built on IntelliJ, in place of the Kotlin extra's
-- community fwcd server, which fails to parse current Java versions.
-- kotlin-lsp imports Gradle and Maven builds, such as a Spring Boot
-- project's. Mason installs it on macOS. The AUR installs it on Arch,
-- since Mason's linux_arm64 entry is broken.
local cmd = vim.fn.executable("intellij-server") == 1 and "intellij-server" or "kotlin-lsp"

local MAVEN_CENTRAL = "https://repo1.maven.org/maven2"
local SOURCES_DIR = vim.fn.stdpath("cache") .. "/sources"
local DECL_KEYWORDS = { "class", "interface", "enum", "record" }

-- These calls block the editor, so a stalled download or mise gives up
-- instead of hanging it. vim.system's wait() kills the process and returns
-- code 124 on timeout.
local DOWNLOAD_TIMEOUT_MS = 15000
local LOCAL_TIMEOUT_MS = 5000

-- Finds the sources jar of a jar in the Gradle cache, laid out as
-- files-2.1/<group>/<artifact>/<version>/<sha1>/<artifact>-<version>.jar.
-- Gradle downloads sources for some libraries only, so a missing one
-- comes from Maven Central, as IntelliJ's "Download Sources" does.
local function sources_jar(jar)
  local root, group, artifact, version = jar:match("^(.*/files%-2%.1/([^/]+)/([^/]+)/([^/]+))/[^/]+/[^/]+%.jar$")
  if not root then
    return nil
  end

  local name = ("%s-%s-sources.jar"):format(artifact, version)
  local cached = vim.fn.glob(root .. "/*/" .. name, false, true)[1]
  if cached then
    return cached
  end

  local path = ("%s/%s/%s"):format(SOURCES_DIR, group, name)
  if vim.uv.fs_stat(path) then
    return path
  end

  vim.fn.mkdir(vim.fs.dirname(path), "p")
  local url = ("%s/%s/%s/%s/%s"):format(MAVEN_CENTRAL, (group:gsub("%.", "/")), artifact, version, name)
  if vim.system({ "curl", "-fsSL", "-o", path, url }):wait(DOWNLOAD_TIMEOUT_MS).code ~= 0 then
    os.remove(path)
    return nil
  end
  return path
end

-- Finds a JDK's lib/src.zip. kotlin-lsp falls back to its bundled
-- JetBrains Runtime, which has none, so try $JAVA_HOME and mise's JDK next.
local function jdk_src_zip(home)
  for _, h in ipairs({ home, vim.env.JAVA_HOME }) do
    if h and vim.uv.fs_stat(h .. "/lib/src.zip") then
      return h .. "/lib/src.zip"
    end
  end

  local mise = vim.system({ "mise", "where", "java" }):wait(LOCAL_TIMEOUT_MS)
  local zip = vim.trim(mise.stdout or "") .. "/lib/src.zip"
  return mise.code == 0 and vim.uv.fs_stat(zip) and zip or nil
end

-- Reads the Java source of a class file URI from its sources jar or, for a
-- JDK class, from the JDK's lib/src.zip, which holds <module>/<path>.java:
--   jar:///…/spring-core-7.0.9.jar!/org/…/Foo$Bar.class
--   jrt://<jdk home>!/java.base/java/util/ArrayList.class
local function read_source(uri)
  local src, class
  local jar, jar_class = uri:match("^jar://(.-%.jar)!/(.+)%.class$")
  local home, jrt_class = uri:match("^jrt://(.-)!/(.+)%.class$")
  if jar then
    src, class = sources_jar(jar), jar_class
  elseif home then
    src, class = jdk_src_zip(home), jrt_class
  end
  if not src then
    return nil
  end

  local res = vim.system({ "unzip", "-p", src, class:gsub("%$.*", "") .. ".java" }):wait(LOCAL_TIMEOUT_MS)
  return res.code == 0 and res.stdout or nil
end

-- Returns the name a decompiled stub line declares and, for a type, its
-- keyword. "public void setUseCaches(boolean useCaches) {" declares
-- setUseCaches.
local function declared(line)
  for _, kw in ipairs(DECL_KEYWORDS) do
    local name = line:match("%f[%w]" .. kw .. "%s+([%w_]+)")
    if name then
      return name, kw
    end
  end
  return line:match("([%w_]+)%s*%(") or line:match("([%w_]+)%s*[;=]")
end

-- Finds the line that declares name in real source. A declaration follows
-- a type or modifier, where a call follows ".", "(", "new", or "return".
local function find_decl(lines, name, kw)
  for i, line in ipairs(lines) do
    local code = vim.trim(line)
    if not code:match("^[/*]") then
      if kw and code:match("%f[%w]" .. kw .. "%s+" .. name .. "%f[^%w_]") then
        return i
      end

      local pre = not kw and line:match("^(.-)%f[%w_]" .. name .. "%s*[(;={]")
      if pre and pre:match("[%w_>%]]%s+$") and not pre:match("%f[%w]new%s+$") and not pre:match("return%s+$") then
        return i
      end
    end
  end
end

-- The server's definition line points into the decompiled stub. After the
-- jump into a real window, move the cursor to the same declaration in the
-- real source.
local function remap_cursor(buf, stub)
  vim.api.nvim_create_autocmd("BufWinEnter", {
    buffer = buf,
    callback = function()
      local win = vim.api.nvim_get_current_win()
      if vim.api.nvim_win_get_config(win).relative ~= "" then
        return
      end

      vim.schedule(function()
        local name, kw = declared(stub[vim.api.nvim_win_get_cursor(win)[1]] or "")
        local row = name and find_decl(vim.api.nvim_buf_get_lines(buf, 0, -1, false), name, kw)
        if row then
          vim.api.nvim_win_set_cursor(win, { row, 0 })
        end
      end)
      return true
    end,
  })
end

-- A definition in a library, such as Spring, comes back as a jar: or jrt:
-- URI that Neovim can't read. kotlin-lsp's decompile command returns the
-- file's text: the commented source when the import attached the
-- library's sources jar, decompiled code otherwise. For decompiled code,
-- read_source looks up the sources jar itself. Treesitter highlights the
-- buffer without a filetype, so jdtls doesn't attach to it.
vim.api.nvim_create_autocmd("BufReadCmd", {
  group = vim.api.nvim_create_augroup("kotlin_lsp_decompile", { clear = true }),
  pattern = { "jar:/*", "jrt:/*" },
  callback = function(args)
    local client = vim.lsp.get_clients({ name = "kotlin_lsp" })[1]
    if not client then
      return
    end

    local uri = vim.api.nvim_buf_get_name(args.buf)
    local res =
      client:request_sync("workspace/executeCommand", { command = "decompile", arguments = { uri } }, 10000, args.buf)
    if not (res and res.result) then
      vim.notify("kotlin-lsp can't decompile " .. uri, vim.log.levels.ERROR)
      return
    end

    local code = res.result.code
    local lang = res.result.language
    local source = read_source(uri)
    if source then
      remap_cursor(args.buf, vim.split(code, "\n", { plain = true }))
      code, lang = source, "java"
    end

    local bo = vim.bo[args.buf]
    bo.buftype = "nofile"
    vim.api.nvim_buf_set_lines(args.buf, 0, -1, false, vim.split(code, "\n", { plain = true }))
    bo.modifiable = false
    pcall(vim.treesitter.start, args.buf, lang)
    vim.lsp.buf_attach_client(args.buf, client.id)
  end,
})

return {
  {
    "neovim/nvim-lspconfig",
    opts = {
      servers = {
        kotlin_language_server = { enabled = false },
        kotlin_lsp = {
          mason = vim.fn.has("mac") == 1,
          cmd = { cmd, "--stdio" },
        },
      },
    },
  },
}
