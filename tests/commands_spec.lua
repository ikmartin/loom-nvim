-- Every command builds the right argument vector, and the browser opener is injected so nothing is launched.
local commands = require("loom.commands")
local config = require("loom.config")

describe("argv_for", function()
  local cfg = vim.tbl_extend("force", config.defaults(), { loom = "/opt/loom" })
  local root = "/tmp/quilt"

  it("puts the quilt root on every call", function()
    for _, name in ipairs({ "status", "lint", "accept", "serve", "bundle", "deps" }) do
      local argv = commands.argv_for(name, root, cfg, "rl-0004")
      assert.are.equal("/opt/loom", argv[1])
      assert.are.equal("--quilt", argv[#argv - 1])
      assert.are.equal(root, argv[#argv])
    end
  end)

  it("asks lint for json", function()
    assert.are.same({ "/opt/loom", "lint", "--json", "--quilt", root }, commands.argv_for("lint", root, cfg))
  end)

  it("keeps a title with spaces in one argument", function()
    local argv = commands.argv_for("new", root, cfg, "lemma A title with spaces")
    assert.are.same({ "/opt/loom", "new", "lemma", "A title with spaces", "--print", "--quilt", root }, argv)
  end)

  it("refuses a new without a title", function()
    assert.is_nil(commands.argv_for("new", root, cfg, "lemma"))
  end)

  it("gives serve the port the session chose", function()
    assert.are.same({ "/opt/loom", "serve", "--port", "8123", "--quilt", root }, commands.argv_for("serve", root, cfg, "8123"))
  end)
end)

-- a stand-in for loom: `serve --port N --quilt ROOT` serves ROOT over http, which is all open needs
local function fake_loom()
  local script = vim.fn.tempname()
  vim.fn.writefile({
    "#!/bin/sh",
    'port=""; root=""',
    'while [ $# -gt 0 ]; do case "$1" in --port) port="$2"; shift;; --quilt) root="$2"; shift;; esac; shift; done',
    'exec python3 -m http.server "$port" --bind 127.0.0.1 --directory "$root"',
  }, script)
  vim.fn.setfperm(script, "rwxr-xr-x")
  return script
end

local function quilt_with_node(with_manifest)
  local d = vim.fn.tempname()
  vim.fn.mkdir(d .. "/nodes", "p")
  vim.fn.writefile({ "[quilt]" }, d .. "/config.toml")
  if with_manifest then
    vim.fn.mkdir(d .. "/build", "p")
    vim.fn.writefile({ "{}" }, d .. "/build/manifest.json")
  end
  local file = d .. "/nodes/rl-0004.tex"
  vim.fn.writefile({ "\\begin{lemma}\\label{rl-0004}", "Text.", "\\end{lemma}" }, file)
  return d, file
end

describe("open", function()
  local saved_tmux
  before_each(function()
    saved_tmux = vim.env.TMUX
    vim.env.TMUX = nil
    require("loom.serve").stop_all()
    vim.cmd("silent! only")
  end)
  after_each(function()
    require("loom.serve").stop_all()
    vim.env.TMUX = saved_tmux
  end)

  it("starts this session's server, says so, opens the node on it, and reuses it", function()
    local _, file = quilt_with_node(true)
    local seen = {}
    config.setup({ loom = fake_loom(), opener = function(url) table.insert(seen, url) end })
    local notes = {}
    local notify = vim.notify
    vim.notify = function(msg) table.insert(notes, msg) end
    vim.cmd("edit " .. file)
    local buf = vim.api.nvim_get_current_buf()
    vim.api.nvim_win_set_cursor(0, { 2, 0 })

    commands.open("")
    assert.is_true(vim.wait(15000, function() return #seen == 1 end, 50))
    commands.open("")
    assert.is_true(vim.wait(5000, function() return #seen == 2 end, 50))
    vim.notify = notify

    assert.is_truthy(seen[1]:match("^http://127%.0%.0%.1:%d+/node/rl%-0004$"))
    assert.are.equal(seen[1], seen[2])
    assert.are.equal(1, #vim.tbl_filter(function(m) return m:match("^loom serve started in a Neovim terminal at ") ~= nil end, notes))
    assert.are.equal(buf, vim.api.nvim_get_current_buf())
  end)

  it("opens the node on a real loom serve", function()
    local demo = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h:h") .. "/loom/tests/quilts/demo"
    if vim.fn.executable("loom") == 0 or vim.fn.isdirectory(demo) == 0 then
      pending("loom or its demo quilt is not available")
      return
    end
    local root = vim.fn.tempname()
    vim.fn.system({ "cp", "-R", demo, root })
    local seen
    config.setup({ loom = "loom", opener = function(url) seen = url end })
    local notify = vim.notify
    vim.notify = function() end
    commands.open_key(root, "dm-0003")
    local ok = vim.wait(60000, function() return seen ~= nil end, 100)
    vim.notify = notify
    assert.is_true(ok, "loom serve never answered")
    local base = seen:match("^(http://127%.0%.0%.1:%d+/)node/dm%-0003$")
    assert.is_not_nil(base)
    local answered
    require("loom.serve").probe(base, function(r) answered = r end)
    vim.wait(5000, function() return answered ~= nil end, 50)
    assert.is_true(answered)
  end)
end)
