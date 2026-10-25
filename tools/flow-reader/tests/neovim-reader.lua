-- Standalone module smoke: nvim --headless -u NONE -i NONE -n -l tools/flow-reader/tests/neovim-reader.lua
-- This does not run the repository's container-only Neovim integration suite.
local repo = vim.fn.getcwd()
vim.opt.runtimepath:append(repo .. '/editors/neovim')
local reader = require 'tinymist.reader'
local temporary = vim.fn.tempname()
vim.fn.mkdir(temporary, 'p')
temporary = assert(vim.uv.fs_realpath(temporary))
local source = temporary .. "/source ' 한글.typ"
local original = 'Hello 한글.\nSecond line.\n'
local updated = '#highlight[Hello 한글.]\nSecond line.\n'

local function write(path, contents)
  local handle = assert(io.open(path, 'wb'))
  assert(handle:write(contents))
  handle:close()
end

local function read(path)
  local handle = assert(io.open(path, 'rb'))
  local contents = handle:read('*a')
  handle:close()
  return contents
end

local function equal(expected, actual)
  assert(vim.deep_equal(expected, actual), vim.inspect { expected = expected, actual = actual })
end

local original_jobstart = vim.fn.jobstart
local original_term = vim.env.TERM_PROGRAM
local original_session = vim.env.ITERM_SESSION_ID
local original_ssh = { vim.env.SSH_CONNECTION, vim.env.SSH_TTY, vim.env.SSH_CLIENT }
local original_shell = vim.o.shell
local original_notify = vim.notify
local messages = {}
vim.notify = function(message) messages[#messages + 1] = message end
vim.env.SSH_CONNECTION, vim.env.SSH_TTY, vim.env.SSH_CLIENT = nil, nil, nil
local launched
vim.fn.jobstart = function(argv, options)
  launched = { argv = vim.deepcopy(argv), options = options }
  return 91
end

local function option(name)
  for index, value in ipairs(launched.argv) do
    if value == name then
      return launched.argv[index + 1]
    end
  end
end

local function run()
  write(source, original)
  reader.setup { root = temporary, auto_open = false, engine = temporary .. '/engine with spaces', command = { 'node', 'runtime with spaces.mjs' }, open = { 'test-opener', '--' } }
  vim.cmd.edit(vim.fn.fnameescape(source))
  vim.bo.swapfile = false
  vim.api.nvim_win_set_cursor(0, { 2, 3 })
  local cursor = reader.cursor()
  equal(source, cursor.path)
  equal(2, cursor.line)
  equal(3, cursor.column)
  equal(false, cursor.modified)
  local realpath = vim.uv.fs_realpath
  vim.uv.fs_realpath = function(path)
    local resolved = realpath(path)
    return resolved and resolved .. '/.' or nil
  end
  local canonical_ok, canonical_cursor = pcall(reader.cursor)
  vim.uv.fs_realpath = realpath
  assert(canonical_ok, canonical_cursor)
  equal(source, canonical_cursor.path)

  equal('highlighted', reader.apply_edit { path = source, original = original, updated = updated })
  equal(updated, read(source))
  equal(false, vim.bo.modified)
  equal('stale', reader.apply_edit { path = source, original = original, updated = updated })
  vim.api.nvim_buf_set_lines(0, 0, 1, false, { 'Unsaved text' })
  equal('modified', reader.apply_edit { path = source, original = updated, updated = original })
  equal(updated, read(source))
  local dirty = vim.api.nvim_get_current_buf()
  local other = temporary .. '/other.typ'
  write(other, 'Other file\n')
  equal('jumped', reader.jump { path = other, line = 1, column = 4, source_hash = vim.fn.sha256('Other file\n') })
  equal(true, vim.bo[dirty].modified)
  equal({ 1, 4 }, vim.api.nvim_win_get_cursor(0))
  equal('stale', reader.jump { path = other, line = 1, column = 0, source_hash = vim.fn.sha256('Older file\n') })
  equal('error', reader.jump { path = '/etc/hosts', line = 1, column = 0 })
  equal('error', reader.apply_edit { path = '/etc/hosts', original = '', updated = '' })
  equal('error', reader.jump { path = other, line = 0, column = 0 })

  local no_newline = temporary .. '/no-newline.typ'
  write(no_newline, 'Without newline')
  equal('highlighted', reader.apply_edit { path = no_newline, original = 'Without newline', updated = 'Still without newline' })
  equal('Still without newline', read(no_newline))
  local crlf = temporary .. '/windows.typ'
  write(crlf, 'One\r\nTwo\r\n')
  equal('highlighted', reader.apply_edit { path = crlf, original = 'One\r\nTwo\r\n', updated = 'One!\r\nTwo\r\n' })
  equal('One!\r\nTwo\r\n', read(crlf))
  equal('unsupported', reader.apply_edit { path = crlf, original = 'One!\r\nTwo\r\n', updated = 'Mixed\r\nnewlines\n' })
  equal('One!\r\nTwo\r\n', read(crlf))
  local empty = temporary .. '/empty.typ'
  write(empty, '')
  equal('highlighted', reader.apply_edit { path = empty, original = '', updated = '' })
  equal('', read(empty))

  assert(reader.start())
  equal({ 'test-opener', '--', vim.fn.exepath('node'), 'runtime with spaces.mjs' }, vim.list_slice(launched.argv, 1, 4))
  equal('', launched.options.env.NVIM)
  equal(temporary, option('--root'))
  equal(nil, option('--engine'))
  equal(nil, option('--compiler'))
  equal(nil, option('--package-path'))
  equal(nil, option('--output'))
  equal(nil, option('--port'))
  equal(other, option('--entry'))
  local control = assert(option('--control-file'))
  equal(1, vim.fn.filereadable(control))
  equal(vim.v.servername, option('--editor-server'))
  assert(option('--parent-pid'))
  assert(reader.sync())
  equal(other, vim.json.decode(read(option('--sync-file'))).path)
  assert(reader.stop())
  equal(0, vim.fn.filereadable(control))

  -- iTerm's command string always invokes /bin/sh, independent of a PowerShell login shell.
  if vim.fn.has('macunix') == 1 then
    vim.env.TERM_PROGRAM = 'iTerm.app'
    vim.env.ITERM_SESSION_ID = 'w0t0p0:session-id'
    local strange = temporary .. "/quotes ' \" $() ` and\nnewline.cjs"
    local capture = temporary .. '/argv.json'
    write(strange, "require('node:fs').writeFileSync(process.argv[2], JSON.stringify(process.argv.slice(3)))")
    reader.setup { root = temporary, auto_open = false, open = 'native', command = { 'node', strange, capture, "literal ' \" $(touch ignored) `echo ignored`\nsecond line" } }
    assert(reader.start())
    equal('osascript', launched.argv[1])
    local script = launched.argv[3]
    assert(script:find('session-id', 1, true))
    assert(script:find('/bin/sh -c', 1, true))
    assert(script:find('split vertically', 1, true))
    assert(not script:find('and\nnewline', 1, true), 'AppleScript strings must escape newlines')
    local literal = assert(script:match('split vertically with default profile command ([^\n]+)'))
    local shell = vim.fn.system { 'osascript', '-e', 'return ' .. literal }
    equal(0, vim.v.shell_error)
    vim.fn.system { '/bin/sh', '-c', shell:gsub('\n$', '') }
    equal(0, vim.v.shell_error)
    local actual_arguments = vim.json.decode(read(capture))
    equal("literal ' \" $(touch ignored) `echo ignored`\nsecond line", actual_arguments[1])
    assert(reader.stop())
  end

  reader.setup { root = temporary, auto_open = false, url = 'http://127.0.0.1:23626/', open = { 'test-opener' } }
  assert(reader.start())
  equal('http://127.0.0.1:23626/', option('--url'))
  equal(nil, option('--root'))
  equal(nil, option('--entry'))
  equal(nil, option('--output'))
  equal(nil, option('--compiler'))
  local completed_control = option('--control-file')
  vim.uv.fs_unlink(completed_control)
  assert(reader.start())
  assert(option('--control-file') ~= completed_control)
  assert(reader.stop())

  reader.setup { root = temporary, auto_open = false, compiler = 'terminal-only-typst' }
  local override_ok, override_error = reader.start()
  equal(false, override_ok)
  assert(override_error:find('managed HTML profile', 1, true))

  -- A remote pane reuses the same source RPC and lifecycle without a Mac GUI.
  launched = nil
  vim.o.shell = '/bin/sh'
  reader.setup { root = temporary, auto_open = false, open = 'manual', protocol = 'sixel' }
  assert(reader.start())
  equal(nil, launched)
  local message = messages[#messages]
  local manifest = assert(message:match("%-%-session' '([^']+)'"), message)
  local record = vim.json.decode(read(manifest))
  equal(1, record.version)
  local function saved_option(name)
    for index, value in ipairs(record.args) do
      if value == name then return record.args[index + 1] end
    end
  end
  equal(vim.v.servername, saved_option('--editor-server'))
  equal(manifest, saved_option('--control-file'))
  equal(tostring(vim.uv.os_getpid()), saved_option('--parent-pid'))
  equal('sixel', saved_option('--protocol'))
  equal(384, bit.band(vim.uv.fs_stat(manifest).mode, 511))
  assert(reader.sync())
  equal(other, vim.json.decode(read(saved_option('--sync-file'))).path)
  assert(reader.start())
  equal(message, messages[#messages])
  assert(reader.stop())
  equal(0, vim.fn.filereadable(manifest))

  vim.env.SSH_CONNECTION = 'remote-client remote-port host host-port'
  reader.setup { root = temporary, auto_open = false, open = 'manual' }
  assert(reader.start())
  equal(nil, launched)
  assert(messages[#messages]:find('second native terminal connection', 1, true))
  assert(reader.stop())
  vim.env.SSH_CONNECTION = nil

  -- Preparation is explicit when a tunnel does not expose SSH environment hints.
  vim.o.shell = '/fake/pwsh'
  reader.setup { root = temporary, auto_open = false, command = { 'node', "reader's $() `script.mjs" } }
  assert(reader.prepare())
  local powershell_message = messages[#messages]
  assert(powershell_message:find("\n& '", 1, true))
  assert(powershell_message:find("'reader''s $() `script.mjs'", 1, true))
  assert(reader.stop())
  vim.o.shell = original_shell

  vim.env.TERM_PROGRAM = 'unsupported-terminal'
  reader.setup { root = temporary, auto_open = false, open = 'native' }
  local ok, err = reader.start()
  equal(false, ok)
  assert(err:find('open', 1, true))

  -- The same paged source history restores an included source without a Reader.
  local main = temporary .. '/main.typ'
  local part = temporary .. '/shared.typ'
  local history = temporary .. '/changes.json'
  local body = '첫 줄\n마지막 수정 위치\n'
  write(main, '#include "shared.typ"\n\n')
  write(part, body)
  local start = assert(body:find('수정', 1, true)) - 1
  write(history, vim.json.encode {
    schema_version = 2, project = vim.json.encode { temporary, main }, variants = {},
    source_history = { sequence = 7, sources = { [part] = body },
      latest = { filepath = part, source_hash = string.rep('a', 32), range = { start = start, ['end'] = #body - 1 } } },
  })
  reader.setup { root = temporary, entry = main, change_file = history, auto_open = false }
  vim.cmd.edit(vim.fn.fnameescape(main))
  local resumed
  assert(reader.resume(false, function(status) resumed = status end))
  assert(vim.wait(5000, function() return resumed ~= nil end), 'Shared lookup did not finish')
  equal('jumped', resumed)
  equal(part, vim.api.nvim_buf_get_name(0))
  equal({ 2, #'마지막 ' }, vim.api.nvim_win_get_cursor(0))

  vim.cmd.edit(vim.fn.fnameescape(main))
  vim.bo.filetype = 'typst'
  reader.setup { root = temporary, entry = main, change_file = history, auto_open = false, restore_last_edit = true }
  assert(vim.wait(5000, function() return vim.api.nvim_buf_get_name(0) == part end), 'Automatic shared restore failed')
  equal({ 2, #'마지막 ' }, vim.api.nvim_win_get_cursor(0))

  reader.setup { root = temporary, entry = main, change_file = history, auto_open = false }
  vim.cmd.edit(vim.fn.fnameescape(main))
  local system = vim.system
  local reply
  vim.system = function(_, _, callback)
    reply = callback
    return { kill = function() end }
  end
  local function deliver()
    local delivered = false
    reply { code = 0, stdout = vim.json.encode {
      status = 'located', path = part, line = 2, column = #'마지막 ', source_hash = vim.fn.sha256(body),
    } }
    vim.schedule(function() delivered = true end)
    assert(vim.wait(1000, function() return delivered end))
  end
  assert(reader.resume())
  vim.api.nvim_win_set_cursor(0, { 2, 0 })
  deliver()
  equal(main, vim.api.nvim_buf_get_name(0))
  equal({ 2, 0 }, vim.api.nvim_win_get_cursor(0))
  assert(reader.resume())
  reader.stop()
  deliver()
  equal(main, vim.api.nvim_buf_get_name(0))
  assert(reader.resume())
  vim.api.nvim_buf_set_lines(0, 1, 2, false, { 'Unsaved while looking up' })
  deliver()
  equal(main, vim.api.nvim_buf_get_name(0))
  equal(true, vim.bo.modified)
  vim.system = system
end

local ok, err = xpcall(run, debug.traceback)
reader.stop()
vim.fn.jobstart = original_jobstart
vim.env.TERM_PROGRAM = original_term
vim.env.ITERM_SESSION_ID = original_session
vim.env.SSH_CONNECTION, vim.env.SSH_TTY, vim.env.SSH_CLIENT = unpack(original_ssh)
vim.o.shell = original_shell
vim.notify = original_notify
vim.fn.delete(temporary, 'rf')
if not ok then
  io.stderr:write(err .. '\n')
  vim.cmd 'cquit 1'
end
print('Neovim HTML Reader module smoke passed')
