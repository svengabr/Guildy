-- "Upgrades aus der Gilde", pure: crafted pieces a guild member's known recipe makes that are better
-- than what a member wears and that they can use. Nothing guessed: only recipes in the guild's books,
-- items whose info the game gave, levels stored with the gear (Core/Gear.lua).
--   GuildyDB.craftItems = { [spellID] = itemID } (per account, equippable items only, at most MAX_CRAFTS)
-- Weapons, off hands and ranged are left out in this version (weapon skills and specs make "better" a guess).
local _, ns = ...

local Upgrades = {}
ns.Upgrades = Upgrades

Upgrades.MAX_CRAFTS = 3000
Upgrades.MIN_GAIN = 3
Upgrades.MAX_ROWS = 5
Upgrades.LEFT_OUT = { [16] = true, [17] = true, [18] = true, [4] = true, [19] = true }

Upgrades.SLOTS_OF = {
  INVTYPE_HEAD = { 1 }, INVTYPE_NECK = { 2 }, INVTYPE_SHOULDER = { 3 }, INVTYPE_CHEST = { 5 }, INVTYPE_ROBE = { 5 },
  INVTYPE_WAIST = { 6 }, INVTYPE_LEGS = { 7 }, INVTYPE_FEET = { 8 }, INVTYPE_WRIST = { 9 }, INVTYPE_HAND = { 10 },
  INVTYPE_FINGER = { 11, 12 }, INVTYPE_TRINKET = { 13, 14 }, INVTYPE_CLOAK = { 15 },
}

-- Best armour subclass per class (cloth 1, leather 2, mail 3, plate 4): { below level 40, from level 40 }
Upgrades.ARMOR = {
  MAGE = { 1, 1 }, PRIEST = { 1, 1 }, WARLOCK = { 1, 1 }, ROGUE = { 2, 2 }, DRUID = { 2, 2 },
  HUNTER = { 2, 3 }, SHAMAN = { 2, 3 }, WARRIOR = { 3, 4 }, PALADIN = { 3, 4 },
}
Upgrades.ARMOR_LEVEL = 40

local ARMOR_CLASS = 4

local function IsId(n) return type(n) == "number" and n == n and n > 0 and n == math.floor(n) end

-- Whether a member of classFile at level can wear the item (info: the itemInfo shape). Armour only is
-- checked: subclass 0 (rings, necks, trinkets) and cloaks always fit; else up to the class's best
-- armour for the level, or a subclass the member already wears (wornSubclasses { [subclass] = true }).
function Upgrades.Wearable(classFile, level, info, wornSubclasses)
  if info.classID ~= ARMOR_CLASS then return true end
  local sub = info.subclassID
  if sub == 0 or info.equipLoc == "INVTYPE_CLOAK" then return true end
  if wornSubclasses and wornSubclasses[sub] then return true end
  if type(sub) ~= "number" or sub < 1 or sub > 4 then return false end
  local best = Upgrades.ARMOR[classFile] or { 1, 1 }
  return sub <= ((level or 0) >= Upgrades.ARMOR_LEVEL and best[2] or best[1])
end

-- Records that recipe spellID makes itemID. True when stored; false for bad IDs, a known pair or the cap.
function Upgrades.Learn(map, spellID, itemID)
  if not (IsId(spellID) and IsId(itemID)) or map[spellID] == itemID then return false end
  if map[spellID] == nil then
    local count = 0
    for _ in pairs(map) do count = count + 1 end
    if count >= Upgrades.MAX_CRAFTS then return false end
  end
  map[spellID] = itemID
  return true
end

-- Removes entries whose item isEquippable(itemID) says is not equippable (false; nil = not known yet,
-- kept). Returns how many were removed.
function Upgrades.Clean(map, isEquippable)
  local removed = 0
  for spellID, itemID in pairs(map) do
    if not (IsId(spellID) and IsId(itemID)) or isEquippable(itemID) == false then
      map[spellID] = nil
      removed = removed + 1
    end
  end
  return removed
end

-- The slot an item for slots is compared with: the one with the lower level (empty = 0), and that level
local function Weakest(items, slots)
  local best, have
  for _, slot in ipairs(slots) do
    local item = items[slot]
    local level = item and item.l or 0
    if not best or level < have then best, have = slot, level end
  end
  return best, have
end

local function SortMakers(a, b)
  if a.online ~= b.online then return a.online end
  if a.offline ~= b.offline then return a.offline < b.offline end
  return a.key < b.key
end

-- Better crafted pieces for member { key, level, classFile } wearing gearRec (Core/Gear.lua record):
-- makers { { key, online, offline = hours, profs = { [skillLine] = ProfRec } } }, craft { [spellID] = itemID },
-- itemInfo(itemID) -> { equipLoc, level, reqLevel, classID, subclassID, bind, quality } | nil.
-- Returns rows { { slot, itemID, quality, have, offer, makers = { { key, skillLine, online } } } } (at most
-- MAX_ROWS, largest gain first, one per slot) and missing { itemID } whose info was nil.
function Upgrades.For(member, gearRec, makers, craft, itemInfo)
  local items = gearRec and gearRec.items or {}
  local worn = {}
  for _, item in pairs(items) do
    local info = itemInfo(item.id)
    if info and info.classID == ARMOR_CLASS and info.subclassID then worn[info.subclassID] = true end
  end
  local missing, missed = {}, {}
  local bySlot = {}   -- slot -> best candidate
  local makersOf = {} -- itemID -> { maker entries }, a maker once per item
  for _, maker in ipairs(makers or {}) do
    if maker.key ~= member.key then
      for skillLine, prof in pairs(maker.profs or {}) do
        for _, spellID in ipairs(type(prof) == "table" and type(prof.recipes) == "table" and prof.recipes or {}) do
          local itemID = craft[spellID]
          local info = itemID and itemInfo(itemID)
          if itemID and not info then
            if not missed[itemID] then
              missed[itemID] = true
              missing[#missing + 1] = itemID
            end
          elseif info then
            local slots = Upgrades.SLOTS_OF[info.equipLoc]
            if slots and not Upgrades.LEFT_OUT[slots[1]] and type(info.level) == "number"
              and (info.reqLevel or 0) <= (member.level or 0) and info.bind ~= 1
              and Upgrades.Wearable(member.classFile, member.level, info, worn) then
              local slot, have = Weakest(items, slots)
              if info.level - have >= Upgrades.MIN_GAIN then
                local list = makersOf[itemID]
                if not list then
                  list = {}
                  makersOf[itemID] = list
                end
                local known = false
                for _, entry in ipairs(list) do if entry.key == maker.key then known = true end end
                if not known then
                  list[#list + 1] = { key = maker.key, skillLine = skillLine, online = maker.online and true or false,
                    offline = maker.online and 0 or (maker.offline or 0) }
                end
                local current = bySlot[slot]
                if not current or info.level > current.offer or (info.level == current.offer and itemID < current.itemID) then
                  bySlot[slot] = { slot = slot, itemID = itemID, quality = info.quality, have = have, offer = info.level }
                end
              end
            end
          end
        end
      end
    end
  end
  local rows = {}
  for _, row in pairs(bySlot) do
    local list = makersOf[row.itemID]
    table.sort(list, SortMakers)
    row.makers = {}
    for i, entry in ipairs(list) do row.makers[i] = { key = entry.key, skillLine = entry.skillLine, online = entry.online } end
    rows[#rows + 1] = row
  end
  table.sort(rows, function(a, b)
    local ga, gb = a.offer - a.have, b.offer - b.have
    if ga ~= gb then return ga > gb end
    return a.slot < b.slot
  end)
  for i = #rows, Upgrades.MAX_ROWS + 1, -1 do rows[i] = nil end
  return rows, missing
end
