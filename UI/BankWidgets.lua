-- More boxes for the board of the Bank tab (UI/Board.lua, UI/TabBank.lua), all from the stored
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

  -- figures in a row: each can be switched off in the box's options ----------------------------------
  local tiles = CreateFrame("Frame", nil, parent)
  local TILES = { "gold", "paid", "taken", "repairs", "slots" }
  tiles.Tiles = {}
  for _, key in ipairs(TILES) do
    local tile = W.Box(tiles)
    tile.Value = W.Text(tile, "GameFontNormalHuge")
    tile.Value:SetPoint("CENTER", 0, 9)
    tile.Label = W.Text(tile, "GameFontDisableSmall")
    tile.Label:SetPoint("CENTER", 0, -16)
    tiles.Tiles[key] = tile
  end
  local function PlaceTiles()
    local shown = {}
    for _, key in ipairs(TILES) do
      local on = (tiles.opts or {})[key] ~= false
      tiles.Tiles[key]:SetShown(on)
      if on then shown[#shown + 1] = tiles.Tiles[key] end
    end
    local each = math.max(1, ((tiles:GetWidth() or 0) - (#shown - 1) * W.GAP) / math.max(1, #shown))
    for i, tile in ipairs(shown) do
      tile:ClearAllPoints()
      tile:SetPoint("TOPLEFT", (i - 1) * (each + W.GAP), 0)
      tile:SetPoint("BOTTOM", 0, 0)
      tile:SetWidth(each)
    end
  end
  tiles:SetScript("OnSizeChanged", PlaceTiles)
  function tiles:Fill(ctx)
    PlaceTiles()
    local none = GREY .. "?|r"
    local sums = ctx.known and B.Sums(ctx.bank, ctx.now, ctx.days)
    local used, room, tabs = 0, 0, 0
    if ctx.known then used, room, tabs = B.Slots(ctx.bank) end
    local values = {
      gold = { ctx.known and ctx.bank.money and H.Money(ctx.bank.money) or none, L.BANK_CHART },
      paid = { sums and (GREEN .. "+" .. H.Money(sums.paid) .. "|r") or none, L.BANK_TILE_PAID:format(ctx.days) },
      taken = { sums and (RED .. "-" .. H.Money(sums.taken) .. "|r") or none, L.BANK_TILE_TAKEN:format(ctx.days) },
      repairs = { sums and (RED .. "-" .. H.Money(sums.repairs) .. "|r") or none, L.BANK_TILE_REPAIRS:format(ctx.days) },
      slots = { ctx.known and (used .. GREY .. " / " .. room .. "|r") or none, L.BANK_TILE_SLOTS:format(tabs) },
    }
    for key, tile in pairs(self.Tiles) do
      tile.Value:SetText(values[key][1])
      tile.Label:SetText(values[key][2])
    end
  end
  widgets.tiles = tiles

  -- who gives, who takes: rank, items and "last" can be switched off in the box's options -----------
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
  local KEYS = { "name", "rankIndex", "paid", "taken", "net", "itemsIn", "itemsOut", "last" }
  local HEADS = { name = L.COL_NAME, rankIndex = L.COL_RANK, paid = L.BANK_COL_PAID, taken = L.BANK_COL_TAKEN,
    net = L.BANK_COL_NET, itemsIn = L.BANK_COL_IN, itemsOut = "-", last = L.BANK_COL_LAST }
  local NET_HALF = 44
  -- where each column stands: { side, x, width }; the right ones are counted in from the right edge
  local function Cols()
    local o = balance.opts or {}
    local c = { name = { "LEFT", 4, 140 } }
    if o.rank ~= false then c.rankIndex = { "LEFT", 146, 80 } end
    local r = -4
    local function Right(key, width)
      c[key] = { "RIGHT", r, width }
      r = r - width - 4
    end
    if o.last ~= false then Right("last", 70) end
    if o.items ~= false then
      Right("itemsOut", 40)
      Right("itemsIn", 68)
    end
    Right("net", 94)
    Right("taken", 80)
    Right("paid", 80)
    c.netX = c.net[2] - 47
    return c
  end
  local function Arrange(owner, cells, c)
    for _, key in ipairs(KEYS) do
      local cell, col = cells[key], c[key]
      if cell then
        cell:SetShown(col ~= nil)
        if col then
          cell:ClearAllPoints()
          cell:SetPoint(col[1], owner, col[1], col[2], 0)
          cell:SetWidth(col[3])
        end
      end
    end
  end
  local head = CreateFrame("Frame", nil, balance)
  head:SetPoint("TOPLEFT", 8, -28)
  head:SetPoint("RIGHT", -28, 0)
  head:SetHeight(16)
  balance.Heads = {}
  for _, key in ipairs(KEYS) do
    local button = CreateFrame("Button", nil, head)
    button:SetHeight(16)
    button.Text = W.Text(button, "GameFontDisableSmall", HEADS[key])
    button.Text:SetAllPoints()
    button.Text:SetJustifyH(key == "net" and "CENTER" or (key == "name" or key == "rankIndex") and "LEFT" or "RIGHT")
    button:SetScript("OnClick", function()
      if balance.sort == key then
        balance.desc = not balance.desc
      else
        balance.sort, balance.desc = key, key ~= "name" and key ~= "rankIndex"
      end
      view:Refresh()
    end)
    balance.Heads[key] = button
  end
  balance.List = W.ScrollList(balance, ROW, function(row)
    row.Picked = row:CreateTexture(nil, "BORDER")
    row.Picked:SetAllPoints()
    row.Picked:SetColorTexture(W.GOLD[1], W.GOLD[2], W.GOLD[3], 0.28)
    row.Cells = {}
    for _, key in ipairs(KEYS) do
      if key ~= "net" then
        local cell = W.Text(row, key == "rankIndex" and "GameFontDisableSmall" or "GameFontHighlightSmall")
        cell:SetJustifyH((key == "name" or key == "rankIndex") and "LEFT" or "RIGHT")
        cell:SetWordWrap(false)
        row.Cells[key] = cell
      end
    end
    row.Mid = row:CreateTexture(nil, "ARTWORK")
    row.Mid:SetColorTexture(0.43, 0.41, 0.35, 1)
    row.Mid:SetSize(1, ROW - 4)
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
    local c = balance.cols
    Arrange(row, row.Cells, c)
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
    row.Mid:ClearAllPoints()
    row.Mid:SetPoint("CENTER", row, "RIGHT", c.netX, 0)
    local peak = balance.peak or 0
    row.Bar:SetShown(m.net ~= 0 and peak > 0)
    row.Bar:ClearAllPoints()
    if m.net >= 0 then
      row.Bar:SetPoint("LEFT", row, "RIGHT", c.netX, 0)
      row.Bar:SetColorTexture(0.25, 0.88, 0.25, 0.8)
    else
      row.Bar:SetPoint("RIGHT", row, "RIGHT", c.netX, 0)
      row.Bar:SetColorTexture(1, 0.35, 0.29, 0.85)
    end
    row.Bar:SetWidth(math.max(1, NET_HALF * math.abs(m.net) / math.max(1, peak)))
  end)
  balance.List:SetPoint("TOPLEFT", 8, -46)
  balance.List:SetPoint("BOTTOMRIGHT", -28, 8)
  balance.Empty = W.Text(balance, "GameFontDisable", L.BANK_BALANCE_NONE)
  balance.Empty:SetPoint("TOPLEFT", 12, -52)
  function balance:Fill(ctx)
    self.cols = Cols()
    Arrange(head, self.Heads, self.cols)
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
