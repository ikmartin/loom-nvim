-- Every command builds the right argument vector, and the browser opener is injected so nothing is launched.
local commands = require("loom.commands")
local config = require("loom.config")

describe("argv_for", function()
  local cfg = vim.tbl_extend("force", config.defaults(), { loom = "/opt/loom", serve_url = "http://127.0.0.1:9000/" })
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

  it("builds the arras url rather than a command", function()
    local argv, url = commands.argv_for("open", root, cfg, "rl-0004")
    assert.is_nil(argv)
    assert.are.equal("http://127.0.0.1:9000/node/rl-0004", url)
  end)
end)

describe("open", function()
  it("hands the url to the injected opener and launches nothing", function()
    local d = vim.fn.tempname()
    vim.fn.mkdir(d .. "/nodes", "p")
    vim.fn.writefile({ "[quilt]" }, d .. "/config.toml")
    local file = d .. "/nodes/rl-0004.tex"
    vim.fn.writefile({ "\\begin{lemma}\\label{rl-0004}", "Text.", "\\end{lemma}" }, file)

    local seen = nil
    config.setup({ opener = function(url) seen = url end, serve_url = "http://127.0.0.1:8123" })
    vim.cmd("edit " .. file)
    vim.api.nvim_win_set_cursor(0, { 2, 0 })
    commands.open("")
    assert.are.equal("http://127.0.0.1:8123/node/rl-0004", seen)
  end)
end)
