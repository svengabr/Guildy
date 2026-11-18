-- Public API for other addons: the global table GuildyAPI.
--
-- Name formatters let another addon change how character names are shown in Guildy, for example
-- nicknames the player gave to guild members. Only the shown text changes: keys, links, whispers,
-- invites and the saved data keep the real name. Guildy calls the formatters in W.ClassName, the one
-- place every tab draws a member's name.
--
--   GuildyAPI.RegisterNameFormatter("MyAddon", function(name)
--     return nicknames[name] -- the text to show, or nil to keep the name
--   end)
--   GuildyAPI.Refresh()                         -- the formatter's names changed: draw them anew
--   GuildyAPI.UnregisterNameFormatter("MyAddon")
--
-- A formatter gets the name as Guildy shows it ("First Last"), never a secret value, and returns plain
-- text: "|" is removed, so it cannot add colors, textures or links. It runs for every name drawn and
-- should be cheap. A formatter that raises an error is reported once and removed.
local _, ns = ...

local formatters = {} -- { owner = string, fn = function }, in the order they were registered

local function Report(owner, err)
  local message = "Guildy: the name formatter of " .. owner .. " failed and was removed: " .. tostring(err)
  local handler = rawget(_G, "geterrorhandler")
  if handler then handler()(message) else print(message) end
end

-- The text to show for a character name: what the first formatter returns that gives a non-empty
-- string, else the name. Secret values and made-up names for pictures (Core/Anon.lua) pass untouched.
function ns.DisplayName(name)
  if formatters[1] == nil or ns.IsSecret(name) or type(name) ~= "string" or name == "" or ns.Anon.on then
    return name
  end
  for i = 1, #formatters do
    local entry = formatters[i]
    local ok, shown = pcall(entry.fn, name)
    if not ok then
      -- a broken formatter would fail for every name in a list: reported once, then dropped
      table.remove(formatters, i)
      Report(entry.owner, shown)
      return ns.DisplayName(name)
    end
    if type(shown) == "string" and not ns.IsSecret(shown) then
      shown = shown:gsub("|", "")
      if shown ~= "" then return shown end
    end
  end
  return name
end

-- The open tab draws its names anew (UI/Main.lua listens to "NAMES")
function ns.RedrawNames()
  ns.Fire("NAMES")
end

local API = { version = 1 }

-- Adds a formatter, or replaces the one the same owner registered before
function API.RegisterNameFormatter(owner, fn)
  assert(type(owner) == "string" and owner ~= "", "GuildyAPI.RegisterNameFormatter: owner must be a non-empty string")
  assert(type(fn) == "function", "GuildyAPI.RegisterNameFormatter: fn must be a function")
  for _, entry in ipairs(formatters) do
    if entry.owner == owner then
      entry.fn = fn
      ns.RedrawNames()
      return
    end
  end
  formatters[#formatters + 1] = { owner = owner, fn = fn }
  ns.RedrawNames()
end

function API.UnregisterNameFormatter(owner)
  for i, entry in ipairs(formatters) do
    if entry.owner == owner then
      table.remove(formatters, i)
      ns.RedrawNames()
      return
    end
  end
end

-- For a registered formatter whose names changed
function API.Refresh()
  ns.RedrawNames()
end

GuildyAPI = API
