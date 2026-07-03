-- lua/byteask/commands.lua
-- Headless power-commands (exec / review / apply / resume / fork) and context sends.
-- The interactive terminal lives in terminal.lua; this module drives `byteask`
-- non-interactively and streams results into a scratch output buffer.

local config = require('byteask.config')
local util = require('byteask.util')

local M = {}

-- Reusable scratch output buffer for headless runs.
local out = { buf = nil, job = nil }

local function ensure_out_buffer()
  if out.buf and vim.api.nvim_buf_is_valid(out.buf) then
    return out.buf
  end
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_option(buf, 'bufhidden', 'hide')
  vim.api.nvim_buf_set_option(buf, 'filetype', 'byteask-output')
  vim.api.nvim_buf_set_name(buf, 'byteask://output')
  out.buf = buf
  return buf
end

local function open_out_window()
  local buf = ensure_out_buffer()
  -- Reuse a visible window showing the buffer if there is one.
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_get_buf(win) == buf then
      vim.api.nvim_set_current_win(win)
      return
    end
  end
  vim.cmd('botright 15split')
  vim.api.nvim_win_set_buf(0, buf)
  vim.api.nvim_win_set_option(0, 'wrap', true)
end

local function append(lines)
  local buf = ensure_out_buffer()
  if type(lines) == 'string' then
    lines = vim.split(lines, '\n', { plain = true })
  end
  vim.api.nvim_buf_set_lines(buf, -1, -1, false, lines)
  -- Keep the output window scrolled to the bottom.
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_get_buf(win) == buf then
      local n = vim.api.nvim_buf_line_count(buf)
      vim.api.nvim_win_set_cursor(win, { n, 0 })
    end
  end
end

local function clear_out()
  local buf = ensure_out_buffer()
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, {})
end

--- Run `byteask apply` to apply the latest agent diff to the working tree.
--- No common flags: `apply` only performs a git-apply and rejects model/-c flags.
---@param on_done fun(ok: boolean)|nil
function M.apply(on_done)
  local argv = util.base_cmd()
  argv[#argv + 1] = 'apply'
  vim.fn.jobstart(argv, {
    cwd = vim.loop.cwd(),
    on_exit = function(_, code)
      vim.schedule(function()
        local ok = code == 0
        if ok then
          vim.cmd('checktime') -- reload any buffers changed on disk
          vim.notify('ByteAsk: applied latest diff to working tree.', vim.log.levels.INFO)
        else
          vim.notify('ByteAsk apply failed (code ' .. tostring(code) .. ').', vim.log.levels.ERROR)
        end
        if on_done then
          on_done(ok)
        end
      end)
    end,
  })
end

--- Generic headless runner: streams stdout/stderr into the output buffer.
---@param argv string[]
---@param opts table|nil { title=string, stdin=string, apply_after=boolean }
local function run_headless(argv, opts)
  opts = opts or {}
  if out.job then
    vim.notify('ByteAsk: a headless run is already in progress.', vim.log.levels.WARN)
    return
  end

  open_out_window()
  clear_out()
  append({ '$ ' .. table.concat(argv, ' '), '' })

  local function on_data(_, data)
    if not data then
      return
    end
    local chunk = {}
    for _, line in ipairs(data) do
      if line ~= '' then
        chunk[#chunk + 1] = line
      end
    end
    if #chunk > 0 then
      vim.schedule(function()
        append(chunk)
      end)
    end
  end

  out.job = vim.fn.jobstart(argv, {
    cwd = vim.loop.cwd(),
    stdout_buffered = false,
    on_stdout = on_data,
    on_stderr = on_data,
    on_exit = function(_, code)
      out.job = nil
      vim.schedule(function()
        append({ '', '[byteask ' .. (opts.title or 'run') .. ' exited: ' .. code .. ']' })
        if code == 0 and opts.apply_after then
          M.apply()
        elseif config.options.notify_on_exit then
          vim.notify('ByteAsk ' .. (opts.title or 'run') .. ' finished (code ' .. code .. ').', vim.log.levels.INFO)
        end
      end)
    end,
  })

  if opts.stdin and opts.stdin ~= '' then
    vim.fn.chansend(out.job, opts.stdin)
    vim.fn.chanclose(out.job, 'stdin')
  end
end

--- `byteask exec` with a prompt. Streams JSONL-free text output.
---@param prompt string
---@param extra_context string|nil prepended to the prompt as an fenced block
function M.exec(prompt, extra_context)
  if (not prompt or prompt == '') and (not extra_context or extra_context == '') then
    vim.notify('ByteAsk exec: empty prompt.', vim.log.levels.WARN)
    return
  end
  local full = prompt or ''
  if extra_context and extra_context ~= '' then
    full = full .. '\n\n```\n' .. extra_context .. '\n```'
  end
  local argv = util.build_subcommand({ 'exec' }, { full })
  run_headless(argv, { title = 'exec', apply_after = config.options.auto_apply })
end

local function run_review(flags)
  local argv = util.build_subcommand({ 'review' }, flags)
  run_headless(argv, { title = 'review' })
end

--- `byteask review`, scoped to match what the CLI actually supports
--- (`--uncommitted` / `--base <branch>` / `--commit <sha>` / whole repo).
--- With no scope, prompts via vim.ui.select.
---@param scope string|nil one of 'uncommitted' | 'base' | 'commit' | 'repo'
function M.review(scope)
  if not scope then
    vim.ui.select(
      { 'Uncommitted changes', 'Against base branch', 'Specific commit', 'Whole repo' },
      { prompt = 'ByteAsk review scope:' },
      function(choice)
        if not choice then
          return
        end
        local scope_of = {
          ['Uncommitted changes'] = 'uncommitted',
          ['Against base branch'] = 'base',
          ['Specific commit'] = 'commit',
          ['Whole repo'] = 'repo',
        }
        M.review(scope_of[choice])
      end
    )
    return
  end

  if scope == 'uncommitted' then
    run_review({ '--uncommitted' })
  elseif scope == 'base' then
    vim.ui.input({ prompt = 'Base branch: ', default = 'main' }, function(branch)
      if branch and branch ~= '' then
        run_review({ '--base', branch })
      end
    end)
  elseif scope == 'commit' then
    vim.ui.input({ prompt = 'Commit SHA: ' }, function(sha)
      if sha and sha ~= '' then
        run_review({ '--commit', sha })
      end
    end)
  else
    run_review({})
  end
end

--- Locate (or offer to create) the nearest AGENTS.md, walking up from the
--- current buffer's directory. Pure editor action: no byteask process is
--- involved, since AGENTS.md is picked up by the agent on its next turn.
function M.agents()
  local abs = vim.api.nvim_buf_get_name(0)
  local start_dir = (abs and abs ~= '') and vim.fn.fnamemodify(abs, ':p:h') or vim.loop.cwd()
  local found = util.find_upward(start_dir, 'AGENTS.md')
  if found then
    vim.cmd('edit ' .. vim.fn.fnameescape(found))
    return
  end

  local target = vim.loop.cwd() .. '/AGENTS.md'
  vim.ui.select({ 'Yes', 'No' }, {
    prompt = 'No AGENTS.md found. Create one at ' .. vim.fn.fnamemodify(target, ':.') .. '?',
  }, function(choice)
    if choice ~= 'Yes' then
      return
    end
    vim.fn.writefile({
      '# AGENTS.md',
      '',
      '<!-- Instructions/tips for ByteAsk when working in this repo or directory. -->',
      '<!-- Deeper AGENTS.md files override this one; direct user instructions override both. -->',
      '',
    }, target)
    vim.cmd('edit ' .. vim.fn.fnameescape(target))
  end)
end

--- Session lifecycle beyond resume/fork: browse all sessions (delegates to
--- byteask's own picker), or archive/unarchive/delete by id or name.
function M.sessions()
  vim.ui.select(
    { 'Browse all sessions', 'Archive a session', 'Unarchive a session', 'Delete a session' },
    { prompt = 'ByteAsk sessions:' },
    function(choice)
      if not choice then
        return
      end
      if choice == 'Browse all sessions' then
        local argv = util.base_cmd()
        argv[#argv + 1] = 'resume'
        argv[#argv + 1] = '--all'
        require('byteask.terminal').open_argv(argv)
        return
      end

      local subcommand = ({
        ['Archive a session'] = 'archive',
        ['Unarchive a session'] = 'unarchive',
        ['Delete a session'] = 'delete',
      })[choice]

      vim.ui.input({ prompt = 'Session id or name to ' .. subcommand .. ': ' }, function(id)
        if not id or id == '' then
          return
        end
        -- No common flags: archive/unarchive/delete only take a session id,
        -- same precedent as M.apply ("No common flags: apply only performs a
        -- git-apply and rejects model/-c flags") — so this builds off
        -- base_cmd(), not build_subcommand().
        local argv = util.base_cmd()
        argv[#argv + 1] = subcommand
        argv[#argv + 1] = id
        local stderr_lines = {}
        vim.fn.jobstart(argv, {
          cwd = vim.loop.cwd(),
          on_stderr = function(_, data)
            for _, line in ipairs(data or {}) do
              if line ~= '' then
                stderr_lines[#stderr_lines + 1] = line
              end
            end
          end,
          on_exit = function(_, code)
            vim.schedule(function()
              if code == 0 then
                vim.notify('ByteAsk: ' .. subcommand .. 'd session ' .. id .. '.', vim.log.levels.INFO)
              else
                local detail = #stderr_lines > 0 and (': ' .. table.concat(stderr_lines, ' ')) or ''
                vim.notify(
                  'ByteAsk ' .. subcommand .. ' failed (code ' .. code .. ')' .. detail .. '.',
                  vim.log.levels.ERROR
                )
              end
            end)
          end,
        })
      end)
    end
  )
end

--- Interactively set (or, with clear=true, reset) the model / -c overrides
--- used by every subsequent invocation. Persists for the nvim session; falls
--- back to config.lua defaults when left blank or cleared.
---@param clear boolean|nil
function M.model(clear)
  if clear then
    config.clear_override()
    vim.notify('ByteAsk: cleared model/config overrides.', vim.log.levels.INFO)
    return
  end

  local current_model = config.override.model or config.options.model or ''
  vim.ui.input({
    prompt = 'ByteAsk model (blank = default'
      .. (current_model ~= '' and (', current: ' .. current_model) or '')
      .. '): ',
    default = current_model,
  }, function(model)
    if model == nil then
      return -- cancelled: leave the override untouched
    end

    -- Commit the model right away so cancelling the (optional) -c prompt
    -- below can't silently discard it; the existing config override carries
    -- over unless the next prompt explicitly replaces it.
    config.set_override({ model = model ~= '' and model or nil, config = config.override.config })

    local current_cfg = {}
    for key, value in pairs(config.override.config or {}) do
      current_cfg[#current_cfg + 1] = string.format('%s=%s', key, tostring(value))
    end
    table.sort(current_cfg)

    vim.ui.input({
      prompt = 'ByteAsk -c overrides, comma-separated key=value (blank = none): ',
      default = table.concat(current_cfg, ','),
    }, function(cfg_str)
      if cfg_str == nil then
        vim.notify('ByteAsk: model override set; config overrides left unchanged.', vim.log.levels.INFO)
        return -- cancelled: keep the config override as it was
      end
      local cfg = {}
      if cfg_str ~= '' then
        for pair in cfg_str:gmatch('[^,]+') do
          local key, value = pair:match('^%s*([%w_%.%-]+)%s*=%s*(.-)%s*$')
          if key and value then
            cfg[key] = value
          else
            vim.notify(
              "ByteAsk: ignoring malformed -c entry '" .. pair .. "' (expected key=value).",
              vim.log.levels.WARN
            )
          end
        end
      end
      -- Replaces the config override wholesale (blank clears it entirely) —
      -- see config.set_override's docstring for why this can't be a merge.
      config.set_override({ model = config.override.model, config = cfg })
      vim.notify('ByteAsk: model/config override set (use :ByteAskModel! to clear).', vim.log.levels.INFO)
    end)
  end)
end

--- Ask ByteAsk to fix the current buffer's diagnostics via exec.
function M.fix_diagnostics()
  local diags = util.diagnostics_block(0)
  if diags == '' then
    vim.notify('ByteAsk: no diagnostics in the current buffer.', vim.log.levels.INFO)
    return
  end
  local file = util.current_relpath() or '<current file>'
  local prompt = string.format(
    'Fix the following compiler/linter diagnostics in %s. Make the minimal correct change and keep the build green:',
    file
  )
  M.exec(prompt, diags)
end

--- Send the current visual selection to exec with an instruction.
---@param instruction string
function M.exec_selection(instruction)
  local sel = util.visual_selection()
  if sel == '' then
    vim.notify('ByteAsk: no visual selection captured.', vim.log.levels.WARN)
    return
  end
  local file = util.current_relpath() or '<buffer>'
  M.exec(instruction .. ' (from ' .. file .. ')', sel)
end

--- Resume a previous interactive session in the terminal.
--- `last == true` resumes the most recent; otherwise opens the session picker.
--- Model/-c overrides are intentionally omitted — a resumed session keeps its
--- own recorded model/config.
---@param last boolean|nil
function M.resume(last)
  local argv = util.base_cmd()
  argv[#argv + 1] = 'resume'
  if last then
    argv[#argv + 1] = '--last'
  end
  require('byteask.terminal').open_argv(argv)
end

--- Fork a previous interactive session (picker, or --last).
---@param last boolean|nil
function M.fork(last)
  local argv = util.base_cmd()
  argv[#argv + 1] = 'fork'
  if last then
    argv[#argv + 1] = '--last'
  end
  require('byteask.terminal').open_argv(argv)
end

return M
