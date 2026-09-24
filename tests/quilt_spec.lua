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
    vim.fn.writefile({ "[quilt]", 'main = "drafting/main.tex"' }, d .. "/config.toml")
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

  it("takes the first node of the file an \\input names, not its path", function()
    local d = tmpdir()
    vim.fn.mkdir(d .. "/nodes", "p")
    vim.fn.mkdir(d .. "/drafting", "p")
    vim.fn.writefile({ "[quilt]" }, d .. "/config.toml")
    vim.fn.writefile({ "% a comment", "\\begin{example}\\label{rl-0008}", "Text.", "\\end{example}" }, d .. "/nodes/rl-0008.tex")
    local draft = d .. "/drafting/draft4.tex"
    vim.fn.writefile({ "\\section{Examples}\\label{rl-0100}", "\\input{nodes/rl-0008}", "\\nest{nodes/rl-0008.tex}" }, draft)
    vim.cmd("edit " .. draft)
    vim.api.nvim_win_set_cursor(0, { 2, 3 })
    assert.are.equal("rl-0008", quilt.key_at_cursor(0))
    vim.api.nvim_win_set_cursor(0, { 3, 12 })
    assert.are.equal("rl-0008", quilt.key_at_cursor(0))
  end)

  it("falls back to the label above for an \\input of a file with no node", function()
    local d = tmpdir()
    vim.fn.writefile({ "[quilt]" }, d .. "/config.toml")
    vim.fn.writefile({ "Prose only." }, d .. "/intro.tex")
    vim.fn.writefile({ "\\section{Intro}\\label{rl-0100}", "\\input{intro}" }, d .. "/main.tex")
    vim.cmd("edit " .. d .. "/main.tex")
    vim.api.nvim_win_set_cursor(0, { 2, 2 })
    assert.are.equal("rl-0100", quilt.key_at_cursor(0))
  end)

  it("never takes the argument of a command that names no key", function()
    with_lines({ "\\begin{lemma}\\label{rl-0004}", "A \\emph{widget} is \\textbf{fine}." }, 2, 6)
    assert.are.equal("rl-0004", quilt.key_at_cursor(0))
    with_lines({ "\\section{Setup}" }, 1, 10)
    assert.is_nil(quilt.key_at_cursor(0))
  end)

  it("takes a reference with an optional argument and a star", function()
    with_lines({ "see \\cref*[x]{rl-0011}" }, 1, 16)
    assert.are.equal("rl-0011", quilt.key_at_cursor(0))
  end)

  it("returns nil when there is nothing to take", function()
    with_lines({ "plain prose" }, 1, 2)
    assert.is_nil(quilt.key_at_cursor(0))
  end)
end)
