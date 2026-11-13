-- Gear of guild members from the game (record and rules in Core/Gear.lua, upgrades in Core/Upgrades.lua).
-- Own gear: read with the own statistics (login, equipment changes, every 10 minutes), src "self".
-- Others: the inspect Game/Stats.lua already runs hands the links of a complete read here, src "seen".
-- Any secret link (instances, combat) stops the read: nothing secret is compared or stored. Nothing is
-- stored while names are made up for pictures.
-- Also per account: what recipes make (GuildyDB.craftItems, from open profession windows and from the
-- game by spell ID) and the enchant texts of this client's language (GuildyDB.enchantText).
local _, ns = ...
local G, U = ns.Gear, ns.Upgrades

local GameGear = {}
ns.GameGear = GameGear

-- What the upgrades are worked out from goes up when it changes: books (any PROFS: professions, ranks,
-- cooldowns, the craft map; a member's upgrades are worked out anew), the craft map alone (crafts) and
-- item infos loaded (info). The index of crafted pieces does not follow books: PROFS comes for
-- cooldowns and notes too (Game/Cooldowns.lua, Game/Sync.lua, Game/Roster.lua), so it only marks the index
-- to be checked; it is built again when the recipe lists really differ (CraftIndex).
-- gone: items the game said it does not have (no redraw for those, but the index and the upgrades drop them)
GameGear.books, GameGear.info, GameGear.crafts, GameGear.gone = 0, 0, 0, 0
local indexStale = true
local function BooksChanged()
  GameGear.books = GameGear.books + 1
  indexStale = true
end
ns.On("PROFS", BooksChanged)
ns.On("GEAR_INFO", function() GameGear.info = GameGear.info + 1 end)

local CRAFT_BATCH = 20 -- spell IDs asked from the game per frame
local REFRESH = 86400  -- unchanged own gear is stored and sent anew after this many seconds

local function ItemInfoFunction()
  return rawget(_G, "GetItemInfo") or (C_Item and C_Item.GetItemInfo)
end

local function InstantFunction()
  return (C_Item and rawget(C_Item, "GetItemInfoInstant")) or rawget(_G, "GetItemInfoInstant")
end

-- Equip location of itemID from what the client has at once, nil when it does not know the item yet
function GameGear.EquipLoc(itemID)
  local instant = InstantFunction()
  if not instant or not itemID then return nil end
  local _, _, _, equipLoc = ns.Try(instant, itemID)
  if ns.IsSecret(equipLoc) or type(equipLoc) ~= "string" then return nil end
  return equipLoc
end

-- true / false when the client knows whether itemID can be worn, nil when not yet
function GameGear.Equippable(itemID)
  local equipLoc = GameGear.EquipLoc(itemID)
  if equipLoc == nil then return nil end
  return equipLoc ~= "" and equipLoc ~= "INVTYPE_NON_EQUIP_IGNORE" and equipLoc ~= "INVTYPE_NON_EQUIP"
end

-- The gear book of the current guild, created on first use
local function Book(guild)
  if type(guild.gear) ~= "table" then guild.gear = {} end
  return guild.gear
end

-- quality, item level of a link (GetItemInfo's 3rd and 4th returns)
local function LinkInfo(link)
  local getInfo = ItemInfoFunction()
  if not getInfo then return nil end
  local _, _, quality, level = ns.Try(getInfo, link)
  if ns.AnySecret(quality, level) then return nil end
  return quality, level
end

-- links and item IDs of unit's slots 1..19; nil when any of them is secret
local function ReadLinks(unit)
  local getLink, getID = rawget(_G, "GetInventoryItemLink"), rawget(_G, "GetInventoryItemID")
  if not getLink then return nil end
  local links, ids = {}, {}
  for slot = 1, 19 do
    local link = ns.Try(getLink, unit, slot)
    local id = getID and ns.Try(getID, unit, slot)
    if ns.AnySecret(link, id) then return nil end
    links[slot], ids[slot] = link, id
  end
  return links, ids
end

-- Race and sex of unit, when it still shows the member with guid (guid nil: the player)
local function RaceSex(unit, guid)
  if guid then
    local now = ns.Try(rawget(_G, "UnitGUID"), unit)
    if ns.IsSecret(now) or now ~= guid then return nil end
  end
  local _, _, race = ns.Try(rawget(_G, "UnitRace"), unit)
  local sex = ns.Try(rawget(_G, "UnitSex"), unit)
  if ns.AnySecret(race, sex) then return nil end
  return type(race) == "number" and race or nil, (sex == 2 or sex == 3) and sex or nil
end

local function Same(a, b)
  if type(a) ~= "table" or type(b) ~= "table" or a.race ~= b.race or a.sex ~= b.sex then return false end
  local wa, wb = G.Wire(a).i, G.Wire(b).i
  return table.concat(wa, ",") == table.concat(wb, ",")
end

local function Share(key)
  if ns.Sync and ns.Sync.ShareGear then ns.Sync.ShareGear(key) end
end

-- Own gear, called with the own statistics (Game/Stats.lua)
function GameGear.ReadOwn()
  if ns.Anon.on then return end
  local guild = ns.GuildData()
  if not guild then return end
  local links, ids = ReadLinks("player")
  if not links then return end
  local items = G.FromLinks(links, ids, LinkInfo)
  -- nothing at all equipped is far more often a client that has not loaded the inventory yet
  if not items or not next(items) then return end
  local race, sex = RaceSex("player")
  local key = ns.Names.Key(ns.PlayerName())
  local book = Book(guild)
  local have = book[key]
  local rec = { src = "self", race = race, sex = sex, items = items }
  -- unchanged gear keeps its time for a day; then it moves up and is sent once more, so a member who
  -- logs in daily never ages out of the guild's 60 days (Gear.MAX_AGE)
  if type(have) == "table" and have.src == "self" and Same(have, rec) and type(have.ts) == "number"
    and ns.Now() - have.ts < REFRESH then return end
  rec.ts = math.max(ns.Now(), type(have) == "table" and type(have.ts) == "number" and have.ts + 1 or 0)
  book[key] = rec
  ns.Fire("GEAR", key)
  if ns.Settings().share then Share(key) end
end

-- The links of a complete inspect read of request's member (Game/Stats.lua); ids optional
function GameGear.Store(request, links, unit, ids)
  if ns.Anon.on or type(links) ~= "table" then return end
  local guild = ns.GuildData()
  if not guild then return end
  for slot = 1, 19 do
    if ns.AnySecret(links[slot], ids and ids[slot]) then return end
  end
  local items = G.FromLinks(links, ids, LinkInfo)
  if not items or not next(items) then return end
  local race, sex = RaceSex(unit, request.guid)
  local rec = { ts = ns.Now(), src = "seen", race = race, sex = sex, items = items }
  if G.Merge(Book(guild), request.key, rec) then
    ns.Fire("GEAR", request.key)
    Share(request.key)
  end
end

-- Items and the game ---------------------------------------------------------------------------------
-- Every call that reads an item the client does not have makes it ask the server (GetItemInfo,
-- GetItemStats, a tooltip, TryOn), and every answer is a GET_ITEM_INFO_RECEIVED. Found in game
-- 2026-11-13: 765 of them in 30 s, because each render read the items still loading, and the ones the
-- game does not have (bnet-sync knows items Forever lacks) never stopped loading. So each item has a
-- state for the session and is asked for at most once:
--   nil       never looked at
--   "wait"    asked, no answer yet: nothing reads it (unless C_Item.IsItemDataCachedByID says it is in)
--   "answered" the game said it loaded it: read once more; still nothing then means "gone"
--   "gone"    the game has no such item (success false): skipped everywhere, never asked again
-- A loaded item's info, stats and requirements are cached at once, so the next render reads only those.
local itemState = {}
local requestedItems = {} -- itemID -> true: asked from the game this session (never again)

local function IsItemId(id) return type(id) == "number" and id > 0 end

-- Asks the game to load itemID, once per session
local function Request(itemID)
  if not IsItemId(itemID) or requestedItems[itemID] then return end
  requestedItems[itemID] = true
  local request = C_Item and rawget(C_Item, "RequestLoadItemDataByID")
  if request then ns.Try(request, itemID) end
end

-- true / false when the client says whether it has itemID's data, nil when it cannot say
local function IsCached(itemID)
  local cached = C_Item and rawget(C_Item, "IsItemDataCachedByID")
  if not cached then return nil end
  local value = ns.Try(cached, itemID)
  if ns.IsSecret(value) then return nil end
  return value == true
end

-- Whether the game said it has no item itemID (asked once, never again this session)
function GameGear.IsGone(itemID) return itemState[itemID] == "gone" end

local infoCache = {} -- itemID -> item info of a loaded item, for the session (it does not change)

-- Upgrades' item info shape for itemID; nil while it loads (asked once per session), nil, true when the
-- game has no such item. The same table on every call once loaded: callers must not change it.
function GameGear.ItemInfo(itemID)
  local known = infoCache[itemID]
  if known then return known end
  if not IsItemId(itemID) then return nil end
  local state = itemState[itemID]
  if state == "gone" then return nil, true end
  local cached = IsCached(itemID)
  if (cached == false and state ~= "answered") or (state == "wait" and cached == nil) then
    -- not in the client: asking (once) is all; GetItemInfo would make it ask the server once more
    if not state then itemState[itemID] = "wait" end
    Request(itemID)
    return nil
  end
  local getInfo = ItemInfoFunction()
  local name, _, quality, level, reqLevel, _, _, _, equipLoc, _, _, classID, subclassID, bind
  if getInfo then
    name, _, quality, level, reqLevel, _, _, _, equipLoc, _, _, classID, subclassID, bind = ns.Try(getInfo, itemID)
  end
  if ns.AnySecret(name, quality, level, reqLevel, equipLoc, classID, subclassID, bind) then return nil end
  if type(name) ~= "string" or type(level) ~= "number" or type(equipLoc) ~= "string" then
    if state == "answered" or cached == true then
      -- the game says it has the item, and still gives nothing to work with: it never will
      itemState[itemID] = "gone"
      return nil, true
    end
    itemState[itemID] = "wait"
    Request(itemID) -- in flight already when GetItemInfo above asked: the client asks the server once
    return nil
  end
  local info = { name = name, equipLoc = equipLoc, level = level, reqLevel = type(reqLevel) == "number" and reqLevel or 0,
    classID = classID, subclassID = subclassID, bind = bind, quality = quality }
  infoCache[itemID] = info
  itemState[itemID] = nil
  return info
end

local statsCache = {} -- item string -> stats of a loaded item, for the session
local statsByID = {}  -- itemID -> its stats, for the session (no item string built on a hit)
local statsByItem = setmetatable({}, { __mode = "k" }) -- worn item table -> its stats

local function StatsFunction()
  return (C_Item and rawget(C_Item, "GetItemStats")) or rawget(_G, "GetItemStats")
end

-- The stats of itemID or of a stored worn item (its suffix counts) as GetItemStats gives them
-- ({ ITEM_MOD_*_SHORT = n, RESISTANCE0_NAME = armor }); nil while the item is not loaded (asked once)
-- or anything about it is secret, nil, true when the game has no such item
function GameGear.ItemStats(item)
  local isItem = type(item) == "table"
  local fast = (isItem and statsByItem or statsByID)[item]
  if fast then return fast end
  local id = isItem and item.id or item
  -- nothing below reads an item the client does not have (that would ask the server again)
  local info, gone = GameGear.ItemInfo(id)
  if not info then return nil, gone end
  local key = isItem and G.ItemString(item) or ("item:" .. tostring(item))
  local known = statsCache[key]
  if known then
    (isItem and statsByItem or statsByID)[item] = known
    return known
  end
  local getInfo = ItemInfoFunction()
  local name, link
  if getInfo then name, link = ns.Try(getInfo, key) end
  if ns.AnySecret(name, link) then return nil end
  local getStats = StatsFunction()
  local raw = getStats and ns.Try(getStats, type(link) == "string" and link or key)
  if ns.IsSecret(raw) then return nil end
  local stats = {}
  for k, v in pairs(type(raw) == "table" and raw or {}) do
    if ns.AnySecret(k, v) then return nil end
    if type(k) == "string" and type(v) == "number" then stats[k] = v end
  end
  statsCache[key] = stats
  if item ~= nil then (isItem and statsByItem or statsByID)[item] = stats end
  return stats
end

local requirementsCache = {} -- itemID -> what its tooltip says it needs, for the session

-- The client's own format strings of the requirement lines
local function Formats()
  return { minLevel = rawget(_G, "ITEM_MIN_LEVEL"), minSkill = rawget(_G, "ITEM_MIN_SKILL"),
    reqSkill = rawget(_G, "ITEM_REQ_SKILL"), classes = rawget(_G, "ITEM_CLASSES_ALLOWED"),
    reputation = rawget(_G, "ITEM_REQ_REPUTATION") }
end

-- The text lines of itemID's tooltip; nil when there are none yet, nil, true when any of them is secret
local function TooltipLines(itemID)
  local byID = C_TooltipInfo and rawget(C_TooltipInfo, "GetItemByID")
  if byID then
    local data = ns.Try(byID, itemID)
    if ns.IsSecret(data) then return nil, true end
    if type(data) == "table" and type(data.lines) == "table" then
      local lines = {}
      for _, line in ipairs(data.lines) do
        local text = type(line) == "table" and line.leftText or nil
        if ns.IsSecret(text) then return nil, true end
        if type(text) == "string" then lines[#lines + 1] = text end
      end
      return #lines > 0 and lines or nil
    end
  end
  local lines, _, secret = ns.GearProbe.TooltipLines("item:" .. itemID)
  if secret then return nil, true end
  if #lines == 0 then return nil end
  return lines
end

local TOOLTIP_TRIES = 3 -- empty tooltips of a loaded item before it counts as one the game never gives
local emptyTips = {}    -- itemID -> empty tooltips read of it (loaded), this session

-- What itemID needs (Upgrades.ParseRequirements: profession and rank, classes, reputation), read from
-- its tooltip once per session; nil while the item loads or the tooltip is secret (then nothing is kept),
-- nil, true when the game has no such item or its tooltip stayed empty TOOLTIP_TRIES times. The tooltip
-- is read only once the item is loaded: a tooltip of an item the client lacks asks the server again.
function GameGear.ItemRequirements(itemID)
  local known = requirementsCache[itemID]
  if known then return known end
  local info, gone = GameGear.ItemInfo(itemID)
  if not info then return nil, gone end
  if (emptyTips[itemID] or 0) >= TOOLTIP_TRIES then return nil, true end
  local lines, secret = TooltipLines(itemID)
  if not lines then
    if not secret then emptyTips[itemID] = (emptyTips[itemID] or 0) + 1 end
    return nil
  end
  local req = U.ParseRequirements(lines, Formats())
  requirementsCache[itemID] = req
  return req
end

-- The stat name the client shows for an ITEM_MOD_* key
function GameGear.StatName(key)
  local name = rawget(_G, key)
  return type(name) == "string" and name or nil
end

local GAME = { stats = GameGear.ItemStats, requirements = GameGear.ItemRequirements }
GameGear.GAME = GAME

-- What recipes make -----------------------------------------------------------------------------------

local notEquippable = {} -- spellID -> true: checked this session, makes nothing to wear
local asked = {}         -- spellID -> true: asked from the game this session
local queue, queued = {}, {}
local running = false

local function CraftMap()
  local db = ns.DB()
  if not db then return nil end
  if type(db.craftItems) ~= "table" then db.craftItems = {} end
  return db.craftItems
end

-- Records that spellID makes itemOrLink (an item ID or an item link), when it can be worn
function GameGear.LearnCraft(spellID, itemOrLink)
  if ns.AnySecret(spellID, itemOrLink) then return false end
  local itemID = type(itemOrLink) == "number" and itemOrLink or G.ParseLink(itemOrLink)
  local map = CraftMap()
  if not (map and itemID and type(spellID) == "number") then return false end
  local equippable = GameGear.Equippable(itemID)
  if equippable == false then
    notEquippable[spellID] = true
    return false
  end
  if equippable == nil then return false end
  local learned = U.Learn(map, spellID, itemID)
  if learned then
    GameGear.crafts = GameGear.crafts + 1
    BooksChanged()
  end
  return learned
end

local infoTimer
local function InfoChanged()
  if infoTimer then return end
  infoTimer = C_Timer.NewTimer(0.5, function()
    infoTimer = nil
    ns.Fire("GEAR_INFO")
  end)
end

local function RunQueue()
  local output = C_TradeSkillUI and rawget(C_TradeSkillUI, "GetRecipeOutputItemData")
  local learned = false
  for _ = 1, CRAFT_BATCH do
    local spellID = table.remove(queue, 1)
    if not spellID then break end
    queued[spellID] = nil
    asked[spellID] = true
    local data = output and ns.Try(output, spellID)
    local itemID = type(data) == "table" and data.itemID
    if type(itemID) == "number" and GameGear.LearnCraft(spellID, itemID) then learned = true end
  end
  if learned then InfoChanged() end
  if #queue > 0 then
    C_Timer.After(0, function() ns.SafeCall(RunQueue) end)
  else
    running = false
  end
end

-- Asks the game what the recipes spellIDs make, CRAFT_BATCH per frame, for those not known yet
function GameGear.ResolveCrafts(spellIDs)
  local map = CraftMap()
  if not map or not (C_TradeSkillUI and rawget(C_TradeSkillUI, "GetRecipeOutputItemData")) then return end
  for _, spellID in ipairs(spellIDs) do
    if type(spellID) == "number" and not map[spellID] and not notEquippable[spellID] and not asked[spellID] and not queued[spellID] then
      queued[spellID] = true
      queue[#queue + 1] = spellID
    end
  end
  if #queue > 0 and not running then
    running = true
    C_Timer.After(0, function() ns.SafeCall(RunQueue) end)
  end
end

-- The model ------------------------------------------------------------------------------------------
-- A model scene's player actor (UI/CharacterPage.lua), as the game's shop uses it; checked in game on
-- Forever with /guildy modeltest scene. SetModelByUnit(unit, ..., raceID) shows a body of raceID with the
-- sex of unit, hair and face from unit; Undress and TryOn then dress it in any items. The routes:
--   "player"  the own character: SetModelByUnit("player"), the real look
--   "unit"    a member some unit token shows right now: that unit, the real look
--   "donor"   else the stored race and sex: a player unit of the member's sex (the donor) with the
--             member's raceID, undressed and dressed in the stored items. Race and sex are the
--             member's by construction, never the viewer's body with someone else's race or sex.
--   "pool"    no donor around, but Game/ModelPool.lua built a body of that race and sex earlier: the page
--             borrows that scene and dresses it in the stored items (route.body)
--   "wait"    race and sex stored, but no player of that sex around and no pooled body: the portrait
--             until one shows up
--   "none"    nothing stored: the portrait
-- A dressed body stays when its donor leaves (checked in game).

-- The units that may lend their body, the viewer first
local DONORS = { "player", "target", "focus", "mouseover" }
for i = 1, 4 do DONORS[#DONORS + 1] = "party" .. i end
for i = 1, 40 do DONORS[#DONORS + 1] = "raid" .. i end
for i = 1, 40 do DONORS[#DONORS + 1] = "nameplate" .. i end

-- A player unit whose UnitSex is sex (2 or 3), one whose model is ready preferred; nil when none
function GameGear.FindDonor(sex)
  local isPlayer, unitSex = rawget(_G, "UnitIsPlayer"), rawget(_G, "UnitSex")
  local ready = rawget(_G, "IsUnitModelReadyForUI")
  local first
  for _, unit in ipairs(DONORS) do
    local player = unit == "player" or ns.Try(isPlayer, unit)
    local found = ns.Try(unitSex, unit)
    if not ns.AnySecret(player, found) and player == true and found == sex then
      if not ready then return unit end
      local isReady = ns.Try(ready, unit)
      if not ns.IsSecret(isReady) and isReady == true then return unit end
      first = first or unit
    end
  end
  return first
end

local function Record(m)
  local guild = ns.GuildData()
  local rec = guild and type(guild.gear) == "table" and guild.gear[m.key]
  return type(rec) == "table" and rec or nil
end

-- How the model shows member m: { kind = "player"|"unit"|"donor"|"wait"|"none", unit, race, sex }
function GameGear.ModelRoute(m)
  if m.key == ns.Names.Key(ns.PlayerName()) then return { kind = "player", unit = "player" } end
  local unit = m.guid and ns.GameStats.FindUnitByGuid(m.guid)
  if unit and unit ~= "player" then return { kind = "unit", unit = unit } end
  local rec = Record(m)
  if not rec or type(rec.race) ~= "number" or (rec.sex ~= 2 and rec.sex ~= 3) then return { kind = "none" } end
  local donor = GameGear.FindDonor(rec.sex)
  if donor then return { kind = "donor", unit = donor, race = rec.race, sex = rec.sex } end
  local body = ns.ModelPool and ns.ModelPool.Get(rec.race, rec.sex)
  if body then return { kind = "pool", body = body, race = rec.race, sex = rec.sex } end
  return { kind = "wait", race = rec.race, sex = rec.sex }
end

-- What the model shows for member m on route (default: ModelRoute(m)), as a string: the same string means
-- the model already shows it and is left alone (loading it again on every render makes it flicker). The
-- donor unit is not part of it: another donor of the same sex shows the same. A donor's body and a
-- pooled body show the same too, so a donor leaving or coming changes nothing.
function GameGear.ModelKey(m, route)
  route = route or GameGear.ModelRoute(m)
  local rec = Record(m)
  local ts = rec and tostring(rec.ts) or "-"
  if route.kind == "player" then return "player:" .. ts end
  if route.kind == "unit" then return "unit:" .. route.unit .. ":" .. m.key end
  if route.kind == "none" then return "none:" .. m.key end
  local kind = (route.kind == "donor" or route.kind == "pool") and "body" or route.kind
  return ("%s:%s:%s:%s:%s"):format(kind, m.key, tostring(route.race), tostring(route.sex), ts)
end

-- Loads the body of route into actor: true when the game took it
function GameGear.LoadModel(actor, route)
  if not (route.unit and type(actor) == "table" and type(actor.SetModelByUnit) == "function") then return false end
  local autoDress = route.kind ~= "donor" -- the real look wears its own gear; a donor's is replaced
  local ok, result = pcall(actor.SetModelByUnit, actor, route.unit, false, autoDress, false, true, false,
    route.kind == "donor" and route.race or nil)
  return ok and result ~= false
end

-- The picture behind the model ---------------------------------------------------------------------
-- Blizzard's dressing room art, in this order: a race atlas, the classic four race tiles
-- ("Interface\DressUpFrame\DressUpBackground-<race>1..4": 256x256, 64x256, 256x128, 64x128 over 320x384),
-- the class atlas, else nothing (the dark fill). /guildy modeltest bg tells which the client has.
GameGear.RACE_FILES = { [1] = "Human", [2] = "Orc", [3] = "Dwarf", [4] = "NightElf", [5] = "Scourge", [6] = "Tauren",
  [7] = "Gnome", [8] = "Troll", [10] = "BloodElf", [11] = "Draenei" }
GameGear.TILES = "Interface\\DressUpFrame\\DressUpBackground-"

-- The atlas info of name when the client has that atlas
function GameGear.Atlas(name)
  local textures = rawget(_G, "C_Texture")
  local info = textures and ns.Try(rawget(textures, "GetAtlasInfo"), name)
  return type(info) == "table" and info or nil
end

local function RaceAtlas(raceFile)
  local lower = raceFile:lower()
  for _, name in ipairs({ "dressingroom-background-" .. lower, "dressingroom-background-race-" .. lower }) do
    local info = GameGear.Atlas(name)
    if info then return name, info end
  end
end
GameGear.RaceAtlas = RaceAtlas

-- The background of a member of raceFile and classFile: { source = "race atlas"|"class atlas", name, info },
-- { source = "race tiles", path } or nil. probe: a texture the first tile is tried on.
function GameGear.ModelBackground(raceFile, classFile, probe)
  if type(raceFile) == "string" and raceFile ~= "" then
    local name, info = RaceAtlas(raceFile)
    if name then return { source = "race atlas", name = name, info = info } end
    local path = GameGear.TILES .. raceFile
    if probe and ns.Try(probe.SetTexture, probe, path .. "1") == true then return { source = "race tiles", path = path } end
  end
  if type(classFile) == "string" and classFile ~= "" then
    local name = "dressingroom-background-" .. classFile:lower()
    local info = GameGear.Atlas(name)
    if info then return { source = "class atlas", name = name, info = info } end
  end
  return nil
end

-- Undresses actor and dresses it in member m's stored items
function GameGear.DressStored(actor, m)
  local rec = Record(m)
  if not rec then return end
  pcall(actor.Undress, actor)
  for slot = 1, 19 do
    local item = rec.items and rec.items[slot]
    -- an item the game does not have would only be asked for again
    if item and not GameGear.IsGone(item.id) then pcall(actor.TryOn, actor, G.ItemString(item)) end
  end
end

-- The makers of cached rows as the roster shows them now: online first, then the ones seen last
local function SortMakers(a, b)
  if a.online ~= b.online then return a.online end
  if a.offline ~= b.offline then return a.offline < b.offline end
  return a.key < b.key
end
local function Refresh(rows)
  for _, row in ipairs(rows) do
    for _, maker in ipairs(row.makers) do
      local other = ns.Roster.Find(maker.key)
      maker.online = other and other.online and true or false
      maker.offline = maker.online and 0 or (other and type(other.daysOffline) == "number" and other.daysOffline * 24 or math.huge)
    end
    table.sort(row.makers, SortMakers)
  end
end

local upgradesCache = {} -- member key -> { the inputs it was worked out from, rows, state, missing }

-- The index of crafted pieces (Upgrades.Index), built once per guild, craft map (its table and
-- GameGear.crafts) and set of recipe lists of the members, not per member and not per render. PROFS and a
-- changed member list only mark it stale; when next needed the recipe lists are compared with the ones it
-- was built from (by table, else by content: a relayed book is a new table with the same recipes) and it
-- is built again only when they differ, at most once for a burst. Items loading later are taken in, and
-- items the game does not have dropped, when item infos come in.
local index = {}

local function RecipesOf(prof)
  return type(prof) == "table" and type(prof.recipes) == "table" and prof.recipes or nil
end

local function SameList(a, b)
  if #a ~= #b then return false end
  for i = 1, #a do
    if a[i] ~= b[i] then return false end
  end
  return true
end

-- Whether the members' recipe lists are the ones of books ({ [key] = { [skillLine] = recipes } }, count
-- lists in all); a list equal by content is taken over, so the next check is by table alone
local function SameBooks(books, count, guild)
  local seen = 0
  for _, other in ipairs(ns.Roster.Members()) do
    local record = guild and guild.members[other.key]
    if type(record) == "table" and type(record.profs) == "table" then
      for skillLine, prof in pairs(record.profs) do
        local recipes = RecipesOf(prof)
        if recipes then
          seen = seen + 1
          local lines = books[other.key]
          local was = lines and lines[skillLine]
          if not was then return false end
          if was ~= recipes then
            if not SameList(was, recipes) then return false end
            lines[skillLine] = recipes
          end
        end
      end
    end
  end
  return seen == count
end

local function CraftIndex(guild, all)
  local c = index
  if c.index and c.guild == guild and c.all == all and c.crafts == GameGear.crafts then
    local fresh = true
    if indexStale or c.roster ~= ns.Roster.version then
      fresh = SameBooks(c.books, c.count, guild)
      if fresh then
        indexStale, c.roster = false, ns.Roster.version
      end
    end
    if fresh then
      if #c.index.pending > 0 and (c.info ~= GameGear.info or c.gone ~= GameGear.gone) then
        c.info, c.gone = GameGear.info, GameGear.gone
        U.Resolve(c.index, GameGear.ItemInfo)
      end
      return c.index
    end
  end
  local map = all or {}
  -- crafts whose item the game said it does not have are left out (bnet-sync may know items this
  -- client has not)
  local craft = setmetatable({}, { __index = function(_, spellID)
    local itemID = map[spellID]
    if itemID and itemState[itemID] ~= "gone" then return itemID end
  end })
  local makers, books, count = {}, {}, 0
  for _, other in ipairs(ns.Roster.Members()) do
    local record = guild and guild.members[other.key]
    if type(record) == "table" and type(record.profs) == "table" then
      local profs, lines = {}, {}
      for skillLine, prof in pairs(record.profs) do
        local recipes = RecipesOf(prof)
        if recipes then
          profs[skillLine], lines[skillLine] = prof, recipes
          count = count + 1
        end
      end
      if next(profs) then
        books[other.key] = lines
        makers[#makers + 1] = { key = other.key, online = other.online and true or false,
          offline = other.online and 0 or (type(other.daysOffline) == "number" and other.daysOffline * 24 or math.huge),
          profs = profs }
      end
    end
  end
  local built = ns.Perf.Call("upgrades:", "index build", U.Index, makers, craft, GameGear.ItemInfo)
  if #built.unknown > 0 then GameGear.ResolveCrafts(built.unknown) end
  built.unknown = nil
  index = { guild = guild, all = all, crafts = GameGear.crafts, roster = ns.Roster.version, books = books, count = count,
    info = GameGear.info, gone = GameGear.gone, index = built }
  indexStale = false
  return built
end

-- The index as the character page would use it now (the warm-up, tests)
function GameGear.CraftIndexNow()
  local db = ns.DB()
  return CraftIndex(ns.GuildData(), db and type(db.craftItems) == "table" and db.craftItems or nil)
end

-- Better crafted pieces for roster member m: rows (Core/Upgrades.lua) and the state of the box:
-- "nodata" (no book of another member has a recipe whose item is known, or m's gear is unknown),
-- "none" (data, nothing better) or "rows", and the items still loading. Kept per member until their
-- gear, the guild's books, the member list or their level change, or, while items were loading, until
-- item infos come in. Spell IDs without an entry are asked from the game.
function GameGear.UpgradesFor(m)
  local guild, db = ns.GuildData(), ns.DB()
  local rec = guild and type(guild.gear) == "table" and guild.gear[m.key] or nil
  local all = db and type(db.craftItems) == "table" and db.craftItems or nil
  local c = upgradesCache[m.key]
  if c and c.rec == rec and c.ts == (rec and rec.ts) and c.level == m.level and c.books == GameGear.books
    and c.all == all and c.guild == guild and c.roster == ns.Roster.version
    and (#c.missing == 0 or (c.info == GameGear.info and c.gone == GameGear.gone)) then
    Refresh(c.rows)
    return c.rows, c.state, c.missing
  end
  local rows, state, missing = GameGear.WorkOutUpgrades(m)
  Refresh(rows)
  upgradesCache[m.key] = { rec = rec, ts = rec and rec.ts, level = m.level, books = GameGear.books, all = all, guild = guild,
    roster = ns.Roster.version, info = GameGear.info, gone = GameGear.gone, rows = rows, state = state, missing = missing }
  return rows, state, missing
end

-- Each part is measured on its own while /guildy perf runs ("upgrades: index", "upgrades: scoring")
function GameGear.WorkOutUpgrades(m)
  local lap = ns.Perf.Lap()
  local guild, db = ns.GuildData(), ns.DB()
  local all = db and type(db.craftItems) == "table" and db.craftItems or nil
  local built = CraftIndex(guild, all)
  lap("upgrades:", "index")
  local rec = guild and type(guild.gear) == "table" and guild.gear[m.key]
  if not U.HasMakers(built, m.key) or type(rec) ~= "table" then return {}, "nodata", {} end
  -- the items still loading were asked for by GameGear.ItemInfo already, once
  local rows, missing = U.ForIndex(GameGear.Who(m), rec, built, GameGear.ItemInfo, GAME)
  lap("upgrades:", "scoring")
  return rows, #rows > 0 and "rows" or "none", missing
end

-- The warm-up ---------------------------------------------------------------------------------------
-- After the login (Core/Init.lua) the guild's crafted pieces and the stored gear are walked in small steps,
-- so item infos, stats, requirements and the index are in before the character page is opened and its
-- first render reads only caches. WARM_BATCH items per step, a step every WARM_STEP seconds; in combat it
-- waits WARM_COMBAT seconds and tries again. Items still loading are walked once more after a pause, at
-- most WARM_PASSES times in all; items the game does not have are skipped. It stops when done.
GameGear.WARM_DELAY, GameGear.WARM_BATCH, GameGear.WARM_STEP, GameGear.WARM_COMBAT = 20, 5, 0.1, 2
local WARM_PASSES, WARM_PAUSE = 3, 1

local warm -- { list, pos, later, pass } while running; false when done

local function InCombat()
  local combat = ns.Try(rawget(_G, "InCombatLockdown"))
  return combat == true
end

-- Every item of the guild's crafted pieces (the index) and of the stored gear: { itemID | worn item table }
local function WarmList()
  local list, seen = {}, {}
  local built = GameGear.CraftIndexNow()
  for _, entries in pairs(built.byLoc) do
    for _, entry in ipairs(entries) do list[#list + 1] = entry.itemID end
  end
  for _, entry in ipairs(built.pending) do list[#list + 1] = entry.itemID end
  local guild = ns.GuildData()
  for _, rec in pairs(guild and type(guild.gear) == "table" and guild.gear or {}) do
    for _, item in pairs(type(rec) == "table" and type(rec.items) == "table" and rec.items or {}) do
      if type(item) == "table" and IsItemId(item.id) and not seen[item] then
        seen[item] = true
        list[#list + 1] = item
      end
    end
  end
  return list
end

-- Reads one item into the caches; false while it still loads
local function WarmOne(entry)
  local isItem = type(entry) == "table"
  local info, gone = GameGear.ItemInfo(isItem and entry.id or entry)
  if not info then return gone == true end
  GameGear.ItemStats(entry)
  if not isItem then GameGear.ItemRequirements(entry) end
  return true
end

local WarmStep
local function WarmLater(seconds) C_Timer.After(seconds, function() ns.SafeCall(WarmStep) end) end

function WarmStep()
  if not warm then return end
  if InCombat() then return WarmLater(GameGear.WARM_COMBAT) end
  if not warm.list then warm.list = WarmList() end
  for _ = 1, GameGear.WARM_BATCH do
    local entry = warm.list[warm.pos]
    if entry == nil then break end
    warm.pos = warm.pos + 1
    if not WarmOne(entry) then warm.later[#warm.later + 1] = entry end
  end
  if warm.pos <= #warm.list then return WarmLater(GameGear.WARM_STEP) end
  if #warm.later > 0 and warm.pass < WARM_PASSES then
    warm.list, warm.pos, warm.later, warm.pass = warm.later, 1, {}, warm.pass + 1
    return WarmLater(WARM_PAUSE)
  end
  warm = false
  GameGear.CraftIndexNow() -- takes in what loaded on the way
end

-- Starts the warm-up (again, once a run is done)
function GameGear.WarmUp()
  if warm then return end
  warm = { pos = 1, later = {}, pass = 1 }
  WarmLater(0)
end

-- Whether a warm-up ran to its end
function GameGear.WarmDone() return warm == false end

-- Member m as Upgrades.For sees them: level, class (with the client's class names, for the class line
-- of a tooltip) and the stored professions by their name in lower case, with the rank where known
function GameGear.Who(m)
  local names = {}
  if type(m.className) == "string" and m.className ~= "" then names[m.className] = true end
  for _, list in ipairs({ rawget(_G, "LOCALIZED_CLASS_NAMES_MALE"), rawget(_G, "LOCALIZED_CLASS_NAMES_FEMALE") }) do
    local name = type(list) == "table" and m.classFile and list[m.classFile]
    if type(name) == "string" then names[name] = true end
  end
  local profs = {}
  local record = ns.TradeSkill.Record(m)
  for skillLine, prof in pairs(record and type(record.profs) == "table" and record.profs or {}) do
    if type(prof) == "table" then
      profs[ns.TradeSkill.Name(skillLine):lower()] = type(prof.rank) == "number" and prof.rank or true
    end
  end
  return { key = m.key, level = m.level or 0, classFile = m.classFile, classNames = names, profs = profs }
end

-- Enchant texts -----------------------------------------------------------------------------------

local function Locale() return ns.Try(rawget(_G, "GetLocale")) or "enUS" end

-- The text of enchantID on itemID in this client's language: from the cache, else the line the tooltip of
-- the enchanted item has that the plain one lacks; nil when neither gives one (never the raw ID)
-- the enchantment's tooltip names nothing: { [enchantID] = { [itemID] = true } }, for the session
local enchantMisses = {}

function GameGear.EnchantText(itemID, enchantID)
  local db = ns.DB()
  if not db or type(enchantID) ~= "number" or enchantID == 0 then return nil end
  local names = G.EnchantCache(db, Locale())
  if names[enchantID] then return names[enchantID] end
  local misses = enchantMisses[enchantID]
  if misses and misses[itemID] then return nil end
  -- a tooltip of an item the client lacks would ask the server again on every render
  local info, gone = GameGear.ItemInfo(itemID)
  if not info then
    if gone then return nil end
    return nil, true
  end
  local with = ns.GearProbe.TooltipLines(("item:%d:%d"):format(itemID, enchantID))
  local without = ns.GearProbe.TooltipLines(("item:%d"):format(itemID))
  if #with == 0 or #without == 0 then return nil, true end -- the item is not loaded yet: asked again later
  local text = G.EnchantLine(with, without)
  if text then
    names[enchantID] = text
  else
    enchantMisses[enchantID] = misses or {}
    enchantMisses[enchantID][itemID] = true
  end
  return text
end

-- Events ----------------------------------------------------------------------------------------------

-- GET_ITEM_INFO_RECEIVED: a failed load (no such item) marks that item gone for the session and redraws
-- nothing (the index and the upgrades drop it when next asked, GameGear.gone); a good one lets an item
-- that was loading be read once more, and the page hears it once per burst (GEAR_INFO). Together with
-- asking once per item this ends the GEAR_INFO -> render -> request loop.
function GameGear.OnItemInfo(itemID, success)
  if not IsItemId(itemID) then return end
  local state = itemState[itemID]
  if success == false then
    if state == "gone" then return end
    itemState[itemID] = "gone"
    if requestedItems[itemID] then GameGear.gone = GameGear.gone + 1 end
    return
  end
  if state == "wait" then itemState[itemID] = "answered" end
  InfoChanged() -- once per burst; the page draws only when it waits for an item
end

-- Login: what the script wrote into the craft map that cannot be worn goes
function GameGear.Start()
  local map = CraftMap()
  if map then U.Clean(map, GameGear.Equippable) end
end

-- /guildy gearshow [name]: the stored record slot by slot, then the live links when the member is the
-- own character or the target
function GameGear.Show(name)
  name = tostring(name or ""):match("^%s*(.-)%s*$")
  local shown = name ~= "" and name or ns.PlayerName()
  local guild = ns.GuildData()
  local rec = guild and type(guild.gear) == "table" and guild.gear[ns.Names.Key(shown)]
  if type(rec) == "table" then
    ns.Print(("gearshow %s: stored, src %s, %d min old, race %s, sex %s"):format(shown, tostring(rec.src),
      math.floor((ns.Now() - (rec.ts or 0)) / 60), tostring(rec.race), tostring(rec.sex)))
    for slot = 1, 19 do
      local item = rec.items and rec.items[slot]
      if item then
        local loaded = GameGear.ItemInfo(item.id) ~= nil
        local enchant = item.e ~= 0 and (" enchant " .. item.e .. ": " .. tostring(GameGear.EnchantText(item.id, item.e))) or ""
        ns.Print(("  %d: %s, level %d, quality %d, item info %s%s"):format(slot, G.ItemString(item), item.l, item.q,
          loaded and "yes" or "no", enchant))
      end
    end
  else
    ns.Print(("gearshow %s: nothing stored"):format(shown))
  end
  ns.GearProbe.GearShow(name)
end
