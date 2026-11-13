-- Member context menu (whisper, group invite, rank, removal, notes in Blizzard's window), the member tooltip and the
-- guild-invite box with suggestions.
local _, ns = ...
local W = ns.Widgets
local UI = ns.UI

-- "84/150", or "laut Notiz" for professions only known from a guild note
function UI.ProfLevel(prof)
  if prof.rank then return prof.rank .. (prof.max and ("/" .. prof.max) or "") end
  if prof.src == "note" then return "|cff999999–|r" end
  return "?"
end

local function SpecId(prof)
  local spec = type(prof) == "table" and prof.spec
  return type(spec) == "table" and type(spec.id) == "number" and spec.id > 0 and spec.id or nil
end

-- Short tag of a profession's specialization ("Goblin"), nil when none is known
function UI.SpecTag(prof)
  local id = SpecId(prof)
  if not id then return nil end
  local key = "SPEC_" .. id
  local text = ns.L[key]
  return text ~= key and text or nil
end

-- Full name of a profession's specialization in the client's language (the spell's name)
function UI.SpecName(prof)
  local id = SpecId(prof)
  return id and (ns.TradeSkill.RecipeName(id) or UI.SpecTag(prof)) or nil
end

-- Time left on a cooldown: "ready" in green, else "in 14 h"
function UI.CooldownLeft(entry)
  local L = ns.L
  if entry.left <= 0 then return "|cff4ce64c" .. L.CD_READY .. "|r" end
  local unit, count = ns.Cooldowns.Span(entry.left)
  return L.CD_LEFT:format((unit == "m" and L.CD_M or unit == "h" and L.CD_H or L.SPAN_D):format(count))
end

-- A member's cooldowns { { spell, readyAt, left } }, of one profession or all (skillLine nil), and when
-- they were read; nil when nothing is known of them
function UI.CooldownsOf(m, skillLine)
  local guild = ns.GuildData()
  local book = guild and guild.cooldowns
  local list = book and ns.Cooldowns.Of(book, m.key, ns.Now())
  if not list then return nil end
  local watched = ns.Cooldowns.Watched(ns.DB() and ns.DB().cooldownSpells)
  local out = {}
  for _, entry in ipairs(list) do
    if not skillLine or watched[entry.spell] == skillLine then out[#out + 1] = entry end
  end
  return out, book[m.key].ts
end

-- "as of 3 h ago" for a reading older than an hour, nil for a fresh one
function UI.CooldownAge(ts)
  local age = ns.Now() - (ts or 0)
  if age < 3600 then return nil end
  return ns.L.CD_AS_OF:format(ns.Roster.LastOnlineText({ online = false, daysOffline = age / 86400 }))
end

function UI.Whisper(name)
  local tell = rawget(_G, "ChatFrame_SendTell") or (ChatFrameUtil and ChatFrameUtil.SendTell)
  if tell then pcall(tell, name) end
end

-- A 1x1 frame at the mouse, for menus opened where no frame sits (names in the chat)
local cursorAnchor
function UI.CursorAnchor()
  cursorAnchor = cursorAnchor or CreateFrame("Frame", nil, UIParent)
  cursorAnchor:SetSize(1, 1)
  local x, y = GetCursorPosition()
  local scale = UIParent:GetEffectiveScale() or 1
  cursorAnchor:ClearAllPoints()
  cursorAnchor:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", (x or 0) / scale, (y or 0) / scale)
  return cursorAnchor
end

-- WoW has no clipboard access: a small box with the text selected, Ctrl+C copies and closes it
local copyBox
function UI.CopyText(text)
  local L = ns.L
  if not copyBox then
    copyBox = W.Box(UIParent, 0.06, 0.95)
    copyBox:SetFrameStrata("DIALOG")
    copyBox:SetSize(260, 74)
    copyBox:EnableMouse(true)
    copyBox.Title = W.Text(copyBox, "GameFontNormalSmall", L.COPY_HINT)
    copyBox.Title:SetPoint("TOP", 0, -12)
    copyBox.Edit = W.EditBox(copyBox, 220)
    copyBox.Edit:SetPoint("TOP", copyBox.Title, "BOTTOM", 0, -10)
    copyBox.Edit:SetScript("OnEscapePressed", function() copyBox:Hide() end)
    copyBox.Edit:SetScript("OnEnterPressed", function() copyBox:Hide() end)
    -- typing must not change the text: put it back and select it again
    copyBox.Edit:SetScript("OnTextChanged", function(self, user)
      if user and self:GetText() ~= copyBox.text then self:SetText(copyBox.text); self:HighlightText() end
    end)
    copyBox.Edit:SetScript("OnKeyDown", function(_, key)
      if key == "C" and IsControlKeyDown() then C_Timer.After(0, function() copyBox:Hide() end) end
    end)
    copyBox:SetScript("OnHide", function() copyBox.Edit:ClearFocus() end)
    tinsert(UISpecialFrames, "GuildyCopyBox")
    _G.GuildyCopyBox = copyBox
  end
  copyBox.text = text
  copyBox:ClearAllPoints()
  copyBox:SetPoint("TOPLEFT", UI.CursorAnchor(), "TOPLEFT", -20, 20)
  copyBox:SetClampedToScreen(true)
  copyBox:Show()
  copyBox.Edit:SetText(text)
  copyBox.Edit:SetFocus()
  copyBox.Edit:HighlightText()
end

-- Left click on a member anywhere: the character page; shift-click whispers
function UI.MemberClick(m)
  if not m then return end
  if IsShiftKeyDown() then UI.Whisper(m.fullName) else UI.ShowMember(m) end
end

-- Context menu for a roster member (right click anywhere). Officers get one step up and one step down,
-- each naming the rank it leads to (one rank per click, see UI/Commands.lua). anchor defaults to the
-- mouse position.
function UI.MemberMenu(m, anchor)
  local L, R = ns.L, ns.Roster
  local can = R.Can()
  local items = {
    { text = W.ClassName(m.name, m.classFile), isTitle = true },
    { text = L.MEMBER_OPEN_PAGE, onClick = function() UI.ShowMember(m) end },
    { text = L.WHISPER, onClick = function() UI.Whisper(m.fullName) end, disabled = not m.online },
    { text = L.GROUP_INVITE, onClick = function() R.GroupInvite(m) end, disabled = not m.online },
    { text = L.COPY_NAME, onClick = function() UI.CopyText(m.name) end },
  }
  -- professions that are wrong: thrown away, the next reading starts from nothing
  items[#items + 1] = { text = L.MEMBER_FORGET_PROFS, onClick = function()
    if ns.TradeSkill.Forget(m) then ns.Print(L.MEMBER_FORGOT_PROFS:format(m.name)) end
  end }
  local rights = R.Rights(m)
  -- rank and notes: Blizzard's own member panel beside the character page (UI/Notes.lua)
  if can.editPublic or can.editOfficer then
    -- notes are edited on the character page (UI/Notes.lua)
    items[#items + 1] = { text = L.NOTES_IN_BLIZZARD, onClick = function() UI.ShowMember(m) end }
  end
  -- removal last and red, always behind a confirmation
  if can.remove then
    items[#items + 1] = { text = L.REMOVE, disabled = not rights.remove, color = { 1, 0.25, 0.2 },
      onClick = function() UI.ConfirmRemove(m) end }
  end
  W.OpenMenu(anchor or UI.CursorAnchor(), items, 210)
end

-- Where a member's tooltip stands (settings.tooltipAnchor, Guildy's options):
--   "window"  = beside Guildy's window at the row's height, so it never covers the list (default)
--   "row"     = beside the hovered row
--   "cursor"  = at the mouse
--   "default" = the game's own spot
UI.TOOLTIP_ANCHORS = { "window", "row", "cursor", "default" }
function UI.TooltipAnchor()
  local chosen = ns.Settings().tooltipAnchor
  for _, known in ipairs(UI.TOOLTIP_ANCHORS) do
    if chosen == known then return chosen end
  end
  return "window"
end

local TOOLTIP_ROOM = 320 -- what a member tooltip needs beside the window
local function AnchorTooltip(owner)
  local mode = UI.TooltipAnchor()
  local default = rawget(_G, "GameTooltip_SetDefaultAnchor")
  if mode == "default" and default then
    default(GameTooltip, owner)
    return
  end
  local frame = UI.frame
  local target = mode == "row" and owner or frame
  local left, right = target and target:GetLeft(), target and target:GetRight()
  local screen = UIParent and UIParent.GetWidth and UIParent:GetWidth()
  if mode == "cursor" or mode == "default" or not (frame and left and right and screen) then
    GameTooltip:SetOwner(owner, "ANCHOR_CURSOR")
    return
  end
  -- at the row's height; right of the target where there is room (past the window's side tabs), else left
  local top, targetTop = owner:GetTop(), target:GetTop()
  local y = (top and targetTop) and (top - targetTop) or 0
  local scale = target.GetEffectiveScale and UIParent.GetEffectiveScale and target:GetEffectiveScale()
  local base = scale and UIParent:GetEffectiveScale()
  local factor = (type(scale) == "number" and type(base) == "number" and base > 0) and scale / base or 1
  y = y * factor -- the tooltip's units, not the window's (UI.SetScale)
  local gap = mode == "row" and 8 or 66
  GameTooltip:SetOwner(owner, "ANCHOR_NONE")
  if mode == "row" then
    -- a row at the window's right edge (the chat's online list): the tooltip on its left
    if left * factor >= TOOLTIP_ROOM then
      GameTooltip:SetPoint("TOPRIGHT", target, "TOPLEFT", -8, y)
    else
      GameTooltip:SetPoint("TOPLEFT", target, "TOPRIGHT", 8, y)
    end
  elseif screen - right * factor >= TOOLTIP_ROOM + gap then
    GameTooltip:SetPoint("TOPLEFT", target, "TOPRIGHT", gap, y)
  else
    GameTooltip:SetPoint("TOPRIGHT", target, "TOPLEFT", -8, y)
  end
end

-- Tooltip for a roster member (owner frame given); hint replaces the default click hint
function UI.MemberTooltip(owner, m, hint)
  local L = ns.L
  -- the click on this member also picks them in Blizzard's list, for their notes (UI/Notes.lua)
  if UI.Notes then UI.Notes.HoverMember(owner, m, hint) end
  AnchorTooltip(owner)
  GameTooltip:SetText(W.ClassName(m.name, m.classFile))
  GameTooltip:AddLine(L.LEVEL_CLASS:format(m.level or 0, m.className or ""), 1, 1, 1)
  if m.rank then GameTooltip:AddDoubleLine(L.RANK, m.rank, 1, 0.82, 0, 1, 1, 1) end
  if m.zone and m.zone ~= "" then GameTooltip:AddDoubleLine(L.ZONE, m.zone, 1, 0.82, 0, 1, 1, 1) end
  if m.online then
    GameTooltip:AddDoubleLine(L.LAST_ONLINE, ns.Roster.LastOnlineText(m), 1, 0.82, 0, 0.3, 0.9, 0.3)
  else
    GameTooltip:AddDoubleLine(L.LAST_ONLINE, ns.Roster.LastOnlineText(m), 1, 0.82, 0, 1, 1, 1)
  end
  local since = ns.Roster.TenureText(m, true)
  if since then GameTooltip:AddDoubleLine(L.MEMBER_SINCE, since, 1, 0.82, 0, 1, 1, 1) end
  local guildy = UI.GuildyVersionText and UI.GuildyVersionText(m)
  if guildy then GameTooltip:AddDoubleLine(L.COL_GUILDY, guildy, 1, 0.82, 0, 1, 1, 1) end
  if m.note and m.note ~= "" then GameTooltip:AddDoubleLine(L.NOTE, m.note, 1, 0.82, 0, 1, 1, 1) end
  if m.officerNote and m.officerNote ~= "" and ns.Roster.Can().viewOfficer then
    GameTooltip:AddDoubleLine(L.OFFICER_NOTE, m.officerNote, 1, 0.82, 0, 1, 1, 1)
  end
  local record = ns.TradeSkill.Record(m)
  if record and next(record.profs or {}) then
    GameTooltip:AddLine(" ")
    for _, skillLine in ipairs(ns.Professions.ORDER) do
      local prof = record.profs[skillLine]
      if prof then
        local level = UI.ProfLevel(prof)
        local tag = UI.SpecTag(prof)
        GameTooltip:AddDoubleLine("|T" .. ns.Professions.ICONS[skillLine] .. ":14|t " .. ns.TradeSkill.Name(skillLine)
          .. (tag and ("  |cff8f8268" .. tag .. "|r") or ""), level, 1, 1, 1, 0.8, 0.8, 0.8)
      end
    end
  end
  local cooldowns, readAt = UI.CooldownsOf(m)
  if cooldowns and #cooldowns > 0 then
    GameTooltip:AddLine(" ")
    GameTooltip:AddDoubleLine(L.COOLDOWNS, UI.CooldownAge(readAt) or "", 1, 0.82, 0, 0.6, 0.6, 0.6)
    for _, entry in ipairs(cooldowns) do
      GameTooltip:AddDoubleLine(ns.TradeSkill.RecipeName(entry.spell) or ("#" .. entry.spell), UI.CooldownLeft(entry),
        1, 1, 1, 1, 1, 1)
    end
  end
  GameTooltip:AddLine(" ")
  GameTooltip:AddLine(hint or L.MEMBER_CLICK_HINT, 0.6, 0.6, 0.6, true)
  GameTooltip:Show()
end

-- Guild invite: Blizzard's invite dialog (UI/Commands.lua) with the unguilded target filled in and
-- recent whisperers as suggestions

local function TargetSuggestion()
  if not UnitExists("target") or not UnitIsPlayer("target") or UnitIsUnit("target", "player") then return nil end
  if GetGuildInfo("target") then return nil end
  local name = (rawget(_G, "GetUnitName") and GetUnitName("target", true)) or UnitName("target")
  if ns.IsSecret(name) then return nil end -- names in instances can be secret
  return name
end

function UI.InviteAction()
  local L = ns.L
  local target = TargetSuggestion()
  local suggestions = {}
  if target then suggestions[#suggestions + 1] = { label = L.INVITE_TARGET:format(ns.Names.Normalize(target)), value = target } end
  for _, w in ipairs(ns.Chat.RecentWhispers()) do
    if #suggestions < 5 and not (target and ns.Names.Same(w.full, target)) then
      suggestions[#suggestions + 1] = { label = L.INVITE_WHISPERED:format(w.name), value = w.full }
    end
  end
  return UI.Action.InviteWith(target, suggestions)
end