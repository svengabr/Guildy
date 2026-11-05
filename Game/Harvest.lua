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
Harvest.PAUSE = 1              -- seconds between looks (the server may ignore requests in quick succession)
Harvest.DATA_VERSION = 3       -- bump to drop "absent"/"silent" marks made by older, faulty runs

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

function Harvest.Progress()
  if not state then return nil end
  return state.doneMembers, state.totalMembers, state.found
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

-- Server id in a player GUID ("Player-6949-0074341C" -> "6949"). Recipe books only open for members of
-- the player's own realm, not for those on other realms of the connected realm group.
function Harvest.ServerId(guid)
  return type(guid) == "string" and guid:match("^Player%-(%d+)%-") or nil
end

-- Pure: which (member, profession) pairs to look at. members = roster entries, guild = stored data,
-- myServer = server id of the player. Returns queue, member count, members skipped for another realm.
function Harvest.BuildQueue(members, guild, now, isOwn, myServer)
  local queue, memberSet = {}, {}
  local absent = guild.absent or {}
  local silent = guild.silent or {}
  local otherRealm = 0
  for _, m in ipairs(members) do
    local quiet = silent[m.key] and now - silent[m.key] < Harvest.FRESH
    local sameRealm = not myServer or Harvest.ServerId(m.guid) == myServer
    if m.online and not m.isMobile and m.guid and not isOwn(m) and not sameRealm then
      otherRealm = otherRealm + 1
    elseif m.online and not m.isMobile and m.guid and not isOwn(m) and not quiet then
      local record = guild.members[m.key]
      -- professions the guild note mentions go first: the first look decides whether a member is skipped
      local order = {}
      for _, skillLine in ipairs(Harvest.ORDER) do
        local prof = record and record.profs and record.profs[skillLine]
        if prof and prof.src == "note" then order[#order + 1] = skillLine end
      end
      for _, skillLine in ipairs(Harvest.ORDER) do
        local prof = record and record.profs and record.profs[skillLine]
        if not (prof and prof.src == "note") then order[#order + 1] = skillLine end
      end
      for _, skillLine in ipairs(order) do
        local prof = record and record.profs and record.profs[skillLine]
        local fresh = prof and prof.recipes and now - (prof.ts or 0) < Harvest.FRESH
        local gone = absent[m.key] and absent[m.key][skillLine] and now - absent[m.key][skillLine] < Harvest.ABSENT
        if not fresh and not gone then
          queue[#queue + 1] = { member = m, skillLine = skillLine }
          memberSet[m.key] = true
        end
      end
    end
  end
  local total = 0
  for _ in pairs(memberSet) do total = total + 1 end
  return queue, total, otherRealm
end

local function ProfessionsFrame()
  return rawget(_G, "ProfessionsFrame") or rawget(_G, "TradeSkillFrame")
end

local function SetHidden(hidden)
  local frame = ProfessionsFrame()
  if frame and frame.SetAlpha then frame:SetAlpha(hidden and 0 or 1) end
end

local function CloseWindow()
  local close = C_TradeSkillUI and C_TradeSkillUI.CloseTradeSkill or rawget(_G, "CloseTradeSkill")
  if close then pcall(close) end
end

local Step

local function Finish(reason, keepWindow)
  if not state then return end
  local found, members = state.found, state.doneMembers
  state = nil
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
  if scan.skillLine == entry.skillLine and (scan.recipes or 0) > 0 then return "found" end
  if not scan.rank or scan.rank == 0 then return "absent" end
  return nil -- has the profession, recipes not loaded yet: wait for the next scan or the timeout
end

-- Last looks for /guildy debug: {member, skill, result, path, rank, recipes, seconds}
Harvest.log = {}

local function Log(entry, result, scan, startedAt)
  local mine = scan and scan.at and scan.at >= startedAt and scan.target == entry.member.name
  table.insert(Harvest.log, 1, {
    member = entry.member.name, classFile = entry.member.classFile, skillLine = entry.skillLine,
    skill = ns.TradeSkill.Name(entry.skillLine), result = result,
    path = mine and scan.path or "no scan", rank = mine and scan.rank or nil, recipes = mine and scan.recipes or nil,
    seconds = math.floor((GetTime() - startedAt) * 10 + 0.5) / 10,
  })
  while #Harvest.log > 30 do table.remove(Harvest.log) end
end

local function Check(entry, startedAt)
  if not state or state.current ~= entry then return end
  local scan = ns.TradeSkill.lastScan
  local verdict = Verdict(entry, startedAt, scan)
  local guild = ns.GuildData()
  if verdict == "found" then
    state.found = state.found + 1
  elseif verdict == "absent" and guild then
    -- only an empty book counts as "doesn't have it"; no answer at all is tried again next run
    local absent = Absent(guild)
    absent[entry.member.key] = absent[entry.member.key] or {}
    absent[entry.member.key][entry.skillLine] = ns.Now()
  end
  local key = entry.member.key
  local result = verdict or "no answer"
  if verdict then
    state.answered[key] = true
  elseif state.looks[key] == 1 and not state.answered[key] then
    -- the server stays silent for members without any profession: skip the rest of them for a day
    state.skip[key] = true
    if guild then
      guild.silent = guild.silent or {}
      guild.silent[key] = ns.Now()
    end
    result = "silent"
  end
  Log(entry, result, scan, startedAt)
  CloseWindow()
  state.current = nil
  ns.Fire("HARVEST")
  C_Timer.After(Harvest.PAUSE, Step)
end

-- Forget all "doesn't have it" marks (after a bad run)
function Harvest.ResetAbsent()
  local guild = ns.GuildData()
  if guild then guild.absent = {} end
end

Step = function()
  if not state then return end
  if InCombatLockdown() then
    C_Timer.After(3, Step)
    return
  end
  local guild = ns.GuildData()
  if not guild then return Finish() end
  local now = ns.Now()
  while state.index < #state.queue do
    state.index = state.index + 1
    local entry = state.queue[state.index]
    local m = ns.Roster.Find(entry.member.key)
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
        C_Timer.After(Harvest.WAIT, function() Check(entry, startedAt) end)
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
    guild.absentVersion = Harvest.DATA_VERSION
  end
  local db = ns.DB()
  local myServer = Harvest.ServerId(ns.Try(rawget(_G, "UnitGUID"), "player"))
  local queue, total, otherRealm = Harvest.BuildQueue(ns.Roster.Members(), guild, ns.Now(), function(m)
    return (db.ownChars and db.ownChars[m.key]) or ns.Names.Same(m.name, ns.PlayerName())
  end, myServer)
  Harvest.otherRealm = otherRealm
  if #queue == 0 then
    ns.Print(ns.L.HARVEST_NOTHING)
    ns.Fire("HARVEST")
    return
  end
  state = { queue = queue, index = 0, totalMembers = total, doneMembers = 0, found = 0, looks = {}, answered = {}, skip = {} }
  ns.Fire("HARVEST")
  Step()
end

-- TradeSkill.ScanOpen finished a scan: decide right away when it answers the current look
function Harvest.OnScanned(scan)
  if not state or not state.current then return end
  if Verdict(state.current, state.startedAt, scan) then Check(state.current, state.startedAt) end
end

-- The player opened their own profession window: stop, so we don't close it under their hands
function Harvest.OnOwnWindow()
  if state then Finish(ns.L.HARVEST_STOPPED, true) end
end
