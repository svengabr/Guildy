-- Load smoke test: loads every TOC file in order against permissive WoW stubs (any frame method
-- exists), fires the startup events, opens the window and every tab, and fails on any Lua error,
-- including errors reported through geterrorhandler (ns.SafeCall).
local T = ...

local errors = {}
local registered = {}   -- event -> {frames}
local timers = {}
local boundKeys = {}

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
  local CHILDREN = { Inset = true, TitleText = true, Icon = true, Mask = true, HighlightTexture = true, SelectedTexture = true }
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
local SECRET = setmetatable({}, { __index = function() error("secret value inspected") end })
env.issecretvalue = function(v) return v == SECRET end
env.SetOverrideBindingClick = function(_, _, key, button) boundKeys[key] = button end
env.GetBindingKey = function(action) if action == "TOGGLEGUILDTAB" then return "J" end end
env.ClearOverrideBindings = function() end
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
  { "Au-Tsch", "Haifutter", 2, 21, "Schurke", "Dämmerwald", "Kürsch", "", true, 0, "ROGUE", nil, nil, false, nil, nil, "Player-1-03" },
}
env.GetNumGuildMembers = function() return #roster end
env.GetGuildRosterInfo = function(i) return unpack(roster[i], 1, 17) end
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

local function RunTimers(rounds)
  for _ = 1, rounds or 5 do
    local pending = timers
    timers = {}
    for _, fn in ipairs(pending) do fn() end
  end
end

T.describe("Widgets", function()
  T.it("defines every W.* helper the code uses", function()
    for _, file in ipairs(T.tocFiles()) do
      if file:match("^UI/") then
        for helper in T.readFile(T.addonDir .. "/" .. file):gmatch("W%.([A-Z]%w*)%(") do
          T.truthy(type(ns.Widgets[helper]) == "function", file .. " uses missing W." .. helper)
        end
      end
    end
  end)
end)

T.describe("Smoke", function()
  T.it("loads and starts", function()
    Fire("ADDON_LOADED", "Guildy")
    Fire("PLAYER_LOGIN")
    Fire("GUILD_ROSTER_UPDATE")
    RunTimers()
    T.eq(#ns.Roster.Members(), 3)
    T.eq(ns.GuildData().members["makira farron"], nil) -- note "Heiler" mentions no profession
    T.eq(ns.GuildData().members["au tsch"].profs[393].src, "note")
    T.truthy(env.GuildyDB and env.GuildyDB.settings, "GuildyDB initialised")
    T.eq(errors, {})
  end)

  T.it("scans own skills", function()
    ns.TradeSkill.ScanSkills()
    local guild = ns.GuildData()
    T.eq(guild.members["ran fred"].profs[171].rank, 120)
    ns.TradeSkill.ScanOpen()
    ns.TradeSkill.Debug()
    -- recipe book of another member, opened through their profession link
    local linked = true
    env.C_TradeSkillUI = {
      GetAllRecipeIDs = function() return { 11, 12, 13 } end,
      GetRecipeInfo = function(id) return { learned = id ~= 13 } end,
      GetBaseProfessionInfo = function() return { professionID = 171, professionName = "Alchimie", skillLevel = 99, maxSkillLevel = 150 } end,
      IsTradeSkillLinked = function() return linked, "Au-Tsch" end,
    }
    ns.TradeSkill.ScanOpen()
    T.eq(guild.members["au tsch"].profs[171].recipes, { 11, 12 })
    T.eq(guild.members["au tsch"].profs[171].src, "link")
    T.eq(guild.members["ran fred"].profs[171].recipes, nil)
    -- own window again
    linked = false
    ns.TradeSkill.ScanOpen()
    T.eq(guild.members["ran fred"].profs[171].recipes, { 11, 12 })
    -- no IsTradeSkillLinked: a clicked link decides
    env.C_TradeSkillUI.IsTradeSkillLinked = nil
    ns.TradeSkill.OnLinkClicked("trade:Player-1-02:2259:171")
    env.C_TradeSkillUI.GetBaseProfessionInfo = function() return { professionID = 171, skillLevel = 40, maxSkillLevel = 75 } end
    ns.TradeSkill.ScanOpen()
    T.eq(guild.members["makira farron"].profs[171].rank, 40)
    ns.TradeSkill.ProfDump()
    ns.TradeSkill.OnClose()
    env.C_TradeSkillUI = nil
    local opened
    env.SetItemRef = function(link) opened = link end
    ns.TradeSkill.Probe("Makira Farron Alchemie")
    T.eq(opened, "trade:Player-1-02:2259:171")
    local au = ns.Roster.Find("Au Tsch")
    T.eq(ns.TradeSkill.CanOpenBook(au), true)
    T.eq(ns.TradeSkill.CanOpenBook(ns.Roster.Find("Makira Farron")), false) -- offline
    T.eq(ns.TradeSkill.OpenBook(au, 197), true)
    T.eq(opened, "trade:Player-1-03:3908:197")
    env.SetItemRef = nil
    T.eq(errors, {})
  end)

  T.it("opens the window on the chat tab and every tab", function()
    env.GuildyToggleButton._scripts.PostClick(env.GuildyToggleButton, "LeftButton", false)
    T.truthy(ns.UI.IsShown(), "J opens Guildy")
    T.eq(boundKeys.J, "GuildyToggleButton")
    T.eq(ns.UI.Current(), "chat")
    for _, key in ipairs({ "members", "overview", "fame", "professions", "info", "ranks", "chat" }) do
      ns.UI.SelectTab(key)
      T.eq(ns.UI.Current(), key)
    end
    ns.UI.FilterMembers({ classFile = "PALADIN" })
    T.eq(errors, {})
  end)

  T.it("handles chat, links and sync messages", function()
    Fire("CHAT_MSG_GUILD", "hallo |Htrade:Player-1-03:3908:197|h[Schneiderei]|h", "Au-Tsch", "", "", "", "", 0, 0, "", 0, 1, "Player-1-03")
    Fire("CHAT_MSG_SYSTEM", "Xii Lightspark ist der Gilde beigetreten.")
    Fire("CHAT_MSG_SYSTEM", SECRET)
    Fire("CHAT_MSG_GUILD", SECRET, "Au-Tsch")
    Fire("CHAT_MSG_WHISPER", "hi", SECRET)
    Fire("CHAT_MSG_ADDON", "GUILDY", SECRET, "GUILD", "Au-Tsch")
    Fire("CHAT_MSG_WHISPER", "inv pls", "Xii-Lightspark")
    T.eq(#ns.Chat.History("guild"), 2)
    T.eq(ns.Chat.RecentWhispers()[1].name, "Xii Lightspark")
    T.truthy(ns.GuildData().members["au tsch"].profs[197], "link stored")
    local P = ns.Protocol
    local payload = P.Encode("PROF", { m = "Makira Farron", p = { ["171"] = { ts = 1800000000, rank = 100, recipes = { 1, 2 } } } })
    for _, part in ipairs(P.Chunk("x1", payload)) do Fire("CHAT_MSG_ADDON", "GUILDY", part, "GUILD", "Makira-Farron") end
    T.eq(ns.GuildData().members["makira farron"].profs[171].src, "self")
    T.eq(ns.Sync.UserVersion("Makira Farron"), "") -- any message marks a Guildy user (this one without version)
    for _, part in ipairs(P.Chunk("h1", P.Encode("HI", { q = true }, "0.1.0"))) do
      Fire("CHAT_MSG_ADDON", "GUILDY", part, "GUILD", "Au-Tsch")
    end
    T.eq(ns.Sync.UserVersion("Au Tsch"), "0.1.0")
    for _, part in ipairs(P.Chunk("h2", P.Encode("HI", {}))) do Fire("CHAT_MSG_ADDON", "GUILDY", part, "GUILD", "Xii-Lightspark") end
    T.eq(ns.Sync.UserVersion("Xii Lightspark"), "")
    ns.UI.Show()
    ns.UI.SelectTab("members")
    local members = ns.UI.TabView("members")
    members.sort = "guildy"
    members:Refresh()
    ns.UI.SelectTab("professions")
    ns.UI.Show()
    local A = ns.UI.Action
    env.GuildMicroButton = env.CreateFrame("Button", "GuildMicroButton")
    T.eq(A.BlizzardWindow().click, env.GuildMicroButton)
    T.eq(A.Invite("Xii Lightspark").click, env.GuildMicroButton) -- Blizzard window not loaded yet
    local invite = env.CreateFrame("Button")
    invite.IsEnabled = function() return true end
    env.C_Club = { GetGuildClubId = function() return 7 end }
    env.CommunitiesFrame = { InviteButton = invite, GetSelectedClubId = function() return 7 end }
    T.eq(A.Invite("Xii Lightspark").click, invite)
    T.eq(ns.UI.InviteAction().click, invite)
    ns.UI.ShowOverlay(env.UIParent, A.BlizzardWindow())
    RunTimers()
    T.eq(errors, {})
  end)
end)

T.describe("Harvest", function()
  T.it("builds a queue of online, not yet read members", function()
    local now = 1700000000
    local members = {
      { key = "a", name = "A", online = true, guid = "G-A" },
      { key = "b", name = "B", online = false, guid = "G-B" },
      { key = "me", name = "Me", online = true, guid = "G-ME" },
    }
    local guild = { members = { a = { profs = { [171] = { ts = now - 10, recipes = { 1 } } } } },
      absent = { a = { [164] = now - 100 } } }
    local queue, total = ns.Harvest.BuildQueue(members, guild, now, function(m) return m.key == "me" end)
    T.eq(total, 1)
    T.eq(ns.Harvest.ServerId("Player-6949-0074341C"), "6949")
    local _, sameTotal, other = ns.Harvest.BuildQueue({
      { key = "x", name = "X", online = true, guid = "Player-6949-01" },
      { key = "y", name = "Y", online = true, guid = "Player-6945-02" },
    }, { members = {} }, now, function() return false end, "6949")
    T.eq(sameTotal, 1)
    T.eq(other, 1)
    T.eq(#queue, #ns.Harvest.ORDER - 2) -- alchemy is fresh, blacksmithing known absent
    for _, entry in ipairs(queue) do T.eq(entry.member.key, "a") end
  end)

  T.it("runs through online members and stops", function()
    local opened = {}
    env.SetItemRef = function(link) opened[#opened + 1] = link end
    ns.Harvest.Start()
    T.truthy(ns.Harvest.IsRunning(), "running")
    RunTimers(60)
    T.eq(ns.Harvest.IsRunning(), false)
    T.truthy(#opened > 0, "opened links")
    T.eq(ns.GuildData().absent["au tsch"], nil) -- no answer is not "absent"
    T.eq(ns.Harvest.log[1].result, "silent") -- first look unanswered: member skipped
    T.eq(#opened, 1)
    T.truthy(ns.GuildData().silent["au tsch"], "remembered as silent")
    ns.TradeSkill.Debug()
    env.SetItemRef = nil
    ns.UI.SelectTab("professions")
    T.eq(errors, {})
  end)
end)
T.describe("Hall of Fame", function()
  T.it("reads own and nearby statistics, merges shared ones and shows both views", function()
    env.GetStatisticsCategoryList = function() return { 128, 14821 } end
    env.GetCategoryNumAchievements = function(cat) return cat == 128 and 2 or 1 end
    env.GetStatistic = function(cat, i)
      if cat == 128 then return i == 1 and "1298" or "672 (Humanoid)", false, i == 1 and 107 or 1487 end
      return "2", false, 63570
    end
    env.GetAchievementInfo = function(id) return id, "Siege über Edwin van Cleef (Todesminen)" end
    env.GetCategoryInfo = function(id) return "Kategorie " .. id end
    ns.GameStats.UpdateOwn()
    local me = ns.GuildData().members[ns.Names.Key(ns.PlayerName())]
    T.eq(me.stats.v[107], 1298)
    T.eq(me.stats.v[63570], 2)

    -- a guild member in the target: comparison
    local set
    env.SetAchievementComparisonUnit = function(unit) set = unit return true end
    env.ClearAchievementComparisonUnit = function() end
    env.GetComparisonStatistic = function(id) return id == 107 and "1077" or "--" end
    env.UnitExists = function() return true end
    env.UnitIsPlayer = function() return true end
    env.UnitIsUnit = function() return false end
    env.UnitIsConnected = function() return true end
    env.UnitName = function(unit) if unit == "target" then return "Au", "Tsch" end return "Ran", "Fred" end
    env.UnitGUID = function() return "Player-1-03" end
    Fire("PLAYER_TARGET_CHANGED")
    T.eq(set, "target")
    Fire("INSPECT_ACHIEVEMENT_READY", "Player-1-03")
    RunTimers(1)
    T.eq(ns.GuildData().members["au tsch"].stats.v[107], 1077)
    T.eq(ns.GuildData().members["au tsch"].stats.src, "seen")

    local testing = ns.GameStats.TESTING
    ns.GameStats.TESTING = false
    -- mouseover: ignored while switched off, read when on, safeguard mark cleared after the answer
    set = nil
    env.UnitName = function(unit) if unit == "mouseover" then return "Makira", "Farron" end return "Au", "Tsch" end
    env.UnitGUID = function() return "Player-1-04" end
    env.GetTime = (function(t) return function() t = t + 20 return t end end)(10000)
    Fire("UPDATE_MOUSEOVER_UNIT")
    T.eq(set, nil)
    ns.GameStats.ToggleMouseover()
    Fire("UPDATE_MOUSEOVER_UNIT")
    T.eq(set, "mouseover")
    T.eq(env.GuildyDB.mouseoverProbe, "Makira Farron")
    Fire("INSPECT_ACHIEVEMENT_READY", "Player-1-04")
    RunTimers(1)
    T.eq(env.GuildyDB.mouseoverProbe, nil)
    T.eq(ns.GuildData().members["makira farron"].stats.v[107], 1077)
    -- an answer that arrives in parts: the second read completes it
    ns.GuildData().members["au tsch"].stats = nil
    env.UnitName = function() return "Au", "Tsch" end
    env.UnitGUID = function() return "Player-1-03" end
    local reads = 0
    env.GetComparisonStatistic = function(id)
      if id == 107 then return reads > 0 and "500" or "--" end
      return id == 98 and "12" or "--"
    end
    set = nil
    Fire("PLAYER_TARGET_CHANGED")
    T.eq(set, "target")
    Fire("INSPECT_ACHIEVEMENT_READY", "Player-1-03")
    reads = 1
    RunTimers(1)
    T.eq(ns.GuildData().members["au tsch"].stats.v[107], 500)
    -- level 21 without creature kills: incomplete, not stored
    ns.GuildData().members["au tsch"].stats = nil
    ns.GameStats._ResetForTest()
    env.GetComparisonStatistic = function(id) return id == 98 and "12" or "--" end
    Fire("PLAYER_TARGET_CHANGED")
    Fire("INSPECT_ACHIEVEMENT_READY", "Player-1-03")
    RunTimers(1)
    T.eq(ns.GuildData().members["au tsch"].stats, nil)
    -- a mark left from the last session switches mouseover off again
    env.GuildyDB.mouseoverProbe = "Makira Farron"
    ns.GameStats.Start()
    T.eq(env.GuildyDB.settings.statMouseover, false)
    T.eq(env.GuildyDB.mouseoverProbe, nil)
    ns.GameStats.TESTING = testing

    -- a Guildy user shares their own statistics
    local P = ns.Protocol
    local payload = P.Encode("STAT", { m = "Makira Farron", s = { ts = 1800000000, src = "self", v = { ["107"] = 4210 } } })
    for _, part in ipairs(P.Chunk("s1", payload)) do Fire("CHAT_MSG_ADDON", "GUILDY", part, "GUILD", "Makira-Farron") end
    T.eq(ns.GuildData().members["makira farron"].stats.v[107], 4210)

    env.SlashCmdList.GUILDY("statshow Makira Farron")
    env.SlashCmdList.GUILDY("statshow Niemand")
    ns.UI.Show()
    ns.UI.SelectTab("fame")
    local view = ns.UI.TabView("fame")
    T.truthy(view, "fame view built")
    for _, period in ipairs({ "all", "month", "last" }) do
      view.period = period
      view:Refresh()
      view:ShowDetail(107)
      view:ShowDetail("bosses")
      view:ShowHome()
    end
    RunTimers()
    T.eq(errors, {})
  end)
end)
