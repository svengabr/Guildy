-- The guild's blacklist in the game (Core/Blacklist.lua holds the rules): officers from the roster,
-- adding and removing from this client, sharing every change at once (Game/Sync.lua, message BL).
local _, ns = ...

local GameBlacklist = {}
ns.GameBlacklist = GameBlacklist

local Rules = ns.Blacklist

-- Guild members and the player's own characters are never listed
local function IsProtected(name)
  if ns.Roster.IsMember(name) or ns.Names.Same(name, ns.PlayerName()) then return true end
  local db = ns.DB()
  return db ~= nil and type(db.ownChars) == "table" and db.ownChars[ns.Names.Key(name)] ~= nil
end

local ctx = { isOfficer = function(name) return ns.Roster.IsOfficer(name) end, isProtected = IsProtected }

function GameBlacklist.Ctx()
  return ctx
end

function GameBlacklist.IsProtected(name)
  return IsProtected(name)
end

-- The list of the current guild, nil outside a guild
function GameBlacklist.Book()
  local guild = ns.GuildData()
  return guild and Rules.Book(guild)
end

function GameBlacklist.CanRemove()
  return ns.Roster.IsOfficer(ns.PlayerName())
end

-- Whether the player may remove this entry: officers, and whoever added it while nobody else changed it
function GameBlacklist.CanRemoveEntry(entry)
  return Rules.CanRemove(entry, ns.PlayerName(), ctx)
end

-- Adds or updates a name. seen = { c = classFile, l = level, f = "A" | "H" } from a unit, optional.
-- Returns the entry, or nil and "name" | "protected" | "removed" | "guild".
function GameBlacklist.Add(name, tag, reason, seen)
  local book = GameBlacklist.Book()
  if not book then return nil, "guild" end
  local entry, err = Rules.Add(book, name, tag, reason, ns.PlayerName(), ns.Now(), ctx, seen)
  if not entry then return nil, err end
  ns.Fire("BLACKLIST")
  ns.Sync.ShareBlacklist({ entry })
  return entry
end

-- Removes a name (officers). Returns the entry, or nil and "officer" | "missing" | "guild".
function GameBlacklist.Remove(name)
  local book = GameBlacklist.Book()
  if not book then return nil, "guild" end
  local entry, err = Rules.Remove(book, name, ns.PlayerName(), ns.Now(), ctx)
  if not entry then return nil, err end
  ns.Fire("BLACKLIST")
  ns.Sync.ShareBlacklist({ entry })
  return entry
end

-- Seeing listed players -----------------------------------------------------------------------------------

-- The kinds' colors (hex), shared with the Blacklist tab
GameBlacklist.COLORS = { kos = "ff4848", ninja = "ff9230", insult = "c480ff", scam = "40d0c8", other = "b0a896" }

function GameBlacklist.TagLabel(tag)
  local L = ns.L
  local labels = { kos = L.BL_TAG_KOS, ninja = L.BL_TAG_NINJA, insult = L.BL_TAG_INSULT, scam = L.BL_TAG_SCAM,
    other = L.BL_TAG_OTHER }
  return labels[Rules.Tag(tag)]
end

-- The live entry of a name, nil when not listed or now in the guild (an entry from before stays quiet)
function GameBlacklist.Find(name)
  if ns.AnySecret(name) or type(name) ~= "string" or name == "" then return nil end
  local book = GameBlacklist.Book()
  local entry = book and book[ns.Names.Key(name)]
  if not Rules.IsLive(entry) or IsProtected(entry.n) then return nil end
  return entry
end

local warned = {} -- nameKey -> when the last warning about them went out

local function Phrase(trigger)
  local L = ns.L
  return ({ group = L.BL_GROUP, invite = L.BL_INVITE, whisper = L.BL_WHISPER, trade = L.BL_TRADE })[trigger] or L.BL_SEEN
end

-- One chat line and the raid warning sound, at most once in Blacklist.ALERT_GAP per name
function GameBlacklist.Alert(entry, trigger)
  if ns.Settings().blacklistAlert == false then return end
  if not Rules.ShouldAlert(warned, ns.Names.Key(entry.n), ns.Now()) then return end
  local color = GameBlacklist.COLORS[Rules.Tag(entry.t)]
  local name = "|cff" .. color .. entry.n .. "|r"
  local label = GameBlacklist.TagLabel(entry.t)
  if entry.r then
    ns.Print(ns.L.BL_ALERT:format(name, Phrase(trigger), label, entry.r, entry.a or "?"))
  else
    ns.Print(ns.L.BL_ALERT_PLAIN:format(name, Phrase(trigger), label, entry.a or "?"))
  end
  local kit = rawget(_G, "SOUNDKIT")
  local sound = kit and kit.RAID_WARNING
  local play = rawget(_G, "PlaySound")
  if sound and play then pcall(play, sound, "Master") end
end

local FACTIONS = { Alliance = "A", Horde = "H" }

local function UnitPlayerName(unit)
  if ns.AnySecret(unit) or not ns.Try(rawget(_G, "UnitIsPlayer"), unit) then return nil end
  local name = ns.Names.FromUnit(ns.Try(UnitName, unit))
  return name ~= "" and name or nil
end

-- A player unit was seen (nameplate, target, mouseover, group, trade): fill in what is still missing of
-- them (kept locally) and warn
function GameBlacklist.OnUnit(unit, trigger)
  local entry = GameBlacklist.Find(UnitPlayerName(unit))
  if not entry then return end
  local _, class = ns.Try(rawget(_G, "UnitClass"), unit)
  local level = ns.Try(rawget(_G, "UnitLevel"), unit)
  local faction = ns.Try(rawget(_G, "UnitFactionGroup"), unit)
  if not ns.AnySecret(class, level, faction) then
    if entry.c == nil and type(class) == "string" and class:match("^%u+$") then entry.c = class end
    if entry.l == nil and type(level) == "number" and level > 0 then entry.l = level end
    if entry.f == nil then entry.f = FACTIONS[faction] end
  end
  GameBlacklist.Alert(entry, trigger)
end

-- A name without a unit (whisper, group invite)
function GameBlacklist.OnName(name, trigger)
  if ns.AnySecret(name) or type(name) ~= "string" then return end
  local entry = GameBlacklist.Find(ns.Names.Normalize(name))
  if entry then GameBlacklist.Alert(entry, trigger) end
end

-- Everyone in the group or raid
function GameBlacklist.OnGroup()
  local raid = ns.Try(rawget(_G, "IsInRaid"))
  local count = tonumber(ns.Try(rawget(_G, "GetNumGroupMembers"))) or 0
  for i = 1, raid and count or math.max(0, count - 1) do
    GameBlacklist.OnUnit((raid and "raid" or "party") .. i, "group")
  end
end

-- The line in a player's tooltip
local function OnTooltip(tooltip)
  if not (tooltip and tooltip.GetUnit) then return end
  local _, unit = tooltip:GetUnit()
  local entry = unit and GameBlacklist.Find(UnitPlayerName(unit))
  if not entry then return end
  local color = GameBlacklist.COLORS[Rules.Tag(entry.t)]
  local r, g, b = tonumber(color:sub(1, 2), 16) / 255, tonumber(color:sub(3, 4), 16) / 255, tonumber(color:sub(5, 6), 16) / 255
  tooltip:AddLine(ns.L.BL_TOOLTIP:format(GameBlacklist.TagLabel(entry.t)), r, g, b)
  if entry.r then tooltip:AddLine(entry.r, 1, 0.78, 0.59, true) end
end

function GameBlacklist.HookTooltip()
  local processor, enum = rawget(_G, "TooltipDataProcessor"), rawget(_G, "Enum")
  if processor and processor.AddTooltipPostCall and enum and enum.TooltipDataType and enum.TooltipDataType.Unit then
    processor.AddTooltipPostCall(enum.TooltipDataType.Unit, function(tooltip) ns.SafeCall(OnTooltip, tooltip) end)
  elseif rawget(_G, "GameTooltip") then
    GameTooltip:HookScript("OnTooltipSetUnit", function(tooltip) ns.SafeCall(OnTooltip, tooltip) end)
  end
end

-- "Invite to guild" and "Add to Guildy blacklist" in the right-click menu of other players (Blizzard's
-- Menu.ModifyMenu; unit menus are tagged MENU_UNIT_<type>, names in the chat open FRIEND). The blacklist
-- entry opens the Blacklist tab's add row with the name.
local MENU_TAGS = { "PLAYER", "ENEMY_PLAYER", "PARTY", "RAID_PLAYER", "FRIEND", "TARGET", "FOCUS" }

local function MenuName(context)
  if type(context) ~= "table" then return nil end
  if ns.AnySecret(context.name, context.server, context.unit) then return nil end
  local name
  if type(context.unit) == "string" and ns.Try(rawget(_G, "UnitIsPlayer"), context.unit) then
    name = ns.Names.FromUnit(ns.Try(UnitName, context.unit))
  else
    name = ns.Names.FromUnit(context.name, context.server)
  end
  if name == "" or IsProtected(name) then return nil end
  return name
end

function GameBlacklist.HookMenu()
  local menu = rawget(_G, "Menu")
  if not (menu and menu.ModifyMenu) then return end
  for _, which in ipairs(MENU_TAGS) do
    pcall(menu.ModifyMenu, "MENU_UNIT_" .. which, function(_, root, context)
      if ns.GamepadUI() then return end -- the entry would break the menu's protected actions there
      local name = MenuName(context)
      if not name or not root then return end
      root:CreateDivider()
      -- not in the guild (MenuName leaves members out): officers may invite them (UI/Popups.lua)
      if which ~= "ENEMY_PLAYER" and ns.Roster.Can().invite then
        root:CreateButton(ns.L.INVITE_TITLE, function() ns.UI.CopyInvite(name) end)
      end
      root:CreateButton(ns.L.BL_MENU, function() ns.UI.BlacklistAdd(name) end)
    end)
  end
end
