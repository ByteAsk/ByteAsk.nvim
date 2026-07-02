-- lua/byteask/state.lua
-- Mutable runtime state for the single ByteAsk terminal instance.

local M = {
  buf = nil, -- terminal buffer handle
  win = nil, -- window handle currently displaying the buffer (nil when hidden)
  job = nil, -- terminal job id (nil when no session running)
}

--- True when a ByteAsk terminal session is alive (running in the background or foreground).
function M.job_alive()
  return M.job ~= nil and M.buf ~= nil and vim.api.nvim_buf_is_valid(M.buf)
end

--- True when the ByteAsk window is currently visible.
function M.win_visible()
  return M.win ~= nil and vim.api.nvim_win_is_valid(M.win)
end

--- Reset window handle only (buffer/job survive so the session keeps running hidden).
function M.forget_win()
  M.win = nil
end

--- Full reset after the session exits.
function M.reset()
  M.buf = nil
  M.win = nil
  M.job = nil
end

return M
