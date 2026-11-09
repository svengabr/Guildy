-- GuildyDB layout and access. Pure: takes and returns tables.
--   GuildyDB = { version, settings = {...}, guilds = { [guildKey] = { members = { [nameKey] = MemberRec } } } }
--   MemberRec = { name = "First Last", profs = { [skillLineID] = ProfRec } }
local _, ns = ...

local Store = {}
ns.Store = Store

Store.VERSION = 1

Store.DEFAULTS = {
  activityDays = 30,   -- census window in days; false = all members
  share = true,        -- send own profession data to other Guildy users
  width = 1000,
  height = 600,
  listSort = "level",  -- online list sort on the chat tab
  statMouseover = true, -- read statistics of guild members under the mouse (/guildy statmouse)
}

function Store.Init(db)
  if type(db) ~= "table" then db = {} end
  db.version = db.version or Store.VERSION
  if type(db.settings) ~= "table" then db.settings = {} end
  -- where the window was left is session state now (UI/Main.lua, UI/TabFame.lua); drop old saves
  db.settings.lastTab, db.settings.famePage = nil, nil
  for key, value in pairs(Store.DEFAULTS) do
    if db.settings[key] == nil then db.settings[key] = value end
  end
  -- 1.0.1: mouseover reading became the default. Saves from before carry the old default (off), so it
  -- is switched on once; whoever switches it off afterwards keeps it off.
  if not db.settings.mouseoverDefaultOn then
    db.settings.statMouseover = true
    db.settings.mouseoverDefaultOn = true
  end
  if type(db.guilds) ~= "table" then db.guilds = {} end
  return db
end

function Store.Guild(db, guildKey)
  local guild = db.guilds[guildKey]
  if type(guild) ~= "table" then
    guild = {}
    db.guilds[guildKey] = guild
  end
  if type(guild.members) ~= "table" then guild.members = {} end
  return guild
end

-- Member record by name (created on first use)
function Store.Member(guild, name)
  local key = ns.Names.Key(name)
  local member = guild.members[key]
  if not member then
    member = { name = ns.Names.Normalize(name), profs = {} }
    guild.members[key] = member
  end
  if type(member.profs) ~= "table" then member.profs = {} end
  return member
end

-- Removes members no longer in the guild. keep = { [nameKey] = true }. Returns how many were removed.
function Store.Prune(guild, keep)
  local removed = 0
  for key in pairs(guild.members) do
    if not keep[key] then
      guild.members[key] = nil
      removed = removed + 1
    end
  end
  return removed
end
