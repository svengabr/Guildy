-- "Upgrades aus der Gilde", pure: crafted pieces a guild member's known recipe makes that are better
-- than what a member wears and that they can use. Nothing guessed: only recipes in the guild's books,
-- items whose info, stats and tooltip the game gave, levels stored with the gear (Core/Gear.lua).
--   GuildyDB.craftItems = { [spellID] = itemID } (per account, equippable items only, at most MAX_CRAFTS)
-- Weapons, off hands and ranged are left out in this version (weapon skills and specs make "better" a guess).
-- "Better" is the member's own stat profile: the stats of what they wear, as weights (Upgrades.Profile).
local _, ns = ...

local Upgrades = {}
ns.Upgrades = Upgrades

Upgrades.MAX_CRAFTS = 3000
Upgrades.MIN_GAIN = 3       -- item levels an offer needs with a weak profile
Upgrades.MIN_RATIO = 1.10   -- an offer's score beats the worn piece's by at least 10 % ...
Upgrades.MIN_SCORE = 1      -- ... and by at least this much (about one point of the member's main stat)
Upgrades.STRONG_ITEMS = 4   -- worn pieces with stats a profile needs to be trusted
Upgrades.ARMOR_SHARE = 0.7  -- of the worn armour in one type: no lighter type is offered
Upgrades.ARMOR_KEY = "RESISTANCE0_NAME"
Upgrades.PRIMARY = { "ITEM_MOD_STRENGTH_SHORT", "ITEM_MOD_AGILITY_SHORT", "ITEM_MOD_INTELLECT_SHORT", "ITEM_MOD_SPIRIT_SHORT" }
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

-- The stat profile -----------------------------------------------------------------------------------
-- Stats are the tables the game's GetItemStats gives: { [ITEM_MOD_*_SHORT] = n, RESISTANCE0_NAME = armor }.
-- Every ITEM_MOD_* key counts (primary stats, stamina, attack and spell power, healing, hit, crit,
-- defense ...); armor does not, it only breaks ties.

local function Counts(key) return type(key) == "string" and key:sub(1, 9) == "ITEM_MOD_" end
Upgrades.Counts = Counts

local function HasStats(stats)
  for key, value in pairs(stats) do
    if Counts(key) and type(value) == "number" and value > 0 then return true end
  end
  return false
end

-- The highest of the primary stats (stamina left out: nearly every piece has it), nil when none
function Upgrades.TopPrimary(stats)
  local best, have
  for _, key in ipairs(Upgrades.PRIMARY) do
    local value = stats and stats[key]
    if type(value) == "number" and value > 0 and (not have or value > have) then best, have = key, value end
  end
  return best
end

-- The profile of the worn pieces' stats (a list of stat tables): weights { [key] = share of the sum },
-- items (pieces with stats), sum, top (the top primary stat of the sum)
function Upgrades.Profile(list)
  local totals, sum, items = {}, 0, 0
  for _, stats in ipairs(list) do
    if HasStats(stats) then items = items + 1 end
    for key, value in pairs(stats) do
      if Counts(key) and type(value) == "number" and value > 0 then
        totals[key] = (totals[key] or 0) + value
        sum = sum + value
      end
    end
  end
  local weights = {}
  for key, total in pairs(totals) do weights[key] = total / sum end
  return { weights = weights, items = items, sum = sum, top = Upgrades.TopPrimary(totals) }
end

-- Σ weight × stat of a piece under profile
function Upgrades.Score(profile, stats)
  local score = 0
  for key, value in pairs(stats or {}) do
    local weight = profile.weights[key]
    if weight and type(value) == "number" then score = score + weight * value end
  end
  return score
end

-- The counted stats offer has more (+) or less (-) than worn: { { key, delta } }, the largest first
function Upgrades.Diff(offer, worn)
  offer, worn = offer or {}, worn or {}
  local seen, list = {}, {}
  for _, stats in ipairs({ offer, worn }) do
    for key in pairs(stats) do
      if Counts(key) and not seen[key] then
        seen[key] = true
        local a, b = offer[key], worn[key]
        local delta = (type(a) == "number" and a or 0) - (type(b) == "number" and b or 0)
        if delta ~= 0 then list[#list + 1] = { key = key, delta = delta } end
      end
    end
  end
  table.sort(list, function(x, y)
    if math.abs(x.delta) ~= math.abs(y.delta) then return math.abs(x.delta) > math.abs(y.delta) end
    return x.key < y.key
  end)
  return list
end

-- The differences as one line for the tooltip, "+8 Agility, −6 Intellect", gains green, losses red;
-- name(key) gives the client's stat name (the key itself where it has none). nil for no difference.
function Upgrades.DiffText(diff, name)
  local parts = {}
  for _, d in ipairs(diff or {}) do
    local size = math.abs(d.delta)
    local number = size == math.floor(size) and tostring(size) or ("%.1f"):format(size)
    parts[#parts + 1] = ("%s%s %s|r"):format(d.delta > 0 and "|cff4ce64c+" or "|cffff5a5a−", number, name(d.key) or d.key)
  end
  return #parts > 0 and table.concat(parts, ", ") or nil
end

-- The armour subclass (1 cloth .. 4 plate) of at least ARMOR_SHARE of the pieces in list, else nil
function Upgrades.ArmorType(list)
  local count = {}
  for _, sub in ipairs(list) do count[sub] = (count[sub] or 0) + 1 end
  for sub, n in pairs(count) do
    if n / #list >= Upgrades.ARMOR_SHARE then return sub end
  end
  return nil
end

-- Requirements from the tooltip -------------------------------------------------------------------------
-- formats: the client's global format strings { minLevel = ITEM_MIN_LEVEL, minSkill = ITEM_MIN_SKILL,
-- reqSkill = ITEM_REQ_SKILL, classes = ITEM_CLASSES_ALLOWED, reputation = ITEM_REQ_REPUTATION }

local patterns = {} -- format -> { pattern, order }

-- A Lua pattern for a format string and the argument number of each capture; nil for no format
local function Pattern(fmt)
  if type(fmt) ~= "string" or fmt == "" then return nil end
  local known = patterns[fmt]
  if known then return known[1], known[2] end
  local out, order, i, nextArg = { "^" }, {}, 1, 1
  while i <= #fmt do
    local index, kind, after = fmt:match("^%%(%d+)%$([sd])()", i)
    if not index then kind, after = fmt:match("^%%([sd])()", i) end
    if kind then
      local arg = index and tonumber(index) or nextArg
      if not index then nextArg = nextArg + 1 end
      order[#order + 1] = arg
      out[#out + 1] = kind == "d" and "(%d+)" or "(.+)"
      i = after
    elseif fmt:sub(i, i + 1) == "%%" then
      out[#out + 1] = "%%"
      i = i + 2
    else
      local c = fmt:sub(i, i)
      out[#out + 1] = c:find("[%^%$%(%)%%%.%[%]%*%+%-%?]") and ("%" .. c) or c
      i = i + 1
    end
  end
  out[#out + 1] = "$"
  local pattern = table.concat(out)
  patterns[fmt] = { pattern, order }
  return pattern, order
end

-- The arguments of fmt that line was written with, by their number; nil when it was not
local function Match(fmt, line)
  local pattern, order = Pattern(fmt)
  if not pattern then return nil end
  local found = { line:match(pattern) }
  if #found == 0 then return nil end
  local args = {}
  for i, arg in ipairs(order) do args[arg] = found[i] end
  return args
end

local function Trim(text) return (text:gsub("^%s+", ""):gsub("%s+$", "")) end

-- What the tooltip lines say an item needs: { skill, rank, classes = { names }, reputation = true }
function Upgrades.ParseRequirements(lines, formats)
  local req = {}
  for _, raw in ipairs(lines or {}) do
    local line = Trim((tostring(raw):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")))
    if not Match(formats.minLevel, line) then -- the required level is in the item info already
      local args = Match(formats.minSkill, line)
      if args then
        req.skill, req.rank = Trim(args[1] or ""), tonumber(args[2])
      elseif Match(formats.reputation, line) then
        req.reputation = true
      else
        args = Match(formats.classes, line)
        if args then
          req.classes = {}
          for name in (args[1] or ""):gmatch("[^,]+") do req.classes[#req.classes + 1] = Trim(name) end
        else
          args = Match(formats.reqSkill, line)
          if args then req.skill = Trim(args[1] or "") end
        end
      end
    end
  end
  return req
end

-- Whether member { classNames = { [name] = true }, profs = { [lower name] = rank | true } } meets req.
-- A reputation cannot be checked for others: never met. A profession whose rank is not known counts.
function Upgrades.Meets(req, member)
  if req.reputation then return false end
  if req.classes then
    local names = {}
    for name in pairs(member.classNames or {}) do names[name:lower()] = true end
    local ok = false
    for _, name in ipairs(req.classes) do ok = ok or names[name:lower()] == true end
    if not ok then return false end
  end
  if req.skill then
    local have = (member.profs or {})[req.skill:lower()]
    if not have then return false end
    if type(have) == "number" and req.rank and have < req.rank then return false end
  end
  return true
end

-- Upgrades --------------------------------------------------------------------------------------------

local function SortMakers(a, b)
  if a.online ~= b.online then return a.online end
  if a.offline ~= b.offline then return a.offline < b.offline end
  return a.key < b.key
end

local function IsArmour(info)
  return info ~= nil and info.classID == ARMOR_CLASS and type(info.subclassID) == "number" and info.subclassID >= 1
    and info.subclassID <= 4 and info.equipLoc ~= "INVTYPE_CLOAK"
end

local function NoRequirements() return {} end

-- Better crafted pieces for member { key, level, classFile, classNames, profs } wearing gearRec (Core/Gear.lua
-- record): makers { { key, online, offline = hours, profs = { [skillLine] = ProfRec } } }, craft { [spellID] =
-- itemID }, itemInfo(itemID) -> { equipLoc, level, reqLevel, classID, subclassID, bind, quality } | nil,
-- game { stats(itemID | worn item) -> stat table | nil, requirements(itemID) -> req | nil } (nil: not loaded).
-- An offer counts when it fits the slot, level, armour and binding, its requirements are met and it beats
-- the worn piece's score by MIN_RATIO and MIN_SCORE; with a weak profile (fewer than STRONG_ITEMS pieces with
-- stats) instead when its top primary stat is the worn piece's (empty slot: the profile's) and its level is
-- MIN_GAIN higher. Returns rows { { slot, itemID, quality, have, offer, gain, diff, makers = { { key, skillLine,
-- online } } } } (at most MAX_ROWS, largest gain first, one per slot) and missing { itemID } (info, stats or
-- tooltip not loaded yet).
function Upgrades.For(member, gearRec, makers, craft, itemInfo, game)
  local items = gearRec and gearRec.items or {}
  local requirements = game.requirements or NoRequirements
  local missing, missed = {}, {}
  local function Miss(itemID)
    if not missed[itemID] then
      missed[itemID] = true
      missing[#missing + 1] = itemID
    end
  end
  -- what is worn: armour types, stats per slot, the profile
  local worn, armour, wornStats, list = {}, {}, {}, {}
  for slot, item in pairs(items) do
    local info = itemInfo(item.id)
    if info and info.classID == ARMOR_CLASS and info.subclassID then worn[info.subclassID] = true end
    if IsArmour(info) then armour[#armour + 1] = info.subclassID end
    local stats = game.stats(item)
    if stats then
      wornStats[slot] = stats
      list[#list + 1] = stats
    else
      Miss(item.id)
    end
  end
  local profile = Upgrades.Profile(list)
  local strong = profile.items >= Upgrades.STRONG_ITEMS and profile.sum > 0
  local prefer = Upgrades.ArmorType(armour)
  local function WornScore(slot) return wornStats[slot] and Upgrades.Score(profile, wornStats[slot]) or 0 end
  -- the slot of slots an offer is compared with: the weaker by score (strong) or level, empty first;
  -- nil while a worn piece's stats are not loaded
  local function Target(slots)
    local best, bestScore, bestLevel
    for _, slot in ipairs(slots) do
      local item = items[slot]
      if item and not wornStats[slot] then return nil end
      local score, level = item and WornScore(slot) or -1, item and item.l or 0
      local better
      if not best then better = true
      elseif strong then better = score < bestScore or (score == bestScore and level < bestLevel)
      else better = level < bestLevel end
      if better then best, bestScore, bestLevel = slot, score, level end
    end
    return best, bestLevel
  end

  local function Judge(itemID)
    local info = itemInfo(itemID)
    if not info then
      Miss(itemID)
      return false
    end
    local slots = Upgrades.SLOTS_OF[info.equipLoc]
    if not (slots and not Upgrades.LEFT_OUT[slots[1]] and type(info.level) == "number"
      and (info.reqLevel or 0) <= (member.level or 0) and info.bind ~= 1
      and Upgrades.Wearable(member.classFile, member.level, info, worn)) then return false end
    if prefer and IsArmour(info) and info.subclassID < prefer then return false end
    local stats, req = game.stats(itemID), requirements(itemID)
    if not stats or not req then
      Miss(itemID)
      return false
    end
    if not Upgrades.Meets(req, member) then return false end
    local slot, have = Target(slots)
    if not slot then return false end
    local armor = stats[Upgrades.ARMOR_KEY]
    local candidate = { slot = slot, itemID = itemID, quality = info.quality, have = have, offer = info.level,
      armor = type(armor) == "number" and armor or 0, stats = stats }
    if strong then
      local score, current = Upgrades.Score(profile, stats), WornScore(slot)
      if score < current * Upgrades.MIN_RATIO or score - current < Upgrades.MIN_SCORE then return false end
      candidate.score, candidate.gain = score, score - current
    else
      local top = Upgrades.TopPrimary(stats)
      local want = items[slot] and Upgrades.TopPrimary(wornStats[slot]) or profile.top
      if not top or top ~= want or info.level - have < Upgrades.MIN_GAIN then return false end
      candidate.score, candidate.gain = info.level, info.level - have
    end
    return candidate
  end
  local function Better(a, b) -- a better than b for one slot
    if a.score ~= b.score then return a.score > b.score end
    if a.armor ~= b.armor then return a.armor > b.armor end
    if a.offer ~= b.offer then return a.offer > b.offer end
    return a.itemID < b.itemID
  end

  local bySlot = {}   -- slot -> best candidate
  local makersOf = {} -- itemID -> { maker entries }, a maker once per item
  local judged = {}   -- itemID -> candidate | false, once per call
  for _, maker in ipairs(makers or {}) do
    if maker.key ~= member.key then
      for skillLine, prof in pairs(maker.profs or {}) do
        for _, spellID in ipairs(type(prof) == "table" and type(prof.recipes) == "table" and prof.recipes or {}) do
          local itemID = craft[spellID]
          if itemID then
            if judged[itemID] == nil then judged[itemID] = Judge(itemID) end
            local candidate = judged[itemID]
            if candidate then
              local entries = makersOf[itemID]
              if not entries then
                entries = {}
                makersOf[itemID] = entries
              end
              local known = false
              for _, entry in ipairs(entries) do if entry.key == maker.key then known = true end end
              if not known then
                entries[#entries + 1] = { key = maker.key, skillLine = skillLine, online = maker.online and true or false,
                  offline = maker.online and 0 or (maker.offline or 0) }
              end
              local current = bySlot[candidate.slot]
              if not current or Better(candidate, current) then bySlot[candidate.slot] = candidate end
            end
          end
        end
      end
    end
  end
  local rows = {}
  for _, c in pairs(bySlot) do
    local entries = makersOf[c.itemID]
    table.sort(entries, SortMakers)
    local row = { slot = c.slot, itemID = c.itemID, quality = c.quality, have = c.have, offer = c.offer, gain = c.gain,
      diff = Upgrades.Diff(c.stats, wornStats[c.slot]), makers = {} }
    for i, entry in ipairs(entries) do row.makers[i] = { key = entry.key, skillLine = entry.skillLine, online = entry.online } end
    rows[#rows + 1] = row
  end
  table.sort(rows, function(a, b)
    if a.gain ~= b.gain then return a.gain > b.gain end
    return a.slot < b.slot
  end)
  for i = #rows, Upgrades.MAX_ROWS + 1, -1 do rows[i] = nil end
  return rows, missing
end
