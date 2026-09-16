-- TeX's search path follows the current buffer: the quilt root first inside a quilt, the original values outside one.
local texenv = require("loom.texenv")

local SEP = vim.fn.has("win32") == 1 and ";" or ":"

local function make_quilt()
  local d = vim.fn.resolve(vim.fn.tempname())
  vim.fn.mkdir(d .. "/drafts", "p")
  vim.fn.mkdir(d .. "/nodes", "p")
  vim.fn.writefile({ "[quilt]" }, d .. "/config.toml")
  vim.fn.writefile({ "\\ProvidesPackage{loom}" }, d .. "/loom.sty")
  vim.fn.writefile({ "@misc{x, title={X}}" }, d .. "/refs.bib")
  vim.fn.writefile({ "\\documentclass{article}", "\\usepackage{loom}" }, d .. "/drafts/main.tex")
  return d
end

local function plain_file()
  local d = vim.fn.tempname()
  vim.fn.mkdir(d, "p")
  vim.fn.writefile({ "\\documentclass{article}" }, d .. "/paper.tex")
  return d .. "/paper.tex"
end

describe("texenv", function()
  local saved
  before_each(function()
    saved = { TEXINPUTS = vim.env.TEXINPUTS, BIBINPUTS = vim.env.BIBINPUTS }
    texenv._reset()
    vim.env.TEXINPUTS = "/existing/tex"
    vim.env.BIBINPUTS = nil
    texenv.setup()
  end)
  after_each(function()
    texenv._reset()
    vim.env.TEXINPUTS = saved.TEXINPUTS
    vim.env.BIBINPUTS = saved.BIBINPUTS
  end)

  it("puts the quilt root first while a quilt file is current, keeping what was there", function()
    local root = make_quilt()
    vim.cmd("edit " .. root .. "/drafts/main.tex")
    assert.are.equal(root .. SEP .. "/existing/tex", vim.env.TEXINPUTS)
    assert.are.equal(root .. SEP, vim.env.BIBINPUTS)
  end)

  it("does not add the root twice when the quilt is entered again", function()
    local root = make_quilt()
    vim.cmd("edit " .. root .. "/drafts/main.tex")
    vim.cmd("edit " .. root .. "/loom.sty")
    vim.cmd("edit " .. root .. "/drafts/main.tex")
    assert.are.equal(root .. SEP .. "/existing/tex", vim.env.TEXINPUTS)
  end)

  it("restores the original values for a file outside any quilt", function()
    local root = make_quilt()
    vim.cmd("edit " .. root .. "/drafts/main.tex")
    vim.cmd("edit " .. plain_file())
    assert.are.equal("/existing/tex", vim.env.TEXINPUTS)
    assert.is_nil(vim.env.BIBINPUTS)
  end)

  it("leaves the path alone for a buffer that is not a file", function()
    local root = make_quilt()
    vim.cmd("edit " .. root .. "/drafts/main.tex")
    local scratch = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_current_buf(scratch)
    assert.are.equal(root .. SEP .. "/existing/tex", vim.env.TEXINPUTS)
  end)

  it("switches between two quilts", function()
    local a, b = make_quilt(), make_quilt()
    vim.cmd("edit " .. a .. "/drafts/main.tex")
    vim.cmd("edit " .. b .. "/drafts/main.tex")
    assert.are.equal(b .. SEP .. "/existing/tex", vim.env.TEXINPUTS)
  end)

  it("reaches the processes Neovim starts, so TeX run from drafts/ finds the root's files", function()
    if vim.fn.executable("kpsewhich") == 0 then
      pending("kpsewhich is not installed")
      return
    end
    local root = make_quilt()
    vim.cmd("edit " .. root .. "/drafts/main.tex")
    local function find(args)
      local out = {}
      local job = vim.fn.jobstart(args, {
        cwd = root .. "/drafts",
        stdout_buffered = true,
        on_stdout = function(_, data)
          out = data
        end,
      })
      vim.fn.jobwait({ job }, 10000)
      return vim.fn.resolve(vim.trim(table.concat(out, "")))
    end
    assert.are.equal(root .. "/loom.sty", find({ "kpsewhich", "loom.sty" }))
    assert.are.equal(root .. "/refs.bib", find({ "kpsewhich", "-format=bib", "refs.bib" }))
  end)
end)

describe("texenv in setup", function()
  it("is not installed when tex_search_path is off", function()
    texenv._reset()
    local before = vim.env.TEXINPUTS
    require("loom").setup({ autostart = false, which_key = false, tex_search_path = false })
    assert.are.equal(0, #vim.api.nvim_get_autocmds({ event = "BufEnter", group = vim.api.nvim_create_augroup("loom_texenv", { clear = false }) }))
    assert.are.equal(before, vim.env.TEXINPUTS)
  end)
end)
