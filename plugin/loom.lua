-- Loaded once. The plugin does nothing until `require("loom").setup()` runs, which a lazy.nvim spec does through `opts`.
if vim.g.loaded_loom_nvim then
  return
end
vim.g.loaded_loom_nvim = true
