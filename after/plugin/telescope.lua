local telescope = require("telescope")
local lga_actions = require('telescope-live-grep-args.actions')
telescope.setup({
    defaults = {
        file_ignore_patterns = {
            "node_modules"
        }
    }
})

local builtin = require('telescope.builtin')
telescope.load_extension('live_grep_args')

-- Find files
vim.keymap.set('n', '<leader>pf', builtin.find_files, {})

-- Find git files
vim.keymap.set('n', '<C-p>', builtin.git_files, {})

-- Find using grep in current buffer
vim.keymap.set('n', '<leader>ps', function()
	builtin.grep_string({ search = vim.fn.input("Grep > ") })

end)

vim.keymap.set('n', '<leader>fg', function() 
    telescope.extensions.live_grep_args.live_grep_args()
end)
