local t = require('tests._helpers')
t.setup()

local ok = t.ok
local with_buf = t.with_buf

local index = require('neo_notebooks.index')
local output = require('neo_notebooks.output')
local nb = require('neo_notebooks')

-- Test: kitty output includes placement parameters (optional backend lane)
with_buf({
  '# %% [code]',
  'print(1)',
}, function(buf)
  local prev_protocol = nb.config.image_protocol
  local prev_renderer = nb.config.image_renderer
  nb.config.image_protocol = 'kitty'
  nb.config.image_renderer = 'kitty'
  local state = index.rebuild(buf)
  local cell = state.list[1]
  output.show_payload(buf, {
    id = cell.id,
    start = cell.start,
    finish = cell.finish,
    type = cell.type,
  }, {
    items = {
      { type = 'image/png', data = 'abcd', meta = { width = 10, height = 10 } },
    },
  })
  local lines = output.get_lines(buf, cell.id)
  ok(lines and lines[1]:find('\27_G', 1, true), 'kitty escape emitted')
  ok(lines[1]:find('C=1', 1, true), 'kitty cursor hold set')
  nb.config.image_protocol = prev_protocol
  nb.config.image_renderer = prev_renderer
end)

print('optional_kitty tests passed')
