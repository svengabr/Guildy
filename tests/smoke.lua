-- Load smoke test: loads every TOC file in order against permissive WoW stubs (any frame method
-- exists), fires the startup events, opens the window and every tab, and fails on any Lua error,
-- including errors reported through geterrorhandler (ns.SafeCall).
local T = ...

local errors = {}
local registered = {}   -- event -> {frames}
local timers = {}

local function Stub(name)
  local stub = { _name = name, _scripts = {}, _shown = false, _text = "", _w = 100, _h = 100, _checked = false }
  local methods = {}
  function methods:GetName() return self._name end
  function methods:GetWidth() return self._w end
  function methods:GetHeight() return self._h end
  function methods:SetWidth(w) self._w = w end
  function methods:SetHeight(h) self._h = h end
  function methods:SetSize(w, h) self._w, self._h = w, h end
  function methods:GetStringWidth() return 50 end
  function methods:GetFont() return "Fonts\\FRIZQT__.TTF", 12, "" end
  function methods:GetPoint() return "CENTER", nil, "CENTER", 0, 0 end
  function methods:GetFrameLevel() return 1 end
  function methods:IsShown() return self._shown end
  function methods:IsVisible() return self._shown end
  function methods:Show()
    local was = self._shown
    self._shown = true
    if not was and self._scripts.OnShow then self._scripts.OnShow(self) end
  end
  function methods:Hide()
    local was = self._shown
    self._shown = false
    if was and self._scripts.OnHide then self._scripts.OnHide(self) end
  end
  function methods:SetShown(v) if v then self:Show() else self:Hide() end end
  function methods:HasFocus() return false end
  function methods:GetText() return self._text end
  function methods:SetText(t) self._text = t or "" end
  function methods:GetChecked() return self._checked end
  function methods:SetChecked(v) self._checked = v end
  function methods:IsTruncated() return false end
  function methods:SetScript(event, fn) self._scripts[event] = fn end
  function methods:GetScript(event) return self._scripts[event] end
  function methods:HookScript(event, fn)
    local old = self._scripts[event]
    self._scripts[event] = function(...) if old then old(...) end fn(...) end
  end
  function methods:RegisterEvent(event)
    registered[event] = registered[event] or {}
    table.insert(registered[event], self)
  end
  function methods:CreateTexture() return Stub() end
  function methods:CreateFontString() return Stub() end
  function methods:CreateAnimationGroup() return Stub() end
  function methods:GetFontString() return self._fs or Stub() end
  function methods:GetParent() return self._parent or Stub() end
  local CHILDREN = { Inset = true, TitleText = true }
  return setmetatable(stub, { __index = function(self, key)
    if methods[key] then return methods[key] end
    if CHILDREN[key] then
      local child = Stub()
      rawset(self, key, child)
      return child
    end
    if type(key) == "string" and key:match("^%l") then return nil end -- fields, not methods
    return function() end
  end })
end

local env = {
  UIParent = Stub("UIParent"),
  GameTooltip = Stub("GameTooltip"),
  DEFAULT_CHAT_FRAME = Stub("ChatFrame1"),
  ChatFontNormal = Stub("ChatFontNormal"),
  QuestTitleFont = Stub("QuestTitleFont"),
  UISpecialFrames = {},
  StaticPopupDialogs = {},
  SlashCmdList = {},
  RAID_CLASS_COLORS = setmetatable({}, { __index = function() return { r = 1, g = 0.5, b = 0.2 } end }),
  ChatTypeInfo = { GUILD = { r = 0.25, g = 1, b = 0.25 }, OFFICER = { r = 0.25, g = 0.75, b = 0.25 } },
  LOCALIZED_CLASS_NAMES_MALE = { DRUID = "Druide", PALADIN = "Paladin", ROGUE = "Schurke" },
  ERR_GUILD_JOIN_S = "%s ist der Gilde beigetreten.",
  ACCEPT = "Annehmen", CANCEL = "Abbrechen", YES = "Ja", NO = "Nein",
}
env.CreateFrame = function(_, name, parent)
  local frame = Stub(name)
  frame._parent = parent
  if name then env[name] = frame end
  frame._fs = Stub()
  return frame
end
env.C_Timer = {
  After = function(_, fn) timers[#timers + 1] = fn end,
  NewTimer = function(_, fn) timers[#timers + 1] = fn return { Cancel = function() end } end,
  NewTicker = function() return { Cancel = function() end } end,
}
env.tinsert = table.insert
env.GetTime = function() return 1000 end
env.GetServerTime = function() return 1700000000 end
env.GetLocale = function() return "deDE" end
env.IsInGuild = function() return true end
env.GetGuildInfo = function() return "Murloc Mafia", "Haifutter", 1 end
env.GetNormalizedRealmName = function() return "Forever" end
env.UnitName = function() return "Ran", "Fred" end
env.UnitExists = function() return false end
env.InCombatLockdown = function() return false end
env.IsShiftKeyDown = function() return false end
env.hooksecurefunc = function() end
env.geterrorhandler = function() return function(err) errors[#errors + 1] = tostring(err) end end
env.StaticPopup_Show = function() end
env.PanelTemplates_SetNumTabs = function() end
env.PanelTemplates_SetTab = function() end
env.PanelTemplates_TabResize = function() end
env.ButtonFrameTemplate_HideButtonBar = function() end
env.ToggleGuildFrame = function() end
env.CanGuildInvite = function() return true end
env.CanGuildRemove = function() return true end
env.CanGuildPromote = function() return true end
env.CanGuildDemote = function() return true end
env.CanEditPublicNote = function() return true end
env.CanEditMOTD = function() return true end
env.CanEditGuildInfo = function() return true end
env.GuildControlGetNumRanks = function() return 3 end
env.GuildControlGetRankName = function(i) return ({ "GM", "Offizier", "Haifutter" })[i] end
env.C_GuildInfo = {
  GuildRoster = function() end,
  GetMOTD = function() return "Mrglmrglmrgl!" end,
  GetInfoText = function() return "Discord" end,
  CanViewOfficerNote = function() return true end,
  CanEditOfficerNote = function() return true end,
}
env.C_ChatInfo = { RegisterAddonMessagePrefix = function() end, SendAddonMessage = function() end, SendChatMessage = function() end }
env.C_Spell = { GetSpellName = function(id) return "Rezept " .. id end }

local roster = {
  { "Ran-Fred", "Offizier", 1, 16, "Druide", "Sturmwind", "", "", true, 0, "DRUID", nil, nil, false, nil, nil, "Player-1-01" },
  { "Makira-Farron", "Offizier", 1, 16, "Paladin", "Eisenschmiede", "Heiler", "", false, 0, "PALADIN", nil, nil, false, nil, nil, "Player-1-02" },
  { "Au-Tsch", "Haifutter", 2, 21, "Schurke", "Dämmerwald", "", "", true, 0, "ROGUE", nil, nil, false, nil, nil, "Player-1-03" },
}
env.GetNumGuildMembers = function() return #roster end
env.GetGuildRosterInfo = function(i) return unpack(roster[i]) end
env.GetGuildRosterLastOnline = function(i) if i == 2 then return 0, 0, 3, 2 end end
env.GetNumGuildEvents = function() return 1 end
env.GetGuildEventInfo = function() return "join", "Au-Tsch", nil, nil, 0, 0, 1, 0 end
env.GetNumSkillLines = function() return 2 end
env.GetSkillLineInfo = function(i)
  if i == 1 then return "Berufe", true end
  return "Alchemie", false, nil, 120, 0, 0, 150
end

setmetatable(env, { __index = _G })
env._G = env

local ns = {}
for _, file in ipairs(T.tocFiles()) do
  local chunk, err = loadfile(T.addonDir .. "/" .. file)
  if not chunk then error(err) end
  setfenv(chunk, env)
  chunk("Guildy", ns)
end

local function Fire(event, ...)
  for _, frame in ipairs(registered[event] or {}) do
    local handler = frame._scripts.OnEvent
    if handler then handler(frame, event, ...) end
  end
end

local function RunTimers()
  for _ = 1, 5 do
    local pending = timers
    timers = {}
    for _, fn in ipairs(pending) do fn() end
  end
end

T.describe("Smoke", function()
  T.it("loads and starts", function()
    Fire("ADDON_LOADED", "Guildy")
    Fire("PLAYER_LOGIN")
    Fire("GUILD_ROSTER_UPDATE")
    RunTimers()
    T.eq(#ns.Roster.Members(), 3)
    T.truthy(env.GuildyDB and env.GuildyDB.settings, "GuildyDB initialised")
    T.eq(errors, {})
  end)

  T.it("scans own skills", function()
    ns.TradeSkill.ScanSkills()
    local guild = ns.GuildData()
    T.eq(guild.members["ran fred"].profs[171].rank, 120)
    T.eq(errors, {})
  end)

  T.it("opens the window on the chat tab and every tab", function()
    env.ToggleGuildFrame()
    T.truthy(ns.UI.IsShown(), "J opens Guildy")
    T.eq(ns.UI.Current(), "chat")
    for _, key in ipairs({ "members", "overview", "professions", "info", "chat" }) do
      ns.UI.SelectTab(key)
      T.eq(ns.UI.Current(), key)
    end
    ns.UI.FilterMembers({ classFile = "PALADIN" })
    T.eq(errors, {})
  end)

  T.it("handles chat, links and sync messages", function()
    Fire("CHAT_MSG_GUILD", "hallo |Htrade:Player-1-03:3908:197|h[Schneiderei]|h", "Au-Tsch", "", "", "", "", 0, 0, "", 0, 1, "Player-1-03")
    Fire("CHAT_MSG_SYSTEM", "Xii Lightspark ist der Gilde beigetreten.")
    Fire("CHAT_MSG_WHISPER", "inv pls", "Xii-Lightspark")
    T.eq(#ns.Chat.History("guild"), 2)
    T.eq(ns.Chat.RecentWhispers()[1].name, "Xii Lightspark")
    T.truthy(ns.GuildData().members["au tsch"].profs[197], "link stored")
    local P = ns.Protocol
    local payload = P.Encode("PROF", { m = "Makira Farron", p = { ["171"] = { ts = 5, rank = 100, recipes = { 1, 2 } } } })
    for _, part in ipairs(P.Chunk("x1", payload)) do Fire("CHAT_MSG_ADDON", "GUILDY", part, "GUILD", "Makira-Farron") end
    T.eq(ns.GuildData().members["makira farron"].profs[171].src, "self")
    ns.UI.SelectTab("professions")
    ns.UI.Show()
    ns.UI.ShowInvite(env.UIParent)
    RunTimers()
    T.eq(errors, {})
  end)
end)
