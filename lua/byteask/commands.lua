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

--- `byteask review` against the current repository.
function M.review()
  local argv = util.build_subcommand({ 'review' })
  run_headless(argv, { title = 'review' })
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
