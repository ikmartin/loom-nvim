-- A minimal init that loads only plenary and this plugin, so a test sees nothing from the user's own configuration.
local here = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
local plenary = vim.fn.expand("~/.local/share/nvim/lazy/plenary.nvim")
if vim.fn.isdirectory(plenary) == 0 then
  plenary = vim.fn.expand("~/.local/share/nvim/site/pack/vendor/start/plenary.nvim")
end
vim.opt.runtimepath:prepend(here)
vim.opt.runtimepath:prepend(plenary)
vim.opt.swapfile = false
vim.cmd("runtime plugin/plenary.vim")
