-- The tiles and title cards of a Hall of Fame page, chosen in a small window of its own: opened from
-- the two boxes while the tab is customized (UI/TabFame.lua, "Choose"). The two rows on top, one under
-- the other: the tiles (guild totals) and the title cards (who holds a title), each drawn as the page
-- shows it. A click picks an entry, the buttons under the rows move or remove it; the two lists below
-- hold what else can go into each row (the page's own first, then the other pages'), a click adds.
-- "Restore defaults" brings the page's two rows back to what Guildy ships.
local _, ns = ...
local W = ns.Widgets
local UI = ns.UI

local WIDTH, HEIGHT = 560, 560

local function BuildEditor(panel)
  local L = ns.L
  local S = ns.Stats
  panel.page, panel.kind = S.PAGES[1].key, "tiles"

  local function CurrentPage()
    for _, page in ipairs(S.PAGES) do
      if page.key == panel.page then return page end
    end
    return S.PAGES[1]
  end
  -- every title by its key, and the page a statistic or title comes from
  local titleOf, homeOf = {}, {}
  for _, page in ipairs(S.PAGES) do
    for _, id in ipairs(page.headline) do homeOf[id] = homeOf[id] or page end
    for _, fame in ipairs(page.titles) do
      titleOf[fame.key] = fame
      homeOf[fame.key] = page
      homeOf[fame.stat] = homeOf[fame.stat] or page
    end
  end
  -- the tab shows the change at once
  local function Changed()
    local view = UI.TabView("fame")
    if view and view.Refresh then ns.SafeCall(view.Refresh, view) end
  end
  local function Saved(setting, page)
    local saved = ns.Settings()[setting]
    return type(saved) == "table" and saved[page.key] or nil
  end
  -- the two rows a page has: what it shows now (ids), what it could show, how an id reads, and where
  -- its preview stands
  local KINDS = {
    tiles = {
      setting = "fameTiles", max = S.MAX_TILES, label = L.OPTIONS_KIND_TILES, more = L.OPTIONS_TILES_MORE,
      top = -2, height = 84, slotHeight = 68,
      list = function(page)
        local list = {}
        for i, id in ipairs(S.Headline(page, Saved("fameTiles", page))) do list[i] = id end
        return list
      end,
      choices = function(page) return S.TileChoices(page) end,
      name = function(id) return UI.Fame.TileName(id) end,
    },
    cards = {
      setting = "fameCards", max = S.MAX_CARDS, label = L.OPTIONS_KIND_CARDS, more = L.OPTIONS_CARDS_MORE,
      top = -114, height = 88, slotHeight = 34, perRow = 4,
      list = function(page)
        local list = {}
        for i, fame in ipairs(S.Titles(page, Saved("fameCards", page))) do
          if i <= S.MAX_CARDS then list[i] = fame.key end
        end
        return list
      end,
      choices = function(page)
        local list = {}
        for i, fame in ipairs(S.TitleChoices(page)) do list[i] = fame.key end
        return list
      end,
      name = function(key) return L["FAME_TITLE_" .. key] or key end,
    },
  }
  local ORDER = { "tiles", "cards" }
  local function Kind(key) return KINDS[key or panel.kind] or KINDS.tiles end
  local function Save(page, kind, list)
    local settings = ns.Settings()
    if type(settings[kind.setting]) ~= "table" then settings[kind.setting] = {} end
    settings[kind.setting][page.key] = list
    panel:Refresh()
    Changed()
  end
  local function IndexOf(list, id)
    for i, other in ipairs(list) do
      if other == id then return i end
    end
  end

  -- panel.kind is the row the picked entry is in (and the row the buttons work on)
  function panel:SetKind(kind)
    self.kind, self.selected = KINDS[kind] and kind or "tiles", nil
    self:Refresh()
  end
  function panel:Add(id, key)
    if key then self.kind = key end
    local page, kind = CurrentPage(), Kind()
    local list = kind.list(page)
    if IndexOf(list, id) or #list >= kind.max then return end
    list[#list + 1] = id
    self.selected = id
    Save(page, kind, list)
  end
  -- a row keeps at least one entry
  function panel:Remove(id)
    local page, kind = CurrentPage(), Kind()
    local list = kind.list(page)
    local index = IndexOf(list, id)
    if not index or #list <= 1 then return end
    table.remove(list, index)
    self.selected = nil
    Save(page, kind, list)
  end
  function panel:Move(id, delta)
    local page, kind = CurrentPage(), Kind()
    local list = kind.list(page)
    local index = IndexOf(list, id)
    local to = index and index + delta
    if not to or to < 1 or to > #list then return end
    list[index], list[to] = list[to], list[index]
    Save(page, kind, list)
  end
  -- the page as Guildy ships it: tiles and title cards
  function panel:Restore()
    local settings = ns.Settings()
    for _, kind in pairs(KINDS) do
      if type(settings[kind.setting]) == "table" then settings[kind.setting][self.page] = nil end
    end
    self.selected = nil
    self:Refresh()
    Changed()
  end

  -- the two rows: a label with the count, the preview under it
  for _, key in ipairs(ORDER) do
    local kind = KINDS[key]
    kind.Label = W.Text(panel, "GameFontNormalSmall")
    kind.Label:SetPoint("TOPLEFT", 4, kind.top)
    local preview = W.Box(panel)
    preview:SetPoint("TOPLEFT", 0, kind.top - 16)
    preview:SetPoint("RIGHT", 0, 0)
    preview:SetHeight(kind.height)
    kind.Preview = preview
    kind.Slots = {}
    for i = 1, kind.max do
      local slot = W.Box(preview, 0.05, 0.5)
      slot.Icon = slot:CreateTexture(nil, "ARTWORK")
      slot.Icon:SetSize(24, 24)
      slot.Icon:SetPoint("LEFT", 5, 0)
      slot.Icon:SetShown(key == "cards")
      slot.Value = W.Text(slot, key == "cards" and "GameFontNormalSmall" or "GameFontNormalLarge")
      slot.Label = W.Text(slot, "GameFontDisableSmall")
      if key == "cards" then
        -- like the page's cards: the title's icon, its name, the statistic under it
        slot.Value:SetPoint("TOPLEFT", slot.Icon, "TOPRIGHT", 6, 0)
        slot.Value:SetPoint("RIGHT", -4, 0)
        slot.Value:SetWordWrap(false)
        slot.Label:SetPoint("TOPLEFT", slot.Value, "BOTTOMLEFT", 0, -2)
        slot.Label:SetPoint("RIGHT", -4, 0)
        slot.Label:SetWordWrap(false)
      else
        slot.Value:SetPoint("TOP", 0, -10)
        slot.Value:SetJustifyH("CENTER")
        slot.Label:SetPoint("TOP", slot.Value, "BOTTOM", 0, -4)
        slot.Label:SetPoint("LEFT", 4, 0)
        slot.Label:SetPoint("RIGHT", -4, 0)
        slot.Label:SetJustifyH("CENTER")
        if slot.Label.SetMaxLines then slot.Label:SetMaxLines(2) end
      end
      local hover = slot:CreateTexture(nil, "HIGHLIGHT")
      hover:SetPoint("TOPLEFT", 3, -3)
      hover:SetPoint("BOTTOMRIGHT", -3, 3)
      hover:SetColorTexture(1, 0.82, 0, 0.08)
      slot:EnableMouse(true)
      slot:SetScript("OnMouseUp", function(self)
        local same = panel.kind == key and panel.selected == self.id
        panel.kind, panel.selected = key, (not same) and self.id or nil
        panel:Refresh()
      end)
      slot:SetScript("OnEnter", function(self)
        if not self.id then return end
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(kind.name(self.id), 1, 1, 1)
        local fame = key == "cards" and titleOf[self.id]
        if fame then GameTooltip:AddLine(UI.Fame.TileName(fame.stat), 0.8, 0.8, 0.8, true) end
        GameTooltip:Show()
      end)
      slot:SetScript("OnLeave", function() GameTooltip:Hide() end)
      kind.Slots[i] = slot
    end
  end

  -- what to do with the picked entry
  panel.Left = W.Button(panel, L.OPTIONS_TILE_LEFT, function() panel:Move(panel.selected, -1) end, 90, { small = true })
  panel.Left:SetPoint("TOPLEFT", KINDS.cards.Preview, "BOTTOMLEFT", 0, -8)
  panel.Right = W.Button(panel, L.OPTIONS_TILE_RIGHT, function() panel:Move(panel.selected, 1) end, 90, { small = true })
  panel.Right:SetPoint("LEFT", panel.Left, "RIGHT", 4, 0)
  panel.RemoveButton = W.Button(panel, L.OPTIONS_TILE_REMOVE, function() panel:Remove(panel.selected) end, 90, { small = true })
  panel.RemoveButton:SetPoint("LEFT", panel.Right, "RIGHT", 4, 0)
  -- filters both lists below: a part of the name, or of the page or category an entry comes from
  panel.query = ""
  local search = W.EditBox(panel, 190)
  search:SetPoint("RIGHT", panel, "RIGHT", -2, 0)
  search:SetPoint("TOP", panel.Left, "TOP", 0, -1)
  search.Hint = W.Text(search, "GameFontDisableSmall", L.OPTIONS_TILES_SEARCH)
  search.Hint:SetPoint("LEFT", 2, 0)
  search:SetScript("OnTextChanged", function(self)
    panel.query = self:GetText() or ""
    self.Hint:SetShown(panel.query == "")
    panel:Refresh()
  end)
  panel.Search = search

  -- what else can go into each row: two lists side by side, tiles left, title cards right
  panel.Lists = {}
  for index, key in ipairs(ORDER) do
    local kind = KINDS[key]
    local box = W.Box(panel)
    if index == 1 then
      box:SetPoint("TOPLEFT", panel.Left, "BOTTOMLEFT", 0, -34)
      box:SetPoint("BOTTOMRIGHT", panel, "BOTTOM", -4, 32)
      panel.FirstBox = box
    else
      box:SetPoint("TOPLEFT", panel.FirstBox, "TOPRIGHT", 8, 0)
      box:SetPoint("BOTTOMRIGHT", 0, 32)
    end
    local title = W.Text(panel, "GameFontNormal", kind.more)
    title:SetPoint("BOTTOMLEFT", box, "TOPLEFT", 4, 6)
    local list = W.ScrollList(box, 20, function(row)
      row:EnableMouse(true)
      row.Text = W.Text(row, "GameFontHighlightSmall")
      row.Text:SetPoint("LEFT", 6, 0)
      row.Text:SetPoint("RIGHT", -4, 0)
      row.Text:SetWordWrap(false)
      local highlight = row:CreateTexture(nil, "HIGHLIGHT")
      highlight:SetAllPoints()
      highlight:SetColorTexture(1, 0.82, 0, 0.1)
      row:SetScript("OnMouseUp", function(self) if self.id and not self.full then panel:Add(self.id, key) end end)
      -- the page an entry comes from, and for a title its statistic
      row:SetScript("OnEnter", function(self)
        if not self.id then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(kind.name(self.id), 1, 1, 1)
        local fame = key == "cards" and titleOf[self.id]
        if fame then GameTooltip:AddLine(UI.Fame.TileName(fame.stat), 0.8, 0.8, 0.8, true) end
        if self.from then GameTooltip:AddLine(self.from, 0.6, 0.6, 0.6) end
        GameTooltip:Show()
      end)
      row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end, function(row, item)
      row.id, row.full, row.from = item.id, item.full, item.from
      row.Text:SetText("|cff4ce64c+|r  " .. item.name .. (item.from and ("  |cff8f8268" .. item.from .. "|r") or ""))
      row:SetAlpha(item.full and 0.45 or 1)
    end)
    list:SetPoint("TOPLEFT", 4, -4)
    list:SetPoint("BOTTOMRIGHT", -26, 4)
    panel.Lists[key] = list
  end
  panel.List = panel.Lists.tiles

  local restore = W.Button(panel, L.OPTIONS_RESTORE, function() panel:Restore() end, 170, { small = true })
  restore:SetPoint("BOTTOMRIGHT", 0, 2)
  W.Tooltip(restore, L.OPTIONS_RESTORE, L.OPTIONS_RESTORE_TIP)

  function panel:Refresh()
    local page = CurrentPage()
    local query = (self.query or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    local picked
    for _, key in ipairs(ORDER) do
      local kind = KINDS[key]
      local list = kind.list(page)
      local selected = self.kind == key and self.selected or nil
      if selected and not IndexOf(list, selected) then
        selected, self.selected = nil, nil
      end
      kind.Label:SetText(kind.label .. "  |cff8f8268" .. L.OPTIONS_TILES_COUNT:format(#list, kind.max) .. "|r")
      local gap = 4
      local width = ((kind.Preview:GetWidth() or 0) > 200 and kind.Preview:GetWidth() or WIDTH - 26) - 16
      local perRow = kind.perRow or #list
      local slotW = (width - gap * (perRow - 1)) / perRow
      for i, slot in ipairs(kind.Slots) do
        local id = list[i]
        slot.id = id
        slot:SetShown(id ~= nil)
        if id then
          slot:ClearAllPoints()
          slot:SetPoint("TOPLEFT", kind.Preview, "TOPLEFT", 8 + ((i - 1) % perRow) * (slotW + gap),
            -8 - math.floor((i - 1) / perRow) * (kind.slotHeight + gap))
          slot:SetSize(slotW, kind.slotHeight)
          if key == "cards" then
            local fame = titleOf[id]
            slot.Icon:SetTexture(UI.Fame.Icon(fame.icon))
            slot.Value:SetText(kind.name(id))
            slot.Label:SetText(UI.Fame.TileName(fame.stat))
          else
            slot.Value:SetText(UI.Fame.TileValue(id))
            slot.Label:SetText(kind.name(id))
          end
          if slot.SetBackdropBorderColor then
            local shade = id == selected and 1.2 or 0.5
            slot:SetBackdropBorderColor(W.GOLD[1] * shade, W.GOLD[2] * shade, W.GOLD[3] * shade)
          end
        end
      end
      if selected then picked = { index = IndexOf(list, selected), count = #list } end
      -- what the row does not show yet; entries of another page name it
      local full, items = #list >= kind.max, {}
      for _, id in ipairs(kind.choices(page)) do
        if not IndexOf(list, id) then
          -- from: the other page it stands on, else its category among all statistics
          local home = homeOf[id]
          local from
          if home then
            if home ~= page then from = L["FAME_PAGE_" .. home.key:upper()] end
          elseif key == "tiles" then
            from = UI.Fame.CategoryName(id)
          end
          local name = kind.name(id)
          local found = query == "" or (name .. " " .. (from or "")):lower():find(query, 1, true)
          if found then items[#items + 1] = { id = id, name = name, full = full, from = from } end
        end
      end
      self.Lists[key]:SetItems(items)
    end
    self.Left:SetEnabled(picked ~= nil and picked.index > 1)
    self.Right:SetEnabled(picked ~= nil and picked.index < picked.count)
    self.RemoveButton:SetEnabled(picked ~= nil and picked.count > 1)
  end
end

local window

local function Build()
  local L = ns.L
  window = W.Box(UIParent, 0.05, 0.95)
  window:Hide()
  window:SetSize(WIDTH, HEIGHT)
  if window.SetScale then window:SetScale(UI.Scale()) end
  window:SetFrameStrata("DIALOG")
  if window.SetToplevel then window:SetToplevel(true) end
  window:EnableMouse(true)
  window:SetMovable(true)
  window:SetClampedToScreen(true)
  window:RegisterForDrag("LeftButton")
  window:SetScript("OnDragStart", window.StartMoving)
  window:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    self.moved = true -- stays where the player put it for the session
  end)
  window.Title = W.Text(window, "GameFontNormal")
  window.Title:SetPoint("TOPLEFT", 14, -12)
  window.Close = W.Button(window, "x", function() window:Hide() end, 24, { small = true, pad = 10 })
  window.Close:SetPoint("TOPRIGHT", -6, -6)
  local panel = CreateFrame("Frame", nil, window)
  panel:SetPoint("TOPLEFT", 14, -38)
  panel:SetPoint("BOTTOMRIGHT", -12, 12)
  BuildEditor(panel)
  window.Panel = panel
  function window:Place()
    if self.moved then return end
    self:ClearAllPoints()
    self:SetPoint("CENTER", UI.frame or UIParent, "CENTER", 0, -20)
  end
  function window:SetPage(page)
    panel.page, panel.selected = page, nil
    self.Title:SetText(L.FAME_PICK_TITLE:format(L["FAME_PAGE_" .. page:upper()]))
    panel:Refresh()
  end
end

UI.FamePicker = {}

-- Opens the window for a page ("general", "economy", ...) on one of its rows ("tiles" or "cards")
function UI.FamePicker.Show(page, kind)
  if not window then Build() end
  if window.SetScale then window:SetScale(UI.Scale()) end
  window.Panel.kind = kind == "cards" and "cards" or "tiles"
  window:SetPage(page)
  window:Place()
  window:Show()
end

function UI.FamePicker.Hide()
  if window then window:Hide() end
end

-- The page shown changed: an open window follows it
function UI.FamePicker.Follow(page)
  if window and window:IsShown() and window.Panel.page ~= page then window:SetPage(page) end
end

-- The window once it was built, and its editor (tests)
function UI.FamePicker.Window()
  return window, window and window.Panel
end
