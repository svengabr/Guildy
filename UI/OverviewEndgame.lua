-- The endgame view of the overview tab (UI/TabOverview.lua): six boxes, three by two. Top: the activity
-- of the guild (the pulse and how the players spread over the score, Core/Activity.lua), what the guild
-- did this month against the last, and the item levels of the level 60 members. Bottom: last online and
-- comings and goings (the boxes of the level view), and the raids. Clicks open the members tab filtered
-- to the bar, column or raid.
local _, ns = ...
local W = ns.Widgets
local UI = ns.UI

local GAP = 8
local TOP_SHARE = 0.48
local MAX_COLUMNS = 60
local MONTH_LABELS = { raidBosses = "MONTH_RAID", dungeonBosses = "MONTH_BOSSES", [932] = "MONTH_DUNGEONS",
  [98] = "MONTH_QUESTS", [588] = "MONTH_HONOR", days = "MONTH_DAYS" }
local SCORE_RANGES = { "75-100", "50-74", "25-49", "0-24" }
local GREEN, RED, GREY = "|cff40e040", "|cffff5a4a", "|cff808080"

local function Decimal(value)
  return (string.format("%.1f", value):gsub("%.", ns.L.DECIMAL_MARK))
end

local function Whole(value)
  return UI.Number(math.floor(value + 0.5))
end

-- "+13" green, "-55" red; nil when there is nothing to compare with
local function Change(delta, format)
  if not delta then return nil end
  return (delta >= 0 and GREEN .. "+" or RED .. "-") .. format(math.abs(delta)) .. "|r"
end

function UI.BuildOverviewEndgame(panel)
  local L = ns.L
  local S = ns.Stats
  local CLASSES = UI.OVERVIEW_CLASSES
  local view = {}

  local function Box(title, hint)
    local box = W.Box(panel)
    box.Title = W.Text(box, "GameFontNormal", title)
    box.Title:SetPoint("TOPLEFT", 10, -8)
    if hint then
      box.Hint = W.Text(box, "GameFontDisableSmall", hint)
      box.Hint:SetPoint("LEFT", box.Title, "RIGHT", 8, 0)
      box.Hint:SetPoint("RIGHT", -10, 0)
      box.Hint:SetWordWrap(false)
    end
    return box
  end

  -- activity ------------------------------------------------------------------------------------------
  local score = Box(L.SCORE, L.SCORE_HINT)
  view.Pulse = W.Text(score, "GameFontNormalHuge")
  view.Pulse:SetPoint("TOPLEFT", 12, -32)
  view.PulseLabel = W.Text(score, "GameFontNormal")
  view.PulseLabel:SetPoint("TOPLEFT", view.Pulse, "TOPRIGHT", 10, 2)
  view.PulseOf = W.Text(score, "GameFontDisableSmall")
  view.PulseOf:SetPoint("TOPLEFT", view.PulseLabel, "BOTTOMLEFT", 0, -2)
  view.PulseOf:SetPoint("RIGHT", -10, 0)
  view.PulseOf:SetWordWrap(false)
  view.ScoreRows = {}
  for bucket = 1, 5 do
    local row = W.BarRow(score, 150)
    row:SetScript("OnClick", function() UI.FilterMembers({ scoreBucket = bucket }) end)
    view.ScoreRows[bucket] = row
  end
  view.ScoreClick = W.Text(score, "GameFontDisableSmall", L.SCORE_CLICK)
  view.ScoreClick:SetPoint("BOTTOMLEFT", 12, 8)

  -- this month ----------------------------------------------------------------------------------------
  local month = Box(L.MONTH, L.MONTH_HINT)
  view.MonthRows = {}
  for i = 1, #ns.Activity.MONTH_ROWS do
    local row = CreateFrame("Frame", nil, month)
    row.Label = W.Text(row, "GameFontHighlightSmall")
    row.Label:SetPoint("TOPLEFT", 0, 0)
    row.Value = W.Text(row, "GameFontNormalSmall")
    row.Value:SetPoint("TOPRIGHT", 0, 0)
    row.Value:SetJustifyH("RIGHT")
    row.Label:SetPoint("RIGHT", row.Value, "LEFT", -6, 0)
    row.Label:SetWordWrap(false)
    row.Track = row:CreateTexture(nil, "BACKGROUND")
    row.Track:SetPoint("BOTTOMLEFT", 0, 2)
    row.Track:SetPoint("BOTTOMRIGHT", 0, 2)
    row.Track:SetHeight(8)
    row.Track:SetColorTexture(0.13, 0.11, 0.08, 1)
    row.Fill = row:CreateTexture(nil, "ARTWORK")
    row.Fill:SetPoint("LEFT", row.Track, "LEFT", 0, 0)
    row.Fill:SetHeight(8)
    row.Fill:SetColorTexture(0.80, 0.66, 0.33, 1)
    row.Mark = row:CreateTexture(nil, "OVERLAY")
    row.Mark:SetSize(2, 12)
    row.Mark:SetColorTexture(1, 1, 1, 1)
    view.MonthRows[i] = row
  end

  -- item level ----------------------------------------------------------------------------------------
  local ilvl = Box(L.ILVL, L.ILVL_HINT)
  view.IlvlMax = W.Text(ilvl, "GameFontDisableSmall")
  view.IlvlMax:SetPoint("TOPRIGHT", -10, -10)
  ilvl.Hint:ClearAllPoints()
  ilvl.Hint:SetPoint("LEFT", ilvl.Title, "RIGHT", 8, 0)
  view.Columns, view.Ticks = {}, {}
  local function Column(i)
    local column = view.Columns[i]
    if column then return column end
    column = CreateFrame("Button", nil, ilvl)
    column.Segments = {}
    for c, classFile in ipairs(CLASSES) do
      local segment = column:CreateTexture(nil, "ARTWORK")
      local r, g, b = W.ClassColor(classFile)
      segment:SetColorTexture(r, g, b, 0.9)
      segment:Hide()
      column.Segments[c] = segment
    end
    column.Glow = column:CreateTexture(nil, "HIGHLIGHT")
    column.Glow:SetAllPoints()
    column.Glow:SetColorTexture(1, 1, 1, 0.12)
    column:SetScript("OnClick", function(self)
      UI.FilterMembers({ ilvl = self.level, level = ns.Census.MAX_LEVEL, activeDays = ns.Settings().activityDays or nil })
    end)
    column:SetScript("OnEnter", function(self)
      GameTooltip:SetOwner(self, "ANCHOR_TOP")
      GameTooltip:SetText(L.ILVL_TIP:format(self.level, self.total or 0))
      for _, classFile in ipairs(CLASSES) do
        local count = self.counts and self.counts[classFile]
        if count and count > 0 then
          local r, g, b = W.ClassColor(classFile)
          GameTooltip:AddDoubleLine(UI.OverviewClassLabel(classFile), count, r, g, b, 1, 1, 1)
        end
      end
      GameTooltip:AddLine(L.LEVEL_CLICK, 0.6, 0.6, 0.6)
      GameTooltip:Show()
    end)
    column:SetScript("OnLeave", function() GameTooltip:Hide() end)
    view.Columns[i] = column
    return column
  end
  local function Tick(i)
    local tick = view.Ticks[i]
    if not tick then
      tick = W.Text(ilvl, "GameFontDisableSmall")
      tick:SetJustifyH("CENTER")
      view.Ticks[i] = tick
    end
    return tick
  end
  view.ReadyLine = ilvl:CreateTexture(nil, "OVERLAY")
  view.ReadyLine:SetColorTexture(W.GOLD[1], W.GOLD[2], W.GOLD[3], 0.8)
  view.ReadyLine:SetWidth(1)
  view.ReadyText = W.Text(ilvl, "GameFontNormalSmall", L.ILVL_READY:format(ns.Census.READY_ILVL))
  view.ReadyText:SetTextColor(W.GOLD[1], W.GOLD[2], W.GOLD[3])

  -- last online, comings and goings: the boxes of the level view ----------------------------------------
  local online = UI.OverviewOnlineBox(panel)
  local changes = UI.OverviewChangesBox(panel)

  -- raids ---------------------------------------------------------------------------------------------
  local raids = Box(L.RAIDS, L.RAIDS_HINT)
  view.RaidBlocks = {}
  local function RaidBlock(i)
    local block = view.RaidBlocks[i]
    if block then return block end
    block = CreateFrame("Button", nil, raids)
    block:SetHeight(46)
    block.Icon = W.Icon(block, 24)
    block.Icon.Border:SetPoint("TOPLEFT", 0, -1)
    block.Name = W.Text(block, "GameFontHighlightSmall")
    block.Name:SetPoint("TOPLEFT", 34, 0)
    block.New = W.Text(block, "GameFontDisableSmall")
    block.New:SetPoint("LEFT", block.Name, "RIGHT", 10, 0)
    block.Count = W.Text(block, "GameFontNormalSmall")
    block.Count:SetPoint("TOPRIGHT", 0, -14)
    block.Count:SetJustifyH("RIGHT")
    block.Count:SetWidth(64)
    block.Track = block:CreateTexture(nil, "BACKGROUND")
    block.Track:SetPoint("TOPLEFT", 34, -17)
    block.Track:SetPoint("RIGHT", block.Count, "LEFT", -6, 0)
    block.Track:SetHeight(8)
    block.Track:SetColorTexture(0.13, 0.11, 0.08, 1)
    block.Fill = block:CreateTexture(nil, "ARTWORK")
    block.Fill:SetPoint("LEFT", block.Track, "LEFT", 0, 0)
    block.Fill:SetHeight(8)
    block.Fill:SetColorTexture(0.80, 0.66, 0.33, 1)
    block.Open = W.Text(block, "GameFontDisableSmall")
    block.Open:SetPoint("TOPLEFT", 34, -30)
    block.Open:SetWordWrap(false)
    block:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    block:SetScript("OnClick", function(self) UI.FilterMembers({ raidKill = self.raid.key }) end)
    view.RaidBlocks[i] = block
    return block
  end

  -- layout --------------------------------------------------------------------------------------------
  local function PlaceMonth()
    local width = math.max(60, (month:GetWidth() or 300) - 24)
    for _, row in ipairs(view.MonthRows) do
      row.Fill:SetWidth(math.max(1, width * (row.fraction or 0)))
      row.Mark:SetShown(row.mark ~= nil)
      if row.mark then
        row.Mark:ClearAllPoints()
        row.Mark:SetPoint("CENTER", row.Track, "LEFT", width * row.mark, 0)
      end
    end
  end

  local function PlaceColumns()
    local data = view.ilvls
    local shown = 0
    local left, bottom = 10, 22
    local width = math.max(60, (ilvl:GetWidth() or 300) - 20)
    local height = math.max(30, (ilvl:GetHeight() or 200) - 46 - bottom)
    local ticks = 0
    view.ReadyLine:Hide()
    view.ReadyText:Hide()
    if data and data.min then
      local first = data.min
      local count = math.min(MAX_COLUMNS, data.max - data.min + 1)
      local step = width / count
      for i = 1, count do
        local level = first + i - 1
        local column = Column(i)
        column.level, column.counts, column.total = level, data.counts[level] or {}, data.totals[level] or 0
        column:ClearAllPoints()
        column:SetPoint("BOTTOMLEFT", ilvl, "BOTTOMLEFT", left + (i - 1) * step, bottom)
        column:SetSize(math.max(1, step - 1), height)
        local y = 0
        for c, classFile in ipairs(CLASSES) do
          local segment = column.Segments[c]
          local n = column.counts[classFile] or 0
          if n > 0 then
            local h = height * n / data.top
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
        column:Show()
        if level % 5 == 0 then
          ticks = ticks + 1
          local tick = Tick(ticks)
          tick:SetText(tostring(level))
          tick:ClearAllPoints()
          tick:SetPoint("BOTTOM", ilvl, "BOTTOMLEFT", left + (i - 0.5) * step, 6)
          tick:Show()
        end
        if level == ns.Census.READY_ILVL then
          local x = left + (i - 1) * step - 1
          view.ReadyLine:ClearAllPoints()
          view.ReadyLine:SetPoint("BOTTOMLEFT", ilvl, "BOTTOMLEFT", x, bottom)
          view.ReadyLine:SetHeight(height + 14)
          view.ReadyLine:Show()
          view.ReadyText:ClearAllPoints()
          -- the text stands right of the line, left of it when the line is in the right half
          if x > width / 2 then
            view.ReadyText:SetPoint("BOTTOMRIGHT", ilvl, "BOTTOMLEFT", x - 5, bottom + height + 2)
          else
            view.ReadyText:SetPoint("BOTTOMLEFT", ilvl, "BOTTOMLEFT", x + 5, bottom + height + 2)
          end
          view.ReadyText:Show()
        end
      end
      shown = count
    end
    for i = shown + 1, #view.Columns do view.Columns[i]:Hide() end
    for i = ticks + 1, #view.Ticks do view.Ticks[i]:Hide() end
  end

  local function PlaceRaids()
    local list = view.raids or {}
    local height = raids:GetHeight() or 200
    local pitch = #list > 0 and math.min(74, math.max(48, (height - 36) / #list)) or 48
    for i, entry in ipairs(list) do
      local block = RaidBlock(i)
      block:ClearAllPoints()
      block:SetPoint("TOPLEFT", raids, "TOPLEFT", 10, -30 - (i - 1) * pitch)
      block:SetPoint("RIGHT", raids, "RIGHT", -10, 0)
      local track = math.max(40, (raids:GetWidth() or 300) - 20 - 34 - 70)
      block.Fill:SetWidth(math.max(1, track * (entry.readings > 0 and #entry.killers / entry.readings or 0)))
      -- as many names as fit, the rest as "+n"
      local room = math.max(60, (raids:GetWidth() or 300) - 20 - 34)
      for shown = math.min(#entry.open, 8), 0, -1 do
        local names = {}
        for n = 1, shown do names[n] = W.ClassName(entry.open[n].name, entry.open[n].classFile) end
        local text = L.RAIDS_OPEN .. " " .. table.concat(names, ", ")
        if #entry.open == 0 then
          text = L.RAIDS_OPEN .. " |cffffffff" .. L.RAIDS_OPEN_NONE .. "|r"
        elseif shown < #entry.open then
          text = text .. (shown > 0 and ", " or "") .. "|cffffd100+" .. (#entry.open - shown) .. "|r"
        end
        block.Open:SetText(text)
        if (block.Open:GetStringWidth() or 0) <= room then break end
      end
      block:Show()
    end
    for i = #list + 1, #view.RaidBlocks do view.RaidBlocks[i]:Hide() end
  end

  function view:Layout()
    local width, height = panel:GetWidth() or 0, panel:GetHeight() or 0
    if width < 100 or height < 100 then return end
    local third = (width - 2 * GAP) / 3
    local top = math.floor(height * TOP_SHARE)
    local bottom = height - top - GAP
    for i, pair in ipairs({ { score, online }, { month, changes }, { ilvl, raids } }) do
      local x = (i - 1) * (third + GAP)
      pair[1]:ClearAllPoints()
      pair[1]:SetPoint("TOPLEFT", panel, "TOPLEFT", x, 0)
      pair[1]:SetSize(third, top)
      pair[2]:ClearAllPoints()
      pair[2]:SetPoint("TOPLEFT", panel, "TOPLEFT", x, -(top + GAP))
      pair[2]:SetSize(third, bottom)
    end
    -- activity: the five bars under the pulse; the hint at the bottom only where there is room
    local first = 74
    local step = math.min(30, math.max(17, (top - first - 26) / #self.ScoreRows))
    for i, row in ipairs(self.ScoreRows) do
      row:ClearAllPoints()
      row:SetPoint("TOPLEFT", score, "TOPLEFT", 12, -first - (i - 1) * step)
      row:SetPoint("RIGHT", score, "RIGHT", -10, 0)
    end
    self.ScoreClick:SetShown(top - first - #self.ScoreRows * step >= 24)
    -- this month: six rows over the box
    local pitch = math.min(46, math.max(24, (top - 34) / #self.MonthRows))
    for i, row in ipairs(self.MonthRows) do
      row:ClearAllPoints()
      row:SetPoint("TOPLEFT", month, "TOPLEFT", 12, -30 - (i - 1) * pitch)
      row:SetPoint("RIGHT", month, "RIGHT", -12, 0)
      row:SetHeight(math.min(28, pitch - 2))
    end
    online:Arrange(bottom)
    PlaceMonth()
    PlaceColumns()
    PlaceRaids()
  end

  function view:Refresh()
    local settings = ns.Settings()
    local windowDays = settings.activityDays
    local members = ns.Roster.Members()
    local guild = ns.GuildData()
    local activity = ns.GameActivity.Get()
    local summary = activity.summary

    -- activity
    self.Pulse:SetText(summary.pulse and Whole(summary.pulse) or "–")
    local change = Change(activity.change, Whole)
    self.PulseLabel:SetText(L.SCORE_PULSE .. (change and ("   " .. L.SCORE_CHANGE:format(change)) or ""))
    self.PulseOf:SetText(L.SCORE_PULSE_OF:format(summary.scored))
    local max = 1
    for _, count in ipairs(summary.buckets) do max = math.max(max, count) end
    for bucket, row in ipairs(self.ScoreRows) do
      local green = 1 - (bucket - 1) / 3
      if bucket == 5 then
        row:SetData(L.SCORE_5, summary.buckets[5], max, 0.5, 0.47, 0.4)
        row.Label:SetTextColor(0.5, 0.5, 0.5)
        row.Count:SetTextColor(0.5, 0.5, 0.5)
      else
        row:SetData(L["SCORE_" .. bucket] .. "  " .. GREY .. SCORE_RANGES[bucket] .. "|r", summary.buckets[bucket], max,
          1 - green * 0.6, 0.35 + green * 0.5, 0.25)
        row.Label:SetTextColor(1, 1, 1)
      end
    end

    -- this month
    for i, data in ipairs(activity.month) do
      local row = self.MonthRows[i]
      local format = data.id == "days" and Decimal or Whole
      local compare = data.compare
      if compare and data.id ~= "days" then compare = math.floor(compare + 0.5) end
      local delta = Change(compare and data.value - compare or nil, format)
      row.Label:SetText(L[MONTH_LABELS[data.id]])
      row.Value:SetText(format(data.value) .. (delta and ("  " .. delta) or ""))
      local scale = math.max(data.value, compare or 0) * 1.08
      row.fraction = scale > 0 and data.value / scale or 0
      row.mark = (compare and scale > 0) and compare / scale or nil
    end

    -- item level and raids: the level 60 members active in the time window
    local function ValuesOf(m)
      local record = guild and guild.members[m.key]
      local stats = record and record.stats
      return type(stats) == "table" and type(stats.v) == "table" and stats.v or nil
    end
    local function IlvlOf(m)
      local values = ValuesOf(m)
      return values and values[S.GEAR.ILVL] or nil
    end
    local thisMonth = S.MonthKey(ns.Now(), ns.GameStats.Date)
    local function MonthStartOf(m)
      if thisMonth == S.LAUNCH_MONTH then return {} end -- nothing happened before the launch
      local record = guild and guild.members[m.key]
      local months = record and type(record.stats) == "table" and record.stats.months
      local snap = type(months) == "table" and months[thisMonth]
      return type(snap) == "table" and type(snap.v) == "table" and snap.v or nil
    end
    self.ilvls = ns.Census.ItemLevels(members, windowDays, IlvlOf)
    self.IlvlMax:SetText(L.LEVEL_MAX:format(self.ilvls.top))
    local raidList = {}
    for _, dungeon in ipairs(S.DUNGEONS) do
      if dungeon.raid then raidList[#raidList + 1] = dungeon end
    end
    self.raids = ns.Census.Raids(members, windowDays, raidList, ValuesOf, MonthStartOf, IlvlOf)
    for i, entry in ipairs(self.raids) do
      local block = RaidBlock(i)
      block.raid = entry.raid
      local path, cropped = UI.DungeonIcon(entry.raid)
      block.Icon:SetTexture(path or W.LOGO)
      if path and not cropped then block.Icon:SetTexCoord(0, 1, 0, 1) else block.Icon:SetTexCoord(0.07, 0.93, 0.07, 0.93) end
      block.Name:SetText(UI.DungeonTitle(entry.raid))
      block.New:SetText(entry.new > 0 and L.RAIDS_NEW:format(entry.new) or "")
      block.Count:SetText(#entry.killers .. GREY .. " / " .. entry.readings .. "|r")
    end

    online:Fill(ns.Census.Compute(members, false).activity)
    changes:Fill()
    self:Layout()
  end

  return view
end
