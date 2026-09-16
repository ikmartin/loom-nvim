-- The `loom serve` processes this Neovim session owns: one per quilt, each on a free port chosen here, stopped when the session ends.
-- Inside tmux a server runs in a detached pane below Neovim's own; outside it, in a terminal buffer in a split. Either way the cursor stays where it was.

local M = {}

-- root -> { port, url, kind = "tmux"|"terminal", pane, job, ready, waiting = { callbacks } }
local servers = {}

local READY_TIMEOUT_MS = 30000
local POLL_MS = 200

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

--- The tmux call that opens a server pane below `pane`, holding a placeholder process.
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

--- A port on 127.0.0.1 that nothing was listening on a moment ago.
--- @return integer|nil
function M.free_port()
  local tcp = vim.uv.new_tcp()
  if not tcp then
    return nil
  end
  local ok = tcp:bind("127.0.0.1", 0)
  local name = ok and tcp:getsockname() or nil
  tcp:close()
  return name and name.port or nil
end

--- @param port integer
--- @return string
function M.url_for(port)
  return ("http://127.0.0.1:%d/"):format(port)
end

--- The state of the tmux pane `pane`: "running", "dead" (kept by remain-on-exit) or "gone".
function M.tmux_pane_state(pane)
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

local function alive(entry)
  if entry.kind == "tmux" then
    return M.tmux_pane_state(entry.pane) == "running"
  end
  return entry.job ~= nil and vim.fn.jobwait({ entry.job }, 0)[1] == -1
end

--- Ask `url` for its manifest once; `done(true)` on a 200. Never blocks: the request runs on the event loop.
--- @param url string
--- @param done fun(ok: boolean)
function M.probe(url, done)
  local port = tonumber(url:match(":(%d+)/"))
  local tcp = vim.uv.new_tcp()
  if not port or not tcp then
    done(false)
    return
  end
  local finished = false
  local function finish(ok)
    if finished then
      return
    end
    finished = true
    if not tcp:is_closing() then
      tcp:close()
    end
    vim.schedule(function()
      done(ok)
    end)
  end
  tcp:connect("127.0.0.1", port, function(err)
    if err then
      finish(false)
      return
    end
    tcp:write("GET /build/manifest.json HTTP/1.0\r\nHost: 127.0.0.1\r\n\r\n")
    local head = ""
    tcp:read_start(function(rerr, chunk)
      if rerr or not chunk then
        finish(head:match("^HTTP/%d%.%d 200") ~= nil)
        return
      end
      head = head .. chunk
      if head:find("\r\n", 1, true) then
        finish(head:match("^HTTP/%d%.%d 200") ~= nil)
      end
    end)
  end)
end

--- Start `argv` for `root`, reusing a dead tmux pane from an earlier server of the same quilt.
--- @return table|nil  the entry's process fields, or nil after reporting why
local function start(root, argv, target, previous)
  if target == "tmux" then
    local pane = previous and previous.kind == "tmux" and previous.pane or nil
    if not pane or M.tmux_pane_state(pane) == "gone" then
      local out = vim.fn.system(M.tmux_split_argv(root, vim.env.TMUX_PANE))
      if vim.v.shell_error ~= 0 then
        vim.notify("loom: tmux split-window failed: " .. out, vim.log.levels.WARN)
        return start(root, argv, "terminal", nil)
      end
      pane = vim.trim(out)
      vim.fn.system({ "tmux", "set-option", "-p", "-t", pane, "remain-on-exit", "on" })
    end
    local out = vim.fn.system(M.tmux_respawn_argv(root, pane, argv))
    if vim.v.shell_error ~= 0 then
      vim.notify("loom: tmux respawn-pane failed: " .. out, vim.log.levels.WARN)
      vim.fn.system({ "tmux", "kill-pane", "-t", pane })
      return start(root, argv, "terminal", nil)
    end
    return { kind = "tmux", pane = pane, where = "tmux pane " .. pane }
  end

  local from = vim.api.nvim_get_current_win()
  vim.cmd("botright new")
  local buf = vim.api.nvim_get_current_buf()
  local job
  if vim.fn.has("nvim-0.11") == 1 then
    job = vim.fn.jobstart(argv, { term = true, cwd = root })
  else
    job = vim.fn.termopen(argv, { cwd = root })
  end
  vim.api.nvim_set_current_win(from)
  if job <= 0 then
    vim.notify("loom: could not start " .. argv[1], vim.log.levels.ERROR)
    pcall(vim.api.nvim_buf_delete, buf, { force = true })
    return nil
  end
  return { kind = "terminal", job = job, buf = buf, where = "a Neovim terminal" }
end

local function settle(root, entry, ok)
  local waiting = entry.waiting
  entry.waiting = {}
  if not ok then
    servers[root] = nil
    return
  end
  entry.ready = true
  for _, cb in ipairs(waiting) do
    cb(entry.url, { started = true, where = entry.where })
  end
end

local function launch(root, cfg, build_argv, previous, attempt)
  local port = M.free_port()
  if not port then
    vim.notify("loom: no free port for loom serve", vim.log.levels.ERROR)
    return settle(root, previous, false)
  end
  local target, warning = M.serve_target(cfg.serve, vim.env.TMUX, vim.fn.executable("tmux") == 1)
  if warning and attempt == 1 then
    vim.notify(warning, vim.log.levels.WARN)
  end
  local proc = start(root, build_argv(port), target, previous)
  if not proc then
    return settle(root, previous, false)
  end
  local entry = vim.tbl_extend("force", proc, {
    port = port,
    url = M.url_for(port),
    ready = false,
    waiting = previous.waiting,
  })
  servers[root] = entry

  local started = vim.uv.now()
  local timer = vim.uv.new_timer()
  local probing = false
  timer:start(POLL_MS, POLL_MS, vim.schedule_wrap(function()
    if probing or servers[root] ~= entry then
      return
    end
    if not alive(entry) then
      timer:stop()
      timer:close()
      if attempt == 1 then
        return launch(root, cfg, build_argv, entry, 2) -- most likely the port was taken in the moment after it was chosen
      end
      vim.notify(("loom serve exited before it was ready; see %s"):format(entry.where), vim.log.levels.ERROR)
      return settle(root, entry, false)
    end
    if vim.uv.now() - started > READY_TIMEOUT_MS then
      timer:stop()
      timer:close()
      vim.notify(("loom serve did not answer at %s; see %s"):format(entry.url, entry.where), vim.log.levels.WARN)
      return settle(root, entry, false)
    end
    probing = true
    M.probe(entry.url, function(ok)
      probing = false
      if ok and servers[root] == entry and not entry.ready then
        timer:stop()
        timer:close()
        settle(root, entry, true)
      end
    end)
  end))
end

--- Call `on_ready(url, info)` once this session's server for `root` answers, starting it first when there is none.
--- `info.started` says whether this call started it and `info.where` names the pane or terminal. A second call while the server is starting waits for the same one.
--- @param root string
--- @param cfg table  the plugin settings; `serve` picks tmux or a terminal
--- @param build_argv fun(port: integer): string[]  the command for a port
--- @param on_ready fun(url: string, info: { started: boolean, where: string })
function M.ensure(root, cfg, build_argv, on_ready)
  local entry = servers[root]
  if entry and not entry.ready then
    table.insert(entry.waiting, on_ready)
    return
  end
  if entry and alive(entry) then
    on_ready(entry.url, { started = false, where = entry.where })
    return
  end
  local previous = entry or {}
  previous.waiting = { on_ready }
  previous.ready = false
  servers[root] = previous
  launch(root, cfg, build_argv, previous, 1)
end

--- This session's server for `root`, or nil.
function M.get(root)
  return servers[root]
end

--- Stop every server this session started: tmux panes are killed, terminal jobs stopped. Run on VimLeavePre.
function M.stop_all()
  for root, entry in pairs(servers) do
    if entry.kind == "tmux" and entry.pane then
      vim.fn.system({ "tmux", "kill-pane", "-t", entry.pane })
    elseif entry.kind == "terminal" and entry.job then
      pcall(vim.fn.jobstop, entry.job)
    end
    servers[root] = nil
  end
end

return M
