-- Hall of Fame tab: guild totals, title cards and dungeon progress from the members' statistics
-- (Core/Stats.lua, Game/Stats.lua), with a period switch (all time / this month / last month). A click
-- on a total, a card or a dungeon opens the detail view: every tracked statistic in a tree on the left,
-- the guild ranking of the chosen one on the right.
local _, ns = ...
local W = ns.Widgets
local UI = ns.UI
local S = ns.Stats

local function StatName(id)
  if id == "bosses" then return ns.L.FAME_BOSSES end
  local _, name = ns.Try(rawget(_G, "GetAchievementInfo"), id)
  return name or ("#" .. tostring(id))
end

local function CategoryName(id)
  local name = ns.Try(rawget(_G, "GetCategoryInfo"), id)
  return name or ("#" .. tostring(id))
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
    if gold > 0 then return Number(gold) .. "|cffffd100g|r" end
    if silver > 0 then return silver .. "|cffc7c7cfs|r" end
    return (value % 100) .. "|cffeda55fc|r"
  end
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

local function Build(panel)
  local L = ns.L
  local view = { period = ns.Settings().famePeriod or "all", mode = "home" }

  -- top bar -------------------------------------------------------------------------------------
  local title = W.Text(panel, "GameFontNormalLarge", L.TAB_FAME)
  title:SetPoint("TOPLEFT", 54, -4) -- clear of the portrait
  view.Period = W.Segmented(panel, {
    { value = "all", text = L.FAME_ALL }, { value = "month", text = L.FAME_MONTH }, { value = "last", text = L.FAME_LAST },
  }, function(value)
    view.period = value
    ns.Settings().famePeriod = value
    view:Refresh()
  end)
  view.Period:SetPoint("LEFT", title, "RIGHT", 14, 0)
  view.AllButton = W.Button(panel, L.FAME_ALL_STATS, function() view:ShowDetail(view.detailStat or 107) end, 140, { small = true })
  view.AllButton:SetPoint("TOPRIGHT", 0, -2)
  view.Back = W.Button(panel, L.FAME_BACK, function() view:ShowHome() end, 140, { small = true })
  view.Back:SetPoint("TOPRIGHT", 0, -2)
  view.Fresh = W.Text(panel, "GameFontDisableSmall")
  view.Fresh:SetPoint("RIGHT", view.AllButton, "LEFT", -10, 0)
  view.Fresh:SetJustifyH("RIGHT")

  -- home: totals, cards, dungeons ---------------------------------------------------------------
  local home = CreateFrame("Frame", nil, panel)
  home:SetPoint("TOPLEFT", 0, -30)
  home:SetPoint("BOTTOMRIGHT", 0, 0)
  view.Home = home

  view.Tiles = {}
  for i, id in ipairs(S.HEADLINE) do
    local tile = W.Box(home)
    tile:SetHeight(64)
    tile.Value = W.Text(tile, "GameFontNormalHuge")
    tile.Value:SetPoint("TOP", 0, -8)
    tile.Label = W.Text(tile, "GameFontDisableSmall", StatName(id))
    tile.Label:SetPoint("TOP", tile.Value, "BOTTOM", 0, -2)
    tile.Trend = W.Text(tile, "GameFontHighlightSmall")
    tile.Trend:SetPoint("TOP", tile.Label, "BOTTOM", 0, -2)
    tile:EnableMouse(true)
    tile:SetScript("OnMouseUp", function() view:ShowDetail(id) end)
    tile.id = id
    view.Tiles[i] = tile
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
    card:EnableMouse(true)
    card:SetScript("OnMouseUp", function(self) if self.stat then view:ShowDetail(self.stat) end end)
    view.Cards[i] = card
  end

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
    local tileWidth = (width - gap * (#self.Tiles - 1)) / #self.Tiles
    for i, tile in ipairs(self.Tiles) do
      tile:ClearAllPoints()
      tile:SetWidth(tileWidth)
      tile:SetPoint("TOPLEFT", home, "TOPLEFT", (i - 1) * (tileWidth + gap), 0)
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
    local cardRows = math.ceil(shownCards / 4)
    dungeons:ClearAllPoints()
    dungeons:SetPoint("TOPLEFT", home, "TOPLEFT", 0, -72 - cardRows * 56)
    dungeons:SetPoint("BOTTOMRIGHT", home, "BOTTOMRIGHT", 0, 0)
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

  function view:RefreshHome(entries)
    local now = ns.Now()
    for _, tile in ipairs(self.Tiles) do
      local ranking = Ranking(entries, tile.id, self.period)
      local total = S.Total(ranking)
      tile.Value:SetText(#ranking > 0 and Format(tile.id, total) or "–")
      local trend = ""
      if self.period == "month" then
        local last = S.Total(Ranking(entries, tile.id, "last"))
        if last > 0 then
          local pct = math.floor((total / last - 1) * 100 + 0.5)
          trend = (pct >= 0 and "|cff40e040+" or "|cffff5a4a-") .. math.abs(pct) .. " %|r " .. L.FAME_VS_LAST
        end
      elseif self.period == "all" then
        local month = S.Total(Ranking(entries, tile.id, "month"))
        if month > 0 then trend = "|cff40e040+" .. Format(tile.id, month) .. "|r " .. L.FAME_THIS_MONTH end
      end
      tile.Trend:SetText(trend)
    end

    local index = 0
    for _, fame in ipairs(S.TITLES) do
      if index < #self.Cards then
        local ranking = Ranking(entries, fame.stat, self.period)
        local top = ranking[1]
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

  function view:RefreshDetail(entries)
    local id = self.detailStat
    -- tree
    local items = {}
    for _, category in ipairs(S.CATALOG) do
      items[#items + 1] = { text = CategoryName(category.id) }
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
    self.BoardNote:SetText(self.period == "all" and L.FAME_NOTE_ALL
      or L.FAME_NOTE_MONTH:format(since and ShortDate(since) or "–"))
  end

  function view:Refresh()
    self.Period:SetValue(self.period)
    local entries = ns.GameStats.Entries()
    local counts = { self = 0, seen = 0, relay = 0 }
    for _, entry in ipairs(entries) do
      local src = entry.rec.src or "relay"
      counts[src] = (counts[src] or 0) + 1
    end
    self.Fresh:SetText(L.FAME_FRESH:format(#entries, #ns.Roster.Members(), counts.self + counts.relay, counts.seen))
    local inDetail = self.mode == "detail"
    self.Home:SetShown(not inDetail)
    self.Detail:SetShown(inDetail)
    self.AllButton:SetShown(not inDetail)
    self.Back:SetShown(inDetail)
    self.Fresh:ClearAllPoints()
    self.Fresh:SetPoint("RIGHT", inDetail and self.Back or self.AllButton, "LEFT", -10, 0)
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
