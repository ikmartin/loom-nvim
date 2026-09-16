-- A smoke test against a real quilt and the real server: open a node, wait for LspAttach, print the diagnostic count.
-- Run it with:
--   nvim --headless --noplugin -u tests/minimal_init.lua -l scripts/smoke.lua <quilt-root> <file>
local root = vim.fn.fnamemodify(vim.v.argv[#vim.v.argv - 1] or "", ":p")
local file = vim.v.argv[#vim.v.argv]
if not file or file == "" then
  io.stderr:write("usage: ... -l scripts/smoke.lua <quilt-root> <file>\n")
  vim.cmd("cquit 2")
end

local server = vim.env.LOOM_LSP or "loom-lsp"
require("loom").setup({ autostart = false, which_key = false, server = server })

local attached = false
vim.api.nvim_create_autocmd("LspAttach", {
  callback = function(args)
    local client = vim.lsp.get_client_by_id(args.data.client_id)
    if client and client.name == "loom_lsp" then
      attached = true
    end
  end,
})

require("loom.lsp").register(require("loom.config").get())
vim.cmd("edit " .. vim.fn.fnameescape(file))

local deadline = vim.uv.now() + 30000
while not attached and vim.uv.now() < deadline do
  vim.wait(200)
end
if not attached then
  io.stderr:write("the loom client never attached\n")
  vim.cmd("cquit 1")
end

-- give the first publish a moment
vim.wait(3000, function()
  return #vim.diagnostic.get(0) > 0
end, 200)

local diags = vim.diagnostic.get(0)
print(("attached: yes; %s: %d diagnostic(s)"):format(vim.fn.fnamemodify(file, ":~:."), #diags))
for _, d in ipairs(diags) do
  print(("  %s:%d %s"):format(d.source or "?", (d.lnum or 0) + 1, d.message))
end
print("quilt root: " .. tostring(require("loom.quilt").root_of_buf(0)) .. " (asked for " .. root .. ")")
vim.cmd("qall!")
