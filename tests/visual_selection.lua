-- Headless regression tests for the visual-selection context helper.
--
--   nvim --headless --clean -l tests/visual_selection.lua
--
-- Exits non-zero when any expectation fails.
local this = debug.getinfo(1, 'S').source:sub(2)
vim.opt.runtimepath:prepend(vim.fn.fnamemodify(this, ':p:h:h'))

local util = require('byteask.util')

local failures = 0

local function check(name, want, got)
  if got == want then
    print('ok - ' .. name)
  else
    failures = failures + 1
    print(string.format('FAIL - %s\n  want: %s\n  got:  %s', name, vim.inspect(want), vim.inspect(got)))
  end
end

--- Fill a fresh buffer with `lines`, replay `keys` from normal mode, and
--- return what the command handling would use as the prompt context.
local function select(lines, keys)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_current_buf(buf)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.api.nvim_win_set_cursor(0, { 1, 0 })
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>' .. keys, true, false, true), 'x', false)
  return util.visual_selection()
end

check(
  'blockwise selection is the rectangle on every line',
  'ph\nta\nm',
  select({ 'alphabet', 'beta', 'gam' }, 'gg02l<C-v>2j2l<Esc>')
)
check(
  'blockwise $ extends to the end of every line from the block column',
  'lphabet\neta\nam',
  select({ 'alphabet', 'beta', 'gam' }, 'gg0l<C-v>2j$<Esc>')
)
check(
  'linewise selection is the whole lines',
  'alpha\nbeta\ngamma',
  select({ 'alpha', 'beta', 'gamma' }, 'gg0V2j<Esc>')
)
check(
  'charwise selection is the continuous range',
  'alpha\nbeta\ngam',
  select({ 'alpha', 'beta', 'gamma' }, 'gg0v2j2l<Esc>')
)

if failures > 0 then
  print(string.format('\n%d check(s) FAILED', failures))
  vim.cmd('cquit 1')
end
print('\nAll checks passed.')
vim.cmd('quit')
