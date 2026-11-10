-- Guildy's options ("Customize Guildy"): a window of its own beside Guildy's, so a change shows in
-- Guildy at once; opened by the cog left of the close button. Its tabs are named like Guildy's own and
-- each holds what can be changed on that tab (chat, members, Hall of Fame, professions); "General" holds
-- what belongs to none of them (member tooltip, resetting everything, Blizzard's own window).
-- Everything here is the player's own and lives in settings; the guild's settings stay on the info tab.
local _, ns = ...
local W = ns.Widgets
local UI = ns.UI

local WIDTH, HEIGHT = 560, 620
local PREVIEW_ROW = 18 -- the member list's row height
-- who the previews show
-- (level, name, class, online, days offline)
local SAMPLE = {
  { 37, "Ran Fred", "DRUID", true },
  { 34, "Naughty One", "WARRIOR", true },
  { 42, "Syd Syd", "SHAMAN", false, 1 },
  { 35, "Maerith Withersong", "PRIEST", false, 3 },
}
local CARD_W = math.floor((WIDTH - 26 - 12) / 3) -- three style cards across the window

local options

-- The views that show what the options change, when they are built
local function RefreshTab(key, layout)
  local view = UI.TabView(key)
  if not view then return end
  if layout and view.Layout then ns.SafeCall(view.Layout, view) end
  if view.Refresh then ns.SafeCall(view.Refresh, view) end
end

-- false for an unticked box, nil for a ticked one: settings only store what differs from the default
local function Off(check)
  if check:GetChecked() then return nil end
  return false
end

local function Check(parent, label, onClick)
  local check = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
  check:SetSize(24, 24)
  check:SetScript("OnClick", onClick)
  check.Label = W.Text(parent, "GameFontHighlightSmall", label)
  check.Label:SetPoint("LEFT", check, "RIGHT", 2, 0)
  return check
end

-- language ---------------------------------------------------------------------------------------------
-- The language of Guildy's own texts: nil follows the client. Most texts are set once when the window
-- is built, so a change of the language in force loads the interface anew. Should the client refuse
-- that (it blocks a reload outside a click), a chat line asks for /reload.
local function ClientLanguage()
  return ns.Locale.Resolve(nil, rawget(_G, "GetLocale") and GetLocale() or nil)
end

function UI.SetLanguage(code)
  if code ~= nil and ns.Locale.Resolve(code, "enUS") ~= code then code = nil end -- no such language
  ns.Settings().language = code
  if ns.Locale.Resolve(code, ClientLanguage()) ~= ns.Locale.current then
    ns.ReloadUI()
    C_Timer.After(1, function() ns.Print(ns.L.OPTIONS_LANGUAGE_RELOAD) end) -- still here: not reloaded
  elseif options and options.Panels and options.Panels.general then
    options.Panels.general:Refresh()
  end
end

local function LanguageText(code)
  if code then return ns.Locale.NAMES[code] or code end
  return ns.L.OPTIONS_LANGUAGE_AUTO:format(ns.Locale.NAMES[ClientLanguage()])
end

-- The menu: automatic first, then every language under its own name (never translated: whoever
-- landed in a language they cannot read finds theirs again)
function UI.LanguageItems()
  local chosen = ns.Settings().language
  local items = { { text = LanguageText(nil), checked = chosen == nil, onClick = function() UI.SetLanguage(nil) end } }
  for _, code in ipairs(ns.Locale.Languages()) do
    items[#items + 1] = { text = LanguageText(code), checked = chosen == code,
      onClick = function() UI.SetLanguage(code) end }
  end
  return items
end

-- general ----------------------------------------------------------------------------------------------
local function BuildGeneral(panel)
  local L = ns.L
  local about = W.Box(panel)
  about:SetPoint("TOPLEFT", 0, 0)
  about:SetPoint("TOPRIGHT", 0, 0)
  about:SetHeight(64)
  local icon = W.Icon(about, 40)
  icon.Border:SetPoint("LEFT", 12, 0)
  icon:SetTexture(W.LOGO)
  local name = W.Text(about, "GameFontNormalLarge", "Guildy")
  name:SetPoint("TOPLEFT", icon.Border, "TOPRIGHT", 12, -4)
  local getMeta = (C_AddOns and C_AddOns.GetAddOnMetadata) or rawget(_G, "GetAddOnMetadata")
  local author = getMeta and getMeta(ns.ADDON, "Author") or "Conoar"
  local version = W.Text(about, "GameFontHighlightSmall", L.OPTIONS_ABOUT:format(ns.Version(), author or "Conoar"))
  version:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -6)

  -- where a member's tooltip stands
  local tooltipLabel = W.Text(panel, "GameFontHighlightSmall", L.OPTIONS_TOOLTIP)
  tooltipLabel:SetPoint("TOPLEFT", about, "BOTTOMLEFT", 8, -22)
  panel.Tooltip = W.MenuButton(panel, "", function()
    local items = {}
    for _, mode in ipairs(UI.TOOLTIP_ANCHORS) do
      items[#items + 1] = { text = L["OPTIONS_TOOLTIP_" .. mode:upper()], checked = UI.TooltipAnchor() == mode,
        onClick = function()
          ns.Settings().tooltipAnchor = mode
          panel:Refresh()
        end }
    end
    return items
  end, 190, 240)
  panel.Tooltip:SetPoint("LEFT", tooltipLabel, "RIGHT", 10, 0)

  -- Guildy's language, under the tooltip choice and in line with it
  local languageLabel = W.Text(panel, "GameFontHighlightSmall", L.OPTIONS_LANGUAGE)
  languageLabel:SetPoint("TOPLEFT", tooltipLabel, "BOTTOMLEFT", 0, -24)
  panel.Language = W.MenuButton(panel, "", UI.LanguageItems, 190, 240)
  panel.Language:SetPoint("LEFT", panel.Tooltip, "LEFT", 0, 0)
  panel.Language:SetPoint("TOP", languageLabel, "TOP", 0, 6)
  W.Tooltip(panel.Language, L.OPTIONS_LANGUAGE, L.OPTIONS_LANGUAGE_TIP)

  local blizzard = W.Button(panel, L.OPEN_BLIZZARD, function()
    options:Hide()
    UI.ShowBlizzard()
  end, 170, { small = true })
  blizzard:SetPoint("TOPLEFT", languageLabel, "BOTTOMLEFT", -2, -30)

  -- everything this window changes back to what Guildy ships (sharing is not a look: it stays)
  local reset = W.Button(panel, L.OPTIONS_RESET_ALL, function()
    local settings = ns.Settings()
    settings.memberStyle, settings.fameTiles, settings.fameCards = nil, nil, nil
    settings.memberColumns, settings.memberTwinks, settings.chatProfs, settings.tooltipAnchor = nil, nil, nil, nil
    panel:Refresh()
    RefreshTab("members")
    RefreshTab("chat")
    RefreshTab("fame", true)
  end, 170, { small = true })
  reset:SetPoint("LEFT", blizzard, "RIGHT", 8, 0)
  W.Tooltip(reset, L.OPTIONS_RESET_ALL, L.OPTIONS_RESET_ALL_TIP)

  function panel:Refresh()
    self.Tooltip:SetText(L["OPTIONS_TOOLTIP_" .. UI.TooltipAnchor():upper()])
    self.Language:SetText(LanguageText(ns.Settings().language))
  end
end

-- members: online style ----------------------------------------------------------------------------------
-- One card per style: its name, a line on what it does, and four sample rows drawn the way the list
-- draws them. The chosen card has the gold border and the check mark.
local function BuildStyle(panel)
  local L = ns.L
  panel.Cards = {}
  for i, style in ipairs(UI.MEMBER_STYLES) do
    local sections = style == "sections"
    -- three cards side by side: name and a line on what the style does, the preview under it
    local card = W.Box(panel, 0.08, 0.5)
    card:SetSize(CARD_W, 212)
    card:SetPoint("TOPLEFT", (i - 1) * (CARD_W + 6), 0)
    card.style = style
    card.Mark = card:CreateTexture(nil, "ARTWORK")
    card.Mark:SetSize(18, 18)
    card.Mark:SetPoint("TOPLEFT", 10, -10)
    card.Mark:SetTexture(W.ICON_YES)
    card.Title = W.Text(card, "GameFontNormal", L["OPTIONS_STYLE_" .. style:upper()])
    card.Title:SetPoint("TOPLEFT", 34, -12)
    card.Text = W.Text(card, "GameFontHighlightSmall", L["OPTIONS_STYLE_" .. style:upper() .. "_TEXT"])
    card.Text:SetPoint("TOPLEFT", card.Title, "BOTTOMLEFT", 0, -6)
    card.Text:ClearAllPoints()
    card.Text:SetPoint("TOPLEFT", 10, -34)
    card.Text:SetWidth(CARD_W - 20)
    card.Text:SetSpacing(3)

    -- the preview: a dark inner box with the sample rows
    local preview = W.Box(card, 0.04, 0.35)
    preview:SetPoint("TOPLEFT", 8, -86)
    preview:SetPoint("BOTTOMRIGHT", -8, 8)
    -- rows built like the list's own: same height, font, stripes, colors and section headers
    local index = 0
    local function Row()
      index = index + 1
      local row = CreateFrame("Frame", nil, preview)
      row:SetHeight(PREVIEW_ROW)
      row:SetPoint("TOPLEFT", 4, -5 - (index - 1) * PREVIEW_ROW)
      row:SetPoint("RIGHT", -4, 0)
      if index % 2 == 0 then
        local stripe = row:CreateTexture(nil, "BACKGROUND")
        stripe:SetAllPoints()
        stripe:SetColorTexture(1, 1, 1, 0.03)
      end
      return row
    end
    local function Header(text, online)
      local row = Row()
      local label = W.Text(row, "GameFontNormalSmall", text)
      label:SetPoint("LEFT", 4, 0)
      if online then label:SetTextColor(0.3, 0.9, 0.3) else label:SetTextColor(0.6, 0.6, 0.6) end
      local line = row:CreateTexture(nil, "ARTWORK")
      line:SetHeight(1)
      line:SetPoint("LEFT", label, "RIGHT", 8, 0)
      line:SetPoint("RIGHT", row, "RIGHT", -4, 0)
      line:SetColorTexture(1, 1, 1, 0.12)
    end
    local shownOffline = false
    if sections then Header(L.SECTION_ONLINE:format(2), true) end
    for _, sample in ipairs(SAMPLE) do
      local level, who, classFile, online, days = sample[1], sample[2], sample[3], sample[4], sample[5]
      if sections and not online and not shownOffline then
        shownOffline = true
        Header(L.OFFLINE_N:format(2), false)
      end
      local row = Row()
      local grey = online and 1 or 0.6
      local levelText = W.Text(row, "GameFontHighlightSmall", tostring(level))
      levelText:SetPoint("LEFT", 2, 0)
      levelText:SetWidth(18)
      levelText:SetTextColor(grey, grey, grey)
      local text, alpha = UI.MemberNameText(ns.Anon.Name(who), classFile, online, style)
      local nameText = W.Text(row, "GameFontHighlightSmall", text)
      nameText:SetPoint("LEFT", 22, 0)
      nameText:SetWidth(84)
      nameText:SetWordWrap(false)
      nameText:SetAlpha(alpha)
      local when = W.Text(row, "GameFontHighlightSmall", ns.Roster.LastOnlineText({ online = online, daysOffline = days }))
      when:SetPoint("RIGHT", -2, 0)
      when:SetJustifyH("RIGHT")
      if online then when:SetTextColor(0.3, 0.9, 0.3) else when:SetTextColor(0.6, 0.6, 0.6) end
    end

    card:EnableMouse(true)
    local hover = card:CreateTexture(nil, "HIGHLIGHT")
    hover:SetPoint("TOPLEFT", 3, -3)
    hover:SetPoint("BOTTOMRIGHT", -3, 3)
    hover:SetColorTexture(1, 0.82, 0, 0.06)
    card:SetScript("OnMouseUp", function(self)
      ns.Settings().memberStyle = self.style
      panel:Refresh()
      RefreshTab("members")
    end)
    panel.Cards[i] = card
  end

  function panel:Refresh()
    local chosen = UI.MemberStyle()
    for _, card in ipairs(self.Cards) do
      local on = card.style == chosen
      card.Mark:SetShown(on)
      if card.SetBackdropBorderColor then
        local shade = on and 1 or 0.5
        card:SetBackdropBorderColor(W.GOLD[1] * shade, W.GOLD[2] * shade, W.GOLD[3] * shade)
      end
    end
  end
end

-- members: columns and twinks ----------------------------------------------------------------------------
local function BuildColumns(panel)
  local L = ns.L
  local head = W.Text(panel, "GameFontNormal", L.OPTIONS_COLUMNS_HEAD)
  head:SetPoint("TOPLEFT", 4, -2)
  local fixed = W.Text(panel, "GameFontDisableSmall", L.OPTIONS_COLUMNS_FIXED)
  fixed:SetPoint("LEFT", head, "RIGHT", 10, 0)

  local box = W.Box(panel)
  box:SetPoint("TOPLEFT", 0, -24)
  box:SetPoint("RIGHT", 0, 0)
  box:SetHeight(20 + math.ceil(#UI.MEMBER_COLUMNS / 2) * 26)
  panel.Columns = {}
  local perColumn = math.ceil(#UI.MEMBER_COLUMNS / 2)
  for i, key in ipairs(UI.MEMBER_COLUMNS) do
    local check = Check(box, L["COL_" .. key:upper()], function(self)
      local settings = ns.Settings()
      if type(settings.memberColumns) ~= "table" then settings.memberColumns = {} end
      settings.memberColumns[key] = Off(self)
      RefreshTab("members")
    end)
    check.key = key
    check:SetPoint("TOPLEFT", 10 + math.floor((i - 1) / perColumn) * 262, -10 - ((i - 1) % perColumn) * 26)
    panel.Columns[i] = check
  end

  panel.Twinks = Check(panel, L.OPTIONS_TWINKS, function(self)
    ns.Settings().memberTwinks = Off(self)
    RefreshTab("members")
  end)
  panel.Twinks:SetPoint("TOPLEFT", box, "BOTTOMLEFT", 6, -14)
  local twinksTip = W.Text(panel, "GameFontDisableSmall", L.OPTIONS_TWINKS_TIP)
  twinksTip:SetPoint("TOPLEFT", panel.Twinks, "BOTTOMLEFT", 26, -2)
  twinksTip:SetPoint("RIGHT", -12, 0)

  function panel:Refresh()
    local settings = ns.Settings()
    local hidden = type(settings.memberColumns) == "table" and settings.memberColumns or {}
    for _, check in ipairs(self.Columns) do check:SetChecked(hidden[check.key] ~= false) end
    self.Twinks:SetChecked(settings.memberTwinks ~= false)
  end
end

-- members ------------------------------------------------------------------------------------------------
-- Everything about the member list on one page: its columns and twinks, under them how it tells
-- online from offline (cards with a preview)
local function BuildMembers(panel)
  local L = ns.L
  local columns = CreateFrame("Frame", nil, panel)
  columns:SetPoint("TOPLEFT", 0, 0)
  columns:SetPoint("RIGHT", 0, 0)
  columns:SetHeight(216)
  BuildColumns(columns)
  local head = W.Text(panel, "GameFontNormal", L.OPTIONS_STYLE_HEAD)
  head:SetPoint("TOPLEFT", columns, "BOTTOMLEFT", 4, -4)
  local style = CreateFrame("Frame", nil, panel)
  style:SetPoint("TOPLEFT", head, "BOTTOMLEFT", -4, -8)
  style:SetPoint("BOTTOMRIGHT", 0, 0)
  BuildStyle(style)
  panel.Parts = { columns = columns, style = style }
  panel.Cards = style.Cards
  panel.Columns, panel.Twinks = columns.Columns, columns.Twinks

  function panel:Refresh()
    for _, part in pairs(self.Parts) do part:Refresh() end
  end
end

-- chat ---------------------------------------------------------------------------------------------------
local function BuildChat(panel)
  local L = ns.L
  local head = W.Text(panel, "GameFontNormal", L.OPTIONS_CHAT_HEAD)
  head:SetPoint("TOPLEFT", 4, -2)
  panel.ChatProfs = Check(panel, L.OPTIONS_CHAT_PROFS, function(self)
    ns.Settings().chatProfs = Off(self)
    RefreshTab("chat")
  end)
  panel.ChatProfs:SetPoint("TOPLEFT", head, "BOTTOMLEFT", 2, -8)
  local tip = W.Text(panel, "GameFontDisableSmall", L.OPTIONS_CHAT_PROFS_TIP)
  tip:SetPoint("TOPLEFT", panel.ChatProfs, "BOTTOMLEFT", 26, -2)
  tip:SetPoint("RIGHT", -12, 0)

  function panel:Refresh()
    self.ChatProfs:SetChecked(ns.Settings().chatProfs ~= false)
  end
end

-- professions --------------------------------------------------------------------------------------------
local function BuildProfessions(panel)
  local L = ns.L
  local head = W.Text(panel, "GameFontNormal", L.OPTIONS_SHARE_HEAD)
  head:SetPoint("TOPLEFT", 4, -2)
  panel.Share = Check(panel, L.SHARE, function(self) ns.Settings().share = self:GetChecked() and true or false end)
  panel.Share:SetPoint("TOPLEFT", head, "BOTTOMLEFT", 2, -8)
  local tip = W.Text(panel, "GameFontDisableSmall", L.SHARE_TIP)
  tip:SetPoint("TOPLEFT", panel.Share, "BOTTOMLEFT", 26, -2)
  tip:SetPoint("RIGHT", -12, 0)

  function panel:Refresh()
    self.Share:SetChecked(ns.Settings().share and true or false)
  end
end

-- Hall of Fame pages ------------------------------------------------------------------------------------
-- An editor per page for its two rows on top, one under the other: the tiles (guild totals) and the
-- title cards (who holds a title), each drawn as the page shows it. A click picks an entry, the buttons
-- under the rows move or remove it; the two lists below hold what else can go into each row (the
-- page's own first, then the other pages'), a click adds. "Restore defaults" brings the page back to
-- what Guildy ships.
local function BuildFame(panel)
  local L = ns.L
  local S = ns.Stats
  local head = W.Text(panel, "GameFontNormal", L.OPTIONS_TILES_HEAD)
  head:SetPoint("TOPLEFT", 4, -2)

  local pages = {}
  for i, page in ipairs(S.PAGES) do pages[i] = { value = page.key, text = L["FAME_PAGE_" .. page.key:upper()] } end
  panel.page, panel.kind = S.PAGES[1].key, "tiles"
  panel.Pages = W.Segmented(panel, pages, function(value)
    panel.page, panel.selected = value, nil
    panel:Refresh()
  end)
  panel.Pages:SetPoint("TOPLEFT", 0, -26)

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
  local function Saved(setting, page)
    local saved = ns.Settings()[setting]
    return type(saved) == "table" and saved[page.key] or nil
  end
  -- the two rows a page has: what it shows now (ids), what it could show, how an id reads, and where
  -- its preview stands
  local KINDS = {
    tiles = {
      setting = "fameTiles", max = S.MAX_TILES, label = L.OPTIONS_KIND_TILES, more = L.OPTIONS_TILES_MORE,
      top = -58, height = 84, slotHeight = 68,
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
      top = -170, height = 88, slotHeight = 34, perRow = 4,
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
    RefreshTab("fame", true)
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
    RefreshTab("fame", true)
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
    self.Pages:SetValue(self.page)
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

-- window -------------------------------------------------------------------------------------------------
local function Build()
  local L = ns.L
  local host = UI.frame
  -- A window of its own under UIParent, not a child of Guildy's: as a child its border and title bar
  -- were drawn at levels that mixed with Guildy's own (found in game 2026-11-10). One strata above
  -- Guildy's, so it lies over the window and its side tabs wherever the player drags it. It closes with
  -- Guildy (UI.HideOptions from the window's OnHide).
  options = CreateFrame("Frame", "GuildyOptions", UIParent, "ButtonFrameTemplate")
  options:Hide()
  options:SetSize(WIDTH, HEIGHT)
  options:SetFrameStrata("DIALOG")
  if options.SetToplevel then options:SetToplevel(true) end
  options:EnableMouse(true)
  options:SetMovable(true)
  options:SetClampedToScreen(true)
  options:RegisterForDrag("LeftButton")
  options:SetScript("OnDragStart", options.StartMoving)
  options:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    self.moved = true -- stays where the player put it for the session
  end)
  -- beside Guildy: right of its side tabs, else left of it, else over its right part
  function options:Place()
    if self.moved then return end
    -- Guildy's edges in UIParent's coordinates (its host may have a scale of its own)
    local own = host.GetEffectiveScale and host:GetEffectiveScale()
    local base = UIParent.GetEffectiveScale and UIParent:GetEffectiveScale()
    local scale = (type(own) == "number" and type(base) == "number" and base > 0) and own / base or 1
    local left, right = host:GetLeft(), host:GetRight()
    if left and right then left, right = left * scale, right * scale end
    local screen = UIParent.GetWidth and UIParent:GetWidth()
    self:ClearAllPoints()
    if not (left and right and screen) or screen - right >= WIDTH + 70 then
      self:SetPoint("TOPLEFT", host, "TOPRIGHT", 66, 0)
    elseif left >= WIDTH + 8 then
      self:SetPoint("TOPRIGHT", host, "TOPLEFT", -8, 0)
    else
      self:SetPoint("TOPRIGHT", host, "TOPRIGHT", -40, -70)
    end
  end
  local hidePortrait = rawget(_G, "ButtonFrameTemplate_HidePortrait")
  if hidePortrait then
    pcall(hidePortrait, options)
  else
    local portrait = options.PortraitContainer or options.portrait
    if type(portrait) == "table" and portrait.Hide then portrait:Hide() end
  end
  if rawget(_G, "ButtonFrameTemplate_HideButtonBar") then ButtonFrameTemplate_HideButtonBar(options) end
  if options.Inset then options.Inset:Hide() end
  if options.SetTitle then options:SetTitle(L.OPTIONS_TITLE) elseif options.TitleText then options.TitleText:SetText(L.OPTIONS_TITLE) end
  local close = options.CloseButton or rawget(_G, "GuildyOptionsCloseButton")
  if type(close) == "table" and close.SetScript then close:SetScript("OnClick", function() options:Hide() end) end

  local body = CreateFrame("Frame", nil, options)
  body:SetPoint("TOPLEFT", 14, -62)
  body:SetPoint("BOTTOMRIGHT", -12, 12)
  options.Panels = {}
  local tabs = {}
  for i, def in ipairs({
    -- "General", then Guildy's own tabs in their order (those that have something to change)
    { "general", L.OPTIONS_GENERAL, BuildGeneral }, { "chat", L.TAB_CHAT, BuildChat },
    { "members", L.TAB_MEMBERS, BuildMembers }, { "fame", L.TAB_FAME, BuildFame },
    { "professions", L.TAB_PROFESSIONS, BuildProfessions },
  }) do
    local panel = CreateFrame("Frame", nil, body)
    panel:SetAllPoints()
    panel:Hide()
    def[3](panel)
    options.Panels[def[1]] = panel
    tabs[i] = { value = def[1], text = def[2] }
  end
  -- tabs under the title bar, the client's own top tabs (the selected one raised and gold); toggle
  -- buttons where the client lacks the template
  local select, deselect = rawget(_G, "PanelTemplates_SelectTab"), rawget(_G, "PanelTemplates_DeselectTab")
  local resize = rawget(_G, "PanelTemplates_TabResize")
  options.TopTabs = {}
  for i, def in ipairs(tabs) do
    local ok, tab = pcall(CreateFrame, "Button", "GuildyOptionsTab" .. i, options, "PanelTopTabButtonTemplate")
    if not (ok and tab and select and deselect) then
      if ok and tab then tab:Hide() end
      options.TopTabs = nil
      break
    end
    tab:SetID(i)
    tab:SetText(def.text)
    tab.value = def.value
    tab:SetScript("OnClick", function(self) options:Select(self.value) end)
    if resize then pcall(resize, tab, 15, nil, 70) end
    if i == 1 then
      tab:SetPoint("BOTTOMLEFT", options, "TOPLEFT", 12, -54)
    else
      tab:SetPoint("BOTTOMLEFT", options.TopTabs[i - 1], "BOTTOMRIGHT", 4, 0)
    end
    options.TopTabs[i] = tab
  end
  if not options.TopTabs then
    options.Toggles = W.Segmented(options, tabs, function(value) options:Select(value) end)
    options.Toggles:SetPoint("TOPLEFT", 14, -32)
  end

  function options:Select(key)
    self.selected = key
    local toggles = rawget(self, "Toggles")
    if toggles then toggles:SetValue(key) end
    for _, tab in ipairs(rawget(self, "TopTabs") or {}) do
      pcall(tab.value == key and select or deselect, tab)
    end
    for name, panel in pairs(self.Panels) do
      panel:SetShown(name == key)
      if name == key then panel:Refresh() end
    end
  end
  options:SetScript("OnShow", function(self)
    self:Place()
    self:Select(self.selected or "general")
  end)
end

-- Opens the options, on a given page ("general", "members", "fame") or the one shown last
function UI.ShowOptions(key)
  if not UI.frame then return end
  if not options then Build() end
  if key then options.selected = key end
  options:Show()
  options:Select(options.selected or "general")
end

function UI.HideOptions()
  if options then options:Hide() end
end

function UI.ToggleOptions()
  if options and options:IsShown() then options:Hide() else UI.ShowOptions() end
end

-- The options window once it was built (tests)
function UI.Options()
  return options
end
