-- plugin/byteask.lua
-- Loaded automatically by Neovim at startup. Registers the :ByteAsk* commands
-- so they work even if the user never calls require('byteask').setup().
-- Keymaps and non-default options still require setup().

if vim.g.loaded_byteask then
  return
end
vim.g.loaded_byteask = true

if vim.fn.has('nvim-0.9') == 0 then
  vim.schedule(function()
    vim.notify('byteask.nvim requires Neovim 0.9+', vim.log.levels.WARN)
  end)
  return
end

-- Register commands with default config; setup() re-registers with user config.
require('byteask')._register_commands()
