-- Talent points of guild members from the game (record and spec decision in Core/Talents.lua, weights in
-- Core/StatWeights.lua). Talent specs, not the profession specializations of Core/Specs.lua.
-- Own talents: read with the own statistics (login, every 10 minutes) and a moment after points were spent
-- (CHARACTER_POINTS_CHANGED), src "self", shared like the own gear (only with settings.share).
-- Others: read inside the inspect Game/Stats.lua already runs, after INSPECT_READY, src "seen"; Guildy
-- never inspects for the talents alone. A client without the talent API, or one that gives no points to an
-- inspect, leaves the record alone. Any secret value stops a read: nothing secret is compared or stored.
-- The trees' names in the client's language are kept per class (GuildyDB.talentNames = { locale,
-- classes = { [classFile] = { name1, name2, name3 } } }) for the upgrades heading; tools/bnet-sync writes
-- them as well.
local _, ns = ...
local Tal = ns.Talents

local GameTalents = {}
ns.GameTalents = GameTalents

local REFRESH = 86400 -- unchanged own talents are stored and sent anew after this many seconds
local POINTS_WAIT = 10 -- seconds after points were spent: several points in a row are one reading

local function Locale() return ns.Try(rawget(_G, "GetLocale")) or "enUS" end

-- The three talent tabs of the player (inspect false) or of the inspected unit (inspect true): { { name,
-- points } }, nil without the API, with anything secret or with other than three tabs
local function ReadTabs(inspect)
  local info = rawget(_G, "GetTalentTabInfo")
  if not info then return nil end
  local numTabs = rawget(_G, "GetNumTalentTabs")
  local count = numTabs and ns.Try(numTabs, inspect) or 3
  if ns.IsSecret(count) or count ~= 3 then return nil end
  local tabs = {}
  for i = 1, 3 do
    local a, b, c, d, e = ns.Try(info, i, inspect)
    if ns.AnySecret(a, b, c, d, e) then return nil end
    tabs[i] = Tal.TabPoints(a, b, c, d, e)
    if not tabs[i] then return nil end
  end
  return tabs
end

-- Keeps the tree names of classFile from tabs (the client's language)
local function RememberNames(classFile, tabs)
  local db = ns.DB()
  if not db or type(classFile) ~= "string" or classFile == "" then return end
  local locale = Locale()
  local cache = db.talentNames
  if type(cache) ~= "table" or cache.locale ~= locale or type(cache.classes) ~= "table" then
    cache = { locale = locale, classes = {} }
    db.talentNames = cache
  end
  cache.classes[classFile] = { tabs[1].name, tabs[2].name, tabs[3].name }
end

-- The name of classFile's talent tree in the client's language, nil when not known
function GameTalents.TreeName(classFile, tree)
  local db = ns.DB()
  local cache = db and db.talentNames
  if type(cache) ~= "table" or cache.locale ~= Locale() or type(cache.classes) ~= "table" then return nil end
  local names = cache.classes[classFile]
  local name = type(names) == "table" and names[tree]
  return type(name) == "string" and name ~= "" and name or nil
end

-- The talent book of the current guild, created on first use
local function Book(guild)
  if type(guild.talents) ~= "table" then guild.talents = {} end
  return guild.talents
end

local function Share(key)
  if ns.Sync and ns.Sync.ShareGear then ns.Sync.ShareGear(key) end
end

-- Own talents, called with the own statistics (Game/Stats.lua) and after points were spent
function GameTalents.ReadOwn()
  if ns.Anon.on then return end
  local guild = ns.GuildData()
  if not guild then return end
  local tabs = ReadTabs(false)
  local trees = Tal.FromTabs(tabs)
  if not trees then return end
  local _, classFile = ns.Try(rawget(_G, "UnitClass"), "player")
  if not ns.IsSecret(classFile) then RememberNames(classFile, tabs) end
  local key = ns.Names.Key(ns.PlayerName())
  local book = Book(guild)
  local have = book[key]
  local rec = { src = "self", trees = trees }
  if type(have) == "table" and have.src == "self" and Tal.Same(have, rec) and type(have.ts) == "number"
    and ns.Now() - have.ts < REFRESH then return end
  rec.ts = math.max(ns.Now(), type(have) == "table" and type(have.ts) == "number" and have.ts + 1 or 0)
  book[key] = rec
  ns.Fire("TALENTS", key)
  if ns.Settings().share then Share(key) end
end

local pointsTimer
-- CHARACTER_POINTS_CHANGED: read again a moment later
function GameTalents.OnPointsChanged()
  if pointsTimer then pointsTimer:Cancel() end
  pointsTimer = C_Timer.NewTimer(POINTS_WAIT, function()
    pointsTimer = nil
    ns.SafeCall(GameTalents.ReadOwn)
  end)
end

-- The talents of the member Guildy inspects, read while unit shows them (guid): { trees, classFile }, nil
-- when the game gives none (no API, secret, no points at all: an inspect that brought no talents)
function GameTalents.ReadInspect(unit, guid)
  local now = ns.Try(rawget(_G, "UnitGUID"), unit)
  if ns.IsSecret(now) or not guid or now ~= guid then return nil end
  local tabs = ReadTabs(true)
  local trees = Tal.FromTabs(tabs)
  if not trees or trees[1] + trees[2] + trees[3] == 0 then return nil end
  local _, classFile = ns.Try(rawget(_G, "UnitClass"), unit)
  if ns.IsSecret(classFile) then classFile = nil end
  if classFile then RememberNames(classFile, tabs) end
  return { trees = trees, classFile = classFile }
end

-- Stores the talents read for request's member (ReadInspect); true when they were taken. Sharing goes with
-- the gear read in the same inspect (Game/Gear.lua), or the caller's.
function GameTalents.StoreInspect(request, read)
  if ns.Anon.on or type(read) ~= "table" then return false end
  local guild = ns.GuildData()
  if not guild then return false end
  if Tal.Merge(Book(guild), request.key, { ts = ns.Now(), src = "seen", trees = read.trees }) then
    ns.Fire("TALENTS", request.key)
    return true
  end
  return false
end
