-- The plugin's settings and their defaults. The opener is injected so a test can assert the URL without a browser appearing.

local M = {}

--- @class LoomConfig
--- @field loom string
--- @field server string
--- @field autostart boolean
--- @field which_key boolean
--- @field serve "auto"|"tmux"|"terminal"
--- @field tex_search_path boolean
--- @field opener fun(url: string)
local defaults = {
  loom = "loom",
  server = "loom-lsp",
  serve = "auto",
  tex_search_path = true,
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
