-- setup registers the commands and the client configuration, and does so without starting anything.
describe("setup", function()
  it("creates every command", function()
    require("loom").setup({ autostart = false, which_key = false })
    local made = vim.api.nvim_get_commands({})
    for _, name in ipairs({
      "LoomStatus",
      "LoomLint",
      "LoomNew",
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
    local cfg = lsp.client_config({ server = "loom-lsp", loom = "loom", serve_url = "http://x" })
    assert.are.same({ "loom-lsp" }, cfg.cmd)
    assert.are.same({ "tex", "plaintex" }, cfg.filetypes)
    assert.are.equal("loom", cfg.init_options.loomPath)

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

  it("gives an empty statusline outside a quilt", function()
    local d = vim.fn.tempname()
    vim.fn.mkdir(d, "p")
    vim.fn.writefile({ "x" }, d .. "/paper.tex")
    vim.cmd("edit " .. d .. "/paper.tex")
    assert.are.equal("", require("loom").statusline())
  end)
end)
