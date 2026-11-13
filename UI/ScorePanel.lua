-- The panel that explains a member's activity score (Core/Activity.lua): the score on its scale, the two
-- parts with what fed them, notes where it is scaled or fading, whose and which days. One frame for the
-- whole addon, built on the first hover and filled only when shown: the character page's score tile, the
-- members tab's score cells and the overview's member lists show it (ScorePanel.Show / Hide).
local _, ns = ...
local W = ns.Widgets
local UI = ns.UI

local ScorePanel = {}
UI.ScorePanel = ScorePanel

local TEXTURES = "Interface\\AddOns\\Guildy\\Textures\\"
local panel
local BuildScorePanel

-- Colour of an activity bucket, as the endgame view draws its bars (UI/OverviewEndgame.lua)
local function BucketColor(bucket)
  if bucket >= 5 then return 0.5, 0.47, 0.4 end
  local green = 1 - (bucket - 1) / 3
  return 1 - green * 0.6, 0.35 + green * 0.5, 0.25
end
ScorePanel.BucketColor = BucketColor

local function Number(n)
  local big = rawget(_G, "BreakUpLargeNumbers")
  return big and big(n) or tostring(n)
end

-- A weekly count as the tiles write numbers: whole from 10 on (thousands marked), one decimal below 10
-- unless it is whole (0, not 0,0)
local function Weekly(value)
  value = value or 0
  if value >= 10 then return Number(math.floor(value + 0.5)) end
  local tenths = math.floor(value * 10 + 0.5)
  if tenths % 10 == 0 then return tostring(tenths / 10) end
  return (string.format("%.1f", tenths / 10):gsub("%.", ns.L.DECIMAL_MARK))
end

local PANEL_W, PANEL_PAD = 380, 14
local PANEL_IN = PANEL_W - 2 * PANEL_PAD
local GREY = 0.68
local PARTS = {
  { key = "presence", title = "SCORE_PRESENCE", explain = "SCORE_PRESENCE_EXPLAIN", rows = 1 },
  -- a row for each source of Activity.UNITS, in this order, with its share of the units
  { key = "playing", title = "SCORE_PLAYING", explain = "SCORE_PLAYING_EXPLAIN", rows = 7,
    sources = { "kills", "honorKills", "quests", "dungeons", "dungeonBosses", "raidBosses", "battlegrounds" } },
}
PARTS.SHARE_W = 40 -- the column of a source's share of the units, left of its weekly value
local NOTE_COLORS = { scaled = { 1, 0.82, 0 }, faded = { 1, 0.5, 0.25 } }

local function Grey(text)
  text:SetTextColor(GREY, GREY, GREY)
  return text
end

-- the height of a text wrapped to width
local function TextHeight(text, width)
  text:SetWidth(width)
  local h = text:GetStringHeight()
  return type(h) == "number" and h > 0 and math.ceil(h) or 12
end

local function ScoreBlock(parent)
  local block = CreateFrame("Frame", nil, parent)
  block.Divider = block:CreateTexture(nil, "ARTWORK")
  block.Divider:SetHeight(1)
  block.Divider:SetColorTexture(W.GOLD[1], W.GOLD[2], W.GOLD[3], 0.3)
  block.Title = W.Text(block, "GameFontNormal")
  block.Points = W.Text(block, "GameFontHighlight")
  block.Points:SetJustifyH("RIGHT")
  block.Track = block:CreateTexture(nil, "BORDER")
  block.Track:SetHeight(6)
  block.Track:SetColorTexture(0, 0, 0, 0.7)
  block.Fill = block:CreateTexture(nil, "ARTWORK")
  block.Fill:SetHeight(6)
  block.Explain = Grey(W.Text(block, "GameFontHighlightSmall"))
  block.Explain:SetSpacing(1)
  block.PerWeek = Grey(W.Text(block, "GameFontHighlightSmall"))
  block.PerWeek:SetJustifyH("RIGHT")
  block.Rows = {}
  return block
end

local function ScoreNote(parent, color)
  local note = CreateFrame("Frame", nil, parent)
  local tint = note:CreateTexture(nil, "BACKGROUND")
  tint:SetAllPoints()
  tint:SetColorTexture(color[1], color[2], color[3], 0.1)
  local edge = note:CreateTexture(nil, "ARTWORK")
  edge:SetPoint("TOPLEFT")
  edge:SetPoint("BOTTOMLEFT")
  edge:SetWidth(2)
  edge:SetColorTexture(color[1], color[2], color[3], 0.9)
  note.Text = W.Text(note, "GameFontHighlightSmall")
  note.Text:SetTextColor(color[1], color[2], color[3])
  note.Text:SetSpacing(1)
  note.Text:SetPoint("TOPLEFT", 10, -4)
  return note
end

-- Built once on the first hover, then reused: opaque, above everything, kept on the screen
function BuildScorePanel()
  local L = ns.L
  -- set apart from the page's boxes it lies on: full gold border, a darker ground, a soft shadow around
  panel = W.FloatingPanel(W.Box(UIParent)) -- the one panel of the file (upvalue)
  panel:SetWidth(PANEL_W)
  panel:Hide()
  panel.Value = W.Text(panel, "GameFontNormalHuge")
  panel.Value:SetPoint("TOPLEFT", PANEL_PAD, -PANEL_PAD)
  panel.Of = Grey(W.Text(panel, "GameFontHighlightSmall", L.SCORE_OF))
  panel.Of:SetPoint("BOTTOMLEFT", panel.Value, "BOTTOMRIGHT", 5, 3)
  panel.Label = W.Text(panel, "GameFontNormal")
  panel.Label:SetPoint("TOPRIGHT", -PANEL_PAD, -PANEL_PAD - 6)
  panel.Label:SetJustifyH("RIGHT")
  -- the scale 0-100 in the four bucket colours, a marker at the score, the bucket names under it
  panel.Segments, panel.ScaleLabels = {}, {}
  for i = 1, 4 do
    local bucket = 5 - i -- left the lowest
    local segment = panel:CreateTexture(nil, "BORDER")
    local r, g, b = BucketColor(bucket)
    segment:SetColorTexture(r * 0.55, g * 0.55, b * 0.55, 1)
    segment:SetHeight(8)
    panel.Segments[i] = segment
    local label = Grey(W.Text(panel, "GameFontHighlightSmall", L["SCORE_" .. bucket]))
    label:SetJustifyH("CENTER")
    label:SetWordWrap(false)
    panel.ScaleLabels[i] = label
  end
  panel.Marker = CreateFrame("Frame", nil, panel)
  panel.Marker:SetSize(10, 16)
  local line = panel.Marker:CreateTexture(nil, "OVERLAY")
  line:SetSize(2, 14)
  line:SetPoint("BOTTOM", 0, 0)
  line:SetColorTexture(1, 1, 1, 1)
  local dot = panel.Marker:CreateTexture(nil, "OVERLAY")
  dot:SetSize(8, 8)
  dot:SetPoint("TOP", 0, 0)
  dot:SetTexture(TEXTURES .. "Dot")
  panel.Intro = Grey(W.Text(panel, "GameFontHighlightSmall"))
  panel.Intro:SetSpacing(1)
  panel.None = Grey(W.Text(panel, "GameFontHighlightSmall", L.SCORE_NONE))
  panel.None:SetSpacing(1)
  panel.Blocks = {}
  for _, part in ipairs(PARTS) do
    local block = ScoreBlock(panel)
    block.Title:SetText(L[part.title])
    block.PerWeek:SetText(L.SCORE_PER_WEEK)
    for i = 1, part.rows do
      local label = Grey(W.Text(block, "GameFontHighlight"))
      label:SetWordWrap(false)
      local value = W.Text(block, "GameFontHighlight")
      value:SetJustifyH("RIGHT")
      local share = Grey(W.Text(block, "GameFontHighlightSmall"))
      share:SetJustifyH("RIGHT")
      block.Rows[i] = { Label = label, Value = value, Share = share }
    end
    panel.Blocks[part.key] = block
  end
  panel.Notes = { scaled = ScoreNote(panel, NOTE_COLORS.scaled), faded = ScoreNote(panel, NOTE_COLORS.faded) }
  panel.PerPlayer = Grey(W.Text(panel, "GameFontHighlightSmall", L.SCORE_PER_PLAYER))
  panel.Chars = Grey(W.Text(panel, "GameFontHighlightSmall"))
  panel.Window = Grey(W.Text(panel, "GameFontHighlightSmall"))
  return panel
end


-- the panel at owner: under it, right edges flush (anchor nil or "below"), or beside it ("right", "left")
local function Place(owner, anchor)
  panel:ClearAllPoints()
  if anchor == "right" then
    panel:SetPoint("TOPLEFT", owner, "TOPRIGHT", 4, 0)
  elseif anchor == "left" then
    panel:SetPoint("TOPRIGHT", owner, "TOPLEFT", -4, 0)
  else
    panel:SetPoint("TOPRIGHT", owner, "BOTTOMRIGHT", 0, -4)
  end
  panel:Show()
end

-- The score panel of memberKey at owner (anchor as Place): the score on its scale, the two parts with their bars and
-- what fed them (each source of playing with its share of the units), notes where the score is scaled
-- or fading, whose and which days it covers. Laid out top-down; its height follows from what it shows.
function ScorePanel.Show(owner, memberKey, anchor)
  panel = panel or BuildScorePanel()
  local L = ns.L
  local A = ns.Activity
  local info = {}
  if memberKey then info.score, info.parts, info.detail = ns.GameActivity.ScoreOf(memberKey) end
  local member = memberKey and ns.Roster.Find(memberKey)
  local d = info.detail
  local has = info.score ~= nil and type(d) == "table"
  local bucket = has and A.Bucket(info.score) or 5
  local r, g, b = BucketColor(bucket)
  panel.Value:SetText(has and tostring(info.score) or "–")
  panel.Value:SetTextColor(r, g, b)
  panel.Of:SetShown(has)
  panel.Label:SetText(L["SCORE_" .. bucket])
  panel.Label:SetTextColor(r, g, b)
  local y = PANEL_PAD + 28

  -- the scale
  local seg = PANEL_IN / 4
  for i, segment in ipairs(panel.Segments) do
    segment:ClearAllPoints()
    segment:SetPoint("TOPLEFT", PANEL_PAD + (i - 1) * seg, -y)
    segment:SetWidth(seg - (i < 4 and 1 or 0))
    local label = panel.ScaleLabels[i]
    label:ClearAllPoints()
    label:SetPoint("TOPLEFT", PANEL_PAD + (i - 1) * seg, -(y + 12))
    label:SetWidth(seg)
    if has and 5 - i == bucket then label:SetTextColor(r, g, b) else Grey(label) end
  end
  panel.Marker:ClearAllPoints()
  if has then
    panel.Marker:SetPoint("BOTTOM", panel, "TOPLEFT", PANEL_PAD + PANEL_IN * math.max(0, math.min(100, info.score)) / 100, -(y + 10))
  end
  panel.Marker:SetShown(has)
  y = y + 12 + 12 + 10

  -- no score: what one needs, nothing else
  panel.None:SetShown(not has)
  panel.Intro:SetShown(has)
  for _, part in ipairs(PARTS) do panel.Blocks[part.key]:SetShown(has) end
  for _, text in ipairs({ panel.PerPlayer, panel.Chars, panel.Window }) do text:SetShown(has) end
  if not has then
    panel.Notes.scaled:Hide()
    panel.Notes.faded:Hide()
    panel.None:ClearAllPoints()
    panel.None:SetPoint("TOPLEFT", PANEL_PAD, -y)
    y = y + TextHeight(panel.None, PANEL_IN)
    panel:SetHeight(y + PANEL_PAD)
    Place(owner, anchor)
    return panel
  end

  local parts, max, rates = type(info.parts) == "table" and info.parts or {}, A.MAX, type(d.rates) == "table" and d.rates or {}
  local function Points(x) return math.floor((tonumber(x) or 0) + 0.5) end
  local name = member and member.name or "" -- roster names are made up for pictures already
  panel.Intro:SetText(L.SCORE_INTRO:format(name))
  panel.Intro:ClearAllPoints()
  panel.Intro:SetPoint("TOPLEFT", PANEL_PAD, -y)
  y = y + TextHeight(panel.Intro, PANEL_IN) + 8

  -- the two parts
  local explain = {
    presence = L.SCORE_PRESENCE_EXPLAIN:format(A.FULL_PRESENCE, max.presence),
    playing = L.SCORE_PLAYING_EXPLAIN:format(max.playing),
  }
  local rows = {
    presence = { { L.SCORE_ROW_DAYS, d.presence and L.SCORE_DAYS_OF:format(Weekly(d.presence)) or L.SCORE_PRESENCE_UNCOUNTED } },
    playing = {},
  }
  -- each source's share of the units: none where it brought nothing, "<1" where it brought a little
  local labels = { kills = L.SCORE_ROW_KILLS, honorKills = L.SCORE_ROW_HONOR, quests = L.SCORE_ROW_QUESTS,
    dungeons = L.SCORE_ROW_DUNGEONS, dungeonBosses = L.SCORE_ROW_DUNGEON_BOSSES, raidBosses = L.SCORE_ROW_RAID_BOSSES,
    battlegrounds = L.SCORE_ROW_BATTLEGROUNDS }
  local units = type(d.units) == "table" and d.units or select(2, A.Units(rates))
  local total = 0
  local sources = PARTS[2].sources
  for _, source in ipairs(sources) do total = total + (tonumber(units[source]) or 0) end
  for i, source in ipairs(sources) do
    local own = tonumber(units[source]) or 0
    local share = ""
    if total > 0 and own > 0 then
      local percent = math.floor(own / total * 100 + 0.5)
      share = percent < 1 and L.SCORE_SHARE_SMALL or L.SCORE_SHARE:format(percent)
    end
    rows.playing[i] = { labels[source], Weekly(rates[source]), share }
  end
  for i, part in ipairs(PARTS) do
    local block, key = panel.Blocks[part.key], part.key
    local top = y
    local by = 0
    block.Divider:SetShown(i > 1)
    if i > 1 then
      block.Divider:ClearAllPoints()
      block.Divider:SetPoint("TOPLEFT", PANEL_PAD, 0)
      block.Divider:SetWidth(PANEL_IN)
      by = 7
    end
    local points, most = tonumber(parts[key]) or 0, max[key]
    block.Title:ClearAllPoints()
    block.Title:SetPoint("TOPLEFT", PANEL_PAD, -by)
    block.PerWeek:ClearAllPoints()
    block.PerWeek:SetPoint("BOTTOMLEFT", block.Title, "BOTTOMRIGHT", 6, 1)
    block.Points:SetText(("%d |cff999999/ %d|r"):format(Points(points), most))
    block.Points:ClearAllPoints()
    block.Points:SetPoint("TOPRIGHT", -PANEL_PAD, -by)
    by = by + 16
    local share = math.max(0, math.min(1, points / most))
    block.Track:ClearAllPoints()
    block.Track:SetPoint("TOPLEFT", PANEL_PAD, -by)
    block.Track:SetWidth(PANEL_IN)
    block.Fill:ClearAllPoints()
    block.Fill:SetPoint("TOPLEFT", block.Track, "TOPLEFT", 0, 0)
    block.Fill:SetWidth(math.max(0.01, PANEL_IN * share))
    if share >= 0.999 then
      block.Fill:SetColorTexture(0.3, 0.9, 0.3, 1)
    else
      block.Fill:SetColorTexture(W.GOLD[1], W.GOLD[2], W.GOLD[3], 1)
    end
    block.Fill:SetShown(share > 0)
    by = by + 6 + 5
    block.Explain:SetText(explain[key])
    block.Explain:ClearAllPoints()
    block.Explain:SetPoint("TOPLEFT", PANEL_PAD, -by)
    by = by + TextHeight(block.Explain, PANEL_IN) + 4
    for j, row in ipairs(block.Rows) do
      local entry = rows[key][j]
      row.Label:SetText(entry[1])
      row.Value:SetText(entry[2])
      row.Label:ClearAllPoints()
      row.Label:SetPoint("TOPLEFT", PANEL_PAD, -by)
      row.Label:SetWidth(PANEL_IN - 120)
      row.Value:ClearAllPoints()
      row.Value:SetPoint("TOPRIGHT", -PANEL_PAD, -by)
      row.Share:SetText(entry[3] or "")
      row.Share:ClearAllPoints()
      row.Share:SetPoint("TOPRIGHT", -(PANEL_PAD + 120 - PARTS.SHARE_W), -by - 1)
      row.Share:SetWidth(PARTS.SHARE_W)
      by = by + 13
    end
    block:ClearAllPoints()
    block:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, -top)
    block:SetSize(PANEL_W, by)
    y = top + by + 6
  end

  -- the notes, each only where it applies
  local notes = {}
  if d.scaled then
    local made = math.min(100, math.floor((tonumber(parts.playing) or 0) * 100 / max.playing + 0.5))
    -- the points with one decimal, so the sum reads true ("69,6 von 70 ergeben 99", not "70 von 70 ergeben 99")
    local tenths = math.floor((tonumber(parts.playing) or 0) * 10 + 0.5)
    local shown = tenths % 10 == 0 and tostring(tenths / 10)
      or (string.format("%.1f", tenths / 10):gsub("%.", ns.L.DECIMAL_MARK))
    notes.scaled = L.SCORE_NOTE_SCALED:format(A.MIN_COUNTED, shown, max.playing, made)
  end
  if type(d.fade) == "number" then
    notes.faded = L.SCORE_NOTE_FADED:format(math.floor(tonumber(d.away) or 0), A.FADE_FROM, A.GONE_DAYS,
      math.floor(d.fade * 100 + 0.5))
  end
  for _, kind in ipairs({ "scaled", "faded" }) do
    local note = panel.Notes[kind]
    if notes[kind] then
      note.Text:SetText(notes[kind])
      local h = TextHeight(note.Text, PANEL_IN - 18) + 8
      note:ClearAllPoints()
      note:SetPoint("TOPLEFT", PANEL_PAD, -y)
      note:SetSize(PANEL_IN, h)
      note:Show()
      y = y + h + 5
    else
      note:Hide()
    end
  end

  -- whose and which days
  y = y + 2
  local function Line(text, shown)
    text:SetShown(shown)
    if not shown then return end
    text:ClearAllPoints()
    text:SetPoint("TOPLEFT", PANEL_PAD, -y)
    y = y + TextHeight(text, PANEL_IN) + 1
  end
  Line(panel.PerPlayer, true)
  local chars = type(d.chars) == "table" and d.chars or {}
  local names = {}
  if #chars > 1 then
    for _, key in ipairs(chars) do
      local other = ns.Roster.Find(key) -- roster names are made up for pictures already
      if other then names[#names + 1] = W.ClassName(other.name, other.classFile) end
    end
  end
  panel.Chars:SetText(L.SCORE_CHARS:format(table.concat(names, ns.L.SEP)))
  Line(panel.Chars, #names > 1)
  local from, to = tonumber(d.fromDay), tonumber(d.toDay)
  if from and to then
    panel.Window:SetText(L.SCORE_WINDOW:format(ns.GameStats.Date(L.DATE_SHORT, A.DayTime(from)),
      ns.GameStats.Date(L.DATE_LONG, A.DayTime(to)), to - from))
  end
  Line(panel.Window, from ~= nil and to ~= nil)
  panel:SetHeight(y - 1 + PANEL_PAD)
  Place(owner, anchor)
  return panel
end

function ScorePanel.Hide()
  if panel then panel:Hide() end
end

-- the panel's frame once built (tests, the character page)
function ScorePanel.Frame()
  return panel
end
