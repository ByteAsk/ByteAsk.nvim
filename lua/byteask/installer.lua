-- lua/byteask/installer.lua
-- Detect a missing `byteask` binary and guide (or perform) installation.

local config = require('byteask.config')
local util = require('byteask.util')

local M = {}

local MANUAL_HINT = {
  'ByteAsk CLI not found on $PATH.',
  '',
  'Install it with:',
  '  pip install --upgrade byteask',
  '',
  'or (isolated):',
  '  pipx install byteask',
  '',
  'Then verify:  byteask doctor',
}

--- Print manual instructions and optionally offer to run the install command.
function M.guide()
  if not config.options.autoinstall_hint then
    vim.notify('ByteAsk CLI (`' .. util.bin_name() .. '`) not found on $PATH.', vim.log.levels.ERROR)
    return
  end

  vim.notify(table.concat(MANUAL_HINT, '\n'), vim.log.levels.WARN, { title = 'byteask.nvim' })

  local install_cmd = config.options.install_cmd
  if not install_cmd or #install_cmd == 0 then
    return
  end

  vim.ui.select({ 'Yes', 'No' }, {
    prompt = 'Run `' .. table.concat(install_cmd, ' ') .. '` now?',
  }, function(choice)
    if choice ~= 'Yes' then
      return
    end
    vim.notify('Installing ByteAsk…', vim.log.levels.INFO)
    vim.fn.jobstart(install_cmd, {
      on_exit = function(_, code)
        vim.schedule(function()
          if code == 0 and util.is_installed() then
            vim.notify('ByteAsk installed. Run :ByteAsk to start.', vim.log.levels.INFO)
          else
            vim.notify('ByteAsk install failed (code ' .. tostring(code) .. '). Install manually.', vim.log.levels.ERROR)
          end
        end)
      end,
    })
  end)
end

return M
