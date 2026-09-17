-- The commands. Each one builds an argument vector and either shows the output or, for the ones that write, confirms first.

local quilt = require("loom.quilt")
local run = require("loom.run")
local serve = require("loom.serve")

local M = {}

--- @class LoomCommandContext
--- @field root string
--- @field config table

--- The context a command needs, or nil with a message when the buffer is outside a quilt.
--- @return LoomCommandContext|nil
local function context()
  local cfg = require("loom.config").get()
  local root = quilt.root_of_buf(0)
  if not root then
    vim.notify("loom: this buffer is not inside a quilt", vim.log.levels.WARN)
    return nil
  end
  return { root = root, config = cfg }
end

--- The argument vector each command builds, exposed so the tests can assert it without running anything.
--- @param name string
--- @param root string
--- @param cfg table
--- @param arg string|nil
--- @return string[]|nil
function M.argv_for(name, root, cfg, arg)
  local A = function(...)
    return run.argv(cfg.loom, root, { ... })
  end
  if name == "status" then
    return A("status")
  elseif name == "lint" then
    return A("lint", "--json")
  elseif name == "new" then
    local taxon, title = (arg or ""):match("^(%S+)%s+(.+)$")
    if not taxon then
      return nil
    end
    return A("new", taxon, title, "--print")
  elseif name == "accept" then
    return A("accept", arg or "")
  elseif name == "serve" then
    return arg and A("serve", "--port", arg) or A("serve")
  elseif name == "bundle" then
    return A("bundle", arg or "")
  elseif name == "deps" then
    return A("deps", arg or "")
  end
  return nil
end

function M.status()
  local ctx = context()
  if not ctx then
    return
  end
  run.run(M.argv_for("status", ctx.root, ctx.config), function(_, out)
    vim.schedule(function()
      run.scratch("loom://status", vim.split(out, "\n"))
    end)
  end)
end

function M.lint()
  local ctx = context()
  if not ctx then
    return
  end
  run.run(M.argv_for("lint", ctx.root, ctx.config), function(_, out)
    vim.schedule(function()
      local ok, parsed = pcall(vim.json.decode, out)
      if not ok then
        vim.notify("loom lint: " .. out, vim.log.levels.ERROR)
        return
      end
      local items = {}
      for _, d in ipairs(parsed) do
        for _, loc in ipairs(d.locations or {}) do
          table.insert(items, {
            filename = ctx.root .. "/" .. loc.file,
            lnum = loc.line or 1,
            col = loc.column or 1,
            text = d.code .. ": " .. d.message,
            type = d.severity == "error" and "E" or (d.severity == "warning" and "W" or "I"),
          })
        end
      end
      vim.fn.setqflist({}, "r", { title = "loom lint", items = items })
      vim.cmd("copen")
      vim.notify(("loom lint: %d diagnostic(s)"):format(#items))
    end)
  end)
end

function M.new(arg)
  local ctx = context()
  if not ctx then
    return
  end
  local argv = M.argv_for("new", ctx.root, ctx.config, arg)
  if not argv then
    vim.notify("usage: :LoomNew {taxon} {title}", vim.log.levels.WARN)
    return
  end
  run.run(argv, function(code, out)
    vim.schedule(function()
      if code ~= 0 then
        vim.notify("loom new failed: " .. out, vim.log.levels.ERROR)
        return
      end
      local row = vim.api.nvim_win_get_cursor(0)[1]
      vim.api.nvim_buf_set_lines(0, row, row, false, vim.split(out:gsub("\n$", ""), "\n"))
    end)
  end)
end

function M.accept(arg)
  local ctx = context()
  if not ctx then
    return
  end
  local key = (arg ~= "" and arg) or quilt.key_at_cursor(0)
  if not key then
    vim.notify("loom: no key under the cursor", vim.log.levels.WARN)
    return
  end
  local choice = vim.fn.confirm(("Record an acceptance for %s?"):format(key), "&Yes\n&No", 2)
  if choice ~= 1 then
    return
  end
  run.run(M.argv_for("accept", ctx.root, ctx.config, key), function(code, out, err)
    vim.schedule(function()
      vim.notify(code == 0 and ("loom accept " .. key .. ": " .. out) or ("loom accept failed: " .. (err ~= "" and err or out)),
        code == 0 and vim.log.levels.INFO or vim.log.levels.ERROR)
    end)
  end)
end

--- Report where this session's server for `root` is, starting it when there is none, then call `then_` with its url.
local function with_server(root, cfg, then_)
  serve.ensure(root, cfg, function(port)
    return M.argv_for("serve", root, cfg, tostring(port))
  end, function(url, info)
    if info.started then
      vim.notify(("loom serve started in %s at %s"):format(info.where, url))
    end
    if then_ then
      then_(url, info)
    end
  end)
end

function M.serve()
  local ctx = context()
  if not ctx then
    return
  end
  with_server(ctx.root, ctx.config, function(url, info)
    if not info.started then
      vim.notify(("loom serve is already running in %s at %s"):format(info.where, url))
    end
  end)
end

function M.bundle(arg)
  local ctx = context()
  if not ctx then
    return
  end
  local key = (arg ~= "" and arg) or quilt.key_at_cursor(0)
  if not key then
    vim.notify("loom: no key under the cursor", vim.log.levels.WARN)
    return
  end
  run.run(M.argv_for("bundle", ctx.root, ctx.config, key), function(_, out)
    vim.schedule(function()
      run.scratch("loom://bundle/" .. key, vim.split(out, "\n"), "tex")
    end)
  end)
end

function M.deps(arg)
  local ctx = context()
  if not ctx then
    return
  end
  local key = (arg ~= "" and arg) or quilt.key_at_cursor(0)
  if not key then
    vim.notify("loom: no key under the cursor", vim.log.levels.WARN)
    return
  end
  run.run(M.argv_for("deps", ctx.root, ctx.config, key), function(_, out)
    vim.schedule(function()
      run.scratch("loom://deps/" .. key, vim.split(out, "\n"))
    end)
  end)
end

function M.open(arg)
  local ctx = context()
  if not ctx then
    return
  end
  local key = (arg ~= "" and arg) or quilt.key_at_cursor(0)
  if not key then
    vim.notify("loom: no key under the cursor", vim.log.levels.WARN)
    return
  end
  M.open_key(ctx.root, key)
end

--- Open `key` in arras on this session's server for `root`, starting the server first when there is none.
--- @param root string
--- @param key string
function M.open_key(root, key)
  local cfg = require("loom.config").get()
  with_server(root, cfg, function(url)
    cfg.opener(url .. "node/" .. key)
  end)
end

--- Carry out a `loom.run` command from the language server: confirm when it writes, run, then insert or report the output.
--- A `--print` command (a node skeleton) is inserted below the cursor; anything else is reported.
--- @param argv string[]
--- @param confirm string  empty when the command writes nothing
function M.run_action(argv, confirm)
  if confirm ~= "" and not M.confirm(confirm) then
    return
  end
  local buf, win = vim.api.nvim_get_current_buf(), vim.api.nvim_get_current_win()
  run.run(argv, function(code, out, err)
    vim.schedule(function()
      local name = argv[2] or argv[1]
      if code ~= 0 then
        vim.notify(("loom %s failed: %s"):format(name, err ~= "" and err or out), vim.log.levels.ERROR)
        return
      end
      if vim.tbl_contains(argv, "--print") and vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_buf(win) == buf then
        local row = vim.api.nvim_win_get_cursor(win)[1]
        vim.api.nvim_buf_set_lines(buf, row, row, false, vim.split(out:gsub("\n$", ""), "\n"))
        return
      end
      vim.notify(("loom %s: %s"):format(name, vim.trim(out)))
    end)
  end)
end

local CODE_ACTION_TIMEOUT_MS = 5000

--- Apply the loom server's code action of `kind` at the cursor, and say what it was.
---
--- The server offers at most one action of each reshaping kind, so the first of the kind is taken; the answer is filtered here as well as asked for, because the server sends everything it has at the position. Only the loom client is asked, never the TeX server beside it, and the edit lands in the buffer rather than on disk, which is what makes the whole reshaping one undo. `nothing` is what to say when the server offers none.
--- @param kind string  an LSP code action kind, e.g. "refactor.extract"
--- @param nothing string  the message for a position the server offers nothing at
--- @return table|nil  the action applied, or nil
function M.code_action(kind, nothing)
  local client = require("loom.lsp").client(0)
  if not client then
    vim.notify("loom: the language server is not attached to this buffer", vim.log.levels.WARN)
    return nil
  end
  local params = vim.lsp.util.make_range_params(0, client.offset_encoding)
  params.context = { only = { kind }, diagnostics = {} }
  local response = client:request_sync("textDocument/codeAction", params, CODE_ACTION_TIMEOUT_MS, 0)
  local action
  for _, a in ipairs(response and response.result or {}) do
    local k = a.kind or ""
    if a.edit and (k == kind or vim.startswith(k, kind .. ".")) then
      action = a
      break
    end
  end
  if not action then
    vim.notify(nothing, vim.log.levels.WARN)
    return nil
  end
  vim.lsp.util.apply_workspace_edit(action.edit, client.offset_encoding)
  vim.notify(action.title)
  return action
end

--- Move the node under the cursor into `nodes/<id>.tex`, leaving an `\input` behind.
function M.atomize()
  return M.code_action(
    "refactor.extract",
    "loom: nothing to atomize here; the cursor must be inside a node that has an id and does not already have a file of its own (:LoomId gives a node without an id one)"
  )
end

--- Give the node under the cursor the next free id.
function M.id()
  return M.code_action(
    "refactor.rewrite",
    "loom: nothing to give an id to here; the cursor must be inside a node that has none"
  )
end

--- Ask before a command that writes. Replaced in the tests.
--- @param message string
--- @return boolean
function M.confirm(message)
  return vim.fn.confirm(message, "&Yes\n&No", 2) == 1
end

return M
