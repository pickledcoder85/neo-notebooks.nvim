local t = require('tests._helpers')
t.setup()

dofile(vim.fn.getcwd() .. '/tests/core_contract.lua')
dofile(vim.fn.getcwd() .. '/tests/integration.lua')
if not vim.g.neo_notebooks_test_skip_optional_kitty then
  dofile(vim.fn.getcwd() .. '/tests/optional_kitty.lua')
end
print('All tests passed')
vim.cmd('qa!')
