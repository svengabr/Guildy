-- Overview tab (census): activity window switch, summary box, class bars, level histogram and
-- profession bars. Clicking a bar opens the members tab filtered to it.
local _, ns = ...
local W = ns.Widgets
local UI = ns.UI

local CLASSES = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }

local function ClassLabel(classFile)
  local male = rawget(_G, "LOCALIZED_CLASS_NAMES_MALE")
  return male and male[classFile] or classFile
end

local function Build(panel)
  local L = ns.L
  local view = {}

  local top = CreateFrame("Frame", nil, panel)
  top:SetPoint("TOPLEFT", 0, 0)
  top:SetPoint("TOPRIGHT", 0, 0)
  top:SetHeight(26)
  local label = W.Text(top, "GameFontNormal", L.ACTIVE_IN)
  label:SetPoint("LEFT", 4, 0)
  view.Window = W.Segmented(top, {
    { value = 30, text = L.WINDOW_1M }, { value = 90, text = L.WINDOW_3M },
    { value = 180, text = L.WINDOW_6M }, { value = false, text = L.WINDOW_ALL },
  }, function(value)
    ns.Settings().activityDays = value
    view:Refresh()
  end)
  view.Window:SetPoint("LEFT", label, "RIGHT", 10, 0)

  -- summary box
  local summary = W.Box(panel)
  summary:SetPoint("TOPLEFT", 0, -32)
  summary:SetSize(170, 200)
  view.Big = W.Text(summary, "GameFontNormalHuge")
  view.Big:SetPoint("TOPLEFT", 12, -12)
  view.BigSub = W.Text(summary, "GameFontDisableSmall")
  view.BigSub:SetPoint("TOPLEFT", view.Big, "BOTTOMLEFT", 0, -2)
  view.Stats = W.Text(summary, "GameFontHighlightSmall")
  view.Stats:SetPoint("TOPLEFT", view.BigSub, "BOTTOMLEFT", 0, -12)
  view.Stats:SetPoint("RIGHT", -10, 0)
  view.Stats:SetSpacing(5)

  -- classes
  local classes = W.Box(panel)
  classes:SetPoint("TOPLEFT", summary, "TOPRIGHT", 8, 0)
  classes:SetPoint("BOTTOM", summary, "BOTTOM", 0, 0)
  classes:SetPoint("RIGHT", panel, "CENTER", 60, 0)
  local classTitle = W.Text(classes, "GameFontNormal", L.CLASSES)
  classTitle:SetPoint("TOPLEFT", 10, -8)
  view.ClassRows = {}
  for i, classFile in ipairs(CLASSES) do
    local row = W.BarRow(classes, 90)
    row:SetPoint("TOPLEFT", 10, -26 - (i - 1) * 18)
    row:SetPoint("RIGHT", -10, 0)
    row:SetScript("OnClick", function() UI.FilterMembers({ classFile = classFile, activeDays = ns.Settings().activityDays or nil }) end)
    view.ClassRows[classFile] = row
  end

  -- level histogram
  local levels = W.Box(panel)
  levels:SetPoint("TOPLEFT", classes, "TOPRIGHT", 8, 0)
  levels:SetPoint("BOTTOMRIGHT", summary, "BOTTOMRIGHT", 0, 0)
  levels:SetPoint("RIGHT", panel, "RIGHT", 0, 0)
  local levelTitle = W.Text(levels, "GameFontNormal", L.LEVELS)
  levelTitle:SetPoint("TOPLEFT", 10, -8)
  view.Columns = {}
  for bracket = 1, ns.Census.BRACKETS do
    local column = CreateFrame("Button", nil, levels)
    column.Bar = column:CreateTexture(nil, "ARTWORK")
    column.Bar:SetPoint("BOTTOM", 0, 16)
    column.Bar:SetColorTexture(1, 0.82, 0, 0.85)
    column.Count = W.Text(column, "GameFontHighlightSmall")
    column.Count:SetPoint("BOTTOM", column.Bar, "TOP", 0, 2)
    column.Label = W.Text(column, "GameFontDisableSmall", ns.Census.BracketLabel(bracket))
    column.Label:SetPoint("BOTTOM", 0, 0)
    column:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    column:SetScript("OnClick", function() UI.FilterMembers({ bracket = bracket, activeDays = ns.Settings().activityDays or nil }) end)
    view.Columns[bracket] = column
  end
  function view:LayoutColumns()
    local width = math.max(60, (levels:GetWidth() or 300) - 20)
    local height = math.max(40, (levels:GetHeight() or 200) - 34)
    local step = width / ns.Census.BRACKETS
    for bracket, column in ipairs(self.Columns) do
      column:ClearAllPoints()
      column:SetPoint("BOTTOMLEFT", levels, "BOTTOMLEFT", 10 + (bracket - 1) * step, 8)
      column:SetSize(step - 4, height)
      column.Bar:SetWidth(step - 12)
    end
  end

  -- professions
  local profs = W.Box(panel)
  profs:SetPoint("TOPLEFT", summary, "BOTTOMLEFT", 0, -8)
  profs:SetPoint("BOTTOMRIGHT", 0, 0)
  local profTitle = W.Text(profs, "GameFontNormal", L.PROFESSIONS)
  profTitle:SetPoint("TOPLEFT", 10, -8)
  local profHint = W.Text(profs, "GameFontDisableSmall", L.CLICK_TO_FILTER)
  profHint:SetPoint("LEFT", profTitle, "RIGHT", 8, 0)
  view.ProfRows = {}
  for i, skillLine in ipairs(ns.Professions.ORDER) do
    local row = W.BarRow(profs, 100)
    row.skillLine = skillLine
    row:SetScript("OnClick", function() UI.FilterMembers({ skillLine = skillLine, activeDays = ns.Settings().activityDays or nil }) end)
    view.ProfRows[i] = row
  end
  function view:LayoutProfs()
    local width = math.max(300, (profs:GetWidth() or 600) - 20)
    local colWidth = width / 3
    for i, row in ipairs(self.ProfRows) do
      local col, line = (i - 1) % 3, math.floor((i - 1) / 3)
      row:ClearAllPoints()
      row:SetPoint("TOPLEFT", profs, "TOPLEFT", 10 + col * colWidth, -28 - line * 20)
      row:SetWidth(colWidth - 14)
    end
  end

  function view:Refresh()
    local settings = ns.Settings()
    local windowDays = settings.activityDays
    self.Window:SetValue(windowDays)
    local r = ns.Census.Compute(ns.Roster.Members(), windowDays, ns.TradeSkill.ProfsOf)
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
    for _, classFile in ipairs(CLASSES) do
      local cr, cg, cb = W.ClassColor(classFile)
      self.ClassRows[classFile]:SetData(ClassLabel(classFile), r.classes[classFile] or 0, maxClass, cr, cg, cb)
    end

    self:LayoutColumns()
    local maxBracket = 1
    for _, count in ipairs(r.brackets) do maxBracket = math.max(maxBracket, count) end
    for bracket, column in ipairs(self.Columns) do
      local count = r.brackets[bracket] or 0
      local height = math.max(1, (column:GetHeight() - 34) * count / maxBracket)
      column.Bar:SetHeight(height)
      column.Count:SetText(count)
    end

    self:LayoutProfs()
    local maxProf = 1
    for _, count in pairs(r.professions) do maxProf = math.max(maxProf, count) end
    for _, row in ipairs(self.ProfRows) do
      local name = "|T" .. ns.Professions.ICONS[row.skillLine] .. ":14|t " .. ns.TradeSkill.Name(row.skillLine)
      row:SetData(name, r.professions[row.skillLine] or 0, maxProf, 0.85, 0.7, 0.35)
    end
  end

  function view:OnResize() self:Refresh() end

  return view
end

UI.RegisterTab("overview", 3, ns.L.TAB_OVERVIEW, Build)
