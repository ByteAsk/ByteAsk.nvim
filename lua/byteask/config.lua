-- lua/byteask/config.lua
-- Default configuration and merge logic for byteask.nvim.

local M = {}

--- Default configuration. Every field can be overridden via `require('byteask').setup{...}`.
M.defaults = {
  -- Executable used to launch ByteAsk. String or list (argv). If a bare string
  -- with no spaces, it is treated as the binary name and looked up on $PATH.
  cmd = 'byteask',

  -- Extra CLI args always appended to the base command (e.g. { '--oss' }).
  args = {},

  -- Model passed via `-m`. nil = ByteAsk default.
  model = nil,

  -- Config overrides passed as repeated `-c key=value` (dotted TOML paths).
  -- e.g. { ['model_reasoning_effort'] = 'high' }
  config = {},

  -- Window presentation: 'float' | 'panel' | 'tab'.
  layout = 'float',

  -- Float geometry (fractions of the editor). Only used when layout == 'float'.
  width = 0.85,
  height = 0.85,

  -- Panel side + width fraction. Only used when layout == 'panel'.
  panel_side = 'right', -- 'left' | 'right'
  panel_width = 0.42,

  -- Float border: 'single' | 'double' | 'rounded' | 'none' | custom table.
  border = 'rounded',

  -- Auto-enter terminal insert mode when the window opens.
  start_insert = true,

  -- Keymaps. Set a value to nil to disable that mapping.
  keymaps = {
    toggle = nil,   -- global normal-mode map to toggle (e.g. '<leader>bb'); nil = none
    quit = '<C-q>', -- inside the ByteAsk window: close it (keeps job alive)
  },

  -- If the `byteask` binary is missing, show guided install instructions.
  autoinstall_hint = true,

  -- Command to attempt an automatic install when the binary is missing.
  -- Set to nil to only print manual instructions.
  install_cmd = { 'pip', 'install', '--upgrade', 'byteask' },

  -- When sending editor context (selection/file/diagnostics) into `exec`,
  -- automatically run `byteask apply` afterwards to apply the produced diff.
  auto_apply = false,

  -- Notify via vim.notify on job completion for headless (exec/review) runs.
  notify_on_exit = true,
}

-- The active, merged configuration. Populated by M.setup().
M.options = vim.deepcopy(M.defaults)

--- Merge user options over defaults.
---@param user table|nil
---@return table merged options
function M.setup(user)
  M.options = vim.tbl_deep_extend('force', vim.deepcopy(M.defaults), user or {})
  return M.options
end

return M
