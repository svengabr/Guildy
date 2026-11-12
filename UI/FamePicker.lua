-- One tile or one title card of a Hall of Fame page, changed where it stands: while the tab is
-- customized, a click on a tile opens this small list right under it (UI/TabFame.lua). A click on an
-- entry puts it in the tile's place; the buttons above the list move the tile or take it away. Opened
-- from "Add a statistic" / "Add a title" of the box, a click adds at the end.
-- What a page shows is the player's own: settings.fameTiles[page.key] and settings.fameCards[page.key].
local _, ns = ...
local W = ns.Widgets
local UI = ns.UI
local S = ns.Stats

local WIDTH, HEIGHT = 300, 330

local P = {}
UI.FamePicker = P

local function PageOf(key)
  for _, page in ipairs(S.PAGES) do
    if page.key == key then return page end
  end
  return S.PAGES[1]
end

-- every title by its key, and the page a statistic or title comes from
local titleOf, homeOf
local function Index()
  if titleOf then return end
  titleOf, homeOf = {}, {}
  for _, page in ipairs(S.PAGES) do
    for _, id in ipairs(page.headline) do homeOf[id] = homeOf[id] or page end
    for _, fame in ipairs(page.titles) do
      titleOf[fame.key] = fame
      homeOf[fame.key] = page
      homeOf[fame.stat] = homeOf[fame.stat] or page
    end
  end
end

local function Saved(setting, page)
  local saved = ns.Settings()[setting]
  return type(saved) == "table" and saved[page.key] or nil
end

-- the two rows a page has: what it shows now (ids), what it could show, how an id reads
local KINDS = {
  tiles = {
    setting = "fameTiles", max = S.MAX_TILES, more = "OPTIONS_TILES_MORE",
    list = function(page)
      local list = {}
      for i, id in ipairs(S.Headline(page, Saved("fameTiles", page))) do list[i] = id end
      return list
    end,
    choices = function(page) return S.TileChoices(page) end,
    name = function(id) return UI.Fame.TileName(id) end,
  },
  cards = {
    setting = "fameCards", max = S.MAX_CARDS, more = "OPTIONS_CARDS_MORE",
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
    name = function(key) return ns.L["FAME_TITLE_" .. key] or key end,
  },
}

local function IndexOf(list, id)
  for i, other in ipairs(list) do
    if other == id then return i end
  end
end

-- what is open: { page, kind, index (nil: adding), anchorOf(index) = the frame to stand under, query }
local state
local window

-- The tiles ("tiles") or title cards ("cards") a page shows, in their order
function P.List(pageKey, kind)
  return KINDS[kind].list(PageOf(pageKey))
end

-- Whether the row has no room for another entry
function P.Full(pageKey, kind)
  return #P.List(pageKey, kind) >= KINDS[kind].max
end

local function Save(page, kind, list)
  local settings = ns.Settings()
  if type(settings[kind.setting]) ~= "table" then settings[kind.setting] = {} end
  settings[kind.setting][page.key] = list
  local view = UI.TabView("fame")
  if view and view.Refresh then ns.SafeCall(view.Refresh, view) end -- the tab shows it at once
end

-- The page's tiles and title cards as Guildy ships them
function P.Restore(pageKey)
  local settings = ns.Settings()
  for _, kind in pairs(KINDS) do
    if type(settings[kind.setting]) == "table" then
      settings[kind.setting][pageKey] = nil
      if next(settings[kind.setting]) == nil then settings[kind.setting] = nil end
    end
  end
end

-- What can go into the place that is open: everything the row does not show yet that matches the
-- search (a part of its name, or of the page or category it comes from)
function P.Items()
  if not state then return {} end
  Index()
  local page, kind = PageOf(state.page), KINDS[state.kind]
  local list = kind.list(page)
  local query = (state.query or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
  local items = {}
  for _, id in ipairs(kind.choices(page)) do
    if not IndexOf(list, id) then
      -- from: the other page it stands on, else its category among all statistics
      local home, from = homeOf[id], nil
      if home then
        if home ~= page then from = ns.L["FAME_PAGE_" .. home.key:upper()] end
      elseif state.kind == "tiles" then
        from = UI.Fame.CategoryName(id)
      end
      local name = kind.name(id)
      if query == "" or (name .. " " .. (from or "")):lower():find(query, 1, true) then
        items[#items + 1] = { id = id, name = name, from = from }
      end
    end
  end
  return items
end

-- Puts an entry into the open place (in the place of what stood there, or at the end when adding)
function P.Choose(id)
  if not state then return end
  local page, kind = PageOf(state.page), KINDS[state.kind]
  local list = kind.list(page)
  if IndexOf(list, id) then return end
  if state.index then
    if not list[state.index] then return end
    list[state.index] = id
  else
    if #list >= kind.max then return end
    list[#list + 1] = id
  end
  P.Hide()
  Save(page, kind, list)
end

-- Moves the open tile one place to the left (-1) or right (1); the list stays open with it
function P.Move(delta)
  if not (state and state.index) then return end
  local page, kind = PageOf(state.page), KINDS[state.kind]
  local list = kind.list(page)
  local to = state.index + delta
  if not list[state.index] or to < 1 or to > #list then return end
  list[state.index], list[to] = list[to], list[state.index]
  state.index = to
  Save(page, kind, list)
  P.Refresh()
end

-- Takes the open tile away (a row keeps at least one)
function P.Remove()
  if not (state and state.index) then return end
  local page, kind = PageOf(state.page), KINDS[state.kind]
  local list = kind.list(page)
  if not list[state.index] or #list <= 1 then return end
  table.remove(list, state.index)
  P.Hide()
  Save(page, kind, list)
end

local function Build()
  local L = ns.L
  window = W.Box(UIParent, 0.05, 0.96)
  window:Hide()
  window:SetSize(WIDTH, HEIGHT)
  window:SetFrameStrata("DIALOG")
  if window.SetToplevel then window:SetToplevel(true) end
  window:EnableMouse(true)
  window:SetClampedToScreen(true)
  window.Title = W.Text(window, "GameFontNormal")
  window.Title:SetPoint("TOPLEFT", 10, -10)
  window.Title:SetPoint("RIGHT", -34, 0)
  window.Title:SetJustifyH("LEFT")
  window.Title:SetWordWrap(false)
  window.Close = W.Button(window, "x", function() P.Hide() end, 24, { small = true, pad = 10 })
  window.Close:SetPoint("TOPRIGHT", -4, -4)
  -- what to do with the tile itself
  window.Left = W.Button(window, L.OPTIONS_TILE_LEFT, function() P.Move(-1) end, 80, { small = true })
  window.Left:SetPoint("TOPLEFT", 8, -32)
  window.Right = W.Button(window, L.OPTIONS_TILE_RIGHT, function() P.Move(1) end, 80, { small = true })
  window.Right:SetPoint("LEFT", window.Left, "RIGHT", 4, 0)
  window.RemoveButton = W.Button(window, L.OPTIONS_TILE_REMOVE, function() P.Remove() end, 80, { small = true })
  window.RemoveButton:SetPoint("LEFT", window.Right, "RIGHT", 4, 0)
  local search = W.EditBox(window, WIDTH - 28)
  search.Hint = W.Text(search, "GameFontDisableSmall", L.OPTIONS_TILES_SEARCH)
  search.Hint:SetPoint("LEFT", 2, 0)
  search:SetScript("OnTextChanged", function(self)
    if not state then return end
    state.query = self:GetText() or ""
    self.Hint:SetShown(state.query == "")
    P.Refresh()
  end)
  search:SetScript("OnEnterPressed", search.ClearFocus)
  window.Search = search
  local box = W.Box(window, 0.03, 0.4)
  window.ListBox = box
  window.List = W.ScrollList(box, 20, function(row)
    row:EnableMouse(true)
    row.Text = W.Text(row, "GameFontHighlightSmall")
    row.Text:SetPoint("LEFT", 6, 0)
    row.Text:SetPoint("RIGHT", -4, 0)
    row.Text:SetWordWrap(false)
    local highlight = row:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints()
    highlight:SetColorTexture(1, 0.82, 0, 0.1)
    row:SetScript("OnMouseUp", function(self) if self.id then P.Choose(self.id) end end)
    -- the page an entry comes from, and for a title its statistic
    row:SetScript("OnEnter", function(self)
      if not (self.id and state) then return end
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      GameTooltip:SetText(self.name, 1, 1, 1)
      local fame = state.kind == "cards" and titleOf[self.id]
      if fame then GameTooltip:AddLine(UI.Fame.TileName(fame.stat), 0.8, 0.8, 0.8, true) end
      if self.from then GameTooltip:AddLine(self.from, 0.6, 0.6, 0.6) end
      GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
  end, function(row, item)
    row.id, row.name, row.from = item.id, item.name, item.from
    row.Text:SetText(item.name .. (item.from and ("  |cff8f8268" .. item.from .. "|r") or ""))
  end)
  window.List:SetPoint("TOPLEFT", 4, -4)
  window.List:SetPoint("BOTTOMRIGHT", -26, 4)
end

-- The list as what is open asks for
function P.Refresh()
  if not (state and window) then return end
  local L = ns.L
  local kind = KINDS[state.kind]
  local list = kind.list(PageOf(state.page))
  local current = state.index and list[state.index]
  if state.index and not current then return P.Hide() end -- (the tile is gone)
  window.Title:SetText(current and kind.name(current) or L[kind.more])
  for _, button in ipairs({ window.Left, window.Right, window.RemoveButton }) do button:SetShown(current ~= nil) end
  if current then
    window.Left:SetEnabled(state.index > 1)
    window.Right:SetEnabled(state.index < #list)
    window.RemoveButton:SetEnabled(#list > 1)
  end
  local top = current and -60 or -34
  window.Search:ClearAllPoints()
  window.Search:SetPoint("TOPLEFT", 14, top)
  window.ListBox:ClearAllPoints()
  window.ListBox:SetPoint("TOPLEFT", 8, top - 26)
  window.ListBox:SetPoint("BOTTOMRIGHT", -8, 8)
  window.List:SetItems(P.Items())
  -- right under what it changes (the tile may have moved)
  local anchor = state.anchorOf and state.anchorOf(state.index)
  window:ClearAllPoints()
  if anchor then
    window:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -4)
    -- as large as Guildy shows itself (the window hangs under the screen, not under Guildy)
    local own = anchor.GetEffectiveScale and anchor:GetEffectiveScale()
    local base = UIParent.GetEffectiveScale and UIParent:GetEffectiveScale()
    if window.SetScale and type(own) == "number" and type(base) == "number" and own > 0 and base > 0 then window:SetScale(own / base) end
  else
    window:SetPoint("CENTER", UI.frame or UIParent, "CENTER", 0, 0)
  end
end

-- Opens the list for one tile or title card of a page (kind: "tiles" or "cards"; index: its place in
-- the row, nil to add one at the end). anchorOf(index) gives the frame it stands under.
-- A second click on what is open closes it.
function P.Open(pageKey, kind, index, anchorOf)
  if not KINDS[kind] then return end
  if state and state.page == pageKey and state.kind == kind and state.index == index then return P.Hide() end
  if not index and P.Full(pageKey, kind) then return end
  if not window then Build() end
  Index()
  state = { page = pageKey, kind = kind, index = index, anchorOf = anchorOf, query = "" }
  window.Search:SetText("")
  window.Search.Hint:Show()
  window:Show()
  P.Refresh()
end

function P.Hide()
  if not state then return end
  state = nil
  if window then window:Hide() end
  local view = UI.TabView("fame")
  if view and view.LayoutHandles then view:LayoutHandles() end -- (no tile is marked as open any more)
end

-- The tab shows a page (nil: none to change tiles on): a list open for another one closes
function P.Follow(pageKey)
  if state and state.page ~= pageKey then P.Hide() end
end

-- What is open ({ page, kind, index }), nil while the list is closed; and the window once it was built
function P.State()
  return state, window
end
