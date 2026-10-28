-- Headless regression test for :ByteAskReview's scopes.
--
--   nvim --headless --clean -l tests/review_scope.lua
--
-- `byteask review` needs a scope flag or positional instructions; a bare
-- invocation exits with "Specify --uncommitted, --base, --commit, or provide
-- custom review instructions". The whole-repo scope therefore has to pass an
-- instruction instead of no arguments at all.
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
rawset(vim.fn, 'chansend', function()
  return 1
end)
rawset(vim.fn, 'chanclose', function() end)

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

-- Lets the next review start: run_headless refuses a second run while one is
-- in flight, and the stub job never exits on its own.
local function finish_run()
  captured.opts.on_exit(4242, 0)
  vim.wait(100, function()
    return false
  end)
  captured = {}
end

commands.review('uncommitted')
check(
  'uncommitted scope passes its flag',
  vim.tbl_contains(captured.argv or {}, '--uncommitted'),
  vim.inspect(captured.argv)
)
finish_run()

commands.review('repo')
local argv = captured.argv or {}
local last = argv[#argv]
check('whole-repo scope starts a review at all', argv[2] == 'review', vim.inspect(argv))
check(
  'whole-repo scope passes instructions instead of nothing',
  last ~= nil and last:sub(1, 2) ~= '--' and last:find('entire repository', 1, true) ~= nil,
  vim.inspect(argv)
)
finish_run()

-- Custom instruction string
commands.review('Check concurrency safety')
local custom_argv = captured.argv or {}
local custom_last = custom_argv[#custom_argv]
check(
  'custom review scope passes custom instructions',
  custom_last == 'Check concurrency safety',
  vim.inspect(custom_argv)
)
finish_run()

-- Invalid/empty scope starts no job
commands.review('   ')
check('blank review scope starts no job', captured.argv == nil)

-- Process failure recovery
local old_jobstart = vim.fn.jobstart
rawset(vim.fn, 'jobstart', function()
  return -1
end)
commands.review('repo')
rawset(vim.fn, 'jobstart', old_jobstart)
captured = {}
commands.review('repo')
check('headless runner recovers after failed jobstart', captured.argv ~= nil)
finish_run()

if failures > 0 then
  print(string.format('\n%d check(s) FAILED', failures))
  vim.cmd('cquit 1')
end
print('\nAll checks passed.')
vim.cmd('quit')
