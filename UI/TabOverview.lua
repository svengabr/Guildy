-- Overview tab (census): activity window switch, summary box, class bars, levels 1-60 stacked by class, profession
-- bars with the highest known skill, and below: last-online activity, joins and departures of the last
-- 30 days, and a class x level matrix. Everything grows with the window. Clicks open the members tab
-- filtered to the bar, bucket or cell.
local _, ns = ...
local W = ns.Widgets
local UI = ns.UI

local CLASSES = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }
local CHANGE_DAYS = 30

local function ClassLabel(classFile)
  local male = rawget(_G, "LOCALIZED_CLASS_NAMES_MALE")
  return male and male[classFile] or classFile
end

-- { {kind, player1, player2, daysAgo} } from the guild event log
local function GuildEvents()
  local list = {}
  local count = ns.Try(rawget(_G, "GetNumGuildEvents")) or 0
  local getInfo = rawget(_G, "GetGuildEventInfo")
  for i = 1, count do
    local kind, player1, player2, _, years, months, days, hours = ns.Try(getInfo, i)
    if kind then
      list[#list + 1] = { kind = kind, player1 = ns.Anon.Name(ns.Names.Normalize(player1 or "?")),
        player2 = ns.Anon.Name(ns.Names.Normalize(player2 or "?")), daysAgo = ns.Census.DaysOffline(years, months, days, hours) }
    end
  end
  return list
end

-- { [skillLine] = rank } of a member (known ranks only)
local function RanksOf(m)
  local record = ns.TradeSkill.Record(m)
  local ranks = {}
  for skillLine, prof in pairs(record and record.profs or {}) do
    if type(prof.rank) == "number" then ranks[skillLine] = prof.rank end
  end
  return ranks
end

local function Build(panel)
  local L = ns.L
  local view = {}

  local page = W.Page(panel)
  panel = page.Body -- the boxes live in the body; the toolbar holds the time window
  page:Left(W.Text(page.Bar, "GameFontNormalSmall", L.ACTIVE_IN), 2)
  view.Window = W.Segmented(page.Bar, {
    { value = 30, text = L.WINDOW_1M }, { value = 90, text = L.WINDOW_3M },
    { value = 180, text = L.WINDOW_6M }, { value = false, text = L.WINDOW_ALL },
  }, function(value)
    ns.Settings().activityDays = value
    view:Refresh()
  end)
  page:Left(view.Window, 8)

  -- row 1: summary, classes, levels ---------------------------------------------------------------
  local summary = W.Box(panel)
  summary:SetPoint("TOPLEFT", 0, 0)
  summary:SetWidth(170)
  view.Summary = summary
  view.Big = W.Text(summary, "GameFontNormalHuge")
  view.Big:SetPoint("TOPLEFT", 12, -12)
  view.BigSub = W.Text(summary, "GameFontDisableSmall")
  view.BigSub:SetPoint("TOPLEFT", view.Big, "BOTTOMLEFT", 0, -2)
  view.Stats = W.Text(summary, "GameFontHighlightSmall")
  view.Stats:SetPoint("TOPLEFT", view.BigSub, "BOTTOMLEFT", 0, -12)
  view.Stats:SetPoint("RIGHT", -10, 0)
  view.Stats:SetSpacing(5)

  local classes = W.Box(panel)
  classes:SetPoint("TOPLEFT", summary, "TOPRIGHT", 8, 0)
  classes:SetPoint("BOTTOM", summary, "BOTTOM", 0, 0)
  local classTitle = W.Text(classes, "GameFontNormal", L.CLASSES)
  classTitle:SetPoint("TOPLEFT", 10, -8)
  view.ClassRows = {}
  for _, classFile in ipairs(CLASSES) do
    local row = W.BarRow(classes, 90)
    row:SetScript("OnClick", function() UI.FilterMembers({ classFile = classFile, activeDays = ns.Settings().activityDays or nil }) end)
    view.ClassRows[#view.ClassRows + 1] = row
    row.classFile = classFile
  end

  local levels = W.Box(panel)
  levels:SetPoint("TOPLEFT", classes, "TOPRIGHT", 8, 0)
  levels:SetPoint("BOTTOMRIGHT", summary, "BOTTOMRIGHT", 0, 0)
  levels:SetPoint("RIGHT", panel, "RIGHT", 0, 0)
  local levelTitle = W.Text(levels, "GameFontNormal", L.LEVELS)
  levelTitle:SetPoint("TOPLEFT", 10, -8)
  -- one column per level, stacked by class in class colours
  view.Columns = {}
  view.Axis = {}
  for level = 1, ns.Census.MAX_LEVEL do
    local column = CreateFrame("Button", nil, levels)
    column.level = level
    column.Segments = {}
    for i, classFile in ipairs(CLASSES) do
      local segment = column:CreateTexture(nil, "ARTWORK")
      local cr, cg, cb = W.ClassColor(classFile)
      segment:SetColorTexture(cr, cg, cb, 0.9)
      segment:Hide()
      column.Segments[i] = segment
    end
    column.Glow = column:CreateTexture(nil, "HIGHLIGHT")
    column.Glow:SetAllPoints()
    column.Glow:SetColorTexture(1, 1, 1, 0.12)
    column:SetScript("OnClick", function(self)
      UI.FilterMembers({ level = self.level, activeDays = ns.Settings().activityDays or nil })
    end)
    column:SetScript("OnEnter", function(self)
      GameTooltip:SetOwner(self, "ANCHOR_TOP")
      GameTooltip:SetText(L.LEVEL_TIP:format(self.level, self.total or 0))
      for _, classFile in ipairs(CLASSES) do
        local count = self.counts and self.counts[classFile]
        if count and count > 0 then
          local cr, cg, cb = W.ClassColor(classFile)
          GameTooltip:AddDoubleLine(ClassLabel(classFile), count, cr, cg, cb, 1, 1, 1)
        end
      end
      GameTooltip:AddLine(L.LEVEL_CLICK, 0.6, 0.6, 0.6)
      GameTooltip:Show()
    end)
    column:SetScript("OnLeave", function() GameTooltip:Hide() end)
    view.Columns[level] = column
  end
  for i, level in ipairs({ 1, 10, 20, 30, 40, 50, 60 }) do
    local tick = W.Text(levels, "GameFontDisableSmall", tostring(level))
    tick:SetJustifyH("CENTER")
    tick.level = level
    view.Axis[i] = tick
  end
  view.LevelMax = W.Text(levels, "GameFontDisableSmall")
  view.LevelMax:SetPoint("TOPRIGHT", -10, -10)

  -- row 2: professions (count and highest known skill) ---------------------------------------------
  local profs = W.Box(panel)
  profs:SetPoint("TOPLEFT", summary, "BOTTOMLEFT", 0, -8)
  profs:SetPoint("RIGHT", 0, 0)
  profs:SetHeight(4 * 20 + 36)
  local profTitle = W.Text(profs, "GameFontNormal", L.PROFESSIONS)
  profTitle:SetPoint("TOPLEFT", 10, -8)
  local profHint = W.Text(profs, "GameFontDisableSmall", L.PROF_OVERVIEW_HINT)
  profHint:SetPoint("LEFT", profTitle, "RIGHT", 8, 0)
  view.ProfRows = {}
  for i, skillLine in ipairs(ns.Professions.ORDER) do
    local row = W.BarRow(profs, 100)
    row.Count:SetWidth(64)
    row.skillLine = skillLine
    row:SetScript("OnClick", function() UI.FilterMembers({ skillLine = skillLine, activeDays = ns.Settings().activityDays or nil }) end)
    view.ProfRows[i] = row
  end

  -- row 3: activity, joins and departures, class x level -------------------------------------------
  local activity = W.Box(panel)
  activity:SetPoint("TOPLEFT", profs, "BOTTOMLEFT", 0, -8)
  activity:SetPoint("BOTTOM", 0, 0)
  local activityTitle = W.Text(activity, "GameFontNormal", L.ACTIVITY)
  activityTitle:SetPoint("TOPLEFT", 10, -8)
  local activityHint = W.Text(activity, "GameFontDisableSmall", L.ACTIVITY_HINT)
  activityHint:SetPoint("LEFT", activityTitle, "RIGHT", 8, 0)
  view.ActivityRows = {}
  for bucket = 1, #ns.Census.ACTIVITY do
    local row = W.BarRow(activity, 110)
    row:SetScript("OnClick", function() UI.FilterMembers({ activity = bucket }) end)
    view.ActivityRows[bucket] = row
  end

  local changes = W.Box(panel)
  changes:SetPoint("TOPLEFT", activity, "TOPRIGHT", 8, 0)
  changes:SetPoint("BOTTOM", 0, 0)
  local changesTitle = W.Text(changes, "GameFontNormal", L.CHANGES:format(CHANGE_DAYS))
  changesTitle:SetPoint("TOPLEFT", 10, -8)
  view.ChangesSummary = W.Text(changes, "GameFontDisableSmall")
  view.ChangesSummary:SetPoint("LEFT", changesTitle, "RIGHT", 8, 0)
  view.Changes = W.ScrollList(changes, 18, function(row)
    row.Text = W.Text(row, "GameFontHighlightSmall")
    row.Text:SetPoint("LEFT", 4, 0)
    row.Text:SetPoint("RIGHT", -70, 0)
    row.Text:SetWordWrap(false)
    row.When = W.Text(row, "GameFontDisableSmall")
    row.When:SetPoint("RIGHT", -4, 0)
    row.When:SetJustifyH("RIGHT")
  end, function(row, change)
    local m = ns.Roster.Find(change.name)
    local name = m and W.ClassName(m.name, m.classFile) or change.name
    if change.kind == "join" then
      row.Text:SetText("|cff40e040+|r " .. L.CHANGE_JOIN:format(name))
    elseif change.kind == "quit" then
      row.Text:SetText("|cffff5a4a-|r " .. L.CHANGE_QUIT:format(name))
    else
      row.Text:SetText("|cffff5a4ax|r " .. L.CHANGE_REMOVE:format(name, change.by or "?"))
    end
    row.When:SetText(ns.Roster.LastOnlineText({ online = false, daysOffline = change.daysAgo }))
  end)
  view.Changes:SetPoint("TOPLEFT", 8, -28)
  view.Changes:SetPoint("BOTTOMRIGHT", -28, 8)
  view.ChangesEmpty = W.Text(changes, "GameFontDisable", L.CHANGES_EMPTY)
  view.ChangesEmpty:SetPoint("TOPLEFT", 12, -32)

  local matrix = W.Box(panel)
  matrix:SetPoint("TOPLEFT", changes, "TOPRIGHT", 8, 0)
  matrix:SetPoint("BOTTOMRIGHT", 0, 0)
  local matrixTitle = W.Text(matrix, "GameFontNormal", L.CLASS_LEVEL)
  matrixTitle:SetPoint("TOPLEFT", 10, -8)
  view.MatrixHeads = {}
  for bracket = 1, ns.Census.BRACKETS do
    local head = W.Text(matrix, "GameFontDisableSmall", ns.Census.BracketLabel(bracket))
    head:SetJustifyH("CENTER")
    view.MatrixHeads[bracket] = head
  end
  view.MatrixNames, view.Cells = {}, {}
  for i, classFile in ipairs(CLASSES) do
    local name = W.Text(matrix, "GameFontHighlightSmall", ClassLabel(classFile))
    name:SetTextColor(W.ClassColor(classFile))
    name:SetWordWrap(false)
    view.MatrixNames[i] = name
    view.Cells[i] = {}
    for bracket = 1, ns.Census.BRACKETS do
      local cell = CreateFrame("Button", nil, matrix)
      cell.Bg = cell:CreateTexture(nil, "BACKGROUND")
      cell.Bg:SetAllPoints()
      cell.Text = W.Text(cell, "GameFontHighlightSmall")
      cell.Text:SetPoint("CENTER")
      cell:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
      cell:SetScript("OnClick", function()
        UI.FilterMembers({ classFile = classFile, bracket = bracket, activeDays = ns.Settings().activityDays or nil })
      end)
      view.Cells[i][bracket] = cell
    end
  end

  -- layout ----------------------------------------------------------------------------------------
  function view:Layout()
    local width, height = panel:GetWidth() or 0, panel:GetHeight() or 0
    if width < 100 or height < 100 then return end
    -- row 1 takes 45 % of what remains after the profession row, at least 180 (window minimum: UI.MIN_H)
    local rest = height - 8 - profs:GetHeight() - 8
    local topHeight = math.max(180, math.floor(rest * 0.45))
    summary:SetHeight(topHeight)
    -- row 1 shares the thirds of row 3: summary and classes over its first two boxes, levels over the third
    classes:SetWidth(2 * (width - 16) / 3 + 8 - summary:GetWidth() - 8)
    local step = math.min(26, math.max(16, (topHeight - 34) / #self.ClassRows))
    for i, row in ipairs(self.ClassRows) do
      row:ClearAllPoints()
      row:SetPoint("TOPLEFT", classes, "TOPLEFT", 10, -26 - (i - 1) * step)
      row:SetPoint("RIGHT", classes, "RIGHT", -10, 0)
    end
    -- level columns: 60 slim columns over the box, level ticks below
    local levelWidth = math.max(60, (levels:GetWidth() or 300) - 20)
    self.columnHeight = math.max(40, topHeight - 30 - 22)
    local columnStep = levelWidth / ns.Census.MAX_LEVEL
    for level, column in ipairs(self.Columns) do
      column:ClearAllPoints()
      column:SetPoint("BOTTOMLEFT", levels, "BOTTOMLEFT", 10 + (level - 1) * columnStep, 22)
      column:SetSize(math.max(1, columnStep - 1), self.columnHeight)
    end
    for _, tick in ipairs(self.Axis) do
      tick:ClearAllPoints()
      tick:SetPoint("BOTTOM", levels, "BOTTOMLEFT", 10 + (tick.level - 0.5) * columnStep, 6)
    end
    -- professions: three columns
    local colWidth = math.max(300, width - 20) / 3
    for i, row in ipairs(self.ProfRows) do
      local col, line = (i - 1) % 3, math.floor((i - 1) / 3)
      row:ClearAllPoints()
      row:SetPoint("TOPLEFT", profs, "TOPLEFT", 10 + col * colWidth, -28 - line * 20)
      row:SetWidth(colWidth - 14)
    end
    -- row 3: three boxes of equal width
    local boxWidth = (width - 16) / 3
    activity:SetWidth(boxWidth)
    changes:SetWidth(boxWidth)
    local bottomHeight = height - topHeight - 8 - profs:GetHeight() - 8
    local activityStep = math.min(28, math.max(16, (bottomHeight - 34) / #self.ActivityRows))
    for i, row in ipairs(self.ActivityRows) do
      row:ClearAllPoints()
      row:SetPoint("TOPLEFT", activity, "TOPLEFT", 10, -28 - (i - 1) * activityStep)
      row:SetPoint("RIGHT", activity, "RIGHT", -10, 0)
    end
    -- matrix: class names + 6 cells per row
    local nameWidth = 82
    local cellWidth = math.max(18, (boxWidth - 20 - nameWidth) / ns.Census.BRACKETS)
    local cellHeight = math.min(22, math.max(12, (bottomHeight - 52) / #CLASSES))
    for bracket, head in ipairs(self.MatrixHeads) do
      head:ClearAllPoints()
      head:SetPoint("TOPLEFT", matrix, "TOPLEFT", 10 + nameWidth + (bracket - 1) * cellWidth, -28)
      head:SetWidth(cellWidth)
    end
    for i, name in ipairs(self.MatrixNames) do
      local y = -44 - (i - 1) * cellHeight
      name:ClearAllPoints()
      name:SetPoint("TOPLEFT", matrix, "TOPLEFT", 10, y - (cellHeight - 12) / 2)
      name:SetWidth(nameWidth - 4)
      for bracket, cell in ipairs(self.Cells[i]) do
        cell:ClearAllPoints()
        cell:SetPoint("TOPLEFT", matrix, "TOPLEFT", 10 + nameWidth + (bracket - 1) * cellWidth + 1, y)
        cell:SetSize(cellWidth - 2, cellHeight - 2)
      end
    end
  end

  function view:Refresh()
    self:Layout()
    local settings = ns.Settings()
    local windowDays = settings.activityDays
    self.Window:SetValue(windowDays)
    local r = ns.Census.Compute(ns.Roster.Members(), windowDays, ns.TradeSkill.ProfsOf, RanksOf)
    self.Big:SetText(r.active)
    self.BigSub:SetText(windowDays and L.ACTIVE_OF:format(r.total) or L.MEMBERS_TOTAL)
    self.Stats:SetText(table.concat({
      L.STAT_ONLINE:format(r.online),
      L.STAT_AVG_LEVEL:format(r.avgLevel),
      L.STAT_NEW:format(r.newCount),
      L.STAT_PROFS_KNOWN:format(r.withProfessions, r.active),
    }, "\n"))

    local maxClass = 1
    for _, count in pairs(r.classes) do maxClass = math.max(maxClass, count) end
    for _, row in ipairs(self.ClassRows) do
      local cr, cg, cb = W.ClassColor(row.classFile)
      row:SetData(ClassLabel(row.classFile), r.classes[row.classFile] or 0, maxClass, cr, cg, cb)
    end

    local maxLevel = 1
    for _, total in pairs(r.levelTotals) do maxLevel = math.max(maxLevel, total) end
    self.LevelMax:SetText(L.LEVEL_MAX:format(maxLevel))
    for level, column in ipairs(self.Columns) do
      local counts = r.levels[level] or {}
      column.counts, column.total = counts, r.levelTotals[level] or 0
      local y = 0
      for i, classFile in ipairs(CLASSES) do
        local segment = column.Segments[i]
        local count = counts[classFile] or 0
        if count > 0 then
          local h = self.columnHeight * count / maxLevel
          segment:ClearAllPoints()
          segment:SetPoint("BOTTOMLEFT", column, "BOTTOMLEFT", 0, y)
          segment:SetPoint("BOTTOMRIGHT", column, "BOTTOMRIGHT", 0, y)
          segment:SetHeight(h)
          segment:Show()
          y = y + h
        else
          segment:Hide()
        end
      end
    end

    local maxProf = 1
    for _, count in pairs(r.professions) do maxProf = math.max(maxProf, count) end
    for _, row in ipairs(self.ProfRows) do
      local name = "|T" .. ns.Professions.ICONS[row.skillLine] .. ":14|t " .. ns.TradeSkill.Name(row.skillLine)
      local count = r.professions[row.skillLine] or 0
      row:SetData(name, count, maxProf, 0.85, 0.7, 0.35)
      local best = r.maxRank[row.skillLine]
      row.Count:SetText(count .. (best and ("|cff999999 · " .. best .. "|r") or ""))
    end

    local maxActivity = 1
    for _, count in ipairs(r.activity) do maxActivity = math.max(maxActivity, count) end
    for bucket, row in ipairs(self.ActivityRows) do
      local green = 1 - (bucket - 1) / (#self.ActivityRows - 1)
      row:SetData(L["ACTIVITY_" .. bucket], r.activity[bucket] or 0, maxActivity, 1 - green * 0.6, 0.35 + green * 0.5, 0.25)
      row.Label:SetTextColor(1, 1, 1)
    end

    local list = ns.Census.Changes(GuildEvents(), CHANGE_DAYS)
    local joins, gone = 0, 0
    for _, change in ipairs(list) do
      if change.kind == "join" then joins = joins + 1 else gone = gone + 1 end
    end
    self.ChangesSummary:SetText(L.CHANGES_SUMMARY:format(joins, gone))
    self.Changes:SetItems(list)
    self.ChangesEmpty:SetShown(#list == 0)

    local maxCell = 1
    for _, row in pairs(r.matrix) do
      for _, count in pairs(row) do maxCell = math.max(maxCell, count) end
    end
    for i, classFile in ipairs(CLASSES) do
      local cr, cg, cb = W.ClassColor(classFile)
      for bracket, cell in ipairs(self.Cells[i]) do
        local count = r.matrix[classFile] and r.matrix[classFile][bracket] or 0
        if count > 0 then
          cell.Bg:SetColorTexture(cr, cg, cb, 0.15 + 0.6 * count / maxCell)
          cell.Text:SetText(count)
        else
          cell.Bg:SetColorTexture(1, 1, 1, 0.03)
          cell.Text:SetText("")
        end
      end
    end
  end

  function view:OnShow()
    local query = rawget(_G, "QueryGuildEventLog")
    if query then pcall(query) end
  end

  function view:OnResize() self:Refresh() end

  return view
end

UI.RegisterTab("overview", 3, "TAB_OVERVIEW", Build)
