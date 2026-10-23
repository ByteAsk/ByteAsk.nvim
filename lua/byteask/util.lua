-- lua/byteask/util.lua
-- Shared helpers: argv construction, binary detection, buffer/context extraction.

local config = require('byteask.config')

local M = {}

--- Resolve the base command as a list (argv[0..]) regardless of string/table config.
---@return string[] argv base command
function M.base_cmd()
  local cmd = config.options.cmd
  if type(cmd) == 'table' then
    return vim.deepcopy(cmd)
  end
  -- A string may itself contain args (e.g. "byteask --oss"); split on whitespace.
  local parts = {}
  for word in tostring(cmd):gmatch('%S+') do
    parts[#parts + 1] = word
  end
  if #parts == 0 then
    parts = { 'byteask' }
  end
  return parts
end

--- The executable name to probe on $PATH (argv[0] of the base command).
---@return string
function M.bin_name()
  return M.base_cmd()[1]
end

--- Is the ByteAsk binary available on $PATH?
---@return boolean
function M.is_installed()
  return vim.fn.executable(M.bin_name()) == 1
end

--- Append the shared flags (model, -c overrides, extra args) to an argv list.
--- The transient override set via :ByteAskModel (config.override) wins over
--- the static M.options defaults: its model replaces opts.model when set,
--- and its config keys are layered on top of opts.config.
---@param argv string[]
---@return string[] argv (mutated + returned)
function M.apply_common_flags(argv)
  local opts = config.options
  local override = config.override or {}

  local model = override.model or opts.model
  if model and model ~= '' then
    argv[#argv + 1] = '-m'
    argv[#argv + 1] = model
  end

  local cfg = vim.tbl_extend('force', opts.config or {}, override.config or {})
  for key, value in pairs(cfg) do
    argv[#argv + 1] = '-c'
    -- Values are parsed as TOML by ByteAsk; strings pass through as literals.
    argv[#argv + 1] = string.format('%s=%s', key, tostring(value))
  end
  for _, extra in ipairs(opts.args or {}) do
    argv[#argv + 1] = extra
  end
  return argv
end

--- Build the argv for the interactive TUI, optionally seeded with a prompt.
---@param prompt string|nil
---@return string[]
function M.build_interactive(prompt)
  local argv = M.base_cmd()
  M.apply_common_flags(argv)
  if prompt and prompt ~= '' then
    argv[#argv + 1] = prompt
  end
  return argv
end

--- Build the argv for a headless subcommand (exec/review/apply/resume/fork).
--- Common flags (model/-c/args) are inserted after the subcommand so they bind
--- to the right clap parser.
---@param subcommand string[]  e.g. { 'exec' } or { 'review' }
---@param tail string[]|nil    trailing positional args (e.g. { prompt })
---@return string[]
function M.build_subcommand(subcommand, tail)
  local argv = M.base_cmd()
  for _, part in ipairs(subcommand) do
    argv[#argv + 1] = part
  end
  M.apply_common_flags(argv)
  for _, part in ipairs(tail or {}) do
    argv[#argv + 1] = part
  end
  return argv
end

--- Current buffer's file path relative to cwd (or absolute if outside cwd).
---@return string|nil
function M.current_relpath()
  local abs = vim.api.nvim_buf_get_name(0)
  if abs == nil or abs == '' then
    return nil
  end
  return vim.fn.fnamemodify(abs, ':.')
end

--- True when the last blockwise selection was made with `$`, i.e. it extended
--- to the end of every line instead of stopping at a fixed column. `'>` stores
--- the end column (not the intent), so the only way to tell `CTRL-V $` apart
--- from a plain `CTRL-V` is to re-select with `gv` and inspect curswant.
---@return boolean
local function block_is_to_eol()
  local view = vim.fn.winsaveview()
  local ok = pcall(vim.cmd, 'normal! gv')
  local to_eol = ok and vim.fn.getcurpos()[5] == vim.v.maxcol
  if ok and vim.fn.mode():find('[vV\22]') then
    pcall(vim.api.nvim_feedkeys, vim.api.nvim_replace_termcodes('<Esc>', true, false, true), 'x', false)
  end
  vim.fn.winrestview(view)
  return to_eol
end

--- Text of the most recent visual selection (call from a command with range).
--- Uses the '< and '> marks, so invoke after leaving visual mode.
---@return string
function M.visual_selection()
  local _, srow, scol = unpack(vim.fn.getpos("'<"))
  local _, erow, ecol = unpack(vim.fn.getpos("'>"))
  if srow == 0 then
    return ''
  end

  -- Blockwise selections are rectangles, not continuous ranges: each line
  -- contributes only its own columns. `$` widens every line to its own EOL.
  if vim.fn.visualmode() == '\22' then
    local c1 = math.min(scol, ecol)
    local to_eol = block_is_to_eol()
    local out = {}
    for _, line in ipairs(vim.api.nvim_buf_get_lines(0, srow - 1, erow, false)) do
      out[#out + 1] = to_eol and line:sub(c1) or line:sub(c1, math.max(scol, ecol))
    end
    return table.concat(out, '\n')
  end

  -- Linewise `'>` and a `$`-extended charwise selection both store MAXCOL here;
  -- Neovim 0.9 rejects it, so clamp to the last line's length.
  local last = vim.api.nvim_buf_get_lines(0, erow - 1, erow, false)[1] or ''
  local lines = vim.api.nvim_buf_get_text(0, srow - 1, scol - 1, erow - 1, math.min(ecol, #last), {})
  return table.concat(lines, '\n')
end

--- Walk upward from `start_dir` looking for `filename`, stopping at the
--- filesystem root. Used to locate the nearest AGENTS.md the way ByteAsk
--- itself resolves it (deeper files take precedence over shallower ones).
---@param start_dir string
---@param filename string
---@return string|nil absolute path if found
function M.find_upward(start_dir, filename)
  local dir = vim.fn.fnamemodify(start_dir, ':p:h')
  while true do
    local candidate = dir .. '/' .. filename
    if vim.fn.filereadable(candidate) == 1 then
      return candidate
    end
    local parent = vim.fn.fnamemodify(dir, ':h')
    if parent == dir then
      return nil -- reached the filesystem root
    end
    dir = parent
  end
end

--- Buffer diagnostics rendered as a compact, model-friendly block.
---@param bufnr integer|nil
---@return string
function M.diagnostics_block(bufnr)
  bufnr = bufnr or 0
  local diags = vim.diagnostic.get(bufnr)
  if #diags == 0 then
    return ''
  end
  local sev = { [1] = 'ERROR', [2] = 'WARN', [3] = 'INFO', [4] = 'HINT' }
  local out = {}
  for _, d in ipairs(diags) do
    out[#out + 1] = string.format(
      '%s:%d:%d: %s: %s',
      M.current_relpath() or '<buffer>',
      d.lnum + 1,
      d.col + 1,
      sev[d.severity] or '?',
      (d.message or ''):gsub('\n', ' ')
    )
  end
  return table.concat(out, '\n')
end

return M
