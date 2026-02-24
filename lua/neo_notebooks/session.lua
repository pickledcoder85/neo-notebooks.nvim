local exec = require("neo_notebooks.exec")
local output = require("neo_notebooks.output")

local M = {}

function M.restart(bufnr)
  bufnr = bufnr or 0
  local win = vim.api.nvim_get_current_win()
  local cursor = vim.api.nvim_win_get_cursor(win)
  exec.stop_session(bufnr)
  output.clear_all(bufnr)
  pcall(vim.api.nvim_buf_set_var, bufnr, "neo_notebooks_exec_hashes", {})
  vim.schedule(function()
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_set_cursor(win, cursor)
      local ok_actions, actions = pcall(require, "neo_notebooks.actions")
      if ok_actions and actions then
        actions.clamp_cursor_to_cell_left(bufnr)
      end
    end
  end)
  vim.notify("NeoNotebook: Python session restarted", vim.log.levels.INFO)
end

return M
