-- Members tab: search, filters (class, level bracket, profession, group, online only, without note)
-- and sortable columns. Twinks hang under their main (or fold into it); the group comes from notes
-- like "Main, Murloc Raid" (any name, Core/Family.lua) and twinks inherit their main's.
-- A click on a member opens the character page (UI/CharacterPage.lua), a right click the member menu.
local _, ns = ...
local W = ns.Widgets
local UI = ns.UI

local ROW = 18
local CLASSES = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }
local COLUMNS = {
  { key = "level", width = 34, desc = true },
  { key = "name", width = 175 },
  { key = "rank", width = 100 },
  { key = "group", width = 130 },
  { key = "ilvl", width = 44, desc = true },
  { key = "zone", width = 120 },
  { key = "lastOnline", width = 70 },
  { key = "guildy", width = 46, desc = true },
  { key = "note", width = 210 },
  { key = "officerNote", width = 0 }, -- rest; only for those who may read officer notes
}
local UNSORTED = { note = true, officerNote = true }
-- colors for the guild's groups (Family.GroupColor picks one per name)
local GROUP_COLORS = { { 64, 166, 214 }, { 196, 107, 224 }, { 224, 80, 80 }, { 102, 204, 89 }, { 255, 153, 64 },
  { 77, 204, 191 }, { 242, 217, 77 }, { 242, 128, 179 } }
local DOT = "|TInterface\\AddOns\\Guildy\\Textures\\Dot:8:8:0:0:32:32:0:32:0:32:%d:%d:%d|t "

local ONLINE_COLOR = { 0.3, 0.9, 0.3 }

-- Guildy version of an online member as colored text: green = same or newer than mine, orange = older
function UI.GuildyVersionText(m)
  local version = m.online and ns.Sync.UserVersion(m.name)
  if not version then return nil end
  if version == "" then return "|cffff9933" .. ns.L.GUILDY_OLD .. "|r" end
  local cmp = ns.Protocol.CompareVersions(version, ns.Version())
  return (cmp == -1 and "|cffff9933" or "|cff4ce64c") .. version .. "|r"
end

local function ClassLabel(classFile)
  local male = rawget(_G, "LOCALIZED_CLASS_NAMES_MALE")
  return male and male[classFile] or classFile
end

local function ClassIcon(classFile)
  local coords = rawget(_G, "CLASS_ICON_TCOORDS")
  local c = classFile and coords and coords[classFile]
  if not c then return "" end
  return ("|TInterface\\TargetingFrame\\UI-Classes-Circles:14:14:0:0:256:256:%d:%d:%d:%d|t "):format(
    c[1] * 256, c[2] * 256, c[3] * 256, c[4] * 256)
end

local function GroupText(group, inherited)
  if not group then return "|cff5e5747–|r" end
  local color = GROUP_COLORS[ns.Family.GroupColor(group, #GROUP_COLORS)]
  local text = DOT:format(color[1], color[2], color[3]) .. group
  return inherited and ("|cff9a9080" .. text .. "|r") or text
end

-- average item level of a member from the statistics (tenths), nil when unknown
local function ItemLevel(guild, m)
  local record = guild and guild.members[m.key]
  local values = record and type(record.stats) == "table" and record.stats.v
  return values and values[ns.Stats.GEAR.ILVL] or nil
end

local function Build(panel)
  local L = ns.L
  local view = { filter = {}, query = "", sort = "level", desc = true }

  -- toolbar ------------------------------------------------------------------------------------
  local main = CreateFrame("Frame", nil, panel)
  main:SetPoint("TOPLEFT", 0, 0)
  main:SetPoint("BOTTOMRIGHT", 0, 0)

  local search = W.EditBox(main, 170)
  search:SetPoint("TOPLEFT", 54, -4) -- clear of the portrait
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

  -- the guild's own groups, as found in the notes
  view.GroupButton = W.MenuButton(main, L.FILTER_GROUP, function()
    local items = { { text = L.ALL, checked = view.group == nil, onClick = function() view.group = nil; view:Refresh() end } }
    for _, group in ipairs(view.groups or {}) do
      items[#items + 1] = { text = GroupText(group), checked = view.group == group, onClick = function() view.group = group; view:Refresh() end }
    end
    return items
  end, 90)
  view.GroupButton:SetPoint("LEFT", view.ProfButton, "RIGHT", 4, 0)

  local function Check(label, anchor, onClick)
    local check = CreateFrame("CheckButton", nil, main, "UICheckButtonTemplate")
    check:SetSize(24, 24)
    check:SetPoint("LEFT", anchor, "RIGHT", 6, 0)
    check:SetScript("OnClick", onClick)
    check.Label = W.Text(main, "GameFontHighlightSmall", label)
    check.Label:SetPoint("LEFT", check, "RIGHT", 0, 0)
    return check
  end
  local onlineCheck = Check(L.ONLINE_ONLY, view.GroupButton, function(self) view:SetFilterValue("onlineOnly", self:GetChecked() or nil) end)
  view.OnlineCheck = onlineCheck
  -- members whose public note is empty: who still needs one
  view.NoNoteCheck = Check(L.NO_NOTE, onlineCheck.Label, function(self) view.noNote = self:GetChecked() or nil; view:Refresh() end)
  -- the same for the officer note, only for those who may read it
  view.NoOfficerNoteCheck = Check(L.NO_OFFICER_NOTE, view.NoNoteCheck.Label, function(self)
    view.noOfficerNote = self:GetChecked() or nil
    view:Refresh()
  end)
  view.FoldCheck = Check(L.FOLD_TWINKS, view.NoOfficerNoteCheck.Label, function(self) view.fold = self:GetChecked() or nil; view:Refresh() end)

  view.Reset = W.Button(main, L.RESET, function()
    view.filter, view.group, view.noNote, view.noOfficerNote = {}, nil, nil, nil
    search:SetText("")
    onlineCheck:SetChecked(false)
    view.NoNoteCheck:SetChecked(false)
    view.NoOfficerNoteCheck:SetChecked(false)
    view:Refresh()
  end, 70, { small = true })
  view.Reset:SetPoint("LEFT", view.FoldCheck.Label, "RIGHT", 8, 0)

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
    if not UNSORTED[column.key] then
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
    local highlight = row:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints()
    highlight:SetColorTexture(1, 0.82, 0, 0.1)
    row:SetScript("OnMouseUp", function(self, button)
      if not self.member then return end
      if button == "RightButton" then
        UI.MemberMenu(self.member, self)
      else
        UI.MemberClick(self.member)
      end
    end)
    row:SetScript("OnEnter", function(self) if self.member then UI.MemberTooltip(self, self.member) end end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
  end, function(row, item)
    local m = item.m
    row.member = m
    local dim = not m.online
    local c = row.Cells
    c.level:SetText(m.level)
    -- twinks under their main are indented; a folded main shows how many hang on it
    local name = ClassIcon(m.classFile) .. W.ClassName(m.name, m.classFile)
    if item.child then name = "      " .. name .. "  |cff8f8268" .. L.TWINK .. "|r" end
    if item.more then name = name .. "  |cff8f8268+" .. item.more .. "|r" end
    c.name:SetText(name)
    c.zone:SetText(m.zone or "")
    c.rank:SetText(m.rank or "")
    c.group:SetText(GroupText(m.group, m.groupInherited))
    c.ilvl:SetText(m.ilvl and (string.format("%.1f", m.ilvl / 10):gsub("%.", L.DECIMAL_MARK)) or "")
    c.lastOnline:SetText(ns.Roster.LastOnlineText(m))
    c.guildy:SetText(UI.GuildyVersionText(m) or "")
    c.note:SetText((m.note and m.note ~= "") and m.note or ("|cffff9a5a" .. L.NO_NOTE_CELL .. "|r"))
    c.officerNote:SetText(not view.viewOfficer and ""
      or (m.officerNote and m.officerNote ~= "") and m.officerNote or ("|cffff9a5a" .. L.NO_NOTE_CELL .. "|r"))
    for key, cell in pairs(c) do
      if key ~= "name" and key ~= "group" and key ~= "note" and key ~= "officerNote" then
        if dim then cell:SetTextColor(0.6, 0.6, 0.6) else cell:SetTextColor(1, 1, 1) end
      end
    end
    for _, cell in ipairs({ c.note, c.officerNote }) do
      if dim then cell:SetTextColor(0.6, 0.6, 0.6) else cell:SetTextColor(1, 1, 1) end
    end
    if m.online then c.lastOnline:SetTextColor(unpack(ONLINE_COLOR)) end
    c.name:SetAlpha(dim and 0.7 or 1)
    c.group:SetAlpha(dim and 0.7 or 1)
  end)
  view.List:SetPoint("TOPLEFT", 4, -4)
  view.List:SetPoint("BOTTOMRIGHT", -26, 4)

  view.Summary = W.Text(header, "GameFontDisableSmall")
  view.Summary:SetPoint("RIGHT", header, "RIGHT", -28, 0)
  view.Summary:SetJustifyH("RIGHT")

  -- behaviour ----------------------------------------------------------------------------------
  function view:SetFilterValue(key, value)
    self.filter[key] = value
    if key == "bracket" then self.filter.level = nil end -- the level menu replaces a single level from the overview
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

  function view:Refresh()
    -- officer note column and filter only for those who may read officer notes
    self.viewOfficer = ns.Roster.Can().viewOfficer and true or false
    self.Headers.officerNote:SetShown(self.viewOfficer)
    self.NoOfficerNoteCheck:SetShown(self.viewOfficer)
    self.NoOfficerNoteCheck.Label:SetShown(self.viewOfficer)
    if not self.viewOfficer then self.noOfficerNote = nil; self.NoOfficerNoteCheck:SetChecked(false) end
    self.FoldCheck:ClearAllPoints()
    self.FoldCheck:SetPoint("LEFT", self.viewOfficer and self.NoOfficerNoteCheck.Label or self.NoNoteCheck.Label, "RIGHT", 6, 0)
    local members = ns.Roster.Members()
    local guild, db = ns.GuildData(), ns.DB()
    local mains = ns.Family.Mains(members, guild and guild.families, db and db.ownChars)
    local byKey, groupSet, noNote, noOfficerNote = {}, {}, 0, 0
    for _, m in ipairs(members) do
      m.guildy = m.online and ns.Sync.UserVersion(m.name) or nil
      m.ilvl = ItemLevel(guild, m)
      m.mainKey = mains[m.key]
      m.group = ns.Family.NoteGroup(m)
      m.groupInherited = nil
      byKey[m.key] = m
      if not m.note or m.note == "" then noNote = noNote + 1 end
      if not m.officerNote or m.officerNote == "" then noOfficerNote = noOfficerNote + 1 end
    end
    -- twinks take the group of their main
    for _, m in ipairs(members) do
      local mainMember = m.mainKey and m.mainKey ~= m.key and byKey[m.mainKey]
      if not m.group and mainMember and mainMember.group then m.group, m.groupInherited = mainMember.group, true end
      if m.group then groupSet[m.group] = true end
    end
    self.groups = {}
    for group in pairs(groupSet) do self.groups[#self.groups + 1] = group end
    table.sort(self.groups)
    if self.group and not groupSet[self.group] then self.group = nil end

    local list = ns.Search.Members(members, self.filter, self.query, ns.TradeSkill.ProfsOf)
    local kept = {}
    for _, m in ipairs(list) do
      if (not self.group or m.group == self.group) and (not self.noNote or not m.note or m.note == "")
        and (not self.noOfficerNote or not m.officerNote or m.officerNote == "") then
        kept[#kept + 1] = m
      end
    end
    ns.Search.SortMembers(kept, self.sort, self.desc)

    -- twinks right under their main (when the main is shown), or folded into it; flat while
    -- looking for members without a note
    local items = {}
    if self.noNote or self.noOfficerNote then
      for _, m in ipairs(kept) do items[#items + 1] = { m = m } end
    else
      local shown, twinksOf = {}, {}
      for _, m in ipairs(kept) do shown[m.key] = true end
      for _, m in ipairs(kept) do
        if m.mainKey and m.mainKey ~= m.key and shown[m.mainKey] then
          twinksOf[m.mainKey] = twinksOf[m.mainKey] or {}
          table.insert(twinksOf[m.mainKey], m)
        end
      end
      for _, m in ipairs(kept) do
        local isTwinkUnderMain = m.mainKey and m.mainKey ~= m.key and shown[m.mainKey]
        if not isTwinkUnderMain then
          local twinks = twinksOf[m.key]
          items[#items + 1] = { m = m, more = self.fold and twinks and #twinks or nil }
          if twinks and not self.fold then
            for _, twink in ipairs(twinks) do items[#items + 1] = { m = twink, child = true } end
          end
        end
      end
    end
    self.List:SetItems(items)
    self.Summary:SetText(L.SHOWN_COUNT:format(#kept, #members))
    self.NoNoteCheck.Label:SetText(L.NO_NOTE .. " |cffffd100" .. noNote .. "|r")
    self.NoOfficerNoteCheck.Label:SetText(L.NO_OFFICER_NOTE .. " |cffffd100" .. noOfficerNote .. "|r")
    Label(self.GroupButton, L.FILTER_GROUP, self.group)
    Label(self.ClassButton, L.FILTER_CLASS, self.filter.classFile and ClassLabel(self.filter.classFile))
    Label(self.LevelButton, L.FILTER_LEVEL, (self.filter.level and tostring(self.filter.level))
      or (self.filter.bracket and ns.Census.BracketLabel(self.filter.bracket)))
    Label(self.ProfButton, L.FILTER_PROFESSION, self.filter.skillLine and ns.TradeSkill.Name(self.filter.skillLine))
    for key, button in pairs(self.Headers) do
      local text = L["COL_" .. key:upper()]
      if key == self.sort then text = text .. (self.desc and " v" or " ^") end
      button.Text:SetText(text)
    end
  end

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
