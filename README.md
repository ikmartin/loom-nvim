# loom-nvim

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
    serve_url = "http://127.0.0.1:8000",
    serve = "auto",             -- where :LoomServe runs: "auto", "tmux" or "terminal"
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
| `:LoomAccept [key]` | record an acceptance for the key under the cursor, after confirming |
| `:LoomServe` | start `loom serve` in a tmux pane or a terminal split (see below) |
| `:LoomOpen [key]` | open the node under the cursor in arras |
| `:LoomBundle [key]` | the standalone bundle for a key, in a scratch buffer |
| `:LoomDeps [key]` | what the key depends on, and what it is related to |

## Where the server runs

`:LoomServe` runs `loom serve` beside the editor and leaves the cursor in the file you were editing. With `serve = "auto"`:

- **Neovim inside tmux** (`$TMUX` is set): a tmux pane below Neovim's own. The pane outlives Neovim, so quitting the editor does not stop the server; stop it with `Ctrl-C` in the pane and close the pane with `prefix x`. A server that exits, for instance because the port is in use, leaves its output in the pane.
- **Neovim outside tmux**, or no tmux on the machine: a terminal buffer in a split at the bottom. Stop it with `Ctrl-C` in terminal mode or `:bd!` in that window; quitting Neovim stops it too.

Running the command again while the server is up only says where it is running; after it has exited, the tmux pane is reused. `serve = "terminal"` always takes the split, and `serve = "tmux"` warns when it cannot have a pane.

## Statusline

`require("loom").statusline()` returns the state of the node under the cursor, e.g. `rl-0004 accepted`, or an empty string outside a quilt.

## Tests

```
nvim --headless --noplugin -u tests/minimal_init.lua \
  -c "PlenaryBustedDirectory tests/ {minimal_init = 'tests/minimal_init.lua'}"
```

Twenty-five busted-style tests over root detection, the key under the cursor, every command's argument vector, the client configuration, and where the server runs. No loom process is run and the browser opener is injected; the serve tests start `sleep` and `sh` in a terminal buffer, and in a private tmux server on its own socket when tmux is installed, never the one the tests were started from.

Two scripts drive the real server against a real quilt:

```
LOOM_LSP=path/to/loom-lsp nvim --headless --noplugin -u tests/minimal_init.lua \
  -l scripts/smoke.lua <quilt-root> <file>     # attach, then print the diagnostics
LOOM_LSP=path/to/loom-lsp nvim --headless --noplugin -u tests/minimal_init.lua \
  -l scripts/probe.lua <file>                  # hover and go-to-definition at the first \ref
```
