-- /guildy shots: walks through every view of Guildy and takes a screenshot of each, with made-up
-- names, notes and chat (Core/Anon.lua) in front of a plain backdrop, for the reference
-- screenshots the gallery images are made from (media/gallery/collect.py picks them up from the
-- game's Screenshots folder and names them after the list below). Guildy has to be open (J).
-- The game names a screenshot after the second it was taken in, so the views are two seconds apart.
local _, ns = ...
local UI = ns.UI

local function Tab(key)
  return function()
    UI.HideOptions()
    UI.SelectTab(key)
  end
end

local function Fame(page)
  return function()
    UI.HideOptions()
    UI.SelectTab("fame")
    local view = UI.TabView("fame")
    if not view then return end
    view.page, view.mode = page, "home"
    if view.Pages then view.Pages:SetValue(page) end
    view:Refresh()
  end
end

-- An options tab next to the tab it is about, so the picture shows what the options change
local function Options(key, tab)
  return function()
    UI.SelectTab(tab)
    UI.ShowOptions(key)
  end
end

-- name of the picture (collect.py reads this list), then what shows it
UI.SHOTS = {
  { "01-chat", Tab("chat") },
  { "02-members", Tab("members") },
  { "03-overview", Tab("overview") },
  { "04-fame-general", Fame("general") },
  { "05-fame-economy", Fame("economy") },
  { "06-fame-dungeons", Fame("dungeons") },
  { "07-fame-reputation", Fame("reputation") },
  { "08-fame-pvp", Fame("pvp") },
  { "09-professions", Tab("professions") },
  { "10-info", Tab("info") },
  { "11-ranks", Tab("ranks") },
  { "13-communities", Tab("communities") },
  { "14-character", function()
    UI.HideOptions()
    UI.SelectTab("members")
    UI.ShowMember(ns.Roster.Me())
  end },
  { "15-options-general", Options("general", "members") }, -- where a member's tooltip stands
  { "16-options-chat", Options("chat", "chat") },
  { "17-options-members", Options("members", "members") },
  { "18-options-fame", function()
    Fame("general")() -- the page the options open on
    UI.ShowOptions("fame")
  end },
  { "19-options-professions", Options("professions", "professions") },
  -- the endgame view of the overview, whatever the guild and the setting say (the run takes it back)
  { "20-overview-endgame", function()
    UI.HideOptions()
    UI.SelectTab("overview")
    UI.SetShotPhase("endgame")
  end },
}

-- /guildy shots bank ------------------------------------------------------------------------------------
-- The Bank tab in every state worth a look, for checking it in the game: its presets, edit mode, the
-- picker with a box shown at a free place, compact columns, a tab that scrolls, the empty tab. The run
-- shows a made-up bank (members of the roster, so their names are made up like everywhere) and its own
-- layouts through UI.bankShot, which the tab reads instead of the stored bank and the saved layout:
-- nothing of it is kept.
local SAMPLE_ITEMS = { { 13446, "Major Healing Potion" }, { 13444, "Major Mana Potion" }, { 13452, "Elixir of the Mongoose" },
  { 12210, "Roast Raptor" }, { 15564, "Rugged Armor Kit" }, { 13463, "Dreamfoil" }, { 8170, "Rugged Leather" } }
local SAMPLE_TABS = { { "Consumables", "INV_Potion_54", 71 }, { "Crafting", "Trade_BlackSmithing", 44 },
  { "Herbs & Ore", "Trade_Herbalism", 88 }, { "Cloth & Leather", "Trade_Tailoring", 23 } }

local function SampleBank()
  local seed = 41
  local function Random(n) -- 1..n, the same numbers every run
    seed = (seed * 1103515245 + 12345) % 2147483648
    return math.floor(seed / 2147483648 * n) + 1
  end
  local now = ns.Now()
  local names = {}
  for _, m in ipairs(ns.Roster.Members()) do
    if #names < 24 then names[#names + 1] = ns.Names.Normalize(m.fullName or m.name) end
  end
  if #names == 0 then names[1] = ns.PlayerName() end
  local reader = ns.PlayerName()
  local bank = { v = 1, at = now - 2 * 3600, by = reader, cost = 5000000, tabs = {}, logs = { money = {} }, samples = {}, mine = {} }
  for index, tab in ipairs(SAMPLE_TABS) do
    local slots = {}
    for slot = 1, tab[3] do
      local item = SAMPLE_ITEMS[(slot + index) % #SAMPLE_ITEMS + 1]
      slots[slot] = { i = "item:" .. item[1], id = item[1], nm = item[2], n = 20 }
    end
    bank.tabs[index] = { name = tab[1], icon = "Interface\\Icons\\" .. tab[2], at = bank.at, slots = slots }
    bank.logs[tostring(index)] = {}
  end
  -- 150 movements over 30 days, oldest first; officers (the first names) take, everyone gives
  local money, events = 8000000, {}
  for n = 1, 150 do
    events[n] = math.floor(30 * 86400 * (1 - ((n - 1) / 150) ^ 0.6)) + Random(3000)
  end
  table.sort(events, function(x, y) return x > y end)
  local bought = false
  for _, age in ipairs(events) do
    local who = names[Random(#names)]
    local ts, roll = now - age - 2 * 3600, Random(100)
    local entry = { w = who, ts = ts, at = bank.at, by = reader }
    if roll <= 62 then
      local item = SAMPLE_ITEMS[Random(#SAMPLE_ITEMS)]
      local tab = Random(#SAMPLE_TABS)
      entry.k = Random(100) <= 58 and "deposit" or "withdraw"
      entry.i, entry.id, entry.nm, entry.n, entry.a = "item:" .. item[1], item[1], item[2], ({ 1, 2, 5, 10, 20, 20 })[Random(6)], tab
      table.insert(bank.logs[tostring(tab)], entry)
    else
      if not bought and age < 11 * 86400 then
        bought = true
        entry.k, entry.c, entry.w = "buyTab", 2500000, names[1]
      elseif roll <= 80 then
        entry.k, entry.c = "deposit", ({ 5, 10, 10, 20, 25, 50, 50, 100, 220 })[Random(9)] * 10000
      elseif roll <= 88 then
        entry.k, entry.c, entry.w = "withdraw", ({ 5, 10, 15, 20, 40 })[Random(5)] * 10000, names[Random(math.min(4, #names))]
      else
        entry.k, entry.c = "repair", Random(600) * 100 + Random(99)
      end
      money = money + (entry.k == "deposit" and entry.c or -entry.c)
      table.insert(bank.logs.money, entry)
    end
  end
  bank.money = math.max(0, money)
  bank.samples[1] = { ts = bank.at, c = bank.money }
  local mine = { at = bank.at, gold = 380000, tabs = { { view = true, deposit = true, limit = 10, left = 8 },
    { view = true, deposit = true, limit = 10, left = 10 }, { view = true, deposit = true, limit = 5, left = 3 },
    { view = true, deposit = false, limit = 0, left = 0 } } }
  return bank, mine
end

local function Layout(...)
  local layout = {}
  for _, item in ipairs({ ... }) do
    layout[#layout + 1] = { k = item[1], x = item[2], y = item[3], w = item[4], h = item[5], o = item[6] }
  end
  return layout
end

-- Shows the Bank tab with a layout of the run (nil: the ledger preset), in edit mode or not
local function Bank(layout, editing, after, extra)
  return function()
    UI.HideOptions()
    ns.Widgets.CloseMenu()
    local bank, mine = SampleBank()
    UI.SelectTab("bank")
    local view = UI.TabView("bank")
    if not (view and view.board) then return end
    view.board:SetEditing(false) -- (closes the picker and what it showed of the picture before)
    local rows = view.board:Rows()
    UI.bankShot = { bank = bank, mine = mine, layout = layout }
    for key, value in pairs(extra or {}) do UI.bankShot[key] = value end
    view.board:RowsChanged(rows) -- a layout with more rows: the window as tall as it would be
    view.filter, view.pick, view.pickName = {}, nil, nil
    view.board:SetEditing(editing == true)
    if view.board.Scroll.SetVerticalScroll then view.board.Scroll:SetVerticalScroll(0) end
    view:Refresh()
    if after then after(view, view.board) end
  end
end

local NO_ACCESS = Layout({ "total", 0, 0, 3, 4 }, { "tabs", 0, 4, 3, 4 }, { "chart", 3, 0, 9, 4 }, { "ledger", 3, 4, 9, 8 })
local function OpenPicker(_, board)
  local slot = board:Slots()[1]
  if slot then board:Pick(slot) end
end

UI.BANK_SHOTS = {
  { "bank-01-ledger", Bank(nil) },
  { "bank-02-seven-days", Bank(nil, false, nil, { days = 7 }) },
  { "bank-03-one-member", Bank(nil, false, function(view)
    local row = view.List.rows[1]
    if row and row.entry and row.entry.w then row.Pick:GetScript("OnClick")(row.Pick) end
  end) },
  { "bank-04-edit", Bank(nil, true) },
  { "bank-05-picker", Bank(NO_ACCESS, true, OpenPicker) },
  { "bank-06-preview", Bank(NO_ACCESS, true, function(view, board)
    OpenPicker(view, board)
    local row = board:PickRows()[2]
    if row then row:GetScript("OnEnter")(row) end
  end) },
  { "bank-07-box-options", Bank(nil, true, function(_, board)
    local gear = board.defs.ledger.Cover and board.defs.ledger.Cover.Gear
    if gear then gear:GetScript("OnClick")(gear) end
  end) },
  { "bank-08-members", Bank(UI.BANK_PRESETS.members, false, function(view)
    local row = view.More.balance.List.rows[1]
    if row then row.Click:GetScript("OnClick")(row.Click) end
  end) },
  { "bank-09-overview", Bank(UI.BANK_PRESETS.overview) },
  { "bank-10-compact", Bank(Layout({ "ledger", 0, 0, 6, 13, { tab = false, after = false } },
    { "balance", 6, 0, 6, 8, { rank = false, items = false } }, { "tiles", 6, 8, 6, 2, { repairs = false, slots = false } },
    { "givers", 6, 10, 3, 2 + 1 }, { "largest", 9, 10, 3, 3 })) },
  { "bank-11-tall", Bank(Layout({ "tiles", 0, 0, 12, 2 }, { "chart", 0, 2, 12, 4 }, { "ledger", 0, 6, 12, 6 },
    { "balance", 0, 12, 8, 6 }, { "detail", 8, 12, 4, 6 })) },
  { "bank-12-edit-free-places", Bank(Layout({ "tiles", 0, 0, 12, 2 }, { "chart", 0, 2, 8, 4 }, { "ledger", 0, 6, 12, 6 }), true) },
  { "bank-13-nothing-read", Bank(nil, false, nil, { empty = true }) },
  { "bank-14-no-boxes", Bank({}) },
  { "bank-15-options", function()
    Bank(nil)()
    UI.ShowOptions("bank")
  end },
}

-- The end of the bank pictures: the stored bank and the saved layout again
local heightBefore -- the window's height before the bank pictures (a tall layout makes it taller)

function UI.EndBankShots()
  if not UI.bankShot then return end
  UI.bankShot = nil
  ns.Widgets.CloseMenu()
  local view = UI.TabView("bank")
  if view and view.board then
    view.filter, view.pick, view.pickName = {}, nil, nil
    view.board:SetEditing(false)
  end
  if heightBefore and UI.frame then UI.GrowWindow(heightBefore - UI.frame:GetHeight()) end
  heightBefore = nil
  if view and view.Refresh then view:Refresh() end
end

function UI.TakeBankShots()
  heightBefore = UI.frame and UI.frame:GetHeight() or nil
  return UI.TakeShots(nil, UI.BANK_SHOTS)
end

-- A plain dark sheet over the whole screen, right behind Guildy: the pictures show the window alone,
-- without the game world, the action bars and the game's own chat. It sits one level below Guildy's
-- window in its strata (one level below Blizzard's guild window, action bars and quest tracker still
-- showed: first run, 2026-11-10); Guildy's options are in a higher strata. Blizzard's own parts shown
-- inside Guildy (the rank editor, the member panel) lie below Guildy and are covered too.
-- /guildy shots backdrop switches it on and off for pictures taken by hand.
local backdrop
local function Backdrop(on)
  if not on then
    if backdrop then backdrop:Hide() end
    return
  end
  if not backdrop then
    backdrop = CreateFrame("Frame", nil, UIParent)
    backdrop:SetAllPoints(UIParent)
    backdrop.Fill = backdrop:CreateTexture(nil, "BACKGROUND")
    -- beyond UIParent's edges too (an ultrawide screen, a UI scale that leaves a margin)
    backdrop.Fill:SetPoint("TOPLEFT", -2000, 2000)
    backdrop.Fill:SetPoint("BOTTOMRIGHT", 2000, -2000)
    backdrop.Fill:SetColorTexture(0.07, 0.07, 0.08, 1)
    backdrop:EnableMouse(true) -- nothing behind it lights up under the mouse
  end
  local window = UI.frame
  if window and window.GetFrameStrata then
    backdrop:SetFrameStrata(window:GetFrameStrata())
    backdrop:SetFrameLevel(math.max(0, (window:GetFrameLevel() or 1) - 1))
  end
  backdrop:Show()
end

function UI.ToggleShotBackdrop()
  Backdrop(not (backdrop and backdrop:IsShown()))
end

-- Made-up names, notes and chat on or off: the roster is read again and every view drawn anew
local function Anonymous(on)
  if ns.Anon.on == (on and true or false) then return end
  ns.Anon.Enable(on)
  ns.Roster.Scan()
  ns.Fire("GUILD") -- the guild name in the title
  ns.Fire("CHAT")
  ns.Fire("COMMUNITY")
end

-- /guildy shots anon: the same for pictures taken by hand
function UI.ToggleShotNames()
  Anonymous(not ns.Anon.on)
  ns.Print("shots: made-up names " .. (ns.Anon.on and "on" or "off"))
end

local STEP = 2 -- seconds per view: shown, one second to settle, the picture, one second to the next
local running -- the pictures being taken: { stopped }

-- onDone: called after the last picture and the clean-up, not when the pictures were stopped.
-- True when the pictures were started.
function UI.TakeShots(onDone, shots)
  shots = shots or UI.SHOTS
  local shoot = rawget(_G, "Screenshot")
  if running then return false end
  if not shoot then
    ns.Print("shots: this client has no Screenshot()")
    return false
  end
  if not UI.IsShown() then
    ns.Print("shots: open Guildy first (J)")
    return false
  end
  local this = {}
  running = this
  -- the "screen captured" line of one picture would be in the next one
  local status = rawget(_G, "ActionStatus")
  if status and status.UnregisterEvent then status:UnregisterEvent("SCREENSHOT_SUCCEEDED") end
  local back = UI.Current()
  local hadBackdrop = backdrop and backdrop:IsShown()
  local wasAnonymous = ns.Anon.on
  Backdrop(true)
  Anonymous(true)
  ns.Print(("shots: %d pictures, about %d seconds. Leave mouse and keyboard alone."):format(#shots, #shots * STEP))
  for i, shot in ipairs(shots) do
    C_Timer.After((i - 1) * STEP, function()
      if this.stopped then return end
      UI.fromTimer = true -- no click behind this: nothing protected (community avatars)
      ns.SafeCall(shot[2])
      UI.fromTimer = nil
      local tip = rawget(_G, "GameTooltip")
      if tip then tip:Hide() end
    end)
    C_Timer.After((i - 1) * STEP + 1, function()
      if this.stopped then return end
      local tip = rawget(_G, "GameTooltip")
      if tip then tip:Hide() end -- of whatever the resting mouse is on
      ns.SafeCall(shoot)
    end)
  end
  C_Timer.After(#shots * STEP, function()
    running = nil
    if status and status.RegisterEvent then status:RegisterEvent("SCREENSHOT_SUCCEEDED") end
    UI.HideOptions()
    UI.SetShotPhase(nil)
    UI.EndBankShots()
    if not hadBackdrop then Backdrop(false) end
    if not wasAnonymous then Anonymous(false) end
    if back then UI.SelectTab(back) end
    if this.stopped then return end
    if onDone then
      onDone()
    else
      ns.Print("shots: done. Collect them with: python media/gallery/collect.py" .. (shots == UI.BANK_SHOTS and " <folder> bank" or ""))
    end
  end)
  return true
end

-- /guildy shots all -------------------------------------------------------------------------------------
-- Every view in every language, at the smallest window size: the end-to-end check of the translations
-- (media/e2e/collect.py files the pictures by language). Guildy's language only changes with a reload
-- of the interface, so the run goes language by language over reloads and keeps its state in
-- GuildyDB.shotRun (Core/ShotRun.lua). The player does two things per language: type /reload (the client
-- blocks a reload that addon code starts from a timer) and press J (Guildy cannot open itself, UI.Show:
-- only Blizzard's own code may open the guild window).
local WAIT_OPEN, WAIT_ROSTER = 120, 20 -- seconds for the player to press J, and for the guild roster

local function Run()
  local db = ns.DB()
  return db and db.shotRun
end

local function ApplySize(width, height)
  if UI.frame and width and height then UI.frame:SetSize(width, height) end -- not saved: only the grip saves
end


-- The end of a run, finished, stopped or given up: language and size as before
local function Finish(message)
  local run = Run()
  if not run then return end
  local settings = ns.Settings()
  ns.ShotRun.Restore(run, settings)
  ns.DB().shotRun = nil
  if running then running.stopped = true end
  UI.SetShotPhase(nil)
  ApplySize(settings.width, settings.height)
  ns.Print(message)
  local client = rawget(_G, "GetLocale") and GetLocale() or nil
  if ns.Locale.Resolve(settings.language, client) ~= ns.Locale.current then
    ns.Print("shots: type /reload to get your language back.")
  end
end

-- Looks once a second, up to `seconds` times; the run counts as alive meanwhile
local function WaitFor(check, seconds, onYes, onNo)
  local run = Run()
  local function Look(left)
    if Run() ~= run then return end -- stopped meanwhile
    run.touched = ns.Now()
    if check() then
      onYes()
    elseif left <= 0 then
      onNo()
    else
      C_Timer.After(1, function() Look(left - 1) end)
    end
  end
  Look(seconds)
end

local NextLanguage

-- The pictures of the language in force
local function ShootLanguage()
  local name = ns.Locale.NAMES[ns.Locale.current] or ns.Locale.current
  if not UI.IsShown() then ns.Print(("shots: %s. Open Guildy (J) to go on."):format(name)) end
  WaitFor(UI.IsShown, WAIT_OPEN, function()
    WaitFor(function() return #ns.Roster.Members() > 0 end, WAIT_ROSTER, function()
      local run = Run()
      ApplySize(UI.MIN_W, UI.MIN_H)
      C_Timer.After(2, function() -- the views lay themselves out at the new size
        if Run() ~= run then return end
        if not UI.TakeShots(NextLanguage) then Finish("shots: stopped, the pictures could not be taken.") end
      end)
    end, function() Finish("shots: stopped, the guild roster did not arrive.") end)
  end, function() Finish("shots: stopped, Guildy was not opened.") end)
end

function NextLanguage()
  local run = Run()
  if not run then return end
  local code = ns.ShotRun.Next(run, ns.Now())
  if not code then
    Finish("shots: every language done. Collect them with: python media/e2e/collect.py")
    return
  end
  ns.Settings().language = code
  if code == ns.Locale.current then
    ShootLanguage()
  else
    ns.Print(("shots: %s is next. Type /reload, then press J."):format(ns.Locale.NAMES[code] or code))
  end
end

function UI.TakeAllShots()
  if Run() or running then
    ns.Print("shots: a run is on. /guildy shots stop ends it.")
    return
  end
  if not rawget(_G, "Screenshot") then
    ns.Print("shots: this client has no Screenshot()")
    return
  end
  local languages = ns.Locale.Languages()
  ns.DB().shotRun = ns.ShotRun.Start(ns.Settings(), languages, ns.Now())
  ns.Print(("shots: %d languages, about %d minutes."):format(
    #languages, math.ceil(#languages * (#UI.SHOTS * STEP + 15) / 60)))
  NextLanguage()
end

-- After the reload of a run (PLAYER_LOGIN): on with the language now in force
function UI.ResumeShots()
  if Run() then ShootLanguage() end
end

function UI.StopShots()
  if Run() then
    Finish("shots: stopped.")
  elseif running then
    running.stopped = true
    UI.SetShotPhase(nil)
    ns.Print("shots: stopped.")
  else
    ns.Print("shots: no run is on.")
  end
end
