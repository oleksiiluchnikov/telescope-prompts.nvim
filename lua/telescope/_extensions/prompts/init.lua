---@module 'telescope'
---@mod telescope-prompts A blazingly fast Telescope extension for managing and using prompts
---@author Oleksii Luchnikov
---@license MIT
---@copyright 2025

---@class TelescopeEntry
---@field path string Full path to the selected prompt file
---@field value any The entry's primary value
---@field ordinal string The entry's ordinal for sorting
---@field display string|function The entry's display text or display function
---@field filename string Name of the file
---@field mtime number Last modified timestamp in seconds since epoch

---@class EntryData: TelescopeEntry
---@field entry_type "file"|"directory" Type of the entry

---@alias SortingStrategy "ascending"|"descending"
---@alias LayoutStrategy "flex"|"horizontal"|"vertical"
---@alias ThemeType "dropdown"|"cursor"|"ivy"|nil
---@alias SortBy "modified"|"name"
---@alias CommandCallback fun(text: string): any

---@class LayoutConfig
---@field height number Window height (0-1)
---@field width number Window width (0-1)
---@field preview_width? number Preview width for horizontal layout (0-1)
---@field preview_height? number Preview height for vertical layout (0-1)

---@class PromptsConfig
---@field previewer boolean Enable file preview
---@field prompt_title string Title of the prompt picker
---@field sorting_strategy SortingStrategy Sort direction
---@field layout_strategy LayoutStrategy Layout strategy
---@field layout_config LayoutConfig Layout configuration
---@field theme? ThemeType Optional theme
---@field dirs string|string[] Directories to scan for prompts
---@field file_extensions? string[] Allowed file extensions (e.g., ["md", "txt"])
---@field accept_all_files? boolean Accept all file types regardless of extension
---@field sort_by? SortBy Sort criteria for file listing
---@field command? string|CommandCallback Command to execute on selection
---@field tail_path? boolean Show only filename in path display
---@field shorten_path? boolean Shorten paths in display
---@field entry_maker? fun(entry: EntryData): TelescopeEntry Custom entry maker function
---@field cwd? string Current working directory override

---@brief [[
--- A Telescope extension that provides a prompt management system.
--- Allows browsing and executing prompts from specified directories.
---
---@usage
--- ```lua
--- require('telescope').setup {
---   extensions = {
---     prompts = {
---       dirs = { "~/.config/nvim/prompts" },
---       file_extensions = { "md", "txt" },
---       command = function(text)
---         -- Handle the prompt text
---       end
---     }
---   }
--- }
--- ```
---@brief ]]

local has_telescope, telescope = pcall(require, "telescope")
if not has_telescope then
	error("This plugin requires nvim-telescope/telescope.nvim")
end

local pickers = require("telescope.pickers")
local finders = require("telescope.finders")
local conf = require("telescope.config").values
local actions = require("telescope.actions")
local action_state = require("telescope.actions.state")
local entry_display = require("telescope.pickers.entry_display")
local previewers = require("telescope.previewers")
local t_utils = require("telescope.utils")
local Path = require("plenary.path")
local async = require("plenary.async")

---Determines the best available markdown preview command
---@param filename string Path to the markdown file
---@return string[] Command array with preview program and its arguments
---@note Prefers glow > bat > cat in order of availability
local function find_markdown_previewer_for_document(filename)
	if vim.fn.executable("glow") == 1 then
		return { "glow", "-s", "dark", filename }
	elseif vim.fn.executable("bat") == 1 then
		return { "bat", "--style=plain", "--paging=always", filename }
	end
	return { "cat", filename }
end

---@class FileInfo
---@field filename string File name
---@field path string Full file path
---@field mtime number Modification timestamp

---Create a lookup table for fast file extension checking
---@param extensions? string[] Array of file extensions without dots (e.g., ["md", "txt"])
---@return table<string, boolean> Lookup table where keys are extensions and values are true
---@note Returns empty table if no extensions provided
local function create_extension_lookup(extensions)
	if not extensions then
		return {}
	end
	local lookup = {}
	for _, ext in ipairs(extensions) do
		lookup[ext] = true
	end
	return lookup
end

---Sort files based on specified criteria
---@param files FileInfo[] Array of file information objects
---@param sort_by? SortBy Sorting criteria ("modified" or "name")
---@note "modified" sorts by mtime descending, "name" sorts by filename ascending
---@note Modifies the input array in-place
local function sort_files(files, sort_by)
	if sort_by == "modified" then
		table.sort(files, function(a, b)
			return a.mtime > b.mtime
		end)
	else
		table.sort(files, function(a, b)
			return a.filename < b.filename
		end)
	end
end

---Execute command with prompt text
---@param command string|CommandCallback Command to execute (either a Vim command string or callback function)
---@param prompt_text string The prompt text to pass to the command
---@throws "Invalid command type" When command is neither string nor function
---@note For string commands, the prompt text is shell-escaped before execution
local function execute_command(command, prompt_text)
	if type(command) == "function" then
		command(prompt_text)
	elseif type(command) == "string" then
		local escaped_text = vim.fn.shellescape(prompt_text)
		vim.cmd(string.format("%s %s", command, escaped_text))
	else
		error("Invalid command type: " .. type(command))
	end
end

---Scans a directory recursively and collects matching files
---@param dir string Directory path to scan
---@param files FileInfo[] Table to store found files
---@param should_include_file fun(filename: string): boolean Function determining if a file should be included
---@param is_async? boolean Whether to use async operations (defaults to false)
---@throws string When directory scanning fails
---@note Modifies the files array in-place by appending found files
local function scan_dir(dir, files, should_include_file, is_async)
	local fs = is_async and vim.loop or vim.uv
	local iterator, err = fs.fs_scandir(dir)
	if not iterator then
		local notify = is_async and vim.schedule(vim.notify) or vim.notify
		notify("Error scanning directory " .. dir .. ": " .. err, vim.log.levels.ERROR)
		return
	end

	while true do
		local name, type = fs.fs_scandir_next(iterator)
		if not name then
			break
		end

		local filepath = dir .. "/" .. name
		if type == "directory" then
			scan_dir(filepath, files, should_include_file, is_async)
		else
			if should_include_file(name) then
				local stat = fs.fs_stat(filepath)
				if stat then
					table.insert(files, {
						filename = name,
						path = filepath,
						mtime = stat.mtime.sec,
					})
				end
			end
		end
	end
	return files
end

---@type table<string, any>
local M = {}

---Browse and select prompt files using Telescope
---@param opts? PromptsConfig Configuration options
---@return nil
function M.prompts(opts)
	-- Merge provided opts with stored config
	opts = vim.tbl_deep_extend("force", M.config or {}, opts or {})
	-- Run in async context for better performance
	async.run(function()
		-- Ensure we have at least one directory
		if not opts.dirs or (type(opts.dirs) == "table" and #opts.dirs == 0) then
			vim.notify("No prompt directories configured.", vim.log.levels.INFO)
		end

		-- Apply telescope theme if defined
		if opts.theme then
			opts = require("telescope.themes")["get_" .. opts.theme](opts)
		end

		-- Validate and expand directories
		local dirs = type(opts.dirs) == "table" and opts.dirs or { opts.dirs }
		local valid_dirs = {}
		local invalid_dirs = {}

		---@diagnostic disable-next-line: param-type-mismatch
		for _, dir in ipairs(dirs) do
			---@diagnostic disable-next-line: param-type-mismatch
			local expanded = vim.fn.expand(dir)
			if vim.uv.fs_stat(expanded) then
				table.insert(valid_dirs, expanded)
			else
				table.insert(invalid_dirs, dir)
			end
		end

		if #valid_dirs == 0 then
			vim.notify(
				string.format(
					"No valid prompt directories found!\n"
						.. "The following directories do not exist:\n- %s\n\n"
						.. "Please check your configuration and ensure the directories exist.",
					table.concat(invalid_dirs, "\n- ")
				),
				vim.log.levels.ERROR
			)
			return
		end

		if #invalid_dirs > 0 then
			vim.notify(
				string.format(
					"Some prompt directories were not found:\n- %s\n\n" .. "Continuing with valid directories:\n- %s",
					table.concat(invalid_dirs, "\n- "),
					table.concat(valid_dirs, "\n- ")
				),
				vim.log.levels.WARN
			)
		end

		-- Setup file filtering
		local extension_lookup = create_extension_lookup(opts.file_extensions)

		---Determines whether a file should be included based on its extension
		---@param filename string The filename to check
		---@return boolean True if the file should be included
		local function should_include_file(filename)
			if opts.accept_all_files or not opts.file_extensions then
				return true
			end
			local ext = filename:match("%.([^%.]+)$")
			return extension_lookup[ext or ""] or false
		end

		-- Scan directories and collect files
		local files = {}
		for _, dir in ipairs(valid_dirs) do
			scan_dir(dir, files, should_include_file, true)
		end

		-- Sort files
		sort_files(files, opts.sort_by)

		---Creates an entry maker for prompt files
		---@return fun(entry: EntryData): TelescopeEntry Entry maker function
		local gen_from_prompt_files = function()
			local displayer = entry_display.create({
				separator = " ",
				items = {
					{ width = 0.3 }, -- filename
					{ width = 0.2 }, -- modified date
					{ remaining = true }, -- path
				},
			})

			---Create display string for an entry
			---@param entry TelescopeEntry
			local make_display = function(entry)
				---Format the display path according to configuration
				---@param path string The full file path
				---@return string The formatted path for display
				local display_path = (function(path)
					local p = Path:new(path)
					if opts.tail_path then
						local parts = p:_split()
						return parts[#parts]
					end

					if opts.shorten_path then
						return p:shorten()
					end

					local cwd = opts.cwd or vim.fn.getcwd()

					if vim.startswith(path, cwd) then
						return p:make_relative(vim.uv.cwd())
					end

					local home = vim.fn.expand("~")
					if vim.startswith(path, home) then
						return (Path:new("~") / p:make_relative(home)).filename
					end

					return path
				end)(entry.path)

				local modified = os.date("%Y-%m-%d", entry.mtime)
				return displayer({
					entry.filename or "",
					{ modified or "", "Comment" },
					{ display_path or "", "Directory" },
				})
			end

			return function(entry)
				return {
					value = entry.path,
					display = make_display,
					ordinal = entry.filename,
					path = entry.path,
					filename = entry.filename,
					mtime = entry.mtime,
				}
			end
		end

		-- Create and show picker
		---@type Picker
		pickers
			.new(opts, {
				prompt_title = opts.prompt_title,
				finder = finders.new_table({
					results = files,
					entry_maker = t_utils.get_lazy_default(opts.entry_maker, gen_from_prompt_files, opts),
				}),
				previewer = opts.previewer
						and previewers.new_termopen_previewer({
							title = "Prompt Preview",
							get_command = function(entry)
								local file_path = Path:new(entry.path)
								if not file_path:is_file() then
									return { "echo", "File not found!" }
								end
								-- Use markdown preview for markdown files
								if file_path.filename:match("%.md$") then
									return find_markdown_previewer_for_document(file_path.filename)
								end
								-- Fallback to cat for other files
								return { "cat", file_path.filename }
							end,
						})
					or false,
				sorter = conf.file_sorter(opts),
				attach_mappings = function(prompt_bufnr, map)
					actions.select_default:replace(function()
						local selection = action_state.get_selected_entry()
						if not selection or not selection.path then
							vim.notify("No valid selection", vim.log.levels.WARN)
							return
						end

						actions.close(prompt_bufnr)

						local ok, content = pcall(vim.fn.readfile, selection.path)
						if ok and content then
							local prompt_text = table.concat(content, "\n")
							if opts.command then
								execute_command(opts.command, prompt_text)
							else
								vim.notify("No command configured to handle prompt text", vim.log.levels.WARN)
							end
						else
							vim.notify("Failed to read prompt file: " .. selection.path, vim.log.levels.ERROR)
						end
					end)

					-- Add custom keymaps
					map("i", "<C-e>", function()
						local selection = action_state.get_selected_entry()
						if selection then
							actions.close(prompt_bufnr)
							vim.cmd("edit " .. vim.fn.fnameescape(selection.path))
						end
					end)

					map("n", "<C-e>", function()
						local selection = action_state.get_selected_entry()
						if selection then
							actions.close(prompt_bufnr)
							vim.cmd("edit " .. vim.fn.fnameescape(selection.path))
						end
					end)

					return true
				end,
			})
			:find()
	end, vim.schedule_wrap)
end

---Register the Telescope extension.
return telescope.register_extension({

	---Setup the extension configuration
	---@param ext_config? PromptsConfig Extension configuration
	---@return PromptsConfig Merged configuration
	setup = function(ext_config)
		---Default configuration
		---@type PromptsConfig
		local defaults = {
			previewer = true,
			prompt_title = "Prompts Library",
			sorting_strategy = "ascending",
			layout_strategy = "flex",
			layout_config = {
				height = 0.95,
				width = 0.95,
				horizontal = {
					preview_width = 0.6,
				},
				vertical = {
					preview_height = 0.7,
				},
			},
			theme = nil, -- Optional theme
			dirs = {}, -- Will be validated in init.lua
			file_extensions = { "md", "txt" }, -- Default extensions
			accept_all_files = false, -- Don't accept all files by default
			sort_by = "name", -- Default sort by name
			command = nil, -- Optional command to execute
		}

		-- Store the merged config globally so it can be accessed by the picker
		M.config = vim.tbl_deep_extend("force", defaults, ext_config or {})
		return M.config
	end,

	exports = {
		prompts = M.prompts,
	},
})
