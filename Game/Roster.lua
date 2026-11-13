-- Guild roster snapshot from the game: members with level, class, zone, notes, online state and days
-- since last online, the player's guild permissions, and join dates from the guild event log.
-- Fires ns "ROSTER" after each (debounced) update.
local _, ns = ...

local Roster = {}
ns.Roster = Roster
-- goes up when the members themselves change (who is in the guild, names, levels, classes), not with
-- every scan: what is worked out from the member list (rankings, the ready mark) is kept until then
Roster.version = 0

local members, byKey, byGuid = {}, {}, {}
local joined = {} -- nameKey -> days ago (from the event log)
local pending = false
local lastRequest = 0
local emptyRetries = 0 -- requests again after an empty roster while in a guild
local EMPTY_RETRIES = 5

-- rosterOnly leaves the guild event log alone (the regular request of Game/Ding.lua: the log's answer
-- would mean a second scan each time)
function Roster.Request(force, rosterOnly)
  local now = GetTime()
  if not force and now - lastRequest < 10 then return end
  lastRequest = now
  local request = (C_GuildInfo and C_GuildInfo.GuildRoster) or rawget(_G, "GuildRoster")
  if request then pcall(request) end
  if rosterOnly then return end
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

-- Since when each member is in the guild (Core/Tenure.lua): a join the event log names is remembered
-- as that day, a member Guildy knows no date of gets today ("since at least"). Members carry
-- joinedDay and joinedExact. Without guild (names made up for pictures) only the log's joins show.
local function NoteJoins(guild)
  local Tenure = ns.Tenure
  local now = ns.Now()
  local today = Tenure.Day(now)
  local book = guild and Tenure.Book(guild)
  for _, m in ipairs(members) do
    local ago = joined[m.key]
    local logDay = ago and Tenure.Day(now - ago * 86400)
    if book then
      if logDay then
        Tenure.Note(book, m.key, logDay, true, today)
      elseif not book[m.key] then
        Tenure.Note(book, m.key, today, false, today)
      end
      local entry = book[m.key]
      m.joinedDay, m.joinedExact = entry and entry.d, entry and entry.x or nil
    else
      m.joinedDay, m.joinedExact = logDay or nil, logDay and true or nil
    end
  end
end

-- Join dates came in from another Guildy user (Game/Sync.lua): the members show them
function Roster.JoinsChanged()
  NoteJoins(not ns.Anon.on and ns.GuildData() or nil)
  ns.Fire("ROSTER")
end

-- "Member since" of member m as text, nil when nothing is known. Short: the span ("3 mo", "3 mo+" for
-- a member who is in the guild at least that long). Long: the date and the span.
function Roster.TenureText(m, long)
  if type(m.joinedDay) ~= "number" then return nil end
  local L = ns.L
  local unit, count = ns.Tenure.Span(ns.Tenure.Day(ns.Now()) - m.joinedDay)
  local span = (unit == "d" and count == 0) and L.SPAN_TODAY or L["SPAN_" .. unit:upper()]:format(count)
  if not long then return m.joinedExact and span or L.SPAN_MORE:format(span) end
  -- today needs no date beside it ("since at least 13.11.2026 · today" says it twice)
  if unit == "d" and count == 0 then
    return m.joinedExact and span or L.SINCE_AT_LEAST_TODAY
  end
  -- (noon of that day: the same date in every time zone the guild plays in)
  local date = ns.GameStats.Date(L.DATE_LONG, m.joinedDay * 86400 + 43200)
  return (m.joinedExact and date or L.SINCE_AT_LEAST:format(date)) .. L.SEP .. span
end

-- The professions a member's two notes mention. Notes rarely change, and parsing them was two thirds
-- of a roster scan (measured in game 2026-11-10: 6.7 of 10.3 ms with 98 members), so the result is
-- kept per pair of note texts from one scan to the next. The set is shared: read it, never change it.
local noteSets = {}
local function Mentioned(note, officerNote, kept)
  local key = (note or "") .. "\1" .. (officerNote or "")
  local set = noteSets[key]
  if not set then
    set = ns.Professions.ParseNote(note)
    for skillLine in pairs(ns.Professions.ParseNote(officerNote)) do set[skillLine] = true end
  end
  kept[key] = set
  return set
end

function Roster.Scan()
  pending = false
  local count = ns.Try(rawget(_G, "GetNumGuildMembers")) or 0
  -- a guild never has 0 members while the player is in it: the game delivered an empty roster for a
  -- moment (seen in game 2026-11-09 after leaving and rejoining a community, which switches the club in
  -- Blizzard's window). Keep the last roster and ask again instead of emptying every tab.
  if count == 0 and IsInGuild() then
    if emptyRetries < EMPTY_RETRIES then
      emptyRetries = emptyRetries + 1
      C_Timer.After(2, function() Roster.Request(true) end)
    end
    return
  end
  emptyRetries = 0
  local lap = ns.Perf.Lap() -- which part of the scan costs (/guildy perf)
  local list, keys, guids = {}, {}, {}
  for i = 1, count do
    local name, rank, rankIndex, level, className, zone, note, officerNote, online, status, classFile,
      _, _, isMobile, _, _, guid = GetGuildRosterInfo(i)
    if name then
      local y, mo, d, h = GetGuildRosterLastOnline(i)
      local key = ns.Names.Key(name)
      -- for pictures: a made-up name and notes (Core/Anon.lua); key and fullName stay the real ones,
      -- so stored data, whispers and invites still find the member
      local shown = ns.Anon.Name(ns.Names.Normalize(name))
      note, officerNote = ns.Anon.Note(note, name), ns.Anon.Note(officerNote, name .. "+")
      local m = {
        index = i, fullName = name, name = shown, key = key, rank = ns.Anon.Rank(rank, rankIndex),
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
  local changed = #list ~= #members
  for _, m in ipairs(changed and {} or list) do
    local old = byKey[m.key]
    if not old or old.name ~= m.name or old.level ~= m.level or old.classFile ~= m.classFile then
      changed = true
      break
    end
  end
  if changed then Roster.version = Roster.version + 1 end
  members, byKey, byGuid = list, keys, guids
  lap("scan roster:", "read members")
  ReadEventLog()
  for _, m in ipairs(members) do m.joinedDaysAgo = joined[m.key] end
  -- forget stored profession data of members who left (only with a complete roster)
  local guild = not ns.Anon.on and ns.GuildData() or nil -- made-up notes must not reach the saved data
  if guild and #members > 0 then
    local keep = {}
    for key in pairs(byKey) do keep[key] = true end
    ns.Store.Prune(guild, keep)
    ns.Tenure.Prune(ns.Tenure.Book(guild), keep)
    if type(guild.cooldowns) == "table" then
      ns.Cooldowns.Prune(guild.cooldowns, keep)
      ns.Cooldowns.DropStale(guild.cooldowns, ns.Now())
    end
    if type(guild.gear) == "table" then ns.Gear.Prune(guild.gear, keep) end
    if type(guild.talents) == "table" then ns.Talents.Prune(guild.talents, keep) end
  end
  NoteJoins(guild)
  lap("scan roster:", "event log and prune")
  -- professions mentioned in public and officer notes ("Herb/ Alch")
  local notesChanged = false
  if guild then
    local kept = {} -- only the notes still in the roster stay remembered
    for _, m in ipairs(members) do
      local mentioned = Mentioned(m.note, m.officerNote, kept)
      local record = guild.members[m.key]
      if next(mentioned) or record then
        record = record or ns.Store.Member(guild, m.name)
        -- also cleans up records saved before the two-primary rule existed
        if ns.Professions.CapPrimary(record) then notesChanged = true end
        if ns.Professions.ApplyNotes(record, mentioned) then notesChanged = true end
      end
    end
    noteSets = kept
  end
  lap("scan roster:", "notes")
  ns.Fire("ROSTER")
  if notesChanged then ns.Fire("PROFS") end
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

-- The player's own roster entry
function Roster.Me()
  return Roster.Find(ns.Names.FromUnit(UnitName("player")))
end

-- The player's rank index (0 = guild master): GetGuildInfo("player"), else the roster entry
local function MyRankIndex()
  local _, _, rankIndex = ns.Try(GetGuildInfo, "player")
  if type(rankIndex) == "number" then return rankIndex end
  local me = Roster.Me()
  return me and me.rankIndex
end

-- The player's own rank index (0 = guild master), nil outside a guild
function Roster.MyRank() return MyRankIndex() end

-- Number of guild ranks: GuildControlGetNumRanks, at least the lowest rank seen in the roster
local function NumRanks()
  local num = ns.Try(rawget(_G, "GuildControlGetNumRanks"))
  num = type(num) == "number" and num or 0
  for _, m in ipairs(members) do
    if type(m.rankIndex) == "number" and m.rankIndex + 1 > num then num = m.rankIndex + 1 end
  end
  return num > 0 and num or nil
end

-- What the player may do with member m: { promote, demote, remove } (Core/Manage.lua)
function Roster.Rights(m)
  local myGuid = ns.Try(rawget(_G, "UnitGUID"), "player")
  local isSelf = m ~= nil and ((myGuid and m.guid == myGuid) or m == Roster.Me())
  return ns.Manage.Rights(m and m.rankIndex, MyRankIndex(), NumRanks(), Roster.Can(), isSelf)
end

-- Name of the rank one step from member m's: kind "promote" (one up) or "demote" (one down); nil when
-- the player may not take that step (Roster.Rights). Forever has no "set rank": one command, one step.
function Roster.NextRank(m, kind)
  if not (m and type(m.rankIndex) == "number" and Roster.Rights(m)[kind]) then return nil end
  local index = kind == "promote" and m.rankIndex - 1 or m.rankIndex + 1
  return Roster.Ranks()[index + 1]
end

-- Debug: why rank actions are off for a member (/guildy rights Name)
function Roster.DebugRights(name)
  local m = name and Roster.Find(name)
  local num = ns.Try(rawget(_G, "GuildControlGetNumRanks"))
  local _, _, myRank = ns.Try(GetGuildInfo, "player")
  ns.Print(("member=%s rank=%s · myRank(GetGuildInfo)=%s · myRank(roster)=%s · numRanks=%s/%s"):format(
    tostring(m and m.name), tostring(m and m.rankIndex), tostring(myRank),
    tostring(Roster.Me() and Roster.Me().rankIndex), tostring(num), tostring(NumRanks())))
  local can = Roster.Can()
  local r = Roster.Rights(m)
  ns.Print(("can promote=%s demote=%s remove=%s · rights promote=%s demote=%s remove=%s"):format(
    tostring(can.promote), tostring(can.demote), tostring(can.remove),
    tostring(r.promote), tostring(r.demote), tostring(r.remove)))
end

-- Guild actions (invite, rank, removal, MOTD, info) are blocked for addon code on Forever; they run
-- through secure buttons (UI/Commands.lua). Notes are edited in Blizzard's window. Group invites are
-- allowed.

function Roster.GroupInvite(m)
  local fn = (C_PartyInfo and C_PartyInfo.InviteUnit) or rawget(_G, "InviteUnit")
  if fn then pcall(fn, m.fullName) end
end

-- Rank names in order (index 1 = guild master)
function Roster.Ranks()
  local ranks = {}
  local num = ns.Try(rawget(_G, "GuildControlGetNumRanks")) or 0
  for i = 1, num do
    ranks[i] = ns.Anon.Rank(ns.Try(rawget(_G, "GuildControlGetRankName"), i) or tostring(i), i - 1)
  end
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
