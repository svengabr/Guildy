-- Rank ladder: a flyout beside the "Rank: X" button of the character page. All guild ranks top to
-- bottom, the member's rank lit in gold with an up and a down arrow in its row. Forever only has
-- /gpromote and /gdemote, one rank per command, so each arrow is one secure click (UI.Action.Manage);
-- hovering an arrow lights the rank it leads to. After a click the arrows wait until the roster shows
-- the new rank: a second command from the old roster would repeat the first step instead of taking
-- the next one (seen in game as the same promotion announced twice).
local _, ns = ...
local W = ns.Widgets
local UI = ns.UI

local ROW = 22
local WIDTH = 232
local TOP = 34 -- title height
local BOTTOM = 26 -- footer height
local PENDING_TIMEOUT = 5 -- seconds until the arrows come back if the roster never confirms

local ARROWS = {
  promote = "Interface\\ChatFrame\\UI-ChatIcon-ScrollUp",
  demote = "Interface\\ChatFrame\\UI-ChatIcon-ScrollDown",
}
local ARROWS_PLAIN = { promote = "Interface\\Buttons\\Arrow-Up", demote = "Interface\\Buttons\\Arrow-Down" }

local ladder

local function Member()
  return ladder and ladder.key and ns.Roster.Find(ladder.key)
end

local function SetArrowTextures(button, kind)
  local base = ARROWS[kind]
  if W.TextureExists(base .. "-Up") then
    button:SetNormalTexture(base .. "-Up")
    button:SetPushedTexture(base .. "-Down")
    button:SetDisabledTexture(base .. "-Disabled")
    button:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
  else
    base = ARROWS_PLAIN[kind]
    button:SetNormalTexture(base .. "-Up")
    button:SetPushedTexture(base .. "-Down")
    button:SetDisabledTexture(base .. "-Disabled")
  end
end

local function Arrow(kind)
  local button = CreateFrame("Button", nil, ladder)
  button:SetSize(24, 24)
  button.kind = kind
  SetArrowTextures(button, kind)
  -- the secure overlay lights its owner through SetHover (UI/Commands.lua): preview the target rank
  function button:SetHover(on)
    if on then self:LockHighlight() else self:UnlockHighlight() end
    ladder.preview = on and self.kind or nil
    ladder:Paint()
  end
  UI.SecureAction(button, function()
    local m = Member()
    local action = m and UI.Action.Manage(kind, m)
    if not action then return nil end
    local after = action.after
    action.after = function()
      ladder.pending = { key = m.key, from = m.rankIndex }
      ladder.preview = nil
      ladder:Render()
      if after then after() end
      local pending = ladder.pending
      C_Timer.After(PENDING_TIMEOUT, function()
        if ladder.pending == pending then
          ladder.pending = nil
          ladder:Render()
        end
      end)
    end
    return action
  end, function()
    local target = ns.Roster.NextRank(Member(), kind)
    return target and (kind == "promote" and ns.L.PROMOTE_TO or ns.L.DEMOTE_TO):format(target)
  end)
  return button
end

local function Row(i)
  local row = CreateFrame("Frame", nil, ladder)
  row:SetHeight(ROW)
  row:SetPoint("TOPLEFT", 8, -TOP - (i - 1) * ROW)
  row:SetPoint("RIGHT", -8, 0)
  row.Fill = row:CreateTexture(nil, "BACKGROUND")
  row.Fill:SetAllPoints()
  row.Name = W.Text(row, "GameFontHighlightSmall")
  row.Name:SetPoint("LEFT", 8, 0)
  row.Name:SetPoint("RIGHT", -60, 0)
  row.Name:SetWordWrap(false)
  row.Tag = W.Text(row, "GameFontDisableSmall")
  row.Tag:SetPoint("RIGHT", -8, 0)
  return row
end

local function Build()
  ladder = W.Box(UIParent, 0.06, 0.9)
  ladder:SetFrameStrata("DIALOG")
  ladder:SetWidth(WIDTH)
  ladder:EnableMouse(true)
  ladder:SetClampedToScreen(true)
  ladder.Title = W.Text(ladder, "GameFontNormal", ns.L.RANK_LADDER)
  ladder.Title:SetPoint("TOPLEFT", 16, -12)
  ladder.Who = W.Text(ladder, "GameFontHighlightSmall")
  ladder.Who:SetPoint("TOPRIGHT", -16, -14)
  ladder.Who:SetPoint("LEFT", ladder.Title, "RIGHT", 8, 0)
  ladder.Who:SetJustifyH("RIGHT")
  ladder.Who:SetWordWrap(false)
  ladder.Footer = W.Text(ladder, "GameFontDisableSmall")
  ladder.Footer:SetPoint("BOTTOMLEFT", 16, 10)
  ladder.Footer:SetPoint("RIGHT", -16, 0)
  ladder.Rows = {}
  ladder.Up = Arrow("promote")
  ladder.Down = Arrow("demote")
  ladder:SetScript("OnHide", function(self)
    self.preview = nil
    if self.anchor and self.anchor.UnlockHighlight then self.anchor:UnlockHighlight() end
  end)
  tinsert(UISpecialFrames, "GuildyRankLadder")
  _G.GuildyRankLadder = ladder

  -- colors only: which row is lit, which is the preview, which ranks are out of reach
  function ladder:Paint()
    local m = Member()
    if not m then return end
    local mine = ns.Roster.MyRank()
    local target = self.preview and m.rankIndex + (self.preview == "promote" and -1 or 1)
    for _, row in ipairs(self.Rows) do
      if row:IsShown() then
        local index = row.index
        if index == m.rankIndex then
          row.Fill:SetColorTexture(1, 0.82, 0, self.pending and 0.08 or 0.16)
          row.Name:SetTextColor(1, 0.82, 0)
        elseif index == target then
          row.Fill:SetColorTexture(1, 1, 1, 0.09)
          row.Name:SetTextColor(1, 1, 1)
        else
          row.Fill:SetColorTexture(0, 0, 0, 0)
          local reachable = type(mine) == "number" and index > mine
          if reachable then row.Name:SetTextColor(0.86, 0.84, 0.78) else row.Name:SetTextColor(0.5, 0.5, 0.5) end
        end
      end
    end
  end

  function ladder:Render()
    local m = Member()
    if not m then self:Hide() return end
    local L = ns.L
    if self.pending and (self.pending.key ~= m.key or self.pending.from ~= m.rankIndex) then self.pending = nil end
    local ranks = ns.Roster.Ranks()
    local mine = ns.Roster.MyRank()
    self.Who:SetText(W.ClassName(m.name, m.classFile))
    local current
    for i, name in ipairs(ranks) do
      local row = self.Rows[i] or Row(i)
      self.Rows[i] = row
      row.index = i - 1
      row.Name:SetText(name)
      row.Tag:SetText(row.index == mine and L.RANK_LADDER_YOU or "")
      row:Show()
      if row.index == m.rankIndex then current = row end
    end
    for i = #ranks + 1, #self.Rows do self.Rows[i]:Hide() end
    self:SetHeight(TOP + #ranks * ROW + BOTTOM)

    -- the arrows sit in the member's row, up first
    local canUp = not self.pending and ns.Roster.NextRank(m, "promote") ~= nil
    local canDown = not self.pending and ns.Roster.NextRank(m, "demote") ~= nil
    local can = ns.Roster.Can()
    self.Up:SetShown(current ~= nil and can.promote or false)
    self.Down:SetShown(current ~= nil and can.demote or false)
    if current and (can.promote or can.demote) then
      self.Down:ClearAllPoints()
      self.Down:SetPoint("RIGHT", current, "RIGHT", -4, 0)
      self.Up:ClearAllPoints()
      self.Up:SetPoint("RIGHT", self.Down, "LEFT", 0, 0)
      current.Tag:SetText("")
    end
    self.Up:SetEnabled(canUp)
    self.Down:SetEnabled(canDown)
    if not canUp then self.Up:UnlockHighlight() end
    if not canDown then self.Down:UnlockHighlight() end
    if not canUp and self.preview == "promote" or not canDown and self.preview == "demote" then self.preview = nil end
    self.Footer:SetText(self.pending and L.RANK_LADDER_PENDING or L.RANK_LADDER_HINT)
    self:Paint()
    UI.RefreshSecureAction(self.Up)
    UI.RefreshSecureAction(self.Down)
  end

  ns.On("ROSTER", function() if ladder:IsShown() then ladder:Render() end end)
end

UI.RankLadder = {}

-- Opens the ladder for member m beside anchor (the rank button), or closes it when already open for m
function UI.RankLadder.Toggle(anchor, m)
  if not m or m.elsewhere then return end
  if not ladder then Build() end
  if ladder:IsShown() and ladder.key == m.key then
    ladder:Hide()
    return
  end
  if ladder.anchor and ladder.anchor ~= anchor and ladder.anchor.UnlockHighlight then ladder.anchor:UnlockHighlight() end
  ladder.key, ladder.anchor, ladder.preview = m.key, anchor, nil
  if ladder.pending and ladder.pending.key ~= m.key then ladder.pending = nil end
  ladder:ClearAllPoints()
  ladder:SetPoint("BOTTOMLEFT", anchor, "BOTTOMRIGHT", 8, -4)
  ladder:Show()
  if anchor.LockHighlight then anchor:LockHighlight() end
  ladder:Render()
end

-- Follows the character page: same member keeps the ladder (fresh data), another member or none closes it
function UI.RankLadder.Sync(m)
  if not (ladder and ladder:IsShown()) then return end
  if not m or m.elsewhere or m.key ~= ladder.key then ladder:Hide() else ladder:Render() end
end

function UI.RankLadder.Hide()
  if ladder then ladder:Hide() end
end
