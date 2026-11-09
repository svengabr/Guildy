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
env.GetCursorPosition = function() return 100, 100 end
env.IsMouseButtonDown = function() return false end
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
env.UnitClass = function() return "Magier", "MAGE" end
env.UnitLevel = function() return 33 end
env.UnitRace = function() return "Gnom", "Gnome" end
env.UnitSex = function() return 3 end
env.InCombatLockdown = function() return false end
env.IsShiftKeyDown = function() return false end
env.IsControlKeyDown = function() return false end
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
      GetRecipeInfo = function(id) return { learned = id ~= 13, icon = 5000 + id } end,
      GetBaseProfessionInfo = function() return { professionID = 171, professionName = "Alchimie", skillLevel = 99, maxSkillLevel = 150 } end,
      IsTradeSkillLinked = function() return linked, "Au-Tsch" end,
    }
    ns.TradeSkill.ScanOpen()
    T.eq(guild.members["au tsch"].profs[171].recipes, { 11, 12 })
    T.eq(guild.members["au tsch"].profs[171].src, "link")
    T.eq(ns.TradeSkill.RecipeIcon(11), 5011) -- the made item's icon, remembered from the open book
    T.eq(ns.TradeSkill.RecipeIcon(99), nil)
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
    -- families: a Guildy user shares their characters in the guild
    local fam = P.Encode("FAM", { m = "Makira Farron", f = { ts = 1800000000, c = { "Makira Farron", "Au Tsch" } } })
    for _, part in ipairs(P.Chunk("f1", fam)) do Fire("CHAT_MSG_ADDON", "GUILDY", part, "GUILD", "Makira-Farron") end
    T.eq(ns.GuildData().families["makira farron"].chars, { "Makira Farron", "Au Tsch" })
    local makira = ns.Roster.Find("Makira Farron")
    T.truthy(makira, "Makira in the roster")
    T.eq(#ns.Family.Of(makira.key, ns.Roster.Members(), ns.GuildData().families, {}), 1)
    ns.UI.ShowMember(makira) -- the character page with a family card
    ns.UI.Hide()
    ns.UI.Show() -- comes back to the page within the session
    ns.UI.SelectTab("chat")
    -- members tab: twinks under their main, folded, without note, by group and item level
    ns.UI.SelectTab("members")
    local mv = ns.UI.TabView("members")
    for _, setup in ipairs({ { noNote = true }, { noOfficerNote = true }, { fold = true, sort = "group" }, { sort = "ilvl" }, { sort = "level" } }) do
      mv.noNote, mv.noOfficerNote, mv.fold = setup.noNote, setup.noOfficerNote, setup.fold
      mv.sort = setup.sort or "level"
      mv:Refresh()
    end
    ns.UI.SelectTab("chat")
    ns.UI.Show()
    ns.UI.SelectTab("members")
    local members = ns.UI.TabView("members")
    members.sort = "guildy"
    members:Refresh()
    ns.UI.SelectTab("professions")
    -- rail, members with filters, recipe book and the search results
    local profs = ns.UI.TabView("professions")
    T.eq(profs.skill, 171)
    T.eq(profs.memberKey, "au tsch") -- first member with recipes (online, highest skill) fills the book
    for _, filter in ipairs({ "online", "book", "all" }) do
      profs.filter = filter
      profs:Refresh()
    end
    profs.recipeQuery = "rezept 1"
    profs:RenderBook()
    profs.query = "rezept"
    profs:Refresh()
    profs.query = ""
    profs:Refresh()
    ns.UI.Hide()
    ns.UI.Show()
    T.eq(ns.UI.Current(), "professions") -- opening comes back to the last tab
    T.eq(ns.Settings().lastTab, nil) -- only within the session: a login or reload starts on chat
    T.eq(ns.Store.Init({ settings = { lastTab = "fame", famePage = "pvp" } }).settings.lastTab, nil)
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

  T.it("reads the whole club history and asks for older messages at the top", function()
    local saved, requested = env.C_Club, nil
    local function Id(n) return { epoch = (1800000000 + n) * 1000000, position = n } end
    local messages = {}
    for n = 1, 400 do
      messages[n] = { messageId = Id(n), content = "line " .. n, author = { name = "Au-Tsch", classID = 2 } }
    end
    env.C_Club = {
      GetGuildClubId = function() return 7 end,
      GetStreams = function() return { { streamId = 1, streamType = 1 } } end,
      -- newest range first, an old cached piece after it (the order seen in a real guild)
      GetMessageRanges = function()
        return { { oldestMessageId = Id(1), newestMessageId = Id(400) }, { oldestMessageId = Id(-50), newestMessageId = Id(-40) } }
      end,
      GetMessagesInRange = function(_, _, oldest) return oldest.position == 1 and messages or {} end,
      IsBeginningOfStream = function() return false end,
      RequestMoreMessagesBefore = function(_, _, before, count) requested = { before = before, count = count } end,
    }
    local lines = ns.Chat.History("guild")
    T.truthy(#lines >= 400, "all messages of the range")
    T.eq(lines[#lines].ts, 1800000400)
    T.truthy(ns.Chat.LoadOlder("guild"))
    T.eq(requested.before.position, 1)
    requested = nil
    ns.Chat.LoadOlder("guild")
    T.eq(requested, nil) -- one request at a time
    ns.Chat.OnHistoryReceived()
    env.C_Club.IsBeginningOfStream = function() return true end
    T.eq(ns.Chat.LoadOlder("guild"), false)
    -- "new since your last login": a reload keeps the mark of the session before
    local Chat = ns.Chat
    T.eq(Chat.InitSeen({}, 5000), nil)
    T.eq(Chat.InitSeen({ lastLogout = 1000, seenMark = 400 }, 5000), 1000)
    T.eq(Chat.InitSeen({ lastLogout = 4900, seenMark = 1000 }, 5000), 1000)
    local settings = {}
    Chat.OnLogout(settings, 1800000300)
    T.eq(Chat.InitSeen(settings, 1800009000), 1800000300)
    ns.UI.Show()
    ns.UI.SelectTab("chat")
    ns.UI.TabView("chat"):RenderChat() -- line 300 of 400 is the last seen one
    T.eq(Chat.HistoryState("guild"), "start")
    -- character page, member menu with ranks, back to the tab
    local member = ns.Roster.Members()[1]
    T.truthy(member, "a roster member")
    ns.UI.ShowMember(member)
    T.truthy(ns.UI.MemberPage(), "page built")
    ns.UI.MemberPage():Render()
    -- the account's characters in other guilds (account tab) and the page of one of them
    local db = ns.DB()
    db.ownChars = db.ownChars or {}
    db.ownChars[member.key] = db.ownChars[member.key] or true
    db.ownChars["drache"] = { name = "Drache", classFile = "WARLOCK", level = 3, raceFile = "Human", guild = "Katzen",
      guildKey = "Katzen@Forever", seen = 0 }
    db.guilds["Katzen@Forever"] = { members = { drache = { stats = {}, profs = {} } } }
    ns.UI.MemberPage():Render()
    -- and the page of that character, from its own guild's data
    local elsewhere = ns.Family.OwnElsewhere(db.ownChars, { [member.key] = true }, 3600)
    T.eq(elsewhere[1] and elsewhere[1].name, "Drache")
    ns.UI.ShowMember(elsewhere[1], true)
    T.eq(ns.UI.MemberPage().member.name, "Drache")
    ns.UI.ShowMember(member, true) -- an own character in this guild, seen from the account
    ns.UI.ShowMember(member)
    ns.UI.MemberMenu(member)
    ns.UI.CopyText(member.name)
    ns.UI.ConfirmRemove(member)
    -- one rank per click: the next rank up or down, never onto the player's own rank or below the lowest
    local low = { name = "Neu", rankIndex = 2 }
    T.eq(ns.Roster.NextRank(low, "promote"), nil)
    T.eq(ns.Roster.NextRank(low, "demote"), nil)
    local myInfo = env.GetGuildInfo
    env.GetGuildInfo = function() return "Murloc Mafia", "GM", 0 end
    T.eq(ns.Roster.NextRank(low, "promote"), "Offizier")
    T.eq(ns.Roster.NextRank({ name = "Neu", rankIndex = 1 }, "demote"), "Haifutter")
    env.GetGuildInfo = myInfo
    -- rank ladder: opens beside the button, follows the page, closes for another member
    local anchor = env.CreateFrame("Button")
    ns.UI.RankLadder.Toggle(anchor, member)
    T.truthy(env.GuildyRankLadder, "ladder built")
    ns.UI.RankLadder.Sync(member)
    ns.UI.RankLadder.Toggle(anchor, member) -- second click closes
    ns.UI.RankLadder.Hide()
    ns.UI.SelectTab("members")
    ns.UI.SelectTab("chat")
    -- account tab in the guild, then without a guild: only the account tab, back to chat on joining
    ns.UI.SelectTab("account")
    T.eq(ns.UI.Current(), "account")
    ns.UI.SelectTab("chat")
    env.IsInGuild = function() return false end
    ns.Fire("GUILD")
    T.eq(ns.UI.Current(), "account")
    ns.UI.SelectTab("members")
    T.eq(ns.UI.Current(), "account")
    ns.UI.Hide()
    ns.UI.Show()
    T.eq(ns.UI.Current(), "account")
    env.IsInGuild = function() return true end
    ns.Fire("GUILD")
    T.eq(ns.UI.Current(), "chat")
    Chat.InitSeen({}, 0)
    env.C_Club = saved
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
    -- order: members in the player's zone first, then those with the player's server id, then the rest;
    -- nobody is left out for their server id beforehand (it changes with the zone)
    local shards = {
      { key = "y", name = "Y", online = true, guid = "Player-6945-02", zone = "Dun Morogh" },
      { key = "x", name = "X", online = true, guid = "Player-6949-01", zone = "Dun Morogh" },
      { key = "z", name = "Z", online = true, guid = "Player-6950-03", zone = "Ironforge" },
    }
    local shardQueue, shardTotal = ns.Harvest.BuildQueue(shards, { members = {} }, now, function() return false end,
      "6949", nil, "Ironforge")
    T.eq(shardTotal, 3)
    -- own server id in the zone, own id elsewhere, other ids in the zone, the rest
    T.eq(shardQueue[1].member.key, "x")
    T.eq(shardQueue[#shardQueue].member.key, "y")
    local zoned = ns.Harvest.BuildQueue(shards, { members = {} }, now, function() return false end, "6949", nil, "Dun Morogh")
    T.eq(zoned[1].member.key, "x")
    T.eq(zoned[#zoned].member.key, "z")
    -- A is known to have alchemy (fresh): only primary professions besides it are tried, a second one may
    -- be missing; no secondary ones, and blacksmithing is known absent
    local primaries = 0
    for _, skillLine in ipairs(ns.Harvest.ORDER) do if ns.Professions.PRIMARY[skillLine] then primaries = primaries + 1 end end
    T.eq(#queue, primaries - 2)
    -- members who run Guildy share their recipes themselves: not read, only counted
    local _, userTotal, users = ns.Harvest.BuildQueue(members, guild, now, function(m) return m.key == "me" end, nil,
      function(m) return m.key == "a" end)
    T.eq(userTotal, 0)
    T.eq(users, 1)
    -- after /guildy scanreset fresh data counts as old: alchemy is read again
    guild.scanResetAt = now
    local again = ns.Harvest.BuildQueue(members, guild, now, function(m) return m.key == "me" end)
    T.eq(#again, primaries - 1)
    -- two known primary professions: only the known ones are read
    local two = { members = { a = { profs = { [171] = { rank = 100 }, [182] = { rank = 50 }, [185] = { src = "note" } } } } }
    local twoQueue = ns.Harvest.BuildQueue(members, two, now, function(m) return m.key == "me" end)
    T.eq(#twoQueue, 2) -- alchemy and cooking (herbalism has no book)
    T.eq(twoQueue[1].skillLine, 171)
    for _, entry in ipairs(queue) do T.eq(entry.member.key, "a") end
  end)

  T.it("runs through online members and stops", function()
    local opened = {}
    env.SetItemRef = function(link) opened[#opened + 1] = link end
    T.truthy(ns.Harvest.IsGuildyUser(ns.Roster.Find("Au Tsch")), "Au Tsch sent Guildy data earlier")
    local isUser = ns.Harvest.IsGuildyUser
    ns.Harvest.IsGuildyUser = function() return false end -- read Au Tsch anyway for this test
    ns.Harvest.log = { { result = "found", member = "Old" } }
    -- Guildy knows nothing about Au Tsch's professions here: every book profession is tried
    local auProfs = ns.GuildData().members["au tsch"].profs
    ns.GuildData().members["au tsch"].profs = {}
    -- sound effects are off while reading and come back afterwards
    local cvars = { Sound_EnableSFX = "1" }
    env.GetCVar = function(name) return cvars[name] end
    env.SetCVar = function(name, value) cvars[name] = value end
    ns.Harvest.Start()
    T.eq(cvars.Sound_EnableSFX, "0")
    T.eq(#ns.Harvest.log, 0) -- a new run starts with an empty log
    ns.Harvest.IsGuildyUser = isUser
    T.truthy(ns.Harvest.IsRunning(), "running")
    ns.UI.Show()
    ns.UI.SelectTab("professions") -- status column with progress bar while running
    -- in combat the run pauses and the status column says so; afterwards it goes on
    env.InCombatLockdown = function() return true end
    RunTimers(2)
    T.truthy(ns.Harvest.IsRunning(), "still running in combat")
    T.truthy(ns.Harvest.InCombatPause(), "paused in combat")
    env.InCombatLockdown = function() return false end
    RunTimers(60)
    T.eq(ns.Harvest.IsRunning(), false)
    T.eq(cvars.Sound_EnableSFX, "1")
    T.eq(env.GuildyDB.harvestSfx, nil)
    -- cut off by a reload: given back at the next login
    env.GuildyDB.harvestSfx = "1"
    cvars.Sound_EnableSFX = "0"
    ns.Harvest.RestoreSound()
    T.eq(cvars.Sound_EnableSFX, "1")
    env.GetCVar, env.SetCVar = nil, nil
    ns.GuildData().members["au tsch"].profs = auProfs
    T.truthy(#opened > 0, "opened links")
    T.eq(ns.GuildData().absent["au tsch"], nil) -- no answer is not "absent"
    -- the run's first look got no answer: tried once more, then the member is skipped
    T.eq(ns.Harvest.log[2].result, "retry")
    T.eq(ns.Harvest.log[1].result, "silent")
    T.eq(#opened, 2)
    T.eq(opened[1], opened[2])
    -- no book was read in this run: the silence may be the server slowing down, so it is not remembered
    T.eq((ns.GuildData().silent or {})["au tsch"], nil)
    ns.GuildData().silent = { ["au tsch"] = ns.Now() }
    env.SlashCmdList.GUILDY("scanreset")
    T.eq(ns.GuildData().silent["au tsch"], nil)
    ns.TradeSkill.Debug()
    env.SetItemRef = nil
    ns.UI.SelectTab("professions")
    -- after the run the results can be closed: the recipe book comes back
    local profView = ns.UI.TabView("professions")
    T.truthy(profView.Status:IsShown(), "results shown after the run")
    profView.Status.Close:GetScript("OnClick")()
    T.eq(profView.Status:IsShown(), false)
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
    env.GetInventoryItemLink = function(_, slot) if slot == 1 or slot == 16 then return "item" .. slot end end
    env.GetItemInfo = function(link) return "Item", link, link == "item16" and 4 or 2, link == "item16" and 40 or 30 end
    ns.GameStats.UpdateOwn()
    local me = ns.GuildData().members[ns.Names.Key(ns.PlayerName())]
    T.eq(me.stats.v[107], 1298)
    T.eq(me.stats.v[ns.Stats.GEAR.ILVL], 350)
    T.eq(me.stats.v[ns.Stats.GEAR.EPIC], 1)
    ns.GameStats.OnEquipmentChanged()
    -- only C_Item.GetItemInfo, item info not loaded at first: the last equipment stays, a retry reads it
    local getItemInfo, loaded, requested = env.GetItemInfo, false, 0
    env.GetItemInfo = nil
    env.GetInventoryItemID = function(_, slot) if slot == 1 or slot == 16 then return slot end end
    env.C_Item = { GetItemInfo = function(link) if loaded then return getItemInfo(link) end end,
      RequestLoadItemDataByID = function() requested = requested + 1 end }
    env.GetInventoryItemLink = function(_, slot) if slot == 1 or slot == 16 then return "item16" end end
    ns.GameStats.UpdateOwn()
    T.eq(me.stats.v[ns.Stats.GEAR.ILVL], 350)
    T.eq(requested, 2)
    loaded = true
    local serverTime = env.GetServerTime
    env.GetServerTime = function() return 1700000100 end
    RunTimers()
    env.GetServerTime = serverTime
    T.eq(me.stats.v[ns.Stats.GEAR.ILVL], 400)
    env.GetItemInfo, env.C_Item = getItemInfo, nil
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

    -- with inspect: the equipment is read right after the statistics and stored with them
    local inspected, cleared
    env.NotifyInspect = function(unit) inspected = unit end
    env.ClearInspectPlayer = function() cleared = true end
    local ownLink = env.GetInventoryItemLink
    env.GetInventoryItemLink = function(unit, slot)
      if unit == "target" and (slot == 1 or slot == 16) then return "item16" end
      return ownLink(unit, slot)
    end
    ns.GuildData().members["au tsch"].stats = nil
    ns.GameStats._ResetForTest()
    Fire("PLAYER_TARGET_CHANGED")
    T.eq(inspected, "target") -- the inspect goes out with the request
    Fire("INSPECT_ACHIEVEMENT_READY", "Player-1-03")
    RunTimers(1)
    T.eq(ns.GuildData().members["au tsch"].stats, nil) -- waits for the equipment
    Fire("INSPECT_READY", "Player-1-03")
    RunTimers(1)
    T.eq(ns.GuildData().members["au tsch"].stats.v[107], 1077)
    T.eq(ns.GuildData().members["au tsch"].stats.v[ns.Stats.GEAR.ILVL], 400)
    T.truthy(cleared)
    -- the links arrive slot by slot: Guildy waits until they stop growing
    ns.GuildData().members["au tsch"].stats = nil
    ns.GameStats._ResetForTest()
    local arrived = 1
    env.GetInventoryItemLink = function(unit, slot)
      if unit == "target" and (slot == 1 or (slot == 16 and arrived > 1)) then return "item16" end
      return ownLink(unit, slot)
    end
    Fire("PLAYER_TARGET_CHANGED")
    Fire("INSPECT_ACHIEVEMENT_READY", "Player-1-03")
    RunTimers(1)
    Fire("INSPECT_READY", "Player-1-03")
    T.eq(ns.GuildData().members["au tsch"].stats, nil)
    arrived = 2
    RunTimers(3)
    T.eq(ns.GuildData().members["au tsch"].stats.v[ns.Stats.GEAR.EPIC], 2)
    env.GetInventoryItemLink = function(unit, slot)
      if unit == "target" and (slot == 1 or slot == 16) then return "item16" end
      return ownLink(unit, slot)
    end
    -- no inspect answer: the statistics are stored alone after the wait
    ns.GuildData().members["au tsch"].stats = nil
    ns.GameStats._ResetForTest()
    Fire("PLAYER_TARGET_CHANGED")
    Fire("INSPECT_ACHIEVEMENT_READY", "Player-1-03")
    RunTimers(1)
    RunTimers(1)
    T.eq(ns.GuildData().members["au tsch"].stats.v[107], 1077)
    T.eq(ns.GuildData().members["au tsch"].stats.v[ns.Stats.GEAR.ILVL], nil)
    -- the target is gone when the equipment arrives, a nameplate still shows the member
    ns.GuildData().members["au tsch"].stats = nil
    ns.GameStats._ResetForTest()
    Fire("PLAYER_TARGET_CHANGED")
    Fire("INSPECT_ACHIEVEMENT_READY", "Player-1-03")
    RunTimers(1)
    local guidOf = env.UnitGUID
    env.UnitGUID = function(unit) if unit == "nameplate7" then return "Player-1-03" end end
    env.GetInventoryItemLink = function(unit, slot)
      if unit == "nameplate7" and (slot == 1 or slot == 16) then return "item16" end
      return ownLink(unit, slot)
    end
    Fire("INSPECT_READY", "Player-1-03")
    RunTimers(1)
    T.eq(ns.GuildData().members["au tsch"].stats.v[ns.Stats.GEAR.ILVL], 400)
    env.UnitGUID = guidOf
    -- nobody shows the member when the equipment arrives: kept and read on the next look
    ns.GuildData().members["au tsch"].stats = nil
    ns.GameStats._ResetForTest()
    env.GetInventoryItemLink = function(unit, slot)
      if unit == "target" and (slot == 1 or slot == 16) then return "item16" end
      return ownLink(unit, slot)
    end
    Fire("PLAYER_TARGET_CHANGED")
    Fire("INSPECT_ACHIEVEMENT_READY", "Player-1-03")
    RunTimers(1)
    env.UnitGUID = function() return nil end
    Fire("INSPECT_READY", "Player-1-03")
    RunTimers(8)
    T.eq(ns.GuildData().members["au tsch"].stats.v[107], 1077)
    T.eq(ns.GuildData().members["au tsch"].stats.v[ns.Stats.GEAR.ILVL], nil)
    env.UnitGUID = guidOf
    Fire("PLAYER_TARGET_CHANGED")
    T.eq(ns.GuildData().members["au tsch"].stats.v[ns.Stats.GEAR.ILVL], 400)
    -- Blizzard's achievement frame does not get the comparison event while Guildy asks
    local events = { INSPECT_ACHIEVEMENT_READY = true }
    env.AchievementFrameComparison = {
      IsEventRegistered = function(_, e) return events[e] == true end,
      UnregisterEvent = function(_, e) events[e] = nil end,
      RegisterEvent = function(_, e) events[e] = true end,
    }
    ns.GuildData().members["au tsch"].stats = nil
    ns.GameStats._ResetForTest()
    Fire("PLAYER_TARGET_CHANGED")
    T.eq(events.INSPECT_ACHIEVEMENT_READY, nil)
    Fire("INSPECT_ACHIEVEMENT_READY", "Player-1-03")
    RunTimers(1)
    T.eq(events.INSPECT_ACHIEVEMENT_READY, true)
    Fire("INSPECT_READY", "Player-1-03")
    RunTimers(1)
    env.AchievementFrameComparison = nil
    -- statreset: a member read a moment ago is asked again right away
    set = nil
    Fire("PLAYER_TARGET_CHANGED")
    T.eq(set, nil)
    env.SlashCmdList.GUILDY("statreset")
    Fire("PLAYER_TARGET_CHANGED")
    T.eq(set, "target")
    Fire("INSPECT_ACHIEVEMENT_READY", "Player-1-03")
    RunTimers(1)
    Fire("INSPECT_READY", "Player-1-03")
    RunTimers(1)
    env.NotifyInspect, env.ClearInspectPlayer, env.GetInventoryItemLink = nil, nil, ownLink

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
    env.SlashCmdList.GUILDY("statshow")
    ns.UI.Show()
    ns.UI.SelectTab("fame")
    local view = ns.UI.TabView("fame")
    T.truthy(view, "fame view built")
    -- PvP page: a member with honorable kills and duels gets a row (honorable kills, duels won : lost)
    local pvp = P.Encode("STAT", { m = "Makira Farron", s = { ts = 1800000100, src = "self",
      v = { ["107"] = 4210, ["588"] = 41, ["319"] = 14, ["320"] = 13, ["839"] = 5 } } })
    for _, part in ipairs(P.Chunk("s2", pvp)) do Fire("CHAT_MSG_ADDON", "GUILDY", part, "GUILD", "Makira-Farron") end
    view.page, view.period = "pvp", "all"
    view:ShowHome()
    T.truthy(view.Pvp:IsShown(), "PvP table shown on the PvP page")
    T.truthy(view.Pvp.List.rows[1] and view.Pvp.List.rows[1]:IsShown(), "PvP row for Makira")
    T.eq(view.Pvp.List.rows[1].Cols.duels:GetText(), "14 : 13")
    T.eq(view.Pvp.List.rows[1].Cols.rate:GetText(), "52 %")
    for _, page in ipairs(ns.Stats.PAGES) do
      view.page = page.key
      for _, period in ipairs({ "all", "month", "last" }) do
        view.period = period
        view:Refresh()
        view:ShowDetail(107)
        view:ShowDetail("bosses")
        view:ShowDetail(ns.Stats.GEAR.ILVL)
        view:ShowDetail("spent")
        view:ShowHome()
      end
    end
    RunTimers()
    T.eq(errors, {})
  end)
end)
