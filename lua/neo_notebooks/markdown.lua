local cells = require("neo_notebooks.cells")

local M = {}

local function open_markdown_window(lines)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.api.nvim_set_option_value("buftype", "nofile", { buf = buf })
  vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = buf })
  vim.api.nvim_set_option_value("modifiable", false, { buf = buf })
  vim.api.nvim_set_option_value("filetype", "markdown", { buf = buf })

  local width = math.min(vim.o.columns - 6, 100)
  local height = math.min(#lines + 2, math.floor(vim.o.lines * 0.6))

  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    row = math.max(1, math.floor((vim.o.lines - height) / 2) - 1),
    col = math.max(1, math.floor((vim.o.columns - width) / 2)),
    width = width,
    height = height,
    style = "minimal",
    border = "single",
  })

  vim.api.nvim_win_set_option(win, "wrap", true)
  vim.api.nvim_win_set_option(win, "linebreak", true)

  vim.keymap.set("n", "q", function()
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
  end, { buffer = buf, silent = true, nowait = true })

  vim.keymap.set("n", "<Esc>", function()
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
  end, { buffer = buf, silent = true, nowait = true })

  return win
end

function M.preview_cell(bufnr, line)
  bufnr = bufnr or 0
  line = line or vim.api.nvim_win_get_cursor(0)[1] - 1

  local content, err = cells.get_cell_markdown(bufnr, line)
  if err then
    vim.notify(err, vim.log.levels.WARN)
    return
  end

  if not content or content == "" then
    vim.notify("Markdown cell is empty", vim.log.levels.INFO)
    return
  end

  local lines = vim.split(content, "\n", { plain = true })
  open_markdown_window(lines)
end

return M
