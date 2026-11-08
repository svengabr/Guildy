-- Timeline for the chat tab: a slim rail right of the messages with a draggable thumb, a mark per
-- day and one for "new since your last login" (click jumps there); a strip pinned over the messages
-- that names the day of the topmost visible line, or at the top of the history whether older lines
-- are loading or the start is reached; and a button centered at the bottom that jumps to the newest
-- line. Works on a ScrollingMessageFrame whose offset counts messages from the bottom.
local _, ns = ...
local W = ns.Widgets

local Timeline = {}
ns.ChatTimeline = Timeline

Timeline.RAIL_WIDTH = 40
Timeline.HEADER_HEIGHT = 20
local MARK_GAP = 13
local THUMB_MIN = 18
local GOLD = { 0.79, 0.64, 0.29 }
local NEW = { 1, 0.55, 0.25 }
local MUTED = { 0.56, 0.51, 0.41 }
local TRACK_RIGHT = 7 -- the track is 2 px wide, ending this far from the rail's right edge

local function Offset(frame)
  return frame.GetScrollOffset and frame:GetScrollOffset() or 0
end

local function MaxOffset(frame)
  if frame.GetMaxScrollRange then return frame:GetMaxScrollRange() or 0 end
  return math.max(0, (frame.GetNumMessages and frame:GetNumMessages() or 1) - 1)
end

-- Rough count of visible lines (wrapped lines count once; good enough for jump targets and thumb size)
local function VisibleLines(frame)
  local lines = frame.GetNumVisibleLines and frame:GetNumVisibleLines()
  if lines and lines > 0 then return lines end
  local ok, _, size = pcall(frame.GetFont, frame)
  size = ok and size or 14
  return math.max(1, math.floor((frame:GetHeight() or 0) / ((size or 14) * 1.2)))
end

local function SetOffset(frame, offset)
  if not frame.SetScrollOffset then return end
  frame:SetScrollOffset(math.max(0, math.min(MaxOffset(frame), math.floor(offset + 0.5))))
end

-- box: the chat inset, messages: its ScrollingMessageFrame. opts:
--   label(ts), short(ts)  name a day (long for the strip and tooltips, short for the marks)
--   newLabel, newShort    the "new since your last login" mark
--   status()              "loading" / "start" / nil at the top of the history; statusText[state]
--   latestText(count)     text of the jump button for count lines below the view
--   onTop()               called when the view reaches the oldest loaded line
function Timeline.Create(box, messages, opts)
  local tl = { days = {}, count = 0, marks = {} }

  -- rail ---------------------------------------------------------------------------------------
  local rail = CreateFrame("Button", nil, box)
  rail:SetPoint("TOPRIGHT", -4, -8)
  rail:SetPoint("BOTTOMRIGHT", -4, 8)
  rail:SetWidth(Timeline.RAIL_WIDTH)
  rail:RegisterForClicks("LeftButtonUp")
  local track = rail:CreateTexture(nil, "BACKGROUND")
  track:SetPoint("TOPRIGHT", -TRACK_RIGHT, 0)
  track:SetPoint("BOTTOMRIGHT", -TRACK_RIGHT, 0)
  track:SetWidth(2)
  track:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.35)

  local thumb = CreateFrame("Button", nil, rail)
  thumb:SetWidth(8) -- centered on the track
  thumb:SetFrameLevel((rail:GetFrameLevel() or 0) + 3)
  local thumbEdge = thumb:CreateTexture(nil, "BACKGROUND")
  thumbEdge:SetPoint("TOPLEFT", -1, 1)
  thumbEdge:SetPoint("BOTTOMRIGHT", 1, -1)
  thumbEdge:SetColorTexture(0, 0, 0, 1)
  local thumbTex = thumb:CreateTexture(nil, "ARTWORK")
  thumbTex:SetAllPoints()
  thumbTex:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 1)
  local thumbHi = thumb:CreateTexture(nil, "HIGHLIGHT")
  thumbHi:SetAllPoints()
  thumbHi:SetColorTexture(1, 0.82, 0, 0.35)

  -- pinned strip -------------------------------------------------------------------------------
  local header = CreateFrame("Frame", nil, box)
  header:SetPoint("TOPLEFT", 6, -4)
  header:SetPoint("TOPRIGHT", -(Timeline.RAIL_WIDTH + 8), -4)
  header:SetHeight(Timeline.HEADER_HEIGHT)
  header:SetFrameLevel((messages:GetFrameLevel() or 0) + 2)
  local headerText = W.Text(header, "GameFontNormalSmall")
  headerText:SetPoint("CENTER")
  headerText:SetJustifyH("CENTER")
  local function Rule(point, relative)
    local tex = header:CreateTexture(nil, "ARTWORK")
    tex:SetHeight(1)
    tex:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.45)
    tex:SetPoint(point, header, point, point == "LEFT" and 20 or -20, 0)
    tex:SetPoint(point == "LEFT" and "RIGHT" or "LEFT", headerText, relative, point == "LEFT" and -10 or 10, 0)
  end
  Rule("LEFT", "LEFT")
  Rule("RIGHT", "RIGHT")
  tl.Header = header

  -- jump to the newest line, centered at the bottom while scrolled up -------------------------
  local latest = CreateFrame("Button", nil, box)
  latest:SetHeight(22)
  latest:SetPoint("BOTTOM", messages, "BOTTOM", 0, 6)
  latest:SetFrameLevel((messages:GetFrameLevel() or 0) + 5)
  local latestBox = W.Box(latest, 0.1, 0.9)
  latestBox:SetAllPoints()
  local latestIcon = latestBox:CreateTexture(nil, "ARTWORK")
  latestIcon:SetSize(16, 16)
  latestIcon:SetPoint("LEFT", 6, 0)
  local iconPath = "Interface\\ChatFrame\\UI-ChatIcon-ScrollEnd-Up"
  if W.TextureExists(iconPath) then latestIcon:SetTexture(iconPath) else latestIcon:SetWidth(1) end
  local latestText = W.Text(latestBox, "GameFontNormalSmall")
  latestText:SetPoint("LEFT", latestIcon, "RIGHT", 3, 0)
  local function SetLatestText(count)
    latestText:SetText(opts.latestText(count))
    latest:SetWidth((latestText:GetStringWidth() or 120) + 34)
  end
  latest:SetScript("OnEnter", function() latestBox:SetBackdropBorderColor(1, 0.82, 0) end)
  latest:SetScript("OnLeave", function() latestBox:SetBackdropBorderColor(W.GOLD[1] * 0.9, W.GOLD[2] * 0.9, W.GOLD[3] * 0.9) end)
  latest:SetScript("OnClick", function()
    messages:ScrollToBottom()
    tl:Update()
  end)
  latest:Hide()

  -- geometry -----------------------------------------------------------------------------------
  local function ThumbHeight(railHeight)
    local visible = VisibleLines(messages)
    return math.max(THUMB_MIN, railHeight * math.min(1, visible / math.max(1, tl.count)))
  end

  -- message index (1 = oldest) at the top of the view
  local function TopIndex()
    return math.max(1, tl.count - Offset(messages) - VisibleLines(messages) + 1)
  end

  local function JumpTo(index)
    SetOffset(messages, tl.count - index - VisibleLines(messages) + 1)
    tl:Update()
  end

  local function SetFraction(fraction) -- 0 = oldest, 1 = newest
    SetOffset(messages, (1 - math.max(0, math.min(1, fraction))) * MaxOffset(messages))
    tl:Update()
  end

  local function CursorFraction(grab)
    local _, y = GetCursorPosition()
    local scale = rail:GetEffectiveScale() or 1
    local top, height = rail:GetTop() or 0, rail:GetHeight() or 0
    local range = height - ThumbHeight(height)
    if range <= 0 then return 1 end
    return (top - y / scale - (grab or 0)) / range
  end

  rail:SetScript("OnClick", function() SetFraction(CursorFraction(ThumbHeight(rail:GetHeight() or 0) / 2)) end)
  thumb:SetScript("OnMouseDown", function(self)
    local _, y = GetCursorPosition()
    self.grab = (self:GetTop() or 0) - y / (rail:GetEffectiveScale() or 1)
    -- grab: distance from the thumb's top down to the cursor, kept while dragging
    self:SetScript("OnUpdate", function(me) SetFraction(CursorFraction(me.grab)) end)
  end)
  thumb:SetScript("OnMouseUp", function(self) self:SetScript("OnUpdate", nil) end)
  thumb:SetScript("OnHide", function(self) self:SetScript("OnUpdate", nil) end)

  local function Mark(i)
    local mark = tl.marks[i]
    if mark then return mark end
    mark = CreateFrame("Button", nil, rail)
    mark:SetSize(Timeline.RAIL_WIDTH - 8, 12)
    mark.Tick = mark:CreateTexture(nil, "ARTWORK")
    mark.Tick:SetSize(6, 1)
    mark.Tick:SetPoint("RIGHT", 0, 0) -- touches the track's left edge
    mark.Label = W.Text(mark, "GameFontDisableSmall")
    mark.Label:SetPoint("RIGHT", mark.Tick, "LEFT", -2, 0)
    mark.Label:SetJustifyH("RIGHT")
    mark:SetScript("OnClick", function(self) if self.entry then JumpTo(self.entry.index) end end)
    mark:SetScript("OnEnter", function(self)
      if not self.entry then return end
      GameTooltip:SetOwner(self, "ANCHOR_LEFT")
      GameTooltip:SetText(self.entry.isNew and opts.newLabel or opts.label(self.entry.ts))
      GameTooltip:Show()
    end)
    mark:SetScript("OnLeave", function() GameTooltip:Hide() end)
    tl.marks[i] = mark
    return mark
  end

  -- public -------------------------------------------------------------------------------------

  -- days: { {index, ts} } in message order, count: number of messages in the frame, newIndex: index
  -- of the "new since your last login" line or nil
  function tl:SetDays(days, count, newIndex)
    self.days, self.count = days or {}, count or 0
    self.entries = {}
    for _, day in ipairs(self.days) do self.entries[#self.entries + 1] = day end
    if newIndex then self.entries[#self.entries + 1] = { index = newIndex, isNew = true } end
    table.sort(self.entries, function(a, b) return a.index < b.index end)
    for i = #self.entries + 1, #self.marks do self.marks[i]:Hide() end
    self:Update()
  end

  function tl:Update()
    local height = rail:GetHeight() or 0
    local maxOffset, offset = MaxOffset(messages), Offset(messages)
    local thumbHeight = ThumbHeight(height)
    local fraction = maxOffset > 0 and 1 - offset / maxOffset or 1
    thumb:SetHeight(thumbHeight)
    thumb:ClearAllPoints()
    thumb:SetPoint("TOP", track, "TOP", 0, -fraction * math.max(0, height - thumbHeight))
    -- everything fits: no thumb and no day marks (they would sit at the top while the few lines
    -- stand at the bottom)
    local scrollable = maxOffset > 0 and self.count > VisibleLines(messages)
    thumb:SetShown(scrollable)
    latest:SetShown(offset > 0)
    if offset > 0 then SetLatestText(offset) end

    -- current day: the last day starting at or above the top line
    local top, current = TopIndex(), nil
    for i, day in ipairs(self.days) do
      if day.index <= top then current = i end
    end
    local currentDay = current and self.days[current]

    -- marks, placed from the newest up so recent ones keep their place when space runs out
    local entries = scrollable and self.entries or {}
    for i = #entries + 1, #self.marks do self.marks[i]:Hide() end
    local below = height + MARK_GAP
    for i = #entries, 1, -1 do
      local entry, mark = entries[i], Mark(i)
      local natural = self.count > 1 and (entry.index - 1) / (self.count - 1) * height or 0
      local y = math.min(natural, below - MARK_GAP, height - 6)
      mark.entry = entry
      if y < 4 and i > 1 then
        mark:Hide()
      else
        y = math.max(y, 6)
        below = y
        mark:ClearAllPoints()
        mark:SetPoint("RIGHT", track, "TOPLEFT", 0, -y)
        local color = entry.isNew and NEW or (entry == currentDay and { 1, 0.82, 0 } or MUTED)
        mark.Label:SetText(entry.isNew and opts.newShort or opts.short(entry.ts))
        mark.Label:SetTextColor(color[1], color[2], color[3])
        local tick = entry.isNew and NEW or GOLD
        mark.Tick:SetColorTexture(tick[1], tick[2], tick[3], entry.isNew and 1 or 0.7)
        mark:Show()
      end
    end

    -- at the top: fetch older lines first, so the strip already shows "loading"
    local atTop = offset >= maxOffset
    if atTop and opts.onTop then opts.onTop() end -- also when everything fits: fill the view

    -- the strip: history state at the top, else the day of the top line unless that line is the
    -- day's own separator
    local state = atTop and opts.status and opts.status() or nil
    if state and opts.statusText[state] then
      headerText:SetText(opts.statusText[state])
      headerText:SetTextColor(0.78, 0.73, 0.56)
      header:Show()
    elseif currentDay and currentDay.index ~= top then
      headerText:SetText(opts.label(currentDay.ts))
      headerText:SetTextColor(1, 0.82, 0)
      header:Show()
    else
      header:Hide()
    end
  end

  if messages.SetOnScrollChangedCallback then
    messages:SetOnScrollChangedCallback(function() tl:Update() end)
  end
  rail:SetScript("OnSizeChanged", function() tl:Update() end)
  return tl
end
