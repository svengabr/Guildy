-- Bank tab: what Guildy users read of the guild bank at a banker (Game/Bank.lua, Core/Bank.lua), the
-- same for everyone in the guild. Its boxes stand on a board (UI/Board.lua): the gold with the
-- sums of the chosen days, the tabs, what the player may still take today, the gold over time, the
-- ledger (every movement of gold and items, newest first), and more from UI/BankWidgets.lua. Which
-- boxes show, where, how large and with which columns is the player's choice, made right on the tab
-- ("Customize").
local _, ns = ...
local W = ns.Widgets
local UI = ns.UI
local B = ns.Bank

local MAX_DAYS = 90
local ROW = 20
local TAB_ROW = 27
local MAX_MARKS = 4
local GREEN, RED, GREY, ORANGE = "|cff40e040", "|cffff5a4a", "|cff999999", "|cffd67a32"
local COIN = {
  gold = "|TInterface\\MoneyFrame\\UI-GoldIcon:12:12:2:0|t",
  silver = "|TInterface\\MoneyFrame\\UI-SilverIcon:12:12:2:0|t",
  copper = "|TInterface\\MoneyFrame\\UI-CopperIcon:12:12:2:0|t",
}
local QUESTION = "Interface\\Icons\\INV_Misc_QuestionMark"

-- What the player chose for the tab ----------------------------------------------------------------------
-- settings.bank.layout: the boxes on the board, nil: the first of these presets
UI.BANK_PRESETS = {
  ledger = { { k = "total", x = 0, y = 0, w = 3, h = 4 }, { k = "tabs", x = 0, y = 4, w = 3, h = 4 },
    { k = "access", x = 0, y = 8, w = 3, h = 4 }, { k = "chart", x = 3, y = 0, w = 9, h = 4 },
    { k = "ledger", x = 3, y = 4, w = 9, h = 8 } },
  members = { { k = "balance", x = 0, y = 0, w = 8, h = 12 }, { k = "detail", x = 8, y = 0, w = 4, h = 7 },
    { k = "largest", x = 8, y = 7, w = 4, h = 5 } },
  overview = { { k = "tiles", x = 0, y = 0, w = 12, h = 2 }, { k = "chart", x = 0, y = 2, w = 8, h = 5 },
    { k = "givers", x = 8, y = 2, w = 4, h = 5 }, { k = "ledger", x = 0, y = 7, w = 8, h = 5 },
    { k = "tabs", x = 8, y = 7, w = 4, h = 5 } },
}
UI.BANK_PRESET_ORDER = { "ledger", "members", "overview" }
UI.BANK_DAYS = { 7, 30, 90 }                           -- settings.bank.days, nil: 30
UI.BANK_SHARES = { 0.1, 0.25, 0.5 }                    -- settings.bank.share, nil: 0.25

function UI.BankSetting(key)
  local bank = ns.Settings().bank
  if type(bank) ~= "table" then return nil end
  return bank[key]
end

-- value nil: back to what Guildy ships (settings only hold what differs)
function UI.SetBankSetting(key, value)
  local settings = ns.Settings()
  if type(settings.bank) ~= "table" then settings.bank = {} end
  settings.bank[key] = value
  if next(settings.bank) == nil then settings.bank = nil end
end

-- The days the tab looks back: the chart, the sums and the lists per member
function UI.BankDays()
  local days = UI.bankShot and UI.bankShot.days or UI.BankSetting("days")
  return (type(days) == "number" and days >= 1 and days <= MAX_DAYS) and days or 30
end

local function Number(n)
  local big = rawget(_G, "BreakUpLargeNumbers")
  return big and big(n) or tostring(n)
end

-- "1,284 g" with the game's coins; silver only below 100 gold, copper only below a silver
local function Money(copper, sign)
  copper = math.floor(math.abs(copper or 0))
  local gold, silver = math.floor(copper / 10000), math.floor(copper / 100) % 100
  local text
  if gold > 0 then
    text = Number(gold) .. COIN.gold
    if gold < 100 and silver > 0 then text = text .. " " .. silver .. COIN.silver end
  elseif silver > 0 then
    text = silver .. COIN.silver
  else
    text = (copper % 100) .. COIN.copper
  end
  return (sign or "") .. text
end
UI.BankMoney = Money

local function Ago(ts)
  return ns.Roster.LastOnlineText({ online = false, daysOffline = math.max(0, ns.Now() - ts) / 86400 })
end

local function Who(name)
  if not name then return GREY .. ns.L.BANK_GUILD .. "|r" end
  local m = ns.Roster.Find(name)
  return m and W.ClassName(m.name, m.classFile) or ns.Anon.Name(name)
end

local function Verb(kind)
  local key = "BANK_K_" .. kind:upper()
  local text = ns.L[key]
  return text ~= key and text or kind
end

-- the item as the game shows it (coloured link) once it knows it, else the name read with the entry
local function ItemText(e)
  local info = rawget(_G, "GetItemInfo") or (C_Item and C_Item.GetItemInfo)
  local _, link = ns.Try(info, e.i or e.id)
  if type(link) == "string" then return link end
  return e.nm and ("[" .. e.nm .. "]") or (e.i or "?")
end

local function ItemIcon(id)
  local getIcon = (C_Item and C_Item.GetItemIconByID) or rawget(_G, "GetItemIcon")
  return (id and ns.Try(getIcon, id)) or QUESTION
end

local function TabName(bank, index)
  local tab = index and bank and bank.tabs[index]
  return (tab and tab.name) or (index and ns.L.BANK_TAB_N:format(index)) or ""
end

-- shared with the other boxes (UI/BankWidgets.lua)
UI.Bank = { Money = Money, Who = Who, Ago = Ago, Verb = Verb, ItemText = ItemText, ItemIcon = ItemIcon }

-- The gold over the chosen days: a stepped line of plain textures, the days' deposits and withdrawals as
-- bars, and marks on the movements that stand out (Core/Bank.lua: Bank.Marks)
local function Chart(parent)
  local L = ns.L
  local box = W.Box(parent)
  local title = W.Text(box, "GameFontNormal", L.BANK_CHART)
  title:SetPoint("TOPLEFT", 10, -8)
  local hint = W.Text(box, "GameFontDisableSmall")
  hint:SetPoint("LEFT", title, "RIGHT", 8, 0)
  local plot = CreateFrame("Frame", nil, box)
  plot:SetPoint("TOPLEFT", 64, -34)
  plot:SetPoint("BOTTOMRIGHT", -96, 24)
  box.Plot = plot
  box.Empty = W.Text(box, "GameFontDisable", L.BANK_CHART_EMPTY)
  box.Empty:SetPoint("CENTER", plot, "CENTER", 0, 0)
  box.Now = W.Text(box, "GameFontNormalSmall")
  box.Today = W.Text(box, "GameFontDisableSmall", L.BANK_TODAY)
  box.Today:SetPoint("TOPLEFT", box.Now, "BOTTOMLEFT", 0, -2)
  box.Grid, box.Scale, box.Axis, box.Bars, box.Lines, box.Marks = {}, {}, {}, {}, {}, {}
  for i = 1, 3 do
    local line = plot:CreateTexture(nil, "BACKGROUND")
    line:SetColorTexture(1, 1, 1, 0.06)
    line:SetHeight(1)
    box.Grid[i] = line
    local label = W.Text(box, "GameFontDisableSmall")
    label:SetJustifyH("RIGHT")
    box.Scale[i] = label
  end
  -- four labels along the days: the start, two between, today
  for i, part in ipairs({ 1, 2 / 3, 1 / 3, 0 }) do
    local label = W.Text(box, part == 0 and "GameFontHighlightSmall" or "GameFontDisableSmall", part == 0 and L.BANK_TODAY or "")
    label:SetJustifyH("CENTER")
    label.part = part
    box.Axis[i] = label
  end
  for day = 0, MAX_DAYS - 1 do
    local plus, minus = plot:CreateTexture(nil, "BORDER"), plot:CreateTexture(nil, "ARTWORK")
    plus:SetColorTexture(0.25, 0.88, 0.25, 0.32)
    minus:SetColorTexture(1, 0.35, 0.29, 0.5)
    box.Bars[day] = { plus = plus, minus = minus }
  end

  local used = 0
  local function Line(x, y, w, h)
    used = used + 1
    local line = box.Lines[used]
    if not line then
      line = plot:CreateTexture(nil, "OVERLAY")
      line:SetColorTexture(1, 0.82, 0, 1)
      box.Lines[used] = line
    end
    line:ClearAllPoints()
    line:SetPoint("BOTTOMLEFT", plot, "BOTTOMLEFT", x, y)
    line:SetSize(math.max(1, w), math.max(1, h))
    line:Show()
  end

  -- A mark: who and how much ("Name +10 g") above the step, with a thin stem down to it. The rest
  -- on hover; a click lists that member's movements in the ledger (box.OnPick, set by the tab).
  local function Mark(index)
    local mark = box.Marks[index]
    if mark then return mark end
    mark = CreateFrame("Button", nil, plot)
    mark.Stem = plot:CreateTexture(nil, "ARTWORK")
    mark.Stem:SetColorTexture(1, 0.82, 0, 0.45)
    mark.Stem:SetWidth(1)
    mark.Text = W.Text(mark, "GameFontHighlightSmall")
    mark.Text:SetPoint("CENTER")
    mark:SetScript("OnEnter", function(self)
      local step = self.step
      if not step then return end
      GameTooltip:SetOwner(self, "ANCHOR_TOP")
      GameTooltip:SetText(step.k == "buyTab" and L.BANK_MARK_TAB:format(Who(step.w)) or Who(step.w))
      GameTooltip:AddDoubleLine(Verb(step.k), Money(math.abs(step.c - step.b)), 1, 1, 1, 1, 1, 1)
      GameTooltip:AddDoubleLine(L.BANK_COL_AFTER, Money(step.c), 0.6, 0.6, 0.6, 1, 0.82, 0)
      GameTooltip:AddLine(Ago(step.ts), 0.6, 0.6, 0.6)
      if step.w then GameTooltip:AddLine(L.BANK_MARK_CLICK, 0.6, 0.6, 0.6) end
      GameTooltip:Show()
    end)
    mark:SetScript("OnLeave", function() GameTooltip:Hide() end)
    mark:SetScript("OnClick", function(self)
      if box.OnPick and self.step then box.OnPick(self.step) end
    end)
    box.Marks[index] = mark
    return mark
  end

  function box:Draw(bank)
    self.bank = bank
    local width, height = plot:GetWidth() or 0, plot:GetHeight() or 0
    local now = ns.Now()
    local days = UI.BankDays()
    hint:SetText(L.BANK_CHART_HINT:format(days))
    local chart = bank and B.Chart(bank, now, days)
    used = 0
    local marked = 0
    local known = chart ~= nil and width > 20 and height > 20
    self.Empty:SetShown(chart == nil)
    self.Now:SetShown(known)
    self.Today:SetShown(known and bank.money ~= nil and (bank.money - (chart.low or 0)) > 0)
    for _, label in ipairs(self.Scale) do label:SetShown(known) end
    for _, line in ipairs(self.Grid) do line:SetShown(known) end
    for _, bar in pairs(self.Bars) do
      bar.plus:Hide()
      bar.minus:Hide()
    end
    if known then
      local since, span = now - days * 86400, days * 86400
      local pad = math.max((chart.high - chart.low) * 0.15, chart.high * 0.02, 10000)
      local low, high = math.max(0, chart.low - pad), chart.high + pad
      local function X(ts) return math.max(0, math.min(width, (ts - since) / span * width)) end
      -- (never outside the plot: a log that does not add up to the gold read would draw below it)
      local function Y(copper) return math.max(0, math.min(height, (copper - low) / (high - low) * height)) end
      for i, label in ipairs(self.Scale) do
        local value = low + (high - low) * (i - 1) / 2
        local y = Y(value)
        self.Grid[i]:ClearAllPoints()
        self.Grid[i]:SetPoint("BOTTOMLEFT", plot, "BOTTOMLEFT", 0, y)
        self.Grid[i]:SetWidth(width)
        label:ClearAllPoints()
        label:SetPoint("RIGHT", plot, "BOTTOMLEFT", -6, y)
        label:SetText(Number(math.floor(value / 10000)))
      end
      -- the days' sums, scaled to the largest of them
      local most = 0
      for _, day in pairs(chart.days) do most = math.max(most, day.plus, day.minus) end
      local dayWidth = width / days
      for day, sums in pairs(chart.days) do
        local bar = self.Bars[day]
        if bar and most > 0 and (self.opts or {}).bars ~= false then
          local x = width - (day + 1) * dayWidth
          if sums.plus > 0 then
            bar.plus:ClearAllPoints()
            bar.plus:SetPoint("BOTTOMLEFT", plot, "BOTTOMLEFT", x + 1, 0)
            bar.plus:SetSize(math.max(1, dayWidth - 2), math.max(1, sums.plus / most * height * 0.4))
            bar.plus:Show()
          end
          if sums.minus > 0 then
            bar.minus:ClearAllPoints()
            bar.minus:SetPoint("BOTTOMLEFT", plot, "BOTTOMLEFT", x + 1, 0)
            bar.minus:SetSize(math.max(1, dayWidth / 2 - 1), math.max(1, sums.minus / most * height * 0.4))
            bar.minus:Show()
          end
        end
      end
      -- the line: flat until a step, then straight up or down
      local steps = chart.steps
      local first = math.max(1, #steps - 199)
      local x, value
      if first > 1 then
        x, value = X(steps[first - 1].ts), steps[first - 1].c
      elseif chart.start then
        x, value = 0, chart.start
      elseif steps[1] then
        x, value = X(steps[1].ts), steps[1].c
        first = 2
      else
        x, value = X(bank.at or now), bank.money
      end
      for index = first, #steps do
        local step = steps[index]
        local nextX = X(step.ts)
        Line(x, Y(value) - 1, nextX - x, 2)
        Line(nextX - 1, math.min(Y(value), Y(step.c)) - 1, 2, math.abs(Y(step.c) - Y(value)) + 2)
        x, value = nextX, step.c
      end
      Line(x, Y(value) - 1, width - x, 2)
      self.Now:ClearAllPoints()
      self.Now:SetPoint("LEFT", plot, "BOTTOMRIGHT", 8, Y(bank.money) + 5)
      self.Now:SetText(Money(bank.money))
      -- the movements that stand out: above the line, a row higher where two stand close together
      if (self.opts or {}).marks ~= false then
        -- "Name +10 g" above its step with a thin stem down to it, a row higher where two steps
        -- stand close together. Where the plot ends above: beside the step, left of its rise.
        local lastX, row
        for _, step in ipairs(B.Marks(steps, UI.BankSetting("share") or 0.25, MAX_MARKS)) do
          marked = marked + 1
          local mark = Mark(marked)
          mark.step = step
          local plus = step.c > step.b
          local text = step.k == "buyTab" and L.BANK_MARK_TAB:format(Who(step.w))
            or (Who(step.w) .. " " .. (plus and GREEN .. "+|r" or RED .. "-|r") .. Money(math.abs(step.c - step.b)))
          mark.Text:SetText(text)
          local textWidth = math.max(40, (mark.Text:GetStringWidth() or 100) + 8)
          local sx = X(step.ts)
          row = (lastX and sx - lastX < 150) and ((row or 0) + 1) % 3 or 0
          lastX = sx
          local top, bottom = math.max(Y(step.c), Y(step.b)), math.min(Y(step.c), Y(step.b))
          local y = top + 8 + row * 14
          local left = math.max(0, math.min(width - textWidth, sx - textWidth / 2))
          local stem = true
          if y + 12 > height then
            stem = false
            if top - bottom >= 22 and sx - 6 - textWidth >= 0 then
              left, y = sx - 6 - textWidth, top - 17 -- in the corner the rise leaves free
            else
              y = math.max(2, bottom - 22 - row * 14)
            end
          end
          mark:ClearAllPoints()
          mark:SetPoint("BOTTOMLEFT", plot, "BOTTOMLEFT", left, y)
          mark:SetSize(textWidth, 14)
          mark.Stem:ClearAllPoints()
          mark.Stem:SetPoint("BOTTOMLEFT", plot, "BOTTOMLEFT", sx, top + 1)
          mark.Stem:SetHeight(math.max(1, y - top - 1))
          mark.Stem:SetShown(stem)
          mark:Show()
        end
      end
    end
    for index = used + 1, #self.Lines do self.Lines[index]:Hide() end
    for index = marked + 1, #self.Marks do
      self.Marks[index]:Hide()
      self.Marks[index].Stem:Hide()
    end
    for _, label in ipairs(self.Axis) do
      label:SetShown(chart ~= nil)
      label:ClearAllPoints()
      local day = math.floor(days * label.part + 0.5)
      if label.part > 0 then label:SetText(L.DAYS_AGO:format(day)) end
      label:SetPoint("TOP", plot, "BOTTOMLEFT", width * (1 - day / days), -6)
    end
  end
  plot:SetScript("OnSizeChanged", function() box:Draw(box.bank) end)
  return box
end

local function Build(panel)
  local L = ns.L
  local view = { filter = {} }

  local page = W.Page(panel)
  panel = page.Body

  -- toolbar: the days everything looks back; right the way into edit mode and what the data is worth.
  -- What the ledger lists (kind, bank tab, one member only) is chosen in the ledger's own title row.
  page:Left(W.Text(page.Bar, "GameFontNormalSmall", L.BANK_PERIOD), 2)
  local periods = {}
  for i, days in ipairs(UI.BANK_DAYS) do periods[i] = { value = days, text = L.BANK_DAYS:format(days) } end
  view.Period = W.Segmented(page.Bar, periods, function(value)
    UI.SetBankSetting("days", value ~= 30 and value or nil)
    view:Refresh()
  end)
  page:Left(view.Period, 8)
  view.Kind = W.Segmented(page.Bar, {
    { value = "all", text = L.BANK_ALL }, { value = "gold", text = L.BANK_GOLD }, { value = "items", text = L.BANK_ITEMS },
  }, function(value)
    view.filter.kind = value ~= "all" and value or nil
    view:Refresh()
  end)
  view.Kind:SetValue("all")
  -- one button per bank tab, "All" first: built anew when the tabs change (their names are the guild's)
  view.TabBar = CreateFrame("Frame", nil, page.Bar)
  view.TabBar:SetSize(1, 22)
  view.TabButtons = {}
  local function TabButton(position)
    local button = view.TabButtons[position]
    if not button then
      button = W.Button(view.TabBar, "", function(self)
        view.filter.tab = self.tab
        view:Refresh()
      end, 44, { small = true, maxWidth = 120 })
      view.TabButtons[position] = button
    end
    return button
  end
  view.Only = W.Button(page.Bar, "", function()
    view.filter.who, view.filter.whoName = nil, nil
    view:Refresh()
  end, 60, { small = true, maxWidth = 200 })
  W.Tooltip(view.Only, L.BANK_ONLY_TIP)
  view.Only:Hide()

  -- the board the boxes stand on, with its edit mode (UI/Board.lua)
  local board = UI.Board(panel, {
    -- (UI.bankShot: the pictures of /guildy shots bank bring their own layout and keep nothing, UI/Shots.lua)
    load = function()
      if UI.bankShot then return UI.bankShot.layout end
      return UI.BankSetting("layout")
    end,
    save = function(layout)
      if UI.bankShot then
        UI.bankShot.layout = layout
      else
        UI.SetBankSetting("layout", layout)
      end
    end,
    default = function() return UI.BANK_PRESETS.ledger end,
    onChange = function() view:Refresh() end,
    grow = function(delta) return UI.GrowWindow(delta) end,
  })
  view.board = board
  board:Controls(page, { { L.BANK_LEDGER }, { L.TAB_MEMBERS, UI.BANK_PRESETS.members }, { L.TAB_OVERVIEW, UI.BANK_PRESETS.overview } })
  view.Status = W.Text(page.Bar, "GameFontDisableSmall")
  view.Status:SetJustifyH("RIGHT")
  view.Status:SetWordWrap(false)
  local holder = board.Content

  -- the gold and the sums of the chosen days
  local total = W.Box(holder)
  view.Total = total
  local totalTitle = W.Text(total, "GameFontNormal", L.BANK_TOTAL)
  totalTitle:SetPoint("TOPLEFT", 10, -8)
  view.Money = W.Text(total, "GameFontNormalHuge")
  view.Money:SetPoint("TOPLEFT", 12, -30)
  view.SumsLabel = W.Text(total, "GameFontDisableSmall")
  view.SumsLabel:SetPoint("TOPLEFT", 12, -58)
  view.Sums = {}
  for i, key in ipairs({ "PAID", "TAKEN", "REPAIRS", "MOVED" }) do
    local label = W.Text(total, "GameFontHighlightSmall", L["BANK_SUM_" .. key])
    label:SetPoint("TOPLEFT", 12, -62 - i * 17)
    local value = W.Text(total, "GameFontHighlightSmall")
    value:SetPoint("RIGHT", total, "RIGHT", -12, 0)
    value:SetPoint("TOP", label, "TOP", 0, 0)
    value:SetJustifyH("RIGHT")
    view.Sums[key] = value
  end

  -- the tabs and how full they are, and what the next one costs
  local tabs = W.Box(holder)
  view.TabsBox = tabs
  local tabsTitle = W.Text(tabs, "GameFontNormal", L.BANK_TABS)
  tabsTitle:SetPoint("TOPLEFT", 10, -8)
  local tabsHint = W.Text(tabs, "GameFontDisableSmall", L.BANK_TABS_HINT)
  tabsHint:SetPoint("LEFT", tabsTitle, "RIGHT", 8, 0)
  view.Tabs = W.ScrollList(tabs, TAB_ROW, function(row)
    row.Icon = row:CreateTexture(nil, "ARTWORK")
    row.Icon:SetSize(20, 20)
    row.Icon:SetPoint("LEFT", 4, 0)
    row.Icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    row.Name = W.Text(row, "GameFontHighlightSmall")
    row.Name:SetPoint("TOPLEFT", 32, -1)
    row.Name:SetPoint("RIGHT", -60, 0)
    row.Name:SetWordWrap(false)
    row.Count = W.Text(row, "GameFontNormalSmall")
    row.Count:SetPoint("TOPRIGHT", -4, -1)
    row.Count:SetJustifyH("RIGHT")
    row.Track = row:CreateTexture(nil, "BACKGROUND")
    row.Track:SetPoint("TOPLEFT", 32, -17)
    row.Track:SetPoint("RIGHT", -4, 0)
    row.Track:SetHeight(5)
    row.Track:SetColorTexture(0.13, 0.11, 0.08, 1)
    row.Fill = row:CreateTexture(nil, "ARTWORK")
    row.Fill:SetPoint("TOPLEFT", row.Track, "TOPLEFT", 0, 0)
    row.Fill:SetHeight(5)
  end, function(row, item)
    local tab = item.tab
    row.Icon:SetTexture(tab.icon or QUESTION)
    row.Name:SetText(tab.name or L.BANK_TAB_N:format(item.index))
    local used = B.Used(tab)
    row.Count:SetText(used and (used .. GREY .. " / " .. B.SLOTS .. "|r") or (GREY .. "?|r"))
    local share = (used or 0) / B.SLOTS
    row.Fill:SetShown(used ~= nil and used > 0)
    row.Fill:SetWidth(math.max(1, (row.Track:GetWidth() or 100) * share))
    if share >= 0.8 then row.Fill:SetColorTexture(0.84, 0.48, 0.2, 1) else row.Fill:SetColorTexture(0.8, 0.66, 0.33, 1) end
  end)
  view.Tabs:SetPoint("TOPLEFT", 6, -30)
  view.TabsEmpty = W.Text(tabs, "GameFontDisable", L.BANK_TABS_EMPTY)
  view.TabsEmpty:SetPoint("TOPLEFT", 12, -32)
  view.TabsEmpty:SetPoint("RIGHT", -12, 0)
  -- what the next tab costs: in the title row (a line of its own below cost the list a tab's height)
  view.Cost = W.Text(tabs, "GameFontDisableSmall")
  view.Cost:SetPoint("TOPRIGHT", -10, -10)
  view.Cost:SetJustifyH("RIGHT")

  -- what this character may still take today, as read at the banker
  local access = W.Box(holder)
  view.Access = access
  local accessTitle = W.Text(access, "GameFontNormal", L.BANK_ACCESS)
  accessTitle:SetPoint("TOPLEFT", 10, -8)
  view.AccessRank = W.Text(access, "GameFontDisableSmall")
  view.AccessRank:SetPoint("LEFT", accessTitle, "RIGHT", 8, 0)
  view.AccessEmpty = W.Text(access, "GameFontDisable", L.BANK_ACCESS_NONE)
  view.AccessEmpty:SetPoint("TOPLEFT", 12, -32)
  view.AccessEmpty:SetPoint("RIGHT", -12, 0)
  local goldLabel = W.Text(access, "GameFontHighlightSmall", L.BANK_ACCESS_GOLD)
  goldLabel:SetPoint("TOPLEFT", 12, -34)
  view.AccessGold = W.Text(access, "GameFontNormalSmall")
  view.AccessGold:SetPoint("TOPRIGHT", -12, -34)
  view.AccessGold:SetJustifyH("RIGHT")
  local takesLabel = W.Text(access, "GameFontDisableSmall", L.BANK_ACCESS_TAKES)
  takesLabel:SetPoint("TOPLEFT", 12, -58)
  view.AccessParts = { goldLabel, view.AccessGold, takesLabel }
  view.AccessRows = {}
  local function AccessRow(position)
    local row = view.AccessRows[position]
    if not row then
      row = { Name = W.Text(access, "GameFontHighlightSmall"), Value = W.Text(access, "GameFontNormalSmall") }
      row.Name:SetPoint("TOPLEFT", 12, -60 - position * 16)
      row.Name:SetPoint("RIGHT", -110, 0)
      row.Name:SetWordWrap(false)
      row.Value:SetPoint("TOPRIGHT", -12, -60 - position * 16)
      row.Value:SetJustifyH("RIGHT")
      view.AccessRows[position] = row
    end
    return row
  end

  -- the gold over time; a click on a mark picks its member
  view.Chart = Chart(holder)
  view.Chart.OnPick = function(step)
    if not step.w then return end
    view.filter.who, view.filter.whoName = ns.Names.Key(step.w), step.w
    view.pick, view.pickName = view.filter.who, step.w
    view:Refresh()
  end

  -- the ledger
  local book = W.Box(holder)
  view.Book = book
  local bookTitle = W.Text(book, "GameFontNormal", L.BANK_LEDGER)
  bookTitle:SetPoint("TOPLEFT", 10, -8)
  view.Count = W.Text(book, "GameFontDisableSmall")
  view.Count:SetPoint("TOPRIGHT", -10, -10)
  -- what it lists, in its title row: the kind, the bank tab (a button each, or a menu where the ledger
  -- is too narrow for them) and one member only
  for _, control in ipairs({ view.Kind, view.TabBar, view.Only }) do control:SetParent(book) end
  view.Kind:SetPoint("LEFT", bookTitle, "RIGHT", 14, 0)
  view.TabBar:SetPoint("LEFT", view.Kind, "RIGHT", 12, 0)
  view.TabMenu = W.MenuButton(book, L.BANK_TABS_ALL, function()
    local items = { { text = L.BANK_TABS_ALL, checked = view.filter.tab == nil, onClick = function()
      view.filter.tab = nil
      view:Refresh()
    end } }
    for index = 1, B.MAX_TABS do
      if view.bank and view.bank.tabs[index] then
        items[#items + 1] = { text = TabName(view.bank, index), checked = view.filter.tab == index, onClick = function()
          view.filter.tab = index
          view:Refresh()
        end }
      end
    end
    return items
  end, 110, 160)
  view.TabMenu:SetPoint("LEFT", view.Kind, "RIGHT", 12, 0)
  view.TabMenu:Hide()

  -- columns: "when", "tab" and "gold after" can be switched off in the box's options (edit mode), which
  -- lets the ledger stand in a narrower place
  local TAB_W, AFTER_W = 126, 100
  local function Cols()
    local o = book.opts or {}
    local c, x, r = {}, 4, -4
    if o.when ~= false then c.when, x = x, x + 80 end
    c.who, c.action, c.what = x, x + 152, x + 272
    if o.after ~= false then c.after, r = r, r - AFTER_W - 6 end
    if o.tab ~= false then c.tab, r = r, r - TAB_W - 6 end
    c.right = r
    return c
  end
  -- places the cells of a row (or the headings) for the columns that show
  local function Arrange(owner, p)
    local c = Cols()
    local function Side(region, side, x, width)
      region:ClearAllPoints()
      region:SetPoint(side, owner, side, x, 0)
      region:SetWidth(width)
    end
    p.When:SetShown(c.when ~= nil)
    if c.when then Side(p.When, "LEFT", c.when, 74) end
    Side(p.Who, "LEFT", c.who, 146)
    Side(p.Action, "LEFT", c.action, 114)
    p.Tab:SetShown(c.tab ~= nil)
    if c.tab then Side(p.Tab, "RIGHT", c.tab, TAB_W) end
    p.After:SetShown(c.after ~= nil)
    if c.after then Side(p.After, "RIGHT", c.after, AFTER_W) end
    return c
  end
  local head = CreateFrame("Frame", nil, book)
  head:SetPoint("TOPLEFT", 8, -28)
  head:SetPoint("RIGHT", -28, 0)
  head:SetHeight(16)
  view.Head = {}
  for key, label in pairs({ When = L.BANK_COL_WHEN, Who = L.BANK_COL_WHO, Action = L.BANK_COL_ACTION,
    What = L.BANK_COL_WHAT, Tab = L.BANK_COL_TAB, After = L.BANK_COL_AFTER }) do
    view.Head[key] = W.Text(head, "GameFontDisableSmall", label)
    view.Head[key]:SetWordWrap(false)
  end
  view.Head.After:SetJustifyH("RIGHT")
  function view:ArrangeHead()
    local c = Arrange(head, self.Head)
    self.Head.What:ClearAllPoints()
    self.Head.What:SetPoint("LEFT", head, "LEFT", c.what, 0)
  end

  view.List = W.ScrollList(book, ROW, function(row)
    row.When = W.Text(row, "GameFontDisableSmall")
    row.Who = W.Text(row, "GameFontHighlightSmall")
    row.Who:SetWordWrap(false)
    row.Action = W.Text(row, "GameFontHighlightSmall")
    row.Action:SetWordWrap(false)
    row.Icon = row:CreateTexture(nil, "ARTWORK")
    row.Icon:SetSize(ROW - 4, ROW - 4)
    row.Icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    row.What = W.Text(row, "GameFontHighlightSmall")
    row.What:SetWordWrap(false)
    row.Tab = W.Text(row, "GameFontDisableSmall")
    row.Tab:SetWordWrap(false)
    row.After = W.Text(row, "GameFontNormalSmall")
    row.After:SetJustifyH("RIGHT")
    -- a gap spans the row from the name column on
    row.Gap = W.Text(row, "GameFontHighlightSmall")
    row.Gap:SetWordWrap(false)
    -- a click on the name lists only that member (and shows them in the box of one member's movements)
    row.Pick = CreateFrame("Button", nil, row)
    row.Pick:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    row.Pick:SetScript("OnClick", function()
      local e = row.entry
      if not (e and e.w) then return end
      view.filter.who, view.filter.whoName = ns.Names.Key(e.w), e.w
      view.pick, view.pickName = view.filter.who, e.w
      view:Refresh()
    end)
    -- the item's tooltip over its icon and name
    row.Hover = CreateFrame("Frame", nil, row)
    row.Hover:EnableMouse(true)
    row.Hover:SetScript("OnEnter", function(self)
      local e = row.entry
      if not (e and e.i) then return end
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      if pcall(GameTooltip.SetHyperlink, GameTooltip, e.i) then GameTooltip:Show() end
    end)
    row.Hover:SetScript("OnLeave", function() GameTooltip:Hide() end)
  end, function(row, item)
    local e, bank = item.e, view.bank
    local c = Arrange(row, row)
    row.entry = e
    row.When:SetText(Ago(e.ts))
    local gap = e.k == "gap"
    row.Gap:SetShown(gap)
    if gap then
      for _, key in ipairs({ "Who", "Action", "Icon", "What", "Tab", "After", "Pick", "Hover" }) do row[key]:Hide() end
      row.Gap:ClearAllPoints()
      row.Gap:SetPoint("LEFT", row, "LEFT", c.who, 0)
      row.Gap:SetPoint("RIGHT", row, "RIGHT", -4, 0)
      row.Gap:SetText(ORANGE .. L.BANK_GAP:format(B.LOG_LIMIT) .. "|r")
      return
    end
    local money = item.log == B.MONEY
    row.Who:Show()
    row.Who:SetText(Who(e.w))
    row.Pick:ClearAllPoints()
    row.Pick:SetPoint("TOPLEFT", c.who, 0)
    row.Pick:SetPoint("BOTTOMLEFT", c.who, 0)
    row.Pick:SetWidth(146)
    row.Pick:SetShown(e.w ~= nil)
    local sign = GREY .. ">|r "
    if (money and B.PLUS[e.k]) or (not money and e.k == "deposit") then
      sign = GREEN .. "+|r "
    elseif (money and B.MINUS[e.k]) or (not money and e.k == "withdraw") then
      sign = RED .. "-|r "
    end
    row.Action:Show()
    row.Action:SetText(sign .. Verb(e.k))
    row.Icon:ClearAllPoints()
    row.Icon:SetPoint("LEFT", row, "LEFT", c.what, 0)
    row.Icon:SetShown(not money)
    row.Hover:ClearAllPoints()
    row.Hover:SetPoint("TOPLEFT", c.what, 0)
    row.Hover:SetPoint("BOTTOMRIGHT", c.right, 0)
    row.Hover:SetShown(not money)
    row.What:Show()
    row.What:ClearAllPoints()
    row.What:SetPoint("LEFT", row, "LEFT", c.what + (money and 0 or ROW + 2), 0)
    row.What:SetPoint("RIGHT", row, "RIGHT", c.right, 0)
    if money then
      row.What:SetText(Money(e.c))
      row.Tab:SetText("|cffc9a34a" .. L.BANK_GOLD .. "|r")
      row.After:SetText(item.after and Money(item.after) or "")
    else
      row.Icon:SetTexture(ItemIcon(e.id))
      row.What:SetText(ItemText(e) .. "  |cffffd100x " .. (e.n or 1) .. "|r")
      local name = TabName(bank, e.a)
      if e.k == "move" and e.b and e.b ~= e.a then name = name .. " > " .. TabName(bank, e.b) end
      row.Tab:SetText(name)
      row.After:SetText("")
    end
  end)
  view.List:SetPoint("TOPLEFT", 8, -46)
  view.List:SetPoint("BOTTOMRIGHT", -28, 8)
  view.Empty = W.Text(book, "GameFontDisable")
  view.Empty:SetPoint("TOPLEFT", 24, -70)
  view.Empty:SetPoint("RIGHT", -24, 0)
  view.Empty:SetJustifyH("CENTER")

  -- every box of the board: what it is, the size a new one gets and the smallest it works at (in cells),
  -- what can be switched off in it, and which of that is a part with a handle of its own (a tile, the
  -- heading of a column) while customizing
  local function On(o, key) return o[key] ~= false and 1 or 0 end
  view.More = UI.BankWidgets(holder, view)
  board:Add("total", total, { name = L.BANK_TOTAL, about = L.BANK_ABOUT_TOTAL, size = { 3, 4 }, min = { 3, 4 } })
  board:Add("tabs", tabs, { name = L.BANK_TABS, about = L.BANK_ABOUT_TABS, size = { 3, 4 }, min = { 3, 3 } })
  board:Add("access", access, { name = L.BANK_ACCESS, about = L.BANK_ABOUT_ACCESS, size = { 3, 4 }, min = { 3, 3 } })
  board:Add("chart", view.Chart, { name = L.BANK_CHART, about = L.BANK_ABOUT_CHART, size = { 8, 4 }, min = { 4, 3 },
    options = { { "marks", L.OPTIONS_BANK_MARKS_HEAD }, { "bars", L.BANK_OPT_BARS } } })
  board:Add("ledger", book, { name = L.BANK_LEDGER, about = L.BANK_ABOUT_LEDGER, size = { 9, 6 },
    min = function(o)
      local side = On(o, "tab") + On(o, "after")
      return { 5 + On(o, "when") + side, 3 }
    end,
    options = { { "when", L.BANK_COL_WHEN }, { "tab", L.BANK_COL_TAB }, { "after", L.BANK_COL_AFTER } },
    parts = function()
      return { { frame = view.Head.When, option = "when" }, { frame = view.Head.Tab, option = "tab" },
        { frame = view.Head.After, option = "after" } }
    end })
  board:Add("tiles", view.More.tiles, { name = L.BANK_TILES, about = L.BANK_ABOUT_TILES, size = { 12, 2 },
    min = function(o)
      local count = On(o, "gold") + On(o, "paid") + On(o, "taken") + On(o, "repairs") + On(o, "slots")
      return { math.max(3, math.ceil(count * 1.6)), 2 }
    end,
    options = { { "gold", L.BANK_GOLD }, { "paid", L.BANK_SUM_PAID }, { "taken", L.BANK_SUM_TAKEN },
      { "repairs", L.BANK_SUM_REPAIRS }, { "slots", L.BANK_TABS_HINT } },
    parts = function()
      local parts = {}
      for _, key in ipairs({ "gold", "paid", "taken", "repairs", "slots" }) do
        parts[#parts + 1] = { frame = view.More.tiles.Tiles[key], option = key }
      end
      return parts
    end, bare = true })
  board:Add("balance", view.More.balance, { name = L.BANK_BALANCE, about = L.BANK_ABOUT_BALANCE, size = { 8, 6 },
    min = function(o) return { 5 + On(o, "rank") + On(o, "items") + On(o, "last"), 4 } end,
    options = { { "rank", L.COL_RANK }, { "items", L.BANK_ITEMS }, { "last", L.BANK_COL_LAST } },
    parts = function()
      local heads = view.More.balance.Heads
      return { { frame = heads.rankIndex, option = "rank" }, { frame = heads.itemsIn, option = "items" },
        { frame = heads.last, option = "last" } }
    end })
  board:Add("detail", view.More.detail, { name = L.BANK_DETAIL, about = L.BANK_ABOUT_DETAIL, size = { 4, 6 }, min = { 4, 4 } })
  board:Add("largest", view.More.largest, { name = L.BANK_LARGEST, about = L.BANK_ABOUT_LARGEST, size = { 4, 4 }, min = { 3, 3 } })
  board:Add("givers", view.More.givers, { name = L.BANK_GIVERS, about = L.BANK_ABOUT_GIVERS, size = { 4, 4 }, min = { 3, 3 } })

  function view:OnHide()
    if board.editing then board:SetEditing(false) end
  end

  function view:Refresh()
    local guild = ns.GuildData()
    -- (looking at the tab stores nothing: no bank table before the first reading)
    local bank = guild and type(guild.bank) == "table" and B.Get(guild) or nil
    local shot = UI.bankShot
    if shot then bank = not shot.empty and shot.bank or nil end
    self.bank = bank
    local known = bank ~= nil and bank.at ~= nil
    local now, days = ns.Now(), UI.BankDays()
    local mine = ns.GameBank.Mine()
    if shot then mine = not shot.empty and shot.mine or nil end
    local editing = board.editing == true
    local ctx = { bank = bank, known = known, now = now, days = days }

    -- toolbar
    self.Period:SetValue(days)
    self.Only:SetShown(self.filter.who ~= nil)
    if self.filter.who then self.Only:SetText(L.BANK_ONLY:format(ns.Anon.Name(self.filter.whoName))) end
    self.Status:ClearAllPoints()
    self.Status:SetPoint("RIGHT", board.Tools, "LEFT", -12, 0)
    self.Status:SetPoint("LEFT", self.Period, "RIGHT", 12, 0)
    self.Status:SetText(editing and L.BOARD_HINT
      or known and L.BANK_STATUS:format(Ago(bank.at), Who(bank.by)) or L.BANK_STATUS_NONE)

    -- the tabs: the list in their box and the buttons in the toolbar
    local tabItems = {}
    for index = 1, B.MAX_TABS do
      if known and bank.tabs[index] then
        tabItems[#tabItems + 1] = { index = index, tab = bank.tabs[index], mine = mine and mine.tabs and mine.tabs[index] }
      end
    end
    if self.filter.tab and not (known and bank.tabs[self.filter.tab]) then self.filter.tab = nil end
    local x = 0
    for position = 0, #tabItems do
      local button = TabButton(position + 1)
      local item = tabItems[position]
      button.tab = item and item.index or nil
      button:SetText(item and (item.tab.name or L.BANK_TAB_N:format(item.index)) or L.BANK_TABS_ALL)
      button:ClearAllPoints()
      button:SetPoint("LEFT", self.TabBar, "LEFT", x, 0)
      x = x + (button:GetWidth() or 44) + 2
      local on = self.filter.tab == button.tab
      button:SetEnabled(not on)
      local label = button:GetFontString()
      if label then label:SetTextColor(1, on and 1 or 0.82, on and 1 or 0) end
      button:Show()
    end
    for position = #tabItems + 2, #self.TabButtons do self.TabButtons[position]:Hide() end
    self.TabBar:SetWidth(math.max(1, x))
    -- a button per tab where the ledger is wide enough for them beside its title, the kinds and the count
    local asMenu = #tabItems > 0 and x > (book:GetWidth() or 0) - 470
    self.TabBar:SetShown(#tabItems > 0 and not asMenu)
    self.TabMenu:SetShown(asMenu)
    self.TabMenu:SetText(self.filter.tab and TabName(bank, self.filter.tab) or L.BANK_TABS_ALL)
    self.Only:ClearAllPoints()
    self.Only:SetPoint("LEFT", asMenu and self.TabMenu or (#tabItems > 0 and self.TabBar or self.Kind), "RIGHT", 10, 0)

    board:Apply()
    local placed = board.placed

    if placed.total then
      self.Money:SetText(known and bank.money and Money(bank.money) or (GREY .. "?|r"))
      self.SumsLabel:SetText(L.BANK_WEEK:format(days))
      local sums = known and B.Sums(bank, now, days) or { paid = 0, taken = 0, repairs = 0, itemsIn = 0, itemsOut = 0 }
      -- nothing read yet: no sums rather than zeros
      local none = GREY .. "?|r"
      self.Sums.PAID:SetText(known and (GREEN .. "+|r" .. Money(sums.paid)) or none)
      self.Sums.TAKEN:SetText(known and (RED .. "-|r" .. Money(sums.taken)) or none)
      self.Sums.REPAIRS:SetText(known and (RED .. "-|r" .. Money(sums.repairs)) or none)
      self.Sums.MOVED:SetText(known and (GREEN .. "+" .. sums.itemsIn .. "|r" .. GREY .. "  /  |r" .. RED .. "-" .. sums.itemsOut .. "|r") or none)
    end

    if placed.tabs then
      local costShown = known and (bank.cost or 0) > 0
      self.Tabs:ClearAllPoints()
      self.Tabs:SetPoint("TOPLEFT", 6, -30)
      self.Tabs:SetPoint("BOTTOMRIGHT", -26, 6)
      self.Tabs:SetItems(tabItems)
      self.TabsEmpty:SetShown(#tabItems == 0)
      self.TabsEmpty:SetText(known and L.BANK_TABS_NONE or L.BANK_TABS_EMPTY)
      self.Cost:SetShown(costShown)
      tabsHint:SetShown(not costShown)
      if costShown then self.Cost:SetText(L.BANK_TAB_COST:format(#tabItems + 1) .. " " .. Money(bank.cost)) end
    end

    -- what the player may still take: from the own visit, never shared
    if placed.access then
      local me = ns.Roster.Me()
      self.AccessRank:SetText(me and me.rank and L.BANK_ACCESS_RANK:format(me.rank) or "")
      self.AccessEmpty:SetShown(mine == nil)
      for _, part in ipairs(self.AccessParts) do part:SetShown(mine ~= nil) end
      local rows = 0
      if mine then
        local gold = mine.gold
        self.AccessGold:SetText(not gold and (GREY .. "?|r") or gold < 0 and L.BANK_UNLIMITED or Money(gold))
        self.AccessParts[3]:SetShown(#tabItems > 0)
        for _, item in ipairs(tabItems) do
          rows = rows + 1
          local row = AccessRow(rows)
          local own = item.mine
          row.Name:SetText(item.tab.name or L.BANK_TAB_N:format(item.index))
          local value = GREY .. "?|r"
          if own then
            if not own.view then
              value = GREY .. L.BANK_TAB_HIDDEN .. "|r"
            elseif (own.left or 0) < 0 then
              value = L.BANK_UNLIMITED
            elseif (own.limit or 0) == 0 then
              value = GREY .. (own.deposit and L.BANK_TAB_DEPOSIT or L.BANK_TAB_VIEW) .. "|r"
            else
              value = (own.left or 0) .. GREY .. " / " .. own.limit .. "|r"
            end
          end
          row.Value:SetText(value)
          row.Name:Show()
          row.Value:Show()
        end
      end
      for position = rows + 1, #self.AccessRows do
        self.AccessRows[position].Name:Hide()
        self.AccessRows[position].Value:Hide()
      end
    end

    if placed.chart then self.Chart:Draw(known and bank or nil) end

    if placed.ledger then
      local ledger = known and B.Ledger(bank, self.filter) or {}
      self:ArrangeHead()
      self.List:SetItems(ledger)
      self.Count:SetText(L.BANK_ENTRIES:format(#ledger))
      self.Empty:SetShown(#ledger == 0)
      local filtered = self.filter.kind or self.filter.tab or self.filter.who
      self.Empty:SetText(not known and L.BANK_EMPTY or filtered and L.BANK_NONE or L.BANK_NO_ENTRIES)
    end

    for key, box in pairs(self.More) do
      if placed[key] then box:Fill(ctx) end
    end
  end

  board:Apply()
  return view
end

UI.RegisterTab("bank", 7, "TAB_BANK", Build)
