-- The servers a session owns. A small `python3 -m http.server` over a directory holding build/manifest.json stands in for `loom serve`, so these start nothing of loom's; the tmux cases run against a private tmux server on its own socket, never the one the tests were started from.
local serve = require("loom.serve")
local config = require("loom.config")

local function fake_site()
  local d = vim.fn.tempname()
  vim.fn.mkdir(d .. "/build", "p")
  vim.fn.writefile({ "{}" }, d .. "/build/manifest.json")
  return d
end

local function http_server(dir)
  return function(port)
    return { "python3", "-m", "http.server", tostring(port), "--bind", "127.0.0.1", "--directory", dir }
  end
end

--- Wait for `ensure` to call back, and return what it was called with.
local function ensure_now(root, cfg, build)
  local got
  serve.ensure(root, cfg, build, function(url, info)
    got = { url = url, info = info }
  end)
  assert.is_true(vim.wait(15000, function()
    return got ~= nil
  end, 50), "ensure never called back")
  return got
end

describe("serve_target", function()
  it("takes a tmux pane only when Neovim runs inside tmux", function()
    assert.are.equal("tmux", (serve.serve_target("auto", "/tmp/tmux-501/default,1,0", true)))
    assert.are.equal("terminal", (serve.serve_target("auto", nil, true)))
    assert.are.equal("terminal", (serve.serve_target("auto", "", true)))
    assert.are.equal("terminal", (serve.serve_target("auto", "/tmp/tmux-501/default,1,0", false)))
  end)

  it("keeps a terminal when told to, even inside tmux", function()
    local target, warning = serve.serve_target("terminal", "/tmp/tmux-501/default,1,0", true)
    assert.are.equal("terminal", target)
    assert.is_nil(warning)
  end)

  it("warns when tmux was asked for and is not there", function()
    local target, warning = serve.serve_target("tmux", nil, true)
    assert.are.equal("terminal", target)
    assert.is_not_nil(warning)
  end)
end)

describe("tmux argument vectors", function()
  it("splits below Neovim's own pane, detached, in the quilt root", function()
    assert.are.same(
      { "tmux", "split-window", "-v", "-l", "30%", "-d", "-c", "/q", "-P", "-F", "#{pane_id}", "-t", "%3", "--", "cat" },
      serve.tmux_split_argv("/q", "%3")
    )
  end)

  it("passes the server command as separate arguments", function()
    assert.are.same(
      { "tmux", "respawn-pane", "-k", "-t", "%4", "-c", "/q q", "--", "loom", "serve", "--quilt", "/q q" },
      serve.tmux_respawn_argv("/q q", "%4", { "loom", "serve", "--quilt", "/q q" })
    )
  end)
end)

describe("free_port", function()
  it("returns a port that can be bound", function()
    local port = serve.free_port()
    assert.is_true(type(port) == "number" and port > 0)
    local tcp = vim.uv.new_tcp()
    assert.is_truthy(tcp:bind("127.0.0.1", port))
    tcp:close()
  end)
end)

describe("a session's server in a terminal", function()
  local saved_tmux
  before_each(function()
    saved_tmux = vim.env.TMUX
    vim.env.TMUX = nil
    serve.stop_all()
    vim.cmd("silent! only")
  end)
  after_each(function()
    serve.stop_all()
    vim.env.TMUX = saved_tmux
  end)

  it("starts once, answers, keeps the cursor in the file, and is reused", function()
    local site = fake_site()
    local file = site .. "/paper.tex"
    vim.fn.writefile({ "x" }, file)
    vim.cmd("edit " .. file)
    local win, buf = vim.api.nvim_get_current_win(), vim.api.nvim_get_current_buf()
    local starts = 0
    local build = function(port)
      starts = starts + 1
      return http_server(site)(port)
    end
    local cfg = vim.tbl_extend("force", config.defaults(), { serve = "auto" })

    local first = ensure_now(site, cfg, build)
    assert.is_true(first.info.started)
    assert.are.equal("a Neovim terminal", first.info.where)
    assert.is_truthy(first.url:match("^http://127%.0%.0%.1:%d+/$"))
    assert.are.equal(win, vim.api.nvim_get_current_win())
    assert.are.equal(buf, vim.api.nvim_win_get_buf(win))
    assert.are.equal("", vim.bo[buf].buftype)
    assert.are.equal(2, #vim.api.nvim_tabpage_list_wins(0))

    local second = ensure_now(site, cfg, build)
    assert.is_false(second.info.started)
    assert.are.equal(first.url, second.url)
    assert.are.equal(1, starts)
    assert.are.equal(2, #vim.api.nvim_tabpage_list_wins(0))
  end)

  it("waits for one server when asked twice while it starts", function()
    local site = fake_site()
    local starts, calls = 0, {}
    local build = function(port)
      starts = starts + 1
      return http_server(site)(port)
    end
    local cfg = config.defaults()
    serve.ensure(site, cfg, build, function(url)
      table.insert(calls, url)
    end)
    serve.ensure(site, cfg, build, function(url)
      table.insert(calls, url)
    end)
    assert.is_true(vim.wait(15000, function()
      return #calls == 2
    end, 50))
    assert.are.equal(1, starts)
    assert.are.equal(calls[1], calls[2])
  end)

  it("tries a second port when the first process exits before answering", function()
    local site = fake_site()
    local attempts = 0
    local build = function(port)
      attempts = attempts + 1
      if attempts == 1 then
        return { "sh", "-c", "exit 1" }
      end
      return http_server(site)(port)
    end
    local got = ensure_now(site, config.defaults(), build)
    assert.are.equal(2, attempts)
    assert.is_true(got.info.started)
  end)

  it("stops its server when the session ends", function()
    local site = fake_site()
    local got = ensure_now(site, config.defaults(), http_server(site))
    local job = serve.get(site).job
    serve.stop_all()
    assert.is_true(vim.wait(5000, function()
      return vim.fn.jobwait({ job }, 0)[1] ~= -1
    end, 50))
    assert.is_nil(serve.get(site))
    local answered
    serve.probe(got.url, function(ok)
      answered = ok
    end)
    vim.wait(3000, function()
      return answered ~= nil
    end, 50)
    assert.is_false(answered)
  end)
end)

describe("a session's server in tmux", function()
  local socket_name = "loom-nvim-test-" .. vim.fn.getpid()
  local saved = {}
  local base_pane, socket

  local function T(...)
    local out = vim.fn.system(vim.list_extend({ "tmux", "-L", socket_name }, { ... }))
    return vim.trim(out), vim.v.shell_error
  end

  local function panes()
    local out = T("list-panes", "-a", "-F", "#{pane_id} #{pane_dead}")
    return vim.split(out, "\n", { trimempty = true })
  end

  before_each(function()
    if vim.fn.executable("tmux") == 0 then
      return
    end
    T("kill-server")
    T("new-session", "-d", "-x", "120", "-y", "40", "-s", "t", "sleep", "300")
    base_pane = T("display-message", "-p", "-t", "t", "#{pane_id}")
    socket = T("display-message", "-p", "#{socket_path}")
    saved = { TMUX = vim.env.TMUX, TMUX_PANE = vim.env.TMUX_PANE }
    vim.env.TMUX = socket .. ",0,0"
    vim.env.TMUX_PANE = base_pane
    serve.stop_all()
    vim.cmd("silent! only")
  end)

  after_each(function()
    if vim.fn.executable("tmux") == 0 then
      return
    end
    serve.stop_all()
    vim.env.TMUX = saved.TMUX
    vim.env.TMUX_PANE = saved.TMUX_PANE
    T("kill-server")
    os.remove(socket)
  end)

  it("runs in one pane beside Neovim, reuses it, and closes it when the session ends", function()
    if vim.fn.executable("tmux") == 0 then
      pending("tmux is not installed")
      return
    end
    local site = fake_site()
    local wins = #vim.api.nvim_tabpage_list_wins(0)

    local first = ensure_now(site, config.defaults(), http_server(site))
    assert.is_true(first.info.started)
    assert.is_truthy(first.info.where:match("^tmux pane %%%d+$"))
    assert.are.equal(2, #panes())
    assert.are.equal(wins, #vim.api.nvim_tabpage_list_wins(0))
    assert.are.equal(base_pane, (T("display-message", "-p", "-t", "t", "#{pane_id}")))

    local second = ensure_now(site, config.defaults(), http_server(site))
    assert.is_false(second.info.started)
    assert.are.equal(2, #panes())

    serve.stop_all()
    assert.are.equal(1, #panes())
  end)

  it("restarts in the same pane after the server has exited", function()
    if vim.fn.executable("tmux") == 0 then
      pending("tmux is not installed")
      return
    end
    local site = fake_site()
    ensure_now(site, config.defaults(), http_server(site))
    local pane = serve.get(site).pane
    T("respawn-pane", "-k", "-t", pane, "--", "sh", "-c", "echo 'port in use'; exit 3")
    assert.is_true(vim.wait(5000, function()
      return (T("display-message", "-p", "-t", pane, "#{pane_dead}")) == "1"
    end, 50))

    local again = ensure_now(site, config.defaults(), http_server(site))
    assert.is_true(again.info.started)
    assert.are.equal(pane, serve.get(site).pane)
    assert.are.equal(2, #panes())
  end)
end)
