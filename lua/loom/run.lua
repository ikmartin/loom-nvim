-- Running loom. Every call builds an argument vector and hands it to the job; nothing here shells out through a string, so a title with a space or a quote is safe.

local M = {}

--- The argument vector for a loom call in `root`.
--- @param loom string the loom binary
--- @param root string the quilt root
--- @param args string[] the subcommand and its arguments
--- @return string[]
function M.argv(loom, root, args)
  local out = { loom }
  vim.list_extend(out, args)
  vim.list_extend(out, { "--quilt", root })
  return out
end

--- Run loom and call `on_done(code, stdout, stderr)`. Synchronous when `opts.sync` is set, which is what the tests use.
--- @param argv string[]
--- @param on_done fun(code: integer, out: string, err: string)
--- @param opts table|nil
function M.run(argv, on_done, opts)
  opts = opts or {}
  if opts.sync then
    local out = vim.fn.system(argv)
    on_done(vim.v.shell_error, out, "")
    return
  end
  local chunks, errs = {}, {}
  vim.fn.jobstart(argv, {
    stdout_buffered = true,
    stderr_buffered = true,
    on_stdout = function(_, data)
      if data then
        vim.list_extend(chunks, data)
      end
    end,
    on_stderr = function(_, data)
      if data then
        vim.list_extend(errs, data)
      end
    end,
    on_exit = function(_, code)
      on_done(code, table.concat(chunks, "\n"), table.concat(errs, "\n"))
    end,
  })
end

--- Show text in a scratch buffer in a split, named `title`.
--- @param title string
--- @param lines string[]
--- @param filetype string|nil
function M.scratch(title, lines, filetype)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"
  if filetype then
    vim.bo[buf].filetype = filetype
  end
  vim.api.nvim_buf_set_name(buf, title)
  vim.cmd("botright split")
  vim.api.nvim_win_set_buf(0, buf)
  return buf
end

return M
