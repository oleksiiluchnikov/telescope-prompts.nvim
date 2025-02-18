# telescope-prompts.nvim

A [Telescope](https://github.com/nvim-telescope/telescope.nvim) extension for managing and using AI prompts in Neovim. Browse your collection of prompt files with fuzzy-finding capabilities and execute them with your favorite AI commands or plugins.

## ✨ Features

- **Smart Prompt Management:**

  - Browse multiple prompt directories with Telescope's fuzzy-finder
  - Preview prompt contents before selection (supports Markdown with `glow` or `bat`)
  - Sort prompts by name or modification date
  - Filter by file extensions (defaults to `.md` and `.txt`)

- **Flexible Command Execution:**

  - Execute any Neovim command with the selected prompt
  - Support for both string commands and Lua functions
  - Automatic prompt text escaping for shell commands

- **Rich Integration:**

  - Multiple theme support (dropdown, cursor, ivy)
  - Customizable layout strategies
  - File preview options
  - Path display customization

- **Developer Friendly:**
  - Async file scanning for better performance
  - Extensive configuration options
  - Built-in error handling and notifications

## 📦 Installation

### Using [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
  "oleksiiluchnikov/telescope-prompts.nvim",
  dependencies = {
    "nvim-telescope/telescope.nvim",
    "nvim-lua/plenary.nvim",   -- Required by Telescope
    -- "yetone/avante.nvim",  -- Optional for AI integration
  },
  config = function()
    require("telescope").load_extension("prompts")
  end,
}
```

### Using [packer.nvim](https://github.com/wbthomason/packer.nvim)

```lua
use {
  "oleksiiluchnikov/telescope-prompts.nvim",
  requires = {
    "nvim-telescope/telescope.nvim",
    "nvim-lua/plenary.nvim",
    -- "yetone/avante.nvim",  -- Optional for AI integration
  },
  config = function()
    require("telescope").load_extension("prompts")
  end,
}
```

## ⚙️ Configuration

Configure the extension through Telescope's setup function:

```lua
require("telescope").setup({
  extensions = {
    prompts = {
      -- Directories to scan for prompts (string or table)
      dirs = {
        vim.fn.expand("~/.config/nvim/prompts"),
        vim.fn.expand("~/my-prompts"),
      },

      -- Command to execute (string or function)
      command = "AvanteEdit", -- or function(text) ... end

      -- File types to include
      file_extensions = { "md", "txt" },
      accept_all_files = false,

      -- Sorting and display
      sort_by = "name", -- or "modified"
      tail_path = false, -- Show full paths
      shorten_path = true, -- Shorten paths in display

      -- Preview options
      previewer = true,

      -- Layout customization
      theme = "dropdown", -- or "cursor", "ivy"
      layout_strategy = "flex",
      layout_config = {
        height = 0.95,
        width = 0.95,
        preview_width = 0.6,
      },
    },
  },
})
```

### Configuration Options

| Option             | Type                 | Default         | Description                                         |
| ------------------ | -------------------- | --------------- | --------------------------------------------------- |
| `dirs`             | `string\|string[]`   | `{}`            | Directories to scan for prompt files                |
| `command`          | `string\|function`   | `nil`           | Command or function to execute with selected prompt |
| `file_extensions`  | `string[]`           | `{"md", "txt"}` | Allowed file extensions                             |
| `accept_all_files` | `boolean`            | `false`         | Include all file types                              |
| `sort_by`          | `"name"\|"modified"` | `"name"`        | How to sort prompt files                            |
| `tail_path`        | `boolean`            | `false`         | Show only filenames in path display                 |
| `shorten_path`     | `boolean`            | `true`          | Shorten paths in display                            |

## 🚀 Usage

### Basic Setup

1. Create a key mapping in your Neovim config:

```lua
vim.keymap.set('n', '<leader>ap', '<cmd>Telescope prompts<cr>', {
  desc = 'Browse AI Prompts'
})
```

### Working with Prompts

#### Creating Prompt Files

Create text files in your configured prompt directories. You can use both Markdown and plain text:

```markdown
<!-- ~/.config/nvim/prompts/code-review.md -->

# Code Review Prompt

Please review this code and provide feedback on:

- Code quality and best practices
- Potential bugs or issues
- Performance considerations
- Security implications
```

```text
# ~/.config/nvim/prompts/summarize.txt
Summarize the following text in three concise bullet points:
```

```xml
<!-- ~/.config/nvim/prompts/add-lua-type-annotations.md -->
 <prompt>
     <role>
         Technical Lead maintaining code quality and type safety in a Neovim/Lua environment
     </role>

     <context>
         Working on a Neovim plugin with multiple contributors where type safety and code clarity are essential
     </context>

     <instructions>
         Add Lua type annotations following Neovim's code style conventions
     </instructions>

     <action>
         1. Add type annotations for functions and variables
         2. Use snake_case naming convention
         3. Document edge cases
         4. Ensure LSP compatibility
     </action>

     <good-example>
         ---@class Vector2D
         ---@field x number
         ---@field y number

         ---@param pos Vector2D Current position
         ---@param speed number Movement speed (pixels/sec)
         ---@return Vector2D new_pos Updated position
         local function update_position(pos, speed)
             assert(type(speed) == "number", "Speed must be a number")
             return {
                 x = pos.x + speed,
                 y = pos.y + speed
             }
         end

         ---@alias BufferState "normal"|"insert"|"visual"
         ---@class BufferInfo
         ---@field buf_id integer
         ---@field state BufferState
         ---@field options table<string, any>
     </good-example>

     <bad-example>
         ---@param x any
         local function doStuff(x)
             return x + 1
         end

         local function processBuffer(buf)
             buf.lines = buf.lines or {}
         end
     </bad-example>

     <guidelines>
         - Use snake_case for all names
         - Document parameters and returns
         - Specify type constraints
         - Ensure LSP compatibility
         - Include usage examples
     </guidelines>

     <validation>
         - Complete type annotations
         - Proper snake_case naming
         - Clear documentation
         - LSP-friendly
     </validation>
 </prompt>
```

#### Using the Picker

1. Press your mapped key (e.g., `<leader>ap`) to open the prompt picker
2. Use Telescope's features:
   - Type to fuzzy-find prompts
   - `<C-n>`/`<C-p>` to navigate
   - Preview content on the right
   - `<C-e>` to edit the prompt file
   - `<CR>` to select and execute

#### Command Execution

The plugin supports different ways to handle selected prompts:

1. **String Command:**

```lua
require("telescope").setup({
  extensions = {
    prompts = {
      command = "AvanteEdit", -- Will run :AvanteEdit <prompt-text>
    }
  }
})
```

2. **Lua Function:**

```lua
require("telescope").setup({
  extensions = {
    prompts = {
      command = function(text)
        -- Custom handling of prompt text
        require("your-ai-plugin").send_to_ai(text)
      end
    }
  }
})
```

### Tips and Tricks

- **Organizing Prompts:**

- Use subdirectories for different categories
- Add file extensions for better syntax highlighting
- Use consistent naming conventions

- **Preview Enhancement:**

  - Install `glow` for better Markdown preview
  - Or use `bat` for syntax highlighting

- **Multiple Directories:**

```lua
dirs = {
  "~/.config/nvim/prompts",
  "~/work/prompts",
  "~/personal/prompts",
}
```

## 🔧 Development

### Prerequisites

- Neovim >= 0.8.0
- Telescope.nvim
- Plenary.nvim

<!-- ### Running Tests -->
<!---->
<!-- ```bash -->
<!-- make test -->
<!-- ``` -->
<!---->
<!-- ### Debugging -->
<!---->
<!-- Enable debug logging in your Neovim config: -->
<!---->
<!-- ```lua -->
<!-- vim.g.telescope_prompts_debug = true -->
<!-- ``` -->

## 🤝 Contributing

Contributions are welcome! Here's how you can help:

- 🐛 Report bugs and issues
- 💡 Suggest new features
- 📝 Improve documentation
- 🔧 Submit pull requests

<!-- Please check out our [Contributing Guide](CONTRIBUTING.md) for guidelines. -->

## 📝 License

Copyright © 2025 [Oleksii Luchnikov](https://github.com/oleksiiluchnikov)

This project is [MIT](https://choosealicense.com/licenses/mit) licensed.
