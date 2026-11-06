-- Hall of Fame tab: three pages (general with equipment, economy, dungeons) of guild totals, title
-- cards and a page-specific box, from the members' statistics (Core/Stats.lua, Game/Stats.lua), with
-- a period switch (all time / this month / last month). A click on a total, a card, a gold source or
-- a dungeon opens the detail view: every tracked statistic in a tree on the left, the guild ranking of
-- the chosen one on the right.
local _, ns = ...
local W = ns.Widgets
local UI = ns.UI
local S = ns.Stats

local SPECIAL = { bosses = "FAME_BOSSES", dungeons = "FAME_DUNGEONS_DONE", spent = "FAME_SPENT",
  [S.GEAR.ILVL] = "FAME_GEAR_ILVL", [S.GEAR.EPIC] = "FAME_GEAR_EPIC", [S.GEAR.RARE] = "FAME_GEAR_RARE",
  [S.GEAR.UNCOMMON] = "FAME_GEAR_UNCOMMON", [339] = "FAME_MOUNTS", [338] = "FAME_PETS",
  [931] = "FAME_REP_931", [1466] = "FAME_REP_1466", [529] = "FAME_REP_529", [378] = "FAME_REP_378", [377] = "FAME_REP_377" }

-- a round dot in an item quality color, one per equipped item (the font has no dot character)
local DOT = "|TInterface\\CHARACTERFRAME\\TempPortraitAlphaMask:9:9:0:0:64:64:0:64:0:64:%d:%d:%d|t"
local QUALITY_DOTS = { { S.GEAR.EPIC, 163, 53, 238 }, { S.GEAR.RARE, 0, 112, 221 }, { S.GEAR.UNCOMMON, 30, 255, 0 } }

-- dots = { {count, r, g, b} } with colors 0-255
local function DotRow(dots)
  local parts = {}
  for _, d in ipairs(dots) do
    local dot = DOT:format(d[2], d[3], d[4])
    for _ = 1, math.min(d[1] or 0, 30 - #parts) do parts[#parts + 1] = dot end
  end
  return #parts > 0 and table.concat(parts) or "|cff9a8f78–|r"
end

local function Dots(values)
  local dots = {}
  for i, quality in ipairs(QUALITY_DOTS) do dots[i] = { values[quality[1]] or 0, quality[2], quality[3], quality[4] } end
  return DotRow(dots)
end

-- reputation standings: key, locale key, color
local REP_TIERS = {
  { "exalted", "FAME_REP_EXALTED", 255, 209, 0 }, { "revered", "FAME_REP_REVERED", 51, 217, 191 },
  { "honored", "FAME_REP_HONORED", 77, 204, 64 }, { "friendly", "FAME_REP_FRIENDLY", 200, 200, 200 },
}

-- colors of the gold sources and spending rows
local FLOW_COLORS = {
  [326] = { 0.79, 0.64, 0.15 }, [333] = { 0.48, 0.60, 0.23 }, [921] = { 0.54, 0.42, 0.60 }, [919] = { 0.23, 0.48, 0.63 },
  [1146] = { 0.23, 0.48, 0.63 }, [1148] = { 0.48, 0.60, 0.23 }, [1150] = { 0.79, 0.64, 0.15 }, [1147] = { 0.54, 0.42, 0.60 },
}

local function StatName(id)
  if SPECIAL[id] then return ns.L[SPECIAL[id]] end
  local _, name = ns.Try(rawget(_G, "GetAchievementInfo"), id)
  return name or ("#" .. tostring(id))
end

local function CategoryName(category)
  if category.label then return ns.L[category.label] end
  local name = ns.Try(rawget(_G, "GetCategoryInfo"), category.id)
  return name or ("#" .. tostring(category.id))
end

-- "Todesminen" from "Siege über Edwin van Cleef (Todesminen)"
local function DungeonName(id)
  local name = StatName(id)
  return name:match("%(([^%)]+)%)%s*$") or name
end

local function Number(n)
  local big = rawget(_G, "BreakUpLargeNumbers")
  return big and big(n) or tostring(n)
end

local function Format(id, value)
  if not value then return "–" end
  if S.MONEY[id] then
    local gold, silver = math.floor(value / 10000), math.floor(value / 100) % 100
    -- below 100 gold the silver counts too (4g and 59s would otherwise not add up to the total)
    if gold > 0 and (gold >= 100 or silver == 0) then return Number(gold) .. "|cffffd100g|r" end
    if gold > 0 then return gold .. "|cffffd100g|r " .. silver .. "|cffc7c7cfs|r" end
    if silver > 0 then return silver .. "|cffc7c7cfs|r" end
    return (value % 100) .. "|cffeda55fc|r"
  end
  if S.TENTHS[id] then return (string.format("%.1f", value / 10):gsub("%.", ns.L.DECIMAL_MARK)) end
  return Number(value)
end

local function Icon(name)
  local path = "Interface\\Icons\\" .. name
  return W.TextureExists(path) and path or "Interface\\Icons\\INV_Misc_QuestionMark"
end

local function ShortDate(ts)
  local date = rawget(_G, "date") or os.date
  return date("%d.%m.", ts)
end

local function Page(key)
  for _, page in ipairs(S.PAGES) do
    if page.key == key then return page end
  end
  return S.PAGES[1]
end

local function Build(panel)
  local L = ns.L
  local view = { period = ns.Settings().famePeriod or "all", page = Page(ns.Settings().famePage).key, mode = "home" }

  -- top bar -------------------------------------------------------------------------------------
  local title = W.Text(panel, "GameFontNormalLarge", L.TAB_FAME)
  title:SetPoint("TOPLEFT", 54, -4) -- clear of the portrait
  -- how many members the values come from: a tooltip on the title, not another text in the bar
  local titleHover = CreateFrame("Frame", nil, panel)
  titleHover:SetAllPoints(title)
  titleHover:EnableMouse(true)
  titleHover:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOMRIGHT")
    GameTooltip:SetText(L.TAB_FAME, 1, 0.82, 0)
    GameTooltip:AddLine(view.freshText or "", 1, 1, 1, true)
    GameTooltip:Show()
  end)
  titleHover:SetScript("OnLeave", function() GameTooltip:Hide() end)
  local pageOptions = {}
  for i, page in ipairs(S.PAGES) do pageOptions[i] = { value = page.key, text = L["FAME_PAGE_" .. page.key:upper()] } end
  view.Pages = W.Segmented(panel, pageOptions, function(value)
    view.page = value
    ns.Settings().famePage = value
    view.mode = "home"
    view:Refresh()
  end)
  view.Pages:SetPoint("LEFT", title, "RIGHT", 14, 0)
  -- right side: period dropdown (all time / this month / last month) and the button to all
  -- statistics (back to the pages in the detail view); both always in the same place
  local PERIODS = { { value = "all", text = L.FAME_ALL }, { value = "month", text = L.FAME_MONTH },
    { value = "last", text = L.FAME_LAST } }
  view.Period = W.MenuButton(panel, L.FAME_ALL, function()
    local items = { { text = L.FAME_PERIOD, isTitle = true } }
    for _, option in ipairs(PERIODS) do
      -- Forever's launch month has no month before it: shown, but greyed out
      local none = option.value == "last" and view:LaunchMonth()
      items[#items + 1] = { text = none and L.FAME_LAST_NONE or option.text, disabled = none,
        checked = view.period == option.value, onClick = function()
          view.period = option.value
          ns.Settings().famePeriod = option.value
          view:Refresh()
        end }
    end
    return items
  end, 180)
  function view:LaunchMonth()
    return S.MonthKey(ns.Now(), ns.GameStats.Date) == S.LAUNCH_MONTH
  end
  function view.Period:SetValue(value)
    for _, option in ipairs(PERIODS) do
      if option.value == value then self:SetText(L.FAME_PERIOD .. ": " .. option.text) end
    end
  end
  view.AllButton = W.Button(panel, L.FAME_ALL_STATS, function()
    if view.mode == "detail" then view:ShowHome() else view:ShowDetail(view.detailStat or 107) end
  end, 170, { small = true })
  view.AllButton:SetPoint("TOPRIGHT", 0, -2)
  view.Period:SetPoint("RIGHT", view.AllButton, "LEFT", -8, 0)

  -- home: totals, cards, page box -----------------------------------------------------------------
  local home = CreateFrame("Frame", nil, panel)
  home:SetPoint("TOPLEFT", 0, -30)
  home:SetPoint("BOTTOMRIGHT", 0, 0)
  view.Home = home

  view.Tiles = {}
  for i = 1, 6 do
    local tile = W.Box(home)
    tile:SetHeight(64)
    tile.Value = W.Text(tile, "GameFontNormalHuge")
    tile.Label = W.Text(tile, "GameFontDisableSmall")
    tile.Label:SetPoint("TOP", tile.Value, "BOTTOM", 0, -2)
    tile.Trend = W.Text(tile, "GameFontHighlightSmall")
    tile.Trend:SetPoint("TOP", tile.Label, "BOTTOM", 0, -2)
    tile:EnableMouse(true)
    tile:SetScript("OnMouseUp", function(self) if self.id then view:ShowDetail(self.id) end end)
    view.Tiles[i] = tile
  end

  -- Text block vertically centered (higher with a trend line)
  local function PlaceTile(tile)
    tile.Value:ClearAllPoints()
    tile.Value:SetPoint("CENTER", 0, (tile.Trend:GetText() or "") ~= "" and 13 or 7)
  end

  view.Cards = {}
  for i = 1, 8 do
    local card = W.Box(home)
    card:SetHeight(48)
    card.Icon = card:CreateTexture(nil, "ARTWORK")
    card.Icon:SetSize(36, 36)
    card.Icon:SetPoint("LEFT", 6, 0)
    card.Title = W.Text(card, "GameFontNormal")
    card.Title:SetPoint("TOPLEFT", card.Icon, "TOPRIGHT", 8, 0)
    card.Title:SetPoint("RIGHT", -6, 0)
    card.Title:SetWordWrap(false)
    card.Name = W.Text(card, "GameFontHighlightSmall")
    card.Name:SetPoint("TOPLEFT", card.Title, "BOTTOMLEFT", 0, -2)
    card.Name:SetPoint("RIGHT", -6, 0)
    card.Name:SetWordWrap(false)
    card.Value = W.Text(card, "GameFontDisableSmall")
    card.Value:SetPoint("TOPLEFT", card.Name, "BOTTOMLEFT", 0, -2)
    card.Value:SetPoint("RIGHT", -6, 0)
    card.Value:SetWordWrap(false)
    card:EnableMouse(true)
    card:SetScript("OnMouseUp", function(self) if self.stat then view:ShowDetail(self.stat) end end)
    view.Cards[i] = card
  end

  -- a member table filling the rest of a page: the columns share the width by weight, the age column
  -- sits at the right edge. cols = { {key, weight, text, stat, bar} }; fill(row, entry, box) sets the
  -- cells (box.width[key] = width of a column).
  local AGE_WIDTH = 70
  local function MemberTable(titleText, cols, fill)
    local box = W.Box(home)
    local boxTitle = W.Text(box, "GameFontNormal", titleText)
    boxTitle:SetPoint("TOPLEFT", 10, -8)
    box.Hint = W.Text(box, "GameFontDisableSmall")
    box.Hint:SetPoint("LEFT", boxTitle, "RIGHT", 8, 0)
    box.cols, box.heads, box.x, box.width = cols, {}, {}, {}
    for i, col in ipairs(cols) do
      local head = CreateFrame("Button", nil, box)
      head:SetHeight(16)
      head.Text = W.Text(head, "GameFontDisableSmall", col.text or "")
      head.Text:SetAllPoints()
      head.Text:SetJustifyH("LEFT")
      head.Text:SetWordWrap(false)
      if col.stat then head:SetScript("OnClick", function() view:ShowDetail(col.stat) end) end
      box.heads[i] = head
    end
    local age = W.Text(box, "GameFontDisableSmall", L.FAME_GEAR_AGE)
    age:SetPoint("TOPRIGHT", -32, -30)
    box.List = W.ScrollList(box, 18, function(row)
      row.Cols = {}
      for _, col in ipairs(cols) do
        if col.bar then
          local bar = row:CreateTexture(nil, "ARTWORK")
          bar:SetHeight(8)
          row.Cols[col.key] = bar
        else
          local text = W.Text(row, "GameFontHighlightSmall")
          text:SetJustifyH("LEFT")
          text:SetWordWrap(false)
          row.Cols[col.key] = text
        end
      end
      row.Age = W.Text(row, "GameFontDisableSmall")
      row.Age:SetPoint("RIGHT", -4, 0)
      row.Age:SetJustifyH("RIGHT")
      row.Mine = row:CreateTexture(nil, "BACKGROUND")
      row.Mine:SetAllPoints()
      row.Mine:SetColorTexture(1, 0.82, 0, 0.15)
      row:EnableMouse(true)
      row:SetScript("OnEnter", function(self) if self.member then UI.MemberTooltip(self, self.member) end end)
      row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end, function(row, entry)
      for _, col in ipairs(cols) do
        local cell = row.Cols[col.key]
        cell:ClearAllPoints()
        cell:SetPoint("LEFT", box.x[col.key] or 0, 0)
        if not col.bar then cell:SetWidth(math.max(1, (box.width[col.key] or 60) - 6)) end
      end
      row.member = entry.member
      row.Cols.name:SetText(W.ClassName(entry.name, entry.classFile))
      fill(row, entry, box)
      row.Age:SetText(UI.Age(entry.rec.ts))
      row.Mine:SetShown(entry.key == ns.Names.Key(ns.PlayerName()))
    end)
    box.List:SetPoint("TOPLEFT", 8, -46)
    box.List:SetPoint("BOTTOMRIGHT", -28, 8)
    box.Empty = W.Text(box, "GameFontDisable")
    box.Empty:SetPoint("TOPLEFT", 12, -50)
    box.Empty:SetPoint("RIGHT", -12, 0)
    box.Empty:SetJustifyH("LEFT")
    function box:Columns()
      local room = math.max(200, (self:GetWidth() or 600) - 36 - AGE_WIDTH)
      local total = 0
      for _, col in ipairs(self.cols) do total = total + col.weight end
      local x = 4
      for i, col in ipairs(self.cols) do
        local w = room * col.weight / total
        self.x[col.key], self.width[col.key] = x, w
        self.heads[i]:ClearAllPoints()
        self.heads[i]:SetPoint("TOPLEFT", self, "TOPLEFT", 8 + x, -28)
        self.heads[i]:SetWidth(math.max(1, w - 6))
        x = x + w
      end
    end
    return box
  end

  -- general: equipment of Guildy users
  local gear = MemberTable(L.FAME_GEAR, {
    { key = "name", weight = 3, text = L.COL_NAME },
    { key = "level", weight = 0.9, text = L.COL_LEVEL },
    { key = "ilvl", weight = 2.6, text = L.FAME_GEAR_ILVL, stat = S.GEAR.ILVL },
    { key = "bar", weight = 2.4, bar = true },
    { key = "quality", weight = 3.2, text = L.FAME_GEAR_QUALITY, stat = S.GEAR.EPIC },
    { key = "month", weight = 1.4, text = L.FAME_THIS_MONTH, stat = S.GEAR.ILVL },
  }, function(row, entry, box)
    local v = entry.rec.v
    local level = entry.member and entry.member.level
    local ilvl = v[S.GEAR.ILVL]
    row.Cols.level:SetText(level or "–")
    local rating = S.GearRating(ilvl and ilvl / 10, level)
    local note = rating == "good" and (" |cff40e040(" .. L.FAME_GEAR_GOOD:format(level) .. ")|r")
      or (rating == "behind" and (" |cffe0a040(" .. L.FAME_GEAR_BEHIND .. ")|r") or "")
    row.Cols.ilvl:SetText(Format(S.GEAR.ILVL, ilvl) .. note)
    local r, g, b = W.ClassColor(entry.classFile)
    row.Cols.bar:SetColorTexture(r, g, b, 0.85)
    local room = math.max(10, (box.width.bar or 100) - 12)
    row.Cols.bar:SetWidth(math.max(1, room * ((ilvl or 0) / math.max(1, box.maxIlvl or 1))))
    row.Cols.quality:SetText(Dots(v))
    local growth = S.Value(entry.rec, S.GEAR.ILVL, "month", ns.Now(), ns.GameStats.Date)
    row.Cols.month:SetText(growth and growth > 0 and ("|cff40e040+" .. Format(S.GEAR.ILVL, growth) .. "|r") or "|cff9a8f78–|r")
  end)
  gear.Empty:SetText(L.FAME_GEAR_EMPTY)
  view.Gear = gear

  -- economy: where the gold comes from and where it goes
  local function FlowBox(titleKey, ids)
    local box = W.Box(home)
    box.Title = W.Text(box, "GameFontNormal", L[titleKey])
    box.Title:SetPoint("TOPLEFT", 10, -8)
    box.Total = W.Text(box, "GameFontHighlightSmall")
    box.Total:SetPoint("TOPRIGHT", -10, -9)
    box.Rows = {}
    for i, id in ipairs(ids) do
      local row = W.BarRow(box, 110)
      row.Count:SetWidth(110)
      row:SetPoint("TOPLEFT", 10, -32 - (i - 1) * 22)
      row:SetPoint("RIGHT", -10, 0)
      row.id = id
      row:SetScript("OnClick", function(self) view:ShowDetail(self.id) end)
      box.Rows[i] = row
    end
    return box
  end
  view.Income = FlowBox("FAME_INCOME", S.INCOME)
  view.Spending = FlowBox("FAME_SPENDING", S.SPENDING)
  view.FlowNote = W.Text(home, "GameFontDisableSmall", L.FAME_FLOW_NOTE)
  view.Economy = MemberTable(L.FAME_ECONOMY_TABLE, {
    { key = "name", weight = 3, text = L.COL_NAME },
    { key = "earned", weight = 2, text = L.FAME_EARNED, stat = 328 },
    { key = "spent", weight = 2, text = L.FAME_SPENT, stat = "spent" },
    { key = "posted", weight = 1.8, text = L.FAME_POSTED, stat = 329 },
    { key = "bought", weight = 1.8, text = L.FAME_BOUGHT, stat = 330 },
    { key = "best", weight = 2.2, text = L.FAME_BEST_SALE, stat = 332 },
  }, function(row, entry)
    local function Cell(id, period)
      local value = S.Value(entry.rec, id, period or view.period, ns.Now(), ns.GameStats.Date)
      return value and value > 0 and Format(id, value) or "|cff9a8f78–|r"
    end
    row.Cols.earned:SetText(Cell(328))
    row.Cols.spent:SetText(Cell("spent"))
    row.Cols.posted:SetText(Cell(329))
    row.Cols.bought:SetText(Cell(330))
    row.Cols.best:SetText(Cell(332, "all"))
  end)
  view.Economy.Hint:SetText(L.FAME_ECONOMY_HINT)
  view.Economy.Empty:SetText(L.FAME_ECONOMY_EMPTY)

  -- reputation: factions per standing, one dot per faction
  local repCols = { { key = "name", weight = 3, text = L.COL_NAME }, { key = "dots", weight = 3.6, text = L.FAME_REP_DOTS } }
  local repStats = { exalted = 377, revered = 378, honored = 529, friendly = 1466 }
  for _, tier in ipairs(REP_TIERS) do
    repCols[#repCols + 1] = { key = tier[1], weight = 1.3, stat = repStats[tier[1]],
      text = ("|cff%02x%02x%02x%s|r"):format(tier[3], tier[4], tier[5], L[tier[2]]) }
  end
  repCols[#repCols + 1] = { key = "met", weight = 1.5, text = L.FAME_REP_MET, stat = 931 }
  view.Reputation = MemberTable(L.FAME_REP_TABLE, repCols, function(row, entry)
    local tiers = S.RepTiers(entry.rec.v)
    local dots = {}
    for _, tier in ipairs(REP_TIERS) do
      dots[#dots + 1] = { tiers[tier[1]], tier[3], tier[4], tier[5] }
      row.Cols[tier[1]]:SetText(tiers[tier[1]] > 0 and tiers[tier[1]] or "|cff9a8f78–|r")
    end
    row.Cols.dots:SetText(DotRow(dots))
    row.Cols.met:SetText(entry.rec.v[S.REP.MET] or "–")
  end)
  view.Reputation.Hint:SetText(L.FAME_REP_HINT)
  view.Reputation.Empty:SetText(L.FAME_REP_EMPTY)


  -- dungeons: end bosses per member
  local dungeons = W.Box(home)
  view.Dungeons = dungeons
  local dungeonTitle = W.Text(dungeons, "GameFontNormal", L.FAME_DUNGEONS)
  dungeonTitle:SetPoint("TOPLEFT", 10, -8)
  local dungeonHint = W.Text(dungeons, "GameFontDisableSmall", L.FAME_DUNGEONS_HINT)
  dungeonHint:SetPoint("LEFT", dungeonTitle, "RIGHT", 8, 0)
  view.DungeonHeads = {}
  view.DungeonRows = W.ScrollList(dungeons, 18, function(row)
    row.Name = W.Text(row, "GameFontHighlightSmall")
    row.Name:SetPoint("LEFT", 4, 0)
    row.Name:SetWidth(150)
    row.Name:SetWordWrap(false)
    row.Cells = {}
  end, function(row, entry)
    row.Name:SetText(W.ClassName(entry.name, entry.classFile))
    for i, id in ipairs(view.dungeonColumns or {}) do
      local cell = row.Cells[i]
      if not cell then
        cell = W.Text(row, "GameFontHighlightSmall")
        cell:SetJustifyH("CENTER")
        row.Cells[i] = cell
      end
      cell:ClearAllPoints()
      cell:SetPoint("LEFT", 158 + (i - 1) * view.dungeonColWidth, 0)
      cell:SetWidth(view.dungeonColWidth)
      local kills = S.Value(entry.rec, id, view.period, ns.Now(), ns.GameStats.Date)
      if kills and kills > 0 then
        cell:SetText("|T" .. W.ICON_YES .. ":12|t" .. (kills > 1 and (" " .. kills) or ""))
      else
        cell:SetText("|cff4a3d29·|r")
      end
      cell:Show()
    end
    for i = #(view.dungeonColumns or {}) + 1, #row.Cells do row.Cells[i]:Hide() end
  end)
  view.DungeonRows:SetPoint("TOPLEFT", 8, -46)
  view.DungeonRows:SetPoint("BOTTOMRIGHT", -28, 8)
  view.DungeonEmpty = W.Text(dungeons, "GameFontDisable", L.FAME_DUNGEONS_EMPTY)
  view.DungeonEmpty:SetPoint("TOPLEFT", 12, -50)

  view.Empty = W.Text(home, "GameFontDisable", L.FAME_EMPTY)
  view.Empty:SetPoint("CENTER", 0, 20)
  view.Empty:SetWidth(520)
  view.Empty:SetJustifyH("CENTER")

  -- detail: statistic tree and ranking ---------------------------------------------------------
  local detail = CreateFrame("Frame", nil, panel)
  detail:SetPoint("TOPLEFT", 0, -30)
  detail:SetPoint("BOTTOMRIGHT", 0, 0)
  detail:Hide()
  view.Detail = detail

  local tree = W.Box(detail)
  tree:SetPoint("TOPLEFT", 0, 0)
  tree:SetPoint("BOTTOM", 0, 0)
  tree:SetWidth(250)
  view.Tree = W.ScrollList(tree, 18, function(row)
    row.Text = W.Text(row, "GameFontHighlightSmall")
    row.Text:SetPoint("LEFT", 4, 0)
    row.Text:SetPoint("RIGHT", -4, 0)
    row.Text:SetWordWrap(false)
    row.Selected = row:CreateTexture(nil, "BACKGROUND")
    row.Selected:SetAllPoints()
    row.Selected:SetColorTexture(1, 0.82, 0, 0.18)
    row:EnableMouse(true)
    row:SetScript("OnMouseUp", function(self) if self.stat then view:ShowDetail(self.stat) end end)
  end, function(row, item)
    row.stat = item.stat
    if item.stat then
      row.Text:SetText("   " .. item.text)
      row.Text:SetFontObject("GameFontHighlightSmall")
    else
      row.Text:SetText(item.text)
      row.Text:SetFontObject("GameFontNormal")
    end
    row.Selected:SetShown(item.stat ~= nil and item.stat == view.detailStat)
  end)
  view.Tree:SetPoint("TOPLEFT", 8, -8)
  view.Tree:SetPoint("BOTTOMRIGHT", -28, 8)

  local board = W.Box(detail)
  board:SetPoint("TOPLEFT", tree, "TOPRIGHT", 8, 0)
  board:SetPoint("BOTTOMRIGHT", 0, 0)
  view.BoardTitle = W.Text(board, "GameFontNormalLarge")
  view.BoardTitle:SetPoint("TOPLEFT", 12, -10)
  view.BoardTitle:SetPoint("RIGHT", -12, 0)
  view.BoardTitle:SetWordWrap(false)
  view.BoardTiles = {}
  for i = 1, 3 do
    local tile = W.Box(board, 0.12)
    tile:SetHeight(52)
    tile.Value = W.Text(tile, "GameFontNormalLarge")
    tile.Value:SetPoint("TOP", 0, -8)
    tile.Label = W.Text(tile, "GameFontDisableSmall")
    tile.Label:SetPoint("TOP", tile.Value, "BOTTOM", 0, -3)
    view.BoardTiles[i] = tile
  end
  view.Board = W.ScrollList(board, 20, function(row)
    row.Rank = W.Text(row, "GameFontDisableSmall")
    row.Rank:SetPoint("LEFT", 2, 0)
    row.Rank:SetWidth(22)
    row.Rank:SetJustifyH("RIGHT")
    row.Name = W.Text(row, "GameFontHighlightSmall")
    row.Name:SetPoint("LEFT", 30, 0)
    row.Name:SetWidth(160)
    row.Name:SetWordWrap(false)
    row.Bar = row:CreateTexture(nil, "ARTWORK")
    row.Bar:SetPoint("LEFT", 196, 0)
    row.Bar:SetHeight(10)
    row.Bar:SetColorTexture(1, 0.82, 0, 0.75)
    row.Value = W.Text(row, "GameFontHighlightSmall")
    row.Value:SetPoint("RIGHT", -120, 0)
    row.Value:SetJustifyH("RIGHT")
    row.Age = W.Text(row, "GameFontDisableSmall")
    row.Age:SetPoint("RIGHT", -4, 0)
    row.Age:SetWidth(110)
    row.Age:SetJustifyH("RIGHT")
    row.Mine = row:CreateTexture(nil, "BACKGROUND")
    row.Mine:SetAllPoints()
    row.Mine:SetColorTexture(1, 0.82, 0, 0.15)
    row:EnableMouse(true)
    row:SetScript("OnEnter", function(self) if self.member then UI.MemberTooltip(self, self.member) end end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
  end, function(row, item, i)
    row.member = item.member
    row.Rank:SetText(i)
    row.Name:SetText(W.ClassName(item.name, item.classFile))
    row.Value:SetText(Format(view.detailStat, item.value))
    local barRoom = math.max(10, row:GetWidth() - 196 - 230)
    row.Bar:SetWidth(math.max(1, barRoom * (view.boardMax > 0 and item.value / view.boardMax or 0)))
    local src = item.rec.src == "seen" and L.FAME_SRC_SEEN or (item.rec.src == "self" and L.FAME_SRC_SELF or L.FAME_SRC_RELAY)
    row.Age:SetText(src .. " · " .. UI.Age(item.rec.ts))
    row.Mine:SetShown(item.key == ns.Names.Key(ns.PlayerName()))
  end)
  view.Board:SetPoint("TOPLEFT", 8, -104)
  view.Board:SetPoint("BOTTOMRIGHT", -28, 26)
  view.BoardNote = W.Text(board, "GameFontDisableSmall")
  view.BoardNote:SetPoint("BOTTOMLEFT", 12, 8)
  view.BoardNote:SetPoint("RIGHT", -12, 0)

  -- layout ----------------------------------------------------------------------------------------
  function view:Layout()
    local width = panel:GetWidth() or 0
    if width < 100 then return end
    local gap = 8
    local tiles = #Page(self.page).headline
    local tileWidth = (width - gap * (tiles - 1)) / tiles
    for i, tile in ipairs(self.Tiles) do
      tile:ClearAllPoints()
      tile:SetWidth(tileWidth)
      tile:SetPoint("TOPLEFT", home, "TOPLEFT", (i - 1) * (tileWidth + gap), 0)
      PlaceTile(tile)
    end
    local cardWidth = (width - gap * 3) / 4
    for i, card in ipairs(self.Cards) do
      card:ClearAllPoints()
      card:SetWidth(cardWidth)
      local column, row = (i - 1) % 4, math.floor((i - 1) / 4)
      card:SetPoint("TOPLEFT", home, "TOPLEFT", column * (cardWidth + gap), -72 - row * 56)
    end
    local shownCards = 0
    for _, card in ipairs(self.Cards) do if card:IsShown() then shownCards = shownCards + 1 end end
    local top = -72 - math.ceil(shownCards / 4) * 56
    for _, box in ipairs({ gear, dungeons, self.Reputation }) do
      box:ClearAllPoints()
      box:SetPoint("TOPLEFT", home, "TOPLEFT", 0, top)
      box:SetPoint("BOTTOMRIGHT", home, "BOTTOMRIGHT", 0, 0)
    end
    local half = (width - gap) / 2
    local flowHeight = 40 + #S.INCOME * 22
    self.Income:ClearAllPoints()
    self.Income:SetPoint("TOPLEFT", home, "TOPLEFT", 0, top)
    self.Income:SetSize(half, flowHeight)
    self.Spending:ClearAllPoints()
    self.Spending:SetPoint("TOPLEFT", home, "TOPLEFT", half + gap, top)
    self.Spending:SetSize(half, flowHeight)
    self.FlowNote:ClearAllPoints()
    self.FlowNote:SetPoint("TOPLEFT", self.Income, "BOTTOMLEFT", 4, -6)
    self.Economy:ClearAllPoints()
    self.Economy:SetPoint("TOPLEFT", home, "TOPLEFT", 0, top - flowHeight - 26)
    self.Economy:SetPoint("BOTTOMRIGHT", home, "BOTTOMRIGHT", 0, 0)
    gear:Columns()
    self.Reputation:Columns()
    self.Economy:Columns()
    local boardWidth = board:GetWidth() or 0
    local boardTile = (boardWidth - 24 - gap * 2) / 3
    for i, tile in ipairs(self.BoardTiles) do
      tile:ClearAllPoints()
      tile:SetWidth(math.max(60, boardTile))
      tile:SetPoint("TOPLEFT", board, "TOPLEFT", 12 + (i - 1) * (boardTile + gap), -40)
    end
  end

  function view:OnResize()
    self:Layout()
    self:Refresh()
  end

  -- data ------------------------------------------------------------------------------------------
  local function Ranking(entries, id, period)
    local list = S.Ranking(entries, id, period, ns.Now(), ns.GameStats.Date)
    for _, row in ipairs(list) do
      for _, entry in ipairs(entries) do
        if entry.key == row.key then
          row.classFile, row.member = entry.classFile, entry.member
          break
        end
      end
    end
    return list
  end

  -- Guild value of a tile: the sum over the members; for "dungeons" the dungeons anybody cleared
  -- (a sum would count the same dungeon once per member)
  local function GuildValue(entries, id, period)
    if id ~= "dungeons" then
      local ranking = Ranking(entries, id, period)
      return S.Total(ranking), #ranking > 0
    end
    local count, known = 0, false
    for _, boss in ipairs(S.Bosses()) do
      for _, entry in ipairs(entries) do
        local kills = S.Value(entry.rec, boss, period, ns.Now(), ns.GameStats.Date)
        if kills then known = true end
        if kills and kills > 0 then
          count = count + 1
          break
        end
      end
    end
    return count, known
  end

  function view:RefreshTiles(entries, page)
    for i, tile in ipairs(self.Tiles) do
      local id = page.headline[i]
      tile.id = id
      tile:SetShown(id ~= nil)
      if id then
        tile.Label:SetText(id == "dungeons" and L.FAME_GUILD_DUNGEONS or StatName(id))
        local total, known = GuildValue(entries, id, self.period)
        tile.Value:SetText(known and Format(id, total) or "–")
        local trend = ""
        if id == "dungeons" and self.period == "all" then
          local month = GuildValue(entries, id, "month")
          if month > 0 then trend = L.FAME_DUNGEONS_MONTH:format(month) end
        elseif self.period == "month" then
          local last = GuildValue(entries, id, "last")
          if last > 0 then
            local pct = math.floor((total / last - 1) * 100 + 0.5)
            trend = (pct >= 0 and "|cff40e040+" or "|cffff5a4a-") .. math.abs(pct) .. " %|r " .. L.FAME_VS_LAST
          end
        elseif self.period == "all" then
          local month = GuildValue(entries, id, "month")
          -- in the launch month this month is everything: no trend
          if month > 0 and month ~= total then trend = "|cff40e040+" .. Format(id, month) .. "|r " .. L.FAME_THIS_MONTH end
        end
        tile.Trend:SetText(trend)
        PlaceTile(tile)
      end
    end
  end

  function view:RefreshCards(entries, page)
    local index = 0
    for _, fame in ipairs(page.titles) do
      if index < #self.Cards then
        local top = Ranking(entries, fame.stat, fame.current and "all" or self.period)[1]
        if top and top.value > 0 then
          index = index + 1
          local card = self.Cards[index]
          card.stat = fame.stat
          card.Icon:SetTexture(Icon(fame.icon))
          card.Title:SetText(L["FAME_TITLE_" .. fame.key])
          card.Name:SetText(W.ClassName(top.name, top.classFile))
          card.Value:SetText(Format(fame.stat, top.value) .. " · " .. StatName(fame.stat))
          card:Show()
        end
      end
    end
    for i = index + 1, #self.Cards do self.Cards[i]:Hide() end
  end

  function view:RefreshGear(entries)
    local rows = {}
    for _, entry in ipairs(entries) do
      if entry.rec.v[S.GEAR.ILVL] then rows[#rows + 1] = entry end
    end
    table.sort(rows, function(a, b)
      local x, y = a.rec.v[S.GEAR.ILVL], b.rec.v[S.GEAR.ILVL]
      if x ~= y then return x > y end
      return a.name < b.name
    end)
    self.Gear.maxIlvl = rows[1] and rows[1].rec.v[S.GEAR.ILVL] or 1
    self.Gear.Hint:SetText(L.FAME_GEAR_HINT:format(#rows, #ns.Roster.Members()))
    self.Gear.List:SetItems(rows)
    self.Gear.Empty:SetShown(#rows == 0)
  end

  function view:RefreshReputation(entries)
    local rows = {}
    for _, entry in ipairs(entries) do
      if (entry.rec.v[S.REP.MET] or 0) > 0 then
        local t = S.RepTiers(entry.rec.v)
        rows[#rows + 1] = { entry = entry, score = ((t.exalted * 100 + t.revered) * 100 + t.honored) * 100 + t.friendly }
      end
    end
    table.sort(rows, function(a, b)
      if a.score ~= b.score then return a.score > b.score end
      return a.entry.name < b.entry.name
    end)
    local items = {}
    for i, row in ipairs(rows) do items[i] = row.entry end
    self.Reputation.List:SetItems(items)
    self.Reputation.Empty:SetShown(#items == 0)
  end

  function view:RefreshEconomy(entries)
    local rows = {}
    for _, entry in ipairs(entries) do
      local earned = S.Value(entry.rec, 328, self.period, ns.Now(), ns.GameStats.Date)
      local spent = S.Value(entry.rec, "spent", self.period, ns.Now(), ns.GameStats.Date)
      if (earned or 0) > 0 or (spent or 0) > 0 then rows[#rows + 1] = { entry = entry, earned = earned or 0 } end
    end
    table.sort(rows, function(a, b)
      if a.earned ~= b.earned then return a.earned > b.earned end
      return a.entry.name < b.entry.name
    end)
    local items = {}
    for i, row in ipairs(rows) do items[i] = row.entry end
    self.Economy.List:SetItems(items)
    self.Economy.Empty:SetShown(#items == 0)
  end

  local function FillFlow(box, entries, period)
    local values, total = {}, 0
    for i, row in ipairs(box.Rows) do
      values[i] = S.Total(Ranking(entries, row.id, period))
      total = total + values[i]
    end
    box.Total:SetText(total > 0 and Format(328, total) or "–")
    for i, row in ipairs(box.Rows) do
      local color = FLOW_COLORS[row.id] or { 1, 0.82, 0 }
      local pct = total > 0 and math.floor(values[i] / total * 100 + 0.5) or 0
      row:SetData(L["FAME_FLOW_" .. row.id], values[i], total, color[1], color[2], color[3])
      row.Label:SetTextColor(0.9, 0.86, 0.75) -- the color belongs to the bar, not the label
      row.Fill:SetShown(values[i] > 0)        -- no sliver for nothing
      row.Count:SetText(values[i] > 0 and (Format(328, values[i]) .. "  |cff9a8f78" .. pct .. " %|r") or "|cff9a8f78–|r")
    end
  end

  function view:RefreshDungeons(entries)
    local now = ns.Now()
    -- dungeon columns: bosses somebody killed (in the period), as many as fit
    local columns = {}
    for _, boss in ipairs(S.Bosses()) do
      for _, entry in ipairs(entries) do
        local kills = S.Value(entry.rec, boss, self.period, now, ns.GameStats.Date)
        if kills and kills > 0 then
          columns[#columns + 1] = boss
          break
        end
      end
    end
    local room = (self.Dungeons:GetWidth() or 600) - 40 - 158
    self.dungeonColWidth = 104
    local fit = math.max(1, math.floor(room / self.dungeonColWidth))
    while #columns > fit do table.remove(columns) end
    self.dungeonColumns = columns
    for i, id in ipairs(columns) do
      local head = self.DungeonHeads[i]
      if not head then
        head = CreateFrame("Button", nil, self.Dungeons)
        head:SetSize(104, 16)
        head.Text = W.Text(head, "GameFontDisableSmall")
        head.Text:SetAllPoints()
        head.Text:SetJustifyH("CENTER")
        head.Text:SetWordWrap(false)
        head:SetScript("OnClick", function(b) view:ShowDetail(b.stat) end)
        head:SetScript("OnEnter", function(b)
          GameTooltip:SetOwner(b, "ANCHOR_TOP")
          GameTooltip:SetText(StatName(b.stat), 1, 1, 1, 1, true)
          GameTooltip:Show()
        end)
        head:SetScript("OnLeave", function() GameTooltip:Hide() end)
        self.DungeonHeads[i] = head
      end
      head.stat = id
      head:ClearAllPoints()
      head:SetPoint("TOPLEFT", self.Dungeons, "TOPLEFT", 8 + 158 + (i - 1) * 104, -28)
      head.Text:SetText(DungeonName(id))
      head:Show()
    end
    for i = #columns + 1, #self.DungeonHeads do self.DungeonHeads[i]:Hide() end
    local rows = {}
    for _, entry in ipairs(entries) do
      local sum = S.Value(entry.rec, "bosses", self.period, now, ns.GameStats.Date)
      if sum and sum > 0 then rows[#rows + 1] = { entry = entry, sum = sum } end
    end
    table.sort(rows, function(a, b)
      if a.sum ~= b.sum then return a.sum > b.sum end
      return a.entry.name < b.entry.name
    end)
    local items = {}
    for i, row in ipairs(rows) do items[i] = row.entry end
    self.DungeonRows:SetItems(items)
    self.DungeonEmpty:SetShown(#items == 0)
  end

  function view:RefreshHome(entries)
    local page = Page(self.page)
    self:RefreshTiles(entries, page)
    self:RefreshCards(entries, page)
    self.Gear:SetShown(page.gear == true)
    self.Income:SetShown(page.flows == true)
    self.Spending:SetShown(page.flows == true)
    self.FlowNote:SetShown(page.flows == true)
    self.Economy:SetShown(page.flows == true)
    self.Dungeons:SetShown(page.dungeons == true)
    self.Reputation:SetShown(page.reputation == true)
    self:Layout() -- the page box sits below the shown cards
    if page.gear then self:RefreshGear(entries) end
    if page.flows then
      FillFlow(self.Income, entries, self.period)
      FillFlow(self.Spending, entries, self.period)
      self:RefreshEconomy(entries)
    end
    if page.dungeons then self:RefreshDungeons(entries) end
    if page.reputation then self:RefreshReputation(entries) end
  end

  function view:RefreshDetail(entries)
    local id = self.detailStat
    -- tree
    local items = {}
    for _, category in ipairs(S.CATALOG) do
      items[#items + 1] = { text = CategoryName(category) }
      for _, stat in ipairs(category.stats) do
        items[#items + 1] = { text = category.bosses and DungeonName(stat) or StatName(stat), stat = stat }
      end
    end
    self.Tree:SetItems(items)
    -- ranking
    self.BoardTitle:SetText(StatName(id))
    local ranking = Ranking(entries, id, self.period)
    local total = S.Total(ranking)
    self.boardMax = ranking[1] and ranking[1].value or 0
    local myKey, myPlace, myValue = ns.Names.Key(ns.PlayerName()), nil, nil
    for i, row in ipairs(ranking) do
      if row.key == myKey then myPlace, myValue = i, row.value end
    end
    local tiles = self.BoardTiles
    tiles[1].Value:SetText(Format(id, total))
    tiles[1].Label:SetText(L.FAME_GUILD_TOTAL)
    tiles[2].Value:SetText(#ranking > 0 and Format(id, math.floor(total / #ranking + 0.5)) or "–")
    tiles[2].Label:SetText(L.FAME_AVERAGE:format(#ranking))
    tiles[3].Value:SetText(myPlace and ("#" .. myPlace) or "–")
    tiles[3].Label:SetText(myPlace and L.FAME_YOUR_PLACE:format(Format(id, myValue)) or L.FAME_NO_PLACE)
    self.Board:SetItems(ranking)
    local since
    if self.period ~= "all" then
      for _, row in ipairs(ranking) do
        local _, start = S.Value(row.rec, id, self.period, ns.Now(), ns.GameStats.Date)
        if start and (not since or start > since) then since = start end
      end
    end
    if self.period == "all" then
      self.BoardNote:SetText(L.FAME_NOTE_ALL)
    elseif self.period == "month" and self:LaunchMonth() then
      self.BoardNote:SetText(L.FAME_NOTE_LAUNCH)
    else
      self.BoardNote:SetText(L.FAME_NOTE_MONTH:format(since and ShortDate(since) or "–"))
    end
  end

  function view:Refresh()
    if self.period == "last" and self:LaunchMonth() then self.period = "all" end
    self.Period:SetValue(self.period)
    self.Pages:SetValue(self.page)
    local entries = ns.GameStats.Entries()
    local counts = { self = 0, seen = 0, relay = 0 }
    for _, entry in ipairs(entries) do
      local src = entry.rec.src or "relay"
      counts[src] = (counts[src] or 0) + 1
    end
    self.freshText = L.FAME_FRESH:format(#entries, #ns.Roster.Members(), counts.self + counts.relay, counts.seen)
    local inDetail = self.mode == "detail"
    self.Home:SetShown(not inDetail)
    self.Detail:SetShown(inDetail)
    self.AllButton:SetText(inDetail and L.FAME_BACK or L.FAME_ALL_STATS)
    self:Layout()
    if inDetail then
      self:RefreshDetail(entries)
    else
      self.Empty:SetShown(#entries == 0)
      self:RefreshHome(entries)
    end
  end

  function view:ShowDetail(id)
    self.mode, self.detailStat = "detail", id
    self:Refresh()
  end

  function view:ShowHome()
    self.mode = "home"
    self:Refresh()
  end

  function view:OnShow()
    ns.SafeCall(ns.GameStats.UpdateOwn)
  end

  return view
end

UI.RegisterTab("fame", 3.5, ns.L.TAB_FAME, Build)
