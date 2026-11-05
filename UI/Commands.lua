-- Guild management (invite, remove, promote, demote, MOTD) is reserved for Blizzard's UI on Forever:
-- addons can't call it and macros are blocked too. Typed into the chat box it works, so Guildy puts
-- the slash command (/ginvite Name, ...) into the chat input and the player sends it with Enter.
-- The invite dialog here only collects the name (with suggestions).
local _, ns = ...
local W = ns.Widgets
local UI = ns.UI

local SLASH = {
  invite = { "SLASH_GUILD_INVITE1", "/ginvite" },
  remove = { "SLASH_GUILD_UNINVITE1", "/gremove" },
  promote = { "SLASH_GUILD_PROMOTE1", "/gpromote" },
  demote = { "SLASH_GUILD_DEMOTE1", "/gdemote" },
  motd = { "SLASH_GUILD_MOTD1", "/gmotd" },
}

-- "/ginvite Xii-Lightspark" for a command kind and an argument (names in server form)
function UI.SlashCommand(kind, argument)
  local entry = SLASH[kind]
  local command = rawget(_G, entry[1])
  if type(command) ~= "string" or command == "" then command = entry[2] end
  if kind ~= "motd" then argument = ns.Names.ToServer(argument) end
  return command .. " " .. (argument or "")
end

-- Opens the chat input with the command; the player confirms with Enter
function UI.CommandToChat(kind, argument)
  local text = UI.SlashCommand(kind, argument)
  local open = rawget(_G, "ChatFrame_OpenChat") or (ChatFrameUtil and ChatFrameUtil.OpenChat)
  if open then
    pcall(open, text)
    ns.Print(ns.L.PRESS_ENTER)
  else
    ns.Print(ns.L.TYPE_COMMAND:format(text))
  end
end

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

  local function Accept()
    local name = ns.Names.Trim(dialog.Edit:GetText() or "")
    dialog:Hide()
    if name ~= "" then UI.CommandToChat("invite", name) end
  end

  dialog.Edit = W.EditBox(dialog, 270)
  dialog.Edit:SetPoint("TOPLEFT", 16, -32)
  dialog.Edit:SetMaxLetters(48)
  dialog.Edit:SetScript("OnEnterPressed", Accept)
  dialog.Edit:SetScript("OnEscapePressed", function() dialog:Hide() end)

  dialog.Hint = W.Text(dialog, "GameFontDisableSmall", L.INVITE_SUGGESTIONS)
  dialog.Hint:SetPoint("TOPLEFT", 12, -56)

  dialog.Suggestions = {}
  for i = 1, 5 do
    local b = W.Button(dialog, "", function(self)
      dialog.Edit:SetText(self.value or "")
      Accept()
    end, 276, { small = true })
    b:SetHeight(18)
    b:SetPoint("TOPLEFT", 12, -70 - (i - 1) * 20)
    dialog.Suggestions[i] = b
  end

  dialog.Ok = W.Button(dialog, L.INVITE, Accept, 130)
  dialog.Ok:SetPoint("BOTTOMLEFT", 12, 10)
  dialog.Cancel = W.Button(dialog, CANCEL or "Cancel", function() dialog:Hide() end, 130)
  dialog.Cancel:SetPoint("BOTTOMRIGHT", -12, 10)
  dialog:Hide()
end

-- suggestions = { {label, value} }; a click on one invites right away
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

-- Member actions: the command goes into the chat input, Enter confirms
function UI.ConfirmMemberCommand(kind, m)
  UI.CommandToChat(kind, m.fullName)
end
