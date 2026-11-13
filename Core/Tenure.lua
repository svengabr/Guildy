-- Since when a member is in the guild, pure. The roster has no join date; the guild event log names
-- the joins of its last hundred or so events with an age (Game/Roster.lua reads it). So a join seen in
-- the log is remembered, and a member whose join has left the log gets the day Guildy first saw them:
-- "since at least". Guildy users share what they know (Game/Sync.lua), so one who is long in the guild
-- fills in the others.
--   guild.joined = { [nameKey] = { d = day, x = true | nil } }
--   d = day number (time / 86400, floored), x = from the event log (else: first seen)
local _, ns = ...

local Tenure = {}
ns.Tenure = Tenure

-- Two log dates further apart than this are two joins (the member left and came back): the later one
-- counts. Closer ones are the same join read at different times, and the earlier one is kept, so two
-- clients end on the same day.
Tenure.REJOIN_DAYS = 2
Tenure.WIRE_MEMBERS = 150 -- members a message carries
local WIRE_MAX = 2000     -- entries of a message that are looked at
local NAME_MAX = 64

local floor = math.floor

function Tenure.Day(ts)
  return floor(ts / 86400)
end

local function IsDay(day, today)
  return type(day) == "number" and day == day and day == floor(day) and day > 0 and day <= today + 1
end

-- The join dates of a guild (created on first use)
function Tenure.Book(guild)
  if type(guild.joined) ~= "table" then guild.joined = {} end
  return guild.joined
end

-- Notes a date for a member: exact = from the event log. Returns whether the entry changed.
function Tenure.Note(joined, key, day, exact, today)
  if type(key) ~= "string" or not IsDay(day, today) then return false end
  exact = exact and true or nil
  local have = joined[key]
  if type(have) ~= "table" or not IsDay(have.d, today) then
    joined[key] = { d = day, x = exact }
    return true
  end
  local take
  if exact and not have.x then
    take = true
  elseif have.x and not exact then
    take = false
  elseif exact and day - have.d > Tenure.REJOIN_DAYS then
    take = true
  elseif exact and have.d - day > Tenure.REJOIN_DAYS then
    take = false
  else
    take = day < have.d
  end
  if take then joined[key] = { d = day, x = exact } end
  return take
end

-- Forgets members no longer in the guild. keep = { [nameKey] = true }. Returns how many were removed.
function Tenure.Prune(joined, keep)
  local removed = 0
  for key in pairs(joined) do
    if not keep[key] then
      joined[key] = nil
      removed = removed + 1
    end
  end
  return removed
end

-- What a client knows, in three numbers: entries, exact ones, the sum of their days
function Tenure.Digest(joined)
  local digest = { n = 0, x = 0, s = 0 }
  if type(joined) ~= "table" then return digest end
  for _, entry in pairs(joined) do
    if type(entry) == "table" and type(entry.d) == "number" then
      digest.n = digest.n + 1
      digest.s = digest.s + entry.d
      if entry.x then digest.x = digest.x + 1 end
    end
  end
  return digest
end

function Tenure.Differs(mine, theirs)
  if type(theirs) ~= "table" then return true end
  return mine.n ~= theirs.n or mine.x ~= theirs.x or mine.s ~= theirs.s
end

-- The dates as messages: lists of { name, day, 1 (from the log) | 0 }, WIRE_MEMBERS each.
-- names = { [nameKey] = name } (a member it does not name goes by key)
function Tenure.Wire(joined, names)
  local keys = {}
  for key, entry in pairs(joined) do
    if type(entry) == "table" and type(entry.d) == "number" then keys[#keys + 1] = key end
  end
  table.sort(keys)
  local messages = {}
  for i, key in ipairs(keys) do
    local at = floor((i - 1) / Tenure.WIRE_MEMBERS) + 1
    messages[at] = messages[at] or {}
    local entry = joined[key]
    messages[at][#messages[at] + 1] = { names[key] or key, entry.d, entry.x and 1 or 0 }
  end
  return messages
end

-- Takes in a received list. isMember(name) says whether that name is in the guild. Returns whether
-- anything changed.
function Tenure.Apply(joined, list, today, isMember)
  if type(list) ~= "table" then return false end
  local changed = false
  for i = 1, math.min(#list, WIRE_MAX) do
    local item = list[i]
    if type(item) == "table" and type(item[1]) == "string" and #item[1] <= NAME_MAX and isMember(item[1]) then
      if Tenure.Note(joined, ns.Names.Key(item[1]), item[2], item[3] == 1, today) then changed = true end
    end
  end
  return changed
end

-- A number of days as a span: "d" up to 30 days, "mo" (30 days each) up to two years, then "y"
function Tenure.Span(days)
  days = math.max(0, floor(days))
  if days < 31 then return "d", days end
  if days < 730 then return "mo", floor(days / 30) end
  return "y", floor(days / 365)
end
