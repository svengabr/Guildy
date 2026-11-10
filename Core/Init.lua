-- Startup and event wiring (loaded last).
local _, ns = ...

local frame = CreateFrame("Frame")
local scanTimer

local function ScheduleTradeScan()
  ns.TradeSkill.events = (ns.TradeSkill.events or 0) + 1
  -- at most 0.5 s after the first event: a stream of updates must not postpone the scan forever
  if scanTimer then return end
  scanTimer = C_Timer.NewTimer(0.5, function()
    scanTimer = nil
    ns.SafeCall(ns.TradeSkill.ScanOpen)
  end)
end

local function OnGuildChat(kind, text, sender, ...)
  local guid = select(10, ...)
  ns.Chat.OnGuildMessage(kind, text, sender, guid)
  ns.TradeSkill.OnChatMessage(text, sender, guid)
end

-- Remembers class, level, race and guild of the logged-in character (for the own character page: the
-- account's characters in other guilds). Stays on this computer, never sent.
local function RememberSelf()
  local db = ns.DB()
  local me = ns.PlayerName()
  if not db or not me then return end
  local className, classFile = UnitClass("player")
  local raceName, raceFile = UnitRace("player")
  local guild = IsInGuild() and GetGuildInfo("player") or nil
  db.ownChars = db.ownChars or {}
  local key = ns.Names.Key(me)
  db.ownChars[key] = ns.Family.OwnRecord(db.ownChars[key], { name = me, classFile = classFile, className = className,
    level = UnitLevel("player"), raceFile = raceFile, raceName = raceName, female = UnitSex("player") == 3,
    guild = guild, guildKey = guild and ns.GuildKey() or nil }, ns.Now())
end
ns.RememberSelf = RememberSelf

local HANDLERS = {
  ADDON_LOADED = function(name)
    if name == ns.ADDON then
      GuildyDB = ns.Store.Init(rawget(_G, "GuildyDB"))
      ns.Chat.InitSeen(GuildyDB.settings, ns.Now())
      ns.Perf.Enable(GuildyDB.settings.perf) -- /guildy perf on: measuring from the login on
    end
  end,
  TRADE_SKILL_CLOSE = function() ns.TradeSkill.OnClose() end,
  PLAYER_LOGIN = function()
    if rawget(_G, "SetItemRef") then
      hooksecurefunc("SetItemRef", function(link) ns.SafeCall(ns.TradeSkill.OnLinkClicked, link) end)
    end
    ns.Harvest.RestoreSound() -- a run cut off by /reload or a crash left the sound effects off
    ns.Sync.Register()
    ns.Roster.Request(true)
    ns.SafeCall(RememberSelf)
    C_Timer.After(3, function() ns.SafeCall(ns.TradeSkill.ScanSkills) end)
    ns.Sync.Start()
    ns.GameStats.Start()
  end,
  PLAYER_LOGOUT = function()
    ns.Chat.OnLogout(ns.Settings(), ns.Now())
    ns.GameStats.UpdateOwn()
  end,
  PLAYER_TARGET_CHANGED = function() ns.GameStats.TryUnit("target") end,
  PLAYER_EQUIPMENT_CHANGED = function() ns.GameStats.OnEquipmentChanged() end,
  UPDATE_MOUSEOVER_UNIT = function() ns.GameStats.TryUnit("mouseover") end,
  INSPECT_ACHIEVEMENT_READY = function(guid) ns.GameStats.OnComparisonReady(guid) end,
  INSPECT_READY = function(guid) ns.GameStats.OnInspectReady(guid) end,
  PLAYER_GUILD_UPDATE = function()
    ns.Roster.Request(true)
    ns.Fire("GUILD")
    -- the guild name can arrive a moment later
    C_Timer.After(2, function()
      ns.SafeCall(RememberSelf)
      ns.Fire("GUILD")
    end)
  end,
  PLAYER_LEVEL_UP = function() C_Timer.After(1, function() ns.SafeCall(RememberSelf) end) end,
  GUILD_ROSTER_UPDATE = function() ns.Roster.ScheduleScan() end,
  GUILD_EVENT_LOG_UPDATE = function()
    ns.Roster.ScheduleScan()
    ns.Fire("INFO")
  end,
  GUILD_MOTD = function() ns.Fire("INFO") end,
  GUILD_RANKS_UPDATE = function() ns.Fire("INFO") end,
  GUILD_PREFERRED_PLAY_SETTINGS_UPDATED = function() ns.Fire("INFO") end,
  CHAT_MSG_GUILD = function(text, sender, ...) OnGuildChat("guild", text, sender, ...) end,
  CHAT_MSG_OFFICER = function(text, sender, ...) OnGuildChat("officer", text, sender, ...) end,
  CHAT_MSG_SYSTEM = function(text) ns.Chat.OnSystemMessage(text) end,
  CHAT_MSG_WHISPER = function(text, sender, ...)
    ns.Chat.OnWhisper(sender)
    ns.TradeSkill.OnChatMessage(text, sender, select(10, ...))
  end,
  CHAT_MSG_CHANNEL = function(text, sender, ...) ns.TradeSkill.OnChatMessage(text, sender, select(10, ...)) end,
  CHAT_MSG_SAY = function(text, sender, ...) ns.TradeSkill.OnChatMessage(text, sender, select(10, ...)) end,
  CHAT_MSG_PARTY = function(text, sender, ...) ns.TradeSkill.OnChatMessage(text, sender, select(10, ...)) end,
  CHAT_MSG_ADDON = function(...) ns.Sync.OnAddonMessage(...) end,
  CLUB_MESSAGE_ADDED = function(clubId, streamId)
    if not ns.Communities.OnMessageAdded(clubId, streamId) then ns.Fire("CHAT") end
  end,
  CLUB_ADDED = function() ns.Communities.Changed() end,
  CLUB_REMOVED = function() ns.Communities.Changed() end,
  CLUB_UPDATED = function() ns.Communities.Changed() end,
  CLUB_FAVORITES_UPDATED = function() ns.Communities.Changed() end,
  CLUB_STREAMS_LOADED = function() ns.Communities.Changed() end,
  CLUB_STREAM_ADDED = function() ns.Communities.Changed() end,
  CLUB_STREAM_REMOVED = function() ns.Communities.Changed() end,
  CLUB_STREAM_UPDATED = function() ns.Communities.Changed() end,
  CLUB_MEMBER_ADDED = function() ns.Communities.Changed() end,
  CLUB_MEMBER_REMOVED = function() ns.Communities.Changed() end,
  CLUB_MEMBER_UPDATED = function() ns.Communities.Changed() end,
  CLUB_MEMBER_PRESENCE_UPDATED = function() ns.Communities.Changed() end,
  CLUB_INVITATIONS_RECEIVED_FOR_SELF = function() ns.Communities.Changed() end,
  CLUB_INVITATION_ADDED_FOR_SELF = function() ns.Communities.Changed() end,
  CLUB_INVITATION_REMOVED_FOR_SELF = function() ns.Communities.Changed() end,
  CLUB_MESSAGE_HISTORY_RECEIVED = function(clubId, streamId)
    ns.Chat.OnHistoryReceived(clubId, streamId)
    ns.Fire("CHAT")
  end,
  TRADE_SKILL_SHOW = ScheduleTradeScan,
  TRADE_SKILL_LIST_UPDATE = ScheduleTradeScan,
  CRAFT_SHOW = ScheduleTradeScan,
  CRAFT_UPDATE = ScheduleTradeScan,
  SKILL_LINES_CHANGED = function() C_Timer.After(1, function() ns.SafeCall(ns.TradeSkill.ScanSkills) end) end,
}

frame:SetScript("OnEvent", function(_, event, ...)
  local handler = HANDLERS[event]
  if not handler then return end
  -- chat events: skip messages whose text, sender or guid are secret (instances, encounters)
  if event:find("^CHAT_MSG_") and ns.AnySecret(select(1, ...), select(2, ...), select(4, ...), select(12, ...)) then
    return
  end
  ns.Perf.Call("event", event, ns.SafeCall, handler, ...)
end)

-- Work that runs from timers, outside the events above (/guildy perf)
ns.Perf.Wrap(ns.Roster, "Scan", "scan", "roster")
ns.Perf.Wrap(ns.TradeSkill, "ScanOpen", "scan", "profession window")
ns.Perf.Wrap(ns.TradeSkill, "ScanSkills", "scan", "own skills")
ns.Perf.Wrap(ns.GameStats, "UpdateOwn", "scan", "own statistics")
ns.Perf.Wrap(ns.Chat, "History", "read", "chat history")
ns.Perf.Wrap(ns.UI, "MemberTooltip", "tooltip", "member")

-- /guildy perf: on | off | reset | copy, without a word the report
local function PerfCommand(word)
  local Perf = ns.Perf
  if word == "on" or word == "off" then
    ns.Settings().perf = (word == "on") or nil
    Perf.Enable(word == "on")
    if word == "on" then Perf.Reset() end
    ns.Print("perf " .. word .. (word == "on" and ": use Guildy as usual, then /guildy perf" or ""))
    return
  end
  if word == "reset" then
    Perf.Reset()
    ns.Print("perf reset")
    return
  end
  if not Perf.on then
    ns.Print("perf is off. /guildy perf on starts measuring (it stays on over /reload and logins).")
    return
  end
  local online, total = ns.Roster.Counts()
  local memory = ""
  local update, usage = rawget(_G, "UpdateAddOnMemoryUsage"), rawget(_G, "GetAddOnMemoryUsage")
  if update and usage then
    update()
    memory = (" · %.1f MB"):format((ns.Try(usage, ns.ADDON) or 0) / 1024)
  end
  local context = ("Guildy %s · %d members, %d online%s"):format(ns.Version(), total, online, memory)
  local lines = Perf.Lines(context, word == "copy" and 40 or 15)
  GuildyDB.perfReport = lines -- also in the SavedVariables after /reload
  if word == "copy" then
    ns.UI.CopyText(table.concat(lines, "\n"))
  else
    for _, line in ipairs(lines) do ns.Print(line) end
  end
end
for event in pairs(HANDLERS) do
  pcall(frame.RegisterEvent, frame, event) -- some events may not exist on this client
end

SLASH_GUILDY1 = "/guildy"
SlashCmdList.GUILDY = function(msg)
  local raw = (msg or ""):match("^%s*(.-)%s*$")
  msg = raw:lower()
  if msg:match("^probelater") then
    -- same as probe, but from a timer (no key press behind it)
    local args = raw:sub(11)
    ns.Print("probelater: opening in 2 seconds ...")
    C_Timer.After(2, function() ns.TradeSkill.Probe(args) end)
  elseif msg:match("^probe") then
    ns.TradeSkill.Probe(raw:sub(6))
  elseif msg == "shots backdrop" then
    ns.UI.ToggleShotBackdrop()
  elseif msg == "shots" then
    ns.UI.TakeShots()
  elseif msg:match("^perf") then
    PerfCommand(msg:match("^perf%s+(%a+)"))
  elseif msg:match("^rights") then
    ns.Roster.DebugRights(raw:sub(8))
  elseif msg == "chatdebug" then
    for _, line in ipairs(ns.Chat.Debug("guild")) do ns.Print(line) end
    local view = ns.UI.TabView("chat")
    if view and view.Messages then
      local m = view.Messages
      ns.Print("frame lines " .. tostring(m.GetNumMessages and m:GetNumMessages()) .. " offset "
        .. tostring(m.GetScrollOffset and m:GetScrollOffset()) .. " max " .. tostring(m.GetMaxScrollRange and m:GetMaxScrollRange()))
      local ok, err = pcall(view.RenderChat, view)
      ns.Print("render ok " .. tostring(ok) .. " " .. tostring(err))
    end
  elseif msg == "notedebug" then
    for _, line in ipairs(ns.UI.Notes.Debug()) do ns.Print(line) end
  elseif msg == "communitydebug" then
    for _, line in ipairs(ns.Communities.Debug()) do ns.Print(line) end
  elseif msg == "statdebug" then
    ns.GameStats.debug = not ns.GameStats.debug
    ns.Print("statdebug " .. (ns.GameStats.debug and "on" or "off"))
  elseif msg:match("^statshow") then
    ns.GameStats.Show(raw:sub(10))
  elseif msg == "scanreset" then
    ns.Harvest.ResetMarks()
  elseif msg == "statreset" then
    ns.GameStats.ResetWaits()
  elseif msg == "statmouse" then
    ns.GameStats.ToggleMouseover()
  elseif msg == "statdump" then
    -- every statistic of this character into GuildyDB.statDump (read from SavedVariables after /reload)
    local dump, count = {}, 0
    local list = ns.Try(rawget(_G, "GetStatisticsCategoryList")) or {}
    for _, categoryID in ipairs(list) do
      local name, parent = ns.Try(rawget(_G, "GetCategoryInfo"), categoryID)
      local entry = { id = categoryID, name = name, parent = parent, stats = {} }
      for i = 1, ns.Try(rawget(_G, "GetCategoryNumAchievements"), categoryID) or 0 do
        local quantity, skip, statID = ns.Try(rawget(_G, "GetStatistic"), categoryID, i)
        if statID then
          local _, statName = ns.Try(rawget(_G, "GetAchievementInfo"), statID)
          entry.stats[#entry.stats + 1] = { id = statID, name = statName, value = quantity, skip = skip }
          count = count + 1
        end
      end
      dump[#dump + 1] = entry
    end
    GuildyDB.statDump = dump
    ns.Print(("statdump: %d categories, %d statistics stored. /reload to write them to disk."):format(#dump, count))
  elseif msg == "profdump" then
    ns.TradeSkill.ProfDump()
  elseif msg == "debug" then
    ns.TradeSkill.Debug()
  elseif msg == "sync" then
    ns.Sync.SendSummary()
    ns.Print(ns.L.SYNC_SENT)
  else
    ns.UI.Toggle()
  end
end
