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
function UI.TakeShots(onDone)
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
  ns.Print(("shots: %d pictures, about %d seconds. Leave mouse and keyboard alone."):format(#UI.SHOTS, #UI.SHOTS * STEP))
  for i, shot in ipairs(UI.SHOTS) do
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
  C_Timer.After(#UI.SHOTS * STEP, function()
    running = nil
    if status and status.RegisterEvent then status:RegisterEvent("SCREENSHOT_SUCCEEDED") end
    UI.HideOptions()
    UI.SetShotPhase(nil)
    if not hadBackdrop then Backdrop(false) end
    if not wasAnonymous then Anonymous(false) end
    if back then UI.SelectTab(back) end
    if this.stopped then return end
    if onDone then
      onDone()
    else
      ns.Print("shots: done. Collect them with: python media/gallery/collect.py")
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
