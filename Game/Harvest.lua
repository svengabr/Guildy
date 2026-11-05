-- "Read online members": opens the profession link of every online guild member for every profession
-- with recipes, one at a time, so TradeSkill.ScanOpen stores what the server sends. Links only open for
-- online members; a profession the member doesn't have opens an empty book and is remembered as absent
-- for a week. Only on the player's click, never in combat, Blizzard's window stays invisible while it
-- runs and is closed after each look. Opening the player's own profession window stops it.
local _, ns = ...
local P = ns.Professions

local Harvest = {}
ns.Harvest = Harvest

-- professions with a recipe book; crafting first, then mining (smelting), then the secondary ones
Harvest.ORDER = { 171, 164, 333, 202, 165, 197, 186, 185, 129 }
Harvest.FRESH = 24 * 3600      -- data younger than this is not read again
Harvest.ABSENT = 7 * 24 * 3600 -- "doesn't have it" is remembered this long
Harvest.WAIT = 1.5             -- seconds to wait for the server per look
Harvest.MAX_PRIMARY = 2

local state

function Harvest.IsRunning()
  return state ~= nil
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

-- Pure: which (member, profession) pairs to look at. members = roster entries, guild = stored data
function Harvest.BuildQueue(members, guild, now, isOwn)
  local queue, memberSet = {}, {}
  local absent = guild.absent or {}
  for _, m in ipairs(members) do
    if m.online and not m.isMobile and m.guid and not isOwn(m) then
      local record = guild.members[m.key]
      for _, skillLine in ipairs(Harvest.ORDER) do
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
  return queue, total
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

local function Check(entry, startedAt)
  if not state or state.current ~= entry then return end
  local scan = ns.TradeSkill.lastScan
  local ok = scan and scan.at and scan.at >= startedAt and scan.target == entry.member.name
    and scan.skillLine == entry.skillLine and (scan.recipes or 0) > 0
  local guild = ns.GuildData()
  if ok then
    state.found = state.found + 1
  elseif guild then
    local absent = Absent(guild)
    absent[entry.member.key] = absent[entry.member.key] or {}
    absent[entry.member.key][entry.skillLine] = ns.Now()
  end
  CloseWindow()
  state.current = nil
  C_Timer.After(0.3, Step)
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
    if m and m.online then
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
        state.current = entry
        local startedAt = GetTime()
        SetHidden(true)
        pcall(setItemRef, link, "[" .. ns.TradeSkill.Name(entry.skillLine) .. "]", "LeftButton")
        SetHidden(true) -- the frame may only exist after the first link
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
  local db = ns.DB()
  local queue, total = Harvest.BuildQueue(ns.Roster.Members(), guild, ns.Now(), function(m)
    return (db.ownChars and db.ownChars[m.key]) or ns.Names.Same(m.name, ns.PlayerName())
  end)
  if #queue == 0 then
    ns.Print(ns.L.HARVEST_NOTHING)
    return
  end
  state = { queue = queue, index = 0, totalMembers = total, doneMembers = 0, found = 0 }
  ns.Fire("HARVEST")
  Step()
end

-- The player opened their own profession window: stop, so we don't close it under their hands
function Harvest.OnOwnWindow()
  if state then Finish(ns.L.HARVEST_STOPPED, true) end
end
