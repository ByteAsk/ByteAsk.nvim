-- lua/byteask/init.lua
-- Public API + user-command / keymap registration for byteask.nvim.
--
-- ByteAsk is a Codex-style agentic coding harness specialized for C/C++.
-- This plugin drives the `byteask` CLI from Neovim: an interactive terminal
-- for the TUI, plus headless commands (exec / review / apply) that stream
-- results and can apply the produced diff to your working tree.

local config = require('byteask.config')
local terminal = require('byteask.terminal')
local commands = require('byteask.commands')
local state = require('byteask.state')

local M = {}

-- ── Public API (stable surface for keymaps / lua callers) ──────────────────
M.open = function(prompt)
  terminal.open(prompt)
end
M.close = function()
  terminal.close()
end
M.toggle = function()
  terminal.toggle()
end
M.exec = function(prompt, ctx)
  commands.exec(prompt, ctx)
end
M.review = function(scope)
  commands.review(scope)
end
M.apply = function()
  commands.apply()
end
M.fix_diagnostics = function()
  commands.fix_diagnostics()
end
M.resume = function(last)
  commands.resume(last)
end
M.fork = function(last)
  commands.fork(last)
end
M.agents = function()
  commands.agents()
end
M.sessions = function()
  commands.sessions()
end
M.model = function(clear)
  commands.model(clear)
end

-- ── Statusline helper (lualine-friendly) ───────────────────────────────────
function M.statusline()
  if state.job_alive() and not state.win_visible() then
    return '[ByteAsk ⏳]'
  elseif state.job_alive() then
    return '[ByteAsk]'
  end
  return ''
end

function M.status()
  return {
    function()
      return M.statusline()
    end,
    cond = function()
      return M.statusline() ~= ''
    end,
    icon = '',
    color = { fg = '#86AEA5' }, -- ByteAsk brand green
  }
end

-- ── Command registration ────────────────────────────────────────────────────
-- Public so plugin/byteask.lua can register commands at startup (idempotent:
-- nvim_create_user_command overwrites), making :ByteAsk work without setup().
function M._register_commands()
  local cmd = vim.api.nvim_create_user_command

  -- Interactive TUI. Optional args become the seed prompt.
  cmd('ByteAsk', function(a)
    if a.args and a.args ~= '' then
      terminal.open(a.args)
    else
      terminal.toggle()
    end
  end, { nargs = '*', desc = 'Toggle ByteAsk, or open seeded with a prompt' })

  cmd('ByteAskToggle', function()
    terminal.toggle()
  end, { desc = 'Toggle the ByteAsk window' })

  -- Headless exec. Range-aware: with a visual selection, the selection is sent
  -- as context and the args are the instruction.
  cmd('ByteAskExec', function(a)
    if a.range > 0 then
      commands.exec_selection(a.args ~= '' and a.args or 'Improve this code.')
    else
      commands.exec(a.args)
    end
  end, { nargs = '*', range = true, desc = 'Run byteask exec (headless); range = send selection as context' })

  cmd('ByteAskReview', function()
    commands.review() -- no scope: prompts (uncommitted / base branch / commit / whole repo)
  end, { desc = 'Run byteask review, scoped via a prompt' })
  cmd('ByteAskApply', function()
    commands.apply()
  end, { desc = 'Apply the latest ByteAsk diff to the working tree' })
  cmd('ByteAskFixDiagnostics', function()
    commands.fix_diagnostics()
  end, { desc = 'Ask ByteAsk to fix the current buffer diagnostics' })

  cmd('ByteAskResume', function(a)
    commands.resume(a.bang) -- :ByteAskResume! resumes the most recent; bare opens picker
  end, { bang = true, desc = 'Resume a ByteAsk session (! = most recent)' })

  cmd('ByteAskFork', function(a)
    commands.fork(a.bang)
  end, { bang = true, desc = 'Fork a ByteAsk session (! = most recent)' })

  cmd('ByteAskAgents', function()
    commands.agents()
  end, { desc = 'Open (or create) the nearest AGENTS.md to steer ByteAsk' })

  cmd('ByteAskSessions', function()
    commands.sessions()
  end, { desc = 'Browse, archive, unarchive, or delete ByteAsk sessions' })

  cmd('ByteAskModel', function(a)
    commands.model(a.bang) -- :ByteAskModel! clears the override
  end, { bang = true, desc = 'Set (or ! = clear) a model/-c override for future ByteAsk invocations' })
end

local function register_keymaps()
  local km = config.options.keymaps or {}
  if km.toggle then
    vim.keymap.set('n', km.toggle, function()
      terminal.toggle()
    end, { noremap = true, silent = true, desc = 'Toggle ByteAsk' })
  end
end

--- Entry point. Call once from your plugin manager's config.
---@param user table|nil
function M.setup(user)
  config.setup(user)
  M._register_commands()
  register_keymaps()
  return M
end

-- Allow `require('byteask')(opts)` as sugar for `.setup(opts)`.
return setmetatable(M, {
  __call = function(_, opts)
    M.setup(opts)
    return M
  end,
})
