local visual_utils = {}

local function is_visual_mode()
  local mode = vim.fn.mode(1):sub(1, 1)
  return mode == "v" or mode == "V" or mode == "\22"
end

-- Returns the first and last line of the current Visual selection.
-- While Visual mode is still active (e.g. when the command is run through
-- <cmd> mappings), the '< and '> marks have not been set yet, so fall back to
-- the live Visual start position ("v") and the cursor.
local function get_range()
  if is_visual_mode() then
    local start_pos = vim.fn.getpos("v")
    local end_pos = vim.fn.getpos(".")
    if start_pos[2] > end_pos[2] or (start_pos[2] == end_pos[2] and start_pos[3] > end_pos[3]) then
      start_pos, end_pos = end_pos, start_pos
    end
    return start_pos[2], end_pos[2]
  end

  return vim.fn.line("'<"), vim.fn.line("'>")
end

visual_utils.get_range = get_range

function visual_utils.get_start_line_number()
  local start_line = get_range()
  return start_line
end

function visual_utils.get_end_line_number()
  local _, end_line = get_range()
  return end_line
end

function visual_utils.get_selected_lines()
  local start_line, end_line = get_range()
  if start_line == 0 or end_line == 0 or start_line > end_line then
    return {}
  end
  return vim.fn.getline(start_line, end_line)
end

function visual_utils.get_selected_text()
  return table.concat(visual_utils.get_selected_lines(), "\n")
end

-- Kept for backwards compatibility. The live selection is now handled by
-- get_range(), so this behaves exactly like get_selected_text().
function visual_utils.get_selected_text_realtime()
  return visual_utils.get_selected_text()
end

return visual_utils
