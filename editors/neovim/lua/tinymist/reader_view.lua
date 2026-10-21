-- An owned Neovim view: input uses a virtual terminal; images bypass its decoder.
local View = {}
View.__index = View
local uv = vim.uv or vim.loop
local esc = '\27'

local function clean(text)
  return tostring(text):gsub('[%z\1-\31\127-\159]', ' ')
end

local function clear_image(rect)
  if not rect then return end
  local output = { esc .. '7', esc .. '_Ga=d,d=I,i=39731,q=2;' .. esc .. '\\' }
  for row = rect.top, rect.top + rect.rows - 2 do
    output[#output + 1] = esc .. '[' .. row .. ';' .. rect.left .. 'H' .. esc .. '[' .. rect.columns .. 'X'
  end
  output[#output + 1] = esc .. '8'
  vim.api.nvim_ui_send(table.concat(output))
end

function View:send(message)
  if not self.job or self.closed then return end
  message.version = 1
  pcall(vim.fn.chansend, self.job, vim.json.encode(message) .. '\n')
end

function View:input(data)
  if self.ready then self:send { type = 'input', data = data }
  elseif #self.pending_input + #data <= 65536 then self.pending_input = self.pending_input .. data end
end

function View:focus()
  if self.closed or not vim.api.nvim_win_is_valid(self.win) then return end
  vim.api.nvim_set_current_win(self.win)
  vim.cmd.startinsert()
end

function View:layout()
  if not vim.api.nvim_win_is_valid(self.win) or vim.api.nvim_win_get_buf(self.win) ~= self.buf then return nil end
  local position = vim.api.nvim_win_get_position(self.win)
  local rect = {
    top = position[1] + 1, left = position[2] + 1,
    columns = vim.api.nvim_win_get_width(self.win), rows = vim.api.nvim_win_get_height(self.win),
    cellWidth = self.measurement.cellWidth, cellHeight = self.measurement.cellHeight,
    visible = vim.api.nvim_get_current_tabpage() == self.tab and vim.fn.mode():sub(1, 1) ~= 'c'
      and vim.fn.pumvisible() == 0,
  }
  if rect.rows < 2 then rect.visible = false; rect.rows = 2 end
  if rect.visible then
    for _, win in ipairs(vim.api.nvim_tabpage_list_wins(self.tab)) do
      local floating = vim.api.nvim_win_get_config(win)
      if floating.relative ~= '' then
        local p = vim.api.nvim_win_get_position(win)
        local border = floating.border and 2 or 0
        if p[1] < rect.top + rect.rows - 1 and p[1] + vim.api.nvim_win_get_height(win) + border >= rect.top
          and p[2] < rect.left + rect.columns and p[2] + vim.api.nvim_win_get_width(win) + border >= rect.left then
          rect.visible = false
          break
        end
      end
    end
  end
  return rect
end

function View:paint()
  if not self.frame or not self.rect.visible or self.closed then return end
  -- Flush Neovim's redraw before the overlay, and preserve its actual cursor.
  self.painting = true
  vim.cmd.redraw()
  self.painting = false
  local sixel = self.measurement.protocol == 'sixel'
  vim.api.nvim_ui_send(esc .. '7' .. esc .. '[' .. self.rect.top .. ';' .. self.rect.left .. 'H'
    .. (sixel and esc .. '[?80l' or '')
    .. self.frame:sub(4) -- Remove only the encoder's initial CSI H.
    .. esc .. '8')
  self.painted = self.rect
  self.repaint = false
end

function View:status(message)
  if self.loading_since then
    local tick = math.floor((uv.hrtime() - self.loading_since) / 500000000)
    local index = tick % 4 + 1
    message = ('|/-\\'):sub(index, index) .. ' Loading... ' .. math.floor(tick / 2) .. 's · Ctrl-W h: source'
  end
  if not message then return end
  local status = ('Flow Reader · ' .. clean(message):sub(1, 180)):gsub('%%', '%%%%')
  if vim.wo[self.win].statusline ~= status then vim.wo[self.win].statusline = status end
end

function View:update()
  if self.closed then return end
  local rect = self:layout()
  if not rect then self.options.on_close(); return end
  self:status()
  if self.measuring then rect.visible = false end
  if not vim.deep_equal(rect, self.rect) then
    clear_image(self.painted)
    self.painted, self.frame = nil, nil
    self.rect = rect
    self.generation = self.generation + 1
    vim.cmd('redraw!')
    if self.ready then
      self:send(vim.tbl_extend('force', rect, { type = 'resize', generation = self.generation }))
    end
  end
  if self.repaint then self:paint() end
end

function View:receive(message)
  if message.version ~= 1 then error('Unsupported Reader view protocol') end
  if message.type == 'ready' then
    self.ready = true
    self:send(vim.tbl_extend('force', self.rect, { type = 'resize', generation = self.generation }))
    self:input(self.pending_input)
    self.pending_input = ''
  elseif message.type == 'error' then error(message.message)
  elseif message.type == 'frame' then
    -- Check the real window now: a resize may precede its deferred autocmd.
    self:update()
    if not self.closed and message.generation == self.generation and self.rect.visible
      and message.columns == self.rect.columns and message.rows == self.rect.rows - 1 then
      local image = type(message.image) == 'string' and message.image or nil
      if image then
        if image:sub(1, 3) ~= esc .. '[H' then error('Invalid Reader image position') end
        self.frame = image
        self.loading_since = nil
      end
      self:status(message.status)
      if image or self.repaint then self:paint() end
    end
    self:send { type = 'ack', id = message.id }
  else error('Unexpected Reader view message') end
end

function View:close()
  if self.closed then return end
  local owns_window = self.win and vim.api.nvim_win_is_valid(self.win)
    and vim.api.nvim_win_get_buf(self.win) == self.buf
  local restore_focus = owns_window and vim.api.nvim_get_current_win() == self.win
  self:send { type = 'stop' }
  self.closed = true
  if self.timer then self.timer:stop(); self.timer:close() end
  if self.namespace then
    vim.on_key(nil, self.namespace)
    vim.api.nvim_set_decoration_provider(self.namespace, {})
  end
  if self.group then pcall(vim.api.nvim_del_augroup_by_id, self.group) end
  clear_image(self.painted)
  if self.job then
    pcall(vim.fn.chanclose, self.job, 'stdin')
    if vim.fn.jobwait({ self.job }, 1500)[1] == -1 then
      pcall(vim.fn.jobstop, self.job)
      vim.fn.jobwait({ self.job }, 2000)
    end
  end
  if owns_window then
    local closed = pcall(vim.api.nvim_win_close, self.win, true)
    if not closed and vim.api.nvim_buf_is_valid(self.source_buf) then
      vim.api.nvim_win_set_buf(self.win, self.source_buf)
    end
  end
  if self.buf and vim.api.nvim_buf_is_valid(self.buf) then pcall(vim.api.nvim_buf_delete, self.buf, { force = true }) end
  if restore_focus then
    if vim.api.nvim_win_is_valid(self.source_win) then vim.api.nvim_set_current_win(self.source_win) end
    vim.cmd.stopinsert()
  end
  vim.cmd('redraw!')
end

function View.open(argv, options)
  local self = setmetatable({
    options = options, source_win = vim.api.nvim_get_current_win(),
    source_buf = vim.api.nvim_get_current_buf(),
    measurement = options.measurement, pending_input = '', generation = 0, loading_since = uv.hrtime(),
  }, View)
  local ok, view, err = pcall(self.start, self, argv)
  if not ok then
    self:close()
    return nil, 'Flow Reader could not create its view: ' .. clean(view)
  end
  return view, err
end

function View:start(argv)
  local options = self.options
  self.buf = vim.api.nvim_create_buf(false, true)
  self.win = vim.api.nvim_open_win(self.buf, true, { split = 'right', win = self.source_win })
  self.tab = vim.api.nvim_get_current_tabpage()
  vim.bo[self.buf].bufhidden = 'wipe'
  vim.bo[self.buf].swapfile = false
  for key, value in pairs {
    number = false, relativenumber = false, signcolumn = 'no', foldcolumn = '0',
    statuscolumn = '', winbar = '', wrap = false, cursorline = false, cursorcolumn = false,
  } do vim.wo[self.win][key] = value end
  local channel = vim.api.nvim_open_term(self.buf, {
    on_input = function(_, _, _, data) self:input(data) end,
  })
  -- These modes configure input encoding only. No Reader pixels enter libvterm.
  vim.api.nvim_chan_send(channel, esc .. '[?25l' .. esc .. '[?1002h' .. esc .. '[?1006h' .. esc .. '[?2004h')
  for _, key in ipairs { 'h', 'j', 'k', 'l', 'w', 'p' } do
    vim.keymap.set('t', '<C-w>' .. key, '<C-\\><C-n><C-w>' .. key, { buffer = self.buf, silent = true })
  end
  vim.keymap.set('n', '<CR>', function() self:focus() end, { buffer = self.buf })
  self.group = vim.api.nvim_create_augroup('TinymistReaderView' .. self.buf, { clear = true })
  self.namespace = vim.api.nvim_create_namespace('TinymistReaderMouse' .. self.buf)
  vim.api.nvim_set_decoration_provider(self.namespace, {
    on_end = function() if not self.painting then self.repaint = true end end,
  })
  local mouse = {}
  for key, event in pairs {
    LeftMouse = { 0, false }, LeftDrag = { 32, false }, LeftRelease = { 0, true },
    ScrollWheelUp = { 64, false }, ScrollWheelDown = { 65, false },
  } do mouse[vim.api.nvim_replace_termcodes('<' .. key .. '>', true, false, true)] = event end
  vim.on_key(function(key)
    local event = mouse[key]
    if not event or self.closed then return end
    local point = vim.fn.getmousepos()
    local rect = self:layout()
    if not rect or not rect.visible then return end
    local column, row = point.screencol - rect.left + 1, point.screenrow - rect.top + 1
    local inside = column >= 1 and column <= rect.columns and row >= 1 and row < rect.rows
    if not inside and not self.dragging then return end
    if event[1] == 0 then self.dragging = not event[2] end
    vim.schedule(function()
      if self.closed then return end
      self:update()
      if event[1] == 0 and not event[2] then self:focus() end
      self:input(esc .. '[<' .. event[1] .. ';' .. math.max(0, column) .. ';' .. math.max(0, row)
        .. (event[2] and 'm' or 'M'))
    end)
    return ''
  end, self.namespace)
  vim.api.nvim_create_autocmd({ 'WinResized', 'WinScrolled', 'TabEnter', 'CmdlineEnter', 'CmdlineLeave',
    'WinEnter', 'WinLeave', 'ModeChanged', 'ColorScheme', 'BufWinEnter', 'BufWinLeave' }, {
    group = self.group,
    callback = function() self.repaint = true; vim.schedule(function() self:update() end) end,
  })
  vim.api.nvim_create_autocmd('BufEnter', { group = self.group, buffer = self.buf,
    callback = function() vim.schedule(function() if not self.closed and vim.api.nvim_get_current_win() == self.win then self:focus() end end) end })
  vim.api.nvim_create_autocmd('WinClosed', { group = self.group, pattern = tostring(self.win),
    callback = function() vim.schedule(function() if not self.closed then options.on_close() end end) end })
  vim.api.nvim_create_autocmd('VimResized', { group = self.group, callback = function()
    if self.measuring then return end
    self.measuring = true
    clear_image(self.painted)
    self.painted, self.frame = nil, nil
    vim.defer_fn(function()
      if self.closed then return end
      local measurement, err = options.measure()
      self.measuring = false
      if not measurement then options.on_error(err); return end
      self.measurement = measurement
      self:update()
    end, 120)
  end })
  self:update()
  local pending, errors = '', {}
  local ok, job = pcall(vim.fn.jobstart, argv, {
    on_stdout = function(_, data)
      if self.closed then return end
      pending = pending .. table.concat(data, '\n')
      if #pending > 67108864 then options.on_error('Reader frame exceeds the view limit'); return end
      while true do
        local ending = pending:find('\n', 1, true)
        if not ending then break end
        local line = pending:sub(1, ending - 1)
        pending = pending:sub(ending + 1)
        local received, err = pcall(function() self:receive(vim.json.decode(line)) end)
        if not received then options.on_error('Flow Reader: ' .. clean(err)); return end
      end
    end,
    on_stderr = function(_, data)
      if #table.concat(errors) < 65536 then vim.list_extend(errors, data) end
    end,
    on_exit = function(_, code)
      if self.closed then return end
      if code ~= 0 then options.on_error('Flow Reader exited (' .. code .. '): ' .. clean(table.concat(errors, '\n')))
      else options.on_close() end
    end,
  })
  if not ok or job <= 0 then self:close(); return nil, 'Flow Reader could not start: ' .. tostring(job) end
  self.job = job
  self.timer = assert(uv.new_timer())
  self.timer:start(500, 500, vim.schedule_wrap(function() self:update() end))
  self:focus()
  return self
end

return View
