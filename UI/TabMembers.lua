-- Members tab: search, filters (class, level bracket, profession, online only), sortable columns and a
-- details panel on the right with notes, rank and officer actions.
local _, ns = ...
local W = ns.Widgets
local UI = ns.UI

local ROW = 18
local DETAIL_WIDTH = 250
local CLASSES = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }
local COLUMNS = {
  { key = "level", width = 34, desc = true },
  { key = "name", width = 140 },
  { key = "zone", width = 120 },
  { key = "rank", width = 100 },
  { key = "profs", width = 70, desc = true },
  { key = "lastOnline", width = 70 },
  { key = "note", width = 0 }, -- rest
}

local function ClassLabel(classFile)
  local male = rawget(_G, "LOCALIZED_CLASS_NAMES_MALE")
  return male and male[classFile] or classFile
end

local function ProfSummary(m)
  local record = ns.TradeSkill.Record(m)
  if not record then return "", 0 end
  local parts, count = {}, 0
  for _, skillLine in ipairs(ns.Professions.ORDER) do
    local prof = record.profs[skillLine]
    if prof and ns.Professions.PRIMARY[skillLine] then
      count = count + 1
      if #parts < 2 then
        parts[#parts + 1] = "|T" .. ns.Professions.ICONS[skillLine] .. ":13|t" .. (prof.rank and (" " .. prof.rank) or "")
      end
    end
  end
  return table.concat(parts, " "), count
end

local function Build(panel)
  local L = ns.L
  local view = { filter = {}, query = "", sort = "level", desc = true }

  -- details panel ------------------------------------------------------------------------------
  local details = W.Box(panel)
  details:SetPoint("TOPRIGHT", 0, 0)
  details:SetPoint("BOTTOMRIGHT", 0, 0)
  details:SetWidth(DETAIL_WIDTH)
  view.Details = details
  details.Empty = W.Text(details, "GameFontDisable", L.SELECT_MEMBER)
  details.Empty:SetPoint("CENTER")
  details.Name = W.Text(details, "GameFontNormalLarge")
  details.Name:SetPoint("TOPLEFT", 12, -12)
  details.Name:SetPoint("RIGHT", -12, 0)
  details.Sub = W.Text(details, "GameFontHighlightSmall")
  details.Sub:SetPoint("TOPLEFT", details.Name, "BOTTOMLEFT", 0, -4)
  details.Lines = W.Text(details, "GameFontHighlightSmall")
  details.Lines:SetPoint("TOPLEFT", details.Sub, "BOTTOMLEFT", 0, -10)
  details.Lines:SetPoint("RIGHT", -12, 0)
  details.Lines:SetSpacing(3)
  details.RankButton = W.MenuButton(details, L.SET_RANK, function()
    local m, items = view.selected, {}
    if not m then return items end
    local can = ns.Roster.Can()
    if can.promote then items[#items + 1] = { text = L.PROMOTE, onClick = function() UI.ConfirmMemberCommand("promote", m) end } end
    if can.demote then items[#items + 1] = { text = L.DEMOTE, onClick = function() UI.ConfirmMemberCommand("demote", m) end } end
    return items
  end, 110)
  details.NoteButton = W.Button(details, L.EDIT_NOTES, function() UI.EditInBlizzard() end, 110, { small = true })
  W.Tooltip(details.NoteButton, L.EDIT_NOTES, L.EDIT_IN_BLIZZARD)
  details.Profs = W.Text(details, "GameFontHighlightSmall")
  details.Profs:SetPoint("RIGHT", -12, 0)
  details.Profs:SetSpacing(3)
  details.Whisper = W.Button(details, L.WHISPER, function() if view.selected then UI.Whisper(view.selected.fullName) end end, 108)
  details.Whisper:SetPoint("BOTTOMLEFT", 12, 36)
  details.Invite = W.Button(details, L.GROUP_INVITE_SHORT, function() if view.selected then ns.Roster.GroupInvite(view.selected) end end, 108)
  details.Invite:SetPoint("BOTTOMRIGHT", -12, 36)
  details.Remove = W.Button(details, L.REMOVE_SHORT, function()
    local m = view.selected
    if m then UI.ConfirmMemberCommand("remove", m) end
  end, 108)
  details.Remove:SetPoint("BOTTOMLEFT", 12, 10)
  details.Menu = W.Button(details, L.MORE, function(self) if view.selected then UI.MemberMenu(view.selected, self) end end, 108)
  details.Menu:SetPoint("BOTTOMRIGHT", -12, 10)

  -- toolbar ------------------------------------------------------------------------------------
  local main = CreateFrame("Frame", nil, panel)
  main:SetPoint("TOPLEFT", 0, 0)
  main:SetPoint("BOTTOMRIGHT", details, "BOTTOMLEFT", -8, 0)

  local search = W.EditBox(main, 170)
  search:SetPoint("TOPLEFT", 6, -4)
  search.Hint = W.Text(search, "GameFontDisableSmall", L.SEARCH_MEMBERS)
  search.Hint:SetPoint("LEFT", 2, 0)
  search:SetScript("OnTextChanged", function(self)
    view.query = self:GetText() or ""
    self.Hint:SetShown(view.query == "")
    view:Refresh()
  end)
  search:SetScript("OnEnterPressed", search.ClearFocus)

  view.ClassButton = W.MenuButton(main, L.FILTER_CLASS, function()
    local items = { { text = L.ALL, checked = view.filter.classFile == nil, onClick = function() view:SetFilterValue("classFile", nil) end } }
    for _, classFile in ipairs(CLASSES) do
      local r, g, b = W.ClassColor(classFile)
      items[#items + 1] = { text = ClassLabel(classFile), color = { r, g, b }, checked = view.filter.classFile == classFile,
        onClick = function() view:SetFilterValue("classFile", classFile) end }
    end
    return items
  end, 90)
  view.ClassButton:SetPoint("LEFT", search, "RIGHT", 8, 0)

  view.LevelButton = W.MenuButton(main, L.FILTER_LEVEL, function()
    local items = { { text = L.ALL, checked = view.filter.bracket == nil, onClick = function() view:SetFilterValue("bracket", nil) end } }
    for bracket = 1, ns.Census.BRACKETS do
      items[#items + 1] = { text = ns.Census.BracketLabel(bracket), checked = view.filter.bracket == bracket,
        onClick = function() view:SetFilterValue("bracket", bracket) end }
    end
    return items
  end, 80)
  view.LevelButton:SetPoint("LEFT", view.ClassButton, "RIGHT", 4, 0)

  view.ProfButton = W.MenuButton(main, L.FILTER_PROFESSION, function()
    local items = { { text = L.ALL, checked = view.filter.skillLine == nil, onClick = function() view:SetFilterValue("skillLine", nil) end } }
    for _, skillLine in ipairs(ns.Professions.ORDER) do
      items[#items + 1] = { text = ns.TradeSkill.Name(skillLine), checked = view.filter.skillLine == skillLine,
        onClick = function() view:SetFilterValue("skillLine", skillLine) end }
    end
    return items
  end, 90)
  view.ProfButton:SetPoint("LEFT", view.LevelButton, "RIGHT", 4, 0)

  local onlineCheck = CreateFrame("CheckButton", nil, main, "UICheckButtonTemplate")
  onlineCheck:SetSize(24, 24)
  onlineCheck:SetPoint("LEFT", view.ProfButton, "RIGHT", 6, 0)
  onlineCheck:SetScript("OnClick", function(self) view:SetFilterValue("onlineOnly", self:GetChecked() or nil) end)
  local onlineLabel = W.Text(main, "GameFontHighlightSmall", L.ONLINE_ONLY)
  onlineLabel:SetPoint("LEFT", onlineCheck, "RIGHT", 0, 0)
  view.OnlineCheck = onlineCheck

  view.Reset = W.Button(main, L.RESET, function()
    view.filter = {}
    search:SetText("")
    onlineCheck:SetChecked(false)
    view:Refresh()
  end, 70, { small = true })
  view.Reset:SetPoint("LEFT", onlineLabel, "RIGHT", 8, 0)

  -- header -------------------------------------------------------------------------------------
  local header = CreateFrame("Frame", nil, main)
  header:SetPoint("TOPLEFT", 0, -32)
  header:SetPoint("RIGHT", main, "RIGHT", 0, 0)
  header:SetHeight(20)
  local x = 8
  view.Headers = {}
  for _, column in ipairs(COLUMNS) do
    local button = CreateFrame("Button", nil, header)
    button:SetHeight(20)
    button:SetPoint("LEFT", x, 0)
    if column.width > 0 then button:SetWidth(column.width) else button:SetPoint("RIGHT", header, "RIGHT", -26, 0) end
    button.Text = W.Text(button, "GameFontNormalSmall", L["COL_" .. column.key:upper()])
    button.Text:SetPoint("LEFT", 0, 0)
    button:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    if column.key ~= "note" then
      button:SetScript("OnClick", function()
        if view.sort == column.key then view.desc = not view.desc else view.sort, view.desc = column.key, column.desc or false end
        view:Refresh()
      end)
    end
    column.x = x
    x = x + column.width + 6
    view.Headers[column.key] = button
  end

  local listBox = W.Box(main)
  listBox:SetPoint("TOPLEFT", 0, -54)
  listBox:SetPoint("BOTTOMRIGHT", 0, 0)
  view.List = W.ScrollList(listBox, ROW, function(row)
    row:EnableMouse(true)
    row.Cells = {}
    for _, column in ipairs(COLUMNS) do
      local cell = W.Text(row, "GameFontHighlightSmall")
      cell:SetPoint("LEFT", column.x - 4, 0)
      if column.width > 0 then cell:SetWidth(column.width) else cell:SetPoint("RIGHT", row, "RIGHT", -4, 0) end
      cell:SetWordWrap(false)
      row.Cells[column.key] = cell
    end
    row.Selected = row:CreateTexture(nil, "BACKGROUND")
    row.Selected:SetAllPoints()
    row.Selected:SetColorTexture(1, 0.82, 0, 0.18)
    local highlight = row:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints()
    highlight:SetColorTexture(1, 0.82, 0, 0.1)
    row:SetScript("OnMouseUp", function(self, button)
      if not self.member then return end
      if button == "RightButton" then
        UI.MemberMenu(self.member, self)
      else
        view:Select(self.member)
      end
    end)
    row:SetScript("OnEnter", function(self) if self.member then UI.MemberTooltip(self, self.member) end end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
  end, function(row, m)
    row.member = m
    local dim = not m.online
    local c = row.Cells
    c.level:SetText(m.level)
    c.name:SetText(W.ClassName(m.name, m.classFile))
    c.zone:SetText(m.zone or "")
    c.rank:SetText(m.rank or "")
    c.profs:SetText((ProfSummary(m)))
    c.lastOnline:SetText(ns.Roster.LastOnlineText(m))
    c.note:SetText(m.note or "")
    for key, cell in pairs(c) do
      if key ~= "name" and key ~= "profs" then
        if dim then cell:SetTextColor(0.6, 0.6, 0.6) else cell:SetTextColor(1, 1, 1) end
      end
    end
    c.name:SetAlpha(dim and 0.7 or 1)
    row.Selected:SetShown(view.selected ~= nil and view.selected.key == m.key)
  end)
  view.List:SetPoint("TOPLEFT", 4, -4)
  view.List:SetPoint("BOTTOMRIGHT", -26, 4)

  view.Summary = W.Text(header, "GameFontDisableSmall")
  view.Summary:SetPoint("RIGHT", header, "RIGHT", -28, 0)
  view.Summary:SetJustifyH("RIGHT")

  -- behaviour ----------------------------------------------------------------------------------
  function view:SetFilterValue(key, value)
    self.filter[key] = value
    self:Refresh()
  end

  function view:SetFilter(filter)
    self.filter = filter or {}
    self.OnlineCheck:SetChecked(self.filter.onlineOnly and true or false)
    self:Refresh()
  end

  local function Label(button, base, value)
    button:SetText(value and (base .. ": " .. value) or base)
  end

  function view:RenderDetails()
    local m = self.selected and ns.Roster.Find(self.selected.key)
    self.selected = m
    local d = self.Details
    local shown = m ~= nil
    for _, element in ipairs({ d.Name, d.Sub, d.Lines, d.Profs, d.Whisper, d.Invite, d.Remove, d.Menu, d.RankButton,
      d.NoteButton }) do
      element:SetShown(shown)
    end
    d.Empty:SetShown(not shown)
    if not m then return end
    local can = ns.Roster.Can()
    d.Name:SetText(W.ClassName(m.name, m.classFile))
    d.Sub:SetText(L.LEVEL_CLASS:format(m.level or 0, m.className or ""))
    local lines = {
      "|cffffd100" .. L.RANK .. ":|r " .. (m.rank or ""),
      "|cffffd100" .. L.ZONE .. ":|r " .. (m.zone or ""),
      "|cffffd100" .. L.LAST_ONLINE .. ":|r " .. ns.Roster.LastOnlineText(m),
      "|cffffd100" .. L.NOTE .. ":|r " .. ((m.note and m.note ~= "") and m.note or "-"),
    }
    if can.viewOfficer then
      lines[#lines + 1] = "|cffffd100" .. L.OFFICER_NOTE .. ":|r " .. ((m.officerNote and m.officerNote ~= "") and m.officerNote or "-")
    end
    d.Lines:SetText(table.concat(lines, "\n"))
    d.RankButton:ClearAllPoints()
    d.RankButton:SetPoint("TOPLEFT", d.Lines, "BOTTOMLEFT", 0, -10)
    d.RankButton:SetShown(can.promote or can.demote)
    d.NoteButton:ClearAllPoints()
    d.NoteButton:SetPoint("LEFT", d.RankButton, "RIGHT", 6, 0)
    d.NoteButton:SetShown(can.editPublic or can.editOfficer)

    local record = ns.TradeSkill.Record(m)
    local profLines = { "|cffffd100" .. L.PROFESSIONS .. "|r" }
    for _, skillLine in ipairs(ns.Professions.ORDER) do
      local prof = record and record.profs[skillLine]
      if prof then
        local level = prof.rank and (prof.rank .. (prof.max and ("/" .. prof.max) or "")) or "?"
        local recipes = prof.recipes and (" · " .. L.RECIPES_COUNT:format(#prof.recipes)) or ""
        profLines[#profLines + 1] = "|T" .. ns.Professions.ICONS[skillLine] .. ":14|t " .. ns.TradeSkill.Name(skillLine)
          .. "  " .. level .. "|cff999999" .. recipes .. " · " .. UI.Age(prof.ts) .. "|r"
      end
    end
    if #profLines == 1 then profLines[2] = "|cff999999" .. L.NO_PROFESSIONS .. "|r" end
    d.Profs:ClearAllPoints()
    d.Profs:SetPoint("TOPLEFT", d.RankButton, "BOTTOMLEFT", 0, -12)
    d.Profs:SetText(table.concat(profLines, "\n"))
    d.Whisper:SetEnabled(m.online)
    d.Invite:SetEnabled(m.online)
    d.Remove:SetShown(can.remove)
  end

  function view:Select(m)
    self.selected = m
    self:Refresh()
  end

  function view:Refresh()
    local members = ns.Roster.Members()
    for _, m in ipairs(members) do
      local _, count = ProfSummary(m)
      m.profCount = count
    end
    local list = ns.Search.Members(members, self.filter, self.query, ns.TradeSkill.ProfsOf)
    ns.Search.SortMembers(list, self.sort, self.desc)
    self.List:SetItems(list)
    self.Summary:SetText(L.SHOWN_COUNT:format(#list, #members))
    Label(self.ClassButton, L.FILTER_CLASS, self.filter.classFile and ClassLabel(self.filter.classFile))
    Label(self.LevelButton, L.FILTER_LEVEL, self.filter.bracket and ns.Census.BracketLabel(self.filter.bracket))
    Label(self.ProfButton, L.FILTER_PROFESSION, self.filter.skillLine and ns.TradeSkill.Name(self.filter.skillLine))
    for key, button in pairs(self.Headers) do
      local text = L["COL_" .. key:upper()]
      if key == self.sort then text = text .. (self.desc and " v" or " ^") end
      button.Text:SetText(text)
    end
    self:RenderDetails()
  end

  view:RenderDetails()
  return view
end

-- "today", "3 d ago" for a timestamp
function UI.Age(ts)
  if type(ts) ~= "number" then return "?" end
  local days = math.floor((ns.Now() - ts) / 86400)
  if days <= 0 then return ns.L.TODAY end
  return ns.L.DAYS_AGO:format(days)
end

UI.RegisterTab("members", 2, ns.L.TAB_MEMBERS, Build)
