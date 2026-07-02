-- lua/byteask/health.lua
-- `:checkhealth byteask` — verifies the CLI, version, and auth/runtime health.

local util = require('byteask.util')

local M = {}

-- Support both the modern (vim.health.*) and legacy (health.report_*) APIs.
local h = vim.health or require('health')
local ok = h.ok or h.report_ok
local warn = h.warn or h.report_warn
local err = h.error or h.report_error
local start = h.start or h.report_start
local info = h.info or h.report_info

function M.check()
  start('byteask.nvim')

  local bin = util.bin_name()
  if not util.is_installed() then
    err('`' .. bin .. '` not found on $PATH', {
      'Install with: pip install --upgrade byteask',
      'Or set opts.cmd to the correct executable path.',
    })
    return
  end
  ok('`' .. bin .. '` found: ' .. vim.fn.exepath(bin))

  -- Version.
  local ver = vim.fn.system({ bin, '--version' })
  if vim.v.shell_error == 0 then
    ok('version: ' .. vim.trim(ver))
  else
    warn('could not read `' .. bin .. ' --version`')
  end

  -- Deeper diagnosis via `byteask doctor` (config/auth/runtime).
  info('running `' .. bin .. ' doctor` …')
  local doctor = vim.fn.system({ bin, 'doctor' })
  if vim.v.shell_error == 0 then
    ok('doctor reported healthy')
    for _, line in ipairs(vim.split(vim.trim(doctor), '\n', { plain = true })) do
      info('  ' .. line)
    end
  else
    warn('`' .. bin .. ' doctor` reported issues:')
    for _, line in ipairs(vim.split(vim.trim(doctor), '\n', { plain = true })) do
      info('  ' .. line)
    end
  end
end

return M
