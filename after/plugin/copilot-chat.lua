local chat = require("CopilotChat")
local prompts = require('CopilotChat.prompts')
local actions = require("CopilotChat.actions")
local select = require('CopilotChat.select')
local context = require('CopilotChat.context')
local utils = require('CopilotChat.utils')
local copilotChatIntegrationsTelescope = require("CopilotChat.integrations.telescope");

require("CopilotChat").setup({
    debug = true, -- Enable debug logging
    proxy = "http://10.7.61.107:8080", -- [protocol://]host[:port] Use this proxy
    allow_insecure = false, -- Allow insecure server connections

    system_prompt = prompts.COPILOT_INSTRUCTIONS, -- System prompt to use
    model = 'gpt-4o', -- GPT model to use, 'gpt-3.5-turbo', 'gpt-4', or 'gpt-4o'
    temperature = 0.1, -- GPT temperature

    question_header = '## User ', -- Header to use for user questions
    answer_header = '## Copilot ', -- Header to use for AI answers
    error_header = '## Error ', -- Header to use for errors
    separator = '───', -- Separator to use in chat

    show_folds = true, -- Shows folds for sections in chat
    show_help = true, -- Shows help message as virtual lines when waiting for user input
    auto_follow_cursor = false, -- Auto-follow cursor in chat
    auto_insert_mode = false, -- Automatically enter insert mode when opening window and on new prompt
    insert_at_end = false, -- Move cursor to end of buffer when inserting text
    clear_chat_on_new_prompt = false, -- Clears chat on every new prompt
    highlight_selection = true, -- Highlight selection in the source buffer when in the chat window

    context = nil, -- Default context or array of contexts to use (can be specified manually in prompt via #).
    history_path = vim.fn.stdpath('data') .. '/copilotchat_history', -- Default path to stored history
    callback = nil, -- Callback to use when ask response is received
    chat_autocomplete = true,

    -- default selection (visual or line)
    selection = function(source)
        return select.visual(source) or select.line(source)
    end,

    -- default prompts
    prompts = {
        Explain = {
            prompt = '> /COPILOT_EXPLAIN\n\nWrite an explanation for the selected code as paragraphs of text.',
        },
        Review = {
            prompt = '> /COPILOT_REVIEW\n\nReview the selected code.',
            callback = function(response, source)
                local diagnostics = {}
                for line in response:gmatch('[^\r\n]+') do
                    if line:find('^line=') then
                        local start_line = nil
                        local end_line = nil
                        local message = nil
                        local single_match, message_match = line:match('^line=(%d+): (.*)$')
                        if not single_match then
                            local start_match, end_match, m_message_match = line:match('^line=(%d+)-(%d+): (.*)$')
                            if start_match and end_match then
                                start_line = tonumber(start_match)
                                end_line = tonumber(end_match)
                                message = m_message_match
                            end
                        else
                            start_line = tonumber(single_match)
                            end_line = start_line
                            message = message_match
                        end

                        if start_line and end_line then
                            table.insert(diagnostics, {
                                lnum = start_line - 1,
                                end_lnum = end_line - 1,
                                col = 0,
                                message = message,
                                severity = vim.diagnostic.severity.WARN,
                                source = 'Copilot Review',
                            })
                        end
                    end
                end
                vim.diagnostic.set(
                    vim.api.nvim_create_namespace('copilot_diagnostics'),
                    source.bufnr,
                    diagnostics
                )
            end,
        },
        Fix = {
            prompt =
            '> /COPILOT_GENERATE\n\nThere is a problem in this code. Rewrite the code to show it with the bug fixed.',
        },
        Optimize = {
            prompt = '> /COPILOT_GENERATE\n\nOptimize the selected code to improve performance and readability.',
        },
        Docs = {
            prompt = '> /COPILOT_GENERATE\n\nPlease add documentation comments to the selected code.',
        },
        Tests = {
            prompt = '> /COPILOT_GENERATE\n\nPlease generate tests for my code.',
        },
        Commit = {
            prompt =
            '> #git:staged\n\nWrite commit message for the change with commitizen convention. Make sure the title has maximum 50 characters and message is wrapped at 72 characters. Wrap the whole message in code block with language gitcommit.',
        },
    },

    -- default window options
    window = {
        layout = 'vertical',    -- 'vertical', 'horizontal', 'float', 'replace'
        width = 0.5,            -- fractional width of parent, or absolute width in columns when > 1
        height = 0.5,           -- fractional height of parent, or absolute height in rows when > 1
        -- Options below only apply to floating windows
        relative = 'editor',    -- 'editor', 'win', 'cursor', 'mouse'
        border = 'single',      -- 'none', single', 'double', 'rounded', 'solid', 'shadow'
        row = nil,              -- row position of the window, default is centered
        col = nil,              -- column position of the window, default is centered
        title = 'Copilot Chat', -- title of chat window
        footer = nil,           -- footer of chat window
        zindex = 1,             -- determines if window is on top or below other floating windows
    },

    -- default contexts
    contexts = {
        buffer = {
            description = 'Includes specified buffer in chat context. Supports input (default current).',
            input = function(callback)
                vim.ui.select(
                    vim.tbl_map(
                        function(buf)
                            return { id = buf, name = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(buf), ':p:.') }
                        end,
                        vim.tbl_filter(function(buf)
                            return utils.buf_valid(buf) and vim.fn.buflisted(buf) == 1
                        end, vim.api.nvim_list_bufs())
                    ),
                    {
                        prompt = 'Select a buffer> ',
                        format_item = function(item)
                            return item.name
                        end,
                    },
                    function(choice)
                        callback(choice and choice.id)
                    end
                )
            end,
            resolve = function(input, source)
                input = input and tonumber(input) or source.bufnr
                return {
                    context.buffer(input),
                }
            end,
        },
        buffers = {
            description = 'Includes all buffers in chat context. Supports input (default listed).',
            input = function(callback)
                vim.ui.select({ 'listed', 'visible' }, {
                    prompt = 'Select buffer scope> ',
                }, callback)
            end,
            resolve = function(input)
                input = input or 'listed'
                return context.buffers(input)
            end,
        },
        file = {
            description = 'Includes content of provided file in chat context. Supports input.',
            input = function(callback, source)
                local cwd = utils.win_cwd(source.winnr)
                local files = vim.tbl_filter(function(file)
                    return vim.fn.isdirectory(file) == 0
                end, vim.fn.glob(cwd .. '/**/*', false, true))

                vim.ui.select(files, {
                    prompt = 'Select a file> ',
                }, callback)
            end,
            resolve = function(input)
                return {
                    context.file(input),
                }
            end,
        },
        files = {
            description =
            'Includes all non-hidden files in the current workspace in chat context. Supports input (default list).',
            input = function(callback)
                local choices = utils.kv_list({
                    list = 'Only lists file names',
                    full = 'Includes file content for each file found. Can be slow on large workspaces, use with care.',
                })

                vim.ui.select(choices, {
                    prompt = 'Select files content> ',
                    format_item = function(choice)
                        return choice.key .. ' - ' .. choice.value
                    end,
                }, function(choice)
                    callback(choice and choice.key)
                end)
            end,
            resolve = function(input, source)
                return context.files(source.winnr, input == 'full')
            end,
        },
        git = {
            description = 'Requires `git`. Includes current git diff in chat context. Supports input (default unstaged).',
            input = function(callback)
                vim.ui.select({ 'unstaged', 'staged' }, {
                    prompt = 'Select diff type> ',
                }, callback)
            end,
            resolve = function(input, source)
                input = input or 'staged'
                return {
                    context.gitdiff(input, source.winnr),
                }
            end,
        },
        url = {
            description = 'Includes content of provided URL in chat context. Supports input.',
            input = function(callback)
                vim.ui.input({
                    prompt = 'Enter URL> ',
                    default = 'https://',
                }, callback)
            end,
            resolve = function(input)
                return {
                    context.url(input),
                }
            end,
        },
        register = {
            description = 'Includes contents of register in chat context. Supports input (default +, e.g clipboard).',
            input = function(callback)
                local choices = utils.kv_list({
                    ['+'] = 'synchronized with the system clipboard',
                    ['*'] = 'synchronized with the selection clipboard',
                    ['"'] = 'last deleted, changed, or yanked content',
                    ['0'] = 'last yank',
                    ['-'] = 'deleted or changed content smaller than one line',
                    ['.'] = 'last inserted text',
                    ['%'] = 'name of the current file',
                    [':'] = 'most recent executed command',
                    ['#'] = 'alternate buffer',
                    ['='] = 'result of an expression',
                    ['/'] = 'last search pattern',
                })

                vim.ui.select(choices, {
                    prompt = 'Select a register> ',
                    format_item = function(choice)
                        return choice.key .. ' - ' .. choice.value
                    end,
                }, function(choice)
                    callback(choice and choice.key)
                end)
            end,
            resolve = function(input)
                input = input or '+'
                return {
                    context.register(input),
                }
            end,
        },
    },

    -- default mappings
    mappings = {
        complete = {
            detail = 'Use @<Tab> or /<Tab> for options.',
            insert = '<Tab>',
        },
        close = {
            normal = 'q',
            insert = '<C-c>'
        },
        reset = {
            normal = '<C-l>',
            insert = '<C-l>'
        },
        submit_prompt = {
            normal = '<CR>',
            insert = '<C-s>'
        },
        accept_diff = {
            normal = '<C-y>',
            insert = '<C-y>'
        },
        yank_diff = {
            normal = 'cdy',
            register = '"',
        },
        show_diff = {
            normal = 'cds'
        },
        show_info = {
            normal = 'csps'
        },
        show_context = {
            normal = 'cuss'
        },
    },
})
-- Show help actions with telescope
vim.keymap.set('n', '<leader>cht',
    function()
        copilotChatIntegrationsTelescope.pick(actions.help_actions())
    end,
    {
        desc = "CopilotChat - Help actions",
    }
)

-- Show prompts actions with telescope
vim.keymap.set('n', '<leader>cat',
    function()
        copilotChatIntegrationsTelescope.pick(actions.prompt_actions())
    end,
    {
        desc = "CopilotChat - Prompt actions",
    }
)

-- Quick chat with Copilot
vim.keymap.set({ 'n', 'v' }, '<leader>cqc',
    function()
        local input = vim.fn.input("Quick Chat: ")
        if input ~= "" then
            local mode = vim.api.nvim_get_mode().mode
            if mode == 'n' then
                chat.ask(input, { selection = select.buffer })
            elseif mode == 'V' then
                chat.ask(input, { selection = select.visual })
            end
        end
    end,
    {
        desc = "CopilotChat - Quick chat",
    }
)
