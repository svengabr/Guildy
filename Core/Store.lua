-- GuildyDB layout and access. Pure: takes and returns tables.
--   GuildyDB = { version, settings = {...}, guilds = { [guildKey] = { members = { [nameKey] = MemberRec } } } }
--   MemberRec = { name = "First Last", profs = { [skillLineID] = ProfRec } }
--   A guild also holds bank = what was read of the guild bank (Core/Bank.lua).
local _, ns = ...

local Store = {}
ns.Store = Store

Store.VERSION = 1
-- Bump to throw away, once per guild, every profession that was read through a profession link
-- (src "link"). 2: Guildy before 1.6.0 stored the book of the member read before on the next one
-- (Game/TradeSkill.lua); such data is not told from good data, so all of it goes and is read anew.
-- What members share of themselves and what the player's own characters know stays.
Store.PROFS_VERSION = 2

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
  -- the account view is gone: of the own characters only the names are kept (twinks in the guild,
  -- Core/Family.lua), not class, level, race and guild of each
  if type(db.ownChars) == "table" then
    for key in pairs(db.ownChars) do db.ownChars[key] = true end
  end
  return db
end

function Store.Guild(db, guildKey)
  local guild = db.guilds[guildKey]
  if type(guild) ~= "table" then
    guild = {}
    db.guilds[guildKey] = guild
  end
  if type(guild.members) ~= "table" then guild.members = {} end
  if guild.profsVersion ~= Store.PROFS_VERSION then
    Store.DropLinked(guild)
    guild.profsVersion = Store.PROFS_VERSION
  end
  return guild
end

-- Removes every profession record read through a profession link. Returns how many were removed.
function Store.DropLinked(guild)
  local removed = 0
  for _, member in pairs(guild.members) do
    if type(member) == "table" and type(member.profs) == "table" then
      for skillLine, rec in pairs(member.profs) do
        if type(rec) == "table" and rec.src == "link" then
          member.profs[skillLine] = nil
          removed = removed + 1
        end
      end
    end
  end
  return removed
end

-- Member record by name (created on first use)
function Store.Member(guild, name)
  local key = ns.Names.Key(name)
  local member = guild.members[key]
  if not member then
    member = { name = ns.Names.Normalize(name), profs = {} }
    -- while names are made up for pictures (Core/Anon.lua) nothing new is kept: the name may be one
    if not (ns.Anon and ns.Anon.on) then guild.members[key] = member end
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
