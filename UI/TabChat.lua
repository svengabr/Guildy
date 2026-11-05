-- Chat tab (shown first): channel switch, the guild / officer chat with history and an input line,
-- and on the right the online list (level, class-colored name, profession icons, zone) with the
-- guild invite button.
local _, ns = ...
local W = ns.Widgets
local UI = ns.UI

local LIST_WIDTH = 250
local ROW = 18

local function ChatColor(kind)
  local info = ChatTypeInfo and ChatTypeInfo[kind == "officer" and "OFFICER" or "GUILD"]
  if info then return info.r, info.g, info.b end
  if kind == "officer" then return 0.25, 0.75, 0.25 end
  return 0.25, 1, 0.25
end

local function FormatLine(line)
  if line.system then return "|cffa0a0a0" .. line.text .. "|r" end
  local link = "|Hplayer:" .. (line.senderFull or line.sender) .. "|h[" .. W.ClassName(line.sender, line.classFile) .. "]|h"
  return link .. ": " .. (line.text or "")
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
  view.SortButton = W.MenuButton(right, L.SORT_BY_LEVEL, function()
    local items = {}
    for _, field in ipairs({ "level", "name", "zone" }) do
      items[#items + 1] = { text = L["SORT_BY_" .. field:upper()], checked = ns.Settings().listSort == field,
        onClick = function()
          ns.Settings().listSort = field
          view:Refresh()
        end }
    end
    return items
  end, 90)
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
    row.Zone:SetWidth(62)
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
      if button == "RightButton" then UI.MemberMenu(self.member, self) else UI.Whisper(self.member.fullName) end
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
  view.List:SetPoint("BOTTOMRIGHT", -26, 4)

  view.InviteButton = W.Button(right, L.INVITE_MEMBER, nil, 150)
  UI.SecureAction(view.InviteButton, function() return UI.InviteAction() end)
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
  view.Channel:SetPoint("TOPLEFT", 0, -2)

  local chatBox = W.Box(left)
  chatBox:SetPoint("TOPLEFT", 0, -28)
  chatBox:SetPoint("BOTTOMRIGHT", 0, 30)
  local messages = CreateFrame("ScrollingMessageFrame", nil, chatBox)
  messages:SetPoint("TOPLEFT", 8, -6)
  messages:SetPoint("BOTTOMRIGHT", -8, 6)
  local fontObject = rawget(_G, "ChatFontNormal")
  if fontObject then
    messages:SetFontObject(fontObject)
    local font, size, flags = fontObject:GetFont()
    if font then messages:SetFont(font, (size or 13) + 1, flags or "") end
  end
  messages:SetJustifyH("LEFT")
  messages:SetFading(false)
  messages:SetMaxLines(500)
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
  end)
  messages:SetScript("OnHyperlinkClick", function(_, link, text, button)
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

  local input = CreateFrame("EditBox", nil, left, "InputBoxTemplate")
  input:SetPoint("BOTTOMLEFT", 6, 4)
  input:SetPoint("BOTTOMRIGHT", 0, 4)
  input:SetHeight(22)
  input:SetAutoFocus(false)
  input:SetMaxLetters(255)
  input:SetScript("OnEnterPressed", function(self)
    ns.Chat.Send(view.kind, self:GetText())
    self:SetText("")
    self:ClearFocus()
  end)
  input:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  view.Input = input
  -- shift-clicked links go into our input while it has focus
  local function InsertLink(link)
    if input:IsVisible() and input:HasFocus() and type(link) == "string" then input:Insert(link) end
  end
  if rawget(_G, "ChatEdit_InsertLink") then hooksecurefunc("ChatEdit_InsertLink", InsertLink) end

  function view:SetKind(kind)
    self.kind = kind
    self.Channel:SetText(kind == "officer" and L.CHANNEL_OFFICER or L.CHANNEL_GUILD)
    self:RenderChat()
  end

  function view:RenderChat()
    self.Messages:Clear()
    local r, g, b = ChatColor(self.kind)
    for _, line in ipairs(ns.Chat.History(self.kind)) do
      if line.system then
        self.Messages:AddMessage(FormatLine(line), 0.63, 0.63, 0.63)
      else
        self.Messages:AddMessage(FormatLine(line), r, g, b)
      end
    end
    self.Messages:ScrollToBottom()
  end

  function view:RenderList()
    local online, total = ns.Roster.Counts()
    self.Count:SetText(L.ONLINE_COUNT:format(online, total))
    local field = ns.Settings().listSort
    if not SORTS[field] then field = "level" end
    self.SortButton:SetText(L["SORT_BY_" .. field:upper()])
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
    ns.Chat.Focus(true)
  end

  function view:OnHide()
    ns.Chat.Focus(false)
  end

  return view
end

UI.RegisterTab("chat", 1, ns.L.TAB_CHAT, Build)
