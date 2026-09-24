-- The two reshaping commands. The helper is driven by a fake client so nothing is started; the end-to-end case runs the real server over a copy of loom's synthetic quilt and is skipped when the binaries are missing.
local commands = require("loom.commands")
local lsp = require("loom.lsp")

--- Run `fn` with `vim.notify` collecting into the list it returns.
local function notes_of(fn)
  local notes = {}
  local notify = vim.notify
  vim.notify = function(msg, level)
    table.insert(notes, { msg = msg, level = level })
  end
  local ok, err = pcall(fn)
  vim.notify = notify
  assert(ok, err)
  return notes
end

--- A client that answers one `textDocument/codeAction` with `actions` and records the parameters it was asked with.
local function fake_client(actions)
  local seen = {}
  return {
    offset_encoding = "utf-16",
    request_sync = function(_, method, params)
      seen.method = method
      seen.params = params
      return { result = actions }
    end,
  }, seen
end

--- An edit replacing the whole first line of the current buffer with `text`.
local function edit_first_line(text)
  return {
    changes = {
      [vim.uri_from_bufnr(0)] = {
        {
          range = { start = { line = 0, character = 0 }, ["end"] = { line = 0, character = 0 } },
          newText = text,
        },
      },
    },
  }
end

describe("the reshaping commands", function()
  local real_client
  before_each(function()
    real_client = lsp.client
    local file = vim.fn.tempname() .. ".tex"
    vim.fn.writefile({ "\\begin{definition}[Widget]\\label{sy-0001}", "\\end{definition}" }, file)
    vim.cmd("edit! " .. file)
  end)
  after_each(function()
    lsp.client = real_client
  end)

  it("says so and changes nothing when the server is not attached", function()
    lsp.client = function()
      return nil
    end
    local before = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    for _, run in ipairs({ commands.atomize, commands.id }) do
      local notes = notes_of(run)
      assert.are.equal(1, #notes)
      assert.is_truthy(notes[1].msg:match("not attached"))
      assert.are.equal(vim.log.levels.WARN, notes[1].level)
    end
    assert.are.same(before, vim.api.nvim_buf_get_lines(0, 0, -1, false))
  end)

  it("asks the loom client for one kind at the cursor", function()
    for run, kind in pairs({ [commands.atomize] = "refactor.extract", [commands.id] = "refactor.rewrite" }) do
      local client, seen = fake_client({})
      lsp.client = function()
        return client
      end
      notes_of(run)
      assert.are.equal("textDocument/codeAction", seen.method)
      assert.are.same({ kind }, seen.params.context.only)
      assert.are.same({}, seen.params.context.diagnostics)
      assert.are.equal(vim.uri_from_bufnr(0), seen.params.textDocument.uri)
      assert.is_not_nil(seen.params.range.start.line)
    end
  end)

  it("reports that there is nothing to do, and points at the other command", function()
    -- the server answers with everything it offers at the position, so the other kinds are the client's to ignore
    local client = fake_client({
      { title = "Accept sy-0001", kind = "refactor", command = { command = "loom.run", arguments = {} } },
      { title = "Give this node the id sy-0002", kind = "refactor.rewrite", edit = edit_first_line("\\label{sy-0002}") },
    })
    lsp.client = function()
      return client
    end
    local before = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    local notes = notes_of(commands.atomize)
    assert.are.equal(1, #notes)
    assert.are.equal(vim.log.levels.WARN, notes[1].level)
    assert.is_truthy(notes[1].msg:match("nothing to atomize"))
    assert.is_truthy(notes[1].msg:match(":LoomId"))
    assert.are.same(before, vim.api.nvim_buf_get_lines(0, 0, -1, false))
  end)

  it("applies the one action the server offers and names it", function()
    local client = fake_client({
      { title = "Atomize sy-0001 into nodes/sy-0001.tex", kind = "refactor.extract", edit = edit_first_line("\\input{nodes/sy-0001}\n") },
    })
    lsp.client = function()
      return client
    end
    local notes = notes_of(commands.atomize)
    assert.are.equal("\\input{nodes/sy-0001}", vim.api.nvim_buf_get_lines(0, 0, 1, false)[1])
    assert.are.same({ "Atomize sy-0001 into nodes/sy-0001.tex" }, { notes[1].msg })
  end)

  it("takes the first when more than one comes back", function()
    local client = fake_client({
      { title = "first", kind = "refactor.rewrite", edit = edit_first_line("one\n") },
      { title = "second", kind = "refactor.rewrite", edit = edit_first_line("two\n") },
    })
    lsp.client = function()
      return client
    end
    local notes = notes_of(commands.id)
    assert.are.equal("one", vim.api.nvim_buf_get_lines(0, 0, 1, false)[1])
    assert.are.equal("first", notes[1].msg)
  end)
end)

--- The quilt's main master, as loom resolves it: `[quilt] main`, else `<drafting>/main.tex`. Reads only flat `key = "string"` lines, which is all a quilt's `[quilt]` table holds.
local function master_of(root)
  local keys, section = {}, nil
  for _, line in ipairs(vim.fn.readfile(root .. "/config.toml")) do
    local table_name = line:match("^%s*%[([^%]]+)%]")
    if table_name then
      section = vim.trim(table_name)
    elseif section == "quilt" then
      local key, value = line:match('^%s*([%w_]+)%s*=%s*"([^"]*)"')
      if key then
        keys[key] = value
      end
    end
  end
  local drafting = (keys.drafting or "drafting"):gsub("^/+", ""):gsub("/+$", "")
  if drafting == "" then
    drafting = "drafting"
  end
  return root .. "/" .. (keys.main or (drafting .. "/main.tex"))
end

describe("atomize on the real server", function()
  it("moves the node under the cursor into nodes/, in the buffer", function()
    local quilt = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h:h") .. "/loom/tests/quilts/synthetic"
    if vim.fn.executable("loom") == 0 or vim.fn.executable("loom-lsp") == 0 or vim.fn.isdirectory(quilt) == 0 then
      pending("loom, loom-lsp or the synthetic quilt is not available")
      return
    end
    local root = vim.fn.tempname()
    vim.fn.system({ "cp", "-R", quilt, root })
    require("loom").setup({ which_key = false })
    local master = master_of(root)
    assert.are.equal(1, vim.fn.filereadable(master), "the synthetic quilt has no master at " .. master .. "; did the fixture layout change?")
    vim.cmd("edit " .. vim.fn.fnameescape(master))

    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    local row
    for i, line in ipairs(lines) do
      if line:match("\\begin{definition}%[Widget%]\\label{sy%-0001}") then
        row = i
      end
    end
    assert.is_not_nil(row, "the definition is not in the draft")
    vim.api.nvim_win_set_cursor(0, { row + 1, 0 })

    assert.is_true(vim.wait(60000, function()
      return lsp.client(0) ~= nil
    end, 100), "the loom client never attached")
    assert.is_true(vim.wait(60000, function()
      return #vim.diagnostic.get(0) > 0
    end, 200), "the server published no diagnostics")

    local notes = notes_of(commands.atomize)
    assert.are.equal(1, #vim.tbl_filter(function(n)
      return n.msg:match("^Atomize sy%-0001 into nodes/sy%-0001%.tex$") ~= nil
    end, notes), vim.inspect(notes))

    local node = root .. "/nodes/sy-0001.tex"
    assert.are.equal(1, vim.fn.filereadable(node), "nodes/sy-0001.tex was not created")
    local created = vim.fn.bufadd(node)
    vim.fn.bufload(created)
    assert.is_truthy(table.concat(vim.api.nvim_buf_get_lines(created, 0, -1, false), "\n"):match("\\begin{definition}%[Widget%]\\label{sy%-0001}"))
    assert.are.equal("\\input{nodes/sy-0001}", vim.api.nvim_buf_get_lines(0, row - 1, row, false)[1])
    assert.is_true(vim.bo.modified, "the draft was written instead of edited in the buffer")
  end)
end)
