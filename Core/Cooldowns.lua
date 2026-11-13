-- Profession cooldowns, pure: transmutes, Mooncloth, the Salt Shaker. Nobody can read another
-- player's cooldowns; a Guildy user reads their own (Game/Cooldowns.lua) and shares them, and the
-- others relay them like the rest (Game/Sync.lua).
--   guild.cooldowns[nameKey] = { ts = when read, cd = { [spellID] = readyAt } }
--   readyAt = absolute server time, 0 = ready
--   GuildyDB.cooldownSpells[spellID] = skillLine: crafts seen with a cooldown in the player's own window
-- Forever shortens the classic durations, so no duration is written down anywhere: only what the
-- game reports counts.
local _, ns = ...

local Cooldowns = {}
ns.Cooldowns = Cooldowns

Cooldowns.MAX_AGE = 7 * 86400 -- a reading this old says nothing any more
Cooldowns.TOLERANCE = 60      -- seconds two readings of the same cooldown may differ by
Cooldowns.MAX_SPELLS = 40     -- cooldowns a reading carries
Cooldowns.MAX_LEARNED = 200

-- The cooldown crafts known from the start (checked against Forever's database 2026-11-13)
Cooldowns.SEED = {
  [17187] = 171, [11479] = 171, [11480] = 171,   -- Transmute: Arcanite, Iron to Gold, Mithril to Truesilver
  [17559] = 171, [17560] = 171, [17561] = 171, [17562] = 171, -- the elemental transmutes
  [17563] = 171, [17564] = 171, [17565] = 171, [17566] = 171,
  [1317279] = 171,                                -- Transmute: Legionite (Forever's own)
  [18560] = 197,                                  -- Mooncloth
  [19566] = 165,                                  -- Salt Shaker (the item's spell)
}
-- Items whose use is a cooldown craft: item -> its spell
Cooldowns.ITEMS = { [15846] = 19566 } -- Salt Shaker

local function IsId(n)
  return type(n) == "number" and n == n and n > 0 and n == math.floor(n)
end

-- spellID -> skillLine of every craft to read: the known ones and those learned since
function Cooldowns.Watched(learned)
  local watched = {}
  for spell, skillLine in pairs(Cooldowns.SEED) do watched[spell] = skillLine end
  if type(learned) == "table" then
    for spell, skillLine in pairs(learned) do
      if IsId(spell) and IsId(skillLine) then watched[spell] = skillLine end
    end
  end
  return watched
end

-- Remembers a craft seen with a cooldown. Returns true when it was new.
function Cooldowns.Learn(learned, spell, skillLine)
  if not (IsId(spell) and IsId(skillLine)) or Cooldowns.SEED[spell] or learned[spell] then return false end
  local count = 0
  for _ in pairs(learned) do count = count + 1 end
  if count >= Cooldowns.MAX_LEARNED then return false end
  learned[spell] = skillLine
  return true
end

local function Same(a, b)
  for spell, at in pairs(a) do
    local other = b[spell]
    if other == nil or math.abs(other - at) > Cooldowns.TOLERANCE then return false end
  end
  for spell in pairs(b) do
    if a[spell] == nil then return false end
  end
  return true
end

-- A reading of the player's own character: cd = { [spellID] = readyAt }. Returns true when it says
-- something the stored one did not (jitter of a few seconds does not count).
function Cooldowns.Note(book, key, cd, ts)
  local clean = {}
  for spell, at in pairs(cd) do
    if IsId(spell) and type(at) == "number" then clean[spell] = at > ts and math.floor(at) or 0 end
  end
  local have = book[key]
  if type(have) == "table" and type(have.cd) == "table" and Same(have.cd, clean) then return false end
  book[key] = { ts = ts, cd = clean }
  return true
end

-- A reading as it goes over the wire: cd as a list of { spellID, readyAt }
function Cooldowns.Wire(rec)
  local list = {}
  for spell, at in pairs(rec.cd) do list[#list + 1] = { spell, at } end
  table.sort(list, function(x, y) return x[1] < y[1] end)
  return { ts = rec.ts, cd = list }
end

-- A clean reading from the wire, or nil when it can't be used
function Cooldowns.Validate(raw, now)
  if type(raw) ~= "table" or not IsId(raw.ts) then return nil end
  if raw.ts > now + 300 or now - raw.ts > Cooldowns.MAX_AGE or type(raw.cd) ~= "table" then return nil end
  local cd = {}
  for i = 1, math.min(#raw.cd, Cooldowns.MAX_SPELLS) do
    local item = raw.cd[i]
    if type(item) == "table" and IsId(item[1]) then
      local at = item[2]
      if type(at) == "number" and at == math.floor(at) and at >= 0 and at <= now + Cooldowns.MAX_AGE then
        cd[item[1]] = at
      end
    end
  end
  return { ts = raw.ts, cd = cd }
end

-- Takes a received reading when it is newer. Returns true when it was taken.
function Cooldowns.Merge(book, key, rec)
  local have = book[key]
  if type(have) == "table" and type(have.ts) == "number" and have.ts >= rec.ts then return false end
  book[key] = rec
  return true
end

-- { [nameKey] = ts } of every reading known
function Cooldowns.Digest(book)
  local digest = {}
  for key, rec in pairs(type(book) == "table" and book or {}) do
    if type(rec) == "table" and type(rec.ts) == "number" then digest[key] = rec.ts end
  end
  return digest
end

-- A member's cooldowns { { spell, readyAt, left = seconds } }, ready first, then the nearest; nil when
-- nothing is known of them or what is known is too old
function Cooldowns.Of(book, key, now)
  local rec = type(book) == "table" and book[key]
  if type(rec) ~= "table" or type(rec.cd) ~= "table" or now - rec.ts > Cooldowns.MAX_AGE then return nil end
  local list = {}
  for spell, at in pairs(rec.cd) do
    list[#list + 1] = { spell = spell, readyAt = at, left = math.max(0, at - now) }
  end
  table.sort(list, function(x, y)
    if x.left ~= y.left then return x.left < y.left end
    return x.spell < y.spell
  end)
  return list
end

-- Forgets members no longer in the guild. keep = { [nameKey] = true }. Returns how many were removed.
function Cooldowns.Prune(book, keep)
  local removed = 0
  for key in pairs(book) do
    if not keep[key] then
      book[key] = nil
      removed = removed + 1
    end
  end
  return removed
end

-- Seconds left as a span: "m" under an hour, "h" under two days, then "d"
function Cooldowns.Span(seconds)
  if seconds < 3600 then return "m", math.max(1, math.ceil(seconds / 60)) end
  if seconds < 48 * 3600 then return "h", math.ceil(seconds / 3600) end
  return "d", math.floor(seconds / 86400 + 0.5)
end
