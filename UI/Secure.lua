-- Guild management calls (invite, remove, promote, demote, MOTD) are blocked for addon code on
-- Forever. The guild slash commands are not: a secure action button the player clicks runs them as a
-- macro (/ginvite Name, ...). This dialog holds that button. It is parented to UIParent (never to the
-- Guildy window, which would otherwise become protected and could not be closed in combat) and only
-- opens out of combat. Enter clicks the button through an override binding.
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

local dialog

local function Build()
  dialog = W.Box(UIParent, 0.06, 0.9)
  dialog:SetSize(300, 140)
  dialog:SetFrameStrata("DIALOG")
  dialog:EnableMouse(true)
  dialog:SetClampedToScreen(true)
  dialog:SetMovable(true)
  dialog:RegisterForDrag("LeftButton")
  dialog:SetScript("OnDragStart", dialog.StartMoving)
  dialog:SetScript("OnDragStop", dialog.StopMovingOrSizing)

  dialog.Title = W.Text(dialog, "GameFontNormal")
  dialog.Title:SetPoint("TOPLEFT", 12, -10)
  dialog.Title:SetPoint("RIGHT", -12, 0)

  dialog.Edit = W.EditBox(dialog, 270)
  dialog.Edit:SetPoint("TOPLEFT", 16, -32)
  dialog.Edit:SetScript("OnTextChanged", function() dialog:UpdateCommand() end)
  -- Enter leaves the field; the next Enter (override binding) clicks the secure button
  dialog.Edit:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
  dialog.Edit:SetScript("OnEscapePressed", function() dialog:Close() end)

  dialog.Hint = W.Text(dialog, "GameFontDisableSmall")
  dialog.Hint:SetPoint("TOPLEFT", 12, -56)

  dialog.Suggestions = {}
  for i = 1, 5 do
    local b = W.Button(dialog, "", function(self)
      dialog.Edit:SetText(self.value or "")
      dialog.Edit:ClearFocus()
    end, 276, { small = true })
    b:SetHeight(18)
    b:SetPoint("TOPLEFT", 12, -70 - (i - 1) * 20)
    dialog.Suggestions[i] = b
  end

  local ok = CreateFrame("Button", "GuildySecureButton", dialog, "SecureActionButtonTemplate,UIPanelButtonTemplate")
  ok:SetSize(130, 22)
  ok:SetPoint("BOTTOMLEFT", 12, 10)
  ok:RegisterForClicks("AnyUp", "AnyDown")
  ok:SetAttribute("type", "macro")
  ok:SetScript("PostClick", function()
    if dialog.after then ns.SafeCall(dialog.after, dialog.value) end
    C_Timer.After(0, function() dialog:Close() end)
    if ns.Roster then C_Timer.After(1, function() ns.Roster.Request(true) end) end
  end)
  dialog.Ok = ok

  dialog.Cancel = W.Button(dialog, CANCEL or "Cancel", function() dialog:Close() end, 130)
  dialog.Cancel:SetPoint("BOTTOMRIGHT", -12, 10)

  function dialog:UpdateCommand()
    if InCombatLockdown() then return end
    local value = self.hasEdit and ns.Names.Trim(self.Edit:GetText() or "") or self.fixed
    self.value = value
    local valid = value ~= nil and (value ~= "" or self.kind == "motd")
    self.Ok:SetAttribute("macrotext", valid and UI.SlashCommand(self.kind, value) or "")
    self.Ok:SetEnabled(valid)
  end

  function dialog:Close()
    if InCombatLockdown() then return end
    ClearOverrideBindings(self)
    self:Hide()
  end

  dialog:SetScript("OnHide", function(self)
    if not InCombatLockdown() then ClearOverrideBindings(self) end
  end)
  dialog:Hide()
end

-- opts = { kind = "invite"|"remove"|"promote"|"demote"|"motd", title, okText, edit = initial text or nil,
--          fixed = argument when there is no edit field, maxLetters, hint, suggestions = { {label, value} },
--          after = function(value) run after the click, anchor = frame or nil (centered) }
function UI.GuildCommand(opts)
  if InCombatLockdown() then
    ns.Print(ns.L.NOT_IN_COMBAT)
    return
  end
  if not dialog then Build() end
  dialog.kind, dialog.after, dialog.fixed = opts.kind, opts.after, opts.fixed
  dialog.hasEdit = opts.edit ~= nil
  dialog.Title:SetText(opts.title or "")
  dialog.Ok:SetText(opts.okText or ACCEPT or "OK")
  dialog.Edit:SetMaxLetters(opts.maxLetters or 64)
  dialog.Edit:SetShown(dialog.hasEdit)
  dialog.Edit:SetText(opts.edit or "")

  local suggestions = opts.suggestions or {}
  dialog.Hint:SetText(#suggestions > 0 and (opts.hint or "") or "")
  for i, button in ipairs(dialog.Suggestions) do
    local s = suggestions[i]
    button.value = s and s.value
    button:SetText(s and s.label or "")
    button:SetShown(s ~= nil)
  end
  local height = dialog.hasEdit and 96 or 72
  if #suggestions > 0 then height = height + 18 + #suggestions * 20 end
  dialog:SetHeight(height)

  dialog:ClearAllPoints()
  if opts.anchor then
    dialog:SetPoint("BOTTOMRIGHT", opts.anchor, "TOPRIGHT", 0, 4)
  else
    dialog:SetPoint("CENTER", 0, 120)
  end
  dialog:UpdateCommand()
  dialog:Show()
  SetOverrideBindingClick(dialog, true, "ENTER", "GuildySecureButton", "LeftButton")
  if dialog.hasEdit then
    dialog.Edit:SetFocus()
    dialog.Edit:HighlightText()
  end
end

-- Shortcuts for member actions
function UI.ConfirmMemberCommand(kind, m)
  local L = ns.L
  local titles = { remove = L.REMOVE_CONFIRM, promote = L.PROMOTE_CONFIRM, demote = L.DEMOTE_CONFIRM }
  local buttons = { remove = L.REMOVE_SHORT, promote = L.PROMOTE, demote = L.DEMOTE }
  UI.GuildCommand({ kind = kind, title = titles[kind]:format(m.name), okText = buttons[kind], fixed = m.fullName })
end
