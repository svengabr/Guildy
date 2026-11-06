-- Forever's character statistics (Blizzard's Statistics window, achievement API underneath) for the
-- Hall of Fame. Pure: catalog, parsing of the game's value strings, records, merging and month values.
--   StatRec = { ts, src = "self" | "seen" | "relay", v = { [statID] = number },
--               months = { ["2026-11"] = { ts, v } } }   -- first values seen in each month
-- Labels come from the game at runtime (GetAchievementInfo / GetCategoryInfo), so they are localized.
-- Records keep EVERY statistic the game reports (not only the catalog), zeros left out, so features
-- added later can use data collected before. A missing value in a record counts as 0.
local _, ns = ...

local Stats = {}
ns.Stats = Stats

Stats.MONTHS_KEPT = 3
Stats.MAX_VALUES = 500

-- Categories (Blizzard statistic category IDs) and the statistics Guildy tracks, in display order.
-- money = the game shows the value as gold/silver/copper.
Stats.CATALOG = {
  { id = 128, stats = { 107, 1487, 108 } },                           -- victories: creatures, killing blows, critters
  { id = 122, stats = { 60, 594, 112, 114, 115, 113, 321, 918 } },    -- deaths: total, Hogger, drowning, falls, fire, fatigue, instances, 5-man
  { id = 133, stats = { 98, 94 } },                                   -- quests: completed, abandoned
  { id = 140, stats = { 328, 333, 326, 919, 921, 334, 1146, 329, 330 } }, -- wealth
  { id = 14807, stats = { 932 } },                                    -- dungeons entered
  { id = 14821, bosses = true, stats = { 15027, 63570, 15028, 1092, 15029, 6137, 6140, 6139, 1093, 6786,
    6141, 6142, 1094, 6143, 6144, 1095, 6146, 6145, 1096, 15030, 15031, 1098, 63571, 63572, 63589, 63573,
    63574, 63575, 63580, 63581 } },                                   -- end boss kills
  { id = 145, stats = { 347, 346, 345, 922, 923, 344 } },             -- consumables
  { id = 191, stats = { 1044, 1043, 339, 342 } },                     -- gear: need, greed, mounts, epics
  { id = 134, stats = { 349, 353 } },                                 -- travel: flight paths, hearthstone
  { id = 131, stats = { 1042, 1066, 1045, 1065, 1047, 1067 } },       -- social emotes
  { id = 21, stats = { 588, 319, 320, 839 } },                        -- PvP: honorable kills, duels, battlegrounds
  { id = 147, stats = { 931 } },                                      -- reputation: factions met
}

Stats.MONEY = { [328] = true, [333] = true, [326] = true, [919] = true, [921] = true, [334] = true, [1146] = true }

-- Titles for the Hall of Fame: holder = highest value in the chosen period
Stats.TITLES = {
  { stat = 107, key = "SLAYER", icon = "Ability_Warrior_SavageBlow" },
  { stat = 98, key = "QUESTER", icon = "INV_Scroll_03" },
  { stat = 328, key = "GOLD", icon = "INV_Misc_Coin_02" },
  { stat = 329, key = "AUCTION", icon = "INV_Misc_Bag_10" },
  { stat = 60, key = "DEATHS", icon = "Ability_Rogue_FeignDeath" },
  { stat = 594, key = "HOGGER", icon = "INV_Misc_MonsterClaw_04" },
  { stat = 347, key = "FOOD", icon = "INV_Misc_Food_14" },
  { stat = 1042, key = "HUGS", icon = "Spell_Holy_Heal" },
  { stat = 112, key = "DROWNED", icon = "Spell_Shadow_DemonBreath" },
  { stat = 114, key = "FALLS", icon = "Spell_Magic_FeatherFall" },
  { stat = 349, key = "TRAVEL", icon = "INV_Misc_Map_01" },
  { stat = 1044, key = "NEED", icon = "INV_Misc_Gem_Pearl_04" },
  { stat = 932, key = "DUNGEONS", icon = "INV_Misc_Key_03" },
  { stat = 1487, key = "BLOWS", icon = "Ability_BackStab" },
}

-- The big guild totals on the Hall of Fame page ("bosses" = sum of all end boss kills)
Stats.HEADLINE = { 107, 98, 60, 328, "bosses" }

local wanted
-- { [statID] = true } for every tracked statistic
function Stats.Wanted()
  if not wanted then
    wanted = {}
    for _, category in ipairs(Stats.CATALOG) do
      for _, id in ipairs(category.stats) do wanted[id] = true end
    end
  end
  return wanted
end

function Stats.Bosses()
  for _, category in ipairs(Stats.CATALOG) do
    if category.bosses then return category.stats end
  end
  return {}
end

local function Digits(text)
  return tonumber((text:gsub("[%.,%s]", "")))
end

-- Number from the game's statistic text: "1298", "672 (Humanoid)", "--", or money with coin icons
-- ("6|T...GoldIcon...|t 88|T...SilverIcon...|t 93|T...CopperIcon...|t"; money is returned in copper).
function Stats.Parse(raw)
  if type(raw) == "number" then return raw end
  if type(raw) ~= "string" then return 0 end
  if raw:find("Icon", 1, true) then
    local total = 0
    for amount, coin in raw:gmatch("([%d%.,]+)%s*|T[^|]-UI%-(%a+)Icon") do
      local n = Digits(amount) or 0
      if coin == "Gold" then total = total + n * 10000
      elseif coin == "Silver" then total = total + n * 100
      elseif coin == "Copper" then total = total + n end
    end
    return total
  end
  local number = raw:match("^%s*([%d%.,]+)")
  return number and Digits(number) or 0
end

-- "2026-11" for a timestamp; date is os.date or WoW's date
function Stats.MonthKey(ts, date)
  date = date or os.date
  return date("%Y-%m", ts)
end

-- The month before "2026-11" -> "2026-10"
function Stats.PreviousMonth(key)
  local year, month = key:match("^(%d+)%-(%d+)$")
  year, month = tonumber(year), tonumber(month)
  if not year then return nil end
  month = month - 1
  if month == 0 then year, month = year - 1, 12 end
  return string.format("%04d-%02d", year, month)
end

local function Copy(values)
  local out = {}
  for id, value in pairs(values) do out[id] = value end
  return out
end

local function PruneMonths(months)
  local keys = {}
  for key in pairs(months) do keys[#keys + 1] = key end
  table.sort(keys)
  for i = 1, #keys - Stats.MONTHS_KEPT do months[keys[i]] = nil end
end

local PRIORITY = { self = 3, seen = 2, relay = 1 }

-- Stores newly read values (own or read nearby) for a member. Returns true when anything changed.
function Stats.Update(member, values, ts, src, date)
  local rec = member.stats
  if type(rec) ~= "table" then
    rec = { months = {} }
    member.stats = rec
  end
  rec.months = type(rec.months) == "table" and rec.months or {}
  local month = Stats.MonthKey(ts, date)
  local changed = false
  if not rec.ts or ts > rec.ts or (ts == rec.ts and (PRIORITY[src] or 0) > (PRIORITY[rec.src] or 0)) then
    rec.ts, rec.src, rec.v = ts, src, Copy(values)
    changed = true
  end
  if not rec.months[month] then
    rec.months[month] = { ts = ts, v = Copy(values) }
    changed = true
  end
  PruneMonths(rec.months)
  return changed
end

local function ValidValues(raw)
  if type(raw) ~= "table" then return nil end
  local values, count = {}, 0
  for id, value in pairs(raw) do
    id = tonumber(id)
    if id and id > 0 and id < 1e7 and type(value) == "number" and value > 0 and value < 1e12 then
      values[id] = math.floor(value)
      count = count + 1
      if count > Stats.MAX_VALUES then return nil end
    end
  end
  return values
end

-- Checks a record from the addon channel; returns a clean StatRec or nil
function Stats.Validate(raw)
  if type(raw) ~= "table" or type(raw.ts) ~= "number" then return nil end
  local values = ValidValues(raw.v)
  if not values then return nil end
  local rec = { ts = raw.ts, src = PRIORITY[raw.src] and raw.src or "relay", v = values, months = {} }
  if type(raw.m) == "table" then
    for month, snap in pairs(raw.m) do
      if type(month) == "string" and month:match("^%d%d%d%d%-%d%d$") and type(snap) == "table" and type(snap.ts) == "number" then
        local snapValues = ValidValues(snap.v)
        if snapValues then rec.months[month] = { ts = snap.ts, v = snapValues } end
      end
    end
  end
  return rec
end

-- Merges an incoming StatRec into member: newer current values win; per month the earliest snapshot.
function Stats.Merge(member, incoming)
  local rec = member.stats
  if type(rec) ~= "table" then
    rec = { months = {} }
    member.stats = rec
  end
  rec.months = type(rec.months) == "table" and rec.months or {}
  local changed = false
  if not rec.ts or incoming.ts > rec.ts
    or (incoming.ts == rec.ts and (PRIORITY[incoming.src] or 0) > (PRIORITY[rec.src] or 0)) then
    rec.ts, rec.src, rec.v = incoming.ts, incoming.src, Copy(incoming.v)
    changed = true
  end
  for month, snap in pairs(incoming.months or {}) do
    local mine = rec.months[month]
    if not mine or snap.ts < mine.ts then
      rec.months[month] = { ts = snap.ts, v = Copy(snap.v) }
      changed = true
    end
  end
  PruneMonths(rec.months)
  return changed
end

-- The record as sent on the channel (string keys for JSON)
function Stats.Wire(rec)
  local function Keys(values)
    local out = {}
    for id, value in pairs(values or {}) do out[tostring(id)] = value end
    return out
  end
  local months = {}
  for month, snap in pairs(rec.months or {}) do months[month] = { ts = snap.ts, v = Keys(snap.v) } end
  return { ts = rec.ts, src = rec.src, v = Keys(rec.v), m = months }
end

-- { [nameKey] = ts } of the members with statistics
function Stats.Digest(guild)
  local digest = {}
  for key, member in pairs(guild.members or {}) do
    if type(member.stats) == "table" and member.stats.ts then digest[key] = member.stats.ts end
  end
  return digest
end

local function StatValue(values, id)
  if not values then return nil end
  if id == "bosses" then
    local sum, any = 0, false
    for _, boss in ipairs(Stats.Bosses()) do
      if values[boss] then
        sum = sum + values[boss]
        any = true
      end
    end
    return any and sum or 0
  end
  return values[id] or 0
end

-- Value of statistic id ("bosses" = all end bosses) for a member record in a period:
--   "all"   = the current value
--   "month" = growth in the month of now (since the first values seen this month)
--   "last"  = growth in the month before (between the first values of both months)
-- Returns value (or nil when unknown) and the timestamp the period's count starts at.
function Stats.Value(rec, id, period, now, date)
  if type(rec) ~= "table" or not rec.v then return nil end
  local current = StatValue(rec.v, id)
  if period == "all" or not period then return current, nil end
  local months = rec.months or {}
  local this = Stats.MonthKey(now, date)
  if period == "month" then
    local base = months[this]
    local start = base and StatValue(base.v, id)
    if not current or not start then return nil end
    return math.max(0, current - start), base.ts
  end
  local before = months[Stats.PreviousMonth(this)]
  local after = months[this]
  local from, to = before and StatValue(before.v, id), after and StatValue(after.v, id)
  if not from or not to then return nil end
  return math.max(0, to - from), before.ts
end

-- Ranking of a statistic over records { {key, name, rec} }: { {key, name, value, rec} } sorted desc
function Stats.Ranking(entries, id, period, now, date)
  local list = {}
  for _, entry in ipairs(entries) do
    local value = Stats.Value(entry.rec, id, period, now, date)
    if value then list[#list + 1] = { key = entry.key, name = entry.name, value = value, rec = entry.rec } end
  end
  table.sort(list, function(a, b)
    if a.value ~= b.value then return a.value > b.value end
    return a.name < b.name
  end)
  return list
end

-- Sum over a ranking
function Stats.Total(ranking)
  local sum = 0
  for _, row in ipairs(ranking) do sum = sum + row.value end
  return sum
end
