-- Headless regression test for :ByteAskApply and the CLI's required task id.
--
--   nvim --headless --clean -l tests/apply_task_id.lua
--
-- `byteask apply` takes a mandatory `<TASK_ID>` positional; running it bare
-- exits 2 with a clap usage error, so the plugin has to prompt for the id (or
-- take it as an argument) instead of spawning the command without one.
-- Exits non-zero when any expectation fails.
local this = debug.getinfo(1, 'S').source:sub(2)
vim.opt.runtimepath:prepend(vim.fn.fnamemodify(this, ':p:h:h'))

local config = require('byteask.config')
config.options.notify_on_exit = false

local jobs = {}
local job_opts = {}
rawset(vim.fn, 'jobstart', function(argv, opts)
  jobs[#jobs + 1] = argv
  job_opts[#job_opts + 1] = opts
  return 4242
end)
rawset(vim.fn, 'chansend', function()
  return 1
end)
rawset(vim.fn, 'chanclose', function() end)

local prompt_seen, default_seen, answer
rawset(vim.ui, 'input', function(opts, cb)
  prompt_seen = opts.prompt
  default_seen = opts.default
  cb(answer)
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

commands.apply('task-123')
local argv = jobs[#jobs] or {}
check('an explicit id is forwarded as the positional', argv[2] == 'apply' and argv[3] == 'task-123', vim.inspect(argv))
check('no id typed means no prompt', prompt_seen == nil)

config.options.model = 'some-model'
commands.apply('task-456')
check('apply never gets a -m flag', not vim.tbl_contains(jobs[#jobs], '-m'), vim.inspect(jobs[#jobs]))
config.options.model = nil

answer = 'task-789'
commands.apply()
check('a missing id prompts for one', prompt_seen ~= nil)
local applied = jobs[#jobs] or {}
check('the typed id is applied', applied[#applied] == 'task-789', vim.inspect(applied))

local before = #jobs
answer = ''
commands.apply()
check('a blank id starts no job', #jobs == before)

-- Session ID capture from headless exec output
config.options.auto_apply = true
commands.exec('Generate changes.')
local last_exec = job_opts[#job_opts]
if last_exec and last_exec.on_stdout then
  last_exec.on_stdout(4242, { 'session id: task-uuid-999', 'generating patch...' })
end
if last_exec and last_exec.on_exit then
  last_exec.on_exit(4242, 0)
  vim.wait(100, function()
    return false
  end)
end
config.options.auto_apply = false

local auto_applied = jobs[#jobs] or {}
check(
  'auto_apply applies the captured session id',
  auto_applied[2] == 'apply' and auto_applied[3] == 'task-uuid-999',
  vim.inspect(auto_applied)
)

-- Default populated in prompt
prompt_seen, default_seen, answer = nil, nil, nil
commands.apply()
check('input prompt defaults to last captured task id', default_seen == 'task-uuid-999')

-- Spawn failure calls on_done(false)
local old_jobstart = vim.fn.jobstart
rawset(vim.fn, 'jobstart', function()
  return -1
end)
local done_result = nil
commands.apply('task-fail', function(ok)
  done_result = ok
end)
check('spawn failure calls on_done(false)', done_result == false)
rawset(vim.fn, 'jobstart', old_jobstart)

if failures > 0 then
  print(string.format('\n%d check(s) FAILED', failures))
  vim.cmd('cquit 1')
end
print('\nAll checks passed.')
vim.cmd('quit')
