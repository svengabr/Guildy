-- Ranks tab: every guild rank with its member count and, for the selected rank, which permissions it
-- has (read with C_GuildInfo.GuildControlGetRankFlags, allowed for everyone) and who holds it. The guild master edits
-- ranks and permissions in Blizzard's rank editor, which Guildy opens over the right half of this tab
-- (UI/Commands.lua explains why it has to be Blizzard's).
local _, ns = ...
local W = ns.Widgets
local UI = ns.UI

local NUM_FLAGS = 21
local OBSOLETE = { [14] = true }

-- { {index, name, count} } with index 1 = guild master
local function Ranks()
  local list = {}
  local num = ns.Try(rawget(_G, "GuildControlGetNumRanks")) or 0
  local counts = {}
  for _, m in ipairs(ns.Roster.Members()) do
    if type(m.rankIndex) == "number" then counts[m.rankIndex + 1] = (counts[m.rankIndex + 1] or 0) + 1 end
  end
  for i = 1, num do
    list[i] = { index = i, name = ns.Try(rawget(_G, "GuildControlGetRankName"), i) or tostring(i), count = counts[i] or 0 }
  end
  return list
end

-- { {label, on} } for rank index
local function Permissions(index)
  local getFlags = C_GuildInfo and C_GuildInfo.GuildControlGetRankFlags
  local flags = getFlags and ns.Try(getFlags, index)
  if type(flags) ~= "table" then return nil end
  local list = {}
  for i = 1, NUM_FLAGS do
    local label = rawget(_G, "GUILDCONTROL_OPTION" .. i)
    if label and not OBSOLETE[i] then list[#list + 1] = { label = label, on = flags[i] and true or false } end
  end
  return list
end

local function Build(panel)
  local L = ns.L
  local view = { selected = nil }

  -- rank list
  local page = W.Page(panel)
  panel = page.Body
  local ranks = W.Box(panel)
  ranks:SetPoint("TOPLEFT", 0, 0)
  ranks:SetPoint("BOTTOM", 0, 0)
  ranks:SetWidth(W.SIDE)
  local ranksTitle = W.Text(ranks, "GameFontNormal", L.RANKS)
  ranksTitle:SetPoint("TOPLEFT", 10, -8)
  view.List = W.ScrollList(ranks, 22, function(row)
    row.Selected = row:CreateTexture(nil, "BACKGROUND")
    row.Selected:SetAllPoints()
    row.Selected:SetColorTexture(1, 0.82, 0, 0.18)
    row.Name = W.Text(row, "GameFontHighlight")
    row.Name:SetPoint("LEFT", 6, 0)
    row.Name:SetPoint("RIGHT", -60, 0)
    row.Name:SetWordWrap(false)
    row.Count = W.Text(row, "GameFontDisableSmall")
    row.Count:SetPoint("RIGHT", -6, 0)
    row.Count:SetJustifyH("RIGHT")
    row:EnableMouse(true)
    row:SetScript("OnMouseUp", function(self)
      view.selected = self.rank and self.rank.index
      view:Refresh()
    end)
  end, function(row, rank)
    row.rank = rank
    row.Name:SetText(rank.index .. ". " .. rank.name)
    row.Count:SetText(L.RANK_MEMBERS:format(rank.count))
    row.Selected:SetShown(view.selected == rank.index)
  end)
  view.List:SetPoint("TOPLEFT", 8, -28)
  view.List:SetPoint("BOTTOMRIGHT", -28, 8)

  -- permissions of the selected rank
  local perms = W.Box(panel)
  perms:SetPoint("TOPLEFT", ranks, "TOPRIGHT", 8, 0)
  perms:SetPoint("BOTTOMRIGHT", 0, 0)
  view.PermsBox = perms
  view.PermsTitle = W.Text(perms, "GameFontNormal")
  view.PermsTitle:SetPoint("TOPLEFT", 10, -8)
  view.PermsTitle:SetPoint("RIGHT", -10, 0)
  view.PermsTitle:SetWordWrap(false)
  view.Lines = {}
  for i = 1, NUM_FLAGS do
    local line = CreateFrame("Frame", nil, perms)
    line:SetSize(240, 18)
    local column, rowIndex = (i - 1) % 2, math.floor((i - 1) / 2)
    line:SetPoint("TOPLEFT", 10 + column * 250, -30 - rowIndex * 20)
    line.Icon = line:CreateTexture(nil, "ARTWORK")
    line.Icon:SetSize(14, 14)
    line.Icon:SetPoint("LEFT", 0, 0)
    line.Text = W.Text(line, "GameFontHighlightSmall")
    line.Text:SetPoint("LEFT", line.Icon, "RIGHT", 4, 0)
    line.Text:SetPoint("RIGHT", 0, 0)
    line.Text:SetWordWrap(false)
    view.Lines[i] = line
  end
  view.NoPerms = W.Text(perms, "GameFontDisable", L.RANK_NO_PERMISSIONS)
  view.NoPerms:SetPoint("TOPLEFT", 10, -30)

  -- members of the selected rank (online first, then by name); a click opens them in the members tab
  view.MembersTitle = W.Text(perms, "GameFontNormal")
  view.MembersTitle:SetPoint("TOPLEFT", 10, -30 - math.ceil(NUM_FLAGS / 2) * 20 - 6)
  view.Members = W.ScrollList(perms, 18, function(row)
    row.Name = W.Text(row, "GameFontHighlightSmall")
    row.Name:SetPoint("LEFT", 4, 0)
    row.Name:SetWidth(180)
    row.Name:SetWordWrap(false)
    row.Level = W.Text(row, "GameFontHighlightSmall")
    row.Level:SetPoint("LEFT", 190, 0)
    row.Level:SetWidth(40)
    row.Zone = W.Text(row, "GameFontDisableSmall")
    row.Zone:SetPoint("LEFT", 236, 0)
    row.Zone:SetPoint("RIGHT", -90, 0)
    row.Zone:SetWordWrap(false)
    row.When = W.Text(row, "GameFontDisableSmall")
    row.When:SetPoint("RIGHT", -4, 0)
    row.When:SetJustifyH("RIGHT")
    row:EnableMouse(true)
    row.Highlight = row:CreateTexture(nil, "HIGHLIGHT")
    row.Highlight:SetAllPoints()
    row.Highlight:SetColorTexture(1, 1, 1, 0.08)
    row:SetScript("OnMouseUp", function(self) if self.member then UI.ShowMember(self.member) end end)
    row:SetScript("OnEnter", function(self) if self.member then UI.MemberTooltip(self, self.member) end end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
  end, function(row, m)
    row.member = m
    row.Name:SetText(W.ClassName(m.name, m.classFile))
    row.Level:SetText(m.level or "")
    row.Zone:SetText(m.online and (m.zone or "") or "")
    row.When:SetText(ns.Roster.LastOnlineText(m))
  end)
  view.Members:SetPoint("TOPLEFT", view.MembersTitle, "BOTTOMLEFT", -2, -6)
  view.Members:SetPoint("BOTTOMRIGHT", -28, 8)

  -- guild master: Blizzard's rank editor over this box
  view.Edit = W.Button(page.Bar, L.RANKS_EDIT, nil, 150, { small = true })
  page:Right(view.Edit)
  local function Place(editor)
    editor:ClearAllPoints()
    editor:SetPoint("TOPRIGHT", perms, "TOPRIGHT", 0, 0)
  end
  UI.SecureAction(view.Edit, function() return UI.Action.RankEditor(Place) end, L.RANKS_EDIT_TIP,
    function() ns.Print(L.BLIZZARD_PART_MISSING) end)
  -- who is not the guild master has no button in the toolbar: the reason stands there
  view.Hint = page:Left(W.Text(page.Bar, "GameFontDisableSmall", L.RANKS_READONLY), 2)

  function view:Refresh()
    local list = Ranks()
    if not self.selected or not list[self.selected] then
      -- the player's own rank (GetGuildInfo's index is 0-based)
      local _, _, myRank = ns.Try(GetGuildInfo, "player")
      self.selected = (type(myRank) == "number" and list[myRank + 1]) and (myRank + 1) or (list[1] and 1)
    end
    self.List:SetItems(list)
    local rank = self.selected and list[self.selected]
    self.PermsTitle:SetText(rank and L.RANK_PERMISSIONS:format(rank.name) or "")
    local permissions = rank and Permissions(rank.index)
    for i, line in ipairs(self.Lines) do
      local p = permissions and permissions[i]
      line:SetShown(p ~= nil)
      if p then
        line.Icon:SetTexture(p.on and W.ICON_YES or W.ICON_NO)
        line.Icon:SetDesaturated(not p.on)
        line.Icon:SetAlpha(p.on and 1 or 0.5)
        line.Text:SetText(p.label)
        if p.on then line.Text:SetTextColor(1, 1, 1) else line.Text:SetTextColor(0.55, 0.55, 0.55) end
      end
    end
    self.NoPerms:SetShown(rank ~= nil and permissions == nil)

    local holders = {}
    for _, m in ipairs(ns.Roster.Members()) do
      if rank and m.rankIndex == rank.index - 1 then holders[#holders + 1] = m end
    end
    table.sort(holders, function(a, b)
      if a.online ~= b.online then return a.online end
      return (a.name or "") < (b.name or "")
    end)
    self.MembersTitle:SetText(rank and L.RANK_HOLDERS:format(rank.name, #holders) or "")
    self.Members:SetItems(holders)
    local leader = ns.Roster.Can().leader
    self.Edit:SetShown(leader)
    self.Hint:SetShown(not leader)
  end

  function view:OnHide()
    UI.Action.CloseRankEditor()
  end

  return view
end

UI.RegisterTab("ranks", 6, ns.L.TAB_RANKS, Build)
