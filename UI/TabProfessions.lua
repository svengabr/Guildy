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
  return L.SRC_RELAY
end

-- Rows for the profession overview: a header per profession, then its members (online first, skill desc)
local function OverviewRows()
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
        rows[#rows + 1] = { member = entry.member, prof = entry.prof, skillLine = skillLine }
      end
    end
  end
  return rows
end

local function Build(panel)
  local L = ns.L
  local view = { query = "" }

  local search = W.EditBox(panel, 320)
  search:SetPoint("TOPLEFT", 6, -4)
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
  status:SetWidth(290)
  status.Title = W.Text(status, "GameFontNormal", L.HARVEST_STATUS)
  status.Title:SetPoint("TOPLEFT", 10, -8)
  status.Progress = W.Text(status, "GameFontHighlightSmall")
  status.Progress:SetPoint("TOPLEFT", 10, -28)
  status.Progress:SetPoint("RIGHT", -10, 0)
  status.Current = W.Text(status, "GameFontHighlight")
  status.Current:SetPoint("TOPLEFT", 10, -46)
  status.Current:SetPoint("RIGHT", -10, 0)
  status.Current:SetWordWrap(false)
  status.Hint = W.Text(status, "GameFontDisableSmall", L.HARVEST_RESULTS)
  status.Hint:SetPoint("TOPLEFT", 10, -70)
  status.Log = W.ScrollList(status, 18, function(row)
    row.Icon = row:CreateTexture(nil, "ARTWORK")
    row.Icon:SetSize(14, 14)
    row.Icon:SetPoint("LEFT", 2, 0)
    row.Icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    row.Name = W.Text(row, "GameFontHighlightSmall")
    row.Name:SetPoint("LEFT", 20, 0)
    row.Name:SetWidth(120)
    row.Name:SetWordWrap(false)
    row.Result = W.Text(row, "GameFontHighlightSmall")
    row.Result:SetPoint("LEFT", 144, 0)
    row.Result:SetPoint("RIGHT", -2, 0)
    row.Result:SetWordWrap(false)
  end, function(row, e)
    row.Icon:SetTexture(ns.Professions.ICONS[e.skillLine])
    row.Name:SetText(W.ClassName(e.member, e.classFile))
    if e.result == "found" then
      row.Result:SetText("|cff40e040" .. L.HARVEST_FOUND:format(e.recipes or 0, e.rank or 0) .. "|r")
    elseif e.result == "silent" then
      row.Result:SetText("|cff999999" .. L.HARVEST_SILENT .. "|r")
    elseif e.result == "absent" then
      row.Result:SetText("|cff999999" .. L.HARVEST_ABSENT .. "|r")
    else
      row.Result:SetText("|cffff9933" .. L.HARVEST_NO_ANSWER .. "|r")
    end
  end)
  status.Log:SetPoint("TOPLEFT", 6, -86)
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
    if running then
      local done, total, found = ns.Harvest.Progress()
      self.Status.Progress:SetText(L.HARVEST_PROGRESS:format(done, total, found))
      local name, skill, classFile = ns.Harvest.Current()
      self.Status.Current:SetText(name and L.HARVEST_NOW:format(W.ClassName(name, classFile), skill) or L.HARVEST_WAITING)
    else
      self.Status.Progress:SetText(L.HARVEST_IDLE)
      self.Status.Current:SetText("")
    end
    self.Status.Log:SetItems(log)
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
      if item.entry then
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if not pcall(GameTooltip.SetSpellByID, GameTooltip, item.entry.spellID) then GameTooltip:SetText(item.entry.recipeName) end
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(L.CLICK_TO_WHISPER, 0.6, 0.6, 0.6)
        GameTooltip:Show()
      elseif item.member then
        UI.MemberTooltip(self, item.member)
      end
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    row:SetScript("OnMouseUp", function(self, button)
      local item = self.item
      local m = item and (item.member or (item.entry and ns.Roster.Find(item.entry.memberKey)))
      if not m then return end
      if button == "RightButton" then UI.MemberMenu(m, self) else UI.Whisper(m.fullName) end
    end)
  end, function(row, item)
    row.item = item
    if item.header then
      row.Icon:SetTexture(ns.Professions.ICONS[item.skillLine])
      row.Icon:Show()
      row.A:SetText("|cffffd100" .. ns.TradeSkill.Name(item.skillLine) .. "|r")
      row.B:SetText("")
      row.C:SetText(L.MEMBERS_COUNT:format(item.count))
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
      row.A:SetText("    " .. W.ClassName(m.name, m.classFile) .. (m.online and " |cff40e040" .. L.ONLINE .. "|r" or ""))
      local level = prof.rank and (prof.rank .. (prof.max and ("/" .. prof.max) or "")) or "?"
      local recipes = prof.recipes and (" · " .. L.RECIPES_COUNT:format(#prof.recipes)) or ""
      row.B:SetText(level .. recipes)
      row.C:SetText(UI.Age(prof.ts) .. " · " .. SourceText(prof.src))
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
      local rows = OverviewRows()
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
