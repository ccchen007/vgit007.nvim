local fs = require('vgit.core.fs')
local Scene = require('vgit.ui.Scene')
local loop = require('vgit.core.loop')
local utils = require('vgit.core.utils')
local Buffer = require('vgit.core.Buffer')
local Object = require('vgit.core.Object')
local Window = require('vgit.core.Window')
local console = require('vgit.core.console')
local DiffView = require('vgit.ui.views.DiffView')
local StatusListView = require('vgit.ui.views.StatusListView')
local KeyHelpBarView = require('vgit.ui.views.KeyHelpBarView')
local Model = require('vgit.features.screens.ProjectDiffScreen.Model')
local project_diff_preview_setting = require('vgit.settings.project_diff_preview')

local ProjectDiffScreen = Object:extend()

function ProjectDiffScreen:constructor(opts)
  opts = opts or {}

  local scene = Scene()
  local model = Model(opts)

  return {
    name = 'Project Diff Screen',
    scene = scene,
    model = model,
    app_bar_view = KeyHelpBarView(scene, {
      keymaps = function()
        local keymaps = project_diff_preview_setting:get('keymaps')
        return {
          { 'Stage',        keymaps['buffer_stage'] },
          { 'Unstage',      keymaps['buffer_unstage'] },
          { 'Reset',        keymaps['buffer_reset'] },
          { 'Stage hunk',   keymaps['buffer_hunk_stage'] },
          { 'Unstage hunk', keymaps['buffer_hunk_unstage'] },
          { 'Stage all',    keymaps['stage_all'] },
          { 'Unstage all',  keymaps['unstage_all'] },
          { 'Reset all',    keymaps['reset_all'] },
          { 'Commit',       keymaps['commit'] },
          { 'Untracked',     keymaps['untrack'] },
        }
      end,
    }),
    diff_view = DiffView(scene, {
      layout_type = function()
        return model:get_layout_type()
      end,
      filename = function()
        return model:get_filename()
      end,
      filetype = function()
        return model:get_filetype()
      end,
      diff = function()
        return model:get_diff()
      end,
    }, {
      row = 1,
      col = '25vw',
      width = '75vw',
    }, {
      elements = {
        header = true,
        footer = false,
      },
    }),
    status_list_view = StatusListView(scene, {
      entries = function()
        return model:get_entries()
      end,
    }, {
      row = 1,
      width = '25vw',
    }, {
      elements = {
        header = false,
        footer = false,
      },
    }),
  }
end

function ProjectDiffScreen:hunk_up()
  self.diff_view:prev()
  local diff = self.diff_view.props.diff()
  local index = self.diff_view.current_hunk_index or 1
  local hunk = diff and diff.hunks and diff.hunks[index] or nil
  if hunk then
    vim.schedule(function()
      vim.notify(string.format("hunk_up: 当前hunk范围 [%d, %d] (index=%d)", hunk.top or -1, hunk.bot or -1, index), vim.log.levels.INFO)
    end)
  end
end

function ProjectDiffScreen:hunk_down()
  self.diff_view:next()
  local diff = self.diff_view.props.diff()
  local index = self.diff_view.current_hunk_index or 1
  local hunk = diff and diff.hunks and diff.hunks[index] or nil
  if hunk then
    vim.schedule(function()
      vim.notify(string.format("hunk_down: 当前hunk范围 [%d, %d] (index=%d)", hunk.top or -1, hunk.bot or -1, index), vim.log.levels.INFO)
    end)
  end
end

function ProjectDiffScreen:move_to(query_fn)
  return self.status_list_view:move_to(query_fn)
end

function ProjectDiffScreen:stage_hunk()
  local entry = self.model:get_entry()
  if not entry then
    vim.schedule(function()
      vim.notify("未获取到 entry", vim.log.levels.ERROR)
    end)
    return
  end
  if entry.type ~= 'unstaged' then
    vim.schedule(function()
      vim.notify("当前不是未暂存文件", vim.log.levels.WARN)
    end)
    return
  end

  local diff = self.diff_view.props.diff()
  local index = self.diff_view.current_hunk_index or 1
  local hunk = diff and diff.hunks and diff.hunks[index] or nil

  vim.schedule(function()
    vim.notify(string.format("stage_hunk: index=%d, hunk=%s", index, vim.inspect(hunk)), vim.log.levels.INFO)
  end)

  if not diff or not diff.hunks or #diff.hunks == 0 or not hunk then
    vim.schedule(function()
      vim.notify("当前 diff 视图没有 hunk，请先选中文件并确保右侧有 diff", vim.log.levels.ERROR)
    end)
    return
  end

  local filename = entry.status.filename
  local _, err = self.model:stage_hunk(filename, hunk)
  if err then
    vim.schedule(function()
      vim.notify("stage_hunk 失败: " .. vim.inspect(err), vim.log.levels.ERROR)
    end)
    return
  end

  self:render()
end

function ProjectDiffScreen:unstage_hunk()
  local entry = self.model:get_entry()
  if not entry then return end
  if entry.type ~= 'staged' then
    vim.schedule(function()
      vim.notify("当前不是已暂存文件，无法 unstage hunk", vim.log.levels.WARN)
    end)
    return
  end

  local diff = self.diff_view.props.diff()
  local index = self.diff_view.current_hunk_index or 1
  local hunk = diff and diff.hunks and diff.hunks[index] or nil

  if not diff or not diff.hunks or #diff.hunks == 0 or not hunk then
    vim.schedule(function()
      vim.notify("当前 diff 视图没有 hunk，请先选中文件并确保右侧有 diff", vim.log.levels.ERROR)
    end)
    return
  end

  local filename = entry.status.filename
  local _, err = self.model:unstage_hunk(filename, hunk)
  if err then
    vim.schedule(function()
      vim.notify("unstage_hunk 失败: " .. vim.inspect(err), vim.log.levels.ERROR)
    end)
    return
  end

  self:render()
end

function ProjectDiffScreen:stage_file()
  local entry = self.model:get_entry()
  if not entry then return end
  if entry.type ~= 'unstaged' and entry.type ~= 'unmerged' then return end

  loop.free_textlock()
  local filename = entry.status.filename
  local _, err = self.model:stage_file(filename)
  if err then
    console.debug.error(err)
    return
  end

  self:render(function()
    local has_unstaged = false
    self.status_list_view:each_status(function(status)
      if status:is_staged() then
        has_unstaged = true
      end
    end)

    self:move_to(function(status)
      if has_unstaged then return status:is_unstaged() == true end
      return status.filename == entry.status.filename
    end)
  end)
end

function ProjectDiffScreen:unstage_file()
  local entry = self.model:get_entry()
  if not entry then return end
  if entry.type ~= 'staged' then return end

  loop.free_textlock()
  local filename = entry.status.filename
  local _, err = self.model:unstage_file(filename)
  if err then
    console.debug.error(err)
    return
  end

  self:render(function()
    local has_staged = false
    self.status_list_view:each_status(function(status)
      if status:is_staged() then
        has_staged = true
      end
    end)

    self:move_to(function(status)
      if has_staged then return status:is_staged() == true end
      return status.filename == entry.status.filename
    end)
  end)
end

function ProjectDiffScreen:stage_all()
  local _, err = self.model:stage_all()
  if err then
    console.debug.error(err)
    return
  end

  local entry = self.model:get_entry()
  self:render(function()
    if not entry then return end
    self:move_to(function(status)
      return status.filename == entry.status.filename
    end)
  end)
end

function ProjectDiffScreen:unstage_all()
  local _, err = self.model:unstage_all()
  if err then
    console.debug.error(err)
    return
  end

  local entry = self.model:get_entry()
  self:render(function()
    if not entry then return end
    self:move_to(function(status)
      return status.filename == entry.status.filename
    end)
  end)
end

function ProjectDiffScreen:commit()
  vim.schedule(function()
    vim.cmd('VGit project_commit_preview')
    self:destroy()
  end)
end

function ProjectDiffScreen:reset_file()
  local filename = self.model:get_filename()
  if not filename then return end

  loop.free_textlock()
  local decision =
      console.input(string.format('Are you sure you want to discard changes in %s? (y/N) ', filename)):lower()

  if decision ~= 'yes' and decision ~= 'y' then return end

  loop.free_textlock()
  local _, err = self.model:reset_file(filename)
  loop.free_textlock()

  if err then
    console.debug.error(err)
    return
  end

  self:render()
end

function ProjectDiffScreen:reset_all()
  loop.free_textlock()
  local decision = console.input('Are you sure you want to discard all unstaged changes? (y/N) '):lower()

  if decision ~= 'yes' and decision ~= 'y' then return end

  loop.free_textlock()
  local _, err = self.model:reset_all()
  loop.free_textlock()

  if err then
    console.debug.error(err)
    return
  end

  self:render()
end

function ProjectDiffScreen:enter_view()
  local mark = self.diff_view:get_current_mark_under_cursor()
  if not mark then return end

  local filepath = self.model:get_filepath()
  loop.free_textlock()
  if not filepath then return end

  self:destroy()

  fs.open(filepath)
  Window(0):set_lnum(mark.top_relative):position_cursor('center')
end

function ProjectDiffScreen:open_file()
  local filename = self.model:get_filepath()
  if not filename then return end

  local mark = self.diff_view:get_current_mark_under_cursor()

  loop.free_textlock()
  self:destroy()
  fs.open(filename)

  if not mark then
    local diff, diff_err = self.model:get_diff()
    if diff_err or not diff then return end
    mark = diff.marks[1]
    if not mark then return end
  end

  Window(0):set_lnum(mark.top_relative):position_cursor('center')
end

function ProjectDiffScreen:render(on_status_list_render)
  local entries = self.model:fetch()
  loop.free_textlock()

  if utils.object.is_empty(entries) then return self:destroy() end

  self.status_list_view:render()
  if on_status_list_render then on_status_list_render() end

  local list_item = self.status_list_view:get_current_list_item()
  self.model:set_entry_id(list_item.id)

  self.diff_view:render()
  self.diff_view:move_to_hunk()
end

function ProjectDiffScreen:handle_list_move()
  local list_item = self.status_list_view:get_current_list_item()
  if not list_item then return end

  self.model:set_entry_id(list_item.id)
  self.diff_view:render()
  self.diff_view:move_to_hunk()
end

function ProjectDiffScreen:focus_relative_buffer_entry(buffer)
  local filename = buffer:get_relative_name()
  if filename == '' then
    self:move_to(function()
      return true
    end)
    return
  end

  local list_item = self:move_to(function(status)
    return status.filename == filename
  end)
  if list_item then return end

  self:move_to(function()
    return true
  end)
end

function ProjectDiffScreen:setup_list_keymaps()
  local keymaps = project_diff_preview_setting:get('keymaps')

  self.status_list_view:set_keymap({
    {
      mode = 'n',
      mapping = keymaps.commit,
      handler = loop.coroutine(function()
        self:commit()
      end),
    },
    {
      mode = 'n',
      mapping = keymaps.buffer_reset,
      handler = loop.coroutine(function()
        self:reset_file()
      end),
    },
    {
      mode = 'n',
      mapping = keymaps.buffer_stage,
      handler = loop.coroutine(function()
        self:stage_file()
      end),
    },
    {
      mode = 'n',
      mapping = keymaps.buffer_unstage,
      handler = loop.coroutine(function()
        self:unstage_file()
      end),
    },
    {
      mode = 'n',
      mapping = keymaps.stage_all,
      handler = loop.coroutine(function()
        self:stage_all()
      end),
    },
    {
      mode = 'n',
      mapping = keymaps.unstage_all,
      handler = loop.coroutine(function()
        self:unstage_all()
      end),
    },
    {
      mode = 'n',
      mapping = keymaps.reset_all,
      handler = loop.coroutine(function()
        self:reset_all()
      end),
    },
    {
      mode = 'n',
      mapping = keymaps.buffer_hunk_stage,
      handler = loop.coroutine(function()
        self:stage_hunk()
      end),
    },
    {
      mode = 'n',
      mapping = keymaps.buffer_hunk_unstage,
      handler = loop.coroutine(function()
        self:unstage_hunk()
      end),
    },
    {
      mode = 'n',
      mapping = keymaps.untrack,
      handler = loop.coroutine(function()
        self:untrack_file()
      end),
    },
  })
end

function ProjectDiffScreen:setup_diff_keymaps()
  local keymaps = project_diff_preview_setting:get('keymaps')

  self.diff_view:set_keymap({
    {
      mode = 'n',
      mapping = keymaps.buffer_hunk_stage,
      handler = loop.debounce_coroutine(function()
        self:stage_hunk()
      end, 15),
    },
    {
      mode = 'n',
      mapping = keymaps.buffer_hunk_unstage,
      handler = loop.debounce_coroutine(function()
        self:unstage_hunk()
      end, 15),
    },
    {
      mode = 'n',
      mapping = keymaps.buffer_reset,
      handler = loop.debounce_coroutine(function()
        self:reset_file()
      end, 15),
    },
    {
      mode = 'n',
      mapping = keymaps.buffer_stage,
      handler = loop.debounce_coroutine(function()
        self:stage_file()
      end, 15),
    },
    {
      mode = 'n',
      mapping = keymaps.buffer_unstage,
      handler = loop.debounce_coroutine(function()
        self:unstage_file()
      end, 15),
    },
    {
      mode = 'n',
      mapping = keymaps.stage_all,
      handler = loop.debounce_coroutine(function()
        self:stage_all()
      end, 15),
    },
    {
      mode = 'n',
      mapping = keymaps.unstage_all,
      handler = loop.debounce_coroutine(function()
        self:unstage_all()
      end, 15),
    },
    {
      mode = 'n',
      mapping = keymaps.reset_all,
      handler = loop.debounce_coroutine(function()
        self:reset_all()
      end, 15),
    },
    {
      mode = 'n',
      mapping = keymaps.commit,
      handler = loop.debounce_coroutine(function()
        self:commit()
      end, 15),
    },
    {
      mode = 'n',
      mapping = {
        key = '<enter>',
        desc = 'Open buffer'
      },
      handler = loop.coroutine(function()
        self:enter_view()
      end),
    },
  })
end

function ProjectDiffScreen:setup_keymaps()
  self:setup_list_keymaps()
  self:setup_diff_keymaps()
end

function ProjectDiffScreen:create()
  local buffer = Buffer(0)

  local data, err = self.model:fetch()
  loop.free_textlock()

  if err then
    console.debug.error(err).error(err)
    return false
  end

  if utils.object.is_empty(data) then
    if self.model:conflict_status() then
      console.info('All conflicts fixed but you are still merging')
      return false
    end
    console.info('No changes found')
    return false
  end

  self.app_bar_view:define()
  self.diff_view:define()
  self.status_list_view:define()

  self.diff_view:mount()
  self.app_bar_view:mount()
  self.status_list_view:mount({
    event_handlers = {
      on_enter = function()
        self:open_file()
      end,
      on_move = function()
        self:handle_list_move()
      end,
    },
  })

  self.diff_view:render()
  self.app_bar_view:render()
  self.status_list_view:render()

  self:setup_keymaps()
  self:focus_relative_buffer_entry(buffer)

  return true
end

function ProjectDiffScreen:destroy()
  self.scene:destroy()
end

function ProjectDiffScreen:untrack_file()
  local entry = self.model:get_entry()
  if not entry then return end

  loop.free_textlock()
  local filename = entry.status.filename
  local decision = console.input(string.format('确定要取消追踪文件 %s 吗？(y/N) ', filename)):lower()

  if decision ~= 'yes' and decision ~= 'y' then return end

  local _, err = self.model:untrack_file(filename)
  if err then
    console.debug.error(err)
    return
  end

  -- 重新获取文件状态并更新视图
  local entries = self.model:fetch()
  if utils.object.is_empty(entries) then
    self:destroy()
    return
  end

  -- 只更新文件列表视图
  self.status_list_view:render()
  
  -- 清空当前的 diff 视图
  self.diff_view:clear_extmarks()
  self.diff_view:clear_title()
  self.diff_view:clear_lines()
  self.diff_view:clear_notification()
  self.diff_view:reset_cursor()
  
  -- 选择下一个可用的文件
  local list_item = self.status_list_view:get_current_list_item()
  if list_item then
    self.model:set_entry_id(list_item.id)
    -- 确保新文件有 diff 数据后再渲染
    local diff = self.model:get_diff()
    if diff then
      self.diff_view:render()
      self.diff_view:move_to_hunk()
    end
  end
end

return ProjectDiffScreen
