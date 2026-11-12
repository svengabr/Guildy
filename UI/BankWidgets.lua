-- More boxes for the board of the Bank tab (UI/BankBoard.lua, UI/TabBank.lua), all from the stored
-- logs: the figures in a row, what every member gave and took, one member's movements, the largest
-- withdrawals and the largest depositors. Each has Fill(ctx) with ctx = { bank, known, now, days }.
local _, ns = ...
local W = ns.Widgets
local UI = ns.UI
local B = ns.Bank

local ROW = 20
local GREEN, RED, GREY = "|cff40e040", "|cffff5a4a", "|cff999999"

-- view: the tab (view.pick / view.pickName: the member the detail box shows; view:Refresh())
function UI.BankWidgets(parent, view)
  local L = ns.L
  local H = UI.Bank
  local widgets = {}

  local function Rank(name)
    local m = ns.Roster.Find(name)
    return m and m.rank or "", m and m.rankIndex or 99
  end

  -- item with its icon, or the amount: into row.Icon and row.What
  local function What(row, e, money)
    row.Icon:SetShown(not money)
    row.What:ClearAllPoints()
    if money then
      row.What:SetPoint("LEFT", row.Icon, "LEFT", 0, 0)
      row.What:SetText(H.Money(e.c))
    else
      row.What:SetPoint("LEFT", row.Icon, "RIGHT", 6, 0)
      row.Icon:SetTexture(H.ItemIcon(e.id))
      row.What:SetText(H.ItemText(e) .. "  |cffffd100x " .. (e.n or 1) .. "|r")
    end
    row.What:SetPoint("RIGHT", row.When, "LEFT", -6, 0)
  end

  local function Sign(e, money)
    if (money and B.PLUS[e.k]) or (not money and e.k == "deposit") then return GREEN .. "+|r " end
    if (money and B.MINUS[e.k]) or (not money and e.k == "withdraw") then return RED .. "-|r " end
    return GREY .. ">|r "
  end

  -- figures in a row -------------------------------------------------------------------------------
  local tiles = CreateFrame("Frame", nil, parent)
  tiles.Tiles = {}
  for i = 1, 5 do
    local tile = W.Box(tiles)
    tile.Value = W.Text(tile, "GameFontNormalHuge")
    tile.Value:SetPoint("CENTER", 0, 9)
    tile.Label = W.Text(tile, "GameFontDisableSmall")
    tile.Label:SetPoint("CENTER", 0, -16)
    tiles.Tiles[i] = tile
  end
  local function PlaceTiles()
    local each = math.max(1, ((tiles:GetWidth() or 0) - 4 * W.GAP) / 5)
    for i, tile in ipairs(tiles.Tiles) do
      tile:ClearAllPoints()
      tile:SetPoint("TOPLEFT", (i - 1) * (each + W.GAP), 0)
      tile:SetPoint("BOTTOM", 0, 0)
      tile:SetWidth(each)
    end
  end
  tiles:SetScript("OnSizeChanged", PlaceTiles)
  PlaceTiles()
  function tiles:Fill(ctx)
    local none = GREY .. "?|r"
    local sums = ctx.known and B.Sums(ctx.bank, ctx.now, ctx.days)
    local used, room, tabs = 0, 0, 0
    if ctx.known then used, room, tabs = B.Slots(ctx.bank) end
    local values = {
      { ctx.known and ctx.bank.money and H.Money(ctx.bank.money) or none, L.BANK_CHART },
      { sums and (GREEN .. "+" .. H.Money(sums.paid) .. "|r") or none, L.BANK_TILE_PAID:format(ctx.days) },
      { sums and (RED .. "-" .. H.Money(sums.taken) .. "|r") or none, L.BANK_TILE_TAKEN:format(ctx.days) },
      { sums and (RED .. "-" .. H.Money(sums.repairs) .. "|r") or none, L.BANK_TILE_REPAIRS:format(ctx.days) },
      { ctx.known and (used .. GREY .. " / " .. room .. "|r") or none, L.BANK_TILE_SLOTS:format(tabs) },
    }
    for i, tile in ipairs(self.Tiles) do
      tile.Value:SetText(values[i][1])
      tile.Label:SetText(values[i][2])
    end
  end
  widgets.tiles = tiles

  -- who gives, who takes ---------------------------------------------------------------------------
  local balance = W.Box(parent)
  local balanceTitle = W.Text(balance, "GameFontNormal", L.BANK_BALANCE)
  balanceTitle:SetPoint("TOPLEFT", 10, -8)
  balance.Count = W.Text(balance, "GameFontDisableSmall")
  balance.Count:SetPoint("TOPRIGHT", -10, -10)
  local balanceHint = W.Text(balance, "GameFontDisableSmall", L.BANK_BALANCE_HINT)
  balanceHint:SetPoint("LEFT", balanceTitle, "RIGHT", 8, 0)
  balanceHint:SetPoint("RIGHT", balance.Count, "LEFT", -8, 0)
  balanceHint:SetWordWrap(false)
  balance.sort, balance.desc = "net", true
  -- key, heading, side, x, width
  local COLS = {
    { "name", L.COL_NAME, "LEFT", 4, 140 }, { "rankIndex", L.COL_RANK, "LEFT", 146, 80 },
    { "paid", L.BANK_COL_PAID, "RIGHT", -362, 84 }, { "taken", L.BANK_COL_TAKEN, "RIGHT", -274, 84 },
    { "net", L.BANK_COL_NET, "RIGHT", -176, 94 }, { "itemsIn", L.BANK_COL_IN, "RIGHT", -122, 50 },
    { "itemsOut", "-", "RIGHT", -78, 40 }, { "last", L.BANK_COL_LAST, "RIGHT", -4, 70 },
  }
  local NET_X, NET_HALF = -223, 44
  local function Place(region, parentFrame, col)
    region:SetPoint(col[3], parentFrame, col[3], col[4], 0)
    region:SetWidth(col[5])
  end
  local head = CreateFrame("Frame", nil, balance)
  head:SetPoint("TOPLEFT", 8, -28)
  head:SetPoint("RIGHT", -28, 0)
  head:SetHeight(16)
  balance.Heads = {}
  for i, col in ipairs(COLS) do
    local button = CreateFrame("Button", nil, head)
    button:SetHeight(16)
    Place(button, head, col)
    button.Text = W.Text(button, "GameFontDisableSmall", col[2])
    button.Text:SetAllPoints()
    button.Text:SetJustifyH(col[1] == "net" and "CENTER" or col[3])
    button:SetScript("OnClick", function()
      if balance.sort == col[1] then
        balance.desc = not balance.desc
      else
        balance.sort, balance.desc = col[1], col[1] ~= "name" and col[1] ~= "rankIndex"
      end
      view:Refresh()
    end)
    balance.Heads[i] = button
  end
  balance.List = W.ScrollList(balance, ROW, function(row)
    row.Picked = row:CreateTexture(nil, "BORDER")
    row.Picked:SetAllPoints()
    row.Picked:SetColorTexture(W.GOLD[1], W.GOLD[2], W.GOLD[3], 0.28)
    row.Cells = {}
    for _, col in ipairs(COLS) do
      if col[1] ~= "net" then
        local cell = W.Text(row, col[1] == "rankIndex" and "GameFontDisableSmall" or "GameFontHighlightSmall")
        Place(cell, row, col)
        cell:SetJustifyH(col[3])
        cell:SetWordWrap(false)
        row.Cells[col[1]] = cell
      end
    end
    row.Mid = row:CreateTexture(nil, "ARTWORK")
    row.Mid:SetColorTexture(0.43, 0.41, 0.35, 1)
    row.Mid:SetSize(1, ROW - 4)
    row.Mid:SetPoint("CENTER", row, "RIGHT", NET_X, 0)
    row.Bar = row:CreateTexture(nil, "ARTWORK")
    row.Bar:SetHeight(ROW - 10)
    row.Click = CreateFrame("Button", nil, row)
    row.Click:SetAllPoints()
    row.Click:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    row.Click:SetScript("OnClick", function()
      local m = row.member
      if not m then return end
      view.pick, view.pickName = m.key, m.name
      view:Refresh()
    end)
  end, function(row, m)
    row.member = m
    row.Picked:SetShown(view.pick == m.key)
    local none = GREY .. "-|r"
    row.Cells.name:SetText(H.Who(m.name))
    row.Cells.rankIndex:SetText(m.rank)
    row.Cells.paid:SetText(m.paid > 0 and H.Money(m.paid) or none)
    row.Cells.taken:SetText(m.taken > 0 and H.Money(m.taken) or none)
    row.Cells.itemsIn:SetText(m.itemsIn > 0 and (GREEN .. "+" .. m.itemsIn .. "|r") or none)
    row.Cells.itemsOut:SetText(m.itemsOut > 0 and (RED .. "-" .. m.itemsOut .. "|r") or none)
    row.Cells.last:SetText(GREY .. H.Ago(m.last) .. "|r")
    local peak = balance.peak or 0
    row.Bar:SetShown(m.net ~= 0 and peak > 0)
    row.Bar:ClearAllPoints()
    if m.net >= 0 then
      row.Bar:SetPoint("LEFT", row, "RIGHT", NET_X, 0)
      row.Bar:SetColorTexture(0.25, 0.88, 0.25, 0.8)
    else
      row.Bar:SetPoint("RIGHT", row, "RIGHT", NET_X, 0)
      row.Bar:SetColorTexture(1, 0.35, 0.29, 0.85)
    end
    row.Bar:SetWidth(math.max(1, NET_HALF * math.abs(m.net) / math.max(1, peak)))
  end)
  balance.List:SetPoint("TOPLEFT", 8, -46)
  balance.List:SetPoint("BOTTOMRIGHT", -28, 8)
  balance.Empty = W.Text(balance, "GameFontDisable", L.BANK_BALANCE_NONE)
  balance.Empty:SetPoint("TOPLEFT", 12, -52)
  function balance:Fill(ctx)
    local list = ctx.known and B.Balance(ctx.bank, ctx.now, ctx.days) or {}
    local peak = 0
    for _, m in ipairs(list) do
      m.rank, m.rankIndex = Rank(m.name)
      peak = math.max(peak, math.abs(m.net))
    end
    self.peak = peak
    local key, desc = self.sort, self.desc
    table.sort(list, function(x, y)
      local p, q = x[key], y[key]
      if p == q then return x.name < y.name end
      if desc then return p > q end
      return p < q
    end)
    self.List:SetItems(list)
    self.Count:SetText(L.COMMUNITIES_MEMBERS:format(#list))
    self.Empty:SetShown(#list == 0)
  end
  widgets.balance = balance

  -- one member's movements --------------------------------------------------------------------------
  local detail = W.Box(parent)
  detail.Name = W.Text(detail, "GameFontNormal", L.BANK_DETAIL)
  detail.Name:SetPoint("TOPLEFT", 10, -8)
  detail.Count = W.Text(detail, "GameFontDisableSmall")
  detail.Count:SetPoint("TOPRIGHT", -10, -10)
  detail.Rank = W.Text(detail, "GameFontDisableSmall")
  detail.Rank:SetPoint("LEFT", detail.Name, "RIGHT", 8, 0)
  detail.Hint = W.Text(detail, "GameFontDisable", L.BANK_DETAIL_HINT)
  detail.Hint:SetPoint("TOPLEFT", 12, -34)
  detail.Hint:SetPoint("RIGHT", -12, 0)
  detail.Body = CreateFrame("Frame", nil, detail)
  detail.Body:SetPoint("TOPLEFT", 0, -28)
  detail.Body:SetPoint("BOTTOMRIGHT", 0, 0)
  detail.Figures = {}
  for i, label in ipairs({ L.BANK_COL_PAID, L.BANK_COL_TAKEN, L.BANK_DETAIL_REPAIRS }) do
    local value = W.Text(detail.Body, "GameFontNormal")
    value:SetPoint("TOPLEFT", detail.Body, "TOPLEFT", 12 + (i - 1) * 120, -4)
    local text = W.Text(detail.Body, "GameFontDisableSmall", label)
    text:SetPoint("TOPLEFT", value, "BOTTOMLEFT", 0, -2)
    detail.Figures[i] = value
  end
  detail.List = W.ScrollList(detail.Body, ROW, function(row)
    row.When = W.Text(row, "GameFontDisableSmall")
    row.When:SetPoint("RIGHT", -4, 0)
    row.When:SetJustifyH("RIGHT")
    row.Action = W.Text(row, "GameFontHighlightSmall")
    row.Action:SetPoint("LEFT", 4, 0)
    row.Action:SetWidth(96)
    row.Action:SetWordWrap(false)
    row.Icon = row:CreateTexture(nil, "ARTWORK")
    row.Icon:SetSize(ROW - 4, ROW - 4)
    row.Icon:SetPoint("LEFT", 104, 0)
    row.Icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    row.What = W.Text(row, "GameFontHighlightSmall")
    row.What:SetWordWrap(false)
  end, function(row, item)
    local e, money = item.e, item.log == B.MONEY
    row.When:SetText(H.Ago(e.ts))
    row.Action:SetText(Sign(e, money) .. H.Verb(e.k))
    What(row, e, money)
  end)
  detail.List:SetPoint("TOPLEFT", 8, -44)
  detail.List:SetPoint("BOTTOMRIGHT", -28, 8)
  function detail:Fill(ctx)
    local picked = ctx.known and view.pick ~= nil
    self.Hint:SetShown(not picked)
    self.Body:SetShown(picked)
    self.Rank:SetShown(picked)
    self.Count:SetShown(picked)
    if not picked then
      self.Name:SetText(L.BANK_DETAIL)
      return
    end
    local since = ctx.now - ctx.days * 86400
    local rows = {}
    for _, row in ipairs(B.Ledger(ctx.bank, { who = view.pick })) do
      if row.e.ts >= since then rows[#rows + 1] = row end
    end
    local sums = { paid = 0, taken = 0, repairs = 0 }
    for _, m in ipairs(B.Balance(ctx.bank, ctx.now, ctx.days)) do
      if m.key == view.pick then sums = m end
    end
    self.Name:SetText(H.Who(view.pickName))
    self.Rank:SetText((Rank(view.pickName)))
    self.Count:SetText(L.BANK_DETAIL_COUNT:format(#rows))
    self.Figures[1]:SetText(GREEN .. "+" .. H.Money(sums.paid) .. "|r")
    self.Figures[2]:SetText(RED .. "-" .. H.Money(sums.taken) .. "|r")
    self.Figures[3]:SetText(H.Money(sums.repairs))
    self.List:SetItems(rows)
  end
  widgets.detail = detail

  -- the largest withdrawals -------------------------------------------------------------------------
  local largest = W.Box(parent)
  local largestTitle = W.Text(largest, "GameFontNormal", L.BANK_LARGEST)
  largestTitle:SetPoint("TOPLEFT", 10, -8)
  largest.Hint = W.Text(largest, "GameFontDisableSmall")
  largest.Hint:SetPoint("LEFT", largestTitle, "RIGHT", 8, 0)
  largest.List = W.ScrollList(largest, ROW, function(row)
    row.When = W.Text(row, "GameFontDisableSmall")
    row.When:SetPoint("RIGHT", -4, 0)
    row.When:SetJustifyH("RIGHT")
    row.Who = W.Text(row, "GameFontHighlightSmall")
    row.Who:SetPoint("LEFT", 4, 0)
    row.Who:SetWidth(130)
    row.Who:SetWordWrap(false)
    row.Icon = row:CreateTexture(nil, "ARTWORK")
    row.Icon:SetSize(ROW - 4, ROW - 4)
    row.Icon:SetPoint("LEFT", 138, 0)
    row.Icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    row.What = W.Text(row, "GameFontHighlightSmall")
    row.What:SetWordWrap(false)
  end, function(row, item)
    row.Who:SetText(H.Who(item.e.w))
    row.When:SetText(H.Ago(item.e.ts))
    What(row, item.e, item.log == B.MONEY)
  end)
  largest.List:SetPoint("TOPLEFT", 8, -30)
  largest.List:SetPoint("BOTTOMRIGHT", -28, 8)
  largest.Empty = W.Text(largest, "GameFontDisable", L.BANK_LARGEST_NONE)
  largest.Empty:SetPoint("TOPLEFT", 12, -34)
  function largest:Fill(ctx)
    local rows = ctx.known and B.Largest(ctx.bank, ctx.now, ctx.days, 20) or {}
    self.Hint:SetText(L.BANK_DAYS:format(ctx.days))
    self.List:SetItems(rows)
    self.Empty:SetShown(#rows == 0)
  end
  widgets.largest = largest

  -- the largest depositors --------------------------------------------------------------------------
  local givers = W.Box(parent)
  local giversTitle = W.Text(givers, "GameFontNormal", L.BANK_GIVERS)
  giversTitle:SetPoint("TOPLEFT", 10, -8)
  givers.Hint = W.Text(givers, "GameFontDisableSmall")
  givers.Hint:SetPoint("LEFT", giversTitle, "RIGHT", 8, 0)
  givers.List = W.ScrollList(givers, ROW, function(row)
    row.Who = W.Text(row, "GameFontHighlightSmall")
    row.Who:SetPoint("LEFT", 4, 0)
    row.Who:SetWidth(120)
    row.Who:SetWordWrap(false)
    row.Amount = W.Text(row, "GameFontNormalSmall")
    row.Amount:SetPoint("RIGHT", -4, 0)
    row.Amount:SetWidth(76)
    row.Amount:SetJustifyH("RIGHT")
    row.Track = row:CreateTexture(nil, "BACKGROUND")
    row.Track:SetPoint("LEFT", 130, 0)
    row.Track:SetPoint("RIGHT", -86, 0)
    row.Track:SetHeight(8)
    row.Track:SetColorTexture(0.13, 0.11, 0.08, 1)
    row.Bar = row:CreateTexture(nil, "ARTWORK")
    row.Bar:SetPoint("LEFT", row.Track, "LEFT", 0, 0)
    row.Bar:SetHeight(8)
    row.Bar:SetColorTexture(0.8, 0.66, 0.33, 1)
  end, function(row, m)
    row.Who:SetText(H.Who(m.name))
    row.Amount:SetText(H.Money(m.paid))
    row.Bar:SetWidth(math.max(1, (row.Track:GetWidth() or 60) * m.paid / math.max(1, givers.peak or 1)))
  end)
  givers.List:SetPoint("TOPLEFT", 8, -30)
  givers.List:SetPoint("BOTTOMRIGHT", -28, 8)
  givers.Empty = W.Text(givers, "GameFontDisable", L.BANK_GIVERS_NONE)
  givers.Empty:SetPoint("TOPLEFT", 12, -34)
  function givers:Fill(ctx)
    local list = {}
    for _, m in ipairs(ctx.known and B.Balance(ctx.bank, ctx.now, ctx.days) or {}) do
      if m.paid > 0 then list[#list + 1] = m end
    end
    table.sort(list, function(x, y)
      if x.paid ~= y.paid then return x.paid > y.paid end
      return x.name < y.name
    end)
    self.peak = list[1] and list[1].paid or 1
    self.Hint:SetText(L.BANK_DAYS:format(ctx.days))
    self.List:SetItems(list)
    self.Empty:SetShown(#list == 0)
  end
  widgets.givers = givers

  return widgets
end
