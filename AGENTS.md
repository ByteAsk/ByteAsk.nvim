# AGENTS.md — byteask.nvim

This file is for coding agents (Claude Code, Codex, etc.) working in this repo or
in a project that depends on it. Humans should read `README.md` instead; this file
assumes you already know how to run shell commands and just need the exact facts.

## What this repo is

A standalone Neovim plugin that drives the `byteask` CLI (a Codex-fork agentic
coding harness specialized for C/C++). It lives in its own repo — not a
subdirectory of a monorepo — because Neovim plugin managers (lazy.nvim, packer,
vim-plug) clone a whole repo and expect `lua/` + `plugin/` at its root; they
cannot install a subdirectory. The companion VS Code extension lives in the
sibling repo `ByteAsk/byteask-extensions` (`vscode-byteask/`), which has no such
constraint.

## If you're installing/using this plugin in a project

Add to the user's Neovim config (lazy.nvim shown; see `README.md` for packer):

```lua
{
  'ByteAsk/byteask.nvim',
  cmd = { 'ByteAsk', 'ByteAskExec', 'ByteAskReview', 'ByteAskResume' },
  opts = {},
}
```

The plugin requires the `byteask` CLI on `$PATH`:

```bash
pip install --upgrade byteask
byteask login
byteask doctor   # health check
```

Commands: `:ByteAsk [prompt]`, `:ByteAskExec {instr}` (range-aware — visual
selection becomes context), `:ByteAskReview` (scoped: uncommitted/base/commit/
repo), `:ByteAskApply`, `:ByteAskFixDiagnostics`, `:ByteAskResume[!]`,
`:ByteAskFork[!]`, `:ByteAskAgents`, `:ByteAskSessions`, `:ByteAskModel[!]`.
Full list and config options in `README.md`.

## If you're cutting a release

Releases are tag-triggered. There is no package registry step required —
Neovim plugin managers install by cloning the repo directly — so "release" here
means: cut a GitHub Release (changelog, pinnable version) and optionally mirror
to luarocks.org.

```bash
git tag -a vX.Y.Z -m "vX.Y.Z — <one-line summary>"
git push origin vX.Y.Z
```

This triggers `.github/workflows/release.yml`:
1. `github-release` job — creates the GitHub Release with auto-generated notes
2. `luarocks` job — publishes to luarocks.org *only if* the `LUAROCKS_API_KEY`
   secret is set; otherwise this step is skipped, not failed

Verify it landed:

```bash
gh run list --repo ByteAsk/ByteAsk.nvim --limit 3
gh release view vX.Y.Z --repo ByteAsk/ByteAsk.nvim
```

### CI (runs on every push, not just tags)

`.github/workflows/ci.yml` runs three jobs: `stylua --check .` (formatting),
`luacheck lua/ plugin/ --globals vim` (lint), and a headless Neovim load-test
that asserts all 11 `:ByteAsk*` commands register. Run these locally before
pushing to avoid a red CI:

```bash
stylua .                                    # auto-fix formatting
luacheck lua/ plugin/ --globals vim         # lint (brew install luarocks; luarocks install luacheck)
nvim --headless --clean --cmd "set rtp+=$(pwd)" \
  -c "lua require('byteask').setup({})" \
  -c "lua for _,n in ipairs({'ByteAsk','ByteAskToggle','ByteAskExec','ByteAskReview','ByteAskApply','ByteAskResume','ByteAskFork','ByteAskFixDiagnostics','ByteAskAgents','ByteAskSessions','ByteAskModel'}) do assert(vim.fn.exists(':'..n)==2, n..' not registered') end; print('ALL_COMMANDS_OK')" \
  -c "qa!"
```

### Required secrets (repo-level, `gh secret set <NAME> --repo ByteAsk/ByteAsk.nvim`)

| Secret | Required for | Where to get it | Notes |
|---|---|---|---|
| `LUAROCKS_API_KEY` | luarocks.org mirror | luarocks.org → account → API keys | Optional — the release still succeeds without it, it just skips this one step |

**You (the agent) cannot obtain these interactively.** If a secret is missing and
you need it for a release, tell the user exactly which one and where to get it
(the table above), then wait — do not guess a value or skip the step silently
without saying so.

Set a secret non-interactively once the user gives you the value:

```bash
printf '%s' '<value>' | gh secret set LUAROCKS_API_KEY --repo ByteAsk/ByteAsk.nvim
```

(`printf '%s' | gh secret set` avoids the value landing in shell history via a
literal argument or an `echo` with interpolation.)

### Workflow-authoring gotcha (already hit once, don't repeat it)

**GitHub Actions rejects `secrets.*` referenced directly inside a step-level
`if:` condition** — not a lint warning, a hard `startup_failure`: the entire
workflow file is rejected and shows `jobs: []` on *every* trigger, even ones
that shouldn't match. Standard YAML parsers (including `python3 -c "import
yaml"`) don't catch this because it's an Actions schema rule, not YAML syntax.

Wrong:
```yaml
steps:
  - if: ${{ secrets.LUAROCKS_API_KEY != '' }}   # invalid — will break the whole file
```

Right — route the secret through job-level `env` first:
```yaml
jobs:
  luarocks:
    env:
      LUAROCKS_API_KEY: ${{ secrets.LUAROCKS_API_KEY }}
    steps:
      - if: ${{ env.LUAROCKS_API_KEY != '' }}   # valid
```

Before pushing any workflow-file change, lint it locally — this catches
schema errors standard YAML parsing misses:

```bash
brew install actionlint   # one-time
actionlint .github/workflows/*.yml
```
