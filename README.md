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
| `:LoomServe` | start `loom serve` in a terminal split |
| `:LoomOpen [key]` | open the node under the cursor in arras |
| `:LoomBundle [key]` | the standalone bundle for a key, in a scratch buffer |
| `:LoomDeps [key]` | what the key depends on, and what it is related to |

## Statusline

`require("loom").statusline()` returns the state of the node under the cursor, e.g. `rl-0004 accepted`, or an empty string outside a quilt.

## Tests

```
nvim --headless --noplugin -u tests/minimal_init.lua \
  -c "PlenaryBustedDirectory tests/ {minimal_init = 'tests/minimal_init.lua'}"
```

Seventeen busted-style tests over root detection, the key under the cursor, every command's argument vector, and the client configuration. They start nothing: the browser opener is injected and no loom process is run.

Two scripts drive the real server against a real quilt:

```
LOOM_LSP=path/to/loom-lsp nvim --headless --noplugin -u tests/minimal_init.lua \
  -l scripts/smoke.lua <quilt-root> <file>     # attach, then print the diagnostics
LOOM_LSP=path/to/loom-lsp nvim --headless --noplugin -u tests/minimal_init.lua \
  -l scripts/probe.lua <file>                  # hover and go-to-definition at the first \ref
```
