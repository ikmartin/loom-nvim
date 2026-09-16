-- loom-nvim: a Neovim client for loom.
-- It complements vimtex rather than replacing it: vimtex keeps the tex filetype, and this plugin attaches a second language client beside it and adds commands of its own, only inside a quilt.

local config = require("loom.config")
local commands = require("loom.commands")
local quilt = require("loom.quilt")

local M = {}

M.commands = commands
M.quilt = quilt

local COMMANDS = {
  { name = "LoomStatus", fn = commands.status, nargs = 0, desc = "The quilt's states" },
  { name = "LoomLint", fn = commands.lint, nargs = 0, desc = "Diagnostics into the quickfix list" },
  { name = "LoomNew", fn = commands.new, nargs = "+", desc = "Insert a node skeleton" },
  { name = "LoomAccept", fn = commands.accept, nargs = "?", desc = "Record an acceptance" },
  { name = "LoomServe", fn = commands.serve, nargs = 0, desc = "Start loom serve in a terminal" },
  { name = "LoomOpen", fn = commands.open, nargs = "?", desc = "Open the node in arras" },
  { name = "LoomBundle", fn = commands.bundle, nargs = "?", desc = "The standalone bundle for a key" },
  { name = "LoomDeps", fn = commands.deps, nargs = "?", desc = "What a key depends on" },
}

--- @param opts table|nil
function M.setup(opts)
  local cfg = config.setup(opts)

  for _, c in ipairs(COMMANDS) do
    vim.api.nvim_create_user_command(c.name, function(args)
      c.fn(args.args)
    end, { nargs = c.nargs, desc = c.desc })
  end

  if cfg.autostart then
    require("loom.lsp").register(cfg)
  end

  -- the language server's code actions name these commands; the editor carries them out (it owns the server "open" needs)
  vim.lsp.commands["loom.run"] = function(command)
    local args = command.arguments or {}
    if type(args[1]) == "table" then
      commands.run_action(args[1], type(args[2]) == "string" and args[2] or "")
    end
  end
  vim.lsp.commands["loom.open"] = function(command, ctx)
    local key = (command.arguments or {})[1]
    local root = quilt.root_of_buf(ctx and ctx.bufnr or 0)
    if type(key) == "string" and root then
      commands.open_key(root, key)
    end
  end

  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = vim.api.nvim_create_augroup("loom_serve", { clear = true }),
    callback = function()
      require("loom.serve").stop_all()
    end,
    desc = "Stop the loom serve processes this session started",
  })

  if cfg.which_key then
    local ok, wk = pcall(require, "which-key")
    if ok then
      wk.add({ { "<leader>l", group = "loom" } })
    end
  end

  return cfg
end

--- The state of the node under the cursor, for a statusline: `rl-0004 accepted`, or "" outside a quilt.
--- @return string
function M.statusline()
  if not quilt.root_of_buf(0) then
    return ""
  end
  local key = quilt.key_at_cursor(0)
  if not key then
    return ""
  end
  local diagnostics = vim.diagnostic.get(0, { namespace = nil })
  for _, d in ipairs(diagnostics) do
    if d.source == "loom" and d.severity == vim.diagnostic.severity.ERROR then
      return key .. " ✗"
    end
  end
  return key
end

return M
