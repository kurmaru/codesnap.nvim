local static = require("codesnap.static")

local clipboard = {}

local function executable(name)
  return vim.fn.executable(name) == 1
end

local function has(feature)
  return vim.fn.has(feature) == 1
end

local function env_set(name)
  local value = vim.env[name]
  return value ~= nil and value ~= ""
end

local function run(args)
  local output = vim.fn.system(args)
  return vim.v.shell_error == 0, output
end

local function to_windows_path(path)
  if not has("wsl") then
    return path
  end
  if not executable("wslpath") then
    return nil
  end
  local ok, output = run({ "wslpath", "-w", path })
  if not ok then
    return nil
  end
  return (output:gsub("[\r\n]+$", ""))
end

local function powershell_command()
  if has("wsl") then
    return executable("powershell.exe") and "powershell.exe" or nil
  end
  if has("win32") then
    for _, name in ipairs({ "powershell", "pwsh" }) do
      if executable(name) then
        return name
      end
    end
  end
  return nil
end

local POWERSHELL_SCRIPT = {
  "param([string]$Path)",
  "$ErrorActionPreference = 'Stop'",
  "try {",
  "  Add-Type -AssemblyName System.Windows.Forms",
  "  Add-Type -AssemblyName System.Drawing",
  "  $img = [System.Drawing.Image]::FromFile($Path)",
  "  for ($i = 0; $i -lt 5; $i++) {",
  "    try {",
  "      [System.Windows.Forms.Clipboard]::SetImage($img)",
  "      $img.Dispose()",
  "      exit 0",
  "    } catch {",
  "      if ($i -eq 4) { throw }",
  "      Start-Sleep -Milliseconds 200",
  "    }",
  "  }",
  "} catch {",
  "  Write-Error $_",
  "  exit 1",
  "}",
}

-- Each backend knows how to put a PNG file on one kind of clipboard.
local backends = {
  ["wl-copy"] = {
    available = function()
      return executable("wl-copy") and env_set("WAYLAND_DISPLAY")
    end,
    copy = function(path)
      return run({ "sh", "-c", "wl-copy --type image/png < " .. vim.fn.shellescape(path) })
    end,
  },
  xclip = {
    available = function()
      return executable("xclip") and env_set("DISPLAY")
    end,
    copy = function(path)
      return run({ "sh", "-c", "xclip -selection clipboard -t image/png -i " .. vim.fn.shellescape(path) })
    end,
  },
  macos = {
    available = function()
      return executable("osascript")
    end,
    copy = function(path)
      return run({
        "osascript",
        "-e",
        "on run argv",
        "-e",
        "set the clipboard to (read (POSIX file (item 1 of argv)) as «class PNGf»)",
        "-e",
        "end run",
        path,
      })
    end,
  },
  -- Windows clipboard, from native Windows or from WSL through interop.
  powershell = {
    available = function()
      return powershell_command() ~= nil
    end,
    copy = function(path)
      local windows_path = to_windows_path(path)
      local script_path = vim.fn.tempname() .. ".ps1"
      vim.fn.writefile(POWERSHELL_SCRIPT, script_path)
      local windows_script = to_windows_path(script_path)

      local ok = false
      if windows_path and windows_script then
        ok = run({
          powershell_command(),
          "-STA",
          "-NoProfile",
          "-ExecutionPolicy",
          "Bypass",
          "-File",
          windows_script,
          windows_path,
        })
      end
      os.remove(script_path)
      return ok
    end,
  },
}

-- Neovim's provider names that tell us which clipboard the user is on.
-- Providers only carry text, so we use the name to pick the image-capable tool.
local PROVIDER_BACKENDS = {
  { "wl-copy", "wl-copy" },
  { "xclip", "xclip" },
  { "xsel", "xclip" },
  { "pbcopy", "macos" },
  { "win32yank", "powershell" },
}

local DEFAULT_ORDER = { "macos", "powershell", "wl-copy", "xclip" }

local function provider_backend()
  local ok, name = pcall(vim.fn["provider#clipboard#Executable"])
  if not ok or type(name) ~= "string" then
    return nil
  end

  name = name:lower()
  for _, entry in ipairs(PROVIDER_BACKENDS) do
    if name:find(entry[1], 1, true) then
      return entry[2]
    end
  end
  return nil
end

local function candidates()
  local order, seen = {}, {}
  local function add(name)
    if name and not seen[name] then
      seen[name] = true
      table.insert(order, name)
    end
  end

  add(provider_backend())
  for _, name in ipairs(DEFAULT_ORDER) do
    add(name)
  end
  return order
end

-- copy_command is either a function(path) -> boolean, or a list of arguments
-- where "{file}" is replaced with the PNG path.
local function copy_with_custom(command, path)
  if type(command) == "function" then
    local ok, result = pcall(command, path)
    return ok and result and true or false
  end

  local args = vim.tbl_map(function(arg)
    return (arg:gsub("{file}", function()
      return path
    end))
  end, command)
  return (run(args))
end

-- Copy a PNG file into the system clipboard. Returns true plus the backend
-- name when a clipboard tool reported success.
function clipboard.copy_image(path)
  local custom = static.config.copy_command
  if custom then
    return copy_with_custom(custom, path), "copy_command"
  end

  for _, name in ipairs(candidates()) do
    local backend = backends[name]
    if backend.available() and backend.copy(path) then
      return true, name
    end
  end

  return false
end

function clipboard.is_available()
  if static.config.copy_command then
    return true
  end

  for _, backend in pairs(backends) do
    if backend.available() then
      return true
    end
  end
  return false
end

return clipboard
