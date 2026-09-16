-- Finding the quilt a buffer belongs to, and the keys inside it.
-- The plugin starts nothing outside a quilt, so an ordinary .tex file is untouched and vimtex keeps the buffer to itself.

local M = {}

--- The quilt root at or above `path`: the nearest directory with a config.toml holding a [quilt] table.
--- @param path string
--- @return string|nil
function M.root(path)
  local dir = vim.fn.isdirectory(path) == 1 and path or vim.fs.dirname(path)
  if not dir or dir == "" then
    return nil
  end
  for _, found in ipairs(vim.fs.find("config.toml", { path = dir, upward = true, limit = math.huge })) do
    local ok, lines = pcall(vim.fn.readfile, found)
    if ok then
      for _, line in ipairs(lines) do
        if line:match("^%s*%[quilt%]") then
          return vim.fs.dirname(found)
        end
      end
    end
  end
  return nil
end

--- The quilt root of a buffer, or nil.
--- @param bufnr integer|nil
--- @return string|nil
function M.root_of_buf(bufnr)
  local name = vim.api.nvim_buf_get_name(bufnr or 0)
  if name == "" then
    return M.root(vim.fn.getcwd())
  end
  return M.root(name)
end

--- The loom id under or nearest before the cursor: the argument of the enclosing `\label{...}`, `\ref{...}` or `\uses{...}`, else the last label above the cursor.
--- @param bufnr integer|nil
--- @return string|nil
function M.key_at_cursor(bufnr)
  bufnr = bufnr or 0
  local row, col = unpack(vim.api.nvim_win_get_cursor(0))
  local line = vim.api.nvim_buf_get_lines(bufnr, row - 1, row, false)[1] or ""
  for s, arg in line:gmatch("()\\%a+%*?{([^}]*)}") do
    local e = s + #arg
    if col + 1 >= s and col <= e + 4 then
      local first = vim.split(arg, ",")[1]
      return (first:gsub("^%s+", ""):gsub("%s+$", ""))
    end
  end
  local above = vim.api.nvim_buf_get_lines(bufnr, 0, row, false)
  for i = #above, 1, -1 do
    local label = above[i]:match("\\label{([^}]+)}")
    if label then
      return label
    end
  end
  return nil
end

--- The path of the current buffer relative to the quilt root, or nil.
--- @param bufnr integer|nil
--- @return string|nil
function M.relative(bufnr)
  local root = M.root_of_buf(bufnr)
  local name = vim.api.nvim_buf_get_name(bufnr or 0)
  if not root or name == "" then
    return nil
  end
  local rel = name:sub(#root + 2)
  return rel ~= name and rel or nil
end

return M
