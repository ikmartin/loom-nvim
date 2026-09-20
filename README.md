# loom-nvim

> **This repository is a mirror.** It is `loom-nvim/` in [ikmartin/loom-arras](https://github.com/ikmartin/loom-arras), pushed here on every change so a plugin manager can install it. Issues and pull requests belong there; a pull request opened here cannot be merged.

A Neovim client for [loom](https://github.com/ikmartin/loom): it starts [loom-lsp](https://github.com/ikmartin/loom-lsp) inside a quilt and puts loom's own commands on the command line.

It **complements vimtex rather than replacing it.** vimtex keeps `tex`; this plugin attaches a second language client beside it and adds commands of its own. It starts only inside a quilt, so an ordinary `.tex` file is untouched.

## Install

```lua
{
  "ikmartin/loom-nvim",
  ft = { "tex", "plaintex" },
  opts = {
    -- every field below is the default
    loom = "loom",              -- the loom binary
    server = "loom-lsp",        -- the language server binary
    serve = "auto",             -- where loom serve runs: "auto", "tmux" or "terminal"
    tex_search_path = true,     -- put the quilt root on TEXINPUTS and BIBINPUTS while a quilt file is current
    autostart = true,           -- attach the server inside a quilt
    which_key = true,           -- register a <leader>l group when which-key is installed
  },
}
```

Neovim 0.12 registers the server through `vim.lsp.config` and `vim.lsp.enable`; on older versions the plugin falls back to `nvim-lspconfig`. `blink.cmp` picks the server's completions up with no extra configuration, because they arrive as ordinary LSP completions.

## Commands

| command | what it does |
|---|---|
| `:LoomStatus` | the quilt's states, in a scratch buffer |
| `:LoomLint` | diagnostics into the quickfix list |
| `:LoomNew {taxon} {title}` | a node skeleton, inserted at the cursor |
| `:LoomAtomize` | move the node under the cursor into `nodes/<id>.tex`, leaving an `\input` behind |
| `:LoomId` | give the node under the cursor the next free id |
| `:LoomAccept [key]` | record an acceptance for the key under the cursor, after confirming |
| `:LoomServe` | start this session's `loom serve` for the quilt, or say where it is running (see below) |
| `:LoomOpen [key]` | open the node under the cursor in arras, starting the server first when needed |
| `:LoomBundle [key]` | the standalone bundle for a key, in a scratch buffer |
| `:LoomDeps [key]` | what the key depends on, and what it is related to |

## The server a session owns

Each Neovim session owns its `loom serve` processes, one per quilt, each on a free port the plugin picks, so arras is always opened on the server this session started and two sessions never compete for a port. `:LoomServe` starts it; `:LoomOpen` starts it too when it is not running, waits until it answers, and says where it started. The cursor stays in the file you were editing either way. Quitting Neovim stops every server the session started.

With `serve = "auto"`:

- **Neovim inside tmux** (`$TMUX` is set): a tmux pane below Neovim's own. A server that exits, for instance on an error, leaves its output in the pane, and the next `:LoomServe` or `:LoomOpen` restarts it there.
- **Neovim outside tmux**, or no tmux on the machine: a terminal buffer in a split at the bottom, which is not entered.

`serve = "terminal"` always takes the split, and `serve = "tmux"` warns when it cannot have a pane.

## Compiling with vimtex

A quilt's masters sit in `drafts/` but name everything relative to the quilt root (`\usepackage{loom}`, `\input{nodes/…}`, `\addbibresource{refs.bib}`), which is how they compile from the root and on Overleaf. vimtex runs latexmk in the master's own folder, where none of those are found. While a file inside a quilt is the current buffer, the plugin therefore puts the quilt root first on `TEXINPUTS` and `BIBINPUTS` in Neovim's environment, so the latexmk vimtex starts finds them; `\ll`, `\lv` and Skim sync work as they do anywhere else, and the compiled files land in `drafts/`, which the quilt's `.gitignore` already covers. Moving to a file outside any quilt restores the original values; buffers that are not files (terminals, the quickfix list) leave them as they are. Nothing is written to the quilt. A continuous compile keeps the path it was started with. `tex_search_path = false` turns this off.

## Language server commands and navigation

The server's code actions name two commands, which the plugin carries out: `loom.run` (accept, atomize, insert a node skeleton; confirming first when it writes) and `loom.open` (open in arras, on this session's server). With LazyVim's defaults they are under `<leader>ca`.

`:LoomAtomize` moves the node under the cursor into `nodes/<id>.tex` and leaves an `\input` in its place, as one edit in your buffers: `u` puts the draft back (the node file it wrote stays on disk), and an unsaved draft is included. loom itself never edits your files — the server plans the change and Neovim applies it. A node with no id refuses the move; `:LoomId` gives it one, and both are offered as code actions at the cursor too.

Moving between nodes uses the server's features and Neovim's jump list:

| to | use |
|---|---|
| go to what a `\ref`, `\uses`, `\cite` or `\input` names | `gd`; `gr` lists the references to a key |
| find a node by title, alias, tag or id | workspace symbols: `<leader>sS` in LazyVim, or `vim.lsp.buf.workspace_symbol()` |
| list what a node uses, or what uses it | `vim.lsp.buf.outgoing_calls()` and `vim.lsp.buf.incoming_calls()` |
| see what an id points to without leaving | inlay hints after each reference and inclusion; `<leader>uh` toggles them in LazyVim |
| go back and forward | `<C-o>` and `<C-i>`; `set jumpoptions+=stack` makes them behave like a browser's back and forward |

## Statusline

`require("loom").statusline()` returns the state of the node under the cursor, e.g. `rl-0004 accepted`, or an empty string outside a quilt.

## Tests

```
nvim --headless --noplugin -u tests/minimal_init.lua \
  -c "PlenaryBustedDirectory tests/ {minimal_init = 'tests/minimal_init.lua', sequential = true}"
```

Forty-eight busted-style tests over root detection, the key under the cursor, every command's argument vector, the client configuration, the language server's commands, the reshaping commands, the servers a session owns, and TeX's search path following the current buffer (checked through `kpsewhich` run from a quilt's `drafts/` when it is installed). The browser opener is injected. The serve tests stand a `python3 -m http.server` in for `loom serve`, in a terminal buffer and, when tmux is installed, in a private tmux server on its own socket, never the one the tests were started from; one test opens a node on a real `loom serve` over a copy of loom's demo quilt when `loom` is on the path. The reshaping commands are driven by a fake client, and by the real server over a copy of loom's synthetic quilt when `loom` and `loom-lsp` are both on the path.

Two scripts drive the real server against a real quilt:

```
LOOM_LSP=path/to/loom-lsp nvim --headless --noplugin -u tests/minimal_init.lua \
  -l scripts/smoke.lua <quilt-root> <file>     # attach, then print the diagnostics
LOOM_LSP=path/to/loom-lsp nvim --headless --noplugin -u tests/minimal_init.lua \
  -l scripts/probe.lua <file>                  # hover and go-to-definition at the first \ref
```
