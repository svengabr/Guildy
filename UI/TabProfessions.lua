-- Professions tab in three parts: a rail with every profession (members, online, best skill), the members
-- of the selected profession (skill bar, recipe count, data age) and the recipe book of the selected
-- member. A search replaces members and book with the recipe results (who can craft X?).
local _, ns = ...
local W = ns.Widgets
local UI = ns.UI

local RAIL_W, BOOK_W = W.SIDE, W.SIDE -- both sidebars as wide as in every other view
local RAIL_ROW, MEMBER_ROW, RECIPE_ROW = 44, 20, 20
local BAR_W = 110
local SKILL_SCALE = W.SKILL_SCALE -- the bar's full width: highest trainer cap of the game (UI/Widgets.lua)
local BOOK_ICON = "Interface\\Icons\\INV_Misc_Book_09"
local UNKNOWN_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"
local DOT_ON, DOT_OFF = "Interface\\COMMON\\Indicator-Green", "Interface\\COMMON\\Indicator-Gray"
local GREEN, MUTED = "|cff40e040", "|cff9a8f78"

local function SourceText(src)
  local L = ns.L
  if src == "scan" or src == "self" then return L.SRC_SELF end
  if src == "link" then return L.SRC_LINK end
  if src == "note" then return L.SRC_NOTE end
  return L.SRC_RELAY
end

-- "über Guildy" for today's data, "vor 3 Tg. · über Guildy" for older (amber after a week)
local function DataText(prof)
  if prof.src == "note" then return SourceText(prof.src) end
  local days = type(prof.ts) == "number" and math.floor((ns.Now() - prof.ts) / 86400) or nil
  if not days then return SourceText(prof.src) end
  if days <= 0 then return SourceText(prof.src) end
  local age = ns.L.DAYS_AGO:format(days)
  if days > 7 then age = "|cffff9f2e" .. age .. "|r" end
  return age .. " · " .. SourceText(prof.src)
end

-- Icon of a recipe: the made item's icon from a recipe book read earlier. Without one, the recipe spell's
-- icon, unless that is a stand-in (a "W", a blue swirl, the question mark ... different per profession):
-- then the profession's icon.
local KNOWN_PLACEHOLDERS = {
  [136235] = true, [134400] = true,
  ["interface\\icons\\temp"] = true, ["interface\\icons\\inv_misc_questionmark"] = true,
}
local iconCache = {}  -- spellID -> icon as the client gives it (false: none)
local placeholders    -- skillLine -> set of stand-in icons; rebuilt on every refresh

local function RawIcon(spellID)
  if iconCache[spellID] == nil then
    local get = (C_Spell and C_Spell.GetSpellTexture) or rawget(_G, "GetSpellTexture")
    local icon = get and ns.Try(get, spellID)
    iconCache[spellID] = icon or false
  end
  return iconCache[spellID] or nil
end

-- stand-in icons per profession, from all recipes of the guild
local function Placeholders()
  if placeholders then return placeholders end
  placeholders = {}
  local guild = ns.GuildData()
  local seen = {}
  for _, record in pairs(guild and guild.members or {}) do
    for skillLine, prof in pairs(record.profs or {}) do
      seen[skillLine] = seen[skillLine] or {}
      for _, spellID in ipairs(prof.recipes or {}) do seen[skillLine][spellID] = true end
    end
  end
  for skillLine, spells in pairs(seen) do
    local icons = {}
    for spellID in pairs(spells) do
      local icon = RawIcon(spellID)
      if icon then icons[#icons + 1] = icon end
    end
    placeholders[skillLine] = ns.Professions.PlaceholderIcons(icons)
  end
  return placeholders
end

local function SpellIcon(spellID, skillLine)
  local made = ns.TradeSkill.RecipeIcon(spellID)
  if made then return made end
  local icon = RawIcon(spellID)
  local key = type(icon) == "string" and icon:lower() or icon
  local standIns = Placeholders()[skillLine]
  if icon and not KNOWN_PLACEHOLDERS[key] and not (standIns and standIns[icon]) then return icon end
  return ns.Professions.ICONS[skillLine] or UNKNOWN_ICON
end

local function InsertRecipeLink(spellID)
  local getLink = (C_Spell and C_Spell.GetSpellLink) or rawget(_G, "GetSpellLink")
  local link = getLink and ns.Try(getLink, spellID)
  local insert = rawget(_G, "ChatEdit_InsertLink") or (ChatFrameUtil and ChatFrameUtil.InsertLink)
  if link and insert then pcall(insert, link) end
end

-- Search results: names in a recipe's tooltip before "+N more"
local RESULT_TIP_NAMES = 12

-- Opens a crafter's recipe book (online, same shard) or whispers them
local function ReachMember(m, skillLine)
  if not m then return end
  if ns.TradeSkill.CanOpenBook(m) then
    ns.TradeSkill.OpenBook(m, skillLine)
  else
    UI.Whisper(m.fullName)
  end
end

-- A click on a recipe in the search results: the first crafter whose book opens, else the first one
-- online (whisper), else the first one
local function ReachCrafter(group)
  local first, online
  for _, e in ipairs(group.entries) do
    local m = ns.Roster.Find(e.memberKey)
    if m then
      if ns.TradeSkill.CanOpenBook(m) then
        ns.TradeSkill.OpenBook(m, group.skillLine)
        return
      end
      first = first or m
      if m.online and not online then online = m end
    end
  end
  ReachMember(online or first, group.skillLine)
end

-- Right click on a recipe in the search results: every crafter, a click reaches them
local function CraftersMenu(anchor, group)
  local items = { { text = group.recipeName, isTitle = true } }
  for _, e in ipairs(group.entries) do
    local m = ns.Roster.Find(e.memberKey)
    if m then
      items[#items + 1] = {
        text = W.ClassName(m.name, m.classFile) .. (m.online and ("  |cff4ce64c" .. ns.L.ONLINE .. "|r") or ""),
        onClick = function() ReachMember(m, group.skillLine) end,
      }
    end
  end
  W.OpenMenu(anchor, items, 220)
end

-- One entry per profession somebody has: its members (online first, skill desc, name) and the numbers
-- for the rail
local function Groups()
  local guild = ns.GuildData()
  local groups = {}
  if not guild then return groups end
  for _, skillLine in ipairs(ns.Professions.ORDER) do
    local members, online, best, books = {}, 0, nil, 0
    for key, record in pairs(guild.members) do
      local prof = record.profs and record.profs[skillLine]
      local m = prof and ns.Roster.Find(key)
      if m then
        members[#members + 1] = { member = m, prof = prof }
        if m.online then online = online + 1 end
        if prof.rank and (not best or prof.rank > best) then best = prof.rank end
        if prof.recipes and #prof.recipes > 0 then books = books + 1 end
      end
    end
    if #members > 0 then
      table.sort(members, function(a, b)
        if a.member.online ~= b.member.online then return a.member.online end
        local ra, rb = a.prof.rank or -1, b.prof.rank or -1
        if ra ~= rb then return ra > rb end
        return a.member.name < b.member.name
      end)
      groups[#groups + 1] = { skillLine = skillLine, members = members, online = online, best = best, books = books }
    end
  end
  return groups
end

local function SkillBar(parent)
  return W.SkillBar(parent, BAR_W)
end

local dotTextures
local function Dot(parent)
  if dotTextures == nil then dotTextures = W.TextureExists(DOT_ON) and W.TextureExists(DOT_OFF) end
  local dot = parent:CreateTexture(nil, "ARTWORK")
  dot:SetSize(12, 12)
  function dot:SetOnline(on)
    if dotTextures then
      self:SetTexture(on and DOT_ON or DOT_OFF)
    else -- small square in the client's online green / grey
      self:SetSize(6, 6)
      if on then self:SetColorTexture(0.25, 0.88, 0.25, 1) else self:SetColorTexture(0.4, 0.4, 0.4, 1) end
    end
    self:SetAlpha(on and 1 or 0.6)
  end
  return dot
end

local function Build(panel)
  local L = ns.L
  local view = { query = "", recipeQuery = "", filter = "all", skill = nil, memberKey = nil }

  -- Menu for a member's profession: open Blizzard's recipe book, whisper, invite
  local function ProfessionMenu(anchor, m, skillLine)
    local canOpen = ns.TradeSkill.CanOpenBook(m)
    W.OpenMenu(anchor, {
      { text = W.ClassName(m.name, m.classFile) .. " · " .. ns.TradeSkill.Name(skillLine), isTitle = true },
      { text = canOpen and L.OPEN_BOOK or L.OPEN_BOOK_OFFLINE,
        disabled = not canOpen, onClick = function() ns.TradeSkill.OpenBook(m, skillLine) end },
      { text = L.WHISPER, disabled = not m.online, onClick = function() UI.Whisper(m.fullName) end },
      { text = L.GROUP_INVITE, disabled = not m.online, onClick = function() ns.Roster.GroupInvite(m) end },
    }, 230)
  end

  -- top row: search, hint, reading members --------------------------------------------------------------
  local page = W.Page(panel)
  panel = page.Body
  local search = page:Left(W.EditBox(page.Bar, W.SEARCH_W), 6)
  search.Hint = W.Text(search, "GameFontDisableSmall", L.SEARCH_RECIPES)
  search.Hint:SetPoint("LEFT", 2, 0)
  search.Hint:SetPoint("RIGHT", -2, 0)
  search.Hint:SetWordWrap(false)
  search:SetScript("OnTextChanged", function(self)
    view.query = self:GetText() or ""
    self.Hint:SetShown(view.query == "")
    view:Refresh()
  end)
  search:SetScript("OnEnterPressed", search.ClearFocus)
  -- shift-clicking an item or recipe link fills the search
  if rawget(_G, "ChatEdit_InsertLink") then
    hooksecurefunc("ChatEdit_InsertLink", function(link)
      if search:IsVisible() and search:HasFocus() and type(link) == "string" then search:SetText(link) end
    end)
  end
  view.Search = search

  view.Harvest = W.Button(page.Bar, L.HARVEST, function()
    if ns.Harvest.IsRunning() then ns.Harvest.Stop() else ns.Harvest.Start() end
  end, 150, { small = true, fit = { L.HARVEST, L.HARVEST_STOP } })
  page:Right(view.Harvest)
  W.Tooltip(view.Harvest, L.HARVEST, L.HARVEST_TIP)

  -- where the data comes from, or the number of search results: between the search and the button
  view.Info = page:Fill(W.Text(page.Bar, "GameFontDisableSmall"))

  -- status column while reading members: current look and the latest results ----------------------------
  local status = W.Box(panel)
  status:SetPoint("TOPRIGHT", 0, 0)
  status:SetPoint("BOTTOMRIGHT", 0, 0)
  status:SetWidth(BOOK_W + 100)
  status.Title = W.Text(status, "GameFontNormal", L.HARVEST_STATUS)
  status.Title:SetPoint("TOPLEFT", 10, -8)
  -- after a run: close the results to get the recipe book back (the next run shows them again)
  status.Close = CreateFrame("Button", nil, status, "UIPanelCloseButton")
  status.Close:SetSize(24, 24)
  status.Close:SetPoint("TOPRIGHT", -2, -2)
  status.Close:SetScript("OnClick", function()
    view.statusClosed = true
    view:Refresh()
  end)
  W.Tooltip(status.Close, L.HARVEST_CLOSE)
  status.Progress = W.Text(status, "GameFontHighlightSmall")
  status.Progress:SetPoint("TOPLEFT", 10, -28)
  status.Progress:SetPoint("RIGHT", -10, 0)
  -- progress bar: looks done of looks planned, with an estimate of the time left
  local bar = CreateFrame("StatusBar", nil, status)
  bar:SetPoint("TOPLEFT", status.Progress, "BOTTOMLEFT", 0, -6)
  bar:SetPoint("RIGHT", -10, 0)
  bar:SetHeight(16)
  bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
  bar:SetStatusBarColor(0.83, 0.63, 0.09)
  bar:SetMinMaxValues(0, 1)
  bar.Back = bar:CreateTexture(nil, "BACKGROUND")
  bar.Back:SetAllPoints()
  bar.Back:SetColorTexture(0, 0, 0, 0.5)
  bar.Text = W.Text(bar, "GameFontHighlightSmall")
  bar.Text:SetPoint("CENTER")
  status.Bar = bar
  status.Current = W.Text(status, "GameFontHighlight")
  status.Current:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", 0, -6)
  status.Current:SetPoint("RIGHT", -10, 0)
  status.Current:SetWordWrap(false)
  status.Hint = W.Text(status, "GameFontDisableSmall", L.HARVEST_RESULTS)
  status.Hint:SetPoint("TOPLEFT", status.Current, "BOTTOMLEFT", 0, -10)
  -- one row per member: one icon per profession looked at (bright with the recipe count = book read,
  -- faded = doesn't have it, faded with "?" = no answer), a short summary; details on hover
  local MAX_ICONS = 8
  local ICON_X = 100
  local SUMMARY_X = ICON_X + MAX_ICONS * 20 + 4

  local function LookLine(e)
    local text, note
    if e.result == "found" then
      text = GREEN .. L.HARVEST_FOUND:format(e.recipes or 0, e.rank or 0) .. "|r"
    elseif e.result == "silent" then
      text, note = "|cffff9933" .. L.HARVEST_SILENT .. "|r", L.HARVEST_DETAIL_SILENT
    elseif e.result == "absent" then
      text, note = "|cff999999" .. L.HARVEST_ABSENT .. "|r", L.HARVEST_DETAIL_ABSENT
    elseif e.result == "retry" then
      text, note = "|cffff9933" .. L.HARVEST_NO_ANSWER .. "|r", L.HARVEST_DETAIL_RETRY
    else
      text, note = "|cffff9933" .. L.HARVEST_NO_ANSWER .. "|r", L.HARVEST_DETAIL_NO_ANSWER
    end
    local line = (e.skill or "?") .. ": " .. text .. " " .. MUTED .. "(" .. tostring(e.seconds or "?") .. " s, "
      .. L.HARVEST_LOOK:format(e.look or 0, e.of or 0) .. ")|r"
    return note and (line .. "\n   " .. MUTED .. note .. "|r") or line
  end

  status.Log = W.ScrollList(status, 24, function(row)
    row.Name = W.Text(row, "GameFontHighlightSmall")
    row.Name:SetPoint("LEFT", 4, 0)
    row.Name:SetWidth(ICON_X - 8)
    row.Name:SetWordWrap(false)
    row.Icons = {}
    for i = 1, MAX_ICONS do
      local icon = row:CreateTexture(nil, "ARTWORK")
      icon:SetSize(18, 18)
      icon:SetPoint("LEFT", ICON_X + (i - 1) * 20, 0)
      icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
      icon.Mark = W.Text(row, "NumberFontNormalSmall")
      icon.Mark:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", 2, -1)
      row.Icons[i] = icon
    end
    row.Summary = W.Text(row, "GameFontHighlightSmall")
    row.Summary:SetPoint("LEFT", SUMMARY_X, 0)
    row.Summary:SetPoint("RIGHT", -4, 0)
    row.Summary:SetWordWrap(false)
    row:EnableMouse(true)
    row:SetScript("OnEnter", function(self)
      if not self.Tip then return end
      GameTooltip:SetOwner(self, "ANCHOR_LEFT")
      GameTooltip:SetText(self.TipTitle or "", 1, 0.82, 0)
      for _, line in ipairs(self.Tip) do GameTooltip:AddLine(line, 1, 1, 1, true) end
      GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
  end, function(row, item)
    for _, icon in ipairs(row.Icons) do
      icon:Hide()
      icon.Mark:SetText("")
    end
    if item.kind == "server" then
      local e = item.entry
      row.Name:SetText("|cffff9933" .. L.HARVEST_SERVER_BAD:format(tostring(e.server)) .. "|r")
      row.Name:SetWidth(SUMMARY_X - 8)
      row.Summary:SetText(MUTED .. L.HARVEST_SERVER_BAD_SHORT:format(e.skipped or 0) .. "|r")
      row.TipTitle = L.HARVEST_SERVER_BAD:format(tostring(e.server))
      row.Tip = { L.HARVEST_SERVER_BAD_DETAIL:format(e.misses or 0, e.skipped or 0) }
      return
    end
    row.Name:SetWidth(ICON_X - 8)
    row.Name:SetText(W.ClassName(item.member, item.classFile))
    local books, recipes, silent = 0, 0, 0
    local tip = {}
    for i, e in ipairs(item.looks) do
      local icon = row.Icons[i]
      if icon then
        icon:SetTexture(ns.Professions.ICONS[e.skillLine])
        icon:Show()
        local found = e.result == "found"
        icon:SetDesaturated(not found)
        icon:SetAlpha(found and 1 or 0.35)
        if found then
          icon.Mark:SetText(GREEN .. (e.recipes or 0) .. "|r")
        elseif e.result ~= "absent" then
          icon.Mark:SetText("|cffff9933?|r")
        end
      end
      if e.result == "found" then
        books, recipes = books + 1, recipes + (e.recipes or 0)
      elseif e.result ~= "absent" then
        silent = silent + 1
      end
      tip[#tip + 1] = LookLine(e)
    end
    local summary
    if books > 0 then
      summary = GREEN .. L.HARVEST_SUM_FOUND:format(recipes) .. "|r"
    elseif silent > 0 then
      summary = "|cffff9933" .. L.HARVEST_SUM_SILENT .. "|r"
    else
      summary = "|cff999999" .. L.HARVEST_SUM_NONE .. "|r"
    end
    row.Summary:SetText(summary)
    row.TipTitle = item.member .. (item.server and ("  " .. MUTED .. L.HARVEST_SERVER:format(item.server) .. "|r") or "")
    row.Tip = tip
  end)
  status.Log:SetPoint("TOPLEFT", status.Hint, "BOTTOMLEFT", -4, -4)
  status.Log:SetPoint("BOTTOMRIGHT", -26, 6)
  status:Hide()
  view.Status = status

  -- rail: one row per profession ------------------------------------------------------------------------
  local rail = W.Box(panel)
  rail:SetPoint("TOPLEFT", 0, 0)
  rail:SetPoint("BOTTOMLEFT", 0, 0)
  rail:SetWidth(RAIL_W)
  view.Rail = W.ScrollList(rail, RAIL_ROW, function(row)
    row:EnableMouse(true)
    row.Selected = row:CreateTexture(nil, "BACKGROUND")
    row.Selected:SetAllPoints()
    row.Selected:SetColorTexture(1, 0.82, 0, 0.16)
    local highlight = row:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints()
    highlight:SetColorTexture(1, 0.82, 0, 0.08)
    row.Icon = W.Icon(row, 30)
    row.Icon.Border:SetPoint("LEFT", 6, 0)
    row.Name = W.Text(row, "GameFontHighlight")
    row.Name:SetPoint("TOPLEFT", 46, -7)
    row.Name:SetPoint("RIGHT", -34, 0)
    row.Name:SetWordWrap(false)
    row.Counts = W.Text(row, "GameFontDisableSmall")
    row.Counts:SetPoint("TOPLEFT", row.Name, "BOTTOMLEFT", 0, -3)
    row.Counts:SetPoint("RIGHT", -34, 0)
    row.Counts:SetWordWrap(false)
    row.Best = W.Text(row, "GameFontDisableSmall")
    row.Best:SetPoint("RIGHT", -6, 0)
    row.Best:SetJustifyH("RIGHT")
    row:SetScript("OnMouseUp", function(self)
      if not self.group then return end
      view.skill, view.memberKey, view.recipeQuery = self.group.skillLine, nil, ""
      view.BookSearch:SetText("")
      if view.query ~= "" then view.Search:SetText("") else view:Refresh() end
    end)
  end, function(row, group)
    row.group = group
    local selected = view.query == "" and group.skillLine == view.skill
    row.Selected:SetShown(selected)
    row.Icon:SetTexture(ns.Professions.ICONS[group.skillLine])
    row.Name:SetText(ns.TradeSkill.Name(group.skillLine))
    if selected then row.Name:SetTextColor(1, 0.82, 0) else row.Name:SetTextColor(1, 1, 1) end
    row.Counts:SetText(#group.members .. "  " .. GREEN .. L.ONLINE_N:format(group.online) .. "|r")
    row.Best:SetText(group.best or "")
  end)
  view.Rail:SetPoint("TOPLEFT", 4, -4)
  view.Rail:SetPoint("BOTTOMRIGHT", -26, 4)

  -- members of the selected profession ------------------------------------------------------------------
  local members = W.Box(panel)
  members:SetPoint("TOPLEFT", rail, "TOPRIGHT", W.GAP, 0)
  view.MembersBox = members
  local header = CreateFrame("Frame", nil, members)
  header:SetPoint("TOPLEFT", 8, -8)
  header:SetPoint("RIGHT", -8, 0)
  header:SetHeight(40)
  header.Icon = W.Icon(header, 36)
  header.Icon.Border:SetPoint("LEFT", 2, 0)
  header.Title = W.Text(header, "GameFontNormalLarge")
  header.Title:SetPoint("TOPLEFT", 48, -2)
  header.Counts = W.Text(header, "GameFontHighlightSmall")
  header.Counts:SetPoint("TOPLEFT", header.Title, "BOTTOMLEFT", 0, -4)
  header.Counts:SetWordWrap(false)
  header.Filter = W.Segmented(header, {
    { value = "all", text = L.ALL }, { value = "online", text = L.FILTER_ONLINE }, { value = "book", text = L.FILTER_BOOKS },
  }, function(value)
    view.filter = value
    view:Refresh()
  end)
  header.Filter:SetPoint("RIGHT", 0, 0)
  header.Counts:SetPoint("RIGHT", header.Filter, "LEFT", -8, 0)
  view.Header = header

  local NAME_X, SKILL_X, RECIPES_X, DATA_X = 22, 182, 404, 456
  local columns = CreateFrame("Frame", nil, members)
  columns:SetPoint("TOPLEFT", 4, -54)
  columns:SetPoint("RIGHT", -26, 0)
  columns:SetHeight(16)
  local labels = {}
  for _, col in ipairs({ { L.COL_MEMBER, NAME_X }, { L.COL_SKILL, SKILL_X }, { L.COL_RECIPES, RECIPES_X }, { L.COL_DATA, DATA_X } }) do
    local label = W.Text(columns, "GameFontDisableSmall", col[1])
    label:SetPoint("LEFT", col[2], 0)
    labels[#labels + 1] = { label = label, x = col[2] }
  end
  -- a heading that doesn't fit the list any more goes (the narrow list beside the read status): the
  -- rows drop that column the same way
  columns:SetScript("OnSizeChanged", function(self, width)
    width = width or self:GetWidth() or 0
    for _, entry in ipairs(labels) do
      entry.label:SetShown(entry.x + (entry.label:GetStringWidth() or 0) <= width)
    end
  end)
  local line = columns:CreateTexture(nil, "ARTWORK")
  line:SetPoint("BOTTOMLEFT", 0, -2)
  line:SetPoint("BOTTOMRIGHT", 0, -2)
  line:SetHeight(1)
  line:SetColorTexture(W.GOLD[1], W.GOLD[2], W.GOLD[3], 0.3)
  view.Columns = columns

  view.Members = W.ScrollList(members, MEMBER_ROW, function(row)
    row:EnableMouse(true)
    row.Selected = row:CreateTexture(nil, "BACKGROUND")
    row.Selected:SetAllPoints()
    row.Selected:SetColorTexture(1, 0.82, 0, 0.18)
    local highlight = row:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints()
    highlight:SetColorTexture(1, 0.82, 0, 0.08)
    row.Dot = Dot(row)
    row.Dot:SetPoint("LEFT", 6, 0)
    row.Name = W.Text(row, "GameFontHighlightSmall")
    row.Name:SetPoint("LEFT", NAME_X, 0)
    row.Name:SetWidth(SKILL_X - NAME_X - 6)
    row.Name:SetWordWrap(false)
    row.Skill = W.Text(row, "GameFontHighlightSmall")
    row.Skill:SetPoint("LEFT", SKILL_X, 0)
    row.Skill:SetWidth(52)
    row.Skill:SetJustifyH("RIGHT")
    row.Bar = SkillBar(row)
    row.Bar:SetPoint("LEFT", SKILL_X + 58, 0)
    row.Trainer = W.Text(row, "GameFontNormalSmall", L.TRAINER)
    row.Trainer:SetPoint("LEFT", row.Bar, "RIGHT", 5, 0)
    row.Book = row:CreateTexture(nil, "ARTWORK")
    row.Book:SetSize(13, 13)
    row.Book:SetPoint("LEFT", RECIPES_X, 0)
    row.Book:SetTexture(BOOK_ICON)
    row.Book:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    row.Recipes = W.Text(row, "GameFontNormalSmall")
    row.Recipes:SetPoint("LEFT", RECIPES_X + 17, 0)
    row.Data = W.Text(row, "GameFontDisableSmall")
    row.Data:SetPoint("LEFT", DATA_X, 0)
    row.Data:SetPoint("RIGHT", -4, 0)
    row.Data:SetWordWrap(false)
    -- offline divider: one label over the whole row
    row.Divider = W.Text(row, "GameFontDisableSmall")
    row.Divider:SetPoint("LEFT", 6, 0)
    row:SetScript("OnEnter", function(self)
      local item = self.item
      if not (item and item.member) then return end
      UI.MemberTooltip(self, item.member, L.PROF_MEMBER_HINT)
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    row:SetScript("OnMouseUp", function(self, button)
      local item = self.item
      if not (item and item.member) then return end
      if button == "RightButton" then
        ProfessionMenu(self, item.member, view.skill)
        return
      end
      view.memberKey, view.recipeQuery = item.member.key, ""
      view.BookSearch:SetText("")
      view:Refresh()
    end)
  end, function(row, item)
    row.item = item
    local isMember = item.member ~= nil
    for _, part in ipairs({ row.Dot, row.Name, row.Skill, row.Bar, row.Data }) do part:SetShown(isMember) end
    row.Divider:SetShown(not isMember)
    row.Selected:SetShown(isMember and item.member.key == view.memberKey)
    if not isMember then
      row.Trainer:Hide()
      row.Book:Hide()
      row.Recipes:SetText("")
      row.Divider:SetText(L.OFFLINE_N:format(item.offline))
      return
    end
    local m, prof = item.member, item.prof
    row.Dot:SetOnline(m.online)
    row.Name:SetText(W.ClassName(m.name, m.classFile))
    row.Name:SetAlpha(m.online and 1 or 0.7)
    if prof.rank then
      row.Skill:SetText(prof.rank .. (prof.max and (MUTED .. "/" .. prof.max .. "|r") or ""))
      row.Bar:SetSkill(prof.rank, prof.max)
    else
      row.Skill:SetText(MUTED .. "–|r")
      row.Bar:Hide()
    end
    row.Trainer:SetShown(prof.rank ~= nil and prof.max ~= nil and prof.rank >= prof.max and prof.max < SKILL_SCALE)
    local count = prof.recipes and #prof.recipes or 0
    row.Book:SetShown(count > 0)
    row.Recipes:SetText(count > 0 and count or (MUTED .. "–|r"))
    row.Recipes:ClearAllPoints()
    row.Recipes:SetPoint("LEFT", count > 0 and (RECIPES_X + 17) or RECIPES_X, 0)
    row.Data:SetText(DataText(prof))
  end)
  view.Members:SetPoint("TOPLEFT", 4, -74)
  view.Members:SetPoint("BOTTOMRIGHT", -26, 4)

  view.Empty = W.Text(members, "GameFontDisable")
  view.Empty:SetPoint("TOPLEFT", 14, -84)
  view.Empty:SetPoint("RIGHT", -14, 0)
  view.Empty:SetWordWrap(true)

  -- search results (replace members and book while searching)
  view.Results = W.ScrollList(members, MEMBER_ROW, function(row)
    row:EnableMouse(true)
    local highlight = row:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints()
    highlight:SetColorTexture(1, 0.82, 0, 0.1)
    row.Icon = row:CreateTexture(nil, "ARTWORK")
    row.Icon:SetSize(16, 16)
    row.Icon:SetPoint("LEFT", 4, 0)
    row.Icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    row.Recipe = W.Text(row, "GameFontHighlightSmall")
    row.Recipe:SetPoint("LEFT", 26, 0)
    row.Recipe:SetWidth(300)
    row.Recipe:SetWordWrap(false)
    row.Dot = Dot(row)
    row.Dot:SetPoint("LEFT", 334, 0)
    row.Member = W.Text(row, "GameFontHighlightSmall")
    row.Member:SetPoint("LEFT", 350, 0)
    row.Member:SetWidth(200)
    row.Member:SetWordWrap(false)
    row.Prof = W.Text(row, "GameFontDisableSmall")
    row.Prof:SetPoint("LEFT", 556, 0)
    row.Prof:SetPoint("RIGHT", -6, 0)
    row.Prof:SetWordWrap(false)
    -- one row per recipe (Search.GroupRecipes): the first crafter (online first) and "+N" for the rest;
    -- the tooltip lists them all, a right click picks one
    row:SetScript("OnEnter", function(self)
      local group = self.group
      if not group then return end
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      if not pcall(GameTooltip.SetSpellByID, GameTooltip, group.spellID) then GameTooltip:SetText(group.recipeName or "?") end
      GameTooltip:AddLine(" ")
      GameTooltip:AddLine(L.RESULT_CRAFTERS, 1, 0.82, 0)
      for i, e in ipairs(group.entries) do
        if i > RESULT_TIP_NAMES then
          GameTooltip:AddLine(L.FAMILY_MORE:format(#group.entries - RESULT_TIP_NAMES), 0.6, 0.6, 0.6)
          break
        end
        local m = ns.Roster.Find(e.memberKey)
        local name = m and W.ClassName(m.name, m.classFile) or e.memberName
        GameTooltip:AddLine(name .. (m and m.online and ("  |cff4ce64c" .. L.ONLINE .. "|r") or ""))
      end
      GameTooltip:AddLine(" ")
      GameTooltip:AddLine(L.RESULT_CLICK_HINT, 0.6, 0.6, 0.6, true)
      GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    row:SetScript("OnMouseUp", function(self, button)
      local group = self.group
      if not group then return end
      if IsShiftKeyDown() then
        InsertRecipeLink(group.spellID)
      elseif button == "RightButton" then
        CraftersMenu(self, group)
      else
        ReachCrafter(group)
      end
    end)
  end, function(row, group)
    row.group = group
    local first = group.entries[1]
    local m = first and ns.Roster.Find(first.memberKey)
    row.Icon:SetTexture(SpellIcon(group.spellID, group.skillLine))
    row.Recipe:SetText(group.recipeName)
    row.Dot:SetOnline(group.online > 0)
    local name = m and W.ClassName(m.name, m.classFile) or (first and first.memberName) or ""
    local more = #group.entries - 1
    row.Member:SetText(more > 0 and (name .. MUTED .. "  +" .. more .. "|r") or name)
    row.Prof:SetText(ns.TradeSkill.Name(group.skillLine))
  end)
  view.Results:SetPoint("TOPLEFT", 4, -8)
  view.Results:SetPoint("BOTTOMRIGHT", -26, 4)

  -- recipe book of the selected member -----------------------------------------------------------------
  local book = W.Box(panel)
  book:SetPoint("TOPRIGHT", 0, 0)
  book:SetPoint("BOTTOMRIGHT", 0, 0)
  book:SetWidth(BOOK_W)
  view.BookBox = book
  book.Dot = Dot(book)
  book.Dot:SetPoint("TOPLEFT", 10, -11)
  book.Who = W.Text(book, "GameFontNormal")
  book.Who:SetPoint("LEFT", book.Dot, "RIGHT", 4, 0)
  book.Who:SetPoint("RIGHT", -10, 0)
  book.Who:SetWordWrap(false)
  book.Meta = W.Text(book, "GameFontHighlightSmall")
  book.Meta:SetPoint("TOPLEFT", 10, -30)
  book.Meta:SetPoint("RIGHT", -10, 0)
  book.Meta:SetWordWrap(false)
  local function Selected()
    local m = view.memberKey and ns.Roster.Find(view.memberKey)
    return m, view.skill
  end
  book.Open = W.Button(book, L.OPEN_BOOK_SHORT, function()
    local m, skillLine = Selected()
    if m and ns.TradeSkill.CanOpenBook(m) then ns.TradeSkill.OpenBook(m, skillLine) end
  end, 86, { small = true })
  book.Open:SetPoint("TOPLEFT", 8, -48)
  W.Tooltip(book.Open, L.OPEN_BOOK, L.OPEN_BOOK_TIP)
  book.Whisper = W.Button(book, L.WHISPER, function()
    local m = Selected()
    if m then UI.Whisper(m.fullName) end
  end, 76, { small = true })
  book.Whisper:SetPoint("LEFT", book.Open, "RIGHT", 4, 0)
  book.Invite = W.Button(book, L.GROUP_INVITE_SHORT, function()
    local m = Selected()
    if m then ns.Roster.GroupInvite(m) end
  end, 76, { small = true })
  book.Invite:SetPoint("LEFT", book.Whisper, "RIGHT", 4, 0)

  local bookSearch = W.EditBox(book, BOOK_W - 30)
  bookSearch:SetPoint("TOPLEFT", 16, -78)
  bookSearch.Hint = W.Text(bookSearch, "GameFontDisableSmall")
  bookSearch.Hint:SetPoint("LEFT", 2, 0)
  bookSearch:SetScript("OnTextChanged", function(self)
    view.recipeQuery = self:GetText() or ""
    self.Hint:SetShown(view.recipeQuery == "")
    view:RenderBook()
  end)
  view.BookSearch = bookSearch

  view.Recipes = W.ScrollList(book, RECIPE_ROW, function(row)
    row:EnableMouse(true)
    local highlight = row:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints()
    highlight:SetColorTexture(1, 0.82, 0, 0.1)
    row.Icon = row:CreateTexture(nil, "ARTWORK")
    row.Icon:SetSize(16, 16)
    row.Icon:SetPoint("LEFT", 4, 0)
    row.Icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    row.Name = W.Text(row, "GameFontHighlightSmall")
    row.Name:SetPoint("LEFT", 26, 0)
    row.Name:SetPoint("RIGHT", -4, 0)
    row.Name:SetWordWrap(false)
    row.Name:SetTextColor(0.85, 0.78, 0.63)
    row:SetScript("OnEnter", function(self)
      if not self.spellID then return end
      GameTooltip:SetOwner(self, "ANCHOR_LEFT")
      if not pcall(GameTooltip.SetSpellByID, GameTooltip, self.spellID) then GameTooltip:SetText(self.Name:GetText() or "?") end
      GameTooltip:AddLine(" ")
      GameTooltip:AddLine(L.RECIPE_CLICK_HINT, 0.6, 0.6, 0.6, true)
      GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    row:SetScript("OnMouseUp", function(self)
      if self.spellID and IsShiftKeyDown() then InsertRecipeLink(self.spellID) end
    end)
  end, function(row, recipe)
    row.spellID = recipe.spellID
    row.Icon:SetTexture(SpellIcon(recipe.spellID, recipe.skillLine))
    row.Name:SetText(recipe.name)
  end)
  view.Recipes:SetPoint("TOPLEFT", 6, -104)
  view.Recipes:SetPoint("BOTTOMRIGHT", -26, 6)

  view.BookEmpty = W.Text(book, "GameFontDisable")
  view.BookEmpty:SetPoint("TOPLEFT", 12, -110)
  view.BookEmpty:SetPoint("RIGHT", -12, 0)
  view.BookEmpty:SetWordWrap(true)

  -- rendering -------------------------------------------------------------------------------------------

  -- members box: between the rail and the book, or the status column while reading
  function view:Layout(statusShown, searching)
    self.Status:SetShown(statusShown)
    self.BookBox:SetShown(not statusShown and not searching)
    self.MembersBox:ClearAllPoints()
    self.MembersBox:SetPoint("TOPLEFT", rail, "TOPRIGHT", W.GAP, 0)
    if statusShown then
      self.MembersBox:SetPoint("BOTTOMRIGHT", self.Status, "BOTTOMLEFT", -W.GAP, 0)
    elseif searching then
      self.MembersBox:SetPoint("BOTTOMRIGHT", 0, 0)
    else
      self.MembersBox:SetPoint("BOTTOMRIGHT", self.BookBox, "BOTTOMLEFT", -W.GAP, 0)
    end
  end

  function view:RenderStatus()
    local log = ns.Harvest.log
    local running = ns.Harvest.IsRunning()
    if not (running or #log > 0) or (self.statusClosed and not running) then return end
    self.Status.Bar:SetShown(running)
    if running then
      local done, total, found, look, looks, left = ns.Harvest.Progress()
      self.Status.Bar:SetValue(looks > 0 and look / looks or 0)
      local eta = left >= 60 and L.HARVEST_ETA:format(math.floor(left / 60 + 0.5)) or L.HARVEST_ETA_SHORT
      self.Status.Bar.Text:SetText(L.HARVEST_BAR:format(look, looks) .. " · " .. eta)
      self.Status.Current:ClearAllPoints()
      self.Status.Current:SetPoint("TOPLEFT", self.Status.Bar, "BOTTOMLEFT", 0, -6)
      self.Status.Current:SetPoint("RIGHT", -10, 0)
      local progress = L.HARVEST_PROGRESS:format(done, total, found)
      if (ns.Harvest.users or 0) > 0 then progress = progress .. "\n" .. L.HARVEST_USERS:format(ns.Harvest.users) end
      if (ns.Harvest.otherRealm or 0) > 0 then progress = progress .. "\n" .. L.HARVEST_OTHER_SERVER:format(ns.Harvest.otherRealm) end
      self.Status.Progress:SetText(progress)
      local name, skill, classFile = ns.Harvest.Current()
      local wait, slowed = ns.Harvest.Waiting()
      if ns.Harvest.InCombatPause() then
        self.Status.Current:SetText("|cffff9933" .. L.HARVEST_COMBAT .. "|r")
      elseif name then
        self.Status.Current:SetText(L.HARVEST_NOW:format(W.ClassName(name, classFile), skill))
      elseif slowed and wait then
        self.Status.Current:SetText("|cffff9933" .. L.HARVEST_SLOWED:format(math.ceil(wait)) .. "|r")
      else
        self.Status.Current:SetText(L.HARVEST_WAITING)
      end
    else
      local idle = L.HARVEST_IDLE
      if (ns.Harvest.otherRealm or 0) > 0 then idle = L.HARVEST_OTHER_SERVER:format(ns.Harvest.otherRealm) .. "\n" .. idle end
      if (ns.Harvest.users or 0) > 0 then idle = L.HARVEST_USERS:format(ns.Harvest.users) .. "\n" .. idle end
      self.Status.Progress:SetText(idle)
      self.Status.Current:SetText("")
      self.Status.Current:ClearAllPoints()
      self.Status.Current:SetPoint("TOPLEFT", self.Status.Progress, "BOTTOMLEFT", 0, -6)
      self.Status.Current:SetPoint("RIGHT", -10, 0)
    end
    -- the log is newest first: consecutive looks at one member become one row (looks in the order made)
    local rows = {}
    for _, e in ipairs(log) do
      local last = rows[#rows]
      if e.result == "serverbad" then
        rows[#rows + 1] = { kind = "server", entry = e }
      elseif last and last.kind == "member" and last.member == e.member then
        table.insert(last.looks, 1, e)
      else
        rows[#rows + 1] = { kind = "member", member = e.member, classFile = e.classFile, server = e.server, looks = { e } }
      end
    end
    self.Status.Log:SetItems(rows)
  end

  function view:RenderBook()
    local group = self.group
    local entry
    for _, e in ipairs(group and group.members or {}) do
      if e.member.key == self.memberKey then entry = e end
    end
    local box = self.BookBox
    local hasMember = entry ~= nil
    for _, part in ipairs({ box.Dot, box.Who, box.Meta, box.Open, box.Whisper, box.Invite }) do part:SetShown(hasMember) end
    if not entry then
      self.BookSearch:Hide()
      self.Recipes:SetItems({})
      self.BookEmpty:SetText(L.BOOK_PICK)
      self.BookEmpty:Show()
      return
    end
    local m, prof = entry.member, entry.prof
    box.Dot:SetOnline(m.online)
    box.Who:SetText(W.ClassName(m.name, m.classFile) .. MUTED .. " · " .. ns.TradeSkill.Name(group.skillLine) .. "|r")
    local meta = { UI.ProfLevel(prof) }
    if prof.recipes then meta[#meta + 1] = L.RECIPES_COUNT:format(#prof.recipes) end
    meta[#meta + 1] = prof.src == "note" and SourceText(prof.src) or (SourceText(prof.src) .. ", " .. UI.Age(prof.ts))
    box.Meta:SetText(table.concat(meta, " · "))
    box.Open:SetEnabled(ns.TradeSkill.CanOpenBook(m))
    box.Whisper:SetEnabled(m.online)
    box.Invite:SetEnabled(m.online)

    local recipes = {}
    local query = ns.Search.Normalize(self.recipeQuery)
    for _, spellID in ipairs(prof.recipes or {}) do
      local name = ns.TradeSkill.RecipeName(spellID) or ("#" .. spellID)
      if query == "" or ns.Search.Normalize(name):find(query, 1, true) then
        recipes[#recipes + 1] = { spellID = spellID, name = name, skillLine = group.skillLine }
      end
    end
    table.sort(recipes, function(a, b) return a.name < b.name end)
    local known = prof.recipes and #prof.recipes or 0
    self.BookSearch:SetShown(known > 0)
    self.BookSearch.Hint:SetText(L.BOOK_SEARCH:format(known))
    self.Recipes:SetItems(recipes)
    if known == 0 then
      self.BookEmpty:SetText(L.BOOK_NONE)
    elseif #recipes == 0 then
      self.BookEmpty:SetText(L.BOOK_NO_MATCH)
    end
    self.BookEmpty:SetShown(known == 0 or #recipes == 0)
  end

  function view:RenderMembers(groups)
    local group
    for _, g in ipairs(groups) do
      if g.skillLine == self.skill then group = g end
    end
    if not group then
      group = groups[1]
      self.skill = group and group.skillLine
    end
    self.group = group
    self.Header:SetShown(group ~= nil)
    self.Columns:SetShown(group ~= nil)
    self.Members:Show()
    self.Results:Hide()
    if not group then
      self.Members:SetItems({})
      self.Empty:SetText(L.NO_PROFESSION_DATA)
      self.Empty:Show()
      self.memberKey = nil
      self:RenderBook()
      return
    end
    self.Header.Icon:SetTexture(ns.Professions.ICONS[group.skillLine])
    self.Header.Title:SetText(ns.TradeSkill.Name(group.skillLine))
    local counts = { L.MEMBERS_COUNT:format(#group.members), GREEN .. L.ONLINE_N:format(group.online) .. "|r" }
    if group.books > 0 then counts[#counts + 1] = L.BOOKS_KNOWN:format(group.books) end
    self.Header.Counts:SetText(table.concat(counts, "   "))
    self.Header.Filter:SetValue(self.filter)

    local items, offline, divider = {}, 0, nil
    local selectedVisible = false
    for _, e in ipairs(group.members) do
      local keep = self.filter == "all" or (self.filter == "online" and e.member.online)
        or (self.filter == "book" and e.prof.recipes and #e.prof.recipes > 0)
      if keep then
        if not e.member.online then
          offline = offline + 1
          if not divider and #items > 0 then
            divider = { offline = 0 }
            items[#items + 1] = divider
          end
        end
        items[#items + 1] = e
        if e.member.key == self.memberKey then selectedVisible = true end
      end
    end
    if divider then divider.offline = offline end
    -- without a (visible) selection the first member with recipes, else the first one, fills the book
    if not selectedVisible then
      self.memberKey = nil
      for _, item in ipairs(items) do
        if item.member and item.prof.recipes and #item.prof.recipes > 0 then
          self.memberKey = item.member.key
          break
        end
      end
      if not self.memberKey and items[1] then self.memberKey = items[1].member.key end
    end
    self.Members:SetItems(items)
    self.Empty:SetText(L.NO_FILTER_MATCH)
    self.Empty:SetShown(#items == 0)
    self:RenderBook()
  end

  function view:RenderResults()
    self.Header:Hide()
    self.Columns:Hide()
    self.Members:Hide()
    self.Members:SetItems({})
    self.Results:Show()
    local results = ns.Search.GroupRecipes(ns.Search.Recipes(ns.TradeSkill.RecipeEntries(), self.query))
    self.Results:SetItems(results)
    self.Empty:SetText(L.NO_RESULTS)
    self.Empty:SetShown(#results == 0)
    self.Info:SetText(L.RESULTS_COUNT:format(#results))
  end

  function view:Refresh(event)
    placeholders = nil -- new recipes may have come in
    local running = ns.Harvest.IsRunning()
    self.Harvest:SetText(running and L.HARVEST_STOP or L.HARVEST)
    local searching = ns.Search.Normalize(self.query) ~= ""
    if running then self.statusClosed = nil end
    self.Status.Close:SetShown(not running)
    self:Layout(running or (#ns.Harvest.log > 0 and not self.statusClosed), searching)
    self:RenderStatus()
    if event == "HARVEST" and running then return end
    local groups = Groups()
    self.Rail:SetItems(groups)
    if searching then
      self:RenderResults()
    else
      self.Info:SetText(#groups == 0 and "" or L.PROFESSIONS_HINT)
      self:RenderMembers(groups)
    end
  end

  return view
end

UI.RegisterTab("professions", 4, "TAB_PROFESSIONS", Build)
