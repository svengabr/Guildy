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

local CRAFT_BATCH = 20 -- spell IDs asked from the game per frame

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
  if not items then return end
  local race, sex = RaceSex("player")
  local key = ns.Names.Key(ns.PlayerName())
  local book = Book(guild)
  local have = book[key]
  local rec = { src = "self", race = race, sex = sex, items = items }
  if type(have) == "table" and have.src == "self" and Same(have, rec) then return end
  rec.ts = math.max(ns.Now(), type(have) == "table" and type(have.ts) == "number" and have.ts + 1 or 0)
  book[key] = rec
  ns.Fire("GEAR")
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
    ns.Fire("GEAR")
    Share(request.key)
  end
end

-- Upgrades' item info shape for itemID, or nil (then the game is asked to load it)
function GameGear.ItemInfo(itemID)
  local getInfo = ItemInfoFunction()
  local name, _, quality, level, reqLevel, _, _, _, equipLoc, _, _, classID, subclassID, bind
  if getInfo then
    name, _, quality, level, reqLevel, _, _, _, equipLoc, _, _, classID, subclassID, bind = ns.Try(getInfo, itemID)
  end
  if name == nil or ns.AnySecret(name, quality, level, reqLevel, equipLoc, classID, subclassID, bind) or type(level) ~= "number" then
    local request = C_Item and rawget(C_Item, "RequestLoadItemDataByID")
    if request then ns.Try(request, itemID) end
    return nil
  end
  return { name = name, equipLoc = equipLoc, level = level, reqLevel = reqLevel or 0, classID = classID,
    subclassID = subclassID, bind = bind, quality = quality }
end

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
  return U.Learn(map, spellID, itemID)
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

-- Enchant texts -----------------------------------------------------------------------------------

local function Locale() return ns.Try(rawget(_G, "GetLocale")) or "enUS" end

-- The text of enchantID on itemID in this client's language: from the cache, else the line the tooltip of
-- the enchanted item has that the plain one lacks; nil when neither gives one (never the raw ID)
function GameGear.EnchantText(itemID, enchantID)
  local db = ns.DB()
  if not db or type(enchantID) ~= "number" or enchantID == 0 then return nil end
  local names = G.EnchantCache(db, Locale())
  if names[enchantID] then return names[enchantID] end
  local with = ns.GearProbe.TooltipLines(("item:%d:%d"):format(itemID, enchantID))
  local without = ns.GearProbe.TooltipLines(("item:%d"):format(itemID))
  if #with == 0 or #without == 0 then return nil end
  local text = G.EnchantLine(with, without)
  if text then names[enchantID] = text end
  return text
end

-- Events ----------------------------------------------------------------------------------------------

function GameGear.OnItemInfo() InfoChanged() end

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
