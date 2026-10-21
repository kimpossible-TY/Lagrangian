-- Query through Neovim's input decoder, leaving the TUI and shell job running.
local Terminal = {}
local esc = '\27'
local querying = false

local function supported_tui()
  if not vim.api.nvim_ui_send then
    return 'The internal Flow Reader view requires Neovim 0.12 or newer.'
  end
  if vim.fn.has('win32') == 1 then
    return 'The internal Flow Reader view requires a POSIX Neovim host, such as your remote Mac.'
  end
  if vim.env.TMUX or (vim.env.TERM or ''):match('^screen') or (vim.env.TERM or ''):match('^tmux') then
    return 'The internal Flow Reader view requires a direct graphics terminal outside tmux/screen.'
  end
  local uis = vim.api.nvim_list_uis()
  if #uis ~= 1 or not uis[1].stdout_tty then
    return 'The internal Flow Reader view requires one attached Neovim TUI.'
  end
end

local function windows_sixel(attributes)
  -- Windows Terminal's default SIXEL grid is virtual 10x20, independent of
  -- physical font pixels and SSH ioctl dimensions. Do not assume other SIXEL
  -- terminals use that grid. DA1 gained optional clipboard feature 52 later.
  return attributes == '61;4;6;7;14;21;22;23;24;28;32;42'
    or attributes == '61;4;6;7;14;21;22;23;24;28;32;42;52'
end

function Terminal.measure(protocol)
  local err = supported_tui()
  if err then return nil, err end
  if protocol and protocol ~= 'kitty' and protocol ~= 'sixel' and protocol ~= 'iterm2' then
    return nil, 'Unsupported Flow Reader image protocol: ' .. tostring(protocol)
  end
  if querying then return nil, 'Flow Reader is already querying this terminal.' end
  querying = true
  local attributes, logical, kitty, autocmd
  local function measurement()
    local selected = protocol or (kitty and 'kitty') or (windows_sixel(attributes) and 'sixel')
    if selected == 'sixel' and windows_sixel(attributes) then
      return { protocol = selected, cellWidth = 10, cellHeight = 20 }
    end
    if (selected == 'kitty' and kitty) or (selected == 'iterm2' and logical) then
      -- Kitty placement scales to explicit columns/rows, so a logical viewport
      -- also preserves browser input coordinates when OSC reports are absent.
      return { protocol = selected, cellWidth = logical and logical[1] or 9,
        cellHeight = logical and logical[2] or 18 }
    end
  end
  local ok, result = pcall(function()
    autocmd = vim.api.nvim_create_autocmd('TermResponse', { callback = function(event)
      local response = event.data.sequence
      attributes = response:match('^' .. esc .. '%[%?([%d;]+)c$') or attributes
      if response:match('^' .. esc .. '_Gi=39732;OK$') then kitty = true end
      local height, width, rest = response:match('^' .. esc .. '%]1337;ReportCellSize=([%d%.]+);([%d%.]+)(.*)$')
      if height and (rest == '' or rest:match('^;[%d%.]+$')) then
        height, width = tonumber(height), tonumber(width)
        if height and width and width >= 1 and width <= 200 and height >= 1 and height <= 400 then
          logical = { width, height }
        end
      end
    end })
    vim.api.nvim_ui_send(esc .. ']1337;ReportCellSize\7'
      .. esc .. '_Gi=39732,a=q,t=d,f=24,s=1,v=1;AAAA' .. esc .. '\\' .. esc .. '[c')
    local completed = vim.wait(1200, function() return attributes ~= nil and measurement() ~= nil end, 10)
    if not completed then return nil end
    if measurement().protocol == 'kitty' and not logical then
      -- Optional OSC replies can arrive after the graphics reply. Leave a short
      -- bounded window for them before using Kitty's scaled logical viewport.
      local reported, reason = vim.wait(150, function() return logical ~= nil end, 10)
      if not reported and reason ~= -1 then return nil end
    end
    return measurement()
  end)
  if autocmd then pcall(vim.api.nvim_del_autocmd, autocmd) end
  querying = false
  if not ok then return nil, 'Flow Reader terminal query failed: ' .. tostring(result) end
  if not result then
    return nil, 'Flow Reader needs a recognized Windows Terminal SIXEL grid or a Kitty graphics response; '
      .. 'the terminal query timed out or its cell geometry is unsupported.'
  end
  return result
end

return Terminal
