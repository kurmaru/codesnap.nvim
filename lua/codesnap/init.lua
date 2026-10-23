local static = require("codesnap.static")
local table_utils = require("codesnap.utils.table")
local module = require("codesnap.module")
local config_module = require("codesnap.config")
local modal = require("codesnap.modal")
local path = require("codesnap.path")
local clipboard = require("codesnap.clipboard")

-- Prepare the path of the Rust module
-- Try to fetch pre-built library first, then fallback to development build
local generator = module.load_generator()

local main = {
  cwd = static.cwd,
  highlight_mode_config = nil,
}

function main.setup(config)
  static.config = table_utils.merge_config(static.config, config == nil and {} or config)
  if static.config.snapshot_config then
    path.expand_paths_in_config(static.config.snapshot_config)
  end
end

-- Save snapshot to specified save_path
--- @param save_path string
function main.save(save_path)
  if save_path == nil or save_path == "" then
    local dir = vim.fn.expand("~/Pictures/codesnap")
    vim.fn.mkdir(dir, "p")
    save_path = dir .. "/codesnap-" .. os.date("%Y-%m-%d_%H-%M-%S") .. ".png"
  end
  save_path = vim.fn.expand(save_path)

  local matched_extension = string.match(save_path, "%.(.+)$")

  if matched_extension ~= "png" and matched_extension ~= nil then
    error("The extension of save_path should be .png", 0)
  end

  generator.save(save_path, config_module.get_config())
  vim.notify("Save snapshot in " .. save_path .. " successfully")
end

-- Render the snapshot to a temporary PNG and hand it to the clipboard tool
-- that matches the clipboard Neovim is using. The Rust generator's own
-- clipboard support is only used when no such tool is available.
local function copy_snapshot(config)
  local tmp_path = vim.fn.tempname() .. ".png"
  local saved, save_err = pcall(generator.save, tmp_path, config)

  if saved then
    if clipboard.copy_image(tmp_path) then
      vim.fn.delete(tmp_path)
      vim.notify("The snapshot is copied into clipboard successfully!")
      return
    end

    if not clipboard.is_available() and pcall(generator.copy, config) then
      vim.fn.delete(tmp_path)
      vim.notify("The snapshot is copied into clipboard successfully!")
      return
    end

    vim.notify("Could not copy the snapshot to the clipboard. Image kept at " .. tmp_path, vim.log.levels.WARN)
    return
  end

  local copied, copy_err = pcall(generator.copy, config)
  if copied then
    vim.notify("The snapshot is copied into clipboard successfully!")
    return
  end

  error(save_err or copy_err or "Failed to generate the snapshot", 0)
end

-- Copy snapshot into clipboard
function main.copy()
  copy_snapshot(config_module.get_config())
end

-- Generate ASCII code snapshot and copy it into clipboard
function main.copy_ascii()
  generator.copy_ascii(config_module.get_config())
  vim.notify("The ASCII code snapshot is copied into clipboard successfully!")
end

function main.copy_highlight()
  -- Get the originally selected text
  local original_config = config_module.get_config()
  if not original_config or not original_config.content or not original_config.content.content then
    vim.notify("No code is selected", vim.log.levels.ERROR)
    return
  end

  local selected_text = original_config.content.content
  -- Get the current buffer's filetype for syntax highlighting
  local filetype = vim.bo.filetype

  -- Pop up the modal and handle the result in the callback
  modal.pop_modal(selected_text, filetype, function(selection)
    if not selection then
      vim.notify("Selection cancelled", vim.log.levels.INFO)
      return
    end

    -- Extract the selected lines from the original text
    local lines = vim.split(selected_text, "\n", { plain = true })
    local start_line, end_line = selection[1], selection[2]

    -- Validate line numbers
    if start_line < 1 or end_line > #lines or start_line > end_line then
      vim.notify("Invalid selection range", vim.log.levels.ERROR)
      return
    end

    local config = config_module.get_config()

    if not config or not config.content then
      vim.notify("Failed to get configuration", vim.log.levels.ERROR)
      return
    end

    config.content.highlight_lines = {
      { start_line, end_line, static.config.highlight_color },
    }

    copy_snapshot(config)
  end)
end

function main.save_highlight() end

return main
