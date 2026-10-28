-- Headless regression tests for how :ByteAskExec transports editor context.
--
--   nvim --headless --clean -l tests/exec_stdin.lua
--
-- Two properties are checked here. The selection/diagnostics block must travel
-- on stdin rather than the command line: `byteask exec` appends piped stdin as
-- a `<stdin>` block, while Windows refuses to spawn a process whose command
-- line exceeds 32K characters. And stdin must always be closed, prompt-only
-- runs included, because `byteask exec` reads stdin to EOF before it starts.
-- Exits non-zero when any expectation fails.
local this = debug.getinfo(1, 'S').source:sub(2)
vim.opt.runtimepath:prepend(vim.fn.fnamemodify(this, ':p:h:h'))

require('byteask.config').options.notify_on_exit = false

local captured = {}

rawset(vim.fn, 'jobstart', function(argv, opts)
  captured.argv = argv
  captured.opts = opts
  return 4242
end)
rawset(vim.fn, 'chansend', function(id, data)
  captured.stdin = data
  return 1
end)
rawset(vim.fn, 'chanclose', function(_, stream)
  captured.closed = stream
end)

local failures = 0
local function check(name, ok, detail)
  if ok then
    print('ok - ' .. name)
  else
    failures = failures + 1
    print('FAIL - ' .. name .. (detail and ('\n  ' .. detail) or ''))
  end
end

local commands = require('byteask.commands')

-- Scenario A: instruction plus a selection big enough to blow the Windows
-- command-line limit on its own.
local context = string.rep('x', 40000)
commands.exec('Improve this code.', context)

local argv = captured.argv or {}
local longest = 0
for _, arg in ipairs(argv) do
  longest = math.max(longest, #arg)
end

check('the instruction stays on the command line', vim.tbl_contains(argv, 'Improve this code.'))
check('no command-line argument carries the context', longest < 1000, 'longest argument: ' .. longest)
check(
  'the context is written to stdin',
  captured.stdin == context,
  'stdin bytes: ' .. tostring(captured.stdin and #captured.stdin)
)
check('stdin is closed so the CLI sees EOF', captured.closed == 'stdin')

-- Scenario B: prompt only. `byteask exec` still waits for stdin EOF, so the
-- channel has to be closed even when nothing was sent. Finishing scenario A
-- through its on_exit clears the module's in-flight job; the short wait lets
-- the scheduled output callbacks run before we start the next run.
captured.opts.on_exit(4242, 0)
vim.wait(100, function()
  return false
end)
captured = {}
commands.exec('Explain this file.')

check('prompt-only run starts a job', captured.opts ~= nil)
check('prompt-only run sends no stdin data', captured.stdin == nil)
check('prompt-only run still closes stdin', captured.closed == 'stdin')

-- Scenario C: streaming stdout/stderr with embedded newlines and CRLF
-- should not throw buffer line set errors.
local on_data_ok = pcall(function()
  captured.opts.on_stdout(4242, { 'line 1\r\nline 2', 'line 3\nline 4' })
end)
check('multiline stdout chunk is accepted without error', on_data_ok)

captured.opts.on_exit(4242, 0)
vim.wait(100, function()
  return false
end)

-- Scenario D: failed jobstart does not leave the headless runner deadlocked.
local old_jobstart = vim.fn.jobstart
rawset(vim.fn, 'jobstart', function()
  return -1
end)
captured = {}
commands.exec('Failing command.')
check('failing jobstart does not capture stdin', captured.stdin == nil)

rawset(vim.fn, 'jobstart', old_jobstart)
captured = {}
commands.exec('Recovered command.')
check('subsequent execution succeeds after a failed jobstart', captured.opts ~= nil)

captured.opts.on_exit(4242, 0)
vim.wait(100, function()
  return false
end)

-- Scenario E: context-only exec defaults to instruction on command line
captured = {}
commands.exec(nil, 'auto context')
check(
  'context-only exec falls back to default instruction',
  vim.tbl_contains(captured.argv or {}, 'Improve this code.')
)
check('context-only exec routes context to stdin', captured.stdin == 'auto context')
check('context-only exec closes stdin', captured.closed == 'stdin')

captured.opts.on_exit(4242, 0)
vim.wait(100, function()
  return false
end)

if failures > 0 then
  print(string.format('\n%d check(s) FAILED', failures))
  vim.cmd('cquit 1')
end
print('\nAll checks passed.')
vim.cmd('quit')
