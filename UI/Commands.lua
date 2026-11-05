-- Guild management (invite, remove, promote, demote, notes) is reserved for Blizzard's UI on Forever:
-- addon code is blocked, macros calling it are blocked, and anything an addon touched first (even the
-- chat input) counts as addon code. What works: a macro that only *opens Blizzard's own dialog*
-- (StaticPopup ADD_GUILDMEMBER, REMOVE_GUILDMEMBER, ...); the player's click on that dialog's Accept
-- button is then Blizzard code.
--
-- So Guildy's action buttons get a secure macro button laid over them while the mouse is on them (out
-- of combat). The overlay is parented to UIParent and placed by absolute coordinates, never anchored
-- to Guildy's frames, so the Guildy window itself stays unprotected and can close in combat.
local _, ns = ...
local W = ns.Widgets
local UI = ns.UI

local Macro = {}
UI.Macro = Macro

local function Q(text)
  text = tostring(text or ""):gsub("|", ""):gsub("[\r\n]", " ")
  return string.format("%q", text)
end

-- Blizzard's invite dialog, name filled in
function Macro.Invite(name)
  local macro = '/run StaticPopup_Show("ADD_GUILDMEMBER")'
  if name and name ~= "" then
    macro = macro .. ' local d=StaticPopup_FindVisible and StaticPopup_FindVisible("ADD_GUILDMEMBER")'
      .. ' if d then (d.GetEditBox and d:GetEditBox() or d.editBox):SetText(' .. Q(ns.Names.ToServer(name)) .. ') end'
  end
  return macro
end

function Macro.Remove(m)
  return '/run StaticPopup_Show("REMOVE_GUILDMEMBER",nil,nil,{guid=' .. Q(m.guid) .. ',name=' .. Q(m.name) .. '})'
end

function Macro.Promote(m)
  return '/run StaticPopup_Show("GUILD_PROMOTE_CONFIRM",' .. Q(ns.L.PROMOTE_CONFIRM:format(m.name)) .. ',nil,' .. Q(m.fullName) .. ')'
end

function Macro.Demote(m)
  return '/run StaticPopup_Show("GUILD_DEMOTE_CONFIRM",' .. Q(ns.L.DEMOTE_CONFIRM:format(m.name)) .. ',nil,' .. Q(m.fullName) .. ')'
end

function Macro.Note(m, officer)
  local which = officer and "SET_GUILDOFFICERNOTE" or "SET_GUILDPLAYERNOTE"
  local note = officer and m.officerNote or m.note
  return '/run StaticPopup_Show("' .. which .. '",nil,nil,{guid=' .. Q(m.guid) .. ',currentNote=' .. Q(note) .. '})'
end

-- Blizzard's guild window (MOTD, guild info, everything else), Guildy closes first
function Macro.BlizzardWindow()
  return '/run if GuildyFrame then GuildyFrame:Hide() end ToggleGuildFrame()'
end

-- Blizzard's rank and permission editor
function Macro.GuildControl()
  return '/run if GuildyFrame then GuildyFrame:Hide() end local l=C_AddOns and C_AddOns.LoadAddOn or LoadAddOn'
    .. ' l("Blizzard_GuildControlUI") if GuildControlUI then ShowUIPanel(GuildControlUI) end'
end

-- The overlay --------------------------------------------------------------------------------------

local overlay

local function Overlay()
  if overlay then return overlay end
  overlay = CreateFrame("Button", "GuildySecureOverlay", UIParent, "SecureActionButtonTemplate")
  overlay:SetFrameStrata("TOOLTIP")
  overlay:RegisterForClicks("AnyUp", "AnyDown")
  overlay:SetAttribute("type", "macro")
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
  overlay:SetScript("PostClick", function(self)
    local after = self.after
    if not InCombatLockdown() then self:Hide() end
    W.CloseMenu()
    if after then ns.SafeCall(after) end
  end)
  overlay:Hide()
  return overlay
end

-- Lays the overlay over button with the given macro (out of combat only)
function UI.ShowOverlay(button, macro, tooltip, after)
  if InCombatLockdown() or not macro or not button:IsVisible() then return end
  local o = Overlay()
  local left, bottom, width, height = button:GetLeft(), button:GetBottom(), button:GetWidth(), button:GetHeight()
  if not left or not bottom then return end
  local scale = button:GetEffectiveScale() / UIParent:GetEffectiveScale()
  o:SetAttribute("macrotext", macro)
  o.tooltip, o.after = tooltip, after
  o:ClearAllPoints()
  o:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", left * scale, bottom * scale)
  o:SetSize(width * scale, height * scale)
  o:Show()
end

function UI.HideOverlay()
  if overlay and not InCombatLockdown() then overlay:Hide() end
end

-- Makes a Guildy button run a Blizzard dialog macro. getMacro(button) returns the macro text (or nil
-- to do nothing). A direct click on the button itself only happens in combat.
function UI.SecureAction(button, getMacro, tooltip, after)
  button:HookScript("OnEnter", function(self) UI.ShowOverlay(self, getMacro(self), tooltip, after) end)
  button:SetScript("OnClick", function() ns.Print(ns.L.NOT_IN_COMBAT) end)
end

-- Invite dialog: name field plus suggestions; every button opens Blizzard's invite dialog --------------

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

  local function Close() dialog:Hide() end

  dialog.Edit = W.EditBox(dialog, 270)
  dialog.Edit:SetPoint("TOPLEFT", 16, -32)
  dialog.Edit:SetMaxLetters(48)
  dialog.Edit:SetScript("OnEscapePressed", Close)

  dialog.Hint = W.Text(dialog, "GameFontDisableSmall", L.INVITE_SUGGESTIONS)
  dialog.Hint:SetPoint("TOPLEFT", 12, -56)

  dialog.Suggestions = {}
  for i = 1, 5 do
    local b = W.Button(dialog, "", nil, 276, { small = true })
    b:SetHeight(18)
    b:SetPoint("TOPLEFT", 12, -70 - (i - 1) * 20)
    UI.SecureAction(b, function(self) return Macro.Invite(self.value) end, nil, Close)
    dialog.Suggestions[i] = b
  end

  dialog.Ok = W.Button(dialog, L.INVITE, nil, 130)
  dialog.Ok:SetPoint("BOTTOMLEFT", 12, 10)
  UI.SecureAction(dialog.Ok, function() return Macro.Invite(ns.Names.Trim(dialog.Edit:GetText() or "")) end, nil, Close)
  dialog.Cancel = W.Button(dialog, CANCEL or "Cancel", Close, 130)
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
