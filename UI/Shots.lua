-- /guildy shots: walks through every view of Guildy and takes a screenshot of each, for the reference
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

local function Options(key)
  return function()
    UI.SelectTab("chat")
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
  { "12-account", Tab("account") },
  { "13-communities", Tab("communities") },
  { "14-character", function()
    UI.HideOptions()
    UI.SelectTab("members")
    UI.ShowMember(ns.Roster.Me())
  end },
  { "15-options-general", Options("general") },
  { "16-options-chat", Options("chat") },
  { "17-options-members", Options("members") },
  { "18-options-fame", Options("fame") },
  { "19-options-professions", Options("professions") },
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

local STEP = 2 -- seconds per view: shown, one second to settle, the picture, one second to the next
local running

function UI.TakeShots()
  local shoot = rawget(_G, "Screenshot")
  if running then return end
  if not shoot then
    ns.Print("shots: this client has no Screenshot()")
    return
  end
  if not UI.IsShown() then
    ns.Print("shots: open Guildy first (J)")
    return
  end
  running = true
  -- the "screen captured" line of one picture would be in the next one
  local status = rawget(_G, "ActionStatus")
  if status and status.UnregisterEvent then status:UnregisterEvent("SCREENSHOT_SUCCEEDED") end
  local back = UI.Current()
  local hadBackdrop = backdrop and backdrop:IsShown()
  Backdrop(true)
  ns.Print(("shots: %d pictures, about %d seconds. Leave mouse and keyboard alone."):format(#UI.SHOTS, #UI.SHOTS * STEP))
  for i, shot in ipairs(UI.SHOTS) do
    C_Timer.After((i - 1) * STEP, function()
      ns.SafeCall(shot[2])
      local tip = rawget(_G, "GameTooltip")
      if tip then tip:Hide() end
    end)
    C_Timer.After((i - 1) * STEP + 1, function()
      local tip = rawget(_G, "GameTooltip")
      if tip then tip:Hide() end -- of whatever the resting mouse is on
      ns.SafeCall(shoot)
    end)
  end
  C_Timer.After(#UI.SHOTS * STEP, function()
    running = nil
    if status and status.RegisterEvent then status:RegisterEvent("SCREENSHOT_SUCCEEDED") end
    UI.HideOptions()
    if not hadBackdrop then Backdrop(false) end
    if back then UI.SelectTab(back) end
    ns.Print("shots: done. Collect them with: python media/gallery/collect.py")
  end)
end
