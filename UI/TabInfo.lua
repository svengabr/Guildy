-- Info & log tab: message of the day and guild information (edited right here with permission, saved
-- in Blizzard's own edit box shown here, UI/Commands.lua), the guild event log, Guildy settings, and
-- buttons to the Ranks tab and Blizzard's window.
local _, ns = ...
local W = ns.Widgets
local UI = ns.UI

local EVENT_FORMATS = {
  invite = "GUILDEVENT_TYPE_INVITE", join = "GUILDEVENT_TYPE_JOIN", promote = "GUILDEVENT_TYPE_PROMOTE",
  demote = "GUILDEVENT_TYPE_DEMOTE", remove = "GUILDEVENT_TYPE_REMOVE", quit = "GUILDEVENT_TYPE_QUIT",
}

local function EventLines()
  local lines = {}
  local count = ns.Try(rawget(_G, "GetNumGuildEvents")) or 0
  local getInfo = rawget(_G, "GetGuildEventInfo")
  for i = count, 1, -1 do
    local kind, player1, player2, rank, years, months, days, hours = ns.Try(getInfo, i)
    if kind then
      local fmt = rawget(_G, EVENT_FORMATS[kind] or "") or ns.L["EVENT_" .. kind:upper()]
      local text
      if type(fmt) == "string" then
        local ok, result = pcall(string.format, fmt, ns.Names.Normalize(player1 or "?"), ns.Names.Normalize(player2 or "?"), rank or "")
        text = ok and result or (kind .. " " .. tostring(player1))
      else
        text = kind .. " " .. tostring(player1)
      end
      local ago = ns.Census.DaysOffline(years, months, days, hours)
      local m = { online = false, daysOffline = ago }
      lines[#lines + 1] = { text = text, when = ago and ns.Roster.LastOnlineText(m) or "" }
    end
  end
  return lines
end

-- In-place editor for the MOTD or guild info box: Edit sets Blizzard's editor up, Save hands it the text
local function Editor(view, box, kind, label)
  local L = ns.L
  local editor = { kind = kind, label = label }

  editor.Edit = W.Button(box, L.EDIT, nil, 70, { small = true })
  editor.Edit:SetPoint("TOPRIGHT", -8, -6)
  UI.SecureAction(editor.Edit, function()
    if UI.Action.TextEditReady(kind) then
      return UI.Action.TextEdit(kind, function() editor:Begin() end)
    end
    return UI.Action.LoadBlizzard(ns.L.EDIT_FIRST_TIME)
  end)

  editor.Cancel = W.Button(box, L.CANCEL, function() editor:Finish() end, 70, { small = true })
  editor.Cancel:SetPoint("TOPRIGHT", -8, -6)
  editor.Save = W.Button(box, L.SAVE, nil, 70, { small = true })
  editor.Save:SetPoint("RIGHT", editor.Cancel, "LEFT", -4, 0)
  UI.SecureAction(editor.Save, function()
    return UI.Action.TextSave(kind, function()
      editor:Finish()
      C_Timer.After(1.5, function() view:Refresh() end)
    end)
  end)
  editor.Cancel:Hide()
  editor.Save:Hide()

  -- Blizzard's own edit box, filled by Blizzard with the current text; the player types into it
  function editor:Begin()
    if not UI.Action.BorrowTextBox(box, 6, -26, -6, 6) then return end
    self.editing = true
    self.label:Hide()
    self.Edit:Hide()
    self.Save:Show()
    self.Cancel:Show()
  end

  function editor:Finish()
    if not self.editing then return end
    self.editing = false
    UI.Action.ReturnTextBox()
    self.Save:Hide()
    self.Cancel:Hide()
    self.label:Show()
    self.Edit:SetShown(self.allowed)
  end
  box:HookScript("OnHide", function() editor:Finish() end)

  function editor:Update(_, allowed)
    self.allowed = allowed
    if not self.editing then self.Edit:SetShown(allowed) end
  end

  return editor
end

-- Preferred play settings (guild language and region). Not protected on Forever (a direct call raised
-- no ADDON_ACTION_FORBIDDEN), unlike most guild settings. Changes have a cooldown of some days.

-- Blizzard's own label if the client has it, else Guildy's
function UI.PlayText(global, fallback)
  local text = rawget(_G, global)
  return type(text) == "string" and text or fallback
end

-- { {id, name} } for "locale" or "datacenter"
function UI.PlayOptions(kind)
  local services = rawget(_G, "C_AccountServices")
  local get = services and (kind == "locale" and services.GetPreferredLocales or services.GetPreferredDatacenterLocalities)
  local ids, names = ns.Try(get)
  local list = {}
  for i, id in ipairs(type(ids) == "table" and ids or {}) do
    list[#list + 1] = { id = id, name = (type(names) == "table" and names[i]) or tostring(id) }
  end
  return list
end

function UI.PlayName(kind, id)
  for _, option in ipairs(UI.PlayOptions(kind)) do
    if option.id == id then return option.name end
  end
  return (id and id ~= 0) and tostring(id) or "-"
end

local function Lockout(lastChange, days)
  if type(lastChange) ~= "number" or lastChange <= 0 or type(days) ~= "number" then return 0 end
  return math.max(0, lastChange + days * 86400 - (ns.Try(rawget(_G, "time")) or 0))
end

function UI.PlayLockoutText(seconds)
  local fmt = UI.PlayText("PREFERRED_PLAY_SETTINGS_LOCKED_REASON_FORMAT", ns.L.PLAY_LOCKED)
  local toTime = rawget(_G, "SecondsToTime")
  local ok, text = pcall(string.format, fmt, toTime and toTime(seconds) or (math.ceil(seconds / 86400) .. " d"))
  return ok and text or fmt
end

-- { loaded, locale = {id, available, lockout}, datacenter = {...} } or nil
function UI.PlaySettings()
  local gi = C_GuildInfo
  if not (gi and gi.GetPreferredPlaySettings) then return nil end
  local loaded, localeID, datacenterID, lastLocale, lastDatacenter, days = ns.Try(gi.GetPreferredPlaySettings)
  local canLocale, canDatacenter = ns.Try(gi.GetPreferredPlaySettingsFeatures)
  return {
    loaded = loaded and true or false,
    locale = { id = localeID, available = canLocale and true or false, lockout = Lockout(lastLocale, days) },
    datacenter = { id = datacenterID, available = canDatacenter and true or false, lockout = Lockout(lastDatacenter, days) },
  }
end

local function Build(panel)
  local L = ns.L
  local view = {}

  local left = CreateFrame("Frame", nil, panel)
  left:SetPoint("TOPLEFT", 0, 0)
  left:SetPoint("BOTTOMRIGHT", panel, "BOTTOM", -4, 0)

  -- MOTD
  local motd = W.Box(left)
  motd:SetPoint("TOPLEFT", 50, 0) -- clear of the portrait
  motd:SetPoint("TOPRIGHT", 0, 0)
  motd:SetHeight(84)
  local motdTitle = W.Text(motd, "GameFontNormal", L.MOTD)
  motdTitle:SetPoint("TOPLEFT", 10, -8)
  view.Motd = W.Text(motd, "GameFontHighlight")
  view.Motd:SetPoint("TOPLEFT", 10, -28)
  view.Motd:SetPoint("RIGHT", -10, 0)
  view.MotdEditor = Editor(view, motd, "motd", view.Motd)

  -- guild info
  local info = W.Box(left)
  info:SetPoint("TOPLEFT", motd, "BOTTOMLEFT", 0, -8)
  info:SetPoint("RIGHT", 0, 0)
  info:SetPoint("BOTTOM", left, "BOTTOM", 0, 172)
  local infoTitle = W.Text(info, "GameFontNormal", L.GUILD_INFO)
  infoTitle:SetPoint("TOPLEFT", 10, -8)
  view.Info = W.Text(info, "GameFontHighlightSmall")
  view.Info:SetPoint("TOPLEFT", 10, -28)
  view.Info:SetPoint("BOTTOMRIGHT", -10, 8)
  view.Info:SetJustifyV("TOP")
  view.InfoEditor = Editor(view, info, "info", view.Info)

  -- settings
  local settings = W.Box(left)
  settings:SetPoint("TOPLEFT", info, "BOTTOMLEFT", 0, -8)
  settings:SetPoint("BOTTOMRIGHT", 0, 0)
  local settingsTitle = W.Text(settings, "GameFontNormal", L.SETTINGS)
  settingsTitle:SetPoint("TOPLEFT", 10, -8)
  local share = CreateFrame("CheckButton", nil, settings, "UICheckButtonTemplate")
  share:SetSize(24, 24)
  share:SetPoint("TOPLEFT", 8, -24)
  share:SetScript("OnClick", function(self) ns.Settings().share = self:GetChecked() and true or false end)
  W.Tooltip(share, L.SHARE, L.SHARE_TIP)
  local shareLabel = W.Text(settings, "GameFontHighlightSmall", L.SHARE)
  shareLabel:SetPoint("LEFT", share, "RIGHT", 2, 0)
  view.Share = share

  -- preferred play settings (language, region): the guild master changes them, everyone sees them
  view.PlayRows = {}
  for i, kind in ipairs({ "locale", "datacenter" }) do
    local row = CreateFrame("Frame", nil, settings)
    row:SetHeight(24)
    row:SetPoint("TOPLEFT", 12, -52 - (i - 1) * 28)
    row:SetPoint("RIGHT", -10, 0)
    row.Label = W.Text(row, "GameFontNormalSmall", kind == "locale" and UI.PlayText("PREFERRED_LOCALE_LABEL", L.PLAY_LOCALE)
      or UI.PlayText("PREFERRED_GUILD_DATACENTER_LOCALITY_LABEL", L.PLAY_REGION))
    row.Label:SetPoint("LEFT", 0, 0)
    row.Label:SetWidth(150)
    row.Label:SetWordWrap(false)
    row.Menu = W.MenuButton(row, "", function()
      local items = {}
      for _, option in ipairs(UI.PlayOptions(kind)) do
        items[#items + 1] = { text = option.name, checked = view.staged[kind] == option.id, onClick = function()
          view.staged[kind] = option.id
          view:Refresh()
        end }
      end
      return items
    end, 140)
    row.Menu:SetPoint("LEFT", row.Label, "RIGHT", 4, 0)
    row.Value = W.Text(row, "GameFontHighlightSmall")
    row.Value:SetPoint("LEFT", row.Label, "RIGHT", 8, 0)
    row.Apply = W.Button(row, UI.PlayText("APPLY", L.APPLY), function()
      local id = view.staged[kind]
      local apply = C_GuildInfo and C_GuildInfo.SetPreferredPlaySettings
      if id and apply then
        if kind == "locale" then ns.Try(apply, id, 0) else ns.Try(apply, 0, id) end
        C_Timer.After(1, function() view:Refresh() end)
      end
    end, 80, { small = true })
    row.Apply:SetPoint("LEFT", row.Menu, "RIGHT", 4, 0)
    row.Apply:SetMotionScriptsWhileDisabled(true)
    row.Apply:SetScript("OnEnter", function(self)
      if not self.tip then return end
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      GameTooltip:SetText(self.tip, 1, 1, 1, 1, true)
      GameTooltip:Show()
    end)
    row.Apply:SetScript("OnLeave", function() GameTooltip:Hide() end)
    row.kind = kind
    view.PlayRows[i] = row
  end
  view.staged = {}

  local control = W.Button(settings, L.GUILD_CONTROL, function() UI.SelectTab("ranks") end, 150, { small = true })
  control:SetPoint("BOTTOMLEFT", 10, 8)
  local blizzard = W.Button(settings, L.OPEN_BLIZZARD, nil, 150, { small = true })
  UI.SecureAction(blizzard, UI.Action.BlizzardWindow)
  blizzard:SetPoint("LEFT", control, "RIGHT", 6, 0)

  -- event log
  local log = W.Box(panel)
  log:SetPoint("TOPLEFT", panel, "TOP", 4, 0)
  log:SetPoint("BOTTOMRIGHT", 0, 0)
  local logTitle = W.Text(log, "GameFontNormal", L.EVENT_LOG)
  logTitle:SetPoint("TOPLEFT", 10, -8)
  view.Log = W.ScrollList(log, 18, function(row)
    row.Text = W.Text(row, "GameFontHighlightSmall")
    row.Text:SetPoint("LEFT", 4, 0)
    row.Text:SetPoint("RIGHT", -70, 0)
    row.Text:SetWordWrap(false)
    row.When = W.Text(row, "GameFontDisableSmall")
    row.When:SetPoint("RIGHT", -4, 0)
    row.When:SetJustifyH("RIGHT")
    row:EnableMouse(true)
    row:SetScript("OnEnter", function(self)
      if self.Text:IsTruncated() then
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(self.Text:GetText(), 1, 1, 1, 1, true)
        GameTooltip:Show()
      end
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
  end, function(row, line)
    row.Text:SetText(line.text)
    row.When:SetText(line.when)
  end)
  view.Log:SetPoint("TOPLEFT", 8, -28)
  view.Log:SetPoint("BOTTOMRIGHT", -28, 8)

  function view:Refresh()
    local can = ns.Roster.Can()
    -- C_GuildInfo.GetMOTD is protected on Forever (ADDON_ACTION_BLOCKED even inside pcall):
    -- only used when the old roster function is missing
    local getMotd = rawget(_G, "GetGuildRosterMOTD") or (C_GuildInfo and C_GuildInfo.GetMOTD)
    local motdText = ns.Try(getMotd) or ""
    self.Motd:SetText(motdText ~= "" and motdText or ("|cff999999" .. L.EMPTY .. "|r"))
    self.MotdEditor:Update(motdText, can.editMotd)
    local get = (C_GuildInfo and C_GuildInfo.GetInfoText) or rawget(_G, "GetGuildInfoText")
    local infoText = ns.Try(get) or ""
    self.Info:SetText(infoText ~= "" and infoText or ("|cff999999" .. L.EMPTY .. "|r"))
    self.InfoEditor:Update(infoText, can.editInfo)
    self.Share:SetChecked(ns.Settings().share and true or false)
    self:RefreshPlay()
    self.Log:SetItems(EventLines())
  end

  function view:RefreshPlay()
    local play = UI.PlaySettings()
    local leader = ns.Roster.Can().leader
    for _, row in ipairs(self.PlayRows) do
      local current = play and play[row.kind]
      local shown = current ~= nil and current.available
      row:SetShown(shown)
      if shown then
        local staged = self.staged[row.kind] or current.id
        local name = UI.PlayName(row.kind, staged)
        row.Menu:SetShown(leader)
        row.Apply:SetShown(leader)
        row.Value:SetShown(not leader)
        row.Value:SetText(name)
        row.Menu:SetText(name)
        local lockout = current.lockout
        row.Apply:SetEnabled(play.loaded and lockout == 0 and staged ~= current.id)
        row.Apply.tip = lockout > 0 and UI.PlayLockoutText(lockout) or ns.L.PLAY_APPLY_TIP
      end
    end
  end

  function view:OnShow()
    local query = rawget(_G, "QueryGuildEventLog")
    if query then pcall(query) end
    self.staged = {}
    local request = C_GuildInfo and C_GuildInfo.RequestPreferredPlaySettings
    if request then ns.Try(request) end
  end

  return view
end

UI.RegisterTab("info", 5, ns.L.TAB_INFO, Build)
