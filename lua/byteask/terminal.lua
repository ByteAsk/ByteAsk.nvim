-- lua/byteask/terminal.lua
-- Window/panel/tab management + the interactive ByteAsk terminal job.

local config = require('byteask.config')
local state = require('byteask.state')
local util = require('byteask.util')

local M = {}

local BORDER_STYLES = {
  single = 'single',
  double = 'double',
  rounded = 'rounded',
  none = 'none',
}

local function resolve_border()
  local b = config.options.border
  if type(b) == 'table' then
    return b
  end
  return BORDER_STYLES[b] or 'rounded'
end

--- Create (or reuse) the terminal buffer and wire the in-window quit keymap.
local function ensure_buffer()
  if state.buf and vim.api.nvim_buf_is_valid(state.buf) then
    return state.buf
  end
  local buf = vim.api.nvim_create_buf(false, false)
  vim.api.nvim_buf_set_option(buf, 'bufhidden', 'hide')
  vim.api.nvim_buf_set_option(buf, 'swapfile', false)

  local quit = config.options.keymaps.quit
  if quit then
    -- From terminal mode: drop to normal first, then close.
    vim.api.nvim_buf_set_keymap(
      buf, 't', quit,
      [[<C-\><C-n><cmd>lua require('byteask').close()<CR>]],
      { noremap = true, silent = true }
    )
    vim.api.nvim_buf_set_keymap(
      buf, 'n', quit,
      [[<cmd>lua require('byteask').close()<CR>]],
      { noremap = true, silent = true }
    )
  end
  state.buf = buf
  return buf
end

local function open_float()
  local width = math.floor(vim.o.columns * config.options.width)
  local height = math.floor(vim.o.lines * config.options.height)
  local row = math.floor((vim.o.lines - height) / 2)
  local col = math.floor((vim.o.columns - width) / 2)
  state.win = vim.api.nvim_open_win(state.buf, true, {
    relative = 'editor',
    width = math.max(width, 1),
    height = math.max(height, 1),
    row = row,
    col = col,
    style = 'minimal',
    border = resolve_border(),
    title = ' ByteAsk ',
    title_pos = 'center',
  })
end

local function open_panel()
  local side = config.options.panel_side == 'left' and 'aboveleft' or 'belowright'
  vim.cmd(side .. ' vsplit')
  local win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(win, state.buf)
  local width = math.floor(vim.o.columns * config.options.panel_width)
  vim.api.nvim_win_set_width(win, math.max(width, 20))
  state.win = win
end

local function open_tab()
  vim.cmd('tabnew')
  local win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(win, state.buf)
  state.win = win
end

local function show_window()
  local layout = config.options.layout
  if layout == 'panel' then
    open_panel()
  elseif layout == 'tab' then
    open_tab()
  else
    open_float()
  end
end

--- Spawn the interactive ByteAsk job into the current window's buffer if not running.
---@param argv string[] fully-built command line
local function ensure_job(argv)
  if state.job then
    return
  end
  state.job = vim.fn.termopen(argv, {
    cwd = vim.loop.cwd(),
    on_exit = function(_, code)
      state.reset()
      if code and code ~= 0 and config.options.notify_on_exit then
        vim.schedule(function()
          vim.notify('ByteAsk exited (code ' .. code .. ')', vim.log.levels.INFO)
        end)
      end
    end,
  })
  vim.b[state.buf].byteask = true
  vim.api.nvim_buf_set_option(state.buf, 'filetype', 'byteask')
end

--- Open the ByteAsk terminal with an explicit argv (creating/reusing the session).
--- Prefer M.open() for the normal interactive flow; this is for resume/fork.
---@param argv string[]
function M.open_argv(argv)
  local installer = require('byteask.installer')
  if not util.is_installed() then
    installer.guide()
    return
  end

  if state.win_visible() then
    vim.api.nvim_set_current_win(state.win)
    return
  end

  ensure_buffer()
  show_window()
  ensure_job(argv)

  if config.options.start_insert then
    vim.cmd('startinsert')
  end
end

--- Open the ByteAsk terminal (creating/reusing the session), optionally seeded.
---@param prompt string|nil
function M.open(prompt)
  M.open_argv(util.build_interactive(prompt))
end

--- Hide the window but keep the session running in the background.
function M.close()
  if state.win_visible() then
    vim.api.nvim_win_close(state.win, true)
  end
  state.forget_win()
end

--- Toggle window visibility.
function M.toggle()
  if state.win_visible() then
    M.close()
  else
    M.open()
  end
end

return M
