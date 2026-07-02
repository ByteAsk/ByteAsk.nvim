# byteask.nvim

Neovim integration for **[ByteAsk](https://byteask.ai)** — the Codex-style agentic
coding harness specialized for **C/C++** (compiler, disassembler, and debugger as
first-class agent tools).

This plugin drives the `byteask` CLI from inside Neovim:

- **Interactive TUI** in a floating window, side panel, or tab.
- **Headless commands** — `exec`, `review`, `apply` — that stream results into a
  scratch buffer and can apply the produced diff straight to your working tree.
- **Context sends** — pipe the current selection, file, or LSP diagnostics into a
  one-shot `exec` (e.g. "fix these compiler errors").
- **Session control** — resume/fork previous sessions.
- `:checkhealth byteask` and a lualine statusline component.

> Inspired by [`codex.nvim`](https://github.com/johnseth97/codex.nvim), rebuilt for
> ByteAsk's richer CLI surface (`exec --json`, `review`, `apply`, `resume`/`fork`).

## Requirements

- Neovim **0.9+**
- The `byteask` CLI on your `$PATH`:
  ```bash
  pip install --upgrade byteask   # or: pipx install byteask
  byteask login                   # authenticate once
  byteask doctor                  # verify install/auth/runtime
  ```

## Install

<details open><summary><b>lazy.nvim</b></summary>

```lua
{
  'ByteAsk/byteask.nvim',
  cmd = { 'ByteAsk', 'ByteAskExec', 'ByteAskReview', 'ByteAskResume' },
  keys = {
    { '<leader>bb', function() require('byteask').toggle() end, mode = { 'n', 't' }, desc = 'Toggle ByteAsk' },
    { '<leader>bx', ':ByteAskExec ', mode = 'n', desc = 'ByteAsk exec' },
    { '<leader>bx', ":'<,'>ByteAskExec ", mode = 'v', desc = 'ByteAsk exec (selection)' },
    { '<leader>bd', function() require('byteask').fix_diagnostics() end, desc = 'ByteAsk: fix diagnostics' },
    { '<leader>br', function() require('byteask').review() end, desc = 'ByteAsk review' },
  },
  opts = {
    layout = 'float',       -- 'float' | 'panel' | 'tab'
    -- model = 'gpt-5.5',   -- omit to use the ByteAsk default
    -- auto_apply = true,   -- apply exec diffs to the working tree automatically
  },
}
```
</details>

<details><summary><b>packer.nvim</b></summary>

```lua
use {
  'ByteAsk/byteask.nvim',
  config = function() require('byteask').setup{} end,
}
```
</details>

## Commands

| Command | Description |
|---|---|
| `:ByteAsk [prompt]` | Toggle the TUI; with args, open seeded with that prompt |
| `:ByteAskToggle` | Toggle the ByteAsk window (session survives when hidden) |
| `:ByteAskExec {instr}` | Headless `exec`. In visual mode, sends the selection as context |
| `:ByteAskFixDiagnostics` | Send current-buffer LSP/compiler diagnostics to `exec` for a fix |
| `:ByteAskReview` | Run `byteask review` on the repository |
| `:ByteAskApply` | Apply the latest agent diff to the working tree (`byteask apply`) |
| `:ByteAskResume[!]` | Resume a session (picker; `!` = most recent) |
| `:ByteAskFork[!]` | Fork a session (picker; `!` = most recent) |

Inside the ByteAsk window, `<C-q>` hides it (the session keeps running in the
background — reopen with `:ByteAsk`).

## Configuration

Defaults (pass any subset to `setup`/`opts`):

```lua
require('byteask').setup({
  cmd = 'byteask',            -- string or argv list; may include flags e.g. 'byteask --oss'
  args = {},                  -- extra CLI args always appended
  model = nil,                -- -m MODEL (nil = ByteAsk default)
  config = {},                -- -c key=value TOML overrides, e.g. { model_reasoning_effort = 'high' }

  layout = 'float',           -- 'float' | 'panel' | 'tab'
  width = 0.85, height = 0.85,-- float size (fraction of editor)
  panel_side = 'right',       -- 'left' | 'right'  (layout='panel')
  panel_width = 0.42,
  border = 'rounded',         -- 'single'|'double'|'rounded'|'none'|custom table
  start_insert = true,        -- enter terminal insert mode on open

  keymaps = { toggle = nil, quit = '<C-q>' },

  autoinstall_hint = true,    -- guide install when `byteask` is missing
  install_cmd = { 'pip', 'install', '--upgrade', 'byteask' },

  auto_apply = false,         -- run `byteask apply` after a successful exec
  notify_on_exit = true,      -- vim.notify when headless runs finish
})
```

### Statusline (lualine)

```lua
require('lualine').setup({
  sections = { lualine_x = { require('byteask').status() } },
})
```

## How it works

- The interactive TUI runs via `termopen({ 'byteask', ... })` in a managed window.
- Headless commands shell out to `byteask exec` / `review` / `apply` with
  `jobstart`, streaming stdout/stderr into the `byteask://output` scratch buffer.
- `resume`/`fork` re-launch the TUI with the corresponding subcommand (model/config
  overrides are omitted so the restored session keeps its own recorded settings).

## Roadmap

- Structured integration via `byteask app-server` (`--remote`) instead of terminal
  scraping — inline diffs, approvals, and streaming tool calls rendered natively.
- Consume `byteask exec --json` (JSONL events) for a real progress/tool-call UI.

## License

Apache-2.0
