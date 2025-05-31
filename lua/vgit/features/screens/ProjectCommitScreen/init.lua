local loop = require('vgit.core.loop')
local Scene = require('vgit.ui.Scene')
local Object = require('vgit.core.Object')
local console = require('vgit.core.console')
local SimpleView = require('vgit.ui.views.SimpleView')
local KeyHelpBarView = require('vgit.ui.views.KeyHelpBarView')
local Model = require('vgit.features.screens.ProjectCommitScreen.Model')
local project_commit_preview_setting = require('vgit.settings.project_commit_preview')

local ProjectCommitScreen = Object:extend()

function ProjectCommitScreen:constructor(opts)
  opts = opts or {}
  local scene = Scene()
  local model = Model()

  return {
    name = 'Project Commit Screen',
    scene = scene,
    model = model,
    app_bar_view = KeyHelpBarView(scene, {
      keymaps = function()
        local keymaps = project_commit_preview_setting:get('keymaps')
        return { { 'Save commit', keymaps['save'] } }
      end,
    }),
    view = SimpleView(scene, {
      title = function()
        return model:get_title()
      end,
      lines = function()
        return model:get_lines()
      end,
    }, { row = 1 }, {
      elements = {
        header = false,
        footer = false,
      },
      buf_options = {
        modifiable = true,
      },
    }),
  }
end

function ProjectCommitScreen:set_cursor(cursor)
  self.window:set_cursor(cursor)
  return self
end

function ProjectCommitScreen:set_lnum(lnum)
  self.window:set_lnum(lnum)
  return self
end

function ProjectCommitScreen:call(callback)
  self.window:call(callback)
  return self
end

function ProjectCommitScreen:reset_cursor()
  Component.reset_cursor(self)
  return self
end

function ProjectCommitScreen:clear_lines()
  Component.clear_lines(self)
  return self
end

function ProjectCommitScreen:position_cursor(placement)
  Component.position_cursor(self, placement)
  return self
end

function ProjectCommitScreen:mount(opts)
  opts = opts or {}

  if self.mounted then return self end

  local config = self.config

  self.notification = Notification()
  self.header_title = HeaderTitle()
  self.buffer = Buffer():create():assign_options(config.buf_options)

  local plot = self.plot
  local buffer = self.buffer

  if config.elements.header then self.elements.header = HeaderElement():mount(plot.header_win_plot) end
  if config.elements.footer then self.elements.footer = FooterElement():mount(plot.footer_win_plot) end

  self.window = Window:open(buffer, plot.win_plot):assign_options(config.win_options)

  self.mounted = true

  return self
end

function ProjectCommitScreen:unmount()
  if not self.mounted then return self end

  local header = self.elements.header
  local footer = self.elements.footer

  self.window:close()
  if header then header:unmount() end
  if footer then footer:unmount() end

  return self
end

function ProjectCommitScreen:set_title(title, opts)
  local header = self.elements.header
  if not header then return self end

  self.header_title:set(header, title, opts)

  return self
end

function ProjectCommitScreen:clear_title()
  local header = self.elements.header
  if not header then return self end

  self.header_title:clear(header)

  return self
end

function ProjectCommitScreen:create()
  loop.free_textlock()
  local _, err = self.model:fetch()
  loop.free_textlock()

  if err then
    console.debug.error(err).error(err)
    return false
  end

  loop.free_textlock()
  self.view:define()
  self.app_bar_view:define()

  self.app_bar_view:mount()
  self.app_bar_view:render()

  self.view:mount()
  self.view:render()
  self.view:set_keymap({
    {
      mode = 'n',
      mapping = project_commit_preview_setting:get('keymaps').save,
      handler = loop.coroutine(function()
        local _, commit_err = self.model:commit(self.view:get_lines())
        loop.free_textlock()

        if commit_err then return console.debug.error(commit_err).error(commit_err) end

        console.info('成功提交更改')
        
        -- 先打开新界面,再销毁当前界面
        vim.schedule(function()
          vim.cmd('VGit project_diff_preview')
          self:destroy()
        end)
      end),
    },
  })
  self.view:set_filetype('gitcommit')

  return true
end

function ProjectCommitScreen:destroy()
  self.scene:destroy()
end

return ProjectCommitScreen
