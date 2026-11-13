-- Searching and filtering: recipes across members, and the member list (filters, text search, sort).
-- Pure functions; text matching is plain (no Lua patterns) and case-insensitive.
local _, ns = ...

local Search = {}
ns.Search = Search

Search.MAX_RESULTS = 200

-- Query text: trimmed, lowercased, item/spell links reduced to their name ("|h[Name]|h" -> "Name")
function Search.Normalize(query)
  if type(query) ~= "string" then return "" end
  query = query:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
  local linked = query:match("|h%[(.-)%]|h")
  if linked then query = linked end
  return ns.Names.Lower(ns.Names.Trim(query))
end

-- Turns a client format string ("%s has joined the guild.") into an anchored Lua pattern
function Search.FormatToPattern(fmt)
  local pattern = fmt:gsub("%%%d?%$?s", "\1"):gsub("%%%d?%$?d", "\2")
  pattern = pattern:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0")
  pattern = pattern:gsub("\1", "(.+)"):gsub("\2", "(%%d+)")
  return "^" .. pattern .. "$"
end

local function Contains(text, q)
  return type(text) == "string" and ns.Names.Lower(text):find(q, 1, true) ~= nil
end

-- entries: { {memberName, skillLine, spellID, recipeName, online} } -> matching entries, best first
function Search.Recipes(entries, query)
  local q = Search.Normalize(query)
  local results = {}
  if q == "" then return results end
  for _, e in ipairs(entries) do
    local name = ns.Names.Lower(e.recipeName or "")
    local at = name:find(q, 1, true)
    if at then results[#results + 1] = { entry = e, prefix = at == 1, name = name } end
  end
  table.sort(results, function(a, b)
    if a.prefix ~= b.prefix then return a.prefix end
    if a.name ~= b.name then return a.name < b.name end
    if (a.entry.online and true or false) ~= (b.entry.online and true or false) then return a.entry.online == true end
    return ns.Names.Lower(a.entry.memberName or "") < ns.Names.Lower(b.entry.memberName or "")
  end)
  local out = {}
  for i = 1, math.min(#results, Search.MAX_RESULTS) do out[i] = results[i].entry end
  return out
end

-- Search.Recipes results -> one group per recipe, in the order of their first entry:
-- { spellID, recipeName, skillLine, entries = {...} (as given: online first), online = count }
function Search.GroupRecipes(results)
  local groups, bySpell = {}, {}
  for _, e in ipairs(results) do
    local group = bySpell[e.spellID]
    if not group then
      group = { spellID = e.spellID, recipeName = e.recipeName, skillLine = e.skillLine, entries = {}, online = 0 }
      bySpell[e.spellID] = group
      groups[#groups + 1] = group
    end
    group.entries[#group.entries + 1] = e
    if e.online then group.online = group.online + 1 end
  end
  return groups
end

-- members: Roster.Members() entries. filter = {classFile, rankIndex, bracket, skillLine, onlineOnly, hideOffline,
-- activeDays}; profsOf(member) -> set or nil
function Search.Members(members, filter, query, profsOf)
  filter = filter or {}
  local q = Search.Normalize(query)
  local out = {}
  for _, m in ipairs(members) do
    local keep = true
    if (filter.onlineOnly or filter.hideOffline) and not m.online then keep = false end
    if keep and filter.classFile and m.classFile ~= filter.classFile then keep = false end
    if keep and filter.rankIndex and m.rankIndex ~= filter.rankIndex then keep = false end
    if keep and filter.bracket and ns.Census.Bracket(m.level) ~= filter.bracket then keep = false end
    if keep and filter.level and tonumber(m.level) ~= filter.level then keep = false end
    if keep and filter.activeDays and not ns.Census.IsActive(m, filter.activeDays) then keep = false end
    if keep and filter.activity and ns.Census.ActivityBucket(m) ~= filter.activity then keep = false end
    -- from the endgame view of the overview; the members tab sets m.scoreBucket, m.ilvl and m.raidKill
    if keep and filter.scoreBucket and m.scoreBucket ~= filter.scoreBucket then keep = false end
    if keep and filter.ilvl and not (m.ilvl and math.floor(m.ilvl / 10) == filter.ilvl) then keep = false end
    if keep and filter.raidKill and not m.raidKill then keep = false end
    if keep and filter.skillLine then
      local profs = profsOf and profsOf(m)
      if not (profs and profs[filter.skillLine]) then keep = false end
    end
    if keep and q ~= "" then
      keep = Contains(m.name, q) or Contains(m.zone, q) or Contains(m.note, q) or Contains(m.rank, q)
        or Contains(m.officerNote, q)
    end
    if keep then out[#out + 1] = m end
  end
  return out
end

local function LastOnlineValue(m)
  if m.online then return -1 end
  return type(m.daysOffline) == "number" and m.daysOffline or math.huge
end

local GETTERS = {
  level = function(m) return tonumber(m.level) or 0 end,
  name = function(m) return ns.Names.Lower(m.name or "") end,
  zone = function(m) return ns.Names.Lower(m.zone or "") end,
  rank = function(m) return tonumber(m.rankIndex) or 99 end,
  class = function(m) return m.classFile or "" end,
  lastOnline = LastOnlineValue,
  -- Guildy users first (set by the members tab: version, "" for an old Guildy), then by version text
  guildy = function(m) return m.guildy and ("1" .. m.guildy) or "0" end,
  -- set by the members tab: the average item level
  ilvl = function(m) return m.ilvl or 0 end,
  -- set by the members tab: the activity score of the member's player, none below every score
  score = function(m) return m.score or -1 end,
  -- the day the member joined (Core/Tenure.lua), members without one after everyone
  joined = function(m) return m.joinedDay or math.huge end,
}

-- Sorts in place by field; desc reverses. Ties by name. Default directions: level high first.
function Search.SortMembers(list, field, desc)
  local get = GETTERS[field] or GETTERS.name
  -- the sort values once per member, not once per comparison: lowering a name is slow
  local value, name = {}, {}
  for _, m in ipairs(list) do
    value[m] = get(m)
    name[m] = ns.Names.Lower(m.name or "")
  end
  table.sort(list, function(a, b)
    local x, y = value[a], value[b]
    if x ~= y then
      if desc then return x > y end
      return x < y
    end
    return name[a] < name[b]
  end)
  return list
end
