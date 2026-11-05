-- Guild management (invite, remove, rank, notes, MOTD, guild info) is reserved for Blizzard's UI on
-- Forever. Blocked: addon calls, macros (/run is force-tainted), and any Blizzard window or chat input
-- an addon touched first. What stays clean is a real click on a Blizzard button: a secure action button
-- of type "click" runs that button's own OnClick without any addon or macro code in between.
--
-- So Guildy's action buttons get such a secure button laid over them while the mouse is on them (out
-- of combat). It clicks Blizzard's guild "Invite member" button (Blizzard's invite dialog opens, Guildy
-- then fills in the name) or the guild micro button (Blizzard's guild window opens for everything else).
-- The overlay is parented to UIParent and placed by absolute coordinates, never anchored to Guildy's
-- frames, so the Guildy window stays unprotected and can close in combat.
local _, ns = ...
local W = ns.Widgets
local UI = ns.UI

local Action = {}
UI.Action = Action

local INVITE_POPUPS = { "ADD_GUILDMEMBER", "ADD_GUILDMEMBER_WITH_FINDER_LINK" }

-- Blizzard's guild invite button, when the communities window is loaded with the guild selected
local function BlizzardInviteButton()
  local frame = rawget(_G, "CommunitiesFrame")
  local button = frame and frame.InviteButton
  if not button or not button.IsEnabled or not button:IsEnabled() then return nil end
  local guildClub = C_Club and ns.Try(C_Club.GetGuildClubId)
  local selected = frame.GetSelectedClubId and ns.Try(frame.GetSelectedClubId, frame)
  if not guildClub or selected ~= guildClub then return nil end
  return button
end

local function FillInviteName(name)
  if not name or name == "" then return end
  local find = rawget(_G, "StaticPopup_FindVisible")
  if not find then return end
  for _, which in ipairs(INVITE_POPUPS) do
    local dialog = find(which)
    if dialog then
      local box = (dialog.GetEditBox and dialog:GetEditBox()) or dialog.editBox
      if box then
        box:SetText(ns.Names.ToServer(name))
        box:SetFocus()
      end
      return
    end
  end
end

-- Blizzard's guild window (everything Guildy can't do itself)
function Action.BlizzardWindow()
  local micro = rawget(_G, "GuildMicroButton")
  if not micro then return nil end
  return { click = micro, after = function()
    ns.UI.Hide()
    ns.Print(ns.L.BLIZZARD_OPENED)
  end }
end

-- Blizzard's invite dialog with the name filled in; falls back to Blizzard's guild window until that
-- window was opened once (its invite button exists only then)
function Action.Invite(name)
  local button = BlizzardInviteButton()
  if button then
    return { click = button, after = function() FillInviteName(name) end }
  end
  local window = Action.BlizzardWindow()
  if window then
    window.after = function()
      ns.UI.Hide()
      ns.Print(ns.L.INVITE_FIRST_TIME)
    end
  end
  return window
end

-- The overlay --------------------------------------------------------------------------------------

local overlay

local function Overlay()
  if overlay then return overlay end
  overlay = CreateFrame("Button", "GuildySecureOverlay", UIParent, "SecureActionButtonTemplate")
  overlay:SetFrameStrata("TOOLTIP")
  overlay:RegisterForClicks("AnyUp", "AnyDown")
  overlay:SetAttribute("type", "click")
  overlay:SetHighlightTexture("Interface\\Buttons\\UI-Panel-Button-Highlight", "ADD")
  overlay:SetScript("OnLeave", function(self)
    GameTooltip:Hide()
    if not InCombatLockdown() then self:Hide() end
  end)
  overlay:SetScript("OnEnter", function(self)
    if self.tooltip then
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      GameTooltip:SetText(self.tooltip, 1, 1, 1, 1, true)
      GameTooltip:Show()
    end
  end)
  overlay:SetScript("PostClick", function(self, _, down)
    if down then return end -- registered for both; act once
    local after = self.after
    if not InCombatLockdown() then self:Hide() end
    W.CloseMenu()
    if after then ns.SafeCall(after) end
  end)
  overlay:Hide()
  return overlay
end

-- Lays the overlay over button; action = {click = Blizzard button, after = function} (out of combat)
function UI.ShowOverlay(button, action, tooltip)
  if InCombatLockdown() or type(action) ~= "table" or not action.click or not button:IsVisible() then return end
  local left, bottom = button:GetLeft(), button:GetBottom()
  if not left or not bottom then return end
  local o = Overlay()
  local scale = button:GetEffectiveScale() / UIParent:GetEffectiveScale()
  o:SetAttribute("clickbutton", action.click)
  o.tooltip, o.after = tooltip, action.after
  o:ClearAllPoints()
  o:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", left * scale, bottom * scale)
  o:SetSize(button:GetWidth() * scale, button:GetHeight() * scale)
  o:Show()
end

function UI.HideOverlay()
  if overlay and not InCombatLockdown() then overlay:Hide() end
end

-- Makes a Guildy button run a Blizzard action. getAction(button) returns the action (or nil). A direct
-- click on the button itself only happens when the overlay could not be laid (combat).
function UI.SecureAction(button, getAction, tooltip)
  button:HookScript("OnEnter", function(self) UI.ShowOverlay(self, getAction(self), tooltip) end)
  button:SetScript("OnClick", function() ns.Print(ns.L.NOT_IN_COMBAT) end)
end

-- Invite dialog: name field plus suggestions; the buttons open Blizzard's invite dialog --------------

local dialog

local function Build()
  local L = ns.L
  dialog = W.Box(UIParent, 0.06, 0.9)
  dialog:SetSize(300, 140)
  dialog:SetFrameStrata("DIALOG")
  dialog:EnableMouse(true)
  dialog:SetClampedToScreen(true)
  dialog:SetMovable(true)
  dialog:RegisterForDrag("LeftButton")
  dialog:SetScript("OnDragStart", dialog.StartMoving)
  dialog:SetScript("OnDragStop", dialog.StopMovingOrSizing)

  dialog.Title = W.Text(dialog, "GameFontNormal", L.INVITE_TITLE)
  dialog.Title:SetPoint("TOPLEFT", 12, -10)

  dialog.Edit = W.EditBox(dialog, 270)
  dialog.Edit:SetPoint("TOPLEFT", 16, -32)
  dialog.Edit:SetMaxLetters(48)
  dialog.Edit:SetScript("OnEscapePressed", function() dialog:Hide() end)

  dialog.Hint = W.Text(dialog, "GameFontDisableSmall", L.INVITE_SUGGESTIONS)
  dialog.Hint:SetPoint("TOPLEFT", 12, -56)

  local function Then(action)
    if not action then return nil end
    local after = action.after
    action.after = function()
      dialog:Hide()
      if after then after() end
    end
    return action
  end

  dialog.Suggestions = {}
  for i = 1, 5 do
    local b = W.Button(dialog, "", nil, 276, { small = true })
    b:SetHeight(18)
    b:SetPoint("TOPLEFT", 12, -70 - (i - 1) * 20)
    UI.SecureAction(b, function(self) return Then(Action.Invite(self.value)) end)
    dialog.Suggestions[i] = b
  end

  dialog.Ok = W.Button(dialog, L.INVITE, nil, 130)
  dialog.Ok:SetPoint("BOTTOMLEFT", 12, 10)
  UI.SecureAction(dialog.Ok, function() return Then(Action.Invite(ns.Names.Trim(dialog.Edit:GetText() or ""))) end)
  dialog.Cancel = W.Button(dialog, CANCEL or "Cancel", function() dialog:Hide() end, 130)
  dialog.Cancel:SetPoint("BOTTOMRIGHT", -12, 10)
  dialog:SetScript("OnHide", function() UI.HideOverlay() end)
  dialog:Hide()
end

-- suggestions = { {label, value} }
function UI.InviteDialog(anchor, name, suggestions)
  if not dialog then Build() end
  for i, button in ipairs(dialog.Suggestions) do
    local s = suggestions[i]
    button.value = s and s.value
    button:SetText(s and s.label or "")
    button:SetShown(s ~= nil)
  end
  dialog.Hint:SetShown(#suggestions > 0)
  dialog:SetHeight(96 + (#suggestions > 0 and (18 + #suggestions * 20) or 0))
  dialog:ClearAllPoints()
  if anchor then dialog:SetPoint("BOTTOMRIGHT", anchor, "TOPRIGHT", 0, 4) else dialog:SetPoint("CENTER", 0, 120) end
  dialog.Edit:SetText(name or "")
  dialog:Show()
  dialog.Edit:SetFocus()
  dialog.Edit:HighlightText()
end
