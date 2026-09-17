-- setup registers the commands and the client configuration, and does so without starting anything.
describe("setup", function()
  it("creates every command", function()
    require("loom").setup({ autostart = false, which_key = false })
    local made = vim.api.nvim_get_commands({})
    for _, name in ipairs({
      "LoomStatus",
      "LoomLint",
      "LoomNew",
      "LoomAtomize",
      "LoomId",
      "LoomAccept",
      "LoomServe",
      "LoomOpen",
      "LoomBundle",
      "LoomDeps",
    }) do
      assert.is_not_nil(made[name], name .. " was not created")
    end
  end)

  it("builds a client configuration that starts only inside a quilt", function()
    local lsp = require("loom.lsp")
    local cfg = lsp.client_config({ server = "loom-lsp", loom = "loom" })
    assert.are.same({ "loom-lsp" }, cfg.cmd)
    assert.are.same({ "tex", "plaintex" }, cfg.filetypes)
    assert.are.same({ loomPath = "loom" }, cfg.init_options)

    -- root_dir takes a callback and calls it only inside a quilt (Neovim 0.12's contract)
    local outside = vim.fn.tempname()
    vim.fn.mkdir(outside, "p")
    vim.fn.writefile({ "\\documentclass{article}" }, outside .. "/paper.tex")
    vim.cmd("edit " .. outside .. "/paper.tex")
    local called = false
    cfg.root_dir(0, function() called = true end)
    assert.is_false(called)

    local inside = vim.fn.tempname()
    vim.fn.mkdir(inside .. "/nodes", "p")
    vim.fn.writefile({ "[quilt]" }, inside .. "/config.toml")
    vim.fn.writefile({ "x" }, inside .. "/nodes/a.tex")
    vim.cmd("edit " .. inside .. "/nodes/a.tex")
    local got = nil
    cfg.root_dir(0, function(dir) got = dir end)
    assert.are.equal(vim.fn.resolve(inside), vim.fn.resolve(got))
  end)

  it("registers the server through the mechanism this Neovim has", function()
    local how = require("loom.lsp").register(require("loom.config").defaults())
    assert.is_true(how == "vim.lsp.config" or how == "lspconfig")
  end)

  it("carries out the language server's commands, confirming before one that writes", function()
    require("loom").setup({ autostart = false, which_key = false })
    assert.is_function(vim.lsp.commands["loom.run"])
    assert.is_function(vim.lsp.commands["loom.open"])
    assert.are.equal(1, #vim.api.nvim_get_autocmds({ group = "loom_serve", event = "VimLeavePre" }))

    local commands = require("loom.commands")
    local run = require("loom.run")
    local real_run, real_confirm = run.run, commands.confirm
    local ran, asked = {}, {}
    run.run = function(argv, done)
      table.insert(ran, argv)
      done(0, "recorded", "")
    end
    commands.confirm = function(message)
      table.insert(asked, message)
      return false
    end
    local notify = vim.notify
    vim.notify = function() end

    vim.lsp.commands["loom.run"]({ arguments = { { "loom", "accept", "rl-0004", "--quilt", "/q" }, "Record it?" } }, {})
    assert.are.same({ "Record it?" }, asked)
    assert.are.equal(0, #ran)

    commands.confirm = function() return true end
    vim.lsp.commands["loom.run"]({ arguments = { { "loom", "accept", "rl-0004", "--quilt", "/q" }, "Record it?" } }, {})
    vim.wait(1000, function() return #ran == 1 end, 10)
    assert.are.equal(1, #ran)

    vim.cmd("enew")
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { "above" })
    run.run = function(argv, done)
      table.insert(ran, argv)
      done(0, "\\begin{lemma}\n\\end{lemma}\n", "")
    end
    vim.lsp.commands["loom.run"]({ arguments = { { "loom", "new", "lemma", "Title", "--print", "--quilt", "/q" }, "" } }, {})
    vim.wait(1000, function() return vim.api.nvim_buf_line_count(0) == 3 end, 10)
    assert.are.same({ "above", "\\begin{lemma}", "\\end{lemma}" }, vim.api.nvim_buf_get_lines(0, 0, -1, false))

    run.run, commands.confirm, vim.notify = real_run, real_confirm, notify
  end)

  it("gives an empty statusline outside a quilt", function()
    local d = vim.fn.tempname()
    vim.fn.mkdir(d, "p")
    vim.fn.writefile({ "x" }, d .. "/paper.tex")
    vim.cmd("edit " .. d .. "/paper.tex")
    assert.are.equal("", require("loom").statusline())
  end)
end)
