-- A visit to the guild banker in the stubbed client (tests/wow.lua): Guildy asks for the logs and the
-- tabs, reads what the game answers, shows it on the Bank tab and shares it with the guild.
local T = ...

local clock = 1000
local atBanker = true -- what the client answers when asked whether the player is at a guild banker
local sent, queried = {}, {}
local LINK = "|cffffffff|Hitem:13446::::::::60:::::|h[Erheblicher Heiltrank]|h|r"
local money = {
  { "deposit", "Makira-Farron", 500000, 0, 0, 2, 3 },
  { "repair", "Au-Tsch", 12345, 0, 0, 0, 5 },
  { "withdraw", "Xii-Lightspark", 100000, 0, 0, 0, 1 },
}
local items = {
  [1] = { { "deposit", "Makira-Farron", LINK, 20, 1, nil, 0, 0, 1, 0 }, { "withdraw", "Au-Tsch", LINK, 5, 1, nil, 0, 0, 0, 2 } },
  [2] = { { "move", "Ran-Fred", LINK, 10, 2, 1, 0, 0, 0, 4 } },
}

local function Setup(env)
  env.GetTime = function() return clock end
  env.C_ChatInfo.SendAddonMessage = function(_, text) sent[#sent + 1] = text end
  env.MAX_GUILDBANK_TABS = 6
  env.GetNumGuildBankTabs = function() return 3 end
  -- tab 3 is not for this rank
  env.GetGuildBankTabInfo = function(tab)
    if tab == 1 then return "Tränke", 134829, true, true, 10, 8 end
    if tab == 2 then return "Kräuter", 134830, true, false, 0, 0 end
    return "Offiziere", 134831, false, false, 0, 0
  end
  env.QueryGuildBankLog = function(tab) queried[#queried + 1] = "log" .. tab end
  env.QueryGuildBankTab = function(tab) queried[#queried + 1] = "tab" .. tab end
  env.QueryGuildBankText = function(tab) queried[#queried + 1] = "text" .. tab end
  env.GetGuildBankMoney = function() return 12340000 end
  env.GetGuildBankWithdrawMoney = function() return 380000 end
  env.GetNumGuildBankMoneyTransactions = function() return #money end
  env.GetGuildBankMoneyTransaction = function(i) return unpack(money[i], 1, 7) end
  env.GetNumGuildBankTransactions = function(tab) return items[tab] and #items[tab] or 0 end
  env.GetGuildBankTransaction = function(tab, i) return unpack(items[tab][i], 1, 10) end
  env.GetGuildBankItemLink = function(tab, slot) if tab == 1 and slot <= 3 then return LINK end end
  env.GetGuildBankItemInfo = function() return 134829, 20, false end
  env.GetGuildBankText = function(tab) return tab == 1 and "Für Raids" or "" end
  env.Enum = { PlayerInteractionType = { GuildBanker = 10, Banker = 8 } }
  env.C_PlayerInteractionManager = { IsInteractingWithNpcOfType = function(kind) return atBanker and kind == 10 end }
end
local world = dofile(T.testsDir .. "/wow.lua")(T, { setup = Setup })
local env, ns, errors = world.env, world.ns, world.errors
local Fire, RunTimers = world.Fire, world.RunTimers

local function Messages(kind)
  local P = ns.Protocol
  local assembler, found = P.NewAssembler(), {}
  for _, part in ipairs(sent) do
    local payload = P.AddPart(assembler, "x", part, 0)
    local envelope = payload and P.Decode(payload)
    if envelope and envelope.t == kind then found[#found + 1] = envelope.d end
  end
  return found
end

T.describe("Guild bank", function()
  Fire("ADDON_LOADED", "Guildy")
  Fire("PLAYER_LOGIN")
  Fire("GUILD_ROSTER_UPDATE")
  RunTimers()

  T.it("shows the tab before anything was read", function()
    env.CommunitiesFrame:Show()
    ns.UI.SelectTab("bank")
    T.eq(ns.UI.Current(), "bank")
    local view = ns.UI.TabView("bank")
    T.eq(#view.List.items, 0)
    T.eq(view.Empty:GetText(), ns.L.BANK_EMPTY)
    T.eq(errors, {})
  end)

  T.it("asks for the money log and every tab the rank may view, and reads the answers", function()
    Fire("GUILDBANKFRAME_OPENED")
    RunTimers()
    T.eq(table.concat(queried, " "), "log7 tab1 log1 text1 tab2 log2 text2")
    local bank = ns.GuildData().bank
    T.eq(bank.money, 12340000)
    T.eq(bank.by, "Ran Fred")
    T.eq(#bank.logs.money, 3)
    T.eq(bank.logs.money[1].w, "Makira Farron") -- oldest first, names as Guildy writes them
    T.eq(bank.logs.money[1].ts, 1700000000 - (2 * 24 + 3) * 3600)
    T.eq(#bank.logs["1"], 2)
    T.eq(bank.logs["1"][1].i, "item:13446::::::::60")
    T.eq(bank.logs["1"][1].nm, "Erheblicher Heiltrank")
    T.eq(bank.logs["2"][1].b, 1)
    T.eq(bank.logs["3"], nil)
    T.eq(bank.tabs[3].name, "Offiziere")
    T.eq(bank.tabs[1].slots, nil) -- contents only once the answers had time to arrive
    clock = clock + 60
    Fire("GUILDBANKBAGSLOTS_CHANGED")
    RunTimers()
    T.eq(ns.Bank.Used(bank.tabs[1]), 3)
    T.eq(bank.tabs[1].slots[2], { i = "item:13446::::::::60", id = 13446, nm = "Erheblicher Heiltrank", n = 20 })
    T.eq(bank.tabs[1].text, "Für Raids")
    T.eq(ns.Bank.Used(bank.tabs[3]), nil)
    local mine = ns.GameBank.Mine()
    T.eq(mine.gold, 380000)
    T.eq(mine.tabs[1], { view = true, deposit = true, limit = 10, left = 8 })
    T.eq(mine.tabs[3].view, false)
    T.eq(errors, {})
  end)

  T.it("reads the same log again without adding anything", function()
    Fire("GUILDBANKLOG_UPDATE")
    Fire("GUILDBANK_UPDATE_MONEY")
    RunTimers()
    local bank = ns.GuildData().bank
    T.eq(#bank.logs.money, 3)
    T.eq(#bank.logs["1"], 2)
    T.eq(#bank.samples, 1)
  end)

  T.it("lists every movement on the Bank tab and filters them", function()
    local view = ns.UI.TabView("bank")
    view:Refresh()
    T.eq(#view.List.items, 6)
    T.eq(#view.Tabs.items, 3)
    T.eq(view.Empty:IsShown(), false)
    local first = view.List.rows[1]
    T.truthy(first and first.entry and first.entry.k == "withdraw", "newest first")
    T.truthy(first.After:GetText():find("1,234", 1, true) or first.After:GetText():find("1234", 1, true), first.After:GetText())
    first.Pick:GetScript("OnClick")(first.Pick)
    T.eq(view.filter.who, "xii lightspark")
    T.eq(#view.List.items, 1)
    T.eq(view.Only:IsShown(), true)
    view.Only:GetScript("OnClick")(view.Only)
    T.eq(#view.List.items, 6)
    view.filter.kind = "gold"
    view:Refresh()
    T.eq(#view.List.items, 3)
    view.filter.kind, view.filter.tab = nil, 2
    view:Refresh()
    T.eq(#view.List.items, 1)
    view.filter.tab = nil
    view:Refresh()
    T.eq(errors, {})
  end)

  T.it("shows a button per tab, what the next one costs and what the player may still take", function()
    env.GetGuildBankTabCost = function() return 2500000 end
    Fire("GUILDBANK_UPDATE_MONEY")
    RunTimers()
    local view = ns.UI.TabView("bank")
    view:Refresh()
    T.eq(ns.GuildData().bank.cost, 2500000)
    T.eq(view.Cost:IsShown(), true)
    T.eq(view.CostLabel:GetText(), ns.L.BANK_TAB_COST:format(4))
    -- "All" and the three tabs; a click filters, the chosen one is the one that cannot be clicked
    T.eq(view.TabButtons[1]:GetText(), ns.L.BANK_TABS_ALL)
    T.eq(view.TabButtons[3]:GetText(), "Kräuter")
    T.eq(#view.TabButtons, 4)
    view.TabButtons[3]:GetScript("OnClick")(view.TabButtons[3])
    T.eq(view.filter.tab, 2)
    T.eq(#view.List.items, 1)
    view.TabButtons[1]:GetScript("OnClick")(view.TabButtons[1])
    T.eq(view.filter.tab, nil)
    T.eq(#view.List.items, 6)
    -- the own limits, one line per tab
    T.eq(view.AccessEmpty:IsShown(), false)
    T.truthy(view.AccessGold:GetText():find("38", 1, true), view.AccessGold:GetText())
    T.truthy(view.AccessRows[1].Value:GetText():find("8", 1, true), view.AccessRows[1].Value:GetText())
    T.truthy(view.AccessRows[2].Value:GetText():find(ns.L.BANK_TAB_VIEW, 1, true), view.AccessRows[2].Value:GetText())
    T.truthy(view.AccessRows[3].Value:GetText():find(ns.L.BANK_TAB_HIDDEN, 1, true), view.AccessRows[3].Value:GetText())
    T.eq(errors, {})
  end)

  T.it("marks large movements in the chart as the options say and looks back the chosen days", function()
    local view = ns.UI.TabView("bank")
    ns.UI.ShowOptions("bank")
    local panel = ns.UI.Options().Panels.bank
    T.eq(panel.Marks:GetChecked(), true)
    local function Marks()
      local shown = 0
      for _, mark in ipairs(view.Chart.Marks) do
        if mark:IsShown() then shown = shown + 1 end
      end
      return shown
    end
    view.Chart.Plot:SetSize(800, 120)
    view:Refresh()
    T.eq(Marks(), 0) -- 50 of 1 234 gold is no quarter of the bank
    ns.UI.SetBankSetting("share", 0.01)
    view:Refresh()
    T.eq(Marks(), 1)
    ns.UI.SetBankSetting("share", 0.005) -- the repair in between never counts
    view:Refresh()
    T.eq(Marks(), 2)
    panel.Marks:SetChecked(false)
    panel.Marks:GetScript("OnClick")(panel.Marks)
    T.eq(Marks(), 0)
    ns.UI.SetBankSetting("marks", nil)
    ns.UI.SetBankSetting("share", nil)
    T.eq(ns.Settings().bank, nil) -- nothing differs from what Guildy ships: nothing is stored
    -- the days: chosen in the toolbar, for every box
    T.eq(view.Period.buttons[1].value, 7)
    view.Period.buttons[1]:GetScript("OnClick")(view.Period.buttons[1])
    T.eq(ns.UI.BankSetting("days"), 7)
    T.eq(ns.UI.BankDays(), 7)
    T.eq(view.SumsLabel:GetText(), ns.L.BANK_WEEK:format(7))
    view.Period.buttons[2]:GetScript("OnClick")(view.Period.buttons[2])
    T.eq(ns.UI.BankSetting("days"), nil)
    ns.UI.HideOptions()
    T.eq(errors, {})
  end)

  T.it("adds, removes, moves and sizes its boxes in edit mode", function()
    local view = ns.UI.TabView("bank")
    local board = view.board
    local function Has(key) return board.placed[key] ~= nil end
    -- the ledger preset to start with
    T.eq(Has("ledger") and Has("chart") and Has("total") and Has("tabs") and Has("access"), true)
    T.eq(Has("balance"), false)
    T.eq(view.More.balance:IsShown(), false)
    T.eq(view.Add:IsShown(), false)
    view.Edit:GetScript("OnClick")(view.Edit)
    T.eq(board.editing, true)
    T.eq(view.Add:IsShown(), true)
    T.eq(view.Edit:GetText(), ns.L.BANK_EDIT_DONE)
    T.eq(board.defs.ledger.Cover:IsShown(), true)
    -- every box that is not on the board is on offer; the board is full
    local offered = {}
    for _, item in ipairs(view:AddItems()) do offered[#offered + 1] = item.text end
    T.eq(#offered, 5)
    T.eq(board:Insert("givers"), false)
    -- remove one: its room is free for another
    board.defs.access.Cover.Remove:GetScript("OnClick")(board.defs.access.Cover.Remove)
    T.eq(Has("access"), false)
    T.eq(view.Access:IsShown(), false)
    T.eq(board:Insert("givers"), true)
    T.eq(board.placed.givers, { k = "givers", x = 0, y = 7, w = 3, h = 3 }) -- at its smallest: more does not fit
    T.eq(view.More.givers:IsShown(), true)
    T.eq(#view.More.givers.List.items, 1) -- Makira paid in
    -- drag its corner: two rows taller (the stubbed board is 100 wide and high: 9 px a cell)
    local x, y, down = 100, 100, true
    env.GetCursorPosition = function() return x, y end
    env.IsMouseButtonDown = function() return down end
    board:Start("size", "givers")
    y = 100 - 2 * 9
    board:Track()
    T.eq(board.Ghost:IsShown(), true)
    down = false
    board:Track()
    T.eq(board.placed.givers.h, 5)
    T.eq(board.Ghost:IsShown(), false)
    -- drag it onto another box: it stays where it was
    down, x, y = true, 100, 100
    board:Start("move", "givers")
    y = 100 + 4 * 9
    board:Track()
    down = false
    board:Track()
    T.eq(board.placed.givers.y, 7)
    -- never smaller than it works at
    down, x, y = true, 100, 100
    board:Start("size", "givers")
    x, y = 0, 300
    board:Track()
    down = false
    board:Track()
    T.eq({ board.placed.givers.w, board.placed.givers.h }, { 3, 3 })
    -- a preset: the members
    local presets = view:PresetItems()
    T.eq(#presets, 3)
    view.pick, view.pickName = nil, nil -- (an earlier click on a name in the ledger picked someone)
    presets[2].onClick()
    T.eq(Has("balance") and Has("detail") and Has("largest"), true)
    T.eq(Has("ledger"), false)
    T.eq(#view.More.balance.List.items, 4)
    T.eq(view.More.detail.Hint:IsShown(), true)
    -- a click on a member shows their movements beside
    local row = view.More.balance.List.rows[1]
    row.Click:GetScript("OnClick")(row.Click)
    T.eq(view.pick, row.member.key)
    T.eq(view.More.detail.Hint:IsShown(), false)
    T.truthy(#view.More.detail.List.items >= 1, "the member's movements")
    -- a click on a heading sorts
    local heads = view.More.balance.Heads
    heads[1]:GetScript("OnClick")(heads[1])
    T.eq(view.More.balance.sort, "name")
    T.eq(view.More.balance.List.items[1].name, "Au Tsch")
    T.eq(#view.More.largest.List.items, 3)
    -- the overview, with the figures in a row
    presets[3].onClick()
    T.eq(Has("tiles") and Has("givers") and Has("ledger"), true)
    T.truthy(view.More.tiles.Tiles[1].Value:GetText():find("1,234", 1, true) or view.More.tiles.Tiles[1].Value:GetText():find("1234", 1, true),
      view.More.tiles.Tiles[1].Value:GetText())
    -- everything removed: a hint instead of an empty tab
    for _, key in ipairs({ "tiles", "chart", "givers", "ledger", "tabs" }) do board:Remove(key) end
    T.eq(ns.Settings().bank.layout, {})
    T.eq(board.Empty:IsShown(), true)
    -- back to the ledger: nothing is stored for what Guildy ships
    presets[1].onClick()
    T.eq(ns.Settings().bank, nil)
    view.Edit:GetScript("OnClick")(view.Edit)
    T.eq(board.editing, false)
    T.eq(board.defs.ledger.Cover:IsShown(), false)
    T.eq(#view.List.items, 6)
    env.GetCursorPosition = function() return 100, 100 end
    env.IsMouseButtonDown = function() return false end
    T.eq(errors, {})
  end)

  T.it("shares the reading, and a guild member's Guildy takes it in", function()
    Fire("GUILDBANKFRAME_CLOSED")
    RunTimers()
    local messages = Messages("BANK")
    T.truthy(#messages >= 1, "a BANK message was sent")
    local data = messages[#messages]
    T.eq(data.money, 12340000)
    T.eq(#data.logs.money, 3)
    -- the receiving side: the same message arrives at someone who knows nothing yet
    local P = ns.Protocol
    ns.GuildData().bank = nil
    for _, part in ipairs(P.Chunk("b1", P.Encode("BANK", data, "1.6.0"))) do
      Fire("CHAT_MSG_ADDON", "GUILDY", part, "GUILD", "Makira-Farron")
    end
    local bank = ns.GuildData().bank
    T.eq(bank.money, 12340000)
    T.eq(bank.by, "Ran Fred")
    T.eq(#bank.logs.money, 3)
    T.eq(#bank.logs["1"], 2)
    T.eq(ns.Bank.Used(bank.tabs[1]), 3)
    T.eq(bank.mine, {}) -- what the reader may take is theirs alone
    -- a second time: nothing doubles
    for _, part in ipairs(P.Chunk("b2", P.Encode("BANK", data, "1.6.0"))) do
      Fire("CHAT_MSG_ADDON", "GUILDY", part, "GUILD", "Au-Tsch")
    end
    T.eq(#bank.logs.money, 3)
    T.eq(errors, {})
  end)

  T.it("tells the guild what it knows after login and offers it to who knows less", function()
    local summaries = Messages("SUM")
    T.truthy(#summaries >= 1, "a summary was sent")
    sent = {}
    ns.Sync.SendSummary()
    T.eq(Messages("SUM")[1].b.n, 6)
    sent = {}
    local P = ns.Protocol
    for _, part in ipairs(P.Chunk("s1", P.Encode("SUM", { d = {}, b = { at = 5, ts = 5, n = 0 } }, "1.6.0"))) do
      Fire("CHAT_MSG_ADDON", "GUILDY", part, "GUILD", "Au-Tsch")
    end
    RunTimers()
    T.eq(#Messages("BANK"), 1)
    -- someone who knows as much gets no offer
    sent = {}
    local digest = ns.Bank.Digest(ns.GuildData().bank)
    for _, part in ipairs(P.Chunk("s2", P.Encode("SUM", { d = {}, b = digest }, "1.6.0"))) do
      Fire("CHAT_MSG_ADDON", "GUILDY", part, "GUILD", "Au-Tsch")
    end
    RunTimers()
    T.eq(#Messages("BANK"), 0)
    T.eq(errors, {})
  end)

  T.it("shows no real name while names are made up for pictures", function()
    env.SlashCmdList.GUILDY("shots anon")
    world.calls.texts = {}
    ns.UI.SelectTab("bank")
    local shown = table.concat(world.calls.texts, " ;; ")
    world.calls.texts = nil
    env.SlashCmdList.GUILDY("shots anon")
    T.truthy(#shown > 100, "the tab was drawn")
    for _, real in ipairs({ "Makira", "Farron", "Au Tsch", "Lightspark", "Ran Fred" }) do
      T.truthy(not shown:find(real, 1, true), real .. " shown")
    end
    T.eq(errors, {})
  end)
end)

-- Which event says that the bank opened differs between clients: each of them starts a visit
T.describe("Guild bank, however the client says it opened", function()
  local function Visit(open)
    local other = dofile(T.testsDir .. "/wow.lua")(T, { setup = Setup })
    other.Fire("ADDON_LOADED", "Guildy")
    other.Fire("PLAYER_LOGIN")
    other.Fire("GUILD_ROSTER_UPDATE")
    other.RunTimers()
    open(other)
    other.RunTimers()
    return other
  end

  T.it("reads when the interaction manager shows the guild banker", function()
    local other = Visit(function(w) w.Fire("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", 10) end)
    T.eq(#other.ns.GuildData().bank.logs.money, 3)
    T.eq(other.ns.GameBank.IsOpen(), true)
    other.Fire("PLAYER_INTERACTION_MANAGER_FRAME_HIDE", 10)
    T.eq(other.ns.GameBank.IsOpen(), false)
    T.eq(other.errors, {})
  end)

  T.it("asks again for a log that came back empty", function()
    queried = {}
    local other = Visit(function(w)
      w.env.GetNumGuildBankMoneyTransactions = function() return 0 end
      w.Fire("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", 10)
    end)
    local asks = 0
    for _, query in ipairs(queried) do
      if query == "log7" then asks = asks + 1 end
    end
    T.eq(asks, 7) -- on opening and six times more; the tabs' logs had entries and are asked once
    T.eq(#queried, 13)
    T.eq(other.errors, {})
  end)

  T.it("asks for the logs again when gold or items move during the visit", function()
    queried = {}
    local other = Visit(function(w) w.Fire("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", 10) end)
    local function Asked(what)
      local count = 0
      for _, query in ipairs(queried) do
        if query == what then count = count + 1 end
      end
      return count
    end
    T.eq(Asked("log7"), 1)
    -- a deposit: the money changes at once, the log only once it was asked for again
    money[#money + 1] = { "deposit", "Ran-Fred", 100, 0, 0, 0, 0 }
    other.Fire("GUILDBANK_UPDATE_MONEY")
    other.RunTimers()
    T.eq(Asked("log7"), 3) -- a moment later, and once more
    T.eq(Asked("log1"), 1)
    other.Fire("GUILDBANKLOG_UPDATE")
    other.RunTimers()
    T.eq(#other.ns.GuildData().bank.logs.money, 4)
    money[#money] = nil
    -- an item moved: the logs of the tabs
    other.Fire("GUILDBANKBAGSLOTS_CHANGED")
    other.RunTimers()
    T.eq(Asked("log1"), 3)
    T.eq(Asked("log2"), 3)
    T.eq(Asked("log7"), 3)
    T.eq(other.errors, {})
  end)

  T.it("does nothing at login, when the client sends news about a bank that is not open", function()
    atBanker = false
    local other = Visit(function(w)
      w.env.GetGuildBankMoney = function() return 0 end
      w.Fire("GUILDBANK_UPDATE_MONEY")
      w.Fire("GUILDBANK_UPDATE_WITHDRAWMONEY")
      w.Fire("GUILDBANK_UPDATE_TABS")
      w.Fire("GUILDBANKLOG_UPDATE")
      w.Fire("GUILDBANKBAGSLOTS_CHANGED")
    end)
    atBanker = true
    T.eq(other.ns.GuildData().bank, nil)
    T.eq(other.ns.GameBank.IsOpen(), false)
    T.eq(other.ns.UI.IsShown(), false)
    T.eq(other.errors, {})
  end)

  T.it("ignores other windows of the interaction manager", function()
    local other = Visit(function(w) w.Fire("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", 8) end)
    T.eq(other.ns.GuildData().bank, nil)
  end)

  T.it("reads when only news about the bank arrive", function()
    local other = Visit(function(w) w.Fire("GUILDBANKLOG_UPDATE") end)
    T.eq(#other.ns.GuildData().bank.logs.money, 3)
    T.eq(other.errors, {})
  end)

  T.it("reads with Blizzard's bank window hidden: bag addons show their own", function()
    local other = Visit(function(w)
      w.env.GuildBankFrame = w.env.CreateFrame("Frame", "GuildBankFrame") -- loaded, never shown
      w.Fire("GUILDBANK_UPDATE_MONEY")
    end)
    T.eq(other.ns.GuildData().bank.money, 12340000)
    T.eq(#other.ns.GuildData().bank.logs.money, 3)
    T.eq(other.errors, {})
  end)

  T.it("reads nothing when the bank closes, and asks anew at the next visit", function()
    queried = {}
    local other = Visit(function(w) w.Fire("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", 10) end)
    local first = #queried
    local bank = other.ns.GuildData().bank
    -- the game answers nonsense about a closed bank: none of it is kept
    other.env.GetGuildBankMoney = function() return 0 end
    other.Fire("PLAYER_INTERACTION_MANAGER_FRAME_HIDE", 10)
    other.Fire("GUILDBANKFRAME_CLOSED")
    other.RunTimers()
    T.eq(bank.money, 12340000)
    T.eq(other.ns.GameBank.IsOpen(), false)
    other.env.GetGuildBankMoney = function() return 12340000 end
    other.Fire("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", 10)
    other.Fire("GUILDBANKFRAME_OPENED") -- said twice: asked once
    other.RunTimers()
    T.eq(#queried, first * 2)
    T.eq(#bank.logs.money, 3)
    T.eq(other.errors, {})
  end)

  T.it("asks anew when the closing was never said and news arrive much later", function()
    queried = {}
    local other = Visit(function(w) w.Fire("GUILDBANKLOG_UPDATE") end)
    local first = #queried
    other.Fire("GUILDBANKLOG_UPDATE")
    other.RunTimers()
    T.eq(#queried, first) -- the same visit
    clock = clock + 3600
    other.Fire("GUILDBANKLOG_UPDATE")
    other.RunTimers()
    T.eq(#queried, first * 2)
    T.eq(other.errors, {})
  end)

  T.it("says what it sees on /guildy bank and keeps no reading without a reader", function()
    local other = Visit(function(w)
      w.env.UnitName = function() return "" end
      w.Fire("GUILDBANKLOG_UPDATE")
    end)
    T.eq(other.ns.GuildData().bank, nil)
    other.env.UnitName = function() return "Ran", "Fred" end
    other.env.SlashCmdList.GUILDY("bank")
    other.RunTimers()
    T.eq(other.ns.GuildData().bank.by, "Ran Fred")
    other.env.SlashCmdList.GUILDY("bank reset")
    T.eq(other.ns.GuildData().bank, nil)
    T.eq(other.ns.GameBank.IsOpen(), false)
    other.Fire("GUILDBANKLOG_UPDATE") -- the next news about the bank reads it anew
    other.RunTimers()
    T.eq(#other.ns.GuildData().bank.logs.money, 3)
    T.eq(other.errors, {})
  end)
end)

-- Guildy opens on its Bank tab with the guild bank, without Blizzard's guild window
T.describe("Guild bank opens Guildy", function()
  local function Login()
    local other = dofile(T.testsDir .. "/wow.lua")(T, { setup = Setup })
    other.Fire("ADDON_LOADED", "Guildy")
    other.Fire("PLAYER_LOGIN")
    other.Fire("GUILD_ROSTER_UPDATE")
    other.RunTimers()
    return other
  end

  T.it("shows on the Bank tab at the banker and closes with the bank", function()
    local other = Login()
    local UI = other.ns.UI
    T.eq(UI.IsShown(), false)
    other.Fire("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", 10)
    other.RunTimers()
    T.eq(UI.IsShown(), true)
    T.eq(UI.Current(), "bank")
    T.eq(UI.AtBank(), true)
    T.eq(UI.frame:GetParent(), other.env.UIParent)
    T.eq(#UI.TabView("bank").List.items, 6)
    -- the other tabs are there to read
    for _, key in ipairs({ "members", "overview", "fame", "professions", "info", "ranks", "chat", "bank" }) do
      UI.SelectTab(key)
      T.eq(UI.Current(), key)
    end
    T.eq(UI.AtBank(), true)
    other.Fire("PLAYER_INTERACTION_MANAGER_FRAME_HIDE", 10)
    T.eq(UI.IsShown(), false)
    T.eq(UI.AtBank(), false)
    -- J afterwards: the whole window, on the chat as after every login
    other.env.CommunitiesFrame:Show()
    T.eq(UI.Current(), "chat")
    T.eq(UI.frame:GetParent(), other.env.CommunitiesFrame)
    T.eq(other.errors, {})
  end)

  T.it("becomes the whole window when J is pressed at the banker", function()
    local other = Login()
    local UI = other.ns.UI
    other.Fire("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", 10)
    other.RunTimers()
    other.env.CommunitiesFrame:Show()
    T.eq(UI.AtBank(), false)
    T.eq(UI.Current(), "bank")
    other.Fire("PLAYER_INTERACTION_MANAGER_FRAME_HIDE", 10)
    T.eq(UI.IsShown(), true) -- the bank no longer closes it
    T.eq(other.errors, {})
  end)

  T.it("selects the Bank tab when Guildy is already open", function()
    local other = Login()
    other.env.CommunitiesFrame:Show()
    T.eq(other.ns.UI.Current(), "chat")
    other.Fire("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", 10)
    other.RunTimers()
    T.eq(other.ns.UI.Current(), "bank")
    T.eq(other.ns.UI.AtBank(), false)
    T.eq(other.errors, {})
  end)

  T.it("stays closed when the option is off, and still reads the bank", function()
    local other = Login()
    other.env.CommunitiesFrame:Show()
    other.ns.UI.ShowOptions("bank")
    local check = other.ns.UI.Options().Panels.bank.Open
    T.eq(check:GetChecked(), true)
    check:SetChecked(false)
    check:GetScript("OnClick")(check)
    T.eq(other.ns.Settings().bankOpen, false)
    other.ns.UI.Hide()
    other.Fire("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", 10)
    other.RunTimers()
    T.eq(other.ns.UI.IsShown(), false)
    T.eq(#other.ns.GuildData().bank.logs.money, 3)
    T.eq(other.errors, {})
  end)
end)
