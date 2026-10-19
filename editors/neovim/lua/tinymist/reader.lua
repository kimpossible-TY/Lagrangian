-- Optional native-terminal host for the existing tinymist-flow HTML Reader.
local reader = {}
local uv = vim.uv or vim.loop
local config = {}
local session
local source_file = debug.getinfo(1, 'S').source:sub(2)
local repository = vim.fs.dirname(source_file)
for _ = 1, 4 do
  repository = vim.fs.dirname(repository)
end

local function absolute(path, base)
  if type(path) ~= 'string' or path == '' or path:find('\0', 1, true) then
    return nil
  end
  if not path:match('^[/\\]') and not path:match('^%a:[/\\]') then
    path = (base or uv.cwd()) .. '/' .. path
  end
  path = vim.fs.normalize(vim.fn.fnamemodify(path, ':p'))
  local resolved = uv.fs_realpath(path)
  return resolved and vim.fs.normalize(resolved) or (path == '/' and path or path:gsub('/$', ''))
end

local function root()
  if session then
    return session.root
  end
  return absolute(config.root or uv.cwd())
end

local function owned_path(path)
  local resolved = absolute(path)
  local directory = root()
  if not resolved or not directory then
    return nil
  end
  local candidate, prefix = resolved, directory
  if vim.fn.has('win32') == 1 then
    candidate, prefix = candidate:lower(), prefix:lower()
  end
  local boundary = prefix:sub(-1) == '/' and prefix or prefix .. '/'
  if candidate ~= prefix and candidate:sub(1, #boundary) ~= boundary then
    return nil
  end
  local stat = uv.fs_stat(resolved)
  return stat and stat.type == 'file' and resolved or nil
end

local function read_file(path)
  local handle = uv.fs_open(path, 'r', 0)
  if not handle then
    return nil
  end
  local stat = uv.fs_fstat(handle)
  local contents = stat and uv.fs_read(handle, stat.size, 0)
  uv.fs_close(handle)
  return contents
end

local function write_private(path, contents)
  local temporary = path .. '.tmp'
  local handle, err = uv.fs_open(temporary, 'w', 384) -- 0600; keep editor addresses private.
  if not handle then
    return nil, err
  end
  local written, write_err = uv.fs_write(handle, contents, 0)
  uv.fs_close(handle)
  if written ~= #contents then
    uv.fs_unlink(temporary)
    return nil, write_err
  end
  local renamed, rename_err = uv.fs_rename(temporary, path)
  if not renamed then uv.fs_unlink(temporary) end
  return renamed, rename_err
end

local function loaded_buffer(path)
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(bufnr) and absolute(vim.api.nvim_buf_get_name(bufnr)) == path then
      return bufnr
    end
  end
end

local function text_parts(text)
  local format = text:find('\r\n', 1, true) and 'dos' or 'unix'
  local normalized = format == 'dos' and text:gsub('\r\n', '\n') or text
  local eol = normalized:sub(-1) == '\n'
  if eol then
    normalized = normalized:sub(1, -2)
  end
  return vim.split(normalized, '\n', { plain = true }), eol, format
end

local function buffer_text(bufnr)
  local separator = vim.bo[bufnr].fileformat == 'dos' and '\r\n' or '\n'
  local contents = table.concat(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), separator)
  if vim.bo[bufnr].endofline then
    contents = contents .. separator
  end
  if vim.bo[bufnr].bomb then
    contents = '\239\187\191' .. contents
  end
  return contents
end

---Return the editor cursor using one-based lines and zero-based UTF-8 byte columns.
function reader.cursor()
  local bufnr = vim.api.nvim_get_current_buf()
  local position = vim.api.nvim_win_get_cursor(0)
  return {
    path = absolute(vim.api.nvim_buf_get_name(bufnr)) or '',
    line = position[1],
    column = position[2],
    modified = vim.bo[bufnr].modified,
  }
end

---Navigate to an already verified saved source position, preserving hidden dirty buffers.
---@param payload table
---@return string
function reader.jump(payload)
  if type(payload) ~= 'table' then
    return 'error'
  end
  local path = owned_path(payload.path)
  local line, column = payload.line, payload.column
  local expected_hash = payload.source_hash
  if type(expected_hash) ~= 'string' or #expected_hash ~= 64 or not expected_hash:match('^%x+$') then
    return 'error'
  end
  if not path or type(line) ~= 'number' or line < 1 or line % 1 ~= 0
    or type(column) ~= 'number' or column < 0 or column % 1 ~= 0 then
    return 'error'
  end
  local target = loaded_buffer(path)
  if target and vim.bo[target].modified then
    return 'modified'
  end
  local disk = read_file(path)
  if not disk or vim.fn.sha256(disk) ~= expected_hash then
    return 'stale'
  end
  target = target or vim.fn.bufadd(path)
  vim.fn.bufload(target)
  if vim.fn.sha256(buffer_text(target)) ~= expected_hash
    and not (disk == '' and vim.api.nvim_buf_get_lines(target, 0, -1, false)[1] == '') then
    return 'stale'
  end
  if line > vim.api.nvim_buf_line_count(target) then
    return 'stale'
  end
  local text = vim.api.nvim_buf_get_lines(target, line - 1, line, false)[1]
  if column > #text or (column < #text and text:byte(column + 1) >= 128 and text:byte(column + 1) < 192) then
    return 'stale'
  end
  -- nvim_win_set_buf can hide the current dirty buffer without writing it.
  local ok = pcall(function()
    vim.api.nvim_win_set_buf(0, target)
    vim.api.nvim_win_set_cursor(0, { line, column })
  end)
  return ok and 'jumped' or 'error'
end

---Apply a compiler-verified replacement only while the file and editor still agree.
---Called through the local Neovim RPC server; full source text is never shell code.
---@param payload table
---@return string
function reader.apply_edit(payload)
  if type(payload) ~= 'table' or type(payload.original) ~= 'string' or type(payload.updated) ~= 'string' then
    return 'error'
  end
  if payload.original:find('\0', 1, true) or payload.updated:find('\0', 1, true) then
    return 'unsupported'
  end
  local path = owned_path(payload.path)
  if not path then
    return 'error'
  end
  local target = loaded_buffer(path)
  if target and vim.bo[target].modified then
    return 'modified'
  end
  if read_file(path) ~= payload.original then
    return 'stale'
  end
  target = target or vim.fn.bufadd(path)
  vim.fn.bufload(target)
  if vim.bo[target].modified then
    return 'modified'
  end
  if vim.bo[target].fileencoding ~= '' and vim.bo[target].fileencoding ~= 'utf-8' then
    return 'unsupported'
  end
  local old_lines = vim.api.nvim_buf_get_lines(target, 0, -1, false)
  if buffer_text(target) ~= payload.original
    and not (payload.original == '' and #old_lines == 1 and old_lines[1] == '') then
    return 'stale'
  end
  if vim.bo[target].readonly or not vim.bo[target].modifiable or vim.bo[target].bomb then
    return 'unsupported'
  end
  local lines, eol, format = text_parts(payload.updated)
  local separator = format == 'dos' and '\r\n' or '\n'
  if table.concat(lines, separator) .. (eol and separator or '') ~= payload.updated then
    return 'unsupported'
  end
  local old_eol, old_format, old_fixeol = vim.bo[target].endofline, vim.bo[target].fileformat, vim.bo[target].fixendofline
  -- Keep the final comparison and mutation synchronous in the editor process.
  if read_file(path) ~= payload.original then
    return 'stale'
  end
  local ok = pcall(function()
    vim.api.nvim_buf_set_lines(target, 0, -1, false, lines)
    vim.bo[target].endofline = eol
    vim.bo[target].fileformat = format
    vim.bo[target].fixendofline = false
    vim.api.nvim_buf_call(target, function()
      vim.cmd 'silent noautocmd write'
    end)
  end)
  vim.bo[target].fixendofline = old_fixeol
  if not ok then
    vim.api.nvim_buf_set_lines(target, 0, -1, false, old_lines)
    vim.bo[target].endofline = old_eol
    vim.bo[target].fileformat = old_format
    vim.bo[target].modified = false
    return 'error'
  end
  return read_file(path) == payload.updated and 'highlighted' or 'error'
end

local function shell_quote(value)
  return "'" .. value:gsub("'", "'\\''") .. "'"
end

local function applescript_quote(value)
  return '"' .. value:gsub('\\', '\\\\'):gsub('"', '\\"'):gsub('\r', '\\r'):gsub('\n', '\\n') .. '"'
end

local function opener(argv)
  if config.open then
    if type(config.open) ~= 'table' or #config.open == 0 then
      return nil, 'Flow Reader open must be a nonempty argv array for a native terminal pane launcher.'
    end
    local result = vim.deepcopy(config.open)
    vim.list_extend(result, argv)
    return result
  end
  if vim.fn.has('macunix') ~= 1 or vim.env.TERM_PROGRAM ~= 'iTerm.app' then
    return nil, 'Flow Reader needs iTerm2 or an explicit open argv array for a native Kitty-compatible terminal pane.'
  end
  local identifier = vim.env.ITERM_SESSION_ID
  if not identifier or identifier == '' then
    return nil, 'Flow Reader cannot identify the current iTerm2 pane; launch Neovim directly in iTerm2 or configure open.'
  end
  identifier = identifier:match(':([^:]+)$') or identifier
  local quoted = {}
  for _, argument in ipairs(argv) do
    quoted[#quoted + 1] = shell_quote(argument)
  end
  -- iTerm overrides the profile command, so PowerShell login profiles are supported.
  local command = '/bin/sh -c ' .. shell_quote('exec ' .. table.concat(quoted, ' '))
  local script = table.concat({
    'tell application "iTerm2"',
    '  repeat with candidateWindow in windows',
    '    repeat with candidateTab in tabs of candidateWindow',
    '      repeat with candidateSession in sessions of candidateTab',
    '        if unique id of candidateSession is ' .. applescript_quote(identifier) .. ' then',
    '          tell candidateSession',
    '            split vertically with default profile command ' .. applescript_quote(command),
    '          end tell',
    '          return',
    '        end if',
    '      end repeat',
    '    end repeat',
    '  end repeat',
    '  error "The Neovim iTerm2 session no longer exists"',
    'end tell',
  }, '\n')
  return { 'osascript', '-e', script }
end

---Stop only the renderer and service owned by this editor session.
function reader.stop()
  if session then
    uv.fs_unlink(session.control)
    uv.fs_unlink(session.sync)
    session = nil
  end
  return true
end

---Open the HTML Reader in a native terminal pane.
---@return boolean, string?
function reader.start()
  if session and uv.fs_stat(session.control) then
    return true
  end
  if session then reader.stop() end
  local directory = root()
  local directory_stat = directory and uv.fs_stat(directory)
  if not directory_stat or directory_stat.type ~= 'directory' then
    return false, 'Flow Reader root must be an existing project directory.'
  end
  local entry = absolute(config.entry or vim.api.nvim_buf_get_name(0), directory)
  if not entry or not entry:match('%.typ$') or not uv.fs_stat(entry) then
    return false, 'Flow Reader needs a saved .typ entry file (set entry for a main document).'
  end
  local command = config.command or { 'node', repository .. '/tools/flow-reader/terminal.mjs' }
  if type(command) ~= 'table' or #command == 0 then
    return false, 'Flow Reader command must be a nonempty argv array.'
  end
  if owned_path(entry) ~= entry then
    return false, 'Flow Reader entry must be inside its root directory.'
  end
  local identity = vim.fn.sha256(config.url or directory .. '\0' .. entry):sub(1, 24)
  local storage = vim.fn.stdpath('state') .. '/tinymist-reader/' .. identity
  vim.fn.mkdir(storage, 'p', 448)
  local control = vim.fn.tempname()
  local sync = control .. '.sync'
  local server = vim.v.servername
  if server == '' then
    local ok, address = pcall(vim.fn.serverstart)
    if not ok then
      return false, 'Flow Reader could not start the Neovim RPC server: ' .. tostring(address)
    end
    server = address
  end
  local argv = vim.deepcopy(command)
  -- Native panes may start without the editor's PATH (including Homebrew binaries).
  local executable = type(argv[1]) == 'string' and vim.fn.exepath(argv[1]) or ''
  if executable ~= '' then argv[1] = executable end
  local compiler = config.compiler or vim.fn.exepath('typst')
  if compiler == '' then compiler = nil end
  local options = {
    { '--editor-server', server },
    { '--parent-pid', tostring(uv.os_getpid()) }, { '--control-file', control }, { '--sync-file', sync },
    { '--nvim', vim.v.progpath }, { '--profile', config.profile and absolute(config.profile, directory) or storage .. '/browser' },
    { '--url', config.url },
    { '--playwright-module', config.playwright_module }, { '--browser-executable', config.browser_executable },
    { '--protocol', config.protocol },
  }
  if not config.url then
    vim.list_extend(options, {
      { '--root', directory }, { '--entry', entry },
      { '--output', config.output and absolute(config.output, directory) or storage .. '/html' },
      { '--package-path', config.package_path and absolute(config.package_path, directory) },
      { '--compiler', compiler }, { '--port', config.port and tostring(config.port) },
    })
  end
  for _, option in ipairs(options) do
    if option[2] ~= nil then
      argv[#argv + 1] = option[1]
      argv[#argv + 1] = option[2]
    end
  end
  vim.list_extend(argv, config.args or {})
  for _, argument in ipairs(argv) do
    if type(argument) ~= 'string' or argument:find('\0', 1, true) then
      return false, 'Flow Reader command arguments must be strings without NUL bytes.'
    end
  end
  local launch, launch_error = opener(argv)
  if not launch then
    return false, launch_error
  end
  local written, write_error = write_private(control, 'running\n')
  if not written then
    return false, 'Flow Reader could not create its lifecycle file: ' .. tostring(write_error)
  end
  local started = { root = directory, entry = entry, control = control, sync = sync }
  session = started
  local errors = {}
  local ok, job = pcall(vim.fn.jobstart, launch, {
    detach = true,
    -- jobstart sets NVIM even for external terminal launchers; this pane is native.
    env = { NVIM = '', TMUX = '' },
    on_stderr = function(_, data)
      for _, line in ipairs(data) do
        if line ~= '' then errors[#errors + 1] = line end
      end
    end,
    on_exit = function(_, code)
      if code ~= 0 and session == started then
        reader.stop()
        vim.schedule(function()
          vim.notify('Flow Reader pane launch failed (' .. code .. '): ' .. table.concat(errors, '\n'), vim.log.levels.ERROR)
        end)
      end
    end,
  })
  if not ok or job <= 0 then
    reader.stop()
    return false, 'Flow Reader could not launch the native pane: ' .. tostring(job)
  end
  return true
end

---Request immediate source-to-Reader synchronization.
function reader.sync()
  if not session then
    return false, 'Flow Reader is not running; use :FlowReader start.'
  end
  return write_private(session.sync, vim.json.encode(reader.cursor()))
end

---Opt in to automatic Typst Reader panes; no user configuration files are written.
---@param options? table
function reader.setup(options)
  reader.stop()
  config = options or {}
  local group = vim.api.nvim_create_augroup('TinymistFlowReader', { clear = true })
  vim.api.nvim_create_autocmd('VimLeavePre', { group = group, callback = reader.stop })
  local function invoke(action)
    local ok, err = reader[action]()
    if not ok then vim.notify(err or 'Flow Reader failed', vim.log.levels.ERROR) end
  end
  vim.api.nvim_create_user_command('FlowReader', function(command)
    local action = command.args ~= '' and command.args or 'start'
    if action == 'start' or action == 'stop' or action == 'sync' then
      invoke(action)
    else
      vim.notify('Use :FlowReader [start|stop|sync]', vim.log.levels.ERROR)
    end
  end, { nargs = '?', complete = function() return { 'start', 'stop', 'sync' } end, force = true })
  if config.auto_open ~= false then
    vim.api.nvim_create_autocmd('FileType', {
      group = group, pattern = 'typst',
      callback = function() vim.schedule(function() invoke('start') end) end,
    })
    if vim.bo.filetype == 'typst' then
      vim.schedule(function() invoke('start') end)
    end
  end
end

return reader
