-- Member context menu (whisper, group invite, notes, rank, remove), the note / confirm / text popups,
-- the member tooltip and the guild-invite box with suggestions.
local _, ns = ...
local W = ns.Widgets
local UI = ns.UI

local function EditBoxOf(popup)
  return popup.editBox or popup.EditBox
end

StaticPopupDialogs.GUILDY_NOTE = {
  text = "%s",
  button1 = ACCEPT or "OK",
  button2 = CANCEL or "Cancel",
  hasEditBox = true,
  maxLetters = 31,
  editBoxWidth = 260,
  OnShow = function(self)
    local box = EditBoxOf(self)
    if box then
      box:SetText(self.data and self.data.text or "")
      box:HighlightText()
    end
  end,
  OnAccept = function(self)
    local box = EditBoxOf(self)
    local data = self.data
    if box and data and data.onAccept then data.onAccept(box:GetText() or "") end
  end,
  EditBoxOnEnterPressed = function(self)
    local parent = self:GetParent()
    StaticPopupDialogs.GUILDY_NOTE.OnAccept(parent)
    parent:Hide()
  end,
  EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
  timeout = 0,
  whileDead = true,
  hideOnEscape = true,
  preferredIndex = 3,
}

StaticPopupDialogs.GUILDY_CONFIRM = {
  text = "%s",
  button1 = YES or "Yes",
  button2 = NO or "No",
  OnAccept = function(self)
    if self.data and self.data.onAccept then self.data.onAccept() end
  end,
  timeout = 0,
  whileDead = true,
  hideOnEscape = true,
  showAlert = true,
  preferredIndex = 3,
}

-- Single-line text popup; onAccept(text)
function UI.AskText(prompt, text, maxLetters, onAccept)
  StaticPopupDialogs.GUILDY_NOTE.maxLetters = maxLetters or 31
  StaticPopup_Show("GUILDY_NOTE", prompt, nil, { text = text, onAccept = onAccept })
end

function UI.Confirm(prompt, onAccept)
  StaticPopup_Show("GUILDY_CONFIRM", prompt, nil, { onAccept = onAccept })
end

function UI.Whisper(name)
  local tell = rawget(_G, "ChatFrame_SendTell") or (ChatFrameUtil and ChatFrameUtil.SendTell)
  if tell then pcall(tell, name) end
end

-- Context menu for a roster member
function UI.MemberMenu(m, anchor)
  local L, R = ns.L, ns.Roster
  local can = R.Can()
  local items = {
    { text = W.ClassName(m.name, m.classFile), isTitle = true },
    { text = L.WHISPER, onClick = function() UI.Whisper(m.fullName) end, disabled = not m.online },
    { text = L.GROUP_INVITE, onClick = function() R.GroupInvite(m) end, disabled = not m.online },
  }
  if can.editPublic then
    items[#items + 1] = { text = L.EDIT_NOTE, onClick = function()
      UI.AskText(L.NOTE_FOR:format(m.name), m.note, 31, function(text) R.SetNote(m, text, true) end)
    end }
  end
  if can.editOfficer then
    items[#items + 1] = { text = L.EDIT_OFFICER_NOTE, onClick = function()
      UI.AskText(L.OFFICER_NOTE_FOR:format(m.name), m.officerNote, 31, function(text) R.SetNote(m, text, false) end)
    end }
  end
  if can.promote then items[#items + 1] = { text = L.PROMOTE, onClick = function() R.Promote(m) end } end
  if can.demote then items[#items + 1] = { text = L.DEMOTE, onClick = function() R.Demote(m) end } end
  if can.remove then
    items[#items + 1] = { text = L.REMOVE, color = { 1, 0.3, 0.3 }, onClick = function()
      UI.Confirm(L.REMOVE_CONFIRM:format(m.name), function() R.Remove(m) end)
    end }
  end
  W.OpenMenu(anchor, items, 200)
end

-- Tooltip for a roster member (owner frame given)
function UI.MemberTooltip(owner, m)
  local L = ns.L
  GameTooltip:SetOwner(owner, "ANCHOR_LEFT")
  GameTooltip:SetText(W.ClassName(m.name, m.classFile))
  GameTooltip:AddLine(L.LEVEL_CLASS:format(m.level or 0, m.className or ""), 1, 1, 1)
  if m.rank then GameTooltip:AddDoubleLine(L.RANK, m.rank, 1, 0.82, 0, 1, 1, 1) end
  if m.zone and m.zone ~= "" then GameTooltip:AddDoubleLine(L.ZONE, m.zone, 1, 0.82, 0, 1, 1, 1) end
  GameTooltip:AddDoubleLine(L.LAST_ONLINE, ns.Roster.LastOnlineText(m), 1, 0.82, 0, 1, 1, 1)
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
        local level = prof.rank and (prof.rank .. (prof.max and ("/" .. prof.max) or "")) or "?"
        GameTooltip:AddDoubleLine("|T" .. ns.Professions.ICONS[skillLine] .. ":14|t " .. ns.TradeSkill.Name(skillLine),
          level, 1, 1, 1, 0.8, 0.8, 0.8)
      end
    end
  end
  GameTooltip:AddLine(" ")
  GameTooltip:AddLine(L.MEMBER_CLICK_HINT, 0.6, 0.6, 0.6, true)
  GameTooltip:Show()
end

-- Guild invite box --------------------------------------------------------------------------------

local inviteBox

local function TargetSuggestion()
  if not UnitExists("target") or not UnitIsPlayer("target") or UnitIsUnit("target", "player") then return nil end
  if GetGuildInfo("target") then return nil end
  local full = (rawget(_G, "GetUnitName") and GetUnitName("target", true)) or UnitName("target")
  return full
end

local function BuildInvite()
  local L = ns.L
  inviteBox = W.Box(UIParent, 0.06, 0.9)
  inviteBox:SetSize(260, 196)
  inviteBox:SetFrameStrata("DIALOG")
  inviteBox:EnableMouse(true)
  inviteBox:SetClampedToScreen(true)
  local title = W.Text(inviteBox, "GameFontNormal", L.INVITE_TITLE)
  title:SetPoint("TOPLEFT", 12, -10)
  inviteBox.Edit = W.EditBox(inviteBox, 232)
  inviteBox.Edit:SetPoint("TOPLEFT", 16, -30)
  inviteBox.Edit:SetScript("OnEnterPressed", function() inviteBox.Accept() end)
  inviteBox.Edit:SetScript("OnEscapePressed", function() inviteBox:Hide() end)
  local hint = W.Text(inviteBox, "GameFontDisableSmall", L.INVITE_SUGGESTIONS)
  hint:SetPoint("TOPLEFT", 12, -56)
  inviteBox.Suggestions = {}
  for i = 1, 5 do
    local b = W.Button(inviteBox, "", function(self)
      inviteBox.Edit:SetText(self.full or "")
      inviteBox.Edit:SetFocus()
    end, 236, { small = true })
    b:SetPoint("TOPLEFT", 12, -70 - (i - 1) * 20)
    b:SetHeight(18)
    inviteBox.Suggestions[i] = b
  end
  inviteBox.Ok = W.Button(inviteBox, L.INVITE, function() inviteBox.Accept() end, 110)
  inviteBox.Ok:SetPoint("BOTTOMLEFT", 12, 10)
  inviteBox.Cancel = W.Button(inviteBox, CANCEL or "Cancel", function() inviteBox:Hide() end, 110)
  inviteBox.Cancel:SetPoint("BOTTOMRIGHT", -12, 10)
  function inviteBox.Accept()
    local name = ns.Names.Trim(inviteBox.Edit:GetText() or "")
    if name ~= "" then
      ns.Roster.Invite(name)
      ns.Print(L.INVITE_SENT:format(ns.Names.Normalize(name)))
    end
    inviteBox:Hide()
  end
  inviteBox:Hide()
end

function UI.ShowInvite(anchor)
  if not inviteBox then BuildInvite() end
  inviteBox:ClearAllPoints()
  inviteBox:SetPoint("BOTTOMRIGHT", anchor, "TOPRIGHT", 0, 4)
  local suggestions = {}
  local target = TargetSuggestion()
  if target then suggestions[#suggestions + 1] = { name = ns.Names.Normalize(target), full = target, target = true } end
  for _, w in ipairs(ns.Chat.RecentWhispers()) do
    if #suggestions < 5 and not (target and ns.Names.Same(w.full, target)) then suggestions[#suggestions + 1] = w end
  end
  for i, button in ipairs(inviteBox.Suggestions) do
    local s = suggestions[i]
    if s then
      button.full = s.full
      button:SetText(s.target and ns.L.INVITE_TARGET:format(s.name) or ns.L.INVITE_WHISPERED:format(s.name))
      button:Show()
    else
      button:Hide()
    end
  end
  inviteBox:SetHeight(110 + math.max(1, #suggestions) * 20)
  inviteBox.Edit:SetText(target or "")
  inviteBox:Show()
  inviteBox.Edit:SetFocus()
end
