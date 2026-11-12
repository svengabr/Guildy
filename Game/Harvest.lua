-- "Read online members": opens the profession link of every online guild member for every profession
-- with recipes, one at a time, so TradeSkill.ScanOpen stores what the server sends. Links only open for
-- online members; a profession the member doesn't have opens an empty book and is remembered as absent
-- for a week. Only on the player's click, never in combat, Blizzard's window stays invisible while it
-- runs and is closed after each look. Opening the player's own profession window stops it.
local _, ns = ...
local P = ns.Professions

local Harvest = {}
ns.Harvest = Harvest

-- professions whose recipe book opens through a link: crafting first, then the secondary ones (mining's
-- smelting book doesn't open from a link on Forever, gathering professions have no book)
Harvest.ORDER = { 171, 164, 333, 202, 165, 197, 185, 129 }
Harvest.FRESH = 24 * 3600      -- data younger than this is not read again
Harvest.ABSENT = 7 * 24 * 3600 -- "doesn't have it" is remembered this long
Harvest.WAIT = 3               -- seconds until a look without any answer counts as "no answer"
Harvest.MAX_PRIMARY = 2
Harvest.PAUSE = 2              -- seconds between looks (the server slows down requests in quick succession)
Harvest.DATA_VERSION = 5       -- bump to drop "absent"/"silent"/server marks made by older, faulty runs
                               -- (4: runs with Blizzard's window muted got only empty books)
Harvest.SERVER_MISSES = 1      -- silent members of another server id before it is skipped for the run
Harvest.SILENT = 3600          -- a member without any answer is left out this long (they may change servers)
Harvest.ABSENT_GRACE = 1.5     -- seconds an empty book may still fill before it counts as "doesn't have it"
Harvest.FIRST_WAIT = 8         -- the run's first look loads Blizzard's profession window: it may take longer

local state

function Harvest.IsRunning()
  return state ~= nil
end

-- The look in progress: member name, profession name (nil when idle)
function Harvest.Current()
  local entry = state and state.current
  if not entry then return nil end
  return entry.member.name, ns.TradeSkill.Name(entry.skillLine), entry.member.classFile
end

-- done members, member count, recipe books found, looks done, looks planned, seconds left (estimate)
function Harvest.Progress()
  if not state then return nil end
  local spent, count = 0, 0
  for i = 1, math.min(#Harvest.log, 10) do
    local e = Harvest.log[i]
    if e.seconds then spent, count = spent + e.seconds, count + 1 end
  end
  local each = (count > 0 and spent / count or Harvest.WAIT) + Harvest.PAUSE
  local left = math.max(0, #state.queue - state.index) * each
  return state.doneMembers, state.totalMembers, state.found, state.index, #state.queue, left
end

local function Absent(guild)
  guild.absent = guild.absent or {}
  return guild.absent
end

local function PrimaryCount(record, now)
  local count = 0
  for skillLine, prof in pairs(record and record.profs or {}) do
    if P.PRIMARY[skillLine] and prof.recipes and now - (prof.ts or 0) < Harvest.FRESH * 7 then count = count + 1 end
  end
  return count
end

-- Server id in a player GUID ("Player-6949-0074341C" -> "6949"). Only members on the server the player
-- is on right now answer, and on Forever that changes with the zone (2026-11-08). So nothing about
-- servers is remembered: members with the player's server id go first (those in the player's zone
-- before the others), then other ids in the zone, then the rest; within a run an id whose member stayed
-- silent is skipped for the rest of that run.
function Harvest.ServerId(guid)
  return type(guid) == "string" and guid:match("^Player%-(%d+)%-") or nil
end

-- Pure: which (member, profession) pairs to look at. members = roster entries, guild = stored data,
-- myServer/myZone = the player's server id and zone (members there go first). isUser(m) = the member
-- runs Guildy (shares their own professions): not read, only counted. Returns queue, member count, users.
-- A profession Guildy knows the member has: a skill level, recipes or the guild note says so
local function Known(prof)
  return prof ~= nil and (prof.rank ~= nil or prof.recipes ~= nil or prof.src == "note")
end

-- Professions to look at for one member: when Guildy knows any of their professions, only those, plus
-- the other book professions while fewer than MAX_PRIMARY primary ones are known (a second one may be
-- missing); known ones first. Members Guildy knows nothing about get every book profession.
function Harvest.Professions(record)
  local profs = record and record.profs or {}
  local knownAny, knownPrimary = false, 0
  for skillLine, prof in pairs(profs) do
    if Known(prof) then
      knownAny = true
      if P.PRIMARY[skillLine] then knownPrimary = knownPrimary + 1 end
    end
  end
  local list = {}
  for _, skillLine in ipairs(Harvest.ORDER) do
    if Known(profs[skillLine]) then list[#list + 1] = skillLine end
  end
  for _, skillLine in ipairs(Harvest.ORDER) do
    if not Known(profs[skillLine]) then
      if not knownAny or (P.PRIMARY[skillLine] and knownPrimary < Harvest.MAX_PRIMARY) then
        list[#list + 1] = skillLine
      end
    end
  end
  return list
end

function Harvest.BuildQueue(members, guild, now, isOwn, myServer, isUser, myZone)
  local queue, memberSet = {}, {}
  local absent = guild.absent or {}
  local silent = guild.silent or {}
  local users = 0
  for _, m in ipairs(members) do
    local quiet = silent[m.key] and now - silent[m.key] < Harvest.SILENT
    local reachable = m.online and not m.isMobile and m.guid and not isOwn(m)
    if reachable and isUser and isUser(m) then
      users = users + 1
    elseif reachable and not quiet then
      -- the player's server id first (in the player's zone before elsewhere), then other ids in the zone
      local own = not myServer or Harvest.ServerId(m.guid) == myServer
      local here = myZone and m.zone == myZone
      local rank = (own and here and 1) or (own and 2) or (here and 3) or 4
      local record = guild.members[m.key]
      for _, skillLine in ipairs(Harvest.Professions(record)) do
        local prof = record and record.profs and record.profs[skillLine]
        -- read less than a day ago, and not before /guildy scanreset
        local fresh = prof and prof.recipes and now - (prof.ts or 0) < Harvest.FRESH and (prof.ts or 0) > (guild.scanResetAt or 0)
        local gone = absent[m.key] and absent[m.key][skillLine] and now - absent[m.key][skillLine] < Harvest.ABSENT
        if not fresh and not gone then
          queue[#queue + 1] = { member = m, skillLine = skillLine, rank = rank, n = #queue + 1 }
          memberSet[m.key] = true
        end
      end
    end
  end
  table.sort(queue, function(x, y)
    if x.rank ~= y.rank then return x.rank < y.rank end
    return x.n < y.n
  end)
  local total = 0
  for _ in pairs(memberSet) do total = total + 1 end
  return queue, total, users
end

-- Whether a member runs Guildy: seen on the addon channel this session, or their own profession data
-- ("self") arrived within the last week. They share their recipes themselves, no need to open books.
Harvest.USER_DAYS = 7
function Harvest.IsGuildyUser(m)
  if ns.Sync and ns.Sync.UserVersion and ns.Sync.UserVersion(m.name) then return true end
  local guild = ns.GuildData()
  local record = guild and guild.members[m.key]
  for _, prof in pairs(record and record.profs or {}) do
    if prof.src == "self" and ns.Now() - (prof.ts or 0) < Harvest.USER_DAYS * 86400 then return true end
  end
  return false
end

local function ProfessionsFrame()
  return rawget(_G, "ProfessionsFrame") or rawget(_G, "TradeSkillFrame")
end

local function SetHidden(hidden)
  local frame = ProfessionsFrame()
  if frame and frame.SetAlpha then frame:SetAlpha(hidden and 0 or 1) end
end

-- Blizzard's window plays its open and close sound on every look. A single sound can't be muted
-- without its file id, so the game's sound effects are off while Guildy reads (music and ambience stay)
-- and come back afterwards. The old value is kept in GuildyDB until restored, so a /reload or crash in
-- the middle of a run gives it back at the next login (Harvest.RestoreSound).
local SFX = "Sound_EnableSFX"

local function GetCVarValue(name)
  local get = (C_CVar and C_CVar.GetCVar) or rawget(_G, "GetCVar")
  return get and ns.Try(get, name)
end

local function SetCVarValue(name, value)
  local set = (C_CVar and C_CVar.SetCVar) or rawget(_G, "SetCVar")
  if set then pcall(set, name, value) end
end

local function MuteSound()
  local db = ns.DB()
  if not db or db.harvestSfx ~= nil then return end
  local value = GetCVarValue(SFX)
  if value == "1" then
    db.harvestSfx = value
    SetCVarValue(SFX, "0")
  end
end

function Harvest.RestoreSound()
  local db = ns.DB()
  if not db or db.harvestSfx == nil then return end
  SetCVarValue(SFX, db.harvestSfx)
  db.harvestSfx = nil
end

local function CloseWindow()
  local close = C_TradeSkillUI and C_TradeSkillUI.CloseTradeSkill or rawget(_G, "CloseTradeSkill")
  if close then pcall(close) end
end

local Step

local function Finish(reason, keepWindow)
  if not state then return end
  local found, members = state.found, state.doneMembers
  if state.watchdog then state.watchdog:Cancel() end
  state = nil
  Harvest.RestoreSound()
  if not keepWindow then CloseWindow() end
  SetHidden(false)
  if reason then ns.Print(reason) else ns.Print(ns.L.HARVEST_DONE:format(found, members)) end
  ns.Fire("HARVEST")
  ns.Fire("PROFS")
end

function Harvest.Stop(reason)
  Finish(reason or ns.L.HARVEST_STOPPED)
end

-- Whether a scan belongs to the look in progress, and what it says: "found", "absent" (empty book,
-- no skill) or nil (not ours / data still loading)
local function Verdict(entry, startedAt, scan)
  if not (scan and scan.at and scan.at >= startedAt and scan.target == entry.member.name) then return nil end
  if scan.stale then return nil end -- the window still showed the book of the member before
  if scan.skillLine == entry.skillLine and (scan.recipes or 0) > 0 then return "found" end
  if not scan.rank or scan.rank == 0 then return "absent" end
  return nil -- has the profession, recipes not loaded yet: wait for the next scan or the timeout
end

-- Last looks for the status column and /guildy debug: {member, skill, result, path, rank, recipes,
-- seconds, server, look, of}; result "serverbad" = a server id was given up for today (server, misses, skipped)
Harvest.log = {}
Harvest.LOG_SIZE = 60

local function Push(item)
  table.insert(Harvest.log, 1, item)
  while #Harvest.log > Harvest.LOG_SIZE do table.remove(Harvest.log) end
end

local function Log(entry, result, scan, startedAt)
  local mine = scan and scan.at and scan.at >= startedAt and scan.target == entry.member.name
  Push({
    member = entry.member.name, classFile = entry.member.classFile, skillLine = entry.skillLine,
    skill = ns.TradeSkill.Name(entry.skillLine), result = result,
    path = mine and scan.path or "no scan", rank = mine and scan.rank or nil, recipes = mine and scan.recipes or nil,
    seconds = math.floor((GetTime() - startedAt) * 10 + 0.5) / 10,
    server = Harvest.ServerId(entry.member.guid), look = state and state.index, of = state and #state.queue,
  })
end

-- An empty book is a real answer ("doesn't have it"). No answer at all from the own or a known server
-- id may mean the server slows down a quick series of requests: then "silent" is only remembered while
-- reading is proven to work (a book was read in the last PROOF_LOOKS looks), and after MISS_STREAK such
-- looks in a row the pause grows (doubling, up to MAX_PAUSE). (2026-11-08: what first looked like the
-- server slowing down were members of other server ids, whose books never answer.)
Harvest.PROOF_LOOKS = 8
Harvest.MISS_STREAK = 3
Harvest.MAX_PAUSE = 30

local function NextPause()
  local over = state.streak - Harvest.MISS_STREAK
  if over < 0 then return Harvest.PAUSE end
  return math.min(Harvest.MAX_PAUSE, Harvest.PAUSE * 2 ^ (over + 1))
end

local function Check(entry, startedAt)
  if not state or state.current ~= entry then return end
  local scan = ns.TradeSkill.lastScan
  local verdict = Verdict(entry, startedAt, scan)
  local guild = ns.GuildData()
  local key = entry.member.key
  local server = Harvest.ServerId(entry.member.guid)
  local proven = state.lastFound and state.index - state.lastFound <= Harvest.PROOF_LOOKS
  local result = verdict or "no answer"
  if verdict then state.anyAnswer = true end
  if verdict == "found" then
    state.found = state.found + 1
    state.lastFound, state.streak = state.index, 0
    state.answered[key] = true
    if server then state.serverAnswered[server] = true end
  elseif not verdict and (not server or server == state.myServer or state.serverAnswered[server]) then
    -- no answer where one was due (silence of an unknown server id is expected)
    state.streak = state.streak + 1
  end
  if verdict == "absent" then
    state.answered[key] = true
    if guild then
      -- only an empty book counts as "doesn't have it"; no answer at all is tried again next run
      local absent = Absent(guild)
      absent[key] = absent[key] or {}
      absent[key][entry.skillLine] = ns.Now()
    end
  elseif not verdict and not state.firstDone and not entry.retried then
    -- the run's very first look often stays silent while Blizzard's window loads: the same look once
    -- more right after the pause, no marks
    entry.retried = true
    state.looks[key] = 0
    table.insert(state.queue, state.index + 1, entry)
    result = "retry"
  elseif not verdict and state.looks[key] == 1 and not state.answered[key] then
    -- no answer at the first look: skip the rest of the member in this run; remembered for an hour only
    -- while reading is proven to work (members without any profession get no answer)
    state.skip[key] = true
    result = "silent"
    if proven and guild then
      guild.silent = guild.silent or {}
      guild.silent[key] = ns.Now()
    end
    -- a silent member of another server id and no answer from it: skip that id for the rest of the run
    -- (any book read in this run shows the server answers at all)
    if state.found > 0 and server and server ~= state.myServer and not state.serverAnswered[server] then
      state.serverMisses[server] = (state.serverMisses[server] or 0) + 1
      if state.serverMisses[server] >= Harvest.SERVER_MISSES then
        state.badServer[server] = true
        state.serverBadPending = { result = "serverbad", server = server, misses = state.serverMisses[server] }
      end
    end
  end
  -- after the first look (and its one retry) Blizzard's window is loaded: normal waits from now on
  if result ~= "retry" then state.firstDone = true end
  Log(entry, result, scan, startedAt)
  if state.serverBadPending then
    local note = state.serverBadPending
    state.serverBadPending = nil
    -- members of that id still waiting in the queue
    local waiting = {}
    for i = state.index + 1, #state.queue do
      local other = state.queue[i].member
      if Harvest.ServerId(other.guid) == note.server then waiting[other.key] = true end
    end
    note.skipped = 0
    for _ in pairs(waiting) do note.skipped = note.skipped + 1 end
    Push(note)
  end
  CloseWindow()
  state.current = nil
  local pause = NextPause()
  state.waitUntil = GetTime() + pause
  state.slowed = pause > Harvest.PAUSE
  ns.Fire("HARVEST")
  C_Timer.After(pause, Step)
end

-- Seconds until the next look and whether Guildy slowed down (nil when not running or not waiting)
function Harvest.Waiting()
  if not state or state.current or not state.waitUntil then return nil end
  return math.max(0, state.waitUntil - GetTime()), state.slowed
end

-- Whether the run is paused because the player is in combat
function Harvest.InCombatPause()
  return state ~= nil and state.inCombat == true
end

-- Forget all "doesn't have it" marks (after a bad run)
function Harvest.ResetAbsent()
  local guild = ns.GuildData()
  if guild then guild.absent = {} end
end

-- /guildy scanreset: forget every mark of earlier runs ("doesn't have it", "silent", server ids) and
-- count all recipe data read so far as old, so the next run looks at every profession of every online
-- member again
function Harvest.ResetMarks()
  local guild = ns.GuildData()
  if guild then guild.absent, guild.silent, guild.servers, guild.scanResetAt = {}, {}, nil, ns.Now() end
  Harvest.otherRealm = 0
  ns.Print("scanreset: the next run reads every profession of every online member again")
  ns.Fire("HARVEST")
end

Step = function()
  if not state or state.current then return end -- a look is running: a second Step must not start another
  if InCombatLockdown() then
    -- paused in combat: tried again every 3 seconds, the status column says so
    state.inCombat = true
    ns.Fire("HARVEST")
    C_Timer.After(3, Step)
    return
  end
  if state.inCombat then
    state.inCombat = nil
    ns.Fire("HARVEST")
  end
  local guild = ns.GuildData()
  if not guild then return Finish() end
  local now = ns.Now()
  while state.index < #state.queue do
    state.index = state.index + 1
    local entry = state.queue[state.index]
    local m = ns.Roster.Find(entry.member.key)
    local server = Harvest.ServerId(entry.member.guid)
    if server and state.badServer[server] and not state.skip[entry.member.key] then
      state.skip[entry.member.key] = true
      Harvest.otherRealm = (Harvest.otherRealm or 0) + 1
    end
    if m and m.online and not state.skip[m.key] then
      if state.lastMember ~= m.key then
        state.lastMember = m.key
        state.doneMembers = state.doneMembers + 1
        ns.Fire("HARVEST")
      end
      local record = guild.members[m.key]
      local skip = P.PRIMARY[entry.skillLine] and PrimaryCount(record, now) >= Harvest.MAX_PRIMARY
        and not (record and record.profs[entry.skillLine])
      local link = not skip and ns.TradeSkill.BuildLink(m, entry.skillLine)
      local setItemRef = rawget(_G, "SetItemRef")
      if link and setItemRef then
        state.looks[m.key] = (state.looks[m.key] or 0) + 1
        state.current = entry
        local startedAt = GetTime()
        state.startedAt = startedAt
        SetHidden(true)
        pcall(setItemRef, link, "[" .. ns.TradeSkill.Name(entry.skillLine) .. "]", "LeftButton")
        SetHidden(true) -- the frame may only exist after the first link
        ns.Fire("HARVEST")
        -- normally OnScanned decides much earlier; this only catches "no answer" (went offline)
        C_Timer.After(state.firstDone and Harvest.WAIT or Harvest.FIRST_WAIT, function() Check(entry, startedAt) end)
        return
      end
    end
  end
  Finish()
end

function Harvest.Start()
  if state then return end
  if InCombatLockdown() then
    ns.Print(ns.L.NOT_IN_COMBAT)
    return
  end
  local guild = ns.GuildData()
  if not guild then return end
  if guild.absentVersion ~= Harvest.DATA_VERSION then
    guild.absent = {}
    guild.silent = {}
    guild.servers = nil
    guild.absentVersion = Harvest.DATA_VERSION
  end
  local db = ns.DB()
  local myServer = Harvest.ServerId(ns.Try(rawget(_G, "UnitGUID"), "player"))
  local me = ns.Roster.Find(ns.PlayerName())
  local myZone = (me and me.zone) or ns.Try(rawget(_G, "GetRealZoneText"))
  local queue, total, users = Harvest.BuildQueue(ns.Roster.Members(), guild, ns.Now(), function(m)
    return (db.ownChars and db.ownChars[m.key]) or ns.Names.Same(m.name, ns.PlayerName())
  end, myServer, Harvest.IsGuildyUser, myZone)
  Harvest.otherRealm, Harvest.users = 0, users
  if #queue == 0 then
    ns.Print(ns.L.HARVEST_NOTHING)
    ns.Fire("HARVEST")
    return
  end
  Harvest.log = {} -- a new run starts with an empty log (a stopped run's log stays until then)
  state = { queue = queue, index = 0, totalMembers = total, doneMembers = 0, found = 0, looks = {}, answered = {},
    skip = {}, myServer = myServer, serverAnswered = {}, serverMisses = {}, badServer = {}, streak = 0 }
  MuteSound()
  -- watchdog: a look without a decision or a pause that ended long ago means a timer got lost; go on
  state.watchdog = C_Timer.NewTicker(5, function()
    ns.SafeCall(function()
      if not state or state.inCombat then return end
      local now = GetTime()
      if state.current and now - state.startedAt > Harvest.FIRST_WAIT + Harvest.ABSENT_GRACE + 5 then
        Check(state.current, state.startedAt)
      elseif not state.current and state.waitUntil and now > state.waitUntil + 8 then
        Step()
      end
    end)
  end)
  ns.Fire("HARVEST")
  Step()
end

-- TradeSkill.ScanOpen finished a scan: decide right away when it answers the current look
function Harvest.OnScanned(scan)
  if not state or not state.current then return end
  local entry, startedAt = state.current, state.startedAt
  local verdict = Verdict(entry, startedAt, scan)
  if verdict == "found" then return Check(entry, startedAt) end
  -- an empty book first: the recipes may still arrive (Seshi's alchemy came back empty after 0.8 s,
  -- though a link showed it), so "doesn't have it" is only decided after a grace period
  if verdict == "absent" and not entry.graceUntil then
    entry.graceUntil = GetTime() + Harvest.ABSENT_GRACE
    C_Timer.After(Harvest.ABSENT_GRACE, function() Check(entry, startedAt) end)
  end
end

-- The player opened their own profession window: stop, so we don't close it under their hands
function Harvest.OnOwnWindow()
  if state then Finish(ns.L.HARVEST_STOPPED, true) end
end
