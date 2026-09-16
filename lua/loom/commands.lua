-- The commands. Each one builds an argument vector and either shows the output or, for the ones that write, confirms first.

local quilt = require("loom.quilt")
local run = require("loom.run")

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
--- @return string[]|nil, string|nil  the vector, or nil and a URL for the browser
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
      return nil, nil
    end
    return A("new", taxon, title, "--print")
  elseif name == "accept" then
    return A("accept", arg or "")
  elseif name == "serve" then
    return A("serve")
  elseif name == "bundle" then
    return A("bundle", arg or "")
  elseif name == "deps" then
    return A("deps", arg or "")
  elseif name == "open" then
    return nil, cfg.serve_url:gsub("/$", "") .. "/node/" .. (arg or "")
  end
  return nil, nil
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

function M.serve()
  local ctx = context()
  if not ctx then
    return
  end
  local argv = M.argv_for("serve", ctx.root, ctx.config)
  vim.cmd("botright split")
  vim.fn.termopen(argv)
  vim.cmd("startinsert")
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
  local _, url = M.argv_for("open", ctx.root, ctx.config, key)
  require("loom.config").get().opener(url)
end

return M
