-- Members tab: search, filters (class, rank, online only, without note) and sortable columns;
-- level and profession only come as drill-downs from the overview.
-- Twinks hang under their main (or fold into it, Core/Family.lua).
-- A click on a member opens the character page (UI/CharacterPage.lua), a right click the member menu.
local _, ns = ...
local W = ns.Widgets
local UI = ns.UI

local ROW = 18
local CLASSES = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }
local COLUMNS = {
  { key = "level", width = 34, desc = true },
  { key = "name", width = 175 },
  { key = "rank", width = 100 },
  { key = "ilvl", width = 44, desc = true },
  { key = "zone", width = 120 },
  { key = "lastOnline", width = 70 },
  { key = "guildy", width = 46, desc = true },
  { key = "note", width = 210 },
  { key = "officerNote", width = 0 }, -- rest; only for those who may read officer notes
}
local UNSORTED = { note = true, officerNote = true }
local REST_WIDTH = 200 -- a rest column's width when another column follows it
-- The columns the player can hide (settings.memberColumns[key] = false, Guildy's options); level and
-- name always stay
UI.MEMBER_COLUMNS = { "rank", "ilvl", "zone", "lastOnline", "guildy", "note", "officerNote" }
local function ColumnOff(key)
  local chosen = ns.Settings().memberColumns
  return type(chosen) == "table" and chosen[key] == false
end
local DOT = "|TInterface\\AddOns\\Guildy\\Textures\\Dot:8:8:0:0:32:32:0:32:0:32:%d:%d:%d|t "

local ONLINE_COLOR = { 0.3, 0.9, 0.3 }

-- Guildy version of an online member as colored text: green = same or newer than mine, orange = older
function UI.GuildyVersionText(m)
  local version = m.online and ns.Sync.UserVersion(m.name)
  if not version then return nil end
  if version == "" then return "|cffff9933" .. ns.L.GUILDY_OLD .. "|r" end
  local cmp = ns.Protocol.CompareVersions(version, ns.Version())
  return (cmp == -1 and "|cffff9933" or "|cff4ce64c") .. version .. "|r"
end

local function ClassLabel(classFile)
  local male = rawget(_G, "LOCALIZED_CLASS_NAMES_MALE")
  return male and male[classFile] or classFile
end

local function ClassIcon(classFile)
  local coords = rawget(_G, "CLASS_ICON_TCOORDS")
  local c = classFile and coords and coords[classFile]
  if not c then return "" end
  return ("|TInterface\\TargetingFrame\\UI-Classes-Circles:14:14:0:0:256:256:%d:%d:%d:%d|t "):format(
    c[1] * 256, c[2] * 256, c[3] * 256, c[4] * 256)
end

-- How the list tells online from offline (settings.memberStyle, Guildy's options):
--   "sections" = online above offline, each under its own header (default)
--   "grey"     = one list, offline names lose their class color
--   "dot"      = one list, a green or grey dot before the name
UI.MEMBER_STYLES = { "sections", "grey", "dot" }
function UI.MemberStyle()
  local style = ns.Settings().memberStyle
  for _, known in ipairs(UI.MEMBER_STYLES) do
    if style == known then return style end
  end
  return "sections"
end

-- A member's name cell in a style: text (class icon, name) and the cell's alpha. Shared with the
-- preview in Guildy's options.
function UI.MemberNameText(name, classFile, online, style)
  local text
  if style == "grey" and not online then
    text = ClassIcon(classFile) .. "|cff8a8a8a" .. name .. "|r"
  else
    text = ClassIcon(classFile) .. W.ClassName(name, classFile)
  end
  if style == "dot" then
    text = (online and DOT:format(76, 230, 76) or DOT:format(110, 110, 110)) .. text
  end
  return text, online and 1 or (style == "grey" and 0.75 or 0.5)
end

-- average item level of a member from the statistics (tenths), nil when unknown
local function ItemLevel(guild, m)
  local record = guild and guild.members[m.key]
  local values = record and type(record.stats) == "table" and record.stats.v
  return values and values[ns.Stats.GEAR.ILVL] or nil
end

local function Build(panel)
  local L = ns.L
  local view = { filter = {}, query = "", sort = "level", desc = true }

  -- toolbar ------------------------------------------------------------------------------------
  local page = W.Page(panel)
  local main, bar = page.Body, page.Bar

  local search = page:Left(W.EditBox(bar, W.SEARCH_W), 6) -- 6: the edit box art starts left of its frame
  search.Hint = W.Text(search, "GameFontDisableSmall", L.SEARCH_MEMBERS)
  search.Hint:SetPoint("LEFT", 2, 0)
  search:SetScript("OnTextChanged", function(self)
    view.query = self:GetText() or ""
    self.Hint:SetShown(view.query == "")
    view:Refresh()
  end)
  search:SetScript("OnEnterPressed", search.ClearFocus)

  view.ClassButton = W.MenuButton(bar, L.FILTER_CLASS, function()
    local items = { { text = L.ALL, checked = view.filter.classFile == nil, onClick = function() view:SetFilterValue("classFile", nil) end } }
    for _, classFile in ipairs(CLASSES) do
      local r, g, b = W.ClassColor(classFile)
      items[#items + 1] = { text = ClassLabel(classFile), color = { r, g, b }, checked = view.filter.classFile == classFile,
        onClick = function() view:SetFilterValue("classFile", classFile) end }
    end
    return items
  end, 90, 150)
  page:Left(view.ClassButton, 8)

  -- the guild's ranks that have members, the guild master's first
  view.RankButton = W.MenuButton(bar, L.FILTER_RANK, function()
    local items = { { text = L.ALL, checked = view.filter.rankIndex == nil, onClick = function() view:SetFilterValue("rankIndex", nil) end } }
    for _, rank in ipairs(view.ranks or {}) do
      items[#items + 1] = { text = rank.name, checked = view.filter.rankIndex == rank.index,
        onClick = function() view:SetFilterValue("rankIndex", rank.index) end }
    end
    return items
  end, 90, 170)
  page:Left(view.RankButton)

  for _, button in ipairs({ view.ClassButton, view.RankButton }) do
    button:SetScript("OnEnter", function(self)
      if not self.tip then return end
      GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
      GameTooltip:SetText(self.tip)
      GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
  end

  local function Check(label, anchor, onClick)
    local check = CreateFrame("CheckButton", nil, bar, "UICheckButtonTemplate")
    check:SetSize(24, 24)
    check:SetPoint("LEFT", anchor, "RIGHT", 6, 0)
    check:SetScript("OnClick", onClick)
    check.Label = W.Text(bar, "GameFontHighlightSmall", label)
    check.Label:SetPoint("LEFT", check, "RIGHT", 0, 0)
    return check
  end
  local onlineCheck = Check(L.ONLINE_ONLY, view.RankButton, function(self) view:SetFilterValue("onlineOnly", self:GetChecked() or nil) end)
  view.OnlineCheck = onlineCheck
  -- members whose public note is empty: who still needs one
  view.NoNoteCheck = Check(L.NO_NOTE, onlineCheck.Label, function(self) view.noNote = self:GetChecked() or nil; view:Refresh() end)
  -- the same for the officer note, only for those who may read it
  view.NoOfficerNoteCheck = Check(L.NO_OFFICER_NOTE, view.NoNoteCheck.Label, function(self)
    view.noOfficerNote = self:GetChecked() or nil
    view:Refresh()
  end)
  view.FoldCheck = Check(L.FOLD_TWINKS, view.NoOfficerNoteCheck.Label, function(self) view.fold = self:GetChecked() or nil; view:Refresh() end)

  view.Reset = W.Button(bar, L.RESET, function()
    view.filter, view.noNote, view.noOfficerNote = {}, nil, nil
    search:SetText("")
    onlineCheck:SetChecked(false)
    view.NoNoteCheck:SetChecked(false)
    view.NoOfficerNoteCheck:SetChecked(false)
    view:Refresh()
  end, 70, { small = true })
  page:Right(view.Reset)

  -- header -------------------------------------------------------------------------------------
  -- the list box fills the body like every view's boxes; the column header is its first row
  local listBox = W.Box(main)
  listBox:SetAllPoints()
  local header = CreateFrame("Frame", nil, listBox)
  header:SetPoint("TOPLEFT", 0, -4)
  header:SetPoint("RIGHT", listBox, "RIGHT", 0, 0)
  header:SetHeight(20)
  local headerLine = header:CreateTexture(nil, "ARTWORK")
  headerLine:SetPoint("BOTTOMLEFT", 6, -1)
  headerLine:SetPoint("BOTTOMRIGHT", -6, -1)
  headerLine:SetHeight(1)
  headerLine:SetColorTexture(W.GOLD[1], W.GOLD[2], W.GOLD[3], 0.3)
  local x = 8
  view.Headers = {}
  for _, column in ipairs(COLUMNS) do
    local button = CreateFrame("Button", nil, header)
    button:SetHeight(20)
    button:SetPoint("LEFT", x, 0)
    if column.width > 0 then button:SetWidth(column.width) else button:SetPoint("RIGHT", header, "RIGHT", -26, 0) end
    button.Text = W.Text(button, "GameFontNormalSmall", L["COL_" .. column.key:upper()])
    button.Text:SetPoint("LEFT", 0, 0)
    button:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    if not UNSORTED[column.key] then
      button:SetScript("OnClick", function()
        if view.sort == column.key then view.desc = not view.desc else view.sort, view.desc = column.key, column.desc or false end
        view:Refresh()
      end)
    end
    column.x = x
    x = x + column.width + 6
    view.Headers[column.key] = button
  end

  -- The shown columns from the left, the last one up to the right edge. Hidden: those switched off in
  -- the options, and the officer note for those who may not read it.
  local function PlaceCells(row)
    for _, column in ipairs(COLUMNS) do
      local cell = row.Cells[column.key]
      cell:ClearAllPoints()
      if not column.hidden then
        cell:SetPoint("LEFT", column.x - 4, 0)
        if column.last then
          cell:SetPoint("RIGHT", row, "RIGHT", -4, 0)
        else
          cell:SetWidth(column.width > 0 and column.width or REST_WIDTH)
        end
      end
    end
  end
  function view:LayoutColumns()
    local at, last, signature = 8, nil, ""
    self.hidden = {}
    for _, column in ipairs(COLUMNS) do
      column.hidden = (column.key == "officerNote" and not self.viewOfficer) or ColumnOff(column.key)
      column.last = false
      self.hidden[column.key] = column.hidden
      if not column.hidden then
        column.x = at
        at = at + (column.width > 0 and column.width or REST_WIDTH) + 6
        last = column
        signature = signature .. column.key .. ","
      end
    end
    if last then last.last = true end
    if signature == self.columnSignature then return end
    self.columnSignature = signature
    for _, column in ipairs(COLUMNS) do
      local button = self.Headers[column.key]
      button:SetShown(not column.hidden)
      button:ClearAllPoints()
      if not column.hidden then
        button:SetPoint("LEFT", column.x, 0)
        if column.last then
          button:SetPoint("RIGHT", header, "RIGHT", -26, 0)
        else
          button:SetWidth(column.width > 0 and column.width or REST_WIDTH)
        end
      end
    end
    for _, row in pairs(self.List.rows) do PlaceCells(row) end
  end

  view.List = W.ScrollList(listBox, ROW, function(row)
    row:EnableMouse(true)
    row.Cells = {}
    for _, column in ipairs(COLUMNS) do
      local cell = W.Text(row, "GameFontHighlightSmall")
      cell:SetWordWrap(false)
      row.Cells[column.key] = cell
    end
    PlaceCells(row)
    local highlight = row:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints()
    highlight:SetColorTexture(1, 0.82, 0, 0.1)
    row.Highlight = highlight
    -- section header ("Online · 5"): label on the left, a hairline to the right edge
    row.Section = W.Text(row, "GameFontNormalSmall")
    row.Section:SetPoint("LEFT", 4, 0)
    row.SectionLine = row:CreateTexture(nil, "ARTWORK")
    row.SectionLine:SetHeight(1)
    row.SectionLine:SetPoint("LEFT", row.Section, "RIGHT", 8, 0)
    row.SectionLine:SetPoint("RIGHT", row, "RIGHT", -4, 0)
    row.SectionLine:SetColorTexture(1, 1, 1, 0.12)
    row:SetScript("OnMouseUp", function(self, button)
      if not self.member then return end
      if button == "RightButton" then
        UI.MemberMenu(self.member, self)
      else
        UI.MemberClick(self.member)
      end
    end)
    row:SetScript("OnEnter", function(self) if self.member then UI.MemberTooltip(self, self.member) end end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
  end, function(row, item)
    local m = item.m
    row.member = m
    local c = row.Cells
    local isHeader = item.header ~= nil
    row.Section:SetShown(isHeader)
    row.SectionLine:SetShown(isHeader)
    row.Highlight:SetAlpha(isHeader and 0 or 1)
    for key, cell in pairs(c) do cell:SetShown(not isHeader and not view.hidden[key]) end
    if isHeader then
      row.Section:SetText(item.header)
      if item.online then row.Section:SetTextColor(unpack(ONLINE_COLOR)) else row.Section:SetTextColor(0.6, 0.6, 0.6) end
      return
    end
    local dim = not m.online
    c.level:SetText(m.level)
    -- twinks under their main are indented; a folded main shows how many hang on it
    local name, nameAlpha = UI.MemberNameText(m.name, m.classFile, m.online, view.style)
    if item.child then name = "      " .. name .. "  |cff8f8268" .. L.TWINK .. "|r" end
    if item.more then name = name .. "  |cff8f8268+" .. item.more .. "|r" end
    c.name:SetText(name)
    c.zone:SetText(m.zone or "")
    c.rank:SetText(m.rank or "")
    c.ilvl:SetText(m.ilvl and (string.format("%.1f", m.ilvl / 10):gsub("%.", L.DECIMAL_MARK)) or "")
    c.lastOnline:SetText(ns.Roster.LastOnlineText(m))
    c.guildy:SetText(UI.GuildyVersionText(m) or "")
    c.note:SetText((m.note and m.note ~= "") and m.note or ("|cffff9a5a" .. L.NO_NOTE_CELL .. "|r"))
    c.officerNote:SetText(not view.viewOfficer and ""
      or (m.officerNote and m.officerNote ~= "") and m.officerNote or ("|cffff9a5a" .. L.NO_NOTE_CELL .. "|r"))
    for key, cell in pairs(c) do
      if key ~= "name" and key ~= "note" and key ~= "officerNote" then
        if dim then cell:SetTextColor(0.6, 0.6, 0.6) else cell:SetTextColor(1, 1, 1) end
      end
    end
    for _, cell in ipairs({ c.note, c.officerNote }) do
      if dim then cell:SetTextColor(0.6, 0.6, 0.6) else cell:SetTextColor(1, 1, 1) end
    end
    if m.online then c.lastOnline:SetTextColor(unpack(ONLINE_COLOR)) end
    c.name:SetAlpha(nameAlpha)
  end)
  view.List:SetPoint("TOPLEFT", 4, -28)
  view.List:SetPoint("BOTTOMRIGHT", -26, 4)

  -- how many of the members the filters leave: in the toolbar, left of the reset button
  view.Summary = page:Right(W.Text(bar, "GameFontDisableSmall"), 10)
  view.Summary:SetJustifyH("RIGHT")

  -- behaviour ----------------------------------------------------------------------------------
  function view:SetFilterValue(key, value)
    self.filter[key] = value
    if key == "bracket" then self.filter.level = nil end -- the level menu replaces a single level from the overview
    self:Refresh()
  end

  function view:SetFilter(filter)
    self.filter = filter or {}
    self.OnlineCheck:SetChecked(self.filter.onlineOnly and true or false)
    self:Refresh()
  end

  -- a set filter shows only its value (the full text is in the tooltip), so the toolbar fits
  local function Label(button, base, value)
    button:SetText(value or base)
    button.tip = value and (base .. ": " .. value) or nil
  end

  function view:Refresh()
    -- officer note column and filter only for those who may read officer notes
    self.viewOfficer = ns.Roster.Can().viewOfficer and true or false
    self:LayoutColumns()
    -- twinks under their main, or every character on its own (settings.memberTwinks, the options)
    self.flat = ns.Settings().memberTwinks == false
    self.FoldCheck:SetShown(not self.flat)
    self.FoldCheck.Label:SetShown(not self.flat)
    self.NoOfficerNoteCheck:SetShown(self.viewOfficer)
    self.NoOfficerNoteCheck.Label:SetShown(self.viewOfficer)
    if not self.viewOfficer then self.noOfficerNote = nil; self.NoOfficerNoteCheck:SetChecked(false) end
    self.FoldCheck:ClearAllPoints()
    self.FoldCheck:SetPoint("LEFT", self.viewOfficer and self.NoOfficerNoteCheck.Label or self.NoNoteCheck.Label, "RIGHT", 6, 0)
    local members = ns.Roster.Members()
    local guild, db = ns.GuildData(), ns.DB()
    local mains = ns.Family.Mains(members, guild and guild.families, db and db.ownChars)
    local rankNames, noNote, noOfficerNote = {}, 0, 0
    for _, m in ipairs(members) do
      m.guildy = m.online and ns.Sync.UserVersion(m.name) or nil
      m.ilvl = ItemLevel(guild, m)
      m.mainKey = mains[m.key]
      if type(m.rankIndex) == "number" and not rankNames[m.rankIndex] then rankNames[m.rankIndex] = m.rank or "" end
      if not m.note or m.note == "" then noNote = noNote + 1 end
      if not m.officerNote or m.officerNote == "" then noOfficerNote = noOfficerNote + 1 end
    end
    self.ranks = {}
    for index, name in pairs(rankNames) do self.ranks[#self.ranks + 1] = { index = index, name = name } end
    table.sort(self.ranks, function(a, b) return a.index < b.index end)
    -- a rank nobody holds any more is no filter
    if self.filter.rankIndex and not rankNames[self.filter.rankIndex] then self.filter.rankIndex = nil end

    local list = ns.Search.Members(members, self.filter, self.query, ns.TradeSkill.ProfsOf)
    local kept = {}
    for _, m in ipairs(list) do
      if (not self.noNote or not m.note or m.note == "")
        and (not self.noOfficerNote or not m.officerNote or m.officerNote == "") then
        kept[#kept + 1] = m
      end
    end
    ns.Search.SortMembers(kept, self.sort, self.desc)

    -- twinks right under their main (when the main is shown), or folded into it; flat while
    -- looking for members without a note
    -- Two sections, online above offline, each under its own header and sorted on its own. A twink
    -- only hangs under its main while both are in the same section; otherwise it stands alone.
    local items = {}
    local function Section(part, label)
      if #part == 0 then return end
      if label then items[#items + 1] = { header = label:format(#part), online = part[1].online } end
      if self.noNote or self.noOfficerNote or self.flat then
        for _, m in ipairs(part) do items[#items + 1] = { m = m } end
        return
      end
      local shown, twinksOf = {}, {}
      for _, m in ipairs(part) do shown[m.key] = true end
      for _, m in ipairs(part) do
        if m.mainKey and m.mainKey ~= m.key and shown[m.mainKey] then
          twinksOf[m.mainKey] = twinksOf[m.mainKey] or {}
          table.insert(twinksOf[m.mainKey], m)
        end
      end
      for _, m in ipairs(part) do
        local isTwinkUnderMain = m.mainKey and m.mainKey ~= m.key and shown[m.mainKey]
        if not isTwinkUnderMain then
          local twinks = twinksOf[m.key]
          items[#items + 1] = { m = m, more = self.fold and twinks and #twinks or nil }
          if twinks and not self.fold then
            for _, twink in ipairs(twinks) do items[#items + 1] = { m = twink, child = true } end
          end
        end
      end
    end
    local online, offline = {}, {}
    for _, m in ipairs(kept) do
      if m.online then online[#online + 1] = m else offline[#offline + 1] = m end
    end
    self.style = UI.MemberStyle()
    if self.style == "sections" then
      Section(online, L.SECTION_ONLINE)
      Section(offline, L.OFFLINE_N)
    else
      Section(kept) -- one list in the chosen sort order
    end
    self.List:SetItems(items)
    -- level and profession have no menu here; a drill-down from the overview names them in the summary
    local summary = L.SHOWN_COUNT:format(#kept, #members)
    local level = (self.filter.level and tostring(self.filter.level))
      or (self.filter.bracket and ns.Census.BracketLabel(self.filter.bracket))
    if level then summary = L.FILTER_LEVEL .. " " .. level .. ns.L.SEP .. summary end
    if self.filter.skillLine then summary = ns.TradeSkill.Name(self.filter.skillLine) .. ns.L.SEP .. summary end
    self.Summary:SetText(summary)
    -- at a narrow window a long language fills the row with the filters: then only the numbers
    local last = (self.FoldCheck.Label:IsShown() and self.FoldCheck.Label)
      or (self.viewOfficer and self.NoOfficerNoteCheck.Label) or self.NoNoteCheck.Label
    local right, filters = self.Summary:GetRight(), last:GetRight()
    if right and filters and right - (self.Summary:GetStringWidth() or 0) < filters + 8 then
      self.Summary:SetText(#kept .. " / " .. #members)
    end
    self.NoNoteCheck.Label:SetText(L.NO_NOTE .. " |cffffd100" .. noNote .. "|r")
    self.NoOfficerNoteCheck.Label:SetText(L.NO_OFFICER_NOTE .. " |cffffd100" .. noOfficerNote .. "|r")
    Label(self.RankButton, L.FILTER_RANK, self.filter.rankIndex and rankNames[self.filter.rankIndex])
    Label(self.ClassButton, L.FILTER_CLASS, self.filter.classFile and ClassLabel(self.filter.classFile))
    for key, button in pairs(self.Headers) do
      local text = L["COL_" .. key:upper()]
      if key == self.sort then text = text .. (self.desc and " v" or " ^") end
      button.Text:SetText(text)
    end
  end

  return view
end

-- "today", "3 d ago" for a timestamp
function UI.Age(ts)
  if type(ts) ~= "number" then return "?" end
  local days = math.floor((ns.Now() - ts) / 86400)
  if days <= 0 then return ns.L.TODAY end
  return ns.L.DAYS_AGO:format(days)
end

UI.RegisterTab("members", 2, "TAB_MEMBERS", Build)
