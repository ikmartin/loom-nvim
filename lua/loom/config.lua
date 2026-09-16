-- The plugin's settings and their defaults. The opener is injected so a test can assert the URL without a browser appearing.

local M = {}

--- @class LoomConfig
--- @field loom string
--- @field server string
--- @field serve_url string
--- @field autostart boolean
--- @field which_key boolean
--- @field serve "auto"|"tmux"|"terminal"
--- @field opener fun(url: string)
local defaults = {
  loom = "loom",
  server = "loom-lsp",
  serve_url = "http://127.0.0.1:8000",
  serve = "auto",
  autostart = true,
  which_key = true,
  opener = function(url)
    vim.ui.open(url)
  end,
}

local current = vim.deepcopy(defaults)

--- @param opts table|nil
function M.setup(opts)
  current = vim.tbl_deep_extend("force", vim.deepcopy(defaults), opts or {})
  return current
end

--- @return LoomConfig
function M.get()
  return current
end

function M.defaults()
  return vim.deepcopy(defaults)
end

return M
