-- Info & log tab: message of the day and guild information (editable with permission), the guild
-- event log, Guildy settings, and buttons into Blizzard's rank editor and window.
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

local function Build(panel)
  local L = ns.L
  local view = {}

  local left = CreateFrame("Frame", nil, panel)
  left:SetPoint("TOPLEFT", 0, 0)
  left:SetPoint("BOTTOMRIGHT", panel, "BOTTOM", -4, 0)

  -- MOTD
  local motd = W.Box(left)
  motd:SetPoint("TOPLEFT", 0, 0)
  motd:SetPoint("TOPRIGHT", 0, 0)
  motd:SetHeight(84)
  local motdTitle = W.Text(motd, "GameFontNormal", L.MOTD)
  motdTitle:SetPoint("TOPLEFT", 10, -8)
  view.Motd = W.Text(motd, "GameFontHighlight")
  view.Motd:SetPoint("TOPLEFT", 10, -28)
  view.Motd:SetPoint("RIGHT", -10, 0)
  view.MotdEdit = W.Button(motd, L.EDIT, function()
    local current = ns.Try(C_GuildInfo and C_GuildInfo.GetMOTD) or ns.Try(rawget(_G, "GetGuildRosterMOTD")) or ""
    UI.GuildCommand({ kind = "motd", title = L.MOTD, okText = L.SAVE, edit = current, maxLetters = 128,
      after = function() C_Timer.After(1, function() ns.Fire("INFO") end) end })
  end, 70, { small = true })
  view.MotdEdit:SetPoint("TOPRIGHT", -8, -6)

  -- guild info
  local info = W.Box(left)
  info:SetPoint("TOPLEFT", motd, "BOTTOMLEFT", 0, -8)
  info:SetPoint("RIGHT", 0, 0)
  info:SetPoint("BOTTOM", left, "BOTTOM", 0, 112)
  local infoTitle = W.Text(info, "GameFontNormal", L.GUILD_INFO)
  infoTitle:SetPoint("TOPLEFT", 10, -8)
  view.Info = W.Text(info, "GameFontHighlightSmall")
  view.Info:SetPoint("TOPLEFT", 10, -28)
  view.Info:SetPoint("BOTTOMRIGHT", -10, 8)
  view.Info:SetJustifyV("TOP")
  view.InfoEdit = W.Button(info, L.EDIT, function() UI.EditInBlizzard() end, 70, { small = true })
  W.Tooltip(view.InfoEdit, L.GUILD_INFO, L.EDIT_IN_BLIZZARD)
  view.InfoEdit:SetPoint("TOPRIGHT", -8, -6)

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
  local settingsHint = W.Text(settings, "GameFontDisableSmall", L.BLIZZARD_HINT)
  settingsHint:SetPoint("TOPLEFT", 12, -52)
  settingsHint:SetPoint("RIGHT", -10, 0)
  local control = W.Button(settings, L.GUILD_CONTROL, function() ns.OpenGuildControl() end, 150, { small = true })
  control:SetPoint("BOTTOMLEFT", 10, 8)
  view.Control = control
  local blizzard = W.Button(settings, L.OPEN_BLIZZARD, function() ns.OpenBlizzard() end, 150, { small = true })
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
    local motdText = ns.Try(C_GuildInfo and C_GuildInfo.GetMOTD) or ns.Try(rawget(_G, "GetGuildRosterMOTD")) or ""
    self.Motd:SetText(motdText ~= "" and motdText or ("|cff999999" .. L.EMPTY .. "|r"))
    self.MotdEdit:SetShown(can.editMotd)
    local get = (C_GuildInfo and C_GuildInfo.GetInfoText) or rawget(_G, "GetGuildInfoText")
    local infoText = ns.Try(get) or ""
    self.Info:SetText(infoText ~= "" and infoText or ("|cff999999" .. L.EMPTY .. "|r"))
    self.InfoEdit:SetShown(can.editInfo)
    self.Share:SetChecked(ns.Settings().share and true or false)
    self.Control:SetShown(can.leader or can.promote)
    self.Log:SetItems(EventLines())
  end

  function view:OnShow()
    local query = rawget(_G, "QueryGuildEventLog")
    if query then pcall(query) end
  end

  return view
end

UI.RegisterTab("info", 5, ns.L.TAB_INFO, Build)
