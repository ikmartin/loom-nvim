-- Ask the running server for a hover and a definition at a known position, so the plugin's end of the protocol is exercised too.
-- nvim --headless --noplugin -u tests/minimal_init.lua -l scripts/probe.lua <file>
require("loom").setup({ autostart = false, which_key = false, server = vim.env.LOOM_LSP or "loom-lsp" })
require("loom.lsp").register(require("loom.config").get())
vim.cmd("edit " .. vim.fn.fnameescape(vim.v.argv[#vim.v.argv]))

local attached = false
vim.api.nvim_create_autocmd("LspAttach", { callback = function() attached = true end })
vim.wait(30000, function() return attached end, 200)
assert(attached, "no client")

local client = require("loom.lsp").client(0)
local line = vim.fn.search("\\\\ref{", "nw") - 1
local col = (vim.api.nvim_buf_get_lines(0, line, line + 1, false)[1] or ""):find("\\ref{") + 5
local pos = { line = line, character = col }

local hov = client:request_sync("textDocument/hover", {
  textDocument = { uri = vim.uri_from_bufnr(0) },
  position = pos,
}, 10000, 0)
print("hover:", (hov and hov.result and hov.result.contents and hov.result.contents.value or ""):gsub("\n", " | "):sub(1, 140))

local def = client:request_sync("textDocument/definition", {
  textDocument = { uri = vim.uri_from_bufnr(0) },
  position = pos,
}, 10000, 0)
local target = def and def.result and (def.result[1] or def.result)
print("definition:", target and vim.uri_to_fname(target.uri) or "none")
vim.cmd("qall!")
