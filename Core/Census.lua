-- Census of the guild: who counts as active in a time window, and the class / level / profession
-- make-up of those members. Pure functions over roster snapshots (Game/Roster.lua Members()).
local _, ns = ...

local Census = {}
ns.Census = Census

Census.WINDOWS = { 30, 90, 180, false } -- days; false = everyone
Census.BRACKETS = 6                     -- 1-9, 10-19, 20-29, 30-39, 40-49, 50-60
Census.NEW_DAYS = 30

-- Days since last online from GetGuildRosterLastOnline (years, months, days, hours); nil when unknown
function Census.DaysOffline(years, months, days, hours)
  if years == nil and months == nil and days == nil and hours == nil then return nil end
  return (years or 0) * 365 + (months or 0) * 30 + (days or 0) + (hours or 0) / 24
end

-- m = {online, daysOffline}; windowDays false/nil = everyone counts
function Census.IsActive(m, windowDays)
  if not windowDays then return true end
  if m.online then return true end
  if type(m.daysOffline) ~= "number" then return false end
  return m.daysOffline <= windowDays
end

function Census.Bracket(level)
  level = tonumber(level) or 1
  return math.max(1, math.min(Census.BRACKETS, math.floor(level / 10) + 1))
end

-- Bracket label "1-9", "10-19", ..., "50-60"
function Census.BracketLabel(bracket)
  if bracket == 1 then return "1-9" end
  if bracket == Census.BRACKETS then return ((bracket - 1) * 10) .. "-60" end
  return ((bracket - 1) * 10) .. "-" .. (bracket * 10 - 1)
end

-- members: list of {level, classFile, online, daysOffline, joinedDaysAgo}
-- profsOf(member) -> { [skillLineID] = true } or nil
function Census.Compute(members, windowDays, profsOf)
  local result = {
    total = #members, active = 0, online = 0, avgLevel = 0, classes = {}, brackets = {},
    professions = {}, withProfessions = 0, newCount = 0,
  }
  for i = 1, Census.BRACKETS do result.brackets[i] = 0 end
  local levelSum = 0
  for _, m in ipairs(members) do
    if m.online then result.online = result.online + 1 end
    if Census.IsActive(m, windowDays) then
      result.active = result.active + 1
      levelSum = levelSum + (tonumber(m.level) or 0)
      if m.classFile then result.classes[m.classFile] = (result.classes[m.classFile] or 0) + 1 end
      local bracket = Census.Bracket(m.level)
      result.brackets[bracket] = result.brackets[bracket] + 1
      local profs = profsOf and profsOf(m)
      if profs and next(profs) then
        result.withProfessions = result.withProfessions + 1
        for skillLine in pairs(profs) do
          result.professions[skillLine] = (result.professions[skillLine] or 0) + 1
        end
      end
      if type(m.joinedDaysAgo) == "number" and m.joinedDaysAgo <= Census.NEW_DAYS then
        result.newCount = result.newCount + 1
      end
    end
  end
  if result.active > 0 then result.avgLevel = levelSum / result.active end
  return result
end

-- {key, count} sorted by count desc then key; for bar charts
function Census.Sorted(counts)
  local list = {}
  for key, count in pairs(counts) do list[#list + 1] = { key = key, count = count } end
  table.sort(list, function(a, b)
    if a.count ~= b.count then return a.count > b.count end
    return tostring(a.key) < tostring(b.key)
  end)
  return list
end
