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

-- Commands whose argument names a key, and commands whose argument names a file of the quilt.
M.KEY_COMMANDS = { "label", "ref", "eqref", "cref", "Cref", "autoref", "pageref", "vref", "Vref", "uses" }
M.INCLUDE_COMMANDS = { "input", "include", "nest" }

--- Every `\name*[opt]{arg}` in `line`: name, argument, and the 1-based columns of the backslash and the closing brace.
local function commands_in(line)
  local out = {}
  local pos = 1
  while true do
    local s, e, name = line:find("\\(%a+)", pos)
    if not s then
      break
    end
    local i = e + 1
    i = line:match("^%*?%s*()", i)
    if line:sub(i, i) == "[" then
      local close = line:find("]", i, true)
      i = close and line:match("^%s*()", close + 1) or i
    end
    if line:sub(i, i) == "{" then
      local close = line:find("}", i, true)
      if close then
        table.insert(out, { name = name, arg = line:sub(i + 1, close - 1), first = s, last = close })
        pos = close + 1
      else
        pos = i + 1
      end
    else
      pos = e + 1
    end
  end
  return out
end

--- The id of the first node in the quilt file an `\input{path}` names: the first `\label` in it.
local function key_of_file(root, path)
  for _, candidate in ipairs({ path, path .. ".tex" }) do
    local full = root .. "/" .. candidate
    if vim.fn.filereadable(full) == 1 then
      for _, line in ipairs(vim.fn.readfile(full)) do
        local label = line:match("\\label{([^}]+)}")
        if label then
          return vim.trim(label)
        end
      end
      return nil
    end
  end
  return nil
end

--- The loom id under or nearest before the cursor.
--- On a `\label`, `\ref`, `\uses` or similar, the first key it names; on an `\input`, `\include` or `\nest`, the first node of the file it names; anywhere else, the last `\label` above the cursor. Other commands' arguments (`\emph{...}`, `\section{...}`) are never taken for keys.
--- @param bufnr integer|nil
--- @return string|nil
function M.key_at_cursor(bufnr)
  bufnr = bufnr or 0
  local row, col = unpack(vim.api.nvim_win_get_cursor(0))
  local line = vim.api.nvim_buf_get_lines(bufnr, row - 1, row, false)[1] or ""
  for _, c in ipairs(commands_in(line)) do
    if col + 1 >= c.first and col + 1 <= c.last then
      local first = vim.trim(vim.split(c.arg, ",")[1] or "")
      if first ~= "" and vim.tbl_contains(M.KEY_COMMANDS, c.name) then
        return first
      end
      if first ~= "" and vim.tbl_contains(M.INCLUDE_COMMANDS, c.name) then
        local root = M.root_of_buf(bufnr)
        local key = root and key_of_file(root, first)
        if key then
          return key
        end
      end
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
