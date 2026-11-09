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
  local rights = R.Rights(m)
  for _, kind in ipairs({ "promote", "demote" }) do
    if can[kind] then
      local target = R.NextRank(m, kind)
      local label = kind == "promote" and L.PROMOTE or L.DEMOTE
      local labelTo = kind == "promote" and L.PROMOTE_TO or L.DEMOTE_TO
      items[#items + 1] = { text = target and labelTo:format(target) or label, disabled = target == nil,
        action = target and function() return UI.Action.Manage(kind, m) end or nil }
    end
  end
  if can.editPublic or can.editOfficer then
    items[#items + 1] = { text = L.NOTES_IN_BLIZZARD, action = UI.Action.BlizzardWindow }
  end
  -- removal last and red, always behind a confirmation
  if can.remove then
    items[#items + 1] = { text = L.REMOVE, disabled = not rights.remove, color = { 1, 0.25, 0.2 },
      onClick = function() UI.ConfirmRemove(m) end }
  end
  W.OpenMenu(anchor or UI.CursorAnchor(), items, 210)
end

-- Tooltip for a roster member (owner frame given); hint replaces the default click hint
function UI.MemberTooltip(owner, m, hint)
  local L = ns.L
  GameTooltip:SetOwner(owner, "ANCHOR_CURSOR")
  GameTooltip:SetText(W.ClassName(m.name, m.classFile))
  GameTooltip:AddLine(L.LEVEL_CLASS:format(m.level or 0, m.className or ""), 1, 1, 1)
  if m.rank then GameTooltip:AddDoubleLine(L.RANK, m.rank, 1, 0.82, 0, 1, 1, 1) end
  if m.zone and m.zone ~= "" then GameTooltip:AddDoubleLine(L.ZONE, m.zone, 1, 0.82, 0, 1, 1, 1) end
  if m.online then
    GameTooltip:AddDoubleLine(L.LAST_ONLINE, ns.Roster.LastOnlineText(m), 1, 0.82, 0, 0.3, 0.9, 0.3)
  else
    GameTooltip:AddDoubleLine(L.LAST_ONLINE, ns.Roster.LastOnlineText(m), 1, 0.82, 0, 1, 1, 1)
  end
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
        GameTooltip:AddDoubleLine("|T" .. ns.Professions.ICONS[skillLine] .. ":14|t " .. ns.TradeSkill.Name(skillLine),
          level, 1, 1, 1, 0.8, 0.8, 0.8)
      end
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