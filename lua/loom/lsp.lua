-- Registering loom-lsp. Neovim 0.12 has vim.lsp.config and vim.lsp.enable; older versions go through nvim-lspconfig.
-- The server attaches only inside a quilt, so vimtex keeps every ordinary .tex buffer to itself and nothing here competes with it.

local quilt = require("loom.quilt")

local M = {}

M.NAME = "loom_lsp"

--- The client configuration, built from the plugin's settings.
--- `root_dir` follows Neovim 0.12's contract: it is handed a callback and calls it only when the buffer is inside a quilt, so the client never starts anywhere else and vimtex keeps every ordinary .tex buffer to itself. Returning a directory instead of calling the callback starts nothing and logs nothing, which is a quiet way to lose an afternoon.
--- @param cfg table
--- @return table
function M.client_config(cfg)
  return {
    cmd = { cfg.server },
    filetypes = { "tex", "plaintex" },
    root_dir = function(bufnr, on_dir)
      local root = quilt.root_of_buf(bufnr)
      if root then
        on_dir(root)
      end
    end,
    init_options = { loomPath = cfg.loom },
    settings = {},
  }
end

--- Register and enable the server. Returns the mechanism used, for the record and for the tests.
--- @param cfg table
--- @return string
function M.register(cfg)
  local conf = M.client_config(cfg)
  if vim.lsp.config and vim.lsp.enable then
    vim.lsp.config[M.NAME] = conf
    vim.lsp.enable(M.NAME)
    return "vim.lsp.config"
  end
  local ok, lspconfig = pcall(require, "lspconfig")
  if not ok then
    return "none"
  end
  local configs = require("lspconfig.configs")
  if not configs[M.NAME] then
    configs[M.NAME] = {
      default_config = {
        cmd = conf.cmd,
        filetypes = conf.filetypes,
        root_dir = function(fname)
          return quilt.root(fname)
        end,
        init_options = conf.init_options,
      },
    }
  end
  lspconfig[M.NAME].setup({})
  return "lspconfig"
end

--- The loom client attached to a buffer, or nil.
--- @param bufnr integer|nil
function M.client(bufnr)
  for _, c in ipairs(vim.lsp.get_clients({ bufnr = bufnr or 0, name = M.NAME })) do
    return c
  end
  return nil
end

return M
