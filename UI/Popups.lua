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

-- Context menu for a roster member
function UI.MemberMenu(m, anchor)
  local L, R = ns.L, ns.Roster
  local can = R.Can()
  local items = {
    { text = W.ClassName(m.name, m.classFile), isTitle = true },
    { text = L.WHISPER, onClick = function() UI.Whisper(m.fullName) end, disabled = not m.online },
    { text = L.GROUP_INVITE, onClick = function() R.GroupInvite(m) end, disabled = not m.online },
  }
  local rights = R.Rights(m)
  if can.promote then
    items[#items + 1] = { text = L.PROMOTE, disabled = not rights.promote, action = function() return UI.Action.Manage("promote", m) end }
  end
  if can.demote then
    items[#items + 1] = { text = L.DEMOTE, disabled = not rights.demote, action = function() return UI.Action.Manage("demote", m) end }
  end
  if can.remove then
    items[#items + 1] = { text = L.REMOVE, disabled = not rights.remove, onClick = function()
      UI.Confirm(L.REMOVE_CONFIRM:format(W.ClassName(m.name, m.classFile)), UI.Action.Manage("remove", m))
    end }
  end
  if can.editPublic or can.editOfficer then
    items[#items + 1] = { text = L.NOTES_IN_BLIZZARD, action = UI.Action.BlizzardWindow }
  end
  W.OpenMenu(anchor, items, 200)
end

-- Tooltip for a roster member (owner frame given)
function UI.MemberTooltip(owner, m)
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
  GameTooltip:AddLine(L.MEMBER_CLICK_HINT, 0.6, 0.6, 0.6, true)
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