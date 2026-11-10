-- Communities view (side tab under the account): the player's communities on the left with lines that
-- came in unseen, the chat of the selected one in the middle (channel switch, history, timeline, input,
-- the same column as the guild chat) and its members on the right, online first. Guildy covers
-- Blizzard's guild window, whose communities part does not work under it, so the communities live
-- here. Works without a guild. Invitations stand first in the list; joining with a link and creating
-- have their own panel. Blizzard's own buttons and dialogs do what addons may not (UI/Commands.lua).
local _, ns = ...
local W = ns.Widgets
local UI = ns.UI

local ROW = 42
local MEMBER_ROW = 18

local selectedClub, selectedStream -- session only, like the last tab
local selectedInvite -- an invitation shown instead of a community (its clubId)

local function ChatColor()
  local info = ChatTypeInfo and (ChatTypeInfo.COMMUNITIES_CHANNEL or ChatTypeInfo.CHANNEL)
  if info and info.r then return info.r, info.g, info.b end
  return 1, 0.75, 0.75
end

-- A whisper to name in Blizzard's chat input (it stays Blizzard's: nothing of it is touched besides)
local function Whisper(full)
  local tell = rawget(_G, "ChatFrame_SendTell")
  if tell and full then pcall(tell, full) end
end

local function Build(panel)
  local L = ns.L
  local view = {}

  -- left: the communities -----------------------------------------------------------------------------
  local page = W.Page(panel)
  local bar = page.Bar
  panel = page.Body
  local left = CreateFrame("Frame", nil, panel)
  left:SetPoint("TOPLEFT", 0, 0)
  left:SetPoint("BOTTOMLEFT", 0, 0)
  left:SetWidth(W.SIDE)
  local listBox = W.Box(left)
  listBox:SetAllPoints()
  view.Clubs = W.ScrollList(listBox, ROW, function(row)
    row:EnableMouse(true)
    row.Selected = row:CreateTexture(nil, "BACKGROUND", nil, 1)
    row.Selected:SetAllPoints()
    row.Selected:SetColorTexture(W.GOLD[1], W.GOLD[2], W.GOLD[3], 0.22)
    -- the community's avatar, round with a thin gold rim like the character page's portraits (the
    -- communities icon until the avatar can be drawn)
    row.Portrait = UI.CharParts.Portrait(row, 38)
    row.Portrait:SetPoint("LEFT", 4, 0)
    row.Portrait.Ring:SetVertexColor(W.GOLD[1], W.GOLD[2], W.GOLD[3])
    row.Avatar = row.Portrait.Picture
    -- favorites: Blizzard's own star at the top left of the icon
    row.Favorite = row:CreateTexture(nil, "OVERLAY", nil, 6)
    W.SetAtlasOr(row.Favorite, "collections-icon-favorites", 1, 0.82, 0)
    row.Favorite:SetSize(22, 22)
    row.Favorite:SetPoint("TOPLEFT", row.Portrait, "TOPLEFT", -5, 5)
    row.Favorite:Hide()
    row.Unread = W.Text(row, "GameFontNormalSmall")
    row.Unread:SetPoint("RIGHT", -6, 0)
    row.Unread:SetTextColor(1, 0.55, 0.25)
    row.Name = W.Text(row, "GameFontHighlight")
    row.Name:SetPoint("TOPLEFT", row.Portrait, "TOPRIGHT", 7, -3)
    row.Name:SetPoint("RIGHT", row.Unread, "LEFT", -4, 0)
    row.Name:SetJustifyH("LEFT")
    row.Name:SetWordWrap(false)
    row.Info = W.Text(row, "GameFontDisableSmall")
    row.Info:SetPoint("BOTTOMLEFT", row.Portrait, "BOTTOMRIGHT", 7, 4)
    row.Info:SetPoint("RIGHT", row.Unread, "LEFT", -4, 0)
    row.Info:SetJustifyH("LEFT")
    row.Info:SetWordWrap(false)
    local highlight = row:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints()
    highlight:SetColorTexture(1, 0.82, 0, 0.12)
    local function Pick(club)
      if club.invite then view:SelectInvite(club.clubId) else view:Select(club.clubId) end
    end
    row:SetScript("OnMouseUp", function(self, button)
      if self.club and button ~= "RightButton" then Pick(self.club) end
    end)
    -- every click also goes to the community's (or invitation's) entry in Blizzard's list underneath
    -- (secure click, like the notes): left picks it there, so Blizzard's invite button and invitation
    -- frame work on it; right opens Blizzard's own menu for it (leave the community, ...)
    UI.OptionalAction(row, function(self)
      local club = self.club
      return club and UI.Action.ClubEntry(club.clubId, function(button)
        if button ~= "RightButton" then Pick(club) end
      end)
    end)
  end, function(row, club)
    row.club = club
    row.Name:SetText(club.name)
    -- the community's own icon; another community's icon must not stay from a reused row
    local avatar = ns.Communities.Avatar(club, view.drawAvatars)
    if avatar then
      row.Avatar:SetTexture(avatar.file)
      row.Avatar:SetTexCoord(unpack(avatar.coords))
    else
      row.Avatar:SetTexture(UI.CommunitiesIcon())
      row.Avatar:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    end
    row.Favorite:SetShown(club.favorite == true)
    if club.invite then
      -- an invitation: orange, from whom
      row.Info:SetText("|cffff8c40" .. (club.inviter and L.COMMUNITIES_INVITATION_FROM:format(club.inviter)
        or L.COMMUNITIES_INVITATION) .. "|r")
    else
      local count = tonumber(club.memberCount)
      local members = count and (count == 1 and L.COMMUNITIES_ONE_MEMBER or L.COMMUNITIES_MEMBERS:format(count)) or ""
      local short = club.shortName and club.shortName ~= "" and club.shortName or nil
      row.Info:SetText(short and members ~= "" and (short .. ns.L.SEP .. members) or short or members)
    end
    if club.invite then
      row.Selected:SetShown(club.clubId == selectedInvite)
    else
      row.Selected:SetShown(not selectedInvite and club.clubId == selectedClub)
    end
    -- the number of new lines, or a dot for what was already unread at the login
    row.Unread:SetText((club.unread or 0) > 0 and tostring(club.unread) or (club.hasUnread and "•" or ""))
  end)
  -- rows to the box's edges (the slim bar lies over their right end when the list scrolls)
  view.Clubs:SetPoint("TOPLEFT", 3, -3)
  view.Clubs:SetPoint("BOTTOMRIGHT", -3, 3)
  W.SlimScrollBar(view.Clubs, 4)
  -- joining: Guildy's own panel in the middle (invite link, creating); invitations are in the list
  view.JoinButton = W.Button(bar, L.COMMUNITIES_JOIN, function() view:ShowJoin(not view.joining) end, 150,
    { small = true })

  -- right: the members ----------------------------------------------------------------------------------
  local right = CreateFrame("Frame", nil, panel)
  right:SetPoint("TOPRIGHT", 0, 0)
  right:SetPoint("BOTTOMRIGHT", 0, 0)
  right:SetWidth(W.SIDE)
  view.Count = W.Text(bar, "GameFontNormalSmall")
  local membersBox = W.Box(right)
  membersBox:SetAllPoints()
  -- inviting: Guildy's button clicks Blizzard's own "Invite member" (InviteToClub is forbidden for
  -- addons); its dialog opens over Guildy. Blizzard's window must show the community: when it still
  -- shows another club, the first click picks it there and the next one invites.
  view.InviteSend = W.Button(bar, L.COMMUNITIES_INVITE_BUTTON, nil, 150, { small = true })
  -- toolbar, from the right: invite members, join a community, the online count
  page:Right(view.InviteSend)
  page:Right(view.JoinButton)
  page:Right(view.Count, 10)
  UI.SecureAction(view.InviteSend, function(button)
    return UI.Action.CommunityInvite(selectedClub) or UI.Action.SelectClub(selectedClub, function()
      ns.Print(L.COMMUNITIES_INVITE_AGAIN)
      C_Timer.After(0.2, function() UI.RefreshSecureAction(button) end)
    end)
  end, nil, function() ns.Print(L.COMMUNITIES_INVITE_UNAVAILABLE) end)
  view.Members = W.ScrollList(membersBox, MEMBER_ROW, function(row)
    row:EnableMouse(true)
    row.Level = W.Text(row, "GameFontDisableSmall")
    row.Level:SetPoint("LEFT", 2, 0)
    row.Level:SetWidth(18)
    row.Level:SetJustifyH("RIGHT")
    row.Zone = W.Text(row, "GameFontDisableSmall")
    row.Zone:SetPoint("RIGHT", -2, 0)
    row.Zone:SetWidth(96)
    row.Zone:SetJustifyH("RIGHT")
    row.Zone:SetWordWrap(false)
    -- a member note (Blizzard's "Member note" of its member menu): an icon here, the text in the tooltip
    row.Note = row:CreateTexture(nil, "ARTWORK")
    row.Note:SetTexture("Interface\\Buttons\\UI-GuildButton-PublicNote-Up")
    row.Note:SetSize(14, 14)
    row.Note:SetPoint("RIGHT", row.Zone, "LEFT", -4, 0)
    row.Note:Hide()
    row.Name = W.Text(row, "GameFontHighlightSmall")
    row.Name:SetPoint("LEFT", 24, 0)
    row.Name:SetPoint("RIGHT", row.Note, "LEFT", -2, 0)
    row.Name:SetJustifyH("LEFT")
    row.Name:SetWordWrap(false)
    local highlight = row:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints()
    highlight:SetColorTexture(1, 0.82, 0, 0.12)
    row:SetScript("OnEnter", function(self)
      local m = self.member
      if not m then return end
      GameTooltip:SetOwner(self, "ANCHOR_LEFT")
      GameTooltip:AddLine(W.ClassName(m.full or m.name, m.classFile))
      if m.level and m.level > 0 then GameTooltip:AddLine(L.COMMUNITIES_LEVEL:format(m.level), 1, 1, 1) end
      if m.zone and m.zone ~= "" then GameTooltip:AddLine(m.zone, 0.7, 0.7, 0.7) end
      if m.note then GameTooltip:AddLine(L.COMMUNITIES_NOTE:format(m.note), 1, 0.82, 0, true) end
      if not m.isSelf then GameTooltip:AddLine(L.COMMUNITIES_WHISPER_HINT, 0.55, 0.51, 0.43) end
      GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    -- a left click whispers; the right click goes to the member's row in Blizzard's member list
    -- underneath (secure click), which opens Blizzard's own member menu
    row:SetScript("OnMouseUp", function(self, button)
      local m = self.member
      if m and not m.isSelf and button ~= "RightButton" then Whisper(m.full) end
    end)
    UI.OptionalAction(row, function(self)
      local m = self.member
      return m and UI.Action.ClubMember(selectedClub, m.guid, function(button)
        if button ~= "RightButton" and not m.isSelf then Whisper(m.full) end
      end)
    end, function(self)
      -- the secure button lies over the row and hides its own tooltip: the same lines go onto it
      local m = self.member
      if not m then return nil end
      local lines = { W.ClassName(m.full or m.name, m.classFile) }
      if m.level and m.level > 0 then lines[#lines + 1] = L.COMMUNITIES_LEVEL:format(m.level) end
      if m.zone and m.zone ~= "" then lines[#lines + 1] = "|cffb3b3b3" .. m.zone .. "|r" end
      if m.note then lines[#lines + 1] = "|cffffd100" .. L.COMMUNITIES_NOTE:format(m.note) .. "|r" end
      if not m.isSelf then lines[#lines + 1] = "|cff8d836e" .. L.COMMUNITIES_WHISPER_HINT .. "|r" end
      return table.concat(lines, "\n")
    end)
  end, function(row, m)
    row.member = m
    row.Note:SetShown(m.note ~= nil)
    row.Level:SetText(m.level and m.level > 0 and m.level or "")
    if m.online then
      row.Name:SetText(W.ClassName(m.name, m.classFile))
      row.Zone:SetText(m.zone or "")
    else
      row.Name:SetText("|cff8d836e" .. m.name .. "|r")
      row.Zone:SetText("")
    end
  end)
  view.Members:SetPoint("TOPLEFT", 4, -4)
  view.Members:SetPoint("BOTTOMRIGHT", -16, 4)
  W.SlimScrollBar(view.Members, 4)

  -- middle: the chat ------------------------------------------------------------------------------------
  local middle = CreateFrame("Frame", nil, panel)
  middle:SetPoint("TOPLEFT", left, "TOPRIGHT", 8, 0)
  middle:SetPoint("BOTTOMRIGHT", right, "BOTTOMLEFT", -8, 0)
  view.Channel = W.MenuButton(bar, "", function()
    local items = {}
    for _, stream in ipairs(ns.Communities.Streams(selectedClub)) do
      items[#items + 1] = { text = stream.name, checked = stream.streamId == selectedStream,
        onClick = function() view:SelectStream(stream.streamId) end }
    end
    return items
  end, 160, 260)
  page:Left(view.Channel)
  local chatBox = W.Box(middle)
  chatBox:SetPoint("TOPLEFT", 0, 0)
  chatBox:SetPoint("BOTTOMRIGHT", 0, 28)
  view.Pane = UI.ChatPane(chatBox, {
    status = function() return ns.Communities.HistoryState(selectedClub, selectedStream) end,
    onTop = function() ns.Communities.LoadOlder(selectedClub, selectedStream) end,
  })
  view.Input = UI.ChatInput(middle, function(text)
    if not ns.Communities.Send(selectedClub, selectedStream, text) then ns.Print(L.COMMUNITIES_SEND_FAILED) end
  end)

  -- the join panel over the chat (the join button, or without communities): an invite link or code,
  -- and creating a community
  local join = W.Box(middle)
  join:SetPoint("TOPLEFT", 0, 0)
  join:SetPoint("BOTTOMRIGHT", 0, 0)
  join:SetFrameLevel(chatBox:GetFrameLevel() + 20)
  join:EnableMouse(true)
  join:Hide()
  view.Join = join
  join.Intro = W.Text(join, "GameFontHighlight")
  join.Intro:SetPoint("TOPLEFT", 16, -14)
  join.Intro:SetPoint("RIGHT", -16, 0)
  join.Intro:SetJustifyH("LEFT")
  join.Intro:SetSpacing(3)
  join.LinkTitle = W.Text(join, "GameFontNormal", L.COMMUNITIES_LINK)
  join.LinkTitle:SetPoint("TOPLEFT", join.Intro, "BOTTOMLEFT", 0, -18)
  join.Link = W.EditBox(join, 320)
  join.Link:SetPoint("TOPLEFT", join.LinkTitle, "BOTTOMLEFT", 6, -8)
  join.Link:SetMaxLetters(200)
  local function Redeem()
    local result = ns.Communities.Redeem(join.Link:GetText())
    if result == "invalid" then
      ns.Print(L.COMMUNITIES_LINK_INVALID)
    else
      join.Link:SetText("")
    end
    join.Link:ClearFocus()
  end
  join.Link:SetScript("OnEnterPressed", Redeem)
  -- a shift-clicked invite link in the chat goes into the field while it has focus
  if rawget(_G, "ChatEdit_InsertLink") then
    hooksecurefunc("ChatEdit_InsertLink", function(link)
      if join.Link:IsVisible() and join.Link:HasFocus() and type(link) == "string" then join.Link:Insert(link) end
    end)
  end
  join.Redeem = W.Button(join, L.COMMUNITIES_JOIN_BUTTON, Redeem, 100)
  join.Redeem:SetPoint("LEFT", join.Link, "RIGHT", 8, 0)
  join.Hint = W.Text(join, "GameFontDisableSmall", L.COMMUNITIES_JOIN_HINT)
  join.Hint:SetPoint("TOPLEFT", join.Link, "BOTTOMLEFT", -6, -14)
  join.Hint:SetPoint("RIGHT", -16, 0)
  join.Hint:SetJustifyH("LEFT")
  join.Hint:SetSpacing(2)
  -- creating: Blizzard's own create dialog (secure, Game/Communities.lua); without it Blizzard's window
  join.CreateTitle = W.Text(join, "GameFontNormal", L.COMMUNITIES_CREATE)
  join.CreateTitle:SetPoint("TOPLEFT", join.Hint, "BOTTOMLEFT", 0, -20)
  join.CreateText = W.Text(join, "GameFontDisableSmall", L.COMMUNITIES_CREATE_HINT)
  join.CreateText:SetPoint("TOPLEFT", join.CreateTitle, "BOTTOMLEFT", 0, -6)
  join.CreateText:SetPoint("RIGHT", -16, 0)
  join.CreateText:SetJustifyH("LEFT")
  join.CreateText:SetSpacing(2)
  join.Create = W.Button(join, L.COMMUNITIES_CREATE_BUTTON, function()
    if ns.Communities.OpenCreate() then return end
    if InCombatLockdown() then ns.Print(L.COMMUNITIES_CREATE_COMBAT) else UI.ShowBlizzard() end
  end, 180)
  join.Create:SetPoint("TOPLEFT", join.CreateText, "BOTTOMLEFT", 0, -8)
  join.Back = W.Button(join, L.COMMUNITIES_BACK, function() view:ShowJoin(false) end, 140, { small = true })
  join.Back:SetPoint("BOTTOMRIGHT", -10, 10)

  -- an invitation over the chat: Guildy's buttons click Blizzard's own Accept / Decline of its invitation
  -- frame (C_Club.AcceptInvitation is Blizzard's to call). Blizzard's window must show the invitation:
  -- the row click picks it there; else the first click on a button does, the next one answers.
  local invite = W.Box(middle)
  invite:SetPoint("TOPLEFT", 0, 0)
  invite:SetPoint("BOTTOMRIGHT", 0, 0)
  invite:SetFrameLevel(chatBox:GetFrameLevel() + 20)
  invite:EnableMouse(true)
  invite:Hide()
  view.Invite = invite
  invite.Title = W.Text(invite, "GameFontNormalHuge")
  invite.Title:SetPoint("TOP", 0, -40)
  invite.Title:SetPoint("LEFT", 16, 0)
  invite.Title:SetPoint("RIGHT", -16, 0)
  invite.Title:SetJustifyH("CENTER")
  invite.Text = W.Text(invite, "GameFontHighlight")
  invite.Text:SetPoint("TOP", invite.Title, "BOTTOM", 0, -14)
  invite.Text:SetPoint("LEFT", 16, 0)
  invite.Text:SetPoint("RIGHT", -16, 0)
  invite.Text:SetJustifyH("CENTER")
  invite.Text:SetSpacing(3)
  local function Answer(accept)
    return function(button)
      return UI.Action.AnswerInvitation(selectedInvite, accept) or UI.Action.SelectClub(selectedInvite, function()
        ns.Print(L.COMMUNITIES_INVITATION_AGAIN)
        C_Timer.After(0.2, function() UI.RefreshSecureAction(button) end)
      end)
    end
  end
  invite.Accept = W.Button(invite, L.COMMUNITIES_ACCEPT, nil, 130)
  invite.Accept:SetPoint("TOPRIGHT", invite.Text, "BOTTOM", -6, -24)
  UI.SecureAction(invite.Accept, Answer(true), nil, function() ns.Print(L.COMMUNITIES_INVITATION_UNAVAILABLE) end)
  invite.Decline = W.Button(invite, L.COMMUNITIES_DECLINE, nil, 130)
  invite.Decline:SetPoint("TOPLEFT", invite.Text, "BOTTOM", 6, -24)
  UI.SecureAction(invite.Decline, Answer(false), nil, function() ns.Print(L.COMMUNITIES_INVITATION_UNAVAILABLE) end)

  function view:RenderInvite()
    local found
    for _, inv in ipairs(ns.Communities.Invitations()) do
      if inv.clubId == selectedInvite then found = inv end
    end
    if not found then return end
    invite.Title:SetText(found.name)
    local count = tonumber(found.memberCount)
    local text = found.inviter and L.COMMUNITIES_INVITATION_FROM:format(found.inviter) or L.COMMUNITIES_INVITATION
    if count then
      text = text .. "\n" .. (count == 1 and L.COMMUNITIES_ONE_MEMBER or L.COMMUNITIES_MEMBERS:format(count))
    end
    invite.Text:SetText(text)
  end

  function view:SelectInvite(clubId)
    self.drawAvatars = true -- a click: the protected avatar drawing is allowed now
    self.joining = nil
    selectedInvite = clubId
    self:Render()
  end

  function view:ShowJoin(on)
    self.joining = on or nil
    self:RenderChat()
  end

  function view:RenderJoin()
    join.Intro:SetText(selectedClub and L.COMMUNITIES_JOIN_INTRO or L.COMMUNITIES_NONE)
    join.Back:SetShown(selectedClub ~= nil)
  end

  function view:Select(clubId)
    self.drawAvatars = true -- a click: the protected avatar drawing is allowed now
    self.joining = nil
    selectedInvite = nil
    if clubId ~= selectedClub then
      selectedClub = clubId
      selectedStream = nil
    end
    local streams = ns.Communities.Streams(selectedClub)
    local stillThere = false
    for _, stream in ipairs(streams) do
      if stream.streamId == selectedStream then stillThere = true end
    end
    if not stillThere then selectedStream = streams[1] and streams[1].streamId or nil end
    self.Pane:Reset()
    self:Render()
  end

  function view:SelectStream(streamId)
    selectedStream = streamId
    self.Pane:Reset()
    self:Render()
  end

  function view:RenderChat()
    local inviting = selectedInvite ~= nil and not self.joining
    local joining = not inviting and (self.joining or selectedClub == nil)
    local has = not joining and not inviting
    join:SetShown(joining)
    invite:SetShown(inviting)
    chatBox:SetShown(has) -- its edge showed through under the join panel
    self.Input:SetShown(has)
    self.Channel:SetShown(has)
    self.Pane.Messages:SetShown(has)
    if joining then
      self:RenderJoin()
      return
    end
    if inviting then
      self:RenderInvite()
      return
    end
    local r, g, b = ChatColor()
    local name = "?"
    for _, stream in ipairs(ns.Communities.Streams(selectedClub)) do
      if stream.streamId == selectedStream then name = stream.name end
    end
    self.Channel:SetText(name)
    self.Input:ShowChannel(name, r, g, b, L.COMMUNITIES_PLACEHOLDER)
    self.Pane:Render(ns.Communities.History(selectedClub, selectedStream), r, g, b)
  end

  function view:RenderMembers()
    local members = (selectedClub and not selectedInvite) and ns.Communities.Members(selectedClub) or {}
    local online = 0
    for _, m in ipairs(members) do
      if m.online then online = online + 1 end
    end
    self.Count:SetText(selectedClub and not selectedInvite and L.ONLINE_COUNT:format(online, #members) or "")
    local canInvite = selectedClub ~= nil and not selectedInvite and ns.Communities.CanInvite(selectedClub)
    self.InviteSend:SetShown(canInvite)
    self.Members:SetItems(members)
  end

  -- the list, the selection (the first community when none or it is gone), focus, chat and members
  function view:Render()
    local clubs = ns.Communities.List()
    -- invitations first in the list; an answered one goes away
    local items, stillInvited = {}, false
    for _, inv in ipairs(ns.Communities.Invitations()) do
      inv.invite = true
      items[#items + 1] = inv
      if inv.clubId == selectedInvite then stillInvited = true end
    end
    if not stillInvited then selectedInvite = nil end
    if not selectedClub or not ns.Communities.Has(selectedClub) then
      local first = clubs[1] and clubs[1].clubId or nil
      if first ~= selectedClub then
        selectedClub, selectedStream = first, nil
        self.Pane:Reset()
      end
    end
    -- the channel: kept while it exists, else the first one. A new community's channels arrive a moment
    -- after it (CLUB_STREAMS_LOADED renders again), so this runs on every render.
    if selectedClub then
      local streams = ns.Communities.Streams(selectedClub)
      local found = false
      for _, stream in ipairs(streams) do
        if stream.streamId == selectedStream then found = true end
      end
      if not found then
        selectedStream = streams[1] and streams[1].streamId or nil
        self.Pane:Reset()
      end
      if not selectedStream then ns.Communities.RequestStreams(selectedClub) end
    end
    if self.shown then ns.Communities.Focus(selectedClub, selectedStream) end
    -- after Focus: the shown community has no unread lines
    for _, club in ipairs(ns.Communities.List()) do items[#items + 1] = club end
    self.Clubs:SetItems(items)
    self.drawAvatars = nil
    self:RenderChat()
    self:RenderMembers()
  end

  function view:Refresh(event, kind, clubId)
    if event == "CHAT" then
      if kind == "community" and clubId == selectedClub then self:RenderChat() end
      return
    end
    self:Render()
  end

  function view:OnShow()
    self.shown = true
    -- opened by a click: the avatars can be drawn in the render that follows. Not when the screenshot
    -- run shows the tab from a timer (UI/Shots.lua): the protected call is blocked there and the
    -- game reports Guildy for it (ADDON_ACTION_BLOCKED, seen in game 2026-11-10)
    self.drawAvatars = not UI.fromTimer
  end

  function view:OnHide()
    self.shown = nil
    ns.Communities.Focus(nil)
  end

  return view
end

UI.RegisterTab("communities", 8, "TAB_COMMUNITIES", Build, true)
