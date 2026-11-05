-- Member context menu (whisper, group invite, notes, rank, remove), the member tooltip and the
-- guild-invite box with suggestions.
local _, ns = ...
local W = ns.Widgets
local UI = ns.UI

-- Notes and the guild info text can't be changed by addons on Forever (and have no slash command):
-- those edits happen in Blizzard's window
function UI.EditInBlizzard()
  ns.Print(ns.L.EDIT_IN_BLIZZARD)
  ns.OpenBlizzard()
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
  if can.editPublic or can.editOfficer then
    items[#items + 1] = { text = L.EDIT_NOTES, onClick = UI.EditInBlizzard }
  end
  if can.promote then items[#items + 1] = { text = L.PROMOTE, onClick = function() UI.ConfirmMemberCommand("promote", m) end } end
  if can.demote then items[#items + 1] = { text = L.DEMOTE, onClick = function() UI.ConfirmMemberCommand("demote", m) end } end
  if can.remove then
    items[#items + 1] = { text = L.REMOVE, color = { 1, 0.3, 0.3 }, onClick = function() UI.ConfirmMemberCommand("remove", m) end }
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

-- Guild invite: name field with the unguilded target and recent whisperers as suggestions; the invite
-- itself goes into the chat input as /ginvite (UI/Commands.lua)

local function TargetSuggestion()
  if not UnitExists("target") or not UnitIsPlayer("target") or UnitIsUnit("target", "player") then return nil end
  if GetGuildInfo("target") then return nil end
  return (rawget(_G, "GetUnitName") and GetUnitName("target", true)) or UnitName("target")
end

function UI.ShowInvite(anchor)
  local L = ns.L
  local suggestions = {}
  local target = TargetSuggestion()
  if target then suggestions[#suggestions + 1] = { label = L.INVITE_TARGET:format(ns.Names.Normalize(target)), value = target } end
  for _, w in ipairs(ns.Chat.RecentWhispers()) do
    if #suggestions < 5 and not (target and ns.Names.Same(w.full, target)) then
      suggestions[#suggestions + 1] = { label = L.INVITE_WHISPERED:format(w.name), value = w.full }
    end
  end
  UI.InviteDialog(anchor, target, suggestions)
end
