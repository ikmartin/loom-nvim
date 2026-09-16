-- Where :LoomServe runs the server. The tmux cases run against a private tmux server on its own socket, never the one the tests were started from.
local commands = require("loom.commands")
local config = require("loom.config")

local function quilt_file()
  local d = vim.fn.tempname()
  vim.fn.mkdir(d .. "/nodes", "p")
  vim.fn.writefile({ "[quilt]" }, d .. "/config.toml")
  local file = d .. "/nodes/rl-0004.tex"
  vim.fn.writefile({ "\\begin{lemma}\\label{rl-0004}", "Text.", "\\end{lemma}" }, file)
  return d, file
end

describe("serve_target", function()
  it("takes a tmux pane only when Neovim runs inside tmux", function()
    assert.are.equal("tmux", (commands.serve_target("auto", "/tmp/tmux-501/default,1,0", true)))
    assert.are.equal("terminal", (commands.serve_target("auto", nil, true)))
    assert.are.equal("terminal", (commands.serve_target("auto", "", true)))
    assert.are.equal("terminal", (commands.serve_target("auto", "/tmp/tmux-501/default,1,0", false)))
  end)

  it("keeps a terminal when told to, even inside tmux", function()
    local target, warning = commands.serve_target("terminal", "/tmp/tmux-501/default,1,0", true)
    assert.are.equal("terminal", target)
    assert.is_nil(warning)
  end)

  it("warns when tmux was asked for and is not there", function()
    local target, warning = commands.serve_target("tmux", nil, true)
    assert.are.equal("terminal", target)
    assert.is_not_nil(warning)
  end)
end)

describe("tmux argument vectors", function()
  it("splits below Neovim's own pane, detached, in the quilt root", function()
    assert.are.same(
      { "tmux", "split-window", "-v", "-l", "30%", "-d", "-c", "/q", "-P", "-F", "#{pane_id}", "-t", "%3", "--", "cat" },
      commands.tmux_split_argv("/q", "%3")
    )
  end)

  it("passes the server command as separate arguments", function()
    assert.are.same(
      { "tmux", "respawn-pane", "-k", "-t", "%4", "-c", "/q q", "--", "loom", "serve", "--quilt", "/q q" },
      commands.tmux_respawn_argv("/q q", "%4", { "loom", "serve", "--quilt", "/q q" })
    )
  end)
end)

describe("serve in a terminal", function()
  local saved_tmux
  before_each(function()
    saved_tmux = vim.env.TMUX
    vim.env.TMUX = nil
    commands._reset_server()
    vim.cmd("silent! only")
  end)
  after_each(function()
    vim.env.TMUX = saved_tmux
  end)

  it("opens a buffer of its own and leaves the edited file where it was", function()
    local root, file = quilt_file()
    vim.cmd("edit " .. file)
    local win, buf = vim.api.nvim_get_current_win(), vim.api.nvim_get_current_buf()
    local cfg = vim.tbl_extend("force", config.defaults(), { serve = "auto" })

    commands.start_server(root, { "sleep", "30" }, cfg)

    local wins = vim.api.nvim_tabpage_list_wins(0)
    assert.are.equal(2, #wins)
    assert.are.equal(win, vim.api.nvim_get_current_win())
    assert.are.equal(buf, vim.api.nvim_win_get_buf(win))
    assert.are.equal("", vim.bo[buf].buftype)
    assert.are.equal(vim.fn.resolve(file), vim.fn.resolve(vim.api.nvim_buf_get_name(buf)))
    local other = wins[1] == win and wins[2] or wins[1]
    local term = vim.api.nvim_win_get_buf(other)
    assert.are.equal("terminal", vim.bo[term].buftype)

    commands.start_server(root, { "sleep", "30" }, cfg)
    assert.are.equal(2, #vim.api.nvim_tabpage_list_wins(0))

    vim.fn.jobstop(vim.bo[term].channel)
    vim.api.nvim_buf_delete(term, { force = true })
  end)
end)

describe("serve in tmux", function()
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

  local function wait_for(pred)
    return vim.wait(5000, pred, 50)
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
    commands._reset_server()
    vim.cmd("silent! only")
  end)

  after_each(function()
    if vim.fn.executable("tmux") == 0 then
      return
    end
    vim.env.TMUX = saved.TMUX
    vim.env.TMUX_PANE = saved.TMUX_PANE
    T("kill-server")
    os.remove(socket)
  end)

  it("opens one pane, reuses it while it runs, and respawns it once the server has exited", function()
    if vim.fn.executable("tmux") == 0 then
      pending("tmux is not installed")
      return
    end
    local root = quilt_file()
    local cfg = vim.tbl_extend("force", config.defaults(), { serve = "auto" })
    local wins = #vim.api.nvim_tabpage_list_wins(0)

    commands.start_server(root, { "sh", "-c", "echo 'served here'; sleep 300" }, cfg)
    assert.are.equal(2, #panes())
    assert.are.equal(wins, #vim.api.nvim_tabpage_list_wins(0))
    local pane = panes()[2]:match("^(%S+)")
    assert.is_true(wait_for(function()
      return T("capture-pane", "-p", "-S", "-", "-t", pane):find("served here", 1, true) ~= nil
    end))
    assert.are.equal(vim.fn.resolve(root), vim.fn.resolve((T("display-message", "-p", "-t", pane, "#{pane_start_path}"))))

    commands.start_server(root, { "sh", "-c", "sleep 300" }, cfg)
    assert.are.equal(2, #panes())

    T("respawn-pane", "-k", "-t", pane, "--", "sh", "-c", "echo 'port in use'; exit 3")
    assert.is_true(wait_for(function()
      return T("display-message", "-p", "-t", pane, "#{pane_dead}") == "1"
    end))
    -- tmux marks the pane dead on exit before it has necessarily read the last output
    assert.is_true(wait_for(function()
      return T("capture-pane", "-p", "-S", "-", "-t", pane):find("port in use", 1, true) ~= nil
    end))

    commands.start_server(root, { "sh", "-c", "echo again; sleep 300" }, cfg)
    assert.are.equal(2, #panes())
    assert.is_true(wait_for(function()
      return T("display-message", "-p", "-t", pane, "#{pane_dead}") == "0"
    end))
    assert.are.equal(base_pane, T("display-message", "-p", "-t", "t", "#{pane_id}"))
  end)

  it("keeps a server that fails at once readable in its pane", function()
    if vim.fn.executable("tmux") == 0 then
      pending("tmux is not installed")
      return
    end
    local root = quilt_file()
    commands.start_server(root, { "printf", "%s\\n", "address already in use" }, config.defaults())
    local pane = panes()[2]:match("^(%S+)")
    assert.is_true(wait_for(function()
      return T("display-message", "-p", "-t", pane, "#{pane_dead}") == "1"
    end))
    -- tmux marks the pane dead on exit before it has necessarily read the last output
    assert.is_true(wait_for(function()
      return T("capture-pane", "-p", "-S", "-", "-t", pane):find("address already in use", 1, true) ~= nil
    end))
  end)
end)
