-- Professions tab: recipe search across all known members (who can craft X?) and, without a search,
-- the list of professions with their members, skill, data age and source.
local _, ns = ...
local W = ns.Widgets
local UI = ns.UI

local ROW = 18

local function SourceText(src)
  local L = ns.L
  if src == "scan" or src == "self" then return L.SRC_SELF end
  if src == "link" then return L.SRC_LINK end
  if src == "note" then return L.SRC_NOTE end
  return L.SRC_RELAY
end

local function ExpandKey(m, skillLine)
  return m.key .. ":" .. skillLine
end

-- Recipe rows of an expanded member profession, sorted by name
local function RecipeRows(m, prof, skillLine)
  local rows = {}
  for _, spellID in ipairs(prof.recipes or {}) do
    local name = ns.TradeSkill.RecipeName(spellID) or ("#" .. spellID)
    rows[#rows + 1] = { recipe = spellID, name = name, member = m, skillLine = skillLine }
  end
  table.sort(rows, function(a, b) return a.name < b.name end)
  return rows
end

-- Rows for the profession overview: a header per profession, then its members (online first, skill
-- desc), with the recipes of expanded members below them
local function OverviewRows(expanded)
  local guild = ns.GuildData()
  local rows = {}
  if not guild then return rows end
  for _, skillLine in ipairs(ns.Professions.ORDER) do
    local members = {}
    for key, record in pairs(guild.members) do
      local prof = record.profs and record.profs[skillLine]
      local m = ns.Roster.Find(key)
      if prof and m then members[#members + 1] = { member = m, prof = prof } end
    end
    if #members > 0 then
      table.sort(members, function(a, b)
        if a.member.online ~= b.member.online then return a.member.online end
        local ra, rb = a.prof.rank or -1, b.prof.rank or -1
        if ra ~= rb then return ra > rb end
        return a.member.name < b.member.name
      end)
      rows[#rows + 1] = { header = true, skillLine = skillLine, count = #members }
      for _, entry in ipairs(members) do
        local open = expanded[ExpandKey(entry.member, skillLine)] and entry.prof.recipes ~= nil
        rows[#rows + 1] = { member = entry.member, prof = entry.prof, skillLine = skillLine, open = open }
        if open then
          for _, recipeRow in ipairs(RecipeRows(entry.member, entry.prof, skillLine)) do rows[#rows + 1] = recipeRow end
        end
      end
    end
  end
  return rows
end

local function Build(panel)
  local L = ns.L
  local view = { query = "", expanded = {} }

  -- Menu for a member's profession: open Blizzard's recipe book, show/hide recipes, whisper, invite
  local function ProfessionMenu(anchor, m, skillLine, prof)
    local canOpen = ns.TradeSkill.CanOpenBook(m)
    local items = {
      { text = W.ClassName(m.name, m.classFile) .. " · " .. ns.TradeSkill.Name(skillLine), isTitle = true },
      { text = canOpen and L.OPEN_BOOK or L.OPEN_BOOK_OFFLINE,
        disabled = not canOpen, onClick = function() ns.TradeSkill.OpenBook(m, skillLine) end },
    }
    if prof and prof.recipes then
      local key = ExpandKey(m, skillLine)
      items[#items + 1] = { text = view.expanded[key] and L.HIDE_RECIPES or L.SHOW_RECIPES, onClick = function()
        view.expanded[key] = not view.expanded[key] or nil
        view:Refresh()
      end }
    end
    items[#items + 1] = { text = L.WHISPER, disabled = not m.online, onClick = function() UI.Whisper(m.fullName) end }
    items[#items + 1] = { text = L.GROUP_INVITE, disabled = not m.online, onClick = function() ns.Roster.GroupInvite(m) end }
    W.OpenMenu(anchor, items, 230)
  end

  local function InsertRecipeLink(spellID)
    local getLink = (C_Spell and C_Spell.GetSpellLink) or rawget(_G, "GetSpellLink")
    local link = getLink and ns.Try(getLink, spellID)
    local insert = rawget(_G, "ChatEdit_InsertLink") or (ChatFrameUtil and ChatFrameUtil.InsertLink)
    if link and insert then pcall(insert, link) end
  end

  local search = W.EditBox(panel, 320)
  search:SetPoint("TOPLEFT", 54, -4) -- clear of the portrait
  search.Hint = W.Text(search, "GameFontDisableSmall", L.SEARCH_RECIPES)
  search.Hint:SetPoint("LEFT", 2, 0)
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

  view.Harvest = W.Button(panel, L.HARVEST, function()
    if ns.Harvest.IsRunning() then ns.Harvest.Stop() else ns.Harvest.Start() end
  end, 190, { fit = { L.HARVEST, L.HARVEST_STOP } })
  view.Harvest:SetPoint("TOPRIGHT", 0, -2)
  W.Tooltip(view.Harvest, L.HARVEST, L.HARVEST_TIP)

  view.Info = W.Text(panel, "GameFontDisableSmall")
  view.Info:SetPoint("LEFT", search, "RIGHT", 12, 0)
  view.Info:SetPoint("RIGHT", view.Harvest, "LEFT", -8, 0)
  view.Info:SetJustifyH("LEFT")
  view.Info:SetWordWrap(false)

  -- status column while reading members: current look and the latest results
  local status = W.Box(panel)
  status:SetPoint("TOPRIGHT", 0, -30)
  status:SetPoint("BOTTOMRIGHT", 0, 0)
  status:SetWidth(560)
  -- wide enough for a member's row, but never more than about half of the tab
  panel:HookScript("OnSizeChanged", function(_, width)
    status:SetWidth(math.max(400, math.min(560, (width or 1000) * 0.46)))
  end)
  status.Title = W.Text(status, "GameFontNormal", L.HARVEST_STATUS)
  status.Title:SetPoint("TOPLEFT", 10, -8)
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
  -- one row per member: server id, one icon per profession looked at (bright with the recipe count =
  -- book read, faded = doesn't have it, faded with "?" = no answer), a short summary; details on hover
  local MAX_ICONS = 8
  local ICON_X, SERVER_X = 156, 156 + MAX_ICONS * 24 + 6

  local function LookLine(e)
    local text, note
    if e.result == "found" then
      text = "|cff40e040" .. L.HARVEST_FOUND:format(e.recipes or 0, e.rank or 0) .. "|r"
    elseif e.result == "silent" then
      text, note = "|cffff9933" .. L.HARVEST_SILENT .. "|r", L.HARVEST_DETAIL_SILENT
    elseif e.result == "absent" then
      text, note = "|cff999999" .. L.HARVEST_ABSENT .. "|r", L.HARVEST_DETAIL_ABSENT
    else
      text, note = "|cffff9933" .. L.HARVEST_NO_ANSWER .. "|r", L.HARVEST_DETAIL_NO_ANSWER
    end
    local line = (e.skill or "?") .. ": " .. text .. " |cff9a8f78(" .. tostring(e.seconds or "?") .. " s, "
      .. L.HARVEST_LOOK:format(e.look or 0, e.of or 0) .. ")|r"
    return note and (line .. "\n   |cff9a8f78" .. note .. "|r") or line
  end

  status.Log = W.ScrollList(status, 26, function(row)
    row.Name = W.Text(row, "GameFontHighlight")
    row.Name:SetPoint("LEFT", 4, 0)
    row.Name:SetWidth(ICON_X - 10)
    row.Name:SetJustifyH("LEFT")
    row.Name:SetWordWrap(false)
    row.Icons = {}
    for i = 1, MAX_ICONS do
      local icon = row:CreateTexture(nil, "ARTWORK")
      icon:SetSize(20, 20)
      icon:SetPoint("LEFT", ICON_X + (i - 1) * 24, 0)
      icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
      icon.Mark = W.Text(row, "NumberFontNormalSmall")
      icon.Mark:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", 2, -1)
      row.Icons[i] = icon
    end
    row.Server = W.Text(row, "GameFontDisableSmall")
    row.Server:SetPoint("LEFT", SERVER_X, 0)
    row.Server:SetWidth(40)
    row.Server:SetJustifyH("LEFT")
    row.Summary = W.Text(row, "GameFontHighlightSmall")
    row.Summary:SetPoint("LEFT", SERVER_X + 44, 0)
    row.Summary:SetPoint("RIGHT", -4, 0)
    row.Summary:SetJustifyH("LEFT")
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
      row.Name:SetWidth(SERVER_X - 10)
      row.Server:SetText("")
      row.Summary:SetText("|cff9a8f78" .. L.HARVEST_SERVER_BAD_SHORT:format(e.skipped or 0) .. "|r")
      row.TipTitle = L.HARVEST_SERVER_BAD:format(tostring(e.server))
      row.Tip = { L.HARVEST_SERVER_BAD_DETAIL:format(e.misses or 0, e.skipped or 0) }
      return
    end
    row.Name:SetWidth(ICON_X - 10)
    row.Name:SetText(W.ClassName(item.member, item.classFile))
    row.Server:SetText(item.server or "")
    local books, recipes, silent, absent = 0, 0, 0, 0
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
          icon.Mark:SetText("|cff40e040" .. (e.recipes or 0) .. "|r")
        elseif e.result ~= "absent" then
          icon.Mark:SetText("|cffff9933?|r")
        end
      end
      if e.result == "found" then
        books, recipes = books + 1, recipes + (e.recipes or 0)
      elseif e.result == "absent" then
        absent = absent + 1
      else
        silent = silent + 1
      end
      tip[#tip + 1] = LookLine(e)
    end
    local summary
    if books > 0 then
      summary = "|cff40e040" .. L.HARVEST_SUM_FOUND:format(books, recipes) .. "|r"
    elseif silent > 0 then
      summary = "|cffff9933" .. L.HARVEST_SUM_SILENT .. "|r"
    else
      summary = "|cff999999" .. L.HARVEST_SUM_NONE .. "|r"
    end
    row.Summary:SetText(summary)
    row.TipTitle = item.member .. (item.server and ("  |cff9a8f78" .. L.HARVEST_SERVER:format(item.server) .. "|r") or "")
    row.Tip = tip
  end)
  status.Log:SetPoint("TOPLEFT", status.Hint, "BOTTOMLEFT", -4, -4)
  status.Log:SetPoint("BOTTOMRIGHT", -26, 6)
  status:Hide()
  view.Status = status

  local listBox = W.Box(panel)
  listBox:SetPoint("TOPLEFT", 0, -30)
  listBox:SetPoint("BOTTOMRIGHT", 0, 0)
  view.ListBox = listBox

  function view:RenderStatus()
    local log = ns.Harvest.log
    local running = ns.Harvest.IsRunning()
    local shown = running or #log > 0
    self.Status:SetShown(shown)
    self.ListBox:ClearAllPoints()
    self.ListBox:SetPoint("TOPLEFT", 0, -30)
    if shown then
      self.ListBox:SetPoint("BOTTOMRIGHT", self.Status, "BOTTOMLEFT", -8, 0)
    else
      self.ListBox:SetPoint("BOTTOMRIGHT", 0, 0)
    end
    if not shown then return end
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
  view.List = W.ScrollList(listBox, ROW, function(row)
    row:EnableMouse(true)
    row.Icon = row:CreateTexture(nil, "ARTWORK")
    row.Icon:SetSize(16, 16)
    row.Icon:SetPoint("LEFT", 4, 0)
    row.Icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    row.A = W.Text(row, "GameFontHighlightSmall")
    row.A:SetPoint("LEFT", 26, 0)
    row.A:SetWidth(260)
    row.A:SetWordWrap(false)
    row.B = W.Text(row, "GameFontHighlightSmall")
    row.B:SetPoint("LEFT", 292, 0)
    row.B:SetWidth(170)
    row.B:SetWordWrap(false)
    row.C = W.Text(row, "GameFontDisableSmall")
    row.C:SetPoint("LEFT", 468, 0)
    row.C:SetPoint("RIGHT", -6, 0)
    row.C:SetWordWrap(false)
    local highlight = row:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints()
    highlight:SetColorTexture(1, 0.82, 0, 0.1)
    row:SetScript("OnEnter", function(self)
      local item = self.item
      if not item then return end
      local spellID = (item.entry and item.entry.spellID) or item.recipe
      if spellID then
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if not pcall(GameTooltip.SetSpellByID, GameTooltip, spellID) then
          GameTooltip:SetText((item.entry and item.entry.recipeName) or item.name or "?")
        end
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(item.entry and L.RESULT_CLICK_HINT or L.RECIPE_CLICK_HINT, 0.6, 0.6, 0.6, true)
        GameTooltip:Show()
      elseif item.member and item.prof then
        UI.MemberTooltip(self, item.member)
        GameTooltip:AddLine(L.PROF_CLICK_HINT, 0.6, 0.6, 0.6, true)
        GameTooltip:Show()
      end
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    row:SetScript("OnMouseUp", function(self, button)
      local item = self.item
      if not item or item.header then return end
      if item.recipe then
        if IsShiftKeyDown() then InsertRecipeLink(item.recipe) end
        return
      end
      if item.entry then
        local m = ns.Roster.Find(item.entry.memberKey)
        if not m then return end
        if IsShiftKeyDown() then
          InsertRecipeLink(item.entry.spellID)
        elseif button == "RightButton" then
          ProfessionMenu(self, m, item.entry.skillLine, nil)
        elseif ns.TradeSkill.CanOpenBook(m) then
          ns.TradeSkill.OpenBook(m, item.entry.skillLine)
        else
          UI.Whisper(m.fullName)
        end
        return
      end
      local m, prof = item.member, item.prof
      if button == "RightButton" then
        ProfessionMenu(self, m, item.skillLine, prof)
      elseif prof.recipes then
        local key = ExpandKey(m, item.skillLine)
        view.expanded[key] = not view.expanded[key] or nil
        view:Refresh()
      elseif ns.TradeSkill.CanOpenBook(m) then
        ns.TradeSkill.OpenBook(m, item.skillLine)
      end
    end)
  end, function(row, item)
    row.item = item
    if item.header then
      row.Icon:SetTexture(ns.Professions.ICONS[item.skillLine])
      row.Icon:Show()
      row.A:SetText("|cffffd100" .. ns.TradeSkill.Name(item.skillLine) .. "|r")
      row.B:SetText("")
      row.C:SetText(L.MEMBERS_COUNT:format(item.count))
    elseif item.recipe then
      row.Icon:Hide()
      row.A:SetText("        |cffd8c8a0" .. item.name .. "|r")
      row.B:SetText("")
      row.C:SetText("")
    elseif item.entry then
      local e = item.entry
      local m = ns.Roster.Find(e.memberKey)
      row.Icon:SetTexture(ns.Professions.ICONS[e.skillLine])
      row.Icon:Show()
      row.A:SetText(e.recipeName)
      row.B:SetText(m and (W.ClassName(m.name, m.classFile) .. (m.online and " |cff40e040" .. L.ONLINE .. "|r" or "")) or e.memberName)
      row.C:SetText(ns.TradeSkill.Name(e.skillLine))
    else
      local m, prof = item.member, item.prof
      row.Icon:Hide()
      local arrow = prof.recipes and (item.open and "|cffffd100-|r " or "|cffffd100+|r ") or "   "
      row.A:SetText("  " .. arrow .. W.ClassName(m.name, m.classFile) .. (m.online and " |cff40e040" .. L.ONLINE .. "|r" or ""))
      local level = UI.ProfLevel(prof)
      local recipes = prof.recipes and (" · " .. L.RECIPES_COUNT:format(#prof.recipes)) or ""
      row.B:SetText(level .. recipes)
      row.C:SetText(prof.src == "note" and SourceText(prof.src) or (UI.Age(prof.ts) .. " · " .. SourceText(prof.src)))
    end
  end)
  view.List:SetPoint("TOPLEFT", 4, -4)
  view.List:SetPoint("BOTTOMRIGHT", -26, 4)

  function view:Refresh(event)
    local running = ns.Harvest.IsRunning()
    self.Harvest:SetText(running and L.HARVEST_STOP or L.HARVEST)
    self:RenderStatus()
    if event == "HARVEST" and running then return end
    if ns.Search.Normalize(self.query) == "" then
      local rows = OverviewRows(self.expanded)
      self.List:SetItems(rows)
      self.Info:SetText(#rows == 0 and L.NO_PROFESSION_DATA or L.PROFESSIONS_HINT)
      return
    end
    local results = ns.Search.Recipes(ns.TradeSkill.RecipeEntries(), self.query)
    local items = {}
    for i, entry in ipairs(results) do items[i] = { entry = entry } end
    self.List:SetItems(items)
    self.Info:SetText(L.RESULTS_COUNT:format(#items))
  end

  return view
end

UI.RegisterTab("professions", 4, ns.L.TAB_PROFESSIONS, Build)
