-- Load smoke test: loads every TOC file in order against permissive WoW stubs (any frame method
-- exists), fires the startup events, opens the window and every tab, and fails on any Lua error,
-- including errors reported through geterrorhandler (ns.SafeCall).
local T = ...

local world = dofile(T.testsDir .. "/wow.lua")(T)
local env, ns, errors = world.env, world.ns, world.errors
local Fire, RunTimers, SECRET = world.Fire, world.RunTimers, world.SECRET

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
    T.eq(ns.GuildData().members["makira farron"].profs, {}) -- note "Heiler" mentions no profession
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
    env.CommunitiesFrame:Show() -- J opens Blizzard's guild window
    T.truthy(ns.UI.IsShown(), "Guildy shows inside Blizzard's guild window")
    T.eq(ns.UI.Current(), "chat")
    for _, key in ipairs({ "members", "overview", "fame", "professions", "info", "ranks", "chat" }) do
      ns.UI.SelectTab(key)
      T.eq(ns.UI.Current(), key)
    end
    ns.UI.FilterMembers({ classFile = "PALADIN" })
    T.eq(errors, {})
  end)

  T.it("fetches older chat lines when the player scrolls to the top, not on every render", function()
    local fetched = 0
    local box = env.CreateFrame("Frame")
    local pane = ns.UI.ChatPane(box, { onTop = function() fetched = fetched + 1 end })
    -- the client tells the timeline about every scroll change, also the one from emptying the frame
    local onScroll
    pane.Messages.SetOnScrollChangedCallback = function(_, fn) onScroll = fn end
    pane.Messages.Clear = function() if onScroll then onScroll() end end
    pane.Timeline = ns.ChatTimeline.Create(box, pane.Messages, { onTop = function() fetched = fetched + 1 end,
      label = tostring, short = tostring, latestText = tostring, statusText = {} })
    local lines = {}
    for i = 1, 50 do lines[i] = { sender = "Au Tsch", text = "hi " .. i, ts = 1700000000 + i } end
    pane:Render(lines, 1, 1, 1)
    pane:Render(lines, 1, 1, 1)
    T.eq(fetched, 0) -- more lines than fit: rendering alone fetches nothing
    pane.Timeline:Update() -- the player scrolled, and the view is at the top
    T.eq(fetched, 1)
    pane:Render({ lines[1], lines[2] }, 1, 1, 1)
    T.eq(fetched, 2) -- everything fits: fill the view
    T.eq(errors, {})
  end)

  T.it("shows the newest chat lines and more of them at the top", function()
    local before, beforeEnum = env.C_Club, env.Enum
    local messages, asked = {}, {}
    for i = 1, 250 do
      messages[i] = { messageId = { epoch = (1700000000 + i) * 1000000, position = i }, content = "line " .. i,
        author = { name = "Au-Tsch" } }
    end
    env.Enum = { ClubStreamType = { Guild = 1, Officer = 2 } }
    env.C_Club = {
      GetGuildClubId = function() return 7 end,
      GetStreams = function() return { { streamType = 1, streamId = 70 } } end,
      GetMessageRanges = function()
        return { { oldestMessageId = messages[1].messageId, newestMessageId = messages[#messages].messageId } }
      end,
      GetMessagesInRange = function(_, _, oldest, newest)
        asked[#asked + 1] = newest.position - oldest.position + 1
        local part = {}
        for i = oldest.position, newest.position do part[#part + 1] = messages[i] end
        return part
      end,
    }
    local Chat = ns.Chat
    local lines, more = Chat.History("officer", Chat.WINDOW)
    T.eq(#lines, 0) -- no officer stream
    lines, more = Chat.History("guild", Chat.WINDOW)
    T.eq({ #lines, lines[1].text, lines[#lines].text, more }, { 100, "line 151", "line 250", true })
    T.eq(asked, { 250 }) -- the first read looks at everything loaded
    -- a new line: only the window is asked for
    messages[251] = { messageId = { epoch = 1700000251 * 1000000, position = 251 }, content = "line 251",
      author = { name = "Ran-Fred" } }
    lines, more = Chat.History("guild", Chat.WINDOW)
    T.eq({ #lines, lines[1].text, lines[#lines].text, more }, { 101, "line 151", "line 251", true })
    T.eq(asked, { 250, 101 })
    -- the chat tab: scrolled to the top it shows a block more, then everything there is
    env.CommunitiesFrame:Show()
    ns.UI.SelectTab("chat")
    local view = ns.UI.TabView("chat")
    T.eq({ view.limit, view.more }, { 100, true })
    view.Timeline:Update() -- the player scrolled (the stub frame is always at its top)
    T.eq({ view.limit, view.more }, { 200, true })
    view.Timeline:Update()
    T.eq({ view.limit, view.more }, { 300, false })
    T.eq(#Chat.History("guild", view.limit), 251)
    -- a client that hands over the newest messages on their own is not asked for everything
    local reads = #asked
    env.C_Club.GetMessagesBefore = function(_, _, newest, count)
      local part = {}
      for i = math.max(1, newest.position - count + 1), newest.position do part[#part + 1] = messages[i] end
      return part
    end
    lines, more = Chat.History("guild", 150)
    T.eq({ #lines, lines[1].text, lines[#lines].text, more }, { 150, "line 102", "line 251", true })
    T.eq(#asked, reads)
    lines, more = Chat.History("guild", 400) -- more than there is: all of it
    T.eq({ #lines, more }, { 251, false })
    T.eq(#asked, reads)
    -- an answer that is not what was asked for (here: newest first) is not used
    env.C_Club.GetMessagesBefore = function() return { messages[251], messages[250] } end
    T.eq(#Chat.History("guild", 2), 2)
    T.eq(#asked, reads + 1)
    env.C_Club.GetMessagesBefore = nil
    -- without a limit (communities): everything, as before
    T.eq(#Chat.StreamLines(7, 70, "guild"), 251)
    ns.UI.SelectTab("members")
    ns.UI.SelectTab("chat")
    T.eq(view.limit, 100) -- opened again: the newest lines
    env.C_Club, env.Enum = before, beforeEnum
    ns.UI.SelectTab("chat")
    T.eq(errors, {})
  end)

  T.it("never leaves the chat scrolled above its first line", function()
    local pane = ns.UI.ChatPane(env.CreateFrame("Frame"), {})
    local frame = pane.Messages
    local offset, atBottom = 0, 0
    frame.GetScrollOffset = function() return offset end
    frame.SetScrollOffset = function(_, value) offset = value end
    frame.ScrollToBottom = function() offset, atBottom = 0, atBottom + 1 end
    frame.GetNumVisibleLines = function() return 30 end
    local lines = {}
    for i = 1, 300 do lines[i] = { sender = "Au Tsch", text = "hi " .. i, ts = env.GetServerTime() - 400 + i } end
    pane:Render(lines, 1, 1, 1)
    offset = 250 -- the player scrolled far up
    pane:Render(lines, 1, 1, 1)
    T.eq(offset, 250) -- the reading position stays
    local newest = {}
    for i = 1, 100 do newest[i] = lines[200 + i] end
    pane:Render(newest, 1, 1, 1) -- far fewer lines now
    T.eq(offset, 71) -- 100 lines and a day line, a full view of 30 at the top
    pane:Render({ lines[1], lines[2] }, 1, 1, 1) -- everything fits
    T.eq(offset, 0)
    T.eq(errors, {})
  end)

  T.it("walks through every view for the reference screenshots", function()
    local taken = 0
    env.Screenshot = function() taken = taken + 1 end
    env.CommunitiesFrame:Show()
    ns.UI.SelectTab("overview")
    env.SlashCmdList.GUILDY("shots")
    RunTimers(1)
    T.eq(taken, #ns.UI.SHOTS)
    T.eq(ns.UI.fromTimer, nil)
    T.truthy(taken >= 19, "every tab, page and options tab")
    T.eq(ns.UI.Current(), "overview") -- back where it started
    T.eq(ns.UI.Options():IsShown(), false)
    env.Screenshot = nil
    env.SlashCmdList.GUILDY("shots backdrop") -- the plain sheet alone, on and off again
    env.SlashCmdList.GUILDY("shots backdrop")
    ns.UI.SelectTab("chat")
    T.eq(errors, {})
  end)

  T.it("shows every chosen title card, also one nobody holds yet", function()
    env.CommunitiesFrame:Show()
    ns.UI.SelectTab("fame")
    local view = ns.UI.TabView("fame")
    for _, page in ipairs(ns.Stats.PAGES) do
      view.page, view.mode = page.key, "home"
      view:Refresh()
      local chosen = ns.Settings().fameCards
      local titles = ns.Stats.Titles(page, type(chosen) == "table" and chosen[page.key] or nil)
      local shown = 0
      for _, card in ipairs(view.Cards) do if card:IsShown() then shown = shown + 1 end end
      T.eq(shown, math.min(#titles, #view.Cards), page.key)
    end
    view.page = ns.Stats.PAGES[1].key
    ns.UI.SelectTab("chat")
    T.eq(errors, {})
  end)

  T.it("marks the communities tab while a community has something new", function()
    local before, beforeUtil = env.C_Club, env.CommunitiesUtil
    local blizzardUnread = { [41] = true }
    env.C_Club = setmetatable({
      GetGuildClubId = function() return 7 end,
      GetSubscribedClubs = function() return { { clubId = 40, name = "Angler", clubType = 1 }, { clubId = 41, name = "Bastler", clubType = 1 } } end,
      FocusStream = function() return true end,
    }, { __index = function() return function() end end })
    env.CommunitiesUtil = { DoesCommunityHaveUnreadMessages = function(clubId) return blizzardUnread[clubId] or false end }
    local C = ns.Communities
    env.CommunitiesFrame:Show()
    ns.UI.SelectTab("chat")
    local dot = ns.UI.frame.CommunitiesTab.Dot
    -- 41 was unread at the login (Blizzard's mark), 40 gets a line now
    T.eq({ C.HasUnread(40), C.HasUnread(41), C.AnyUnread() }, { false, true, true })
    ns.UI.UpdateUnread()
    T.eq(dot:IsShown(), true)
    C.Focus(41, 1) -- shown in Guildy: read, whatever Blizzard's mark still says
    T.eq({ C.HasUnread(41), C.AnyUnread() }, { false, false })
    ns.UI.UpdateUnread()
    T.eq(dot:IsShown(), false)
    Fire("CLUB_MESSAGE_ADDED", 40, 1)
    T.eq({ C.Unread(40), C.HasUnread(40), dot:IsShown() }, { 1, true, true })
    C.Focus(40, 1)
    T.eq(C.AnyUnread(), false)
    C.Focus(nil)
    env.C_Club, env.CommunitiesUtil = before, beforeUtil
    T.eq(errors, {})
  end)

  T.it("measures its own work with /guildy perf", function()
    local slash = env.SlashCmdList.GUILDY
    slash("perf") -- off: only says how to switch it on
    T.eq(env.GuildyDB.perfReport, nil)
    slash("perf on")
    T.eq(env.GuildyDB.settings.perf, true)
    ns.UI.SelectTab("members")
    ns.Fire("ROSTER")
    slash("perf")
    local report = table.concat(env.GuildyDB.perfReport, " / ")
    T.truthy(report:find("3 members, 2 online", 1, true), "the guild size in the head line")
    T.truthy(report:find("refresh members", 1, true), "the members tab measured")
    T.truthy(report:find("fire ROSTER", 1, true), "the roster event measured")
    slash("perf copy")
    slash("perf reset")
    slash("perf off")
    T.eq(env.GuildyDB.settings.perf, nil)
    T.eq(ns.Perf.on, false)
    ns.UI.SelectTab("chat")
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
    T.eq(ns.UI.IsShown(), false) -- closing closes Blizzard's window
    env.CommunitiesFrame:Show() -- comes back to the page within the session
    ns.UI.SelectTab("chat")
    -- members tab: twinks under their main, folded, without note, by rank and item level
    ns.UI.SelectTab("members")
    local mv = ns.UI.TabView("members")
    for _, setup in ipairs({ { noNote = true }, { noOfficerNote = true }, { fold = true, sort = "rank" }, { sort = "ilvl" }, { sort = "level" } }) do
      mv.noNote, mv.noOfficerNote, mv.fold = setup.noNote, setup.noOfficerNote, setup.fold
      mv.sort = setup.sort or "level"
      mv:Refresh()
    end
    -- the rank menu lists the ranks that have members; one of them leaves only its members
    T.truthy(#mv.ranks >= 1, "ranks for the menu")
    T.eq(mv.Headers.group, nil)
    mv:SetFilterValue("rankIndex", mv.ranks[1].index)
    for _, item in ipairs(mv.List.items or {}) do
      if item.m then T.eq(item.m.rankIndex, mv.ranks[1].index) end
    end
    mv:SetFilterValue("rankIndex", nil)
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
    T.eq(ns.UI.IsShown(), false) -- closing closes Blizzard's window
    env.CommunitiesFrame:Show()
    T.eq(ns.UI.Current(), "professions") -- opening comes back to the last tab
    T.eq(ns.Settings().lastTab, nil) -- only within the session: a login or reload starts on chat
    T.eq(ns.Store.Init({ settings = { lastTab = "fame", famePage = "pvp" } }).settings.lastTab, nil)
    local A = ns.UI.Action
    T.eq(A.Invite("Xii Lightspark"), nil) -- no invite button in Blizzard's window
    local invite = env.CreateFrame("Button")
    invite.IsEnabled = function() return true end
    env.C_Club = { GetGuildClubId = function() return 7 end }
    rawset(env.CommunitiesFrame, "InviteButton", invite)
    rawset(env.CommunitiesFrame, "GetSelectedClubId", function() return 7 end)
    T.eq(A.Invite("Xii Lightspark").click, invite)
    T.eq(ns.UI.InviteAction().click, invite)
    ns.UI.ShowOverlay(env.UIParent, A.Invite("Xii Lightspark"))
    ns.UI.ShowBlizzard()
    T.eq(ns.UI.IsShown(), false) -- Blizzard's own window instead of Guildy
    T.truthy(ns.UI.ReturnTab():IsShown(), "Guildy tab on Blizzard's window")
    env.CommunitiesFrame:Hide()
    T.eq(ns.UI.ReturnTab():IsShown(), false)
    env.CommunitiesFrame:Show()
    T.truthy(ns.UI.IsShown(), "Guildy again next time")
    -- the communities side tab shows Blizzard's window; its Guildy tab comes back without closing it
    T.truthy(ns.UI.frame.CommunitiesTab, "communities side tab")
    ns.UI.ShowBlizzard()
    T.eq(ns.UI.IsShown(), false)
    ns.UI.Show()
    T.truthy(ns.UI.IsShown(), "back to Guildy from Blizzard's window")
    T.eq(ns.UI.ReturnTab():IsShown(), false)
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
    T.eq(ns.UI.IsShown(), false) -- closing closes Blizzard's window
    env.CommunitiesFrame:Show()
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
  T.it("shows the communities in Guildy: list, channels, chat, members, unread lines", function()
    local saved = env.C_Club
    local sent, focusedStream
    local function Id(n) return { epoch = (1800000000 + n) * 1000000, position = n } end
    env.C_Club = {
      GetGuildClubId = function() return 7 end,
      GetSubscribedClubs = function()
        return { { clubId = 7, name = "Murloc Mafia", clubType = 2 }, { clubId = 9, name = "Zander", clubType = 1 },
          { clubId = 8, name = "angler", clubType = 0 } }
      end,
      GetStreams = function(clubId)
        if clubId == 7 then return { { streamId = 1, streamType = 1 } } end
        return { { streamId = 3, name = "Off-Topic", sortOrder = 2 }, { streamId = 2, name = "General", sortOrder = 1 } }
      end,
      GetMessageRanges = function(clubId) return clubId == 7 and {} or { { oldestMessageId = Id(1), newestMessageId = Id(2) } } end,
      GetMessagesInRange = function()
        return { { messageId = Id(1), content = "hi", author = { name = "Ika-Forever", classID = 8 } },
          { messageId = Id(2), content = "yo", author = { name = "Bo" } } }
      end,
      IsBeginningOfStream = function() return true end,
      RequestMoreMessagesBefore = function() end,
      FocusStream = function(clubId, streamId) focusedStream = { clubId, streamId } return true end,
      UnfocusStream = function() focusedStream = nil end,
      SetClubPresenceSubscription = function() end,
      ClearClubPresenceSubscription = function() end,
      GetClubMembers = function() return { 1, 2, 3 } end,
      GetMemberInfo = function(_, id)
        return ({ { name = "Bo", presence = 3, level = 20 }, { name = "Ika-Forever", presence = 1, level = 33, classID = 8, zone = "Desolace" },
          { name = SECRET } })[id]
      end,
      SendMessage = function(clubId, streamId, text) sent = { clubId, streamId, text } end,
      GetInvitationsForSelf = function()
        return { { club = { clubId = 11, name = "Kodo-Zähmer" }, inviter = { name = "Bo" } }, { club = {} } }
      end,
      AcceptInvitation = function(clubId) sent = { "accept", clubId } end,
      DeclineInvitation = function(clubId) sent = { "decline", clubId } end,
      RedeemTicket = function() error("RedeemTicket is protected") end,
    }
    local C = ns.Communities
    local list = C.List()
    T.eq(#list, 2) -- not the guild
    T.eq(list[1].name, "angler")
    T.eq(C.Streams(9)[1].name, "General")
    local members = C.Members(9)
    T.eq(#members, 2) -- the secret name is left out
    T.eq(members[1].name, "Ika Forever") -- online first (names as in the guild chat)
    T.eq(members[1].online, true)
    T.eq(#C.History(9, 2), 2)
    -- a line in a community that is not shown counts as unread; a guild line does not
    T.eq(C.OnMessageAdded(9, 2), true)
    T.eq(C.OnMessageAdded(7, 1), false)
    T.eq(C.Unread(9), 1)
    -- the view: the first community selected and focused on its first channel
    env.CommunitiesFrame:Show()
    ns.UI.SelectTab("communities")
    T.eq(ns.UI.Current(), "communities")
    T.eq(focusedStream, { 8, 2 })
    local view = ns.UI.TabView("communities")
    view:Select(9)
    T.eq(focusedStream, { 9, 2 })
    T.eq(C.Unread(9), 0) -- seen now
    view:SelectStream(3)
    T.eq(focusedStream, { 9, 3 })
    view.Input:SetText("hallo")
    view.Input:GetScript("OnEnterPressed")(view.Input)
    T.eq(sent, { 9, 3, "hallo" })
    -- joining in Guildy: invitations and invite links
    local invites = C.Invitations()
    T.eq(#invites, 1) -- one without a club id is left out
    T.eq(invites[1].inviter, "Bo")
    -- invitations stand first in Guildy's list and open their own panel
    view:Render()
    T.eq(view.Clubs.rows[1].club.invite, true)
    view:SelectInvite(11)
    T.truthy(view.Invite:IsShown(), "invitation panel over the chat")
    T.eq(view.Input:IsShown(), false)
    -- its buttons click Blizzard's own Accept / Decline once Blizzard's window shows the invitation
    local accept, decline = {}, {}
    rawset(env.CommunitiesFrame, "InvitationFrame", { clubId = 11, AcceptButton = accept, DeclineButton = decline })
    rawset(env.CommunitiesFrame, "GetSelectedClubId", function() return 7 end)
    T.eq(ns.UI.Action.AnswerInvitation(11, true), nil) -- Blizzard still shows the guild
    rawset(env.CommunitiesFrame, "GetSelectedClubId", function() return 11 end)
    T.eq(ns.UI.Action.AnswerInvitation(11, true).click, accept)
    T.eq(ns.UI.Action.AnswerInvitation(11, false).click, decline)
    rawset(env.CommunitiesFrame, "GetSelectedClubId", function() return 7 end)
    rawset(env.CommunitiesFrame, "InvitationFrame", nil)
    view:Select(9)
    T.eq(view.Invite:IsShown(), false)
    T.eq(C.ParseTicket("|cffffd100|HclubTicket:AbC123|h[Join: Zander]|h|r"), "AbC123")
    T.eq(C.ParseTicket(" https://blizzard.com/invite/Xy9-z "), "Xy9-z")
    T.eq(C.ParseTicket("Qw3rT7"), "Qw3rT7")
    T.eq(C.ParseTicket("not a code"), nil)
    -- RedeemTicket is protected: Guildy writes the invite as a link into Blizzard's chat window instead
    local printed
    rawset(env.DEFAULT_CHAT_FRAME, "AddMessage", function(_, text) printed = text end)
    T.eq(C.Redeem("hallo welt"), "invalid")
    T.eq(C.Redeem("Qw3rT7"), "linked")
    T.truthy(printed:find("|HclubTicket:Qw3rT7|h", 1, true), "clickable invite link in the chat window")
    view:ShowJoin(true)
    T.truthy(view.Join:IsShown(), "join panel over the chat")
    T.eq(view.Input:IsShown(), false)
    view.Join.Link:SetText("|HclubTicket:Zz12|h[x]|h")
    view.Join.Link:GetScript("OnEnterPressed")(view.Join.Link)
    T.truthy(printed:find("|HclubTicket:Zz12|h", 1, true), "the field's link too")
    -- an invite link clicked in Guildy's chat goes the same way
    printed = nil
    view.Pane.Messages:GetScript("OnHyperlinkClick")(view.Pane.Messages, "clubTicket:Ab12", "[x]", "LeftButton")
    T.truthy(printed and printed:find("|HclubTicket:Ab12|h", 1, true), "chat link handed to Blizzard's chat")
    rawset(env.DEFAULT_CHAT_FRAME, "AddMessage", nil)
    view:Select(9)
    T.eq(view.Join:IsShown(), false) -- picking a community goes back to its chat
    T.truthy(#C.Debug() > 5, "/guildy communitydebug")
    -- an empty roster while in a guild (after leaving / joining a community) keeps the last one
    local before = #ns.Roster.Members()
    T.truthy(before > 0, "a roster to keep")
    local count = env.GetNumGuildMembers
    env.GetNumGuildMembers = function() return 0 end
    ns.Roster.Scan()
    T.eq(#ns.Roster.Members(), before)
    env.GetNumGuildMembers = count
    -- a request that brings nothing older ends the loading: no new request on every render
    local requests = 0
    env.C_Club.IsBeginningOfStream = function() return false end
    env.C_Club.RequestMoreMessagesBefore = function() requests = requests + 1 end
    T.eq(C.LoadOlder(9, 3), true)
    T.eq(C.HistoryState(9, 3), "loading")
    ns.Chat.OnHistoryReceived(9, 3)
    T.eq(C.LoadOlder(9, 3), false)
    T.eq(requests, 1)
    T.eq(C.HistoryState(9, 3), "start")
    env.C_Club.IsBeginningOfStream = function() return true end
    local created
    env.CommunitiesCreateCommunityDialog = function() created = true end
    view:ShowJoin(true)
    view.Join.Create:GetScript("OnClick")(view.Join.Create)
    T.truthy(created, "Blizzard's create dialog opened")
    env.CommunitiesCreateCommunityDialog = nil
    -- inviting: Blizzard's own list picks the community (secure click), its invite button invites
    env.C_Club.GetClubPrivileges = function() return { canSendInvitation = true } end
    view:Select(9)
    T.truthy(view.InviteSend:IsShown(), "invite button for those allowed to invite")
    local A, blizzardSelected = ns.UI.Action, 7
    local entries = { { clubId = 7, Click = function() end }, { clubId = 9, Click = function() end } }
    local inviteButton = { IsEnabled = function() return true end }
    rawset(env.CommunitiesFrame, "GetSelectedClubId", function() return blizzardSelected end)
    rawset(env.CommunitiesFrame, "InviteButton", inviteButton)
    rawset(env.CommunitiesFrame, "CommunitiesList", { ScrollBox = { ForEachFrame = function(_, fn)
      for _, entry in ipairs(entries) do fn(entry) end
    end } })
    T.eq(A.CommunityInvite(9), nil) -- Blizzard still shows the guild
    T.eq(A.SelectClub(9).click, entries[2])
    T.eq(A.SelectGuild(), nil) -- the guild is already selected there
    blizzardSelected = 9
    T.eq(A.CommunityInvite(9).click, inviteButton)
    T.eq(A.SelectClub(9), nil)
    T.eq(A.SelectGuild().click, entries[1]) -- the guild tabs pick the guild again
    -- right clicks go to Blizzard's own rows (its menus): the entry always, the member while it shows the club
    T.eq(A.ClubEntry(9).click, entries[2])
    local memberRow = { memberInfo = { guid = "Player-1-AB" }, Click = function() end }
    rawset(env.CommunitiesFrame, "MemberList", { ScrollBox = { ForEachFrame = function(_, fn) fn(memberRow) end } })
    T.eq(A.ClubMember(9, "Player-1-AB").click, memberRow)
    T.eq(A.ClubMember(8, "Player-1-AB"), nil)
    rawset(env.CommunitiesFrame, "MemberList", nil)
    rawset(env.CommunitiesFrame, "CommunitiesList", nil)
    rawset(env.CommunitiesFrame, "InviteButton", nil)
    blizzardSelected = 7
    view:ShowJoin(false)
    ns.UI.SelectTab("chat")
    T.eq(focusedStream, { 7, 1 }) -- leaving the view unfocuses the channel, the guild chat focuses its own
    env.C_Club = saved
    T.eq(errors, {})
  end)

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
    T.eq(env.GuildyDB.settings.statMouseover, true) -- on by default since 1.0.1
    ns.GameStats.ToggleMouseover()
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

  T.it("customizes the member list style and the Hall of Fame tiles in the options", function()
    env.CommunitiesFrame:Show()
    ns.UI.SelectTab("members")
    local members = ns.UI.TabView("members")
    local function Headers()
      local count = 0
      for _, row in ipairs(members.List.rows) do
        if row:IsShown() and row.Section:IsShown() then count = count + 1 end
      end
      return count
    end
    T.truthy(Headers() > 0, "sections by default")
    ns.UI.ToggleOptions()
    local options = ns.UI.Options()
    T.truthy(options and options:IsShown(), "options open")
    for _, key in ipairs({ "general", "chat", "members", "fame", "professions" }) do options:Select(key) end
    -- members: a column switched off leaves the list, twinks stand on their own; chat: no icons
    local lists = options.Panels.members
    local function Toggle(check, on)
      check:SetChecked(on)
      check:GetScript("OnClick")(check)
    end
    for _, check in ipairs(lists.Columns) do
      Toggle(check, false)
      T.eq(ns.Settings().memberColumns[check.key], false)
      T.eq(members.Headers[check.key]:IsShown(), false)
      Toggle(check, true)
      T.eq(ns.Settings().memberColumns[check.key], nil)
    end
    T.truthy(members.Headers.rank:IsShown(), "rank column back")
    Toggle(lists.Twinks, false)
    T.eq(ns.Settings().memberTwinks, false)
    for _, row in ipairs(members.List.rows) do
      if row:IsShown() and row.member then T.eq(row.Cells.name:GetText():find("^      ") == nil, true) end
    end
    Toggle(lists.Twinks, true)
    T.eq(ns.Settings().memberTwinks, nil)
    local chatProfs = options.Panels.chat.ChatProfs
    Toggle(chatProfs, false)
    T.eq(ns.Settings().chatProfs, false)
    ns.UI.SelectTab("chat")
    Toggle(chatProfs, true)
    -- professions: sharing
    local share = options.Panels.professions.Share
    local shared = ns.Settings().share
    Toggle(share, false)
    T.eq(ns.Settings().share, false)
    Toggle(share, true)
    T.eq(ns.Settings().share, true)
    ns.Settings().share = shared
    -- every tooltip position draws a member's tooltip
    for _, mode in ipairs(ns.UI.TOOLTIP_ANCHORS) do
      ns.Settings().tooltipAnchor = mode
      T.eq(ns.UI.TooltipAnchor(), mode)
      ns.UI.MemberTooltip(members.List.rows[2], ns.Roster.Members()[1])
    end
    ns.Settings().tooltipAnchor = nil
    T.eq(ns.UI.TooltipAnchor(), "window")
    ns.UI.SelectTab("members")
    -- a click on a style card changes the list at once
    for _, card in ipairs(options.Panels.members.Cards) do
      card:GetScript("OnMouseUp")(card)
      T.eq(ns.Settings().memberStyle, card.style)
      T.eq(Headers() > 0, card.style == "sections")
    end
    ns.Settings().memberStyle = nil
    -- the tile editor: remove, add at the end, move; a page keeps its last tile
    local fame = options.Panels.fame
    local page = ns.Stats.PAGES[1]
    local a, b = page.headline[1], page.headline[2]
    fame:Remove(a)
    T.eq(#ns.Settings().fameTiles[page.key], #page.headline - 1)
    T.eq(ns.Settings().fameTiles[page.key][1], b)
    fame:Add(a)
    T.eq(ns.Settings().fameTiles[page.key][#page.headline], a)
    T.eq(fame.selected, a)
    fame:Move(a, -1)
    T.eq(ns.Settings().fameTiles[page.key][#page.headline - 1], a)
    -- a click on a free statistic's row adds it; none can be added to a full page
    T.eq(#ns.Settings().fameTiles[page.key], ns.Stats.MAX_TILES)
    fame:Add(347)
    T.eq(#ns.Settings().fameTiles[page.key], ns.Stats.MAX_TILES)
    ns.Settings().fameTiles = { [page.key] = { b } }
    fame:Refresh()
    fame:Remove(b)
    T.eq(ns.Settings().fameTiles[page.key], { b })
    local row = fame.List.rows[1]
    row:GetScript("OnMouseUp")(row)
    T.eq(#ns.Settings().fameTiles[page.key], 2)
    -- the search narrows both lists to what matches
    local all = #fame.Lists.tiles.items
    fame.query = "zzz no such statistic"
    fame:Refresh()
    T.eq(fame.Lists.tiles.rows[1]:IsShown(), false)
    T.eq(fame.Lists.cards.rows[1]:IsShown(), false)
    fame.query = ""
    fame:Refresh()
    T.truthy(all > 20 and #fame.Lists.tiles.items == all, "every statistic back without a search")
    T.truthy(fame.Lists.tiles.rows[1]:IsShown(), "the first statistic in view")
    T.eq(fame.Lists.tiles.rows[all], nil) -- a row out of view is not built
    -- the title cards of the page the same way, also with a title of another page
    fame:SetKind("cards")
    fame:Remove(page.titles[1].key)
    T.eq(ns.Settings().fameCards[page.key][1], page.titles[2].key)
    ns.Settings().fameCards = { [page.key] = { page.titles[2].key } }
    fame:Refresh()
    fame:Add("GOLD")
    T.eq(ns.Settings().fameCards[page.key], { page.titles[2].key, "GOLD" })
    -- a click on a row of the title list adds to the title cards, whatever row was picked before
    fame:SetKind("tiles")
    local titleRow = fame.Lists.cards.rows[1]
    titleRow:GetScript("OnMouseUp")(titleRow)
    T.eq(#ns.Settings().fameCards[page.key], 3)
    T.eq(fame.kind, "cards")
    ns.UI.SelectTab("fame")
    -- restoring brings the page back to what Guildy ships
    fame:Restore()
    T.eq(ns.Settings().fameTiles[page.key], nil)
    T.eq(ns.Settings().fameCards[page.key], nil)
    fame:SetKind("tiles")
    ns.Settings().fameTiles = nil
    ns.UI.SelectTab("fame")
    ns.UI.ToggleOptions()
    T.eq(options:IsShown(), false)
    T.eq(errors, {})
  end)
end)

T.describe("Made-up names for pictures", function()
  local REAL = { "Makira", "Farron", "Au Tsch", "Au-Tsch", "Ran Fred", "Ran-Fred", "Lightspark", "Murloc Mafia",
    "Mrglmrgl", "Discord", "hallo", "Haifutter" }

  -- every view the screenshot run shows, every member's page and tooltip
  local function ShowEverything()
    for _, shot in ipairs(ns.UI.SHOTS) do shot[2]() end
    for _, m in ipairs(ns.Roster.Members()) do
      ns.UI.ShowMember(m)
      ns.UI.MemberTooltip(env.UIParent, m)
    end
    ns.UI.SelectTab("chat")
    ns.UI.HideOptions()
  end

  local function Leaks(texts)
    local found = {}
    for _, text in ipairs(texts) do
      -- the target of a chat link is not drawn (and has to stay real: a click whispers that player)
      text = text:gsub("|H[^|]*|h", "")
      for _, real in ipairs(REAL) do
        if text:find(real, 1, true) then found[#found + 1] = real .. " in: " .. text end
      end
    end
    return found
  end

  T.it("shows no real name, note, guild name or chat line anywhere", function()
    env.CommunitiesFrame:Show()
    Fire("CHAT_MSG_GUILD", "hallo zusammen", "Au-Tsch", "", "", "", "", 0, 0, "", 0, 1, "Player-1-03")
    -- the test itself is able to find them: with real names the same walk does show them
    world.calls.texts = {}
    ShowEverything()
    T.truthy(#Leaks(world.calls.texts) > 5, "real names found while they are shown")
    env.SlashCmdList.GUILDY("shots anon")
    T.eq(ns.Anon.on, true)
    world.calls.texts = {}
    ShowEverything()
    local shown = world.calls.texts
    world.calls.texts = nil
    T.truthy(#shown > 200, "the views were drawn")
    T.eq(table.concat(Leaks(shown), " ;; "), "")
    -- the PvP page gets sample values, on a copy: the stored statistics stay as they are
    local stored = { ts = 5, src = "self", v = { [107] = 12 }, months = {} }
    local sample
    for i = 1, 20 do
      sample = ns.Anon.Stats(stored, "member " .. i, 40)
      if sample ~= stored then break end
    end
    T.truthy(sample ~= stored and sample.v[588] > 0 and sample.v[107] == 12, "sample PvP values beside the real ones")
    T.eq(stored.v, { [107] = 12 })
    -- the same member has the same stand-in everywhere, and stays findable under the real name
    local makira = ns.Roster.Find("Makira Farron")
    T.truthy(makira and makira.name ~= "Makira Farron", "a made-up name")
    T.eq(makira.name, ns.Anon.Name("Makira-Farron"))
    T.eq(makira.fullName, "Makira-Farron")
    T.eq(errors, {})
  end)

  T.it("keeps nothing under a made-up name and gives the real names back", function()
    local guild = ns.GuildData()
    local before = 0
    for _ in pairs(guild.members) do before = before + 1 end
    local makira = ns.Roster.Find("Makira Farron")
    ns.Store.Member(guild, makira.name).profs[171] = { ts = 5, src = "relay" }
    local after = 0
    for _ in pairs(guild.members) do after = after + 1 end
    T.eq(after, before)
    env.SlashCmdList.GUILDY("shots anon")
    T.eq(ns.Anon.on, false)
    T.eq(ns.Roster.Find("Makira Farron").name, "Makira Farron")
    T.eq(ns.Anon.Name("Makira Farron"), "Makira Farron")
    T.eq(errors, {})
  end)
end)

T.describe("Activity in game", function()
  local function Today() return ns.Activity.Day(env.GetServerTime()) end

  T.it("marks the days members were seen online", function()
    local guild = ns.GuildData()
    guild.seenSince = nil
    for _, member in pairs(guild.members) do member.seen = nil end
    Fire("GUILD_ROSTER_UPDATE")
    RunTimers()
    T.eq(guild.seenSince, Today())
    T.eq(guild.members["ran fred"].seen, { [Today()] = true })
    T.eq(guild.members["makira farron"].seen, { [Today() - 3] = true }) -- last online 3 days and 2 hours ago
    T.eq(errors, {})
  end)

  T.it("marks nothing while names are made up for pictures", function()
    local guild = ns.GuildData()
    guild.seenSince = nil
    for _, member in pairs(guild.members) do member.seen = nil end
    env.SlashCmdList.GUILDY("shots anon")
    Fire("GUILD_ROSTER_UPDATE")
    RunTimers()
    T.eq(guild.seenSince, nil)
    T.eq(guild.members["ran fred"].seen, nil)
    env.SlashCmdList.GUILDY("shots anon")
    RunTimers()
    T.eq(ns.Anon.on, false)
    T.eq(errors, {})
  end)

  T.it("counts the days the own character was played", function()
    env.UnitName = function() return "Ran", "Fred" end
    env.GetStatisticsCategoryList = function() return { 128 } end
    env.GetCategoryNumAchievements = function() return 1 end
    env.GetStatistic = function() return "12", false, 107 end
    local serverTime = env.GetServerTime
    env.GuildyDB.ownDays = nil
    local before = ns.GuildData().members["ran fred"].stats
    if before then before.v[ns.Stats.DAYS] = nil end
    ns.GameStats.UpdateOwn()
    local stats = ns.GuildData().members["ran fred"].stats
    T.eq(stats.v[ns.Stats.DAYS], 1)
    ns.GameStats.UpdateOwn()
    T.eq(ns.GuildData().members["ran fred"].stats.v[ns.Stats.DAYS], 1) -- the same day
    env.GetServerTime = function() return serverTime() + 86400 end
    ns.GameStats.UpdateOwn()
    T.eq(ns.GuildData().members["ran fred"].stats.v[ns.Stats.DAYS], 2)
    env.GetServerTime = serverTime
    T.eq(errors, {})
  end)

  T.it("computes the activity of the guild and prints it on /guildy activity", function()
    local activity = ns.GameActivity.Get()
    local chars = 0
    for _, player in ipairs(activity.players) do chars = chars + #player.chars end
    T.eq(chars, #ns.Roster.Members())
    T.eq(#activity.month, #ns.Activity.MONTH_ROWS)
    T.eq(#activity.summary.buckets, 5)
    T.truthy(ns.GameActivity.Get() == activity, "kept until something changes")
    ns.Fire("STATS")
    T.truthy(ns.GameActivity.Get() ~= activity, "computed anew after new statistics")
    local printed
    rawset(env.DEFAULT_CHAT_FRAME, "AddMessage", function(_, text) printed = text end)
    env.SlashCmdList.GUILDY("activity")
    rawset(env.DEFAULT_CHAT_FRAME, "AddMessage", nil)
    T.truthy(printed and printed:find("[Guildy]", 1, true) and printed:find(ns.L.ACTIVITY_REPORT:match("^[^:]+"), 1, true), tostring(printed))
    T.eq(errors, {})
  end)
end)

T.describe("Overview phases", function()
  local function View()
    ns.UI.SelectTab("overview")
    return ns.UI.TabView("overview")
  end

  T.it("follows the guild until somebody chooses, then keeps the choice", function()
    local settings = ns.Settings()
    settings.overviewPhase = nil
    T.eq(ns.UI.OverviewPhase(), "level")
    local view = View()
    view:Refresh()
    T.eq(view.Level:IsShown(), true)
    T.eq(view.Endgame:IsShown(), false)
    local button = view.Phase.buttons[2]
    button:GetScript("OnClick")(button)
    T.eq(settings.overviewPhase, "endgame")
    T.eq(ns.UI.OverviewPhase(), "endgame")
    T.eq(view.Endgame:IsShown(), true)
    T.eq(view.Level:IsShown(), false)
    T.eq(errors, {})
  end)

  T.it("offers the same choice in the options, with automatic", function()
    local items = ns.UI.OverviewPhaseItems()
    T.eq(#items, 3)
    T.eq(items[3].checked, true) -- endgame, chosen on the switch
    items[1].onClick()
    T.eq(ns.Settings().overviewPhase, nil)
    T.eq(ns.UI.OverviewPhaseItems()[1].checked, true)
    items[2].onClick()
    T.eq(ns.Settings().overviewPhase, "level")
    T.eq(View().Level:IsShown(), true)
    T.eq(errors, {})
  end)

  T.it("shows the endgame view with and without statistics", function()
    ns.Settings().overviewPhase = "endgame"
    local view = View()
    view:Refresh()
    view:OnResize()
    T.truthy(view.EndgameView, "built")
    T.eq(errors, {})
    local guild, kept = ns.GuildData(), {}
    for key, member in pairs(guild.members) do
      kept[key] = member.stats
      member.stats = nil
    end
    ns.Fire("STATS")
    view:Refresh()
    T.eq(view.EndgameView.Pulse:GetText(), "–") -- nobody has a score
    for key, member in pairs(guild.members) do member.stats = kept[key] end
    ns.Fire("STATS")
    ns.Settings().overviewPhase = nil
    view:Refresh()
    T.eq(errors, {})
  end)
end)

T.describe("Members tab drill-downs of the endgame view", function()
  local function Listed(view)
    local keys = {}
    for _, item in ipairs(view.List.items) do
      if item.m then keys[#keys + 1] = item.m.key end
    end
    table.sort(keys)
    return keys
  end
  local function Prepare()
    local guild, now = ns.GuildData(), env.GetServerTime()
    local month = ns.Stats.MonthKey(now, ns.GameStats.Date)
    guild.members["ran fred"].stats = { ts = now, src = "self",
      v = { [107] = 5000, [932] = 30, [1095] = 30, [1098] = 2, [ns.Stats.GEAR.ILVL] = 579, [ns.Stats.GEAR.COUNT] = 16 },
      months = { [month] = { ts = now - 10 * 86400, v = { [107] = 1 } } } }
    ns.Fire("STATS")
    ns.UI.SelectTab("members")
    return ns.UI.TabView("members")
  end

  T.it("lists the players of an activity bar, sorted by the score", function()
    local view = Prepare()
    local score = ns.GameActivity.ScoreOf("ran fred")
    T.truthy(score and score > 0, "a score")
    local bucket = ns.Activity.Bucket(score)
    view:SetFilter({ scoreBucket = bucket })
    local listed = Listed(view)
    T.truthy(#listed >= 1)
    for _, key in ipairs(listed) do T.eq(ns.Activity.Bucket((ns.GameActivity.ScoreOf(key))), bucket, key) end
    T.eq(view.sort, "score")
    T.eq(view.desc, true)
    T.eq(view.hidden.score, false)
    T.truthy(view.Summary:GetText():find(ns.L["SCORE_" .. bucket], 1, true), view.Summary:GetText())
    view:SetFilter({ scoreBucket = bucket == 1 and 4 or 1 })
    T.eq(Listed(view), {})
    T.eq(errors, {})
  end)

  T.it("lists the members of an item level column and of a raid", function()
    local view = Prepare()
    view:SetFilter({ ilvl = 57 })
    T.eq(Listed(view), { "ran fred" })
    view:SetFilter({ ilvl = 58 })
    T.eq(Listed(view), {})
    view:SetFilter({ raidKill = "onyxia" })
    T.eq(Listed(view), { "ran fred" })
    view:SetFilter({ raidKill = "hyjal" })
    T.eq(Listed(view), {})
    view:SetFilter({})
    T.eq(#Listed(view), #ns.Roster.Members())
    T.eq(errors, {})
  end)
end)
