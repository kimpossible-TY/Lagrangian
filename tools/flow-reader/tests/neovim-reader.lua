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
  reader.setup { root = temporary, auto_open = false, command = { 'node', 'runtime with spaces.mjs' }, open = { 'test-opener', '--' } }
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
    reader.setup { root = temporary, auto_open = false, command = { 'node', strange, capture, "literal ' \" $(touch ignored) `echo ignored`\nsecond line" } }
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

  vim.env.TERM_PROGRAM = 'unsupported-terminal'
  reader.setup { root = temporary, auto_open = false }
  local ok, err = reader.start()
  equal(false, ok)
  assert(err:find('open', 1, true))
end

local ok, err = xpcall(run, debug.traceback)
reader.stop()
vim.fn.jobstart = original_jobstart
vim.env.TERM_PROGRAM = original_term
vim.env.ITERM_SESSION_ID = original_session
vim.fn.delete(temporary, 'rf')
if not ok then
  io.stderr:write(err .. '\n')
  vim.cmd 'cquit 1'
end
print('Neovim HTML Reader module smoke passed')
