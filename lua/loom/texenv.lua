-- TeX's search path while a quilt file is current. A quilt's masters sit in its drafting folder (`drafting/` by default) but name everything relative to the quilt root, and vimtex runs latexmk in the master's own folder, so the root is put on TEXINPUTS and BIBINPUTS for the processes Neovim starts.
-- Nothing is written to the quilt: the variables live in this Neovim process only, and leaving the quilt for another file restores them.

local quilt = require("loom.quilt")

local M = {}

local VARS = { "TEXINPUTS", "BIBINPUTS" }
local SEP = vim.fn.has("win32") == 1 and ";" or ":"

-- The values before this plugin touched them; false stands for unset.
local originals = nil

--- The value of a search variable with `root` first. An unset or empty original becomes `root:`, whose trailing separator keeps TeX's own trees.
--- @param root string
--- @param original string|nil
--- @return string
function M.with_root(root, original)
  if original == nil or original == "" then
    return root .. SEP
  end
  return root .. SEP .. original
end

local function remember()
  if originals then
    return
  end
  originals = {}
  for _, var in ipairs(VARS) do
    originals[var] = vim.env[var] or false
  end
end

--- Put `root` on the search variables, or restore the originals when `root` is nil.
--- @param root string|nil
function M.set(root)
  remember()
  for _, var in ipairs(VARS) do
    local original = originals[var] or nil
    vim.env[var] = root and M.with_root(root, original) or original
  end
end

--- Apply for buffer `bufnr`: the quilt's root for a file inside one, the originals for any other file, and no change for a buffer that is not a file (a terminal, the quickfix list, a scratch buffer).
--- @param bufnr integer|nil
function M.apply(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  if vim.bo[bufnr].buftype ~= "" or vim.api.nvim_buf_get_name(bufnr) == "" then
    return
  end
  M.set(quilt.root_of_buf(bufnr))
end

--- Follow the current buffer from now on, starting with the one already open.
function M.setup()
  remember()
  vim.api.nvim_create_autocmd("BufEnter", {
    group = vim.api.nvim_create_augroup("loom_texenv", { clear = true }),
    callback = function(args)
      M.apply(args.buf)
    end,
    desc = "Put the quilt root on TeX's search path while a quilt file is current",
  })
  M.apply()
end

--- Restore the originals and stop following buffers, for the tests.
function M._reset()
  pcall(vim.api.nvim_del_augroup_by_name, "loom_texenv")
  if originals then
    M.set(nil)
  end
  originals = nil
end

return M
