-- Character page ("hero card"), variant A "readiness": opened by a left click on a member anywhere
-- (chat names, the online list, the members and ranks tab), shown in the content area instead of a
-- tab, with a way back. Left the hero card: the model area (today the race portrait), level, Hall of
-- Fame title, race, gender and class, rank, notes, whisper and invite, and for officers the removal.
-- Right the statistic tiles across, below them the gear slot by slot (Core/Gear.lua) beside a column
-- with the family (Core/Family.lua), "Upgrades aus der Gilde" (Core/Upgrades.lua) and the professions.
local _, ns = ...
local W = ns.Widgets
local UI = ns.UI

local TEXTURES = "Interface\\AddOns\\Guildy\\Textures\\"
local MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local HERO_WIDTH = W.SIDE
local TILE_H = 78
local TILE_KEYS = { "kills", "quests", "deaths", "gear", "score" }
local FAMILY_LINES = 8
local LINE_H = 18
local PROF_ROWS = 6
local GEAR_SHARE = 0.62 -- of the room right of the hero card, the rest is the column
local GEAR_TOP = 38     -- title and the column heading above the rows
local QUALITY = { [0] = { 0.62, 0.62, 0.62 }, { 1, 1, 1 }, { 0.12, 1, 0 }, { 0, 0.44, 0.87 }, { 0.64, 0.21, 0.93 }, { 1, 0.5, 0 } }
local ENCHANT_COLOR = { 0.12, 1, 0 }
local MISSING_COLOR = { 1, 0.5, 0.15 }
-- slot names: the game's own globals, English where a client has none
local SLOT_NAMES = {
  [1] = { "HEADSLOT", "Head" }, [2] = { "NECKSLOT", "Neck" }, [3] = { "SHOULDERSLOT", "Shoulder" },
  [15] = { "BACKSLOT", "Back" }, [5] = { "CHESTSLOT", "Chest" }, [9] = { "WRISTSLOT", "Wrist" },
  [10] = { "HANDSSLOT", "Hands" }, [6] = { "WAISTSLOT", "Waist" }, [7] = { "LEGSSLOT", "Legs" },
  [8] = { "FEETSLOT", "Feet" }, [11] = { "FINGER0SLOT", "Finger" }, [12] = { "FINGER1SLOT", "Finger" },
  [13] = { "TRINKET0SLOT", "Trinket" }, [14] = { "TRINKET1SLOT", "Trinket" }, [16] = { "MAINHANDSLOT", "Main Hand" },
  [17] = { "SECONDARYHANDSLOT", "Off Hand" }, [18] = { "RANGEDSLOT", "Ranged" },
}
-- achievement icons of the races: Interface\Icons\Achievement_Character_<Race>_<Male|Female>
local RACE_ICON = { NightElf = "Nightelf", Human = "Human", Dwarf = "Dwarf", Gnome = "Gnome", Orc = "Orc",
  Scourge = "Undead", Undead = "Undead", Tauren = "Tauren", Troll = "Troll", BloodElf = "Bloodelf", Draenei = "Draenei" }

local page

local function SlotName(slot)
  local names = SLOT_NAMES[slot]
  local text = names and rawget(_G, names[1])
  return type(text) == "string" and text or (names and names[2] or tostring(slot))
end

-- The gear list's slots in the character window's order
local LIST = {}
for _, group in ipairs(ns.Stats.GEAR_SLOT_GROUPS) do
  for _, slot in ipairs(group) do LIST[#LIST + 1] = slot end
end

-- Race, gender and the race icon of a member from the game (known once the client saw the character)
local function RaceInfo(m)
  local getInfo = rawget(_G, "GetPlayerInfoByGUID")
  if not getInfo or not m.guid or m.guid == "" then return nil end
  local ok, _, _, localizedRace, englishRace, sex = pcall(getInfo, m.guid)
  if not ok or not englishRace then return nil end
  local female = sex == 3
  local race = RACE_ICON[englishRace]
  local icon = race and ("Interface\\Icons\\Achievement_Character_" .. race .. "_" .. (female and "Female" or "Male"))
  return { race = localizedRace, female = female, icon = icon and W.TextureExists(icon) and icon or nil }
end

-- The class icon as an inline texture (for text that may wrap, like the identity line)
local function ClassIconString(classFile, size)
  local coords = rawget(_G, "CLASS_ICON_TCOORDS")
  local c = classFile and coords and coords[classFile]
  if not c then return "" end
  size = size or 16
  return string.format("|TInterface\\TargetingFrame\\UI-Classes-Circles:%d:%d:0:0:256:256:%d:%d:%d:%d|t ", size, size,
    c[1] * 256, c[2] * 256, c[3] * 256, c[4] * 256)
end

local function SetClassIcon(texture, classFile)
  local coords = rawget(_G, "CLASS_ICON_TCOORDS")
  if classFile and coords and coords[classFile] then
    texture:SetTexture("Interface\\TargetingFrame\\UI-Classes-Circles")
    texture:SetTexCoord(unpack(coords[classFile]))
    return true
  end
  texture:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
  texture:SetTexCoord(0, 1, 0, 1)
  return false
end

-- A round picture with a thin colored rim and an optional level badge. The rim is a colored disc
-- behind a dark disc a few pixels smaller (the soft-edged Ring texture blurs when scaled up).
local function Disc(frame, layer, sublevel, inset, r, g, b)
  local disc = frame:CreateTexture(nil, layer, nil, sublevel)
  disc:SetPoint("TOPLEFT", inset, -inset)
  disc:SetPoint("BOTTOMRIGHT", -inset, inset)
  disc:SetTexture(TEXTURES .. "Dot")
  disc:SetVertexColor(r, g, b)
  return disc
end

local function Portrait(parent, size, badge)
  local frame = CreateFrame("Frame", nil, parent)
  frame:SetSize(size, size)
  local rim = math.max(2, math.floor(size * 0.035 + 0.5))
  frame.Ring = Disc(frame, "BACKGROUND", 1, 0, 1, 1, 1)
  Disc(frame, "BACKGROUND", 2, rim, 0.05, 0.04, 0.03)
  frame.Picture = frame:CreateTexture(nil, "ARTWORK")
  frame.Picture:SetPoint("TOPLEFT", rim + 1, -(rim + 1))
  frame.Picture:SetPoint("BOTTOMRIGHT", -(rim + 1), rim + 1)
  local mask = frame.CreateMaskTexture and frame:CreateMaskTexture()
  if mask then
    mask:SetTexture(MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    mask:SetAllPoints(frame.Picture)
    frame.Picture:AddMaskTexture(mask)
  end
  if badge then
    frame.Badge = CreateFrame("Frame", nil, frame)
    frame.Badge:SetSize(badge, badge)
    frame.Badge:SetPoint("BOTTOMRIGHT", badge * 0.1, -badge * 0.1)
    frame.Badge:SetFrameLevel(frame:GetFrameLevel() + 2)
    Disc(frame.Badge, "BACKGROUND", 1, 0, W.GOLD[1], W.GOLD[2], W.GOLD[3])
    Disc(frame.Badge, "BACKGROUND", 2, 2, 0.07, 0.06, 0.04)
    frame.Level = W.Text(frame.Badge, badge >= 26 and "GameFontNormal" or "GameFontNormalSmall")
    frame.Level:SetPoint("CENTER", 0, 0)
  end
  -- member m: race icon (else the class icon), ring in the class color, level
  function frame:SetMember(m)
    local info = RaceInfo(m)
    if info and info.icon then
      self.Picture:SetTexture(info.icon)
      self.Picture:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    else
      SetClassIcon(self.Picture, m.classFile)
    end
    local r, g, b = W.ClassColor(m.classFile)
    self.Ring:SetVertexColor(r or 1, g or 1, b or 1)
    if rawget(self, "Level") then self.Level:SetText(m.level or "") end
    return info
  end
  return frame
end

local function Number(n)
  local big = rawget(_G, "BreakUpLargeNumbers")
  return big and big(n) or tostring(n)
end

-- Place of member key in the guild for statistic id: place, count (nil when the member has no value)
local function Place(entries, key, id)
  local ranking = ns.Stats.Ranking(entries, id, "all", ns.Now(), ns.GameStats.Date)
  for i, row in ipairs(ranking) do
    if row.key == key then return i, #ranking, row.value end
  end
  return nil, #ranking
end

-- The title of member key's first places in the Hall of Fame (the best title card), or nil
local function FirstTitle(entries, key)
  for _, fame in ipairs(ns.Stats.PAGES) do
    for _, title in ipairs(fame.titles or {}) do
      local place, _, value = Place(entries, key, title.stat)
      if place == 1 and value and value > 0 then return ns.L["FAME_TITLE_" .. title.key] end
    end
  end
  return nil
end

local function ProfList(m)
  local record = ns.TradeSkill.Record(m)
  local list = {}
  for _, skillLine in ipairs(ns.Professions.ORDER) do
    local prof = record and record.profs and record.profs[skillLine]
    if prof then list[#list + 1] = { skillLine = skillLine, prof = prof } end
  end
  return list
end

-- the width of a text as written, not cut to its column
local function TextWidth(text)
  local fn = text.GetUnboundedStringWidth
  local width = type(fn) == "function" and fn(text) or nil
  if type(width) ~= "number" then width = text:GetStringWidth() end
  return type(width) == "number" and width or 0
end

-- Colour of an activity bucket, as the endgame view draws its bars (UI/OverviewEndgame.lua)
local function BucketColor(bucket)
  if bucket >= 5 then return 0.5, 0.47, 0.4 end
  local green = 1 - (bucket - 1) / 3
  return 1 - green * 0.6, 0.35 + green * 0.5, 0.25
end

-- A weekly count: one decimal below 10, whole above
local function Weekly(value)
  value = value or 0
  if value < 10 then return (string.format("%.1f", value):gsub("%.", ns.L.DECIMAL_MARK)) end
  return tostring(math.floor(value + 0.5))
end

local function Hex(color)
  return ("|cff%02x%02x%02x"):format(color[1] * 255, color[2] * 255, color[3] * 255)
end

-- "3 Tagen", "5 Std." ...: how long ago, for the line under the gear
local function Span(seconds)
  local L = ns.L
  seconds = math.max(0, seconds)
  if seconds < 3600 then return L.GEAR_SPAN_MIN:format(math.max(1, math.floor(seconds / 60))) end
  if seconds < 86400 then return L.GEAR_SPAN_HOURS:format(math.floor(seconds / 3600)) end
  if seconds < 2 * 86400 then return L.GEAR_SPAN_DAY end
  return L.GEAR_SPAN_DAYS:format(math.floor(seconds / 86400))
end

-- Box with a title and a right-aligned note
local function Section(parent, title)
  local box = W.Box(parent)
  box.Title = W.Text(box, "GameFontNormal", title)
  box.Title:SetPoint("TOPLEFT", 12, -9)
  box.Note = W.Text(box, "GameFontDisableSmall")
  box.Note:SetPoint("TOPRIGHT", -12, -11)
  box.Note:SetJustifyH("RIGHT")
  return box
end

-- Big number tile: label, value, a line under it (place in the guild)
local function Tile(parent, label)
  local tile = W.Box(parent)
  tile.Label = W.Text(tile, "GameFontDisableSmall", label)
  tile.Label:SetPoint("TOPLEFT", 12, -9)
  tile.Value = W.Text(tile, "GameFontHighlightHuge")
  tile.Value:SetPoint("TOPLEFT", tile.Label, "BOTTOMLEFT", 0, -4)
  tile.Line = W.Text(tile, "GameFontNormalSmall")
  tile.Line:SetPoint("TOPLEFT", tile.Value, "BOTTOMLEFT", 0, -3)
  tile.Line:SetPoint("RIGHT", -10, 0)
  tile.Line:SetWordWrap(false)
  return tile
end

-- A line of the family list: name in the class color, level and class; click opens their page
local function FamilyLine(parent)
  local line = CreateFrame("Button", nil, parent)
  line:SetHeight(LINE_H)
  line:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  local glow = line:CreateTexture(nil, "HIGHLIGHT")
  glow:SetAllPoints()
  glow:SetColorTexture(1, 0.82, 0, 0.06)
  line.Name = W.Text(line, "GameFontHighlightSmall")
  line.Name:SetPoint("LEFT", 0, 0)
  line.Name:SetWordWrap(false)
  line.Info = W.Text(line, "GameFontDisableSmall")
  line.Info:SetPoint("LEFT", line.Name, "RIGHT", 6, 0)
  line.Info:SetPoint("RIGHT", 0, 0)
  line.Info:SetWordWrap(false)
  line:SetScript("OnClick", function(self, button)
    if not self.member then return end
    if button == "RightButton" then UI.MemberMenu(self.member, self) else UI.MemberClick(self.member) end
  end)
  line:SetScript("OnEnter", function(self) if self.member then UI.MemberTooltip(self, self.member) end end)
  line:SetScript("OnLeave", function() GameTooltip:Hide() end)
  function line:SetMember(m)
    self.member = m
    self.Name:SetText(W.ClassName(m.name, m.classFile)) -- roster names are made up already for pictures
    self.Name:SetWidth(math.min(TextWidth(self.Name) + 2, 150))
    self.Info:SetText(ns.L.LEVEL_CLASS:format(m.level or 0, m.className or ""))
  end
  return line
end

-- A row of the gear list: slot, icon, item name, enchantment, item level bar with the ready tick, level
local function GearRow(parent)
  local row = CreateFrame("Button", nil, parent)
  local shade = row:CreateTexture(nil, "BACKGROUND")
  shade:SetAllPoints()
  shade:SetColorTexture(1, 1, 1, 0.025)
  row.Shade = shade
  local glow = row:CreateTexture(nil, "HIGHLIGHT")
  glow:SetAllPoints()
  glow:SetColorTexture(1, 0.82, 0, 0.06)
  row.Slot = W.Text(row, "GameFontDisableSmall")
  row.Slot:SetPoint("LEFT", 0, 0)
  row.Slot:SetWidth(92)
  row.Slot:SetWordWrap(false)
  row.Icon = row:CreateTexture(nil, "ARTWORK")
  row.Icon:SetSize(16, 16)
  row.Icon:SetPoint("LEFT", 96, 0)
  row.Name = W.Text(row, "GameFontHighlightSmall")
  row.Name:SetPoint("LEFT", row.Icon, "RIGHT", 6, 0)
  row.Name:SetWordWrap(false)
  row.Enchant = W.Text(row, "GameFontHighlightSmall")
  row.Enchant:SetPoint("LEFT", row.Name, "RIGHT", 6, 0)
  row.Enchant:SetWordWrap(false)
  row.Level = W.Text(row, "GameFontHighlightSmall")
  row.Level:SetPoint("RIGHT", 0, 0)
  row.Level:SetWidth(28)
  row.Level:SetJustifyH("RIGHT")
  row.Track = row:CreateTexture(nil, "BORDER")
  row.Track:SetHeight(6)
  row.Track:SetPoint("RIGHT", row.Level, "LEFT", -8, 0)
  row.Track:SetColorTexture(0, 0, 0, 0.45)
  row.Bar = row:CreateTexture(nil, "ARTWORK")
  row.Bar:SetHeight(6)
  row.Bar:SetPoint("LEFT", row.Track, "LEFT", 0, 0)
  row.Tick = row:CreateTexture(nil, "OVERLAY")
  row.Tick:SetSize(2, 14)
  row.Tick:SetColorTexture(1, 0.82, 0, 0.9)
  row:SetScript("OnEnter", function(self)
    if not self.item then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetHyperlink(ns.Gear.ItemString(self.item))
    GameTooltip:Show()
  end)
  row:SetScript("OnLeave", function() GameTooltip:Hide() end)
  return row
end

local function ItemIcon(itemID)
  local get = (C_Item and rawget(C_Item, "GetItemIconByID")) or rawget(_G, "GetItemIconByID") or rawget(_G, "GetItemIcon")
  return get and ns.Try(get, itemID) or nil
end

-- Name of a stored item (with its suffix) once the client has its info, else nil
local function ItemName(item)
  local getInfo = rawget(_G, "GetItemInfo") or (C_Item and C_Item.GetItemInfo)
  local name = getInfo and ns.Try(getInfo, ns.Gear.ItemString(item))
  if type(name) ~= "string" or ns.IsSecret(name) then
    ns.GameGear.ItemInfo(item.id) -- asks the game to load it; the page redraws on GEAR_INFO
    return nil
  end
  return name
end

local function Build()
  local L = ns.L
  page = CreateFrame("Frame", nil, UI.Content())
  page:SetAllPoints()
  page:Hide()

  local shell = W.Page(page) -- the same toolbar and body as every tab
  local body = shell.Body
  page.Body = body
  page.Back = shell:Left(W.Button(shell.Bar, L.BACK, function() UI.SelectTab(page.backTab or "chat") end, 90, { small = true }))

  -- hero card --------------------------------------------------------------------------------------
  local hero = W.Box(body)
  hero:SetPoint("TOPLEFT", 0, 0)
  hero:SetWidth(HERO_WIDTH)
  page.Hero = hero
  -- the model area: the character itself comes in later; until then (and wherever the game cannot show
  -- the member) the race portrait
  hero.ModelArea = CreateFrame("Frame", nil, hero)
  hero.ModelArea:SetPoint("TOPLEFT", 1, -1)
  hero.ModelArea:SetPoint("TOPRIGHT", -1, -1)
  hero.ModelArea:SetHeight(200)
  page.ModelArea = hero.ModelArea
  hero.Portrait = Portrait(hero.ModelArea, 104)
  hero.Portrait:SetPoint("CENTER", 0, 0)
  hero.ModelHint = W.Text(hero, "GameFontDisableSmall", L.MODEL_HINT)
  hero.ModelHint:SetPoint("TOP", hero.ModelArea, "BOTTOM", 0, -2)
  hero.ModelHint:Hide()
  hero.LevelRing = CreateFrame("Frame", nil, hero)
  hero.LevelRing:SetSize(34, 34)
  hero.LevelRing:SetPoint("TOPRIGHT", -12, -12)
  hero.LevelRing:SetFrameLevel(hero.ModelArea:GetFrameLevel() + 3)
  Disc(hero.LevelRing, "BACKGROUND", 1, 0, W.GOLD[1], W.GOLD[2], W.GOLD[3])
  Disc(hero.LevelRing, "BACKGROUND", 2, 2, 0.07, 0.06, 0.04)
  hero.Level = W.Text(hero.LevelRing, "GameFontNormal")
  hero.Level:SetPoint("CENTER", 0, 0)
  hero.Name = W.Text(hero, "GameFontNormalHuge")
  hero.Name:SetPoint("TOP", hero.ModelArea, "BOTTOM", 0, -18)
  hero.Name:SetWidth(HERO_WIDTH - 24)
  hero.Name:SetWordWrap(false)
  hero.Title = W.Text(hero, "GameFontNormal")
  hero.Title:SetPoint("TOP", hero.Name, "BOTTOM", 0, -4)
  hero.Ident = W.Text(hero, "GameFontHighlightSmall")
  -- long race names ("Himmelsgeborene des Hohen Ordens") wrap inside the card; the class icon is inline
  hero.Ident:SetPoint("TOP", hero.Title, "BOTTOM", 0, -8)
  hero.Ident:SetWidth(HERO_WIDTH - 24)
  hero.Ident:SetJustifyH("CENTER")
  hero.Ident:SetSpacing(2)
  hero.Where = W.Text(hero, "GameFontDisableSmall")
  hero.Where:SetPoint("TOP", hero.Ident, "BOTTOM", 0, -5)
  hero.Where:SetJustifyH("CENTER")
  hero.Where:SetWidth(HERO_WIDTH - 24) -- long guild names wrap inside the card
  hero.Where:SetSpacing(2)
  hero.Notes = W.Text(hero, "GameFontHighlightSmall")
  hero.Notes:SetSpacing(2)
  hero.Whisper = W.Button(hero, L.WHISPER, function() if page.member then UI.Whisper(page.member.fullName) end end, 110)
  hero.Invite = W.Button(hero, L.GROUP_INVITE_SHORT, function() if page.member then ns.Roster.GroupInvite(page.member) end end, 110)

  -- officer bar: removal (rank and notes are in Blizzard's own member panel beside the page,
  -- UI/Notes.lua)
  hero.OfficerLabel = W.Text(hero, "GameFontNormalSmall", L.OFFICERS)
  hero.OfficerLabel:SetTextColor(0.85, 0.5, 0.25)
  hero.Remove = W.Button(hero, L.REMOVE_SHORT, function()
    local m = page.member
    UI.ConfirmRemove(m)
  end, 80, { small = true })

  -- right side -------------------------------------------------------------------------------------
  local right = CreateFrame("Frame", nil, body)
  right:SetPoint("TOPLEFT", hero, "TOPRIGHT", 8, 0)
  page.Right = right

  page.Tiles = {
    kills = Tile(right, L.STAT_KILLS), quests = Tile(right, L.STAT_QUESTS),
    deaths = Tile(right, L.STAT_DEATHS), gear = Tile(right, L.STAT_ILVL), score = Tile(right, L.SCORE_TILE),
  }
  -- the activity score: how it is made in the tooltip (Core/Activity.lua keeps what fed it)
  local scoreTile = page.Tiles.score
  scoreTile:EnableMouse(true)
  scoreTile:SetScript("OnEnter", function(self) page:ScoreTooltip(self) end)
  scoreTile:SetScript("OnLeave", function() GameTooltip:Hide() end)
  -- equipment by quality: a bar per quality under the item level tile
  local gearTile = page.Tiles.gear
  gearTile.Bars = {}
  for i, color in ipairs({ { 1, 0.5, 0 }, { 0.64, 0.21, 0.93 }, { 0, 0.44, 0.87 }, { 0.12, 1, 0 }, { 1, 1, 1 }, { 0.62, 0.62, 0.62 } }) do
    local bar = gearTile:CreateTexture(nil, "ARTWORK")
    bar:SetHeight(6)
    bar:SetColorTexture(color[1], color[2], color[3], 0.9)
    gearTile.Bars[i] = bar
  end

  -- gear list
  local gear = Section(right, L.GEAR)
  page.Gear = gear
  gear.Head = W.Text(gear, "GameFontDisableSmall", L.GEAR_LEVEL_HEAD)
  gear.Rows = {}
  for i, slot in ipairs(LIST) do
    local row = GearRow(gear)
    row.slot = slot
    row.Slot:SetText(SlotName(slot))
    row.Shade:SetShown(i % 2 == 1)
    gear.Rows[i] = row
  end
  gear.Foot = W.Text(gear, "GameFontDisableSmall")
  gear.Foot:SetPoint("BOTTOMLEFT", 12, 8)
  gear.Foot:SetPoint("RIGHT", -12, 0)
  gear.Foot:SetWordWrap(false)

  -- column: family, upgrades, professions
  local family = Section(right, L.FAMILY)
  page.Family = family
  family.Empty = W.Text(family, "GameFontDisableSmall", L.FAMILY_EMPTY)
  family.Empty:SetPoint("TOPLEFT", 12, -30)
  family.Empty:SetPoint("RIGHT", -12, 0)
  family.Lines = {}
  for i = 1, FAMILY_LINES do
    local line = FamilyLine(family)
    line:SetPoint("TOPLEFT", 12, -28 - (i - 1) * LINE_H)
    line:SetPoint("RIGHT", -12, 0)
    family.Lines[i] = line
  end
  family.More = W.Text(family, "GameFontDisableSmall")

  local upgrades = Section(right, L.UPGRADES)
  page.Upgrades = upgrades
  upgrades.Empty = W.Text(upgrades, "GameFontDisableSmall", L.UPGRADES_NO_DATA)
  upgrades.Empty:SetPoint("TOPLEFT", 12, -30)
  upgrades.Empty:SetPoint("RIGHT", -12, 0)
  upgrades.want = 56

  local profs = Section(right, L.PROFESSIONS)
  page.Profs = profs
  profs.Rows = {}
  for i = 1, PROF_ROWS do
    local row = CreateFrame("Frame", nil, profs)
    row:SetHeight(18)
    row:SetPoint("TOPLEFT", 12, -30 - (i - 1) * 22)
    row:SetPoint("RIGHT", -12, 0)
    row.Icon = row:CreateTexture(nil, "ARTWORK")
    row.Icon:SetSize(16, 16)
    row.Icon:SetPoint("LEFT")
    row.Name = W.Text(row, "GameFontHighlightSmall")
    row.Name:SetPoint("LEFT", row.Icon, "RIGHT", 6, 0)
    row.Name:SetWidth(110)
    row.Name:SetWordWrap(false)
    -- skill like the professions tab: number, the bar on the 0-300 scale with the trainer caps, "Trainer"
    row.Level = W.Text(row, "GameFontHighlightSmall")
    row.Level:SetPoint("LEFT", row.Name, "RIGHT", 4, 0)
    row.Level:SetWidth(56)
    row.Level:SetJustifyH("RIGHT")
    row.Trainer = W.Text(row, "GameFontNormalSmall", L.TRAINER)
    row.Trainer:SetPoint("RIGHT")
    row.Bar = W.SkillBar(row, 100)
    row.Bar:SetPoint("LEFT", row.Level, "RIGHT", 8, 0)
    profs.Rows[i] = row
  end
  profs.Empty = W.Text(profs, "GameFontDisableSmall", L.NO_PROFESSIONS)
  profs.Empty:SetPoint("TOPLEFT", 12, -32)

  -- render -----------------------------------------------------------------------------------------
  function page:RenderHero(m, entries)
    local can = ns.Roster.Can()
    local info = hero.Portrait:SetMember(m)
    hero.Level:SetText(m.level or "")
    hero.Name:SetText(W.ClassName(m.name, m.classFile))
    local title = FirstTitle(entries, m.key)
    hero.Title:SetText(title and ("„" .. title .. "“") or "")
    local ident = {}
    if info and info.race then ident[#ident + 1] = info.race end
    if info then ident[#ident + 1] = info.female and L.FEMALE or L.MALE end
    ident[#ident + 1] = m.className or ""
    hero.Ident:SetText(ClassIconString(m.classFile) .. table.concat(ident, ns.L.SEP))
    hero.Where:SetText((m.rank or "") .. (m.zone and m.zone ~= "" and (ns.L.SEP .. m.zone) or "") .. ns.L.SEP ..
      (m.online and ("|cff4ce64c" .. L.ONLINE .. "|r") or ns.Roster.LastOnlineText(m)))

    local notes = {}
    local since = ns.Roster.TenureText(m, true)
    if since then notes[#notes + 1] = L.LABEL_VALUE:format("|cffffd100" .. L.MEMBER_SINCE, "|r" .. since) end
    if m.note and m.note ~= "" then notes[#notes + 1] = L.LABEL_VALUE:format("|cffffd100" .. L.NOTE, "|r" .. m.note) end
    if can.viewOfficer and m.officerNote and m.officerNote ~= "" then
      notes[#notes + 1] = L.LABEL_VALUE:format("|cffffd100" .. L.OFFICER_NOTE, "|r" .. m.officerNote)
    end
    local guildy = UI.GuildyVersionText and UI.GuildyVersionText(m)
    if guildy then notes[#notes + 1] = L.LABEL_VALUE:format("|cffffd100" .. L.COL_GUILDY, "|r" .. guildy) end
    hero.Notes:SetText(table.concat(notes, "\n"))
    hero.Notes:ClearAllPoints()
    hero.Notes:SetPoint("TOP", hero.Where, "BOTTOM", 0, -10)
    hero.Notes:SetWidth(HERO_WIDTH - 28)

    local officer = can.remove
    hero.OfficerLabel:SetShown(officer)
    hero.Remove:SetShown(officer and can.remove)
    hero.Remove:SetEnabled(ns.Roster.Rights(m).remove or false)
    local y = 10
    if officer then
      hero.Remove:ClearAllPoints()
      hero.Remove:SetPoint("BOTTOMLEFT", 12, y)
      hero.OfficerLabel:ClearAllPoints()
      hero.OfficerLabel:SetPoint("BOTTOMLEFT", 14, y + 28)
      y = y + 50
    end
    hero.Whisper:ClearAllPoints()
    hero.Whisper:SetPoint("BOTTOMRIGHT", hero, "BOTTOM", -3, y)
    hero.Invite:ClearAllPoints()
    hero.Invite:SetPoint("BOTTOMLEFT", hero, "BOTTOM", 3, y)
    hero.Whisper:SetEnabled(m.online or false)
    hero.Invite:SetEnabled(m.online or false)
    UI.Notes.Show(m)
  end

  -- the family as a list, as many lines as the box has room for (lines), "+N" after
  function page:RenderFamily(m, lines)
    local guild, db = ns.GuildData(), ns.DB()
    local list = ns.Family.Of(m.key, ns.Roster.Members(), guild and guild.families, db and db.ownChars)
    lines = math.max(1, math.min(lines or FAMILY_LINES, FAMILY_LINES))
    local shown = math.min(#list, lines)
    for i, line in ipairs(family.Lines) do
      if i <= shown then
        line:SetMember(list[i])
        line:Show()
      else
        line:Hide()
      end
    end
    family.Empty:SetShown(#list == 0)
    family.More:ClearAllPoints()
    family.More:SetPoint("TOPLEFT", 12, -28 - shown * LINE_H - 2)
    family.More:SetText(#list > shown and L.FAMILY_MORE:format(#list - shown) or "")
    family.Note:SetText("")
    if #list == 0 then return 74 end
    return 36 + shown * LINE_H + (#list > shown and 16 or 0)
  end

  function page:RenderStats(m, entries)
    local S = ns.Stats
    local guild = ns.GuildData()
    local record = guild and guild.members[m.key]
    local rec = record and record.stats
    local t = self.Tiles
    local function Fill(tile, id)
      local value = S.Value(rec, id, "all", ns.Now(), ns.GameStats.Date)
      tile.Value:SetText(value and Number(value) or "–")
      local place, count = Place(entries, m.key, id)
      return value, place, count
    end
    local _, place, count = Fill(t.kills, 107)
    t.kills.Line:SetText(place and L.PLACE_OF:format(place, count) or "")
    _, place, count = Fill(t.quests, 98)
    t.quests.Line:SetText(place and L.PLACE_OF:format(place, count) or "")
    Fill(t.deaths, 60)
    local hogger = S.Value(rec, 594, "all", ns.Now(), ns.GameStats.Date)
    t.deaths.Line:SetText(hogger and hogger > 0 and L.DEATHS_HOGGER:format(hogger) or "")
    local values = rec and rec.v or {}
    local ilvl = values[S.GEAR.ILVL]
    t.gear.Value:SetText(ilvl and UI.Fame.Format(S.GEAR.ILVL, ilvl) or "–")
    place, count = Place(entries, m.key, S.GEAR.ILVL)
    t.gear.Line:SetText(ilvl and place and L.PLACE_OF:format(place, count) or "")
    local counts = { values[S.GEAR.LEGENDARY] or 0, values[S.GEAR.EPIC] or 0, values[S.GEAR.RARE] or 0,
      values[S.GEAR.UNCOMMON] or 0, values[S.GEAR.COMMON] or 0, values[S.GEAR.POOR] or 0 }
    local total = 0
    for _, n in ipairs(counts) do total = total + n end
    local barWidth = (t.gear:GetWidth() or 120) - 24
    local x = 12
    for i, bar in ipairs(t.gear.Bars) do
      local w = total > 0 and math.floor(counts[i] / total * barWidth + 0.5) or 0
      bar:ClearAllPoints()
      bar:SetPoint("BOTTOMLEFT", t.gear, "BOTTOMLEFT", x, 10)
      bar:SetWidth(math.max(w, 0.01))
      bar:SetShown(w > 0)
      x = x + w
    end
    return rec
  end

  function page:RenderScore(m)
    local score, parts, detail = ns.GameActivity.ScoreOf(m.key)
    self.score = { score = score, parts = parts, detail = detail }
    local tile = self.Tiles.score
    local bucket = ns.Activity.Bucket(score)
    tile.Value:SetText(score and tostring(score) or "–")
    tile.Line:SetText(L["SCORE_" .. bucket])
    tile.Line:SetTextColor(BucketColor(bucket))
  end

  function page:ScoreTooltip(owner)
    local info = self.score or {}
    local A = ns.Activity
    GameTooltip:SetOwner(owner, "ANCHOR_BOTTOM")
    if not info.score or not info.detail then
      GameTooltip:SetText(L.SCORE_5, BucketColor(5))
      GameTooltip:AddLine(L.SCORE_HINT, 1, 1, 1, true)
      GameTooltip:Show()
      return
    end
    local d, parts, max = info.detail, info.parts or {}, A.MAX
    local grey = 0.6
    local function Points(x) return math.floor((x or 0) + 0.5) end
    GameTooltip:SetText(L.SCORE_TIP_TITLE:format(info.score), BucketColor(A.Bucket(info.score)))
    GameTooltip:AddLine(L.SCORE_PART_PRESENCE:format(Points(parts.presence), max.presence), 1, 1, 1)
    GameTooltip:AddLine(d.presence and L.SCORE_FED_PRESENCE:format(Weekly(d.presence)) or L.SCORE_PRESENCE_UNCOUNTED, grey, grey, grey, true)
    GameTooltip:AddLine(L.SCORE_PART_PLAYING:format(Points(parts.playing), max.playing), 1, 1, 1)
    local r = d.rates or {}
    GameTooltip:AddLine(L.SCORE_FED_PLAYING:format(Weekly(r.kills), Weekly(r.honorKills), Weekly(r.quests)), grey, grey, grey, true)
    GameTooltip:AddLine(L.SCORE_PART_GROUP:format(Points(parts.group), max.group), 1, 1, 1)
    GameTooltip:AddLine(L.SCORE_FED_GROUP:format(Weekly(r.raidBosses), Weekly(r.dungeonBosses), Weekly(r.dungeons),
      Weekly(r.battlegrounds)), grey, grey, grey, true)
    if d.scaled then GameTooltip:AddLine(L.SCORE_SCALED:format(A.MIN_COUNTED), 1, 0.82, 0, true) end
    if d.fade then
      GameTooltip:AddLine(L.SCORE_FADED:format(math.floor(d.away or 0), math.floor(d.fade * 100 + 0.5)), 1, 0.5, 0.25, true)
    end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(L.SCORE_PER_PLAYER, grey, grey, grey, true)
    if d.chars and #d.chars > 1 then
      local names = {}
      for _, key in ipairs(d.chars) do
        local other = ns.Roster.Find(key) -- roster names are made up for pictures already
        if other then names[#names + 1] = W.ClassName(other.name, other.classFile) end
      end
      GameTooltip:AddLine(L.SCORE_CHARS:format(table.concat(names, ns.L.SEP)), 1, 1, 1, true)
    end
    if d.fromDay and d.toDay then
      GameTooltip:AddLine(L.SCORE_WINDOW:format(ns.GameStats.Date(L.DATE_LONG, A.DayTime(d.fromDay)),
        ns.GameStats.Date(L.DATE_LONG, A.DayTime(d.toDay))), grey, grey, grey)
    end
    GameTooltip:Show()
  end

  -- The guild's ready mark for level (median average item level of the roster members of that level,
  -- tenths) and the highest stored item level (the bars' scale)
  local function GuildGear(level)
    local guild = ns.GuildData()
    local list, top = {}, 1
    for _, other in ipairs(ns.Roster.Members()) do
      local record = guild and guild.members[other.key]
      local stats = record and record.stats
      local ilvl = type(stats) == "table" and type(stats.v) == "table" and stats.v[ns.Stats.GEAR.ILVL]
      if ilvl then list[#list + 1] = { other.level, ilvl } end
      local rec = guild and type(guild.gear) == "table" and guild.gear[other.key]
      for _, slot in ipairs(LIST) do
        local item = type(rec) == "table" and rec.items and rec.items[slot]
        if item and (item.l or 0) > top then top = item.l end
      end
    end
    return ns.Gear.ReadyMark(list, level), top
  end

  function page:RenderGear(m)
    local G = ns.Gear
    local guild = ns.GuildData()
    local rec = guild and type(guild.gear) == "table" and guild.gear[m.key] or nil
    if type(rec) ~= "table" or type(rec.items) ~= "table" then rec = nil end
    local width, height = gear:GetWidth() or 400, gear:GetHeight() or 400
    local rowH, barW, enchantW = G.Fit(height, width)
    local ready, top = GuildGear(m.level)
    local missing, count = {}, 0
    if rec then missing, count = G.Unenchanted(rec, ns.GameGear.EquipLoc) end
    local room = math.max(0, width - 24 - G.FIXED - barW) -- name and enchantment together
    gear.Head:ClearAllPoints()
    gear.Head:SetPoint("TOPRIGHT", -(12 + 28 + 8), -24) -- over the bars, ending where they end
    for i, row in ipairs(gear.Rows) do
      local item = rec and rec.items[row.slot]
      row.item = item
      row:ClearAllPoints()
      row:SetPoint("TOPLEFT", 12, -GEAR_TOP - (i - 1) * rowH)
      row:SetSize(width - 24, rowH)
      row.Track:SetWidth(barW)
      if item then
        local color = QUALITY[item.q] or QUALITY[1]
        row.Icon:SetTexture(ItemIcon(item.id) or "Interface\\Icons\\INV_Misc_QuestionMark")
        row.Icon:Show()
        local name = ItemName(item)
        row.Name:SetText(Hex(color) .. (name or "…") .. "|r")
        local enchant, enchantColor
        if item.e ~= 0 then
          enchant, enchantColor = ns.GameGear.EnchantText(item.id, item.e), ENCHANT_COLOR
        elseif missing[row.slot] then
          enchant, enchantColor = L.NO_ENCHANT, MISSING_COLOR
        end
        row.Enchant:SetText(enchant or "")
        if enchantColor then row.Enchant:SetTextColor(enchantColor[1], enchantColor[2], enchantColor[3]) end
        -- the item name takes what it needs; the enchantment gets the rest and is cut first
        local wantEnchant = enchant and math.min(TextWidth(row.Enchant), enchantW) or 0
        local nameW = math.max(math.min(G.NAME_MIN, room), math.min(TextWidth(row.Name) + 2, room - wantEnchant - (enchant and 6 or 0)))
        row.Name:SetWidth(nameW)
        row.Enchant:SetWidth(math.max(1, room - nameW - 6))
        row.Enchant:SetShown(enchant ~= nil and room - nameW - 6 > 20)
        row.Bar:SetColorTexture(color[1], color[2], color[3], 0.9)
        row.Bar:SetWidth(math.max(1, math.min(1, (item.l or 0) / top) * barW))
        row.Bar:Show()
        row.Level:SetText(tostring(item.l or 0))
      else
        row.Icon:Hide()
        row.Name:SetText("")
        row.Enchant:SetText("")
        row.Bar:Hide()
        row.Level:SetText("–")
      end
      row.Track:SetShown(item ~= nil)
      if ready and item then
        row.Tick:ClearAllPoints()
        row.Tick:SetPoint("CENTER", row.Track, "LEFT", math.min(1, ready / 10 / top) * barW, 0)
        row.Tick:Show()
      else
        row.Tick:Hide()
      end
      row:Show()
    end
    -- header: average, ready mark, missing enchantments, each only when known
    local parts = {}
    local average = rec and G.Average(rec)
    if average then parts[#parts + 1] = L.GEAR_AVG:format(UI.Fame.Format(ns.Stats.GEAR.ILVL, average)) end
    if ready then parts[#parts + 1] = L.GEAR_READY:format(math.floor(ready / 10 + 0.5)) end
    if rec and count > 0 then parts[#parts + 1] = L.GEAR_UNENCHANTED:format(count) end
    gear.Note:SetText(table.concat(parts, ns.L.SEP))
    -- under the list: how old the reading is and where it comes from, or why there is none
    local name = m.name -- (made up for pictures by the roster itself, Game/Roster.lua)
    if not rec then
      gear.Foot:SetText(L.GEAR_UNSEEN:format(name))
    elseif rec.src == "self" then
      gear.Foot:SetText(L.GEAR_SELF_AGO:format(name, Span(ns.Now() - (rec.ts or 0))))
    elseif rec.src == "api" then
      gear.Foot:SetText(L.GEAR_API_AGO:format(Span(ns.Now() - (rec.ts or 0))))
    else
      gear.Foot:SetText(L.GEAR_SEEN_AGO:format(Span(ns.Now() - (rec.ts or 0))))
    end
    return rec
  end

  function page:RenderUpgrades()
    upgrades.Empty:SetText(L.UPGRADES_NO_DATA)
    upgrades.Empty:Show()
    return upgrades.want
  end

  function page:RenderProfs(m)
    local list = ProfList(m)
    -- the names first: the column is as wide as the longest one with its specialization (at least 110,
    -- at most 200), the same for every row so the numbers stand in one column
    local nameWidth = 110
    for i, row in ipairs(profs.Rows) do
      local p = list[i]
      if p then
        local tag = UI.SpecTag(p.prof)
        row.Name:SetText(ns.TradeSkill.Name(p.skillLine) .. (tag and ("  |cff8f8268" .. tag .. "|r") or ""))
        nameWidth = math.max(nameWidth, math.min(200, math.ceil(TextWidth(row.Name)) + 4))
      end
    end
    for i, row in ipairs(profs.Rows) do
      local p = list[i]
      if p then
        row.Icon:SetTexture(ns.Professions.ICONS[p.skillLine])
        local prof = p.prof
        row.Name:SetWidth(nameWidth)
        row.Level:SetText(prof.rank and (prof.rank .. (prof.max and ("|cff999999/" .. prof.max .. "|r") or "")) or "|cff999999–|r")
        local atCap = prof.rank ~= nil and prof.max ~= nil and prof.rank >= prof.max and prof.max < W.SKILL_SCALE
        row.Trainer:SetShown(atCap)
        -- the bar takes the room between the number and the "Trainer" label
        local rowWidth = (profs:GetWidth() or 300) - 24
        row.Bar:SetBarWidth(math.max(40, rowWidth - 16 - 6 - nameWidth - 4 - 56 - 8 - 8 - (atCap and (row.Trainer:GetStringWidth() or 40) or 0)))
        if prof.rank then
          row.Bar:SetSkill(prof.rank, prof.max)
          row.Bar:Show()
        else
          row.Bar:Hide()
        end
        row:Show()
      else
        row:Hide()
      end
    end
    profs.Empty:SetShown(#list == 0)
    return 34 + math.max(1, #list) * 22
  end

  -- sizes of everything from the page's own size (the smallest window is 1130 x 560: content 1108 x 518)
  function page:Layout()
    local pageW, pageH = self:GetWidth() or 0, self:GetHeight() or 0
    local bodyH = math.max(200, pageH - (W.BAR_H + 6))
    local rightW = math.max(400, pageW - HERO_WIDTH - W.GAP)
    hero:SetSize(HERO_WIDTH, bodyH)
    hero.ModelArea:SetHeight(math.floor(bodyH * 0.45))
    right:SetSize(rightW, bodyH)
    local tileW = math.floor((rightW - (#TILE_KEYS - 1) * W.GAP) / #TILE_KEYS)
    for i, key in ipairs(TILE_KEYS) do
      local tile = self.Tiles[key]
      tile:ClearAllPoints()
      tile:SetSize(tileW, TILE_H)
      tile:SetPoint("TOPLEFT", right, "TOPLEFT", (i - 1) * (tileW + W.GAP), 0)
    end
    local y = -(TILE_H + W.GAP)
    local areaH = bodyH - TILE_H - W.GAP
    local gearW = math.floor((rightW - W.GAP) * GEAR_SHARE)
    local colW = rightW - W.GAP - gearW
    gear:ClearAllPoints()
    gear:SetPoint("TOPLEFT", right, "TOPLEFT", 0, y)
    gear:SetSize(gearW, areaH)
    for _, box in ipairs({ family, upgrades, profs }) do box:SetWidth(colW) end
    return y, areaH, gearW, colW
  end

  -- the column: family as tall as its lines, upgrades as they need, professions take the rest
  function page:LayoutColumn(m, y, areaH, gearW)
    local upH = self:RenderUpgrades(m)
    local profsH = self:RenderProfs(m)
    local free = areaH - upH - profsH - 2 * W.GAP - 36
    local familyH = self:RenderFamily(m, math.floor(free / LINE_H))
    family:ClearAllPoints()
    family:SetPoint("TOPLEFT", right, "TOPLEFT", gearW + W.GAP, y)
    family:SetHeight(familyH)
    upgrades:ClearAllPoints()
    upgrades:SetPoint("TOPLEFT", family, "BOTTOMLEFT", 0, -W.GAP)
    upgrades:SetHeight(upH)
    profs:ClearAllPoints()
    profs:SetPoint("TOPLEFT", upgrades, "BOTTOMLEFT", 0, -W.GAP)
    profs:SetHeight(math.max(profsH, areaH - familyH - upH - 2 * W.GAP))
  end

  function page:Render()
    local m = self.member and ns.Roster.Find(self.member.key) or self.member
    self.member = m
    if not m then return end
    local entries = ns.GameStats.Entries()
    local y, areaH, gearW = self:Layout()
    self:RenderHero(m, entries)
    self:RenderStats(m, entries)
    self:RenderScore(m)
    self:RenderGear(m)
    self:LayoutColumn(m, y, areaH, gearW)
  end
  ns.Perf.Wrap(page, "Render", "render", "character page")
  page:SetScript("OnHide", function()
    UI.Notes.Hide()
  end)
  page:SetScript("OnSizeChanged", function(self) if self.member and self:IsShown() then self:Render() end end)

  for _, event in ipairs({ "ROSTER", "PROFS", "STATS", "FAMILY", "GEAR", "GEAR_INFO" }) do
    ns.On(event, function() if page:IsShown() then page:Render() end end)
  end
end

-- Open the character page of roster member m (left click on a member anywhere)
function UI.ShowMember(m)
  if not m then return end
  if not page then Build() end
  if not page:IsShown() then page.backTab = UI.Current() end
  page.member = m
  UI.ShowPage(page)
  page:Render()
end

function UI.MemberPage()
  return page
end

-- Building blocks the communities view shares (UI/TabCommunities.lua)
UI.CharParts = { Portrait = Portrait }
