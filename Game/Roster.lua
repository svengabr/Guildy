-- Guild roster snapshot from the game: members with level, class, zone, notes, online state and days
-- since last online, the player's guild permissions, and join dates from the guild event log.
-- Fires ns "ROSTER" after each (debounced) update.
local _, ns = ...

local Roster = {}
ns.Roster = Roster

local members, byKey, byGuid = {}, {}, {}
local joined = {} -- nameKey -> days ago (from the event log)
local pending = false
local lastRequest = 0

function Roster.Request(force)
  local now = GetTime()
  if not force and now - lastRequest < 10 then return end
  lastRequest = now
  local request = (C_GuildInfo and C_GuildInfo.GuildRoster) or rawget(_G, "GuildRoster")
  if request then pcall(request) end
  local queryLog = rawget(_G, "QueryGuildEventLog")
  if queryLog then pcall(queryLog) end
end

local function ReadEventLog()
  local count = ns.Try(rawget(_G, "GetNumGuildEvents")) or 0
  local getInfo = rawget(_G, "GetGuildEventInfo")
  if not getInfo then return end
  for i = 1, count do
    local ok, kind, player1, _, _, years, months, days, hours = pcall(getInfo, i)
    if ok and kind == "join" and player1 then
      local ago = ns.Census.DaysOffline(years, months, days, hours) or 0
      local key = ns.Names.Key(player1)
      if not joined[key] or ago < joined[key] then joined[key] = ago end
    end
  end
end

function Roster.Scan()
  pending = false
  local count = ns.Try(rawget(_G, "GetNumGuildMembers")) or 0
  local list, keys, guids = {}, {}, {}
  for i = 1, count do
    local name, rank, rankIndex, level, className, zone, note, officerNote, online, status, classFile,
      _, _, isMobile, _, _, guid = GetGuildRosterInfo(i)
    if name then
      local y, mo, d, h = GetGuildRosterLastOnline(i)
      local key = ns.Names.Key(name)
      local m = {
        index = i, fullName = name, name = ns.Names.Normalize(name), key = key, rank = rank,
        rankIndex = rankIndex, level = level or 1, className = className, classFile = classFile, zone = zone,
        note = note, officerNote = officerNote, online = (online and not isMobile) and true or false,
        isMobile = isMobile and true or false, status = status, guid = guid,
        daysOffline = ns.Census.DaysOffline(y, mo, d, h),
      }
      list[#list + 1] = m
      keys[key] = m
      if guid then guids[guid] = m end
    end
  end
  members, byKey, byGuid = list, keys, guids
  ReadEventLog()
  for _, m in ipairs(members) do m.joinedDaysAgo = joined[m.key] end
  -- forget stored profession data of members who left (only with a complete roster)
  local guild = ns.GuildData()
  if guild and #members > 0 then
    local keep = {}
    for key in pairs(byKey) do keep[key] = true end
    ns.Store.Prune(guild, keep)
  end
  ns.Fire("ROSTER")
end

function Roster.ScheduleScan()
  if pending then return end
  pending = true
  C_Timer.After(0.5, function() ns.SafeCall(Roster.Scan) end)
end

function Roster.Members() return members end
function Roster.Find(name) return byKey[ns.Names.Key(name)] end
function Roster.FindByGuid(guid) return guid and byGuid[guid] end
function Roster.IsMember(name) return byKey[ns.Names.Key(name)] ~= nil end

function Roster.Online()
  local list = {}
  for _, m in ipairs(members) do
    if m.online then list[#list + 1] = m end
  end
  return list
end

function Roster.Counts()
  local online = 0
  for _, m in ipairs(members) do
    if m.online then online = online + 1 end
  end
  return online, #members
end

local function Allowed(fn, ...)
  return ns.Try(fn, ...) and true or false
end

-- What the player may do in the guild
function Roster.Can()
  local gi = C_GuildInfo or {}
  local can = {
    invite = Allowed(rawget(_G, "CanGuildInvite")),
    remove = Allowed(rawget(_G, "CanGuildRemove")),
    promote = Allowed(rawget(_G, "CanGuildPromote")),
    demote = Allowed(rawget(_G, "CanGuildDemote")),
    editPublic = Allowed(rawget(_G, "CanEditPublicNote")),
    viewOfficer = Allowed(gi.CanViewOfficerNote) or Allowed(rawget(_G, "CanViewOfficerNote")),
    editOfficer = Allowed(gi.CanEditOfficerNote) or Allowed(rawget(_G, "CanEditOfficerNote")),
    editMotd = Allowed(rawget(_G, "CanEditMOTD")),
    editInfo = Allowed(rawget(_G, "CanEditGuildInfo")),
    leader = Allowed(rawget(_G, "IsGuildLeader")),
  }
  can.officerChat = Allowed(gi.IsGuildOfficer) or can.viewOfficer
  return can
end

-- Guild actions: invite, remove, promote, demote and MOTD are blocked for addons on Forever and run as
-- slash commands through the secure dialog (UI/Secure.lua); notes and guild info are edited in
-- Blizzard's window. Group invites are allowed.

function Roster.GroupInvite(m)
  local fn = (C_PartyInfo and C_PartyInfo.InviteUnit) or rawget(_G, "InviteUnit")
  if fn then pcall(fn, m.fullName) end
end

-- Rank names in order (index 1 = guild master)
function Roster.Ranks()
  local ranks = {}
  local num = ns.Try(rawget(_G, "GuildControlGetNumRanks")) or 0
  for i = 1, num do ranks[i] = ns.Try(rawget(_G, "GuildControlGetRankName"), i) or tostring(i) end
  return ranks
end

-- Readable "last online": "online", "3 h", "5 d", "2 mo"
function Roster.LastOnlineText(m)
  local L = ns.L
  if m.online then return L.ONLINE end
  if m.isMobile then return L.MOBILE end
  local days = m.daysOffline
  if type(days) ~= "number" then return "?" end
  if days < 1 then return L.HOURS_AGO:format(math.max(1, math.floor(days * 24))) end
  if days < 31 then return L.DAYS_AGO:format(math.floor(days)) end
  if days < 365 then return L.MONTHS_AGO:format(math.floor(days / 30)) end
  return L.YEARS_AGO:format(math.floor(days / 365))
end
