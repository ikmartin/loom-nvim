-- A minimal init that loads only plenary and this plugin, so a test sees nothing from the user's own configuration.
local here = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
local candidates = {
  vim.env.PLENARY_DIR or "",
  vim.fn.expand("~/.local/share/nvim/lazy/plenary.nvim"),
  vim.fn.expand("~/.local/share/nvim/site/pack/vendor/start/plenary.nvim"),
}
local plenary
for _, dir in ipairs(candidates) do
  if dir ~= "" and vim.fn.isdirectory(dir) == 1 then
    plenary = dir
    break
  end
end
if not plenary then
  io.stderr:write("plenary.nvim not found; looked in $PLENARY_DIR, " .. candidates[2] .. " and " .. candidates[3] .. "\n")
  vim.cmd("cquit 1")
end
vim.opt.runtimepath:prepend(here)
vim.opt.runtimepath:prepend(plenary)
vim.opt.swapfile = false
vim.cmd("runtime plugin/plenary.vim")
