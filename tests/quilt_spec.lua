-- Root detection and the key under the cursor. The plugin starts nothing outside a quilt, which is what keeps it out of vimtex's way.
local quilt = require("loom.quilt")

local function tmpdir()
  local d = vim.fn.tempname()
  vim.fn.mkdir(d, "p")
  return d
end

describe("quilt.root", function()
  it("accepts a directory whose config.toml declares a quilt", function()
    local d = tmpdir()
    vim.fn.mkdir(d .. "/nodes", "p")
    vim.fn.writefile({ "[quilt]", 'main = "drafts/main.tex"' }, d .. "/config.toml")
    vim.fn.writefile({ "x" }, d .. "/nodes/a.tex")
    assert.are.equal(vim.fn.resolve(d), vim.fn.resolve(quilt.root(d .. "/nodes/a.tex")))
    assert.are.equal(vim.fn.resolve(d), vim.fn.resolve(quilt.root(d .. "/nodes")))
  end)

  it("rejects a bare directory of .tex files", function()
    local d = tmpdir()
    vim.fn.writefile({ "\\documentclass{article}" }, d .. "/paper.tex")
    assert.is_nil(quilt.root(d .. "/paper.tex"))
  end)

  it("rejects a config.toml that is not a quilt's", function()
    local d = tmpdir()
    vim.fn.writefile({ "[tool.black]", "line-length = 88" }, d .. "/config.toml")
    vim.fn.writefile({ "x" }, d .. "/paper.tex")
    assert.is_nil(quilt.root(d .. "/paper.tex"))
  end)
end)

describe("quilt.key_at_cursor", function()
  local function with_lines(lines, row, col)
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.api.nvim_win_set_buf(0, buf)
    vim.api.nvim_win_set_cursor(0, { row, col })
    return buf
  end

  it("takes the argument of the command under the cursor", function()
    with_lines({ "By Lemma~\\ref{rl-0011} we are done." }, 1, 16)
    assert.are.equal("rl-0011", quilt.key_at_cursor(0))
  end)

  it("takes the first item of a list", function()
    with_lines({ "\\uses{rl-0011, rl-0012}" }, 1, 8)
    assert.are.equal("rl-0011", quilt.key_at_cursor(0))
  end)

  it("falls back to the last label above the cursor", function()
    with_lines({ "\\begin{lemma}\\label{rl-0004}", "Some text.", "\\end{lemma}" }, 2, 3)
    assert.are.equal("rl-0004", quilt.key_at_cursor(0))
  end)

  it("returns nil when there is nothing to take", function()
    with_lines({ "plain prose" }, 1, 2)
    assert.is_nil(quilt.key_at_cursor(0))
  end)
end)
