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

local HANDLERS = {
  ADDON_LOADED = function(name)
    if name == ns.ADDON then
      GuildyDB = ns.Store.Init(rawget(_G, "GuildyDB"))
    end
  end,
  UPDATE_BINDINGS = function() ns.Redirect.Apply() end,
  PLAYER_REGEN_ENABLED = function() ns.Redirect.AfterCombat() end,
  TRADE_SKILL_CLOSE = function() ns.TradeSkill.OnClose() end,
  PLAYER_LOGIN = function()
    if rawget(_G, "SetItemRef") then
      hooksecurefunc("SetItemRef", function(link) ns.SafeCall(ns.TradeSkill.OnLinkClicked, link) end)
    end
    ns.Redirect.Apply()
    ns.Sync.Register()
    ns.Roster.Request(true)
    C_Timer.After(3, function() ns.SafeCall(ns.TradeSkill.ScanSkills) end)
    ns.Sync.Start()
  end,
  PLAYER_GUILD_UPDATE = function() ns.Roster.Request(true) end,
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
  CLUB_MESSAGE_ADDED = function() ns.Fire("CHAT") end,
  CLUB_MESSAGE_HISTORY_RECEIVED = function() ns.Fire("CHAT") end,
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
  ns.SafeCall(handler, ...)
end)
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
  elseif msg:match("^rights") then
    ns.Roster.DebugRights(raw:sub(8))
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
