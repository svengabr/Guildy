-- Guild management (invite, remove, rank, notes, MOTD, guild info) is reserved for Blizzard's own code
-- on Forever. Blocked: addon calls, /run in macros (force-tainted), non-secure slash commands in macros
-- (/ginvite), and any Blizzard window or chat input an addon touched first. Two things stay clean:
-- - a secure action button of type "click" runs a Blizzard button's own OnClick, no addon code between;
-- - a secure action button of type "macro" running Blizzard's secure slash commands /gpromote,
--   /gdemote and /gremove (verified in game: the command reaches C_GuildInfo untainted).
--
-- So Guildy's action buttons get such a secure button laid over them while the mouse is on them (out
-- of combat). Rank and removal run the slash commands; the invite clicks Blizzard's "Invite member"
-- button (Guildy then fills in the name); MOTD and guild info click Blizzard's edit and accept buttons
-- of its (hidden) text editor, the player types into Blizzard's own edit box shown inside Guildy. Notes go
-- through Blizzard's member list and note boxes (UI/Notes.lua). Guildy lives inside Blizzard's guild
-- window (UI/Main.lua), so all of those Blizzard frames exist whenever Guildy is shown.
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
  if type(button) ~= "table" or not button.IsEnabled or not button:IsEnabled() then return nil end
  local guildClub = C_Club and ns.Try(C_Club.GetGuildClubId)
  local selected = frame.GetSelectedClubId and ns.Try(frame.GetSelectedClubId, frame)
  if not guildClub or selected ~= guildClub then return nil end
  return button
end

-- Communities: Blizzard's own list picks the club ----------------------------------------------------
-- Like the notes (UI/Notes.lua): Guildy never selects a club in Blizzard's window itself (that taints
-- its invite button and its dialogs). A secure click on the club's entry in Blizzard's list lets
-- Blizzard select it. Guildy's communities list does that for the community it shows, Guildy's guild
-- tabs do it for the guild, so Blizzard's window always holds what Guildy shows.

local function Selected()
  local frame = rawget(_G, "CommunitiesFrame")
  return frame and frame.GetSelectedClubId and ns.Try(frame.GetSelectedClubId, frame)
end
Action.SelectedClub = Selected

-- The entry of clubId in Blizzard's communities list (its rows are filled by Blizzard: clean)
local function ClubEntry(clubId)
  local frame = rawget(_G, "CommunitiesFrame")
  local list = frame and frame.CommunitiesList
  local box = list and list.ScrollBox
  if not (clubId and box and box.ForEachFrame) then return nil end
  local found
  ns.Try(box.ForEachFrame, box, function(row)
    if not found and row.clubId == clubId and row.Click then found = row end
  end)
  return found
end

-- Lets Blizzard select clubId (nil when it already is, or its entry is not there); after() once done
function Action.SelectClub(clubId, after)
  if not clubId or Selected() == clubId then return nil end
  local entry = ClubEntry(clubId)
  return entry and { click = entry, after = after } or nil
end

-- Back to the guild in Blizzard's window (Guildy's guild tabs), when a community is selected there
function Action.SelectGuild(after)
  return Action.SelectClub(C_Club and ns.Try(C_Club.GetGuildClubId), after)
end

-- Blizzard's own "Invite member" for the community it shows (its dialog invites, untainted)
function Action.CommunityInvite(clubId)
  local frame = rawget(_G, "CommunitiesFrame")
  local button = frame and frame.InviteButton
  if not clubId or Selected() ~= clubId then return nil end
  if type(button) ~= "table" or not button.IsEnabled or not button:IsEnabled() then return nil end
  return { click = button }
end

-- Blizzard's own Accept / Decline of the invitation its window shows (its invitation frame calls
-- C_Club.AcceptInvitation itself, untainted)
function Action.AnswerInvitation(clubId, accept)
  local frame = rawget(_G, "CommunitiesFrame")
  local invitation = frame and frame.InvitationFrame
  if not (clubId and type(invitation) == "table") or Selected() ~= clubId then return nil end
  if rawget(invitation, "clubId") ~= clubId then return nil end
  local button = accept and invitation.AcceptButton or invitation.DeclineButton
  if type(button) ~= "table" then return nil end
  return { click = button, after = function() C_Timer.After(0.5, function() ns.Fire("COMMUNITY") end) end }
end

-- The entry of clubId in Blizzard's list, clicked with whichever mouse button the player used: left
-- picks it there, right opens Blizzard's own menu for it (leave the community, ...). after(button).
function Action.ClubEntry(clubId, after)
  local entry = ClubEntry(clubId)
  return entry and { click = entry, after = after } or nil
end

-- The member's row in Blizzard's member list, while Blizzard's window shows clubId: a right click there
-- opens Blizzard's own member menu (its rows are filled by Blizzard: clean). after(button).
function Action.ClubMember(clubId, guid, after)
  local frame = rawget(_G, "CommunitiesFrame")
  local list = frame and frame.MemberList
  local box = list and list.ScrollBox
  if not (clubId and guid and box and box.ForEachFrame) or Selected() ~= clubId then return nil end
  local found
  ns.Try(box.ForEachFrame, box, function(row)
    local info = row.memberInfo
    if not found and info and info.guid == guid and row.Click then found = row end
  end)
  return found and { click = found, after = after } or nil
end

-- Lays the overlay over button whenever getAction(button) gives one, and leaves the button's own click
-- alone otherwise (in combat or nothing to do: the button works as always). For tabs and list rows.
function UI.OptionalAction(button, getAction, tooltip)
  button:HookScript("OnEnter", function(self)
    if InCombatLockdown() then return end
    local action = getAction(self)
    if action then UI.ShowOverlay(self, action, type(tooltip) == "function" and tooltip(self) or tooltip) end
  end)
end

-- Whether Blizzard's invite button can be clicked right away
function Action.InviteReady()
  return BlizzardInviteButton() ~= nil
end


-- The overlay --------------------------------------------------------------------------------------

local overlay

local function KeyDownMode()
  local get = (C_CVar and C_CVar.GetCVarBool) or rawget(_G, "GetCVarBool")
  return get and get("ActionButtonUseKeyDown") and true or false
end

local function Overlay()
  if overlay then return overlay end
  overlay = CreateFrame("Button", "GuildySecureOverlay", UIParent, "SecureActionButtonTemplate")
  overlay:SetFrameStrata("TOOLTIP")
  overlay:RegisterForClicks("AnyUp", "AnyDown")
  -- the secure action runs on one edge only: key down when "cast on key down" is on, else release.
  -- before and after run on that same edge, right around the action.
  overlay:SetScript("PreClick", function(self, _, down)
    if (down and true or false) ~= KeyDownMode() then return end
    if self.before then ns.SafeCall(self.before) end
  end)
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
  overlay:SetScript("PostClick", function(self, mouseButton, down)
    if (down and true or false) ~= KeyDownMode() then return end
    local after = self.after
    if self.owner and self.owner.UnlockHighlight then self.owner:UnlockHighlight() end
    if not InCombatLockdown() then self:Hide() end
    W.CloseMenu()
    if after then ns.SafeCall(after, mouseButton) end -- after(mouseButton): the clicked mouse button
  end)
  overlay:Hide()
  return overlay
end

-- Lays the overlay over button (out of combat). action = {click = Blizzard button} or
-- {macro = "/gdemote Name"}, plus optional before (right before the action) and after (once done).
function UI.ShowOverlay(button, action, tooltip)
  if InCombatLockdown() or type(action) ~= "table" or not (action.click or action.macro) or not button:IsVisible() then return end
  -- at the guild banker Guildy shows without Blizzard's window (UI.ShowAtBank): none of its buttons to click
  if action.click and UI.AtBank and UI.AtBank() then return end
  local left, bottom = button:GetLeft(), button:GetBottom()
  if not left or not bottom then return end
  local o = Overlay()
  local scale = button:GetEffectiveScale() / UIParent:GetEffectiveScale()
  if action.macro then
    o:SetAttribute("type", "macro")
    o:SetAttribute("macrotext", action.macro)
    o:SetAttribute("clickbutton", nil)
  else
    o:SetAttribute("type", "click")
    o:SetAttribute("clickbutton", action.click)
    o:SetAttribute("macrotext", nil)
  end
  o.tooltip, o.before, o.after, o.owner = tooltip, action.before, action.after, button
  o.beside = button.sideTab == true -- side tabs: tooltip beside the tab instead of above it
  o:ClearAllPoints()
  o:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", left * scale, bottom * scale)
  o:SetSize(button:GetWidth() * scale, button:GetHeight() * scale)
  o:Show()
end

function UI.HideOverlay()
  if overlay and not InCombatLockdown() then overlay:Hide() end
end

-- Makes a Guildy button run a Blizzard action. getAction(button) returns the action (or nil); tooltip
-- is a text or a function(button) returning one. A direct click on the button itself only happens when
-- the overlay could not be laid: in combat, or getAction gave nothing; onPlainClick(button) handles the
-- latter (out of combat), else the click says "not in combat".
function UI.SecureAction(button, getAction, tooltip, onPlainClick)
  local function Lay(self)
    if self.IsEnabled and not self:IsEnabled() then return end
    UI.ShowOverlay(self, getAction(self), type(tooltip) == "function" and tooltip(self) or tooltip)
  end
  button.relayOverlay = Lay
  button:HookScript("OnEnter", Lay)
  if button.HasScript and button:HasScript("OnClick") then
    button:SetScript("OnClick", function(self)
      if UI.AtBank and UI.AtBank() and not InCombatLockdown() then
        ns.Print(ns.L.OPEN_WITH_J)
      elseif onPlainClick and not InCombatLockdown() then
        onPlainClick(self)
      else
        ns.Print(ns.L.NOT_IN_COMBAT)
      end
    end)
  end
end

-- After a button's state changed under a resting mouse (no new OnEnter): lays the overlay again when
-- the button is enabled and hovered, takes it away when the button was disabled. For buttons clicked
-- again and again from the same spot (rank arrows).
function UI.RefreshSecureAction(button)
  if InCombatLockdown() or not button.relayOverlay then return end
  local hovered = button:IsVisible() and button.IsMouseOver and button:IsMouseOver()
  if hovered and button:IsEnabled() then
    button.relayOverlay(button)
  elseif overlay and overlay.owner == button and overlay:IsShown() then
    overlay:Hide()
  end
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
  if not button then return nil end
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

-- Rank and removal: Blizzard's secure slash commands through the overlay. After the command Guildy
-- asks for a fresh roster so the new rank shows up. One rank per click: several /gpromote in one macro
-- all count from the old rank, the member moves one rank and the guild sees the same promotion twice
-- (verified in game), so Guildy offers single steps (promote/demote) instead of a rank list.
function Action.Manage(kind, m)
  local macro = m and ns.Manage.Command(kind, m.fullName or m.name)
  if not macro then return nil end
  return { macro = macro, after = function()
    C_Timer.After(1, function() ns.Roster.Request(true) end)
  end }
end

-- Message of the day and guild info: Blizzard's text editor (CommunitiesGuildTextEditFrame). Its edit
-- buttons set it up for "motd" or "info" and its accept button saves what is in its edit box.
-- SetMOTD/SetInfoText are fully protected: text an addon put into the box taints the save
-- (ADDON_ACTION_FORBIDDEN, verified). So Guildy never writes the text: it clicks Blizzard's edit button,
-- hides Blizzard's dialog and borrows the dialog's edit box (Container) into its own window, where the
-- player types; Save clicks Blizzard's accept button. Enter in the MOTD box is Blizzard's own accept.

local EDIT_BUTTONS = { motd = "EditMOTDButton", info = "EditDetailsButton" }

local function TextEditor()
  return rawget(_G, "CommunitiesGuildTextEditFrame")
end

local function TextEditButton(kind)
  local info = rawget(_G, "CommunitiesFrameGuildDetailsFrameInfo")
  return info and info[EDIT_BUTTONS[kind] or ""]
end

local function TextEditorBox()
  local editor = TextEditor()
  local container = editor and editor.Container
  return container and container.ScrollFrame and container.ScrollFrame.EditBox
end

-- Whether Blizzard's guild text editor can be used (Blizzard's guild window was loaded once)
function Action.TextEditReady(kind)
  return TextEditButton(kind) ~= nil and TextEditorBox() ~= nil and rawget(_G, "CommunitiesGuildTextEditFrameAcceptButton") ~= nil
end

-- Lends Blizzard's edit box (its Container frame) to parent, filling it with the given insets
function Action.BorrowTextBox(parent, left, top, right, bottom)
  local editor = TextEditor()
  local container = editor and editor.Container
  if not container then return nil end
  container:SetParent(parent)
  container:ClearAllPoints()
  container:SetPoint("TOPLEFT", parent, "TOPLEFT", left, top)
  container:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", right, bottom)
  container:SetFrameLevel(parent:GetFrameLevel() + 5)
  container:Show()
  local box = TextEditorBox()
  if box then
    box:SetWidth(math.max(60, container:GetWidth() - 34))
    box:SetFocus()
  end
  return container
end

-- Puts Blizzard's edit box back into Blizzard's dialog (anchors from its XML)
function Action.ReturnTextBox()
  local editor = TextEditor()
  local container = editor and editor.Container
  if not container or container:GetParent() == editor then return end
  local box = TextEditorBox()
  if box then
    box:ClearFocus()
    box:SetWidth(218)
  end
  container:SetParent(editor)
  container:ClearAllPoints()
  container:SetPoint("TOPLEFT", 22, -36)
  container:SetPoint("TOPRIGHT", -22, -36)
  container:SetPoint("BOTTOM", 0, 42)
end

-- Starts editing kind ("motd" or "info"); onReady() runs once Blizzard's editor is set up (hidden)
function Action.TextEdit(kind, onReady)
  local button = TextEditButton(kind)
  if not (button and Action.TextEditReady(kind)) then return nil end
  return { click = button, after = function()
    local editor = TextEditor()
    if editor and editor:IsShown() then editor:Hide() end
    if onReady then onReady() end
  end }
end

-- Saves what the player typed into Blizzard's box; only once TextEdit(kind) set Blizzard's editor up
function Action.TextSave(kind, onDone)
  local editor, accept = TextEditor(), rawget(_G, "CommunitiesGuildTextEditFrameAcceptButton")
  if not (editor and accept and editor.type == kind) then return nil end
  return { click = accept, after = function()
    C_Timer.After(1, function() ns.Roster.Request(true) end)
    if onDone then onDone() end
  end }
end

-- Ranks and permissions: Blizzard's rank editor (GuildControlUI, guild master only). Setting rank flags
-- and saving ranks are protected, and its rank menu can't be driven by an addon, so the player uses
-- Blizzard's editor itself. Guildy opens it through Blizzard's own "Guild Control" button (secure click,
-- Blizzard shows it) and only moves it over the Ranks tab. Guildy never shows it itself: its OnShow
-- handlers fill the rank name boxes, which must stay Blizzard's for saving to work.

local function RankEditorButton()
  local frame = rawget(_G, "CommunitiesFrame")
  local control = frame and frame.CommunitiesControlFrame
  return control and control.GuildControlButton
end

-- (its click loads Blizzard_GuildControlUI the first time)
function Action.RankEditorReady()
  return RankEditorButton() ~= nil
end

-- Opens (or closes, it's Blizzard's toggle) the rank editor; place(editor) positions it when shown
function Action.RankEditor(place)
  local button = RankEditorButton()
  if not (button and Action.RankEditorReady()) then return nil end
  return { click = button, after = function()
    local editor = rawget(_G, "GuildControlUI")
    if editor and editor:IsShown() and place then place(editor) end
  end }
end

-- Closes Blizzard's rank editor when Guildy's Ranks tab goes away (hiding is harmless for it)
function Action.CloseRankEditor()
  local editor = rawget(_G, "GuildControlUI")
  if editor and editor:IsShown() then editor:Hide() end
end

-- Confirmation dialog in Guildy's look whose OK button runs a secure action (removal)

local confirm

-- okText: label of the OK button (default "Yes"); danger: red OK label, for removal
function UI.Confirm(text, action, okText, danger)
  local L = ns.L
  if not confirm then
    confirm = W.Box(UIParent, 0.06, 0.9)
    confirm:SetFrameStrata("DIALOG")
    confirm:SetSize(340, 112)
    confirm:SetPoint("CENTER", 0, 120)
    confirm:EnableMouse(true)
    confirm.Text = W.Text(confirm, "GameFontHighlight")
    confirm.Text:SetPoint("TOPLEFT", 14, -16)
    confirm.Text:SetPoint("RIGHT", -14, 0)
    confirm.Text:SetJustifyH("CENTER")
    confirm.Ok = W.Button(confirm, L.YES, nil, 120)
    confirm.Ok:SetPoint("BOTTOMRIGHT", confirm, "BOTTOM", -4, 12)
    UI.SecureAction(confirm.Ok, function()
      local current = confirm.action
      if not current then return nil end
      local wrapped = {}
      for k, v in pairs(current) do wrapped[k] = v end
      wrapped.after = function()
        confirm:Hide()
        if current.after then current.after() end
      end
      return wrapped
    end)
    confirm.Cancel = W.Button(confirm, L.CANCEL, function() confirm:Hide() end, 120)
    confirm.Cancel:SetPoint("BOTTOMLEFT", confirm, "BOTTOM", 4, 12)
    confirm:SetScript("OnHide", function(self) self.action = nil end)
    tinsert(UISpecialFrames, "GuildyConfirm")
    _G.GuildyConfirm = confirm
  end
  confirm.Text:SetText(text)
  confirm.Ok:SetText(okText or L.YES)
  local label = confirm.Ok:GetFontString()
  if label then
    if danger then label:SetTextColor(1, 0.3, 0.25) else label:SetTextColor(1, 0.82, 0) end
  end
  confirm.action = action
  confirm:Show()
end

-- Removing a member: red button, name and rank in the question
function UI.ConfirmRemove(m)
  if not m then return end
  local L = ns.L
  local who = W.ClassName(m.name, m.classFile) .. (m.rank and ("|cffaaaaaa (" .. m.rank .. ")|r") or "")
  UI.Confirm(L.REMOVE_CONFIRM:format(who), UI.Action.Manage("remove", m), L.REMOVE_BUTTON, true)
end
