local loop = require('vgit.core.loop')
local utils = require('vgit.core.utils')

vim.api.nvim_create_augroup('VGitGroup', { clear = true })

local event = { group = 'VGitGroup' }

function event.on(event_names, callback)
  vim.schedule(function()
    vim.api.nvim_create_autocmd(event_names, { callback = loop.coroutine(callback) })
  end)

  return event
end

function event.buffer_on(buffer, event_name, callback)
  local group = event_name
  if type(event_name) == 'table' then
    group = utils.list.reduce(event_name, '', function(acc, e)
      acc = acc .. '::' .. e
      return acc
    end)
  end
  group = event.group .. '::' .. group .. '::' .. buffer.bufnr
  
  vim.schedule(function()
    vim.api.nvim_create_augroup(group, { clear = true })
    vim.api.nvim_create_autocmd(event_name, {
      group = group,
      buffer = buffer.bufnr,
      callback = loop.coroutine(callback),
    })
  end)

  return event
end

function event.custom_on(event_name, callback)
  vim.schedule(function()
    vim.api.nvim_create_autocmd('User', {
      group = event.group,
      pattern = event_name,
      callback = loop.coroutine(callback),
    })
  end)

  return event
end

function event.emit(event_name, data)
  vim.schedule(function()
    vim.api.nvim_exec_autocmds({ 'User' }, {
      group = event.group,
      pattern = event_name,
      data = data,
    })
  end)
end

return event
