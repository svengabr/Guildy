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

-- Whether Blizzard's invite button can be clicked right away
function Action.InviteReady()
  return BlizzardInviteButton() ~= nil
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

-- The overlay --------------------------------------------------------------------------------------

local overlay

local function Overlay()
  if overlay then return overlay end
  overlay = CreateFrame("Button", "GuildySecureOverlay", UIParent, "SecureActionButtonTemplate")
  overlay:SetFrameStrata("TOOLTIP")
  overlay:RegisterForClicks("AnyUp", "AnyDown")
  overlay:SetAttribute("type", "click")
  -- the overlay is invisible: it lights up the button below it in that button's own style
  local function Light(owner, on)
    if not owner then return end
    if owner.SetHover then
      owner:SetHover(on)
    elseif owner.LockHighlight then
      if on then owner:LockHighlight() else owner:UnlockHighlight() end
    end
  end
  overlay:SetScript("OnLeave", function(self)
    GameTooltip:Hide()
    Light(self.owner, false)
    if not InCombatLockdown() then self:Hide() end
  end)
  overlay:SetScript("OnEnter", function(self)
    Light(self.owner, true)
    if self.tooltip then
      if self.beside then
        GameTooltip:SetOwner(self, "ANCHOR_NONE")
        GameTooltip:SetPoint("LEFT", self, "RIGHT", 6, 0)
      else
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      end
      GameTooltip:SetText(self.tooltip, 1, 1, 1, 1, true)
      GameTooltip:Show()
    end
  end)
  overlay:SetScript("PostClick", function(self, _, down)
    if down then return end -- registered for both; act once
    local after = self.after
    if self.owner and self.owner.UnlockHighlight then self.owner:UnlockHighlight() end
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
  o.tooltip, o.after, o.owner = tooltip, action.after, button
  o.beside = button.Over ~= nil -- side tabs: tooltip beside the tab instead of above it
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

-- Invite: Guildy's button clicks Blizzard's invite button directly. Once Blizzard's dialog is up,
-- Guildy fills in the unguilded target and shows the latest whisperers as a small panel beside it;
-- a click there puts that name into Blizzard's field (the player still confirms in Blizzard's dialog).

local panel

local function InvitePopup()
  local find = rawget(_G, "StaticPopup_FindVisible")
  if not find then return nil end
  for _, which in ipairs(INVITE_POPUPS) do
    local popup = find(which)
    if popup then return popup end
  end
end

local function SetPopupName(popup, name)
  local box = (popup.GetEditBox and popup:GetEditBox()) or popup.editBox
  if box and name then
    box:SetText(ns.Names.ToServer(name))
    box:SetFocus()
  end
end

local function ShowSuggestions(popup, suggestions)
  if #suggestions == 0 then
    if panel then panel:Hide() end
    return
  end
  if not panel then
    panel = W.Box(UIParent, 0.06, 0.9)
    panel:SetFrameStrata("DIALOG")
    panel:SetWidth(200)
    panel.Title = W.Text(panel, "GameFontNormalSmall", ns.L.INVITE_SUGGESTIONS)
    panel.Title:SetPoint("TOPLEFT", 10, -8)
    panel.Buttons = {}
    for i = 1, 5 do
      local b = W.Button(panel, "", function(self)
        local current = InvitePopup()
        if current then SetPopupName(current, self.value) end
      end, 180, { small = true })
      b:SetHeight(18)
      b:SetPoint("TOPLEFT", 10, -24 - (i - 1) * 20)
      panel.Buttons[i] = b
    end
  end
  for i, b in ipairs(panel.Buttons) do
    local s = suggestions[i]
    b.value = s and s.value
    b:SetText(s and s.label or "")
    b:SetShown(s ~= nil)
  end
  panel:SetHeight(32 + #suggestions * 20)
  panel:ClearAllPoints()
  panel:SetPoint("TOPLEFT", popup, "TOPRIGHT", 4, 0)
  panel.popup = popup
  panel:Show()
  -- follow the popup: hide with it
  if not panel.ticker then
    panel.ticker = C_Timer.NewTicker(0.5, function()
      if not (panel.popup and panel.popup:IsShown()) then
        panel:Hide()
        panel.ticker:Cancel()
        panel.ticker = nil
      end
    end)
  end
end

-- target: name to fill in (or nil); suggestions = { {label, value} }
function Action.InviteWith(target, suggestions)
  local button = BlizzardInviteButton()
  if not button then
    local window = Action.BlizzardWindow()
    if window then
      window.after = function()
        ns.UI.Hide()
        ns.Print(ns.L.INVITE_FIRST_TIME)
      end
    end
    return window
  end
  return { click = button, after = function()
    local popup = InvitePopup()
    if not popup then return end
    if target then SetPopupName(popup, target) end
    ShowSuggestions(popup, suggestions)
  end }
end

-- Invite with a name and no suggestions
function Action.Invite(name)
  return Action.InviteWith(name, {})
end
