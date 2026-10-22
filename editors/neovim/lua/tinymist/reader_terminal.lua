-- Query through Neovim's input decoder, leaving the TUI and shell job running.
local Terminal = {}
local esc = '\27'
local querying = false
local windows_ui

local function supported_tui()
  if not vim.api.nvim_ui_send then
    return nil, 'The internal Flow Reader view requires Neovim 0.12 or newer.'
  end
  if vim.fn.has('win32') == 1 then
    return nil, 'The internal Flow Reader view requires a POSIX Neovim host, such as your remote Mac.'
  end
  if vim.env.TMUX or (vim.env.TERM or ''):match('^screen') or (vim.env.TERM or ''):match('^tmux') then
    return nil, 'The internal Flow Reader view requires a direct graphics terminal outside tmux/screen.'
  end
  local uis = vim.api.nvim_list_uis()
  if #uis ~= 1 or not uis[1].stdout_tty then
    return nil, 'The internal Flow Reader view requires one attached Neovim TUI.'
  end
  return uis[1].chan
end

local function windows_sixel(attributes)
  -- Windows Terminal's default SIXEL grid is virtual 10x20, independent of
  -- physical font pixels and SSH ioctl dimensions. Do not assume other SIXEL
  -- terminals use that grid. Compare required features, allowing reordered or
  -- additional capabilities such as the optional clipboard feature 52.
  if not attributes then return false end
  local values = vim.split(attributes, ';', { plain = true })
  if values[1] ~= '61' then return false end
  local features = {}
  for index = 2, #values do
    local feature = tonumber(values[index])
    if not feature then return false end
    features[feature] = true
  end
  for _, feature in ipairs { 4, 6, 7, 14, 21, 22, 23, 24, 28, 32, 42 } do
    if not features[feature] then return false end
  end
  return true
end

function Terminal.measure(protocol)
  local ui, err = supported_tui()
  if not ui then return nil, err end
  if protocol and protocol ~= 'kitty' and protocol ~= 'sixel' and protocol ~= 'iterm2' then
    return nil, 'Unsupported Flow Reader image protocol: ' .. tostring(protocol)
  end
  if windows_ui ~= ui then windows_ui = nil end
  if windows_ui and (not protocol or protocol == 'sixel') then
    return { protocol = 'sixel', cellWidth = 10, cellHeight = 20 }
  end
  if querying then return nil, 'Flow Reader is already querying this terminal.' end
  querying = true
  local attributes, logical, kitty, autocmd
  local attempts = 0
  local function measurement()
    local selected = protocol or (kitty == 'OK' and 'kitty') or (windows_sixel(attributes) and 'sixel')
    if selected == 'sixel' and windows_sixel(attributes) then
      return { protocol = selected, cellWidth = 10, cellHeight = 20 }
    end
    if (selected == 'kitty' and kitty == 'OK') or (selected == 'iterm2' and logical) then
      -- Kitty placement scales to explicit columns/rows, so a logical viewport
      -- also preserves browser input coordinates when OSC reports are absent.
      return { protocol = selected, cellWidth = logical and logical[1] or 9,
        cellHeight = logical and logical[2] or 18 }
    end
  end
  local ok, result, interrupted = pcall(function()
    autocmd = vim.api.nvim_create_autocmd('TermResponse', { callback = function(event)
      local response = event.data.sequence:gsub(esc .. '\\$', ''):gsub('\7$', '')
      attributes = response:match('^' .. esc .. '%[%?([%d;]+)c$') or attributes
      kitty = response:match('^' .. esc .. '_Gi=39732;(.*)$') or kitty
      local height, width, rest = response:match('^' .. esc .. '%]1337;ReportCellSize=([%d%.]+);([%d%.]+)(.*)$')
      if height and (rest == '' or rest:match('^;[%d%.]+$')) then
        height, width = tonumber(height), tonumber(width)
        if height and width and width >= 1 and width <= 200 and height >= 1 and height <= 400 then
          logical = { width, height }
        end
      end
    end })
    for attempt, timeout in ipairs { 1500, 2500 } do
      attempts = attempt
      vim.api.nvim_ui_send(esc .. ']1337;ReportCellSize\7'
        .. esc .. '_Gi=39732,a=q,t=d,f=24,s=1,v=1;AAAA' .. esc .. '\\' .. esc .. '[c')
      local completed, reason = vim.wait(timeout, function() return measurement() ~= nil end, 10)
      if completed then break end
      if reason ~= -1 then return nil, true end
    end
    if not measurement() then return nil end
    if measurement().protocol == 'kitty' and not logical then
      -- Optional OSC replies can arrive after the graphics reply. Leave a short
      -- bounded window for them before using Kitty's scaled logical viewport.
      local reported, reason = vim.wait(150, function() return logical ~= nil end, 10)
      if not reported and reason ~= -1 then return nil, true end
    end
    return measurement()
  end)
  if autocmd then pcall(vim.api.nvim_del_autocmd, autocmd) end
  querying = false
  if interrupted or (not ok and tostring(result):lower():find('interrupt', 1, true)) then
    return nil, 'Flow Reader terminal query was cancelled.'
  end
  if not ok then return nil, 'Flow Reader terminal query failed: ' .. tostring(result) end
  if not result then
    return nil, 'Flow Reader terminal query timed out or reported unsupported cell geometry (' .. attempts
      .. ' attempts, up to 4s). Received DA1=' .. (attributes or 'none')
      .. ', Kitty=' .. (kitty and vim.inspect(kitty:sub(1, 100)) or 'none')
      .. ', cell=' .. (logical and (logical[1] .. 'x' .. logical[2]) or 'none') .. '.'
  end
  if result.protocol == 'sixel' then windows_ui = ui end
  return result
end

return Terminal
