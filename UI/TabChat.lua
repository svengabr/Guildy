-- Chat tab (shown first): channel switch, the guild / officer chat with history and an input line,
-- and on the right the online list (level, class-colored name, profession icons, zone) with the
-- guild invite button.
local _, ns = ...
local W = ns.Widgets
local UI = ns.UI

local LIST_WIDTH = 290
local ZONE_WIDTH = 104
local ROW = 18
local date = rawget(_G, "date") or os.date

local function ChatColor(kind)
  local info = ChatTypeInfo and ChatTypeInfo[kind == "officer" and "OFFICER" or "GUILD"]
  if info then return info.r, info.g, info.b end
  if kind == "officer" then return 0.25, 0.75, 0.25 end
  return 0.25, 1, 0.25
end

local function Stamp(ts)
  if not ts or ts <= 0 then return "" end
  return "|cff8d836e" .. date("%H:%M", ts) .. "|r " -- warm grey: present, but the names lead
end

local function FormatLine(line)
  if line.system then return Stamp(line.ts) .. "|cffa0a0a0" .. line.text .. "|r" end
  -- an author who left the guild and whose name nobody knows any more: grey, not clickable
  local link = line.unknown and ("|cff8d836e[" .. line.sender .. "]|r")
    or ("|Hplayer:" .. (line.senderFull or line.sender) .. "|h[" .. W.ClassName(line.sender, line.classFile) .. "]|h")
  return Stamp(line.ts) .. link .. ": " .. (line.text or "")
end

-- Weekday of ts from a comma separated list starting with Sunday
local function Weekday(list, ts)
  local index = tonumber(date("%w", ts))
  for name in (list or ""):gmatch("[^,]+") do
    if index == 0 then return name end
    index = index - 1
  end
  return nil
end

-- 0 for today, 1 for yesterday, 2 for older days
local function DayAge(ts)
  local day, now = date("%Y-%m-%d", ts), ns.Now()
  if day == date("%Y-%m-%d", now) then return 0 end
  if day == date("%Y-%m-%d", now - 86400) then return 1 end
  return 2
end

-- "Today", "Yesterday" or the weekday with the date
local function DayLabel(ts)
  local L, age = ns.L, DayAge(ts)
  if age == 0 then return L.CHAT_TODAY end
  if age == 1 then return L.CHAT_YESTERDAY end
  local weekday = Weekday(L.WEEKDAYS, ts)
  return (weekday and weekday .. ", " or "") .. date("%d.%m.%Y", ts)
end

-- Short day name for the timeline: "Today", "Yest.", the weekday within a week, else the date
local function DayShort(ts)
  local L, age = ns.L, DayAge(ts)
  if age == 0 then return L.CHAT_TODAY end
  if age == 1 then return L.CHAT_YESTERDAY_SHORT end
  if ns.Now() - ts < 6 * 86400 then return Weekday(L.WEEKDAYS_SHORT, ts) or date("%d.%m.", ts) end
  return date("%d.%m.", ts)
end

local SORTS = { level = true, name = true, zone = true }

local function SortOnline(list, field)
  local Search = ns.Search
  if field == "name" then return Search.SortMembers(list, "name") end
  if field == "zone" then return Search.SortMembers(list, "zone") end
  return Search.SortMembers(list, "level", true)
end

local function Build(panel)
  local L = ns.L
  local view = { kind = "guild" }

  -- right: online list -------------------------------------------------------------------------
  local right = CreateFrame("Frame", nil, panel)
  right:SetPoint("TOPRIGHT", 0, 0)
  right:SetPoint("BOTTOMRIGHT", 0, 0)
  right:SetWidth(LIST_WIDTH)

  view.Count = W.Text(right, "GameFontNormal")
  view.Count:SetPoint("TOPLEFT", 4, -6)
  view.SortButton = W.MenuButton(right, L.SORT_LABEL_LEVEL, function()
    local items = {}
    for _, field in ipairs({ "level", "name", "zone" }) do
      items[#items + 1] = { text = L["SORT_BY_" .. field:upper()], checked = ns.Settings().listSort == field,
        onClick = function()
          ns.Settings().listSort = field
          view:Refresh()
        end }
    end
    return items
  end, 110)
  view.SortButton:SetPoint("TOPRIGHT", 0, -2)

  local listBox = W.Box(right)
  listBox:SetPoint("TOPLEFT", 0, -28)
  listBox:SetPoint("BOTTOMRIGHT", 0, 30)
  view.List = W.ScrollList(listBox, ROW, function(row)
    row:EnableMouse(true)
    row.Level = W.Text(row, "GameFontDisableSmall")
    row.Level:SetPoint("LEFT", 2, 0)
    row.Level:SetWidth(18)
    row.Level:SetJustifyH("RIGHT")
    row.Zone = W.Text(row, "GameFontDisableSmall")
    row.Zone:SetPoint("RIGHT", -2, 0)
    row.Zone:SetWidth(ZONE_WIDTH)
    row.Zone:SetJustifyH("RIGHT")
    row.Zone:SetWordWrap(false)
    row.Profs = {}
    for i = 1, 2 do
      row.Profs[i] = W.ProfIcon(row, 13)
      row.Profs[i]:SetPoint("RIGHT", row.Zone, "LEFT", -4 - (2 - i) * 15, 0)
    end
    row.Name = W.Text(row, "GameFontHighlightSmall")
    row.Name:SetPoint("LEFT", 24, 0)
    row.Name:SetPoint("RIGHT", row.Zone, "LEFT", -36, 0)
    row.Name:SetWordWrap(false)
    local highlight = row:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints()
    highlight:SetColorTexture(1, 0.82, 0, 0.12)
    row:SetScript("OnEnter", function(self) if self.member then UI.MemberTooltip(self, self.member) end end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    row:SetScript("OnMouseUp", function(self, button)
      if not self.member then return end
      if button == "RightButton" then UI.MemberMenu(self.member, self) else UI.MemberClick(self.member) end
    end)
  end, function(row, m)
    row.member = m
    row.Level:SetText(m.level)
    row.Name:SetText(W.ClassName(m.name, m.classFile) .. (m.rankIndex == 0 and " |cffffd100*|r" or ""))
    row.Zone:SetText(m.zone or "")
    local profs = ns.TradeSkill.ProfsOf(m)
    local shown = 0
    if profs then
      for _, skillLine in ipairs(ns.Professions.ORDER) do
        if profs[skillLine] and ns.Professions.PRIMARY[skillLine] and shown < 2 then
          shown = shown + 1
          row.Profs[shown].Icon:SetTexture(ns.Professions.ICONS[skillLine])
          row.Profs[shown]:Show()
        end
      end
    end
    for i = shown + 1, 2 do row.Profs[i]:Hide() end
  end)
  view.List:SetPoint("TOPLEFT", 4, -4)
  view.List:SetPoint("BOTTOMRIGHT", -16, 4)
  W.SlimScrollBar(view.List, 4) -- same slim gold track as the chat timeline

  view.InviteButton = W.Button(right, L.INVITE_MEMBER, nil, 150)
  UI.SecureAction(view.InviteButton, function() return UI.InviteAction() end, nil,
    function() ns.Print(ns.L.INVITE_UNAVAILABLE) end)
  view.InviteButton:SetPoint("BOTTOMRIGHT", 0, 2)

  -- left: chat ---------------------------------------------------------------------------------
  local left = CreateFrame("Frame", nil, panel)
  left:SetPoint("TOPLEFT", 0, 0)
  left:SetPoint("BOTTOMRIGHT", right, "BOTTOMLEFT", -8, 0)

  view.Channel = W.MenuButton(left, L.CHANNEL_GUILD, function()
    local items = { { text = L.CHANNEL_GUILD, checked = view.kind == "guild", onClick = function() view:SetKind("guild") end } }
    if ns.Roster.Can().officerChat then
      items[#items + 1] = { text = L.CHANNEL_OFFICER, checked = view.kind == "officer", onClick = function() view:SetKind("officer") end }
    end
    return items
  end, 130)
  view.Channel:SetPoint("TOPLEFT", 50, -2) -- clear of the portrait

  local chatBox = W.Box(left)
  chatBox:SetPoint("TOPLEFT", 0, -28)
  chatBox:SetPoint("BOTTOMRIGHT", 0, 30)
  local messages = CreateFrame("ScrollingMessageFrame", nil, chatBox)
  local Timeline = ns.ChatTimeline
  messages:SetPoint("TOPLEFT", 8, -(Timeline.HEADER_HEIGHT + 6)) -- strip on top for the pinned day
  messages:SetPoint("BOTTOMRIGHT", -(Timeline.RAIL_WIDTH + 8), 6)
  local fontObject = rawget(_G, "ChatFontNormal")
  if fontObject then
    messages:SetFontObject(fontObject)
    local font, size, flags = fontObject:GetFont()
    if font then messages:SetFont(font, (size or 13) + 1, flags or "") end
  end
  messages:SetJustifyH("LEFT")
  messages:SetFading(false)
  messages:SetMaxLines(4000)
  if messages.SetIndentedWordWrap then pcall(messages.SetIndentedWordWrap, messages, true) end
  if messages.SetHyperlinksEnabled then messages:SetHyperlinksEnabled(true) end
  messages:EnableMouseWheel(true)
  messages:SetScript("OnMouseWheel", function(self, delta)
    if IsShiftKeyDown() then
      if delta > 0 then self:ScrollToTop() else self:ScrollToBottom() end
    elseif delta > 0 then
      self:ScrollUp(); self:ScrollUp()
    else
      self:ScrollDown(); self:ScrollDown()
    end
    view.Timeline:Update()
  end)
  messages:SetScript("OnHyperlinkClick", function(_, link, text, button)
    -- guild members: left click opens the character page, right click Guildy's menu; shift-click
    -- and everyone else keep Blizzard's behaviour
    local name = type(link) == "string" and link:match("^player:([^:]+)")
    local member = name and ns.Roster.Find(name)
    if member and button == "RightButton" then
      UI.MemberMenu(member)
      return
    elseif member and not IsShiftKeyDown() then
      UI.ShowMember(member)
      return
    end
    local setItemRef = rawget(_G, "SetItemRef")
    if setItemRef then pcall(setItemRef, link, text, button, DEFAULT_CHAT_FRAME) end
  end)
  messages:SetScript("OnHyperlinkEnter", function(self, link)
    local kind = link:match("^(%a+):")
    if kind == "item" or kind == "spell" or kind == "enchant" or kind == "quest" or kind == "achievement" then
      GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
      pcall(GameTooltip.SetHyperlink, GameTooltip, link)
      GameTooltip:Show()
    end
  end)
  messages:SetScript("OnHyperlinkLeave", function() GameTooltip:Hide() end)
  view.Messages = messages
  -- at the top the timeline fetches older messages (they arrive as CLUB_MESSAGE_HISTORY_RECEIVED)
  view.Timeline = Timeline.Create(chatBox, messages, {
    label = DayLabel, short = DayShort, newLabel = L.CHAT_NEW_SINCE, newShort = L.CHAT_NEW_SHORT,
    latestText = function(count) return count == 1 and L.CHAT_NEWER_ONE or L.CHAT_NEWER_MANY:format(count) end,
    status = function() return ns.Chat.HistoryState(view.kind) end,
    statusText = { loading = L.CHAT_LOADING_OLDER, start = L.CHAT_HISTORY_START },
    onTop = function() ns.Chat.LoadOlder(view.kind) end,
  })

  local input = CreateFrame("EditBox", nil, left, "InputBoxTemplate")
  input:SetPoint("BOTTOMLEFT", 6, 4)
  input:SetPoint("BOTTOMRIGHT", 0, 4)
  input:SetHeight(22)
  input:SetAutoFocus(false)
  input:SetMaxLetters(255)
  -- the channel the line goes to, left in the field, plus a placeholder while empty
  input.Channel = W.Text(input, "ChatFontNormal")
  input.Channel:SetPoint("LEFT", 2, 0)
  input.Placeholder = W.Text(input, "GameFontDisable")
  input.Placeholder:SetPoint("LEFT", input.Channel, "RIGHT", 6, 0)
  input.Placeholder:SetTextColor(0.55, 0.51, 0.43)
  function input:ShowChannel(kind)
    local r, g, b = ChatColor(kind)
    self.Channel:SetText((kind == "officer" and L.CHANNEL_OFFICER or L.CHANNEL_GUILD) .. ":")
    self.Channel:SetTextColor(r, g, b)
    self.Placeholder:SetText(kind == "officer" and L.CHAT_PLACEHOLDER_OFFICER or L.CHAT_PLACEHOLDER_GUILD)
    self:SetTextInsets(math.ceil(self.Channel:GetStringWidth() or 40) + 8, 4, 0, 0)
    self.Placeholder:SetShown((self:GetText() or "") == "")
  end
  input:SetScript("OnTextChanged", function(self) self.Placeholder:SetShown((self:GetText() or "") == "") end)
  input:SetScript("OnEnterPressed", function(self)
    ns.Chat.Send(view.kind, self:GetText())
    self:SetText("")
    self:ClearFocus()
  end)
  input:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  view.Input = input
  input:ShowChannel("guild")
  -- shift-clicked links go into our input while it has focus
  local function InsertLink(link)
    if input:IsVisible() and input:HasFocus() and type(link) == "string" then input:Insert(link) end
  end
  if rawget(_G, "ChatEdit_InsertLink") then hooksecurefunc("ChatEdit_InsertLink", InsertLink) end

  function view:SetKind(kind)
    self.kind = kind
    self.Channel:SetText(kind == "officer" and L.CHANNEL_OFFICER or L.CHANNEL_GUILD)
    self.Input:ShowChannel(kind)
    ns.Chat.Focus(true, kind)
    self.rendered = nil
    self:RenderChat()
  end

  function view:RenderChat()
    -- keep the reading position when scrolled up: the offset counts from the bottom, so older lines
    -- added on top do not move what is shown
    local frame = self.Messages
    local offset = self.rendered and frame.GetScrollOffset and frame:GetScrollOffset() or 0
    frame:Clear()
    local r, g, b = ChatColor(self.kind)
    local lastDay, days, count, newIndex = nil, {}, 0, nil
    local seen, prevTs = ns.Chat.SeenMark(), nil
    for _, line in ipairs(ns.Chat.History(self.kind)) do
      local day = line.ts and line.ts > 0 and date("%Y-%m-%d", line.ts)
      if day and day ~= lastDay then
        frame:AddMessage("|cffd4a017—— " .. DayLabel(line.ts) .. " ——|r", 1, 1, 1)
        count = count + 1
        days[#days + 1] = { index = count, ts = line.ts }
        lastDay = day
      end
      -- "new since your last login" between the last line before the mark and the first after it
      if seen and not newIndex and prevTs and prevTs <= seen and (line.ts or 0) > seen then
        frame:AddMessage("|cffff8c40—— " .. L.CHAT_NEW_SINCE .. " ——|r", 1, 1, 1)
        count = count + 1
        newIndex = count
      end
      prevTs = line.ts or prevTs
      if line.system then
        frame:AddMessage(FormatLine(line), 0.63, 0.63, 0.63)
      else
        frame:AddMessage(FormatLine(line), r, g, b)
      end
      count = count + 1
    end
    if offset > 0 and frame.SetScrollOffset then frame:SetScrollOffset(offset) else frame:ScrollToBottom() end
    self.rendered = true
    self.Timeline:SetDays(days, count, newIndex)
  end

  function view:RenderList()
    local online, total = ns.Roster.Counts()
    self.Count:SetText(L.ONLINE_COUNT:format(online, total))
    local field = ns.Settings().listSort
    if not SORTS[field] then field = "level" end
    self.SortButton:SetText(L["SORT_LABEL_" .. field:upper()])
    self.List:SetItems(SortOnline(ns.Roster.Online(), field))
    self.InviteButton:SetShown(ns.Roster.Can().invite)
  end

  function view:Refresh(event, kind)
    if event == "CHAT" then
      if kind == nil or kind == self.kind then self:RenderChat() end
      return
    end
    if event == "ROSTER" or event == "PROFS" then
      self:RenderList()
      return
    end
    self:RenderList()
    self:RenderChat()
  end

  function view:OnShow()
    ns.Chat.Focus(true, self.kind)
  end

  function view:OnHide()
    ns.Chat.Focus(false)
  end

  return view
end

UI.RegisterTab("chat", 1, ns.L.TAB_CHAT, Build)
