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

--- Where the server runs: `"tmux"` or `"terminal"`, and a warning when the setting asked for tmux and cannot have it.
--- `"auto"` takes a tmux pane only when Neovim itself runs inside tmux, so a tmux server elsewhere on the machine is never used.
--- @param mode string  the `serve` setting: "auto", "tmux" or "terminal"
--- @param tmux_env string|nil  $TMUX
--- @param has_tmux boolean  whether the tmux binary is executable
--- @return string, string|nil
function M.serve_target(mode, tmux_env, has_tmux)
  if mode == "terminal" then
    return "terminal", nil
  end
  if tmux_env and tmux_env ~= "" and has_tmux then
    return "tmux", nil
  end
  if mode == "tmux" then
    return "terminal", "loom: serve = 'tmux' but Neovim is not running inside tmux; using a terminal split"
  end
  return "terminal", nil
end

--- The tmux call that opens the server's pane below `pane`, holding a placeholder process.
--- The placeholder keeps the pane alive until remain-on-exit is set on it; the server is swapped in by `tmux_respawn_argv`, so a server that fails at once still leaves its error on screen.
--- @param root string
--- @param pane string|nil  $TMUX_PANE
--- @return string[]
function M.tmux_split_argv(root, pane)
  local out = { "tmux", "split-window", "-v", "-l", "30%", "-d", "-c", root, "-P", "-F", "#{pane_id}" }
  if pane and pane ~= "" then
    vim.list_extend(out, { "-t", pane })
  end
  vim.list_extend(out, { "--", "cat" })
  return out
end

--- The tmux call that runs `argv` in `pane`, replacing whatever it holds.
--- @param root string
--- @param pane string
--- @param argv string[]
--- @return string[]
function M.tmux_respawn_argv(root, pane, argv)
  local out = { "tmux", "respawn-pane", "-k", "-t", pane, "-c", root, "--" }
  vim.list_extend(out, argv)
  return out
end

-- The server this session started: { kind = "tmux", pane = "%5" } or { kind = "terminal", job = 12 }.
local server = nil

--- The state of the tmux pane `pane`: "running", "dead" (kept by remain-on-exit) or "gone".
local function tmux_pane_state(pane)
  local out = vim.fn.system({ "tmux", "list-panes", "-a", "-F", "#{pane_id} #{pane_dead}" })
  if vim.v.shell_error ~= 0 then
    return "gone"
  end
  for _, line in ipairs(vim.split(out, "\n")) do
    local id, dead = line:match("^(%%%d+) (%d)$")
    if id == pane then
      return dead == "1" and "dead" or "running"
    end
  end
  return "gone"
end

--- Run `argv` in a tmux pane below Neovim's own, reusing this session's pane when it is still open.
--- @return boolean  false when tmux refused, so the caller can fall back to a terminal
local function serve_in_tmux(root, argv)
  local pane = server and server.kind == "tmux" and server.pane or nil
  local state = pane and tmux_pane_state(pane) or "gone"
  if state == "running" then
    vim.notify(("loom serve is already running in tmux pane %s"):format(pane))
    return true
  end
  if state == "gone" then
    local out = vim.fn.system(M.tmux_split_argv(root, vim.env.TMUX_PANE))
    if vim.v.shell_error ~= 0 then
      vim.notify("loom: tmux split-window failed: " .. out, vim.log.levels.WARN)
      return false
    end
    pane = vim.trim(out)
    vim.fn.system({ "tmux", "set-option", "-p", "-t", pane, "remain-on-exit", "on" })
  end
  local out = vim.fn.system(M.tmux_respawn_argv(root, pane, argv))
  if vim.v.shell_error ~= 0 then
    vim.notify("loom: tmux respawn-pane failed: " .. out, vim.log.levels.WARN)
    vim.fn.system({ "tmux", "kill-pane", "-t", pane })
    return false
  end
  server = { kind = "tmux", pane = pane }
  vim.notify(("loom serve: tmux pane %s"):format(pane))
  return true
end

--- Run `argv` in a terminal buffer in a new split, leaving the cursor where it was.
--- The split gets a buffer of its own, so the buffer being edited is never turned into the terminal.
local function serve_in_terminal(root, argv)
  if server and server.kind == "terminal" and vim.fn.jobwait({ server.job }, 0)[1] == -1 then
    vim.notify("loom serve is already running in a terminal buffer")
    return
  end
  local from = vim.api.nvim_get_current_win()
  vim.cmd("botright new")
  local job
  if vim.fn.has("nvim-0.11") == 1 then
    job = vim.fn.jobstart(argv, { term = true, cwd = root })
  else
    job = vim.fn.termopen(argv, { cwd = root })
  end
  vim.api.nvim_set_current_win(from)
  if job <= 0 then
    vim.notify("loom: could not start " .. argv[1], vim.log.levels.ERROR)
    return
  end
  server = { kind = "terminal", job = job }
end

--- Start `argv` as the server for `root`, where `cfg.serve` and the environment say.
--- Exposed with the command vector injected, so the tests can start something harmless.
--- @param root string
--- @param argv string[]
--- @param cfg table
function M.start_server(root, argv, cfg)
  local target, warning = M.serve_target(cfg.serve, vim.env.TMUX, vim.fn.executable("tmux") == 1)
  if warning then
    vim.notify(warning, vim.log.levels.WARN)
  end
  if target == "tmux" and serve_in_tmux(root, argv) then
    return
  end
  serve_in_terminal(root, argv)
end

--- Forget the server this session started, for the tests.
function M._reset_server()
  server = nil
end

function M.serve()
  local ctx = context()
  if not ctx then
    return
  end
  M.start_server(ctx.root, M.argv_for("serve", ctx.root, ctx.config), ctx.config)
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
