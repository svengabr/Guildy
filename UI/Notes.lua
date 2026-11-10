-- Public and officer notes in Blizzard's own member panel, shown next to Guildy's window.
--
-- C_GuildInfo.SetNote is restricted on Forever (HasRestrictions in Blizzard's API docs): only untainted
-- Blizzard code may call it. The one clean path is Blizzard's own: a row of its guild member list picks
-- the member (CommunitiesFrame.GuildMemberDetailFrame), a mouse click on that panel's note box opens
-- Blizzard's note dialog with the member's GUID, and the dialog's Accept or Enter saves. Guildy must
-- never write any of those values (a GUID, the panel's member, the dialog's data or its text).
-- Approach after SuuUI (github.com/DomenikIrrgang/suuui), which reskins Blizzard's guild window itself.
--
-- Guildy lives inside Blizzard's guild window (UI/Main.lua), so Blizzard's member list and member
-- panel are there whenever Guildy is shown:
-- - Blizzard's member list is made tall enough for every member to have a row, off screen;
-- - picking: while the mouse is on a member anywhere in Guildy (a list row, a card), a secure button
--   lies over it. Its click clicks that member's row in Blizzard's list (Blizzard picks the member) and
--   is passed on to Guildy's own row (character page, menu), so no extra click is needed;
-- - while the character page shows the member Blizzard picked, Blizzard's member panel is shown as it
--   is, next to Guildy's window: its notes, rank menu and buttons are Blizzard's own.
-- (Laying Blizzard's note boxes and edit box invisibly into Guildy's own fields worked only now and
-- then in game, 2026-11-09; the plain panel is what the player asked for.)
local _, ns = ...
local W = ns.Widgets
local UI = ns.UI

local Notes = {}
UI.Notes = Notes

local NOTE_POPUP = "SET_GUILD_COMMUNITIY_NOTE"
local AWAY_X = 5000 -- off screen to the right
local ROW_HEIGHT = 24
local PANEL_GAP = 10 -- between Guildy's window and Blizzard's member panel beside it
local SIDE_TABS = 60 -- room Guildy's side tabs take right of its window (UI/Main.lua clamps the same)

local placing = false -- Guildy itself is moving the member list (its SetPoint hooks ignore that)
local listHooked = false
local AfterPick -- (below) a member was just picked through the pick button
local docked = false -- Blizzard's member panel is shown next to Guildy's window
local shown -- the member the character page shows (nil: no character page)
local saved = {} -- Blizzard frame -> its anchors before Guildy moved it

-- Blizzard's frames -------------------------------------------------------------------------------

local function Host()
  return UI.Host and UI.Host()
end

-- a part of Blizzard's window (only frames: a client without it gives nil)
local function Part(frame, key)
  local part = frame and frame[key]
  return type(part) == "table" and part or nil
end

local function MemberList()
  return Part(Host(), "MemberList")
end

local function Detail()
  return Part(Host(), "GuildMemberDetailFrame")
end

local function NoteBox(officer)
  return Part(Detail(), officer and "OfficerNoteBackground" or "NoteBackground")
end

local function Save(frame)
  if not frame or saved[frame] then return end
  local points = {}
  for i = 1, frame:GetNumPoints() or 0 do points[i] = { frame:GetPoint(i) } end
  points.width, points.height = frame:GetWidth(), frame:GetHeight()
  saved[frame] = points
end

local function Restore(frame)
  local points = frame and saved[frame]
  if not points then return end
  saved[frame] = nil
  frame:ClearAllPoints()
  for _, p in ipairs(points) do frame:SetPoint(unpack(p)) end
  if points.width and points.height and points.width > 0 and points.height > 0 then
    frame:SetSize(points.width, points.height)
  end
end

local function GuildSelected()
  local host = Host()
  local guildClub = C_Club and ns.Try(C_Club.GetGuildClubId)
  local selected = host and host.GetSelectedClubId and ns.Try(host.GetSelectedClubId, host)
  return guildClub ~= nil and selected == guildClub
end

-- Whether the player may change one of m's notes at all
local function CanEdit(m)
  if not (m and not m.elsewhere and m.guid) then return false end
  local can = ns.Roster.Can()
  return (can.editPublic or can.editOfficer or (ns.Roster.Me and ns.Roster.Me() == m)) and true or false
end

-- Blizzard's member list: tall and off screen ------------------------------------------------------

local function SizeList()
  local host, list = Host(), MemberList()
  if not (host and list and host:IsShown()) or InCombatLockdown() then return end
  Save(list)
  local count = ns.Try(rawget(_G, "GetNumGuildMembers")) or 0
  placing = true
  list:ClearAllPoints()
  -- its rows are only clicked by the secure button, never by the mouse
  list:SetPoint("TOPLEFT", UIParent, "TOPRIGHT", AWAY_X, 0)
  list:SetSize(300, count * ROW_HEIGHT + 80)
  placing = false
  if not listHooked then
    listHooked = true
    -- Blizzard lays its list out again (view changes): back where Guildy wants it
    local function Again()
      if not placing and saved[list] then C_Timer.After(0, SizeList) end
    end
    hooksecurefunc(list, "SetPoint", Again)
    hooksecurefunc(list, "SetSize", Again)
    -- Blizzard's window closed: its list as it was
    host:HookScript("OnHide", function() Restore(list) end)
  end
end

-- Blizzard's list ready before the first click: its rows appear a frame after it grows, so Guildy sizes
-- it when Blizzard's window opens (UI/Main.lua) and whenever the roster changes
function Notes.Prepare()
  SizeList()
end
ns.On("ROSTER", function() if UI.IsShown() then SizeList() end end)

-- The member's row in Blizzard's list (rows are filled by Blizzard: clean)
local function Row(guid)
  local list = MemberList()
  local box = list and list.ScrollBox
  if not (guid and box and box.ForEachFrame) then return nil end
  local found
  box:ForEachFrame(function(frame)
    local info = frame.memberInfo
    if not found and info and info.guid == guid and not frame.isInvitation then found = frame end
  end)
  return found
end

-- Whether Blizzard's member panel shows m (picked by Blizzard)
local function Picked(m)
  local detail = Detail()
  if not (m and m.guid and detail and detail:IsShown() and detail.GetMemberInfo) then return false end
  local info = ns.Try(detail.GetMemberInfo, detail)
  return info ~= nil and info.guid == m.guid
end

-- The secure pick button -------------------------------------------------------------------------

local pick

local function KeyDownMode()
  local get = (C_CVar and C_CVar.GetCVarBool) or rawget(_G, "GetCVarBool")
  return get and get("ActionButtonUseKeyDown") and true or false
end

local function HidePick()
  if pick and not InCombatLockdown() then pick:Hide() end
end

-- Passes the click on to the frame under the pick button (its own OnClick or OnMouseUp)
local function Forward(owner, button)
  if not (owner and owner.GetScript) then return end
  local onClick = owner:HasScript("OnClick") and owner:GetScript("OnClick")
  if onClick then
    onClick(owner, button, false)
    return
  end
  local onUp = owner:GetScript("OnMouseUp")
  if onUp then onUp(owner, button) end
end

-- the member a frame below the pick button shows now (rows keep it in .member or .item.member)
local function MemberOf(owner)
  return owner.member or (type(owner.item) == "table" and owner.item.member) or nil
end

local function Pick()
  if pick then return pick end
  pick = CreateFrame("Button", "GuildyNotePick", UIParent, "SecureActionButtonTemplate")
  pick:SetFrameStrata("TOOLTIP")
  pick:RegisterForClicks("AnyUp", "AnyDown")
  -- left: clicks the member's row in Blizzard's list (Blizzard picks them), then Guildy's own click;
  -- right: right-clicks that row, so Blizzard opens its own guild member menu. Its "Copy character
  -- name" copies straight to the clipboard: CopyToClipboard is restricted to Blizzard's code.
  pick:SetAttribute("type1", "click")
  pick:SetAttribute("type2", "click")
  pick:SetScript("PostClick", function(self, button, down)
    if (down and true or false) ~= KeyDownMode() then return end -- registered for both; act once
    local owner, m, forward = self.owner, self.member, self.forward
    if not InCombatLockdown() then self:Hide() end
    if button == "RightButton" then return end -- Blizzard's menu instead of Guildy's
    if m then AfterPick() end
    if forward then Forward(owner, button) end
  end)
  pick:SetScript("OnDoubleClick", function(self, button)
    local owner = self.owner
    local fn = self.forward and owner and owner:GetScript("OnDoubleClick")
    if fn then fn(owner, button) end
  end)
  -- the pick button came over the frame below: that frame keeps its tooltip and highlight
  pick:SetScript("OnEnter", function(self)
    local owner = self.owner
    if self.forward and owner and self.member then UI.MemberTooltip(owner, self.member, self.hint) end
    if owner and owner.LockHighlight then owner:LockHighlight() end
  end)
  pick:SetScript("OnLeave", function(self)
    local owner = self.owner
    GameTooltip:Hide()
    if owner and owner.UnlockHighlight then owner:UnlockHighlight() end
    HidePick()
  end)
  -- the frame below went away or shows someone else now (a list scrolled under the resting mouse)
  pick:SetScript("OnUpdate", function(self)
    local owner = self.owner
    if not owner or not owner:IsVisible() or (self.forward and MemberOf(owner) ~= self.member) then HidePick() end
  end)
  pick:Hide()
  return pick
end

-- Lays the pick button over owner (a frame showing member m) while the mouse is on it.
-- forward: the click goes on to owner afterwards; hint: owner's tooltip hint.
local function LayPick(owner, m, forward, hint)
  if InCombatLockdown() or not (m and m.guid and not m.elsewhere) then return end
  local host = Host()
  if not (host and host:IsShown() and GuildSelected()) then return end
  local p = Pick()
  if p:IsShown() and p.owner == owner and p.member == m then return end
  local row = Row(m.guid)
  if not row then
    SizeList()
    return
  end
  local left, bottom = owner:GetLeft(), owner:GetBottom()
  if not (left and bottom) then return end
  p.owner, p.member, p.forward, p.hint = owner, m, forward, hint
  p:SetAttribute("clickbutton1", row)
  p:SetAttribute("clickbutton2", row)
  local scale = owner:GetEffectiveScale() / UIParent:GetEffectiveScale()
  p:ClearAllPoints()
  p:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", left * scale, bottom * scale)
  p:SetSize(owner:GetWidth() * scale, owner:GetHeight() * scale)
  p:Show()
end

-- The mouse is on member m somewhere in Guildy (UI.MemberTooltip): the click there picks m in
-- Blizzard's list too, then goes on to that frame as always
function Notes.HoverMember(owner, m, hint)
  if owner and m and MemberOf(owner) == m then LayPick(owner, m, true, hint) end
end

-- Guildy's look on Blizzard's panel and note dialog -------------------------------------------------
-- Only looks: Blizzard's frame art goes see-through (alpha, an engine value) and Guildy's own boxes lie
-- behind it. Nothing is written into Blizzard's tables; texts, buttons and the rank menu stay Blizzard's.

local hidden = {} -- Blizzard frame or texture -> its alpha before Guildy made it see-through

local function SeeThrough(object)
  if object and hidden[object] == nil then
    hidden[object] = object:GetAlpha()
    object:SetAlpha(0)
  end
end

local function Unhide(object)
  if object and hidden[object] ~= nil then
    object:SetAlpha(hidden[object])
    hidden[object] = nil
  end
end

-- a frame's own textures (not its texts)
local function Textures(frame)
  local list = {}
  for _, region in ipairs({ frame:GetRegions() }) do
    if region.GetObjectType and region:GetObjectType() == "Texture" then list[#list + 1] = region end
  end
  return list
end

local tinted = {} -- Blizzard texture -> its vertex colour before Guildy recoloured it

-- A backdrop piece in Guildy's field colours: the fill near black, the edge Guildy's dim gold
local function Tint(texture, fill)
  if tinted[texture] == nil then tinted[texture] = { texture:GetVertexColor() } end
  if fill then
    texture:SetVertexColor(0.03, 0.025, 0.02, 0.95)
  else
    texture:SetVertexColor(W.GOLD[1] * 0.6, W.GOLD[2] * 0.6, W.GOLD[3] * 0.6, 1)
  end
end

local function Untint(texture)
  local color = tinted[texture]
  if color then
    texture:SetVertexColor(unpack(color))
    tinted[texture] = nil
  end
end

local backs = {} -- Blizzard frame -> Guildy's box behind it

-- Guildy's box behind frame: a child of parent at frame level level (below frame's own parts)
local function Backing(frame, parent, level, shade, border)
  local box = backs[frame]
  if not box then
    box = W.Box(parent, shade, border)
    box:SetIgnoreParentAlpha(true)
    box:EnableMouse(false)
    backs[frame] = box
  end
  box:ClearAllPoints()
  box:SetAllPoints(frame)
  box:SetFrameLevel(math.max(0, level))
  box:Show()
end

local function Unbacking(frame)
  local box = backs[frame]
  if box then box:Hide() end
end

-- Blizzard's member panel: its dark dialog border see-through, Guildy's box behind it, the two note
-- boxes as Guildy's fields
local BUTTON_GAP, BUTTON_INSET = 6, 10
local laidButtons = {} -- Blizzard button -> its width before Guildy laid it out

-- Remove and group invite side by side at the bottom, equally wide (Guildy's button row)
local function LayButtons(detail)
  local remove, invite = Part(detail, "RemoveButton"), Part(detail, "GroupInviteButton")
  if not (remove and invite) then return end
  local width = math.floor(((detail:GetWidth() or 212) - 2 * BUTTON_INSET - BUTTON_GAP) / 2)
  for _, button in ipairs({ remove, invite }) do
    Save(button)
    if laidButtons[button] == nil then laidButtons[button] = button:GetWidth() end
    button:SetWidth(width)
    button:ClearAllPoints()
  end
  remove:SetPoint("BOTTOMLEFT", detail, "BOTTOMLEFT", BUTTON_INSET, BUTTON_INSET)
  invite:SetPoint("BOTTOMRIGHT", detail, "BOTTOMRIGHT", -BUTTON_INSET, BUTTON_INSET)
end

local function UnlayButtons(detail)
  for _, key in ipairs({ "RemoveButton", "GroupInviteButton" }) do
    local button = Part(detail, key)
    if button and laidButtons[button] then
      button:SetWidth(laidButtons[button])
      laidButtons[button] = nil
      Restore(button)
    end
  end
end

local function SkinDetail()
  local host, detail = Host(), Detail()
  if not (host and detail) then return end
  SeeThrough(Part(detail, "Border"))
  -- part of the character page: it closes with the page, no close button of its own
  local close = Part(detail, "CloseButton")
  if close then close:Hide() end
  -- the name in its class colour, as everywhere in Guildy
  local name = Part(detail, "Name")
  if name and shown then name:SetTextColor(W.ClassColor(shown.classFile)) end
  LayButtons(detail)
  -- Guildy's box behind the whole panel, below its lowest part (Blizzard shifts its levels when the
  -- panel shows again)
  local lowest = detail:GetFrameLevel()
  for _, officer in ipairs({ false, true }) do
    local box = NoteBox(officer)
    if box then lowest = math.min(lowest, box:GetFrameLevel()) end
  end
  Backing(detail, host, lowest - 2)
  -- the note boxes keep their own backdrop, recoloured as Guildy's fields: a box of Guildy's behind
  -- them slid in front of their text once Blizzard reordered the levels (found in game)
  for _, officer in ipairs({ false, true }) do
    local box = NoteBox(officer)
    if box then
      for _, texture in ipairs(Textures(box)) do
        -- the fill: the backdrop's Center, or failing that the one big piece (edges and corners are thin)
        local w, h = texture:GetWidth() or 0, texture:GetHeight() or 0
        Tint(texture, texture == box.Center or (w > 20 and h > 20))
      end
    end
  end
end

local function UnskinDetail()
  local detail = Detail()
  if not detail then return end
  Unhide(Part(detail, "Border"))
  local close = Part(detail, "CloseButton")
  if close then close:Show() end
  local name = Part(detail, "Name")
  if name then name:SetTextColor(1, 0.82, 0) end
  UnlayButtons(detail)
  Unbacking(detail)
  for _, officer in ipairs({ false, true }) do
    local box = NoteBox(officer)
    if box then
      for _, texture in ipairs(Textures(box)) do Untint(texture) end
    end
  end
end

-- Blizzard's note dialog: its frame art see-through (every part but its buttons, edit box and close
-- button), Guildy's box behind it and behind its edit box
local DIALOG_KEEP = { ButtonContainer = true, EditBox = true, CloseButton = true, CoverFrame = true,
  ExtraButton = true, GamepadSequence = true }
local dialogArt = {} -- dialog -> the parts Guildy made see-through

local function SkinDialog(dialog)
  local art = {}
  for _, child in ipairs({ dialog:GetChildren() }) do
    local keep = false
    for key in pairs(DIALOG_KEEP) do
      if dialog[key] == child then keep = true end
    end
    if not keep then art[#art + 1] = child end
  end
  for _, texture in ipairs(Textures(dialog)) do art[#art + 1] = texture end
  local edit = Part(dialog, "EditBox")
  if edit then
    for _, texture in ipairs(Textures(edit)) do art[#art + 1] = texture end
  end
  for _, object in ipairs(art) do SeeThrough(object) end
  dialogArt[dialog] = art
  local level = dialog:GetFrameLevel()
  Backing(dialog, UIParent, level - 1, 0.07, 0.9)
  backs[dialog]:SetFrameStrata(dialog:GetFrameStrata())
  if edit then
    Backing(edit, UIParent, level, 0.02, 0.6)
    backs[edit]:SetFrameStrata(dialog:GetFrameStrata())
  end
end

local function UnskinDialog(dialog)
  for _, object in ipairs(dialogArt[dialog] or {}) do Unhide(object) end
  dialogArt[dialog] = nil
  Unbacking(dialog)
  local edit = Part(dialog, "EditBox")
  if edit then Unbacking(edit) end
end

-- Blizzard's member panel next to Guildy -----------------------------------------------------------


local Undock -- (below)

-- Blizzard's panel shows someone else now (its own list, a guild change) or closed
local hookedDetail = false
local function HookDetail()
  local detail = Detail()
  if hookedDetail or not detail then return end
  hookedDetail = true
  detail:HookScript("OnHide", function() if docked then Undock() end end)
end

function Undock()
  local detail = Detail()
  -- (Blizzard's member panel and Guildy's boxes aren't protected: this works in combat too, so the
  -- panel never stays half shown after a fight)
  if not docked or not detail then return end
  docked = false
  UnskinDetail()
  detail:SetIgnoreParentAlpha(false)
  Restore(detail)
end

-- Blizzard's panel beside Guildy's window, left of it (right when there is no room), by coordinates:
-- it is a child of Blizzard's window, never anchored to Guildy's frame. Drawn (it ignores its window's
-- alpha 0) and outside Guildy's window, so nothing lies over it and its own note boxes, rank menu and
-- buttons work as in Blizzard's window.
local function Dock()
  local detail, guildy = Detail(), UI.frame
  if not (detail and guildy) then return end
  local left, top, right = guildy:GetLeft(), guildy:GetTop(), guildy:GetRight()
  if not (left and top and right) then return end
  Save(detail)
  docked = true
  local width = detail:GetWidth() or 212
  local x = left - width - PANEL_GAP
  -- no room on the left: right of Guildy's window, past its side tabs (guild, account) outside its edge
  if x < 0 then x = right + SIDE_TABS end
  detail:SetIgnoreParentAlpha(true)
  detail:ClearAllPoints()
  detail:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x, top - 60)
  SkinDetail()
  HookDetail()
end

-- Blizzard's panel still holds m but is hidden: Blizzard hides it when its window closes, and keeps
-- the member it picked. Showing it again only shows it; the member stays Blizzard's own pick (its
-- clubId and memberId, which its note boxes read, are untouched).
local function Remembered(m)
  local detail = Detail()
  if not (m and m.guid and detail and not detail:IsShown() and detail.GetMemberInfo) then return false end
  local info = ns.Try(detail.GetMemberInfo, detail)
  return info ~= nil and info.guid == m.guid
end

-- Docked while the character page shows the member Blizzard picked
local function Update()
  local wanted = shown and UI.IsShown() and CanEdit(shown)
  if wanted and not Picked(shown) and Remembered(shown) then Detail():Show() end
  if wanted and Picked(shown) then Dock() else Undock() end
end
Notes.Follow = function() if docked then Dock() end end

-- The character page shows m (nil: it went away)
function Notes.Show(m)
  shown = m
  Update()
  -- again after Blizzard's own handlers ran (its window just opened: they may hide the panel)
  C_Timer.After(0, Update)
end

function Notes.Hide()
  shown = nil
  Undock()
end

-- Blizzard's own window is shown instead of Guildy (UI.ShowBlizzard): its member list back where and
-- as big as it was. Blizzard's chat is anchored to that list, and with the list still parked off
-- screen the chat's frame stretched across the whole screen and showed nothing (reported on Reddit
-- and seen in game 2026-11-10). Opening Guildy again parks it again (Notes.Prepare).
function Notes.Release()
  Notes.Hide()
  if InCombatLockdown() then return end
  if pick then pick:Hide() end
  placing = true
  Restore(MemberList())
  placing = false
end

-- After a pick (the click on a member in a Guildy list): dock once Blizzard shows them
function AfterPick()
  HookDetail()
  C_Timer.After(0, Update)
end

-- Blizzard's note dialog: once it closes Guildy asks for a fresh roster so the saved note shows up
local hookedDialogs = {} -- dialogs whose OnHide Guildy hooked (kept here: nothing is written into Blizzard's)

hooksecurefunc("StaticPopup_Show", function(which)
  if which ~= NOTE_POPUP or not docked then return end
  local find = rawget(_G, "StaticPopup_FindVisible")
  local dialog = find and find(which)
  if not dialog then return end
  SkinDialog(dialog)
  if hookedDialogs[dialog] then return end
  hookedDialogs[dialog] = true
  -- (the popup frames are shared by every dialog: Guildy's look goes again when this one closes)
  dialog:HookScript("OnHide", function(self)
    if not dialogArt[self] then return end
    UnskinDialog(self)
    C_Timer.After(1, function() ns.Roster.Request(true) end)
  end)
end)

-- /guildy notedebug: where Blizzard's frames are (for bug reports)
function Notes.Debug()
  local lines = {}
  local function add(...) lines[#lines + 1] = table.concat({ ... }, " ") end
  local function state(f)
    if not f then return "nil" end
    local l, b, w, h = f:GetRect()
    return ("shown %s visible %s alpha %.2f %s/%s rect %s,%s %sx%s"):format(tostring(f:IsShown()),
      tostring(f:IsVisible()), f:GetEffectiveAlpha(), f:GetFrameStrata(), f:GetFrameLevel(),
      tostring(l and math.floor(l)), tostring(b and math.floor(b)), tostring(w and math.floor(w)),
      tostring(h and math.floor(h)))
  end
  local m = shown
  add("guild", tostring(GuildSelected()), "combat", tostring(InCombatLockdown()), "member", tostring(m and m.name),
    "picked", tostring(Picked(m)), "row", tostring(m and Row(m.guid) ~= nil), "can", tostring(CanEdit(m)))
  add("host:", state(Host()))
  add("guildy:", state(UI.frame))
  add("list:", state(MemberList()))
  add("detail:", state(Detail()))
  for _, officer in ipairs({ false, true }) do
    local box = NoteBox(officer)
    add(officer and "officer box:" or "note box:", state(box), "mouse", tostring(box and box:IsMouseEnabled()))
  end
  local foci = rawget(_G, "GetMouseFoci") and _G.GetMouseFoci()
  if type(foci) == "table" then
    for i, f in ipairs(foci) do
      if i > 4 then break end
      add("  mouse " .. i .. ":", tostring(f.GetDebugName and f:GetDebugName()))
    end
  end
  return lines
end
