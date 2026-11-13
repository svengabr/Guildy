-- Character page ("hero card"), variant A "readiness": opened by a left click on a member anywhere
-- (chat names, the online list, the members and ranks tab), shown in the content area instead of a
-- tab, with a way back. Left the hero card: the model area (the character, else the race portrait), level, Hall of
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
local PROF_H = 18       -- a profession row
local UPGRADE_H = 42    -- an upgrade block: icon, item name, slot and makers, the gain at the right
local UPGRADE_TOP = 28  -- the heading line above the upgrade rows
local UPGRADE_ICON = 32 -- the icon with its quality border
local FACTS = { "since", "last", "guildy" }
local NOTE_LINES = 3
local MODEL_SHARE = 0.6 -- the model area takes at most this share of the card
local MODEL_MIN = 120   -- and at least this, the notes give up lines first
local MODEL_INSET = 9   -- the picture's distance from the card's edge, room for its gold frame
local CONTENT_GAP = 12  -- between the card's content and its buttons
local FRAME_OUTSET = 4  -- the gold frame's reach beyond the model area
local NAME_GAP = 11     -- air between the gold frame's outer bottom edge and the name
local MODEL_ZOOM = 0.8
local MODEL_SCENE = 596 -- the game's scene of a player in the shop and dressing room
local MODEL_DRESS_AFTER = 0.5 -- s a donor's body needs before it takes the stored items (checked in game)
local MODEL_RETRY_AFTER = 0.5 -- s between looks for a donor while one is missing
local GEAR_SHARE = 0.62 -- of the room right of the hero card, the rest is the column
local GEAR_TOP = 32     -- the heading line (title, summary, column label) above the rows
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
  return { race = localizedRace, file = englishRace, female = female, icon = icon and W.TextureExists(icon) and icon or nil }
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

-- What the page works out from the whole guild, kept until the statistics or the member list change
-- (GameStats.version, Roster.version): the entries, a ranking per statistic, the first titles of the guild;
-- the ready marks and the highest item level besides until stored gear changes (GEAR)
local guildData = { stats = -1, roster = -1, gear = -1, rankings = {}, ready = {} }
local gearVersion = 0
ns.On("GEAR", function() gearVersion = gearVersion + 1 end)

local function GuildData()
  local d = guildData
  local guild = ns.GuildData()
  if d.stats ~= ns.GameStats.version or d.roster ~= ns.Roster.version or d.guild ~= guild or d.anon ~= ns.Anon.on then
    d.stats, d.roster, d.guild, d.anon = ns.GameStats.version, ns.Roster.version, guild, ns.Anon.on
    d.entries, d.rankings, d.firstTitles, d.ready, d.gear = ns.GameStats.Entries(), {}, nil, {}, -1
  end
  if d.gear ~= gearVersion then d.gear, d.ready, d.top = gearVersion, {}, nil end
  return d
end

-- Place of member key in the guild for statistic id: place, count (nil when the member has no value)
local function Place(key, id)
  local d = GuildData()
  local ranking = d.rankings[id]
  if not ranking then
    local list = ns.Stats.Ranking(d.entries, id, "all", ns.Now(), ns.GameStats.Date)
    local places = {}
    for i, row in ipairs(list) do places[row.key] = i end
    ranking = { list = list, places = places }
    d.rankings[id] = ranking
  end
  local i = ranking.places[key]
  if i then return i, #ranking.list, ranking.list[i].value end
  return nil, #ranking.list
end

-- The title of member key's first places in the Hall of Fame (the best title card), or nil
-- (Stats.FirstTitles: worked out for the whole guild once per version, a member is then looked up)
local function FirstTitle(key)
  local d = GuildData()
  if not d.firstTitles then d.firstTitles = ns.Stats.FirstTitles(d.entries, ns.Now(), ns.GameStats.Date) end
  local title = d.firstTitles[key]
  return title and ns.L["FAME_TITLE_" .. title] or nil
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

-- Name of a stored item (with its suffix) once the client has its info, else nil. The item info first:
-- it asks the game once and reads nothing while the item loads (the page redraws on GEAR_INFO);
-- GetItemInfo of an item the client lacks would ask the server again on every render. nil, true when the
-- game said it has no such item: nothing to wait for.
-- A random suffix ("des Tigers") is not in GetItemInfo's name, which is the base item's: the name in the
-- link of the full item string (suffix, unique ID, bonus IDs) where it carries one, else the first line of that
-- string's tooltip, read once per item string.
-- A piece whose tooltip came back with the base name is kept as plain (true) and not read again.
local suffixNames = {} -- full item string -> name as worn, or true for the base name, this session
local function SuffixName(itemString, base, link)
  local known = suffixNames[itemString]
  if known == true then return base end
  if known then return known end
  local inLink = type(link) == "string" and not ns.IsSecret(link) and link:match("|h%[(.-)%]|h")
  local name = inLink and inLink ~= "" and inLink ~= base and inLink or nil
  if not name then
    local first = ns.GearProbe.TooltipLines(itemString)[1]
    name = type(first) == "string" and not ns.IsSecret(first) and first ~= "" and first or nil
  end
  if name then suffixNames[itemString] = name ~= base and name or true end -- an empty tooltip is still loading
  return name
end

local function ItemName(item)
  local info, gone = ns.GameGear.ItemInfo(item.id)
  if not info then return nil, gone end
  local getInfo = rawget(_G, "GetItemInfo") or (C_Item and C_Item.GetItemInfo)
  local itemString = ns.Gear.ItemString(item)
  local name, link
  if getInfo then name, link = ns.Try(getInfo, itemString) end
  if type(name) ~= "string" or ns.IsSecret(name) then return nil end
  if (item.s and item.s ~= 0) or (type(item.b) == "table" and #item.b > 0) then
    return SuffixName(itemString, name, link) or name
  end
  return name
end

-- Guildy's own item tooltips: the item, and beside it the member's worn piece it is compared with.
-- Blizzard's comparison (the shopping tooltips) hangs on GameTooltip and compares with the viewer's own
-- gear, which misleads on another member's page; these frames never ask for it.
local itemTip, wornTip
local Tips = {}
UI.ItemTips = Tips

function Tips.Get()
  if not itemTip then
    itemTip = CreateFrame("GameTooltip", "GuildyItemTooltip", UIParent, "GameTooltipTemplate")
    wornTip = CreateFrame("GameTooltip", "GuildyWornTooltip", UIParent, "GameTooltipTemplate")
    for _, tip in ipairs({ itemTip, wornTip }) do
      tip.supportsItemComparison = false
      W.FloatingPanel(tip, { tooltip = true })
    end
  end
  return itemTip, wornTip
end

function Tips.Hide()
  if itemTip then itemTip:Hide() end
  if wornTip then wornTip:Hide() end
end

-- The worn piece's tooltip beside the item's, on the side with room on the screen: a header line
-- "Trägt <Name>" over the piece (G.ItemString with suffix and unique), "Platz leer" for an empty slot,
-- the name or "…" while the client loads it (asked once, Game/Gear.lua)
function Tips.Worn(tip, beside, name, item)
  tip:SetOwner(beside, "ANCHOR_NONE")
  tip:ClearAllPoints()
  tip:SetPoint("TOPLEFT", beside, "TOPRIGHT", 2, 0)
  local header = ns.L.UPGRADE_WORN:format(name or "")
  local loaded, gone
  if item then loaded, gone = ns.GameGear.ItemInfo(item.id) end
  if item and loaded then
    tip:SetHyperlink(ns.Gear.ItemString(item))
    local first = rawget(_G, (tip:GetName() or "") .. "TextLeft1")
    local text = first and first:GetText()
    if type(text) == "string" and not ns.IsSecret(text) and text ~= "" then
      first:SetText(Hex(W.GOLD) .. header .. "|r\n" .. text)
    else
      tip:AddLine(header, W.GOLD[1], W.GOLD[2], W.GOLD[3])
    end
  else
    tip:SetText(header, W.GOLD[1], W.GOLD[2], W.GOLD[3])
    if not item then
      tip:AddLine(ns.L.UPGRADE_EMPTY, 0.62, 0.62, 0.62)
    else
      local name = not gone and ItemName(item)
      tip:AddLine(name or "…", 1, 1, 1)
    end
  end
  tip:Show()
  -- the left side when the right has no room for it on the screen (its size is known once shown)
  local right, width, screen = beside:GetRight(), tip:GetWidth(), UIParent:GetWidth()
  if type(right) == "number" and type(width) == "number" and type(screen) == "number" and right + 2 + width > screen then
    tip:ClearAllPoints()
    tip:SetPoint("TOPRIGHT", beside, "TOPLEFT", -2, 0)
  end
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
    local tip, worn = Tips.Get()
    worn:Hide()
    tip:SetOwner(self, "ANCHOR_RIGHT")
    tip:SetHyperlink(ns.Gear.ItemString(self.item))
    tip:Show()
  end)
  row:SetScript("OnLeave", Tips.Hide)
  return row
end

local function ItemIcon(itemID)
  local get = (C_Item and rawget(C_Item, "GetItemIconByID")) or rawget(_G, "GetItemIconByID") or rawget(_G, "GetItemIcon")
  return get and ns.Try(get, itemID) or nil
end

-- the height of a text wrapped to width
local function TextHeight(text, width)
  text:SetWidth(width)
  local h = text:GetStringHeight()
  return type(h) == "number" and h > 0 and math.ceil(h) or 12
end

local function Build()
  local L = ns.L
  page = CreateFrame("Frame", nil, UI.Content())
  UI.ItemTips.Get()
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
  -- the model area: the character (below); wherever the game cannot show the member in their race and
  -- sex, the race portrait
  hero.ModelArea = CreateFrame("Frame", nil, hero)
  hero.ModelArea:SetPoint("TOPLEFT", MODEL_INSET, -MODEL_INSET)
  hero.ModelArea:SetPoint("TOPRIGHT", -MODEL_INSET, -MODEL_INSET)
  hero.ModelArea:SetHeight(200)
  page.ModelArea = hero.ModelArea
  -- the race's dressing room art behind the model (Game/Gear.lua), up to four pieces, the bottom shaded
  hero.BgPieces = {}
  for i = 1, 4 do
    hero.BgPieces[i] = hero.ModelArea:CreateTexture(nil, "BACKGROUND", nil, 0)
    hero.BgPieces[i]:Hide()
  end
  hero.BgShade = hero.ModelArea:CreateTexture(nil, "BACKGROUND", nil, 1)
  hero.BgShade:SetPoint("BOTTOMLEFT")
  hero.BgShade:SetPoint("BOTTOMRIGHT")
  hero.BgShade:SetHeight(48)
  hero.BgShade:SetColorTexture(1, 1, 1, 1)
  local color = rawget(_G, "CreateColor")
  if not (color and pcall(hero.BgShade.SetGradient, hero.BgShade, "VERTICAL", color(0, 0, 0, 0.7), color(0, 0, 0, 0))) then
    if not pcall(hero.BgShade.SetGradientAlpha, hero.BgShade, "VERTICAL", 0, 0, 0, 0.7, 0, 0, 0, 0) then
      hero.BgShade:SetColorTexture(0, 0, 0, 0.35)
    end
  end
  hero.BgShade:Hide()
  hero.Background = {}
  hero.Portrait = Portrait(hero.ModelArea, 104)
  hero.Portrait:SetPoint("CENTER", 0, 0)
  -- the character in its gear, a model scene with the game's player actor (Game/Gear.lua): drag turns the
  -- actor, the wheel brings the camera closer. Without the template the page keeps the portrait.
  local okScene, model = pcall(CreateFrame, "ModelScene", nil, hero.ModelArea, "ModelSceneMixinTemplate")
  if not okScene or type(model) ~= "table" or type(model.TransitionToModelSceneID) ~= "function"
    or type(model.GetPlayerActor) ~= "function" then
    model = nil
  end
  page.Model = model
  -- the drag and zoom hint: small, at the model area's bottom edge over its shade, only while the mouse
  -- is over the model
  hero.HintLayer = CreateFrame("Frame", nil, hero.ModelArea)
  hero.HintLayer:SetAllPoints()
  hero.HintLayer:SetFrameLevel((model and model:GetFrameLevel() or hero.ModelArea:GetFrameLevel()) + 2)
  hero.ModelHint = W.Text(hero.HintLayer, "GameFontHighlightSmall", L.MODEL_HINT)
  hero.ModelHint:SetTextColor(0.82, 0.8, 0.74)
  hero.ModelHint:SetPoint("BOTTOM", 0, 6)
  hero.ModelHint:Hide()
  -- while the portrait stands in for want of a body of the member's sex: when the figure comes, small and
  -- grey at the same place
  hero.WaitHint = W.Text(hero.HintLayer, "GameFontDisableSmall", "")
  hero.WaitHint:SetPoint("BOTTOMLEFT", 8, 6)
  hero.WaitHint:SetPoint("BOTTOMRIGHT", -8, 6)
  hero.WaitHint:SetJustifyH("CENTER")
  hero.WaitHint:Hide()
  -- drag turns the actor of a scene, the wheel brings its camera closer, the hint while the mouse is over
  -- it: on the page's own scene and on every pooled scene the page borrows (Game/ModelPool.lua)
  local function Equip(scene)
    if scene.guildyEquipped then return end
    scene.guildyEquipped = true
    scene.zoom, scene.yaw = 0, 0
    scene:SetScript("OnMouseWheel", function(self, delta)
      self.zoom = math.max(0, math.min(MODEL_ZOOM, math.floor((self.zoom + delta * 0.1) * 10 + 0.5) / 10))
      self:ApplyView()
    end)
    scene:SetScript("OnMouseDown", function(self, button)
      if button ~= "LeftButton" or not self.actor then return end
      self.dragX, self.dragYaw = GetCursorPosition(), ns.Try(self.actor.GetYaw, self.actor) or 0
    end)
    scene:SetScript("OnMouseUp", function(self) self.dragX = nil end)
    scene:HookScript("OnHide", function(self) self.dragX = nil end)
    -- hooked: the template's own OnUpdate moves the camera
    scene:HookScript("OnUpdate", function(self)
      if not (self.dragX and self.actor) then return end
      self.yaw = self.dragYaw + (GetCursorPosition() - self.dragX) * 0.01
      pcall(self.actor.SetYaw, self.actor, self.yaw)
    end)
    -- the turn and zoom of the viewer on the actor and the camera (again after each scene transition)
    function scene:ApplyView()
      if self.actor then pcall(self.actor.SetYaw, self.actor, self.yaw) end
      local camera = type(self.GetActiveCamera) == "function" and ns.Try(self.GetActiveCamera, self)
      if type(camera) == "table" and self.distance and type(camera.SetZoomDistance) == "function" then
        pcall(camera.SetZoomDistance, camera, self.distance * (1 - self.zoom))
      end
    end
    scene:HookScript("OnEnter", function(self)
      self.hovered = true
      hero.ModelHint:SetShown(self:IsShown())
    end)
    scene:HookScript("OnLeave", function(self)
      self.hovered = nil
      hero.ModelHint:Hide()
    end)
  end
  if model then
    model:SetAllPoints()
    model:EnableMouse(true)
    model:EnableMouseWheel(true)
    model:Hide()
    Equip(model)
  end
  -- a gold frame around the picture, as Blizzard frames its portraits: the picture sits in the card
  -- instead of running into its edge
  hero.ModelFrame = CreateFrame("Frame", nil, hero, BackdropTemplateMixin and "BackdropTemplate" or nil)
  hero.ModelFrame:SetPoint("TOPLEFT", hero.ModelArea, "TOPLEFT", -FRAME_OUTSET, FRAME_OUTSET)
  hero.ModelFrame:SetPoint("BOTTOMRIGHT", hero.ModelArea, "BOTTOMRIGHT", FRAME_OUTSET, -FRAME_OUTSET)
  if hero.ModelFrame.SetBackdrop then
    hero.ModelFrame:SetBackdrop({ edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 12 })
    hero.ModelFrame:SetBackdropBorderColor(W.GOLD[1], W.GOLD[2], W.GOLD[3], 1)
  end
  hero.ModelFrame:SetFrameLevel(hero.HintLayer:GetFrameLevel() + 1)
  hero.ModelFrame:Show()
  hero.LevelRing = CreateFrame("Frame", nil, hero)
  hero.LevelRing:SetSize(34, 34)
  hero.LevelRing:SetPoint("TOPRIGHT", hero.ModelArea, "TOPRIGHT", -8, -8)
  hero.LevelRing:SetFrameLevel(hero.ModelFrame:GetFrameLevel() + 1)
  Disc(hero.LevelRing, "BACKGROUND", 1, 0, W.GOLD[1], W.GOLD[2], W.GOLD[3])
  Disc(hero.LevelRing, "BACKGROUND", 2, 2, 0.07, 0.06, 0.04)
  hero.Level = W.Text(hero.LevelRing, "GameFontNormal")
  hero.Level:SetPoint("CENTER", 0, 0)
  -- identity on the card's centre axis: name, Hall of Fame title, race and class, rank and zone
  hero.Name = W.Text(hero, "GameFontNormalHuge")
  hero.Name:SetWordWrap(false)
  hero.Title = W.Text(hero, "GameFontNormal")
  hero.Title:SetWordWrap(false)
  hero.Ident = W.Text(hero, "GameFontHighlightSmall") -- long race names wrap inside the card
  hero.Ident:SetSpacing(2)
  hero.Where = W.Text(hero, "GameFontHighlightSmall")
  hero.Where:SetSpacing(2)
  hero.Divider = hero:CreateTexture(nil, "ARTWORK")
  hero.Divider:SetHeight(1)
  hero.Divider:SetColorTexture(W.GOLD[1], W.GOLD[2], W.GOLD[3], 0.35)
  -- facts: label left in muted gold, value right in white
  hero.Facts = {}
  for _, key in ipairs(FACTS) do
    local row = CreateFrame("Frame", nil, hero)
    row.Label = W.Text(row, "GameFontNormalSmall")
    row.Label:SetTextColor(W.GOLD[1], W.GOLD[2], W.GOLD[3])
    row.Label:SetPoint("TOPLEFT", 0, 0)
    row.Label:SetWordWrap(false)
    row.Value = W.Text(row, "GameFontHighlightSmall")
    row.Value:SetPoint("TOPRIGHT", 0, 0)
    row.Value:SetJustifyH("RIGHT")
    row.Value:SetSpacing(1)
    if row.Value.SetMaxLines then row.Value:SetMaxLines(2) end
    row:Hide()
    hero.Facts[key] = row
  end
  -- notes: a small heading, the text under it, at most NOTE_LINES lines
  hero.NoteBlocks = {}
  for key, title in pairs({ note = L.NOTE, officer = L.OFFICER_NOTE }) do
    local block = CreateFrame("Frame", nil, hero)
    block.Heading = W.Text(block, "GameFontNormalSmall", title)
    block.Heading:SetTextColor(W.GOLD[1], W.GOLD[2], W.GOLD[3])
    block.Heading:SetPoint("TOPLEFT", 0, 0)
    block.Text = W.Text(block, "GameFontHighlightSmall")
    block.Text:SetSpacing(1)
    block:Hide()
    hero.NoteBlocks[key] = block
  end
  hero.Whisper = W.Button(hero, L.WHISPER, function() if page.member then UI.Whisper(page.member.fullName) end end, 110)
  hero.Invite = W.Button(hero, L.GROUP_INVITE_SHORT, function() if page.member then ns.Roster.GroupInvite(page.member) end end, 110)

  -- officer row under a hairline: removal (rank and notes are in Blizzard's own member panel beside the
  -- page, UI/Notes.lua)
  hero.OfficerRule = hero:CreateTexture(nil, "ARTWORK")
  hero.OfficerRule:SetHeight(1)
  hero.OfficerRule:SetColorTexture(W.GOLD[1], W.GOLD[2], W.GOLD[3], 0.25)
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
  -- the activity score: how it is made in a panel under the tile (Core/Activity.lua keeps what fed it)
  local scoreTile = page.Tiles.score
  scoreTile:EnableMouse(true)
  scoreTile:SetScript("OnEnter", function(self) page:ShowScorePanel(self) end)
  scoreTile:SetScript("OnLeave", function() UI.ScorePanel.Hide() end)
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
  -- no gear known yet: one message in the middle of the box instead of bare slot names
  gear.Empty = W.Text(gear, "GameFontNormal", L.GEAR_EMPTY)
  gear.Empty:SetPoint("CENTER", 0, 12)
  gear.Empty:SetJustifyH("CENTER")
  gear.EmptyHint = W.Text(gear, "GameFontDisableSmall", L.GEAR_EMPTY_HINT)
  gear.EmptyHint:SetPoint("TOP", gear.Empty, "BOTTOM", 0, -8)
  gear.EmptyHint:SetJustifyH("CENTER")
  gear.EmptyHint:SetSpacing(2)

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
  -- what the pieces are rated for, small and grey in the heading line: the talent spec, or the worn gear
  upgrades.Basis = W.Text(upgrades, "GameFontDisableSmall")
  upgrades.Basis:SetPoint("TOPLEFT", upgrades.Title, "TOPRIGHT", 8, -2)
  upgrades.Basis:SetJustifyH("LEFT")
  upgrades.Basis:SetWordWrap(false)
  upgrades.want = 56
  upgrades.Rows = {}
  -- the item's tooltip, under it how its stats differ from the worn piece's; beside it the member's
  -- piece of the slot the comparison used
  local function ItemTooltip(self)
    local row = self:GetParent()
    local itemID = row.itemID
    if not itemID then return end
    local tip, worn = UI.ItemTips.Get()
    tip:SetOwner(self, "ANCHOR_RIGHT")
    tip:SetHyperlink("item:" .. itemID)
    local text = ns.Upgrades.DiffText(row.diff, ns.GameGear.StatName)
    if text then
      tip:AddLine(" ")
      tip:AddLine(L.UPGRADE_COMPARE, W.GOLD[1], W.GOLD[2], W.GOLD[3])
      tip:AddLine(text, 1, 1, 1, true)
    end
    tip:Show()
    local m = page.member
    UI.ItemTips.Worn(worn, tip, m and m.name, row.worn)
  end
  -- a block per piece: the icon in its quality border, the item name over slot and makers, the gain
  -- big at the right over the levels it is made of
  for i = 1, ns.Upgrades.MAX_ROWS do
    local row = CreateFrame("Frame", nil, upgrades)
    row:SetHeight(UPGRADE_H)
    row:SetPoint("TOPLEFT", 12, -UPGRADE_TOP - (i - 1) * UPGRADE_H)
    row:SetPoint("RIGHT", -12, 0)
    if i > 1 then
      row.Rule = row:CreateTexture(nil, "BORDER")
      row.Rule:SetHeight(1)
      row.Rule:SetPoint("TOPLEFT", 0, 0)
      row.Rule:SetPoint("TOPRIGHT", 0, 0)
      row.Rule:SetColorTexture(W.GOLD[1], W.GOLD[2], W.GOLD[3], 0.18)
    end
    row.Item = CreateFrame("Button", nil, row)
    row.Item:SetSize(UPGRADE_ICON, UPGRADE_ICON)
    row.Item:SetPoint("LEFT", 0, 0)
    row.Item:SetScript("OnEnter", ItemTooltip)
    row.Item:SetScript("OnLeave", UI.ItemTips.Hide)
    row.Border = row.Item:CreateTexture(nil, "BACKGROUND")
    row.Border:SetAllPoints()
    row.Icon = row.Item:CreateTexture(nil, "ARTWORK")
    row.Icon:SetPoint("TOPLEFT", 1, -1)
    row.Icon:SetPoint("BOTTOMRIGHT", -1, 1)
    row.Icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    row.Gain = W.Text(row, "GameFontNormalLarge")
    row.Gain:SetPoint("TOPRIGHT", 0, -5)
    row.Gain:SetJustifyH("RIGHT")
    row.Gain:SetTextColor(0.3, 0.9, 0.3)
    row.GainSub = W.Text(row, "GameFontDisableSmall")
    row.GainSub:SetPoint("TOPRIGHT", 0, -25)
    row.GainSub:SetJustifyH("RIGHT")
    row.GainSub:SetWordWrap(false)
    row.Name = W.Text(row, "GameFontHighlightSmall")
    row.Name:SetPoint("TOPLEFT", UPGRADE_ICON + 8, -8)
    row.Name:SetWordWrap(false)
    row.NameHit = CreateFrame("Button", nil, row)
    row.NameHit:SetAllPoints(row.Name)
    row.NameHit:SetScript("OnEnter", ItemTooltip)
    row.NameHit:SetScript("OnLeave", UI.ItemTips.Hide)
    -- "Slot · von", the makers' names (a click whispers them), "(Beruf) · online"
    row.Sub = W.Text(row, "GameFontDisableSmall")
    row.Sub:SetWordWrap(false)
    row.Makers = {}
    for j = 1, 2 do
      local maker = CreateFrame("Button", nil, row)
      maker:SetHeight(14)
      maker.Name = W.Text(maker, "GameFontHighlightSmall")
      maker.Name:SetPoint("LEFT", 0, 0)
      maker.Name:SetWordWrap(false)
      maker.Info = W.Text(maker, "GameFontDisableSmall") -- the comma after the first of two
      maker.Info:SetPoint("LEFT", maker.Name, "RIGHT", 0, 0)
      maker:SetScript("OnClick", function(self) if self.member then UI.Whisper(self.member.fullName) end end)
      maker:SetScript("OnEnter", function(self) if self.member then UI.MemberTooltip(self, self.member) end end)
      maker:SetScript("OnLeave", function() GameTooltip:Hide() end)
      row.Makers[j] = maker
    end
    row.Info = W.Text(row, "GameFontDisableSmall")
    row.Info:SetWordWrap(false)
    upgrades.Rows[i] = row
  end

  local profs = Section(right, L.PROFESSIONS)
  page.Profs = profs
  profs.Rows = {}
  for i = 1, PROF_ROWS do
    local row = CreateFrame("Frame", nil, profs)
    row:SetHeight(PROF_H)
    row:SetPoint("TOPLEFT", 12, -28 - (i - 1) * PROF_H)
    row:SetPoint("RIGHT", -12, 0)
    row.Icon = row:CreateTexture(nil, "ARTWORK")
    row.Icon:SetSize(14, 14)
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
    row.Bar:SetHeight(4)
    row.Bar:SetPoint("LEFT", row.Level, "RIGHT", 8, 0)
    profs.Rows[i] = row
  end
  profs.Empty = W.Text(profs, "GameFontDisableSmall", L.NO_PROFESSIONS)
  profs.Empty:SetPoint("TOPLEFT", 12, -31)

  -- render -----------------------------------------------------------------------------------------
  function page:RenderHero(m)
    local can = ns.Roster.Can()
    local info = hero.Portrait:SetMember(m)
    local SEP = ns.L.SEP
    local inner = HERO_WIDTH - 24
    hero.Level:SetText(m.level or "")
    hero.Name:SetText(W.ClassName(m.name, m.classFile))
    local title = FirstTitle(m.key)
    hero.Title:SetText(title and ("„" .. title .. "“") or "")
    local ident = {}
    if info and info.race then ident[#ident + 1] = info.race end
    if info then ident[#ident + 1] = info.female and L.FEMALE or L.MALE end
    ident[#ident + 1] = m.className or ""
    local icon = info and info.icon and ("|T" .. info.icon .. ":14:14:0:0:64:64:5:59:5:59|t ") or ClassIconString(m.classFile, 14)
    hero.Ident:SetText(icon .. table.concat(ident, SEP))
    -- rank in gold, zone in grey, "online" in green; offline says nothing here (the facts tell when)
    local where = {}
    if m.rank and m.rank ~= "" then where[#where + 1] = "|cffffd100" .. m.rank .. "|r" end
    if m.zone and m.zone ~= "" then where[#where + 1] = "|cff9d9d9d" .. m.zone .. "|r" end
    if m.online then where[#where + 1] = "|cff4ce64c" .. L.ONLINE .. "|r" end
    hero.Where:SetText(table.concat(where, "|cff9d9d9d" .. SEP .. "|r"))

    -- facts, each only with a value
    local values = {
      since = ns.Roster.TenureText(m, true),
      last = not m.online and ns.Roster.LastOnlineText(m) or nil,
      guildy = UI.GuildyVersionText and UI.GuildyVersionText(m) or nil,
    }
    local labels = { since = L.MEMBER_SINCE, last = L.LAST_ONLINE, guildy = L.COL_GUILDY }
    local labelW = 0
    for _, key in ipairs(FACTS) do
      local row = hero.Facts[key]
      row.Label:SetText(labels[key])
      row.Value:SetText(values[key] or "")
      if values[key] then labelW = math.max(labelW, TextWidth(row.Label)) end
    end
    labelW = math.min(110, math.ceil(labelW) + 2)
    local notes = {
      note = m.note ~= nil and m.note ~= "" and m.note or nil,
      officer = can.viewOfficer and m.officerNote ~= nil and m.officerNote ~= "" and m.officerNote or nil,
    }
    for key, block in pairs(hero.NoteBlocks) do block.Text:SetText(notes[key] or "") end

    -- the bottom: whisper and invite, under them the officer row behind a hairline
    local officer = can.remove
    local bottomH = officer and 64 or 32
    hero.OfficerLabel:SetShown(officer)
    hero.OfficerRule:SetShown(officer)
    hero.Remove:SetShown(officer)
    hero.Remove:SetEnabled(ns.Roster.Rights(m).remove or false)
    local y = 10
    if officer then
      hero.Remove:ClearAllPoints()
      hero.Remove:SetPoint("BOTTOMRIGHT", hero, "BOTTOMRIGHT", -12, 8)
      hero.OfficerLabel:ClearAllPoints()
      hero.OfficerLabel:SetPoint("BOTTOMLEFT", hero, "BOTTOMLEFT", 14, 14)
      hero.OfficerRule:ClearAllPoints()
      hero.OfficerRule:SetPoint("BOTTOMLEFT", hero, "BOTTOMLEFT", 12, 36)
      hero.OfficerRule:SetWidth(inner)
      y = 42
    end
    hero.Whisper:ClearAllPoints()
    hero.Whisper:SetPoint("BOTTOMRIGHT", hero, "BOTTOM", -3, y)
    hero.Invite:ClearAllPoints()
    hero.Invite:SetPoint("BOTTOMLEFT", hero, "BOTTOM", 3, y)
    hero.Whisper:SetEnabled(m.online or false)
    hero.Invite:SetEnabled(m.online or false)

    -- heights of what goes under the model; the notes give up lines before the model gets small
    local cardH = hero:GetHeight() or 0
    local function Measure(lines)
      local h = {}
      h.name = TextHeight(hero.Name, inner)
      h.title = title and TextHeight(hero.Title, inner) or 0
      h.ident = TextHeight(hero.Ident, inner)
      h.where = #where > 0 and TextHeight(hero.Where, inner) or 0
      local total = FRAME_OUTSET + NAME_GAP + h.name + (title and 2 + h.title or 0) + 4 + h.ident + (#where > 0 and 3 + h.where or 0)
      total = total + 10 + 1 + 10 -- the divider
      local facts = 0
      for _, key in ipairs(FACTS) do
        if values[key] then
          local row = hero.Facts[key]
          local line = TextHeight(row.Label, labelW)
          h[key] = math.max(line, math.min(TextHeight(row.Value, inner - labelW - 10), 2 * line + 1))
          facts = facts + (facts > 0 and 4 or 0) + h[key]
        end
      end
      total = total + facts
      local blocks = 0
      for _, key in ipairs({ "note", "officer" }) do
        if notes[key] then
          local block = hero.NoteBlocks[key]
          local line = TextHeight(block.Heading, inner)
          h[key] = math.min(TextHeight(block.Text, inner), lines * (line + 1))
          blocks = blocks + (blocks > 0 and 8 or 0) + line + 2 + h[key]
        end
      end
      if blocks > 0 then total = total + (facts > 0 and 12 or 0) + blocks end
      return total, h
    end
    local lines, contentH, h = NOTE_LINES
    repeat
      contentH, h = Measure(lines)
      lines = lines - 1
    until lines < 1 or cardH - MODEL_INSET - bottomH - CONTENT_GAP - contentH >= MODEL_MIN
    local modelH = math.max(MODEL_MIN, math.min(math.floor(cardH * MODEL_SHARE) - MODEL_INSET,
      cardH - MODEL_INSET - bottomH - CONTENT_GAP - contentH))
    hero.ModelArea:SetHeight(modelH)

    -- placed top-down: identity centred, the divider, facts, notes. The name hangs under the gold
    -- frame's outer bottom edge with air between them; the lines below count from the card's top.
    local nameTop = MODEL_INSET + modelH + FRAME_OUTSET + NAME_GAP
    local top = nameTop
    local function Centre(text, height)
      text:SetJustifyH("CENTER")
      text:SetWidth(inner)
      text:ClearAllPoints()
      text:SetPoint("TOP", hero, "TOP", 0, -top)
      top = top + height
    end
    Centre(hero.Name, h.name)
    hero.Name:ClearAllPoints()
    hero.Name:SetPoint("TOP", hero.ModelFrame, "BOTTOM", 0, -NAME_GAP)
    hero.Title:SetShown(title ~= nil)
    if title then
      top = top + 2
      Centre(hero.Title, h.title)
    end
    top = top + 4
    Centre(hero.Ident, h.ident)
    hero.Where:SetShown(#where > 0)
    if #where > 0 then
      top = top + 3
      Centre(hero.Where, h.where)
    end
    top = top + 10
    hero.Divider:ClearAllPoints()
    hero.Divider:SetPoint("TOPLEFT", hero, "TOPLEFT", 24, -top)
    hero.Divider:SetWidth(HERO_WIDTH - 48)
    top = top + 11
    local facts = 0
    for _, key in ipairs(FACTS) do
      local row = hero.Facts[key]
      row:SetShown(values[key] ~= nil)
      if values[key] then
        if facts > 0 then top = top + 4 end
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", hero, "TOPLEFT", 12, -top)
        row:SetSize(inner, h[key])
        row.Label:SetWidth(labelW)
        row.Value:SetWidth(inner - labelW - 10)
        row.Value:SetHeight(h[key])
        top = top + h[key]
        facts = facts + 1
      end
    end
    local blocks = 0
    for _, key in ipairs({ "note", "officer" }) do
      local block = hero.NoteBlocks[key]
      block:SetShown(notes[key] ~= nil)
      if notes[key] then
        top = top + (blocks > 0 and 8 or (facts > 0 and 12 or 0))
        local line = TextHeight(block.Heading, inner)
        block.Text:ClearAllPoints()
        block.Text:SetPoint("TOPLEFT", block.Heading, "BOTTOMLEFT", 0, -2)
        block.Text:SetWidth(inner)
        block.Text:SetHeight(h[key]) -- cut with an ellipsis after the last line that fits
        if block.Text.SetMaxLines then block.Text:SetMaxLines(lines + 1) end
        block:ClearAllPoints()
        block:SetPoint("TOPLEFT", hero, "TOPLEFT", 12, -top)
        block:SetSize(inner, line + 2 + h[key])
        top = top + line + 2 + h[key]
        blocks = blocks + 1
      end
    end
    hero.layout = { model = modelH, name = nameTop, content = top, buttons = cardH - bottomH }
    UI.Notes.Show(m)
  end

  -- the model where the game can show the member in their race and sex, else the portrait (never the
  -- viewer's own body with someone else's race or sex)
  -- The scene in the model area: a pooled body the page borrowed, else its own scene. hint: the line in
  -- the picture while the portrait stands in.
  local function Scene() return page.borrowed and page.borrowed.scene or model end
  local function ShowModel(shown, hint)
    local borrowed = page.borrowed and page.borrowed.scene
    if model then
      model:SetShown(shown and not borrowed)
      model:SetAlpha(1)
    end
    if borrowed then
      borrowed:SetShown(shown)
      borrowed:SetAlpha(1)
    end
    local scene = Scene()
    hero.Portrait:SetShown(not shown)
    hero.ModelHint:SetShown(shown and scene ~= nil and scene.hovered == true)
    hero.WaitHint:SetText(hint or "")
    hero.WaitHint:SetShown(not shown and hint ~= nil)
  end

  -- The pooled body on the page goes back to the pool (Game/ModelPool.lua), unseen, its body kept
  local function GiveBack()
    local body = page.borrowed
    if not body then return end
    page.borrowed = nil
    body.scene.hovered, body.scene.dragX = nil, nil
    ns.ModelPool.Give(body)
  end

  -- The page borrows pooled body for member key: its scene fills the model area in the place of the own
  local function Borrow(body, key)
    if page.borrowed ~= body then
      GiveBack()
      page.borrowed = body
      local scene = body.scene
      Equip(scene)
      scene:SetParent(hero.ModelArea)
      scene:ClearAllPoints()
      scene:SetAllPoints(hero.ModelArea)
      scene:SetFrameLevel(model and model:GetFrameLevel() or hero.ModelArea:GetFrameLevel() + 1)
      scene:EnableMouse(true)
      scene:EnableMouseWheel(true)
      scene.actor, scene.distance = body.actor, body.distance
      scene.zoom, scene.yaw, scene.member = 0, 0, nil
    end
    if body.scene.member ~= key then
      body.scene.zoom, body.scene.yaw, body.scene.member = 0, 0, key
    end
    ns.ModelPool.Take(body, key)
  end

  -- The line in the picture for member m on route "wait": by their sex, only with stored items (without,
  -- the gear box explains)
  local function WaitHint(m, route)
    if route.kind ~= "wait" then return nil end
    local guild = ns.GuildData()
    local rec = guild and type(guild.gear) == "table" and guild.gear[m.key]
    if type(rec) ~= "table" or type(rec.items) ~= "table" or next(rec.items) == nil then return nil end
    return route.sex == 3 and L.MODEL_WAIT_FEMALE or L.MODEL_WAIT_MALE
  end

  -- true when the model shows member m's body already, in whatever gear: it stays while no player of
  -- their sex is around (a dressed body needs no donor afterwards, checked in game)
  local function ShowsBodyOf(m, route)
    local body, scene = page.modelBody, Scene()
    return scene ~= nil and scene:IsShown() and body ~= nil and body.key == m.key
      and (body.race == nil or (body.race == route.race and body.sex == route.sex))
  end

  -- Shows member m (routes in Game/Gear.lua). Loaded again only when GameGear.ModelKey changes: the
  -- member, the route or their gear.
  function page:RenderModel(m)
    local route = ns.GameGear.ModelRoute(m)
    self.modelWaiting = route.kind == "wait"
    if route.kind == "wait" then ns.ModelPool.Prefer(route.race, route.sex) else ns.ModelPool.Prefer(nil) end
    if route.kind == "wait" and ShowsBodyOf(m, route) then return end -- new gear waits for a donor
    local key = ns.GameGear.ModelKey(m, route)
    if key == self.modelKey then return end
    self.modelKey = key
    local token = {}
    self.modelDress = token -- a newer dressing ends a pending one
    if route.kind == "pool" and model then
      -- a body the pool built earlier: borrowed into the model area and dressed in the stored items,
      -- once it had its moment to load
      local body = route.body
      Borrow(body, m.key)
      self.modelFor = m.key
      body.scene:ApplyView()
      local function Dress()
        if page.modelDress ~= token or page.borrowed ~= body then return end
        ns.SafeCall(ns.GameGear.DressStored, body.actor, m)
        page.modelBody = { key = m.key, race = route.race, sex = route.sex }
        ShowModel(true)
      end
      if body.ready then return Dress() end
      -- a body built a moment ago: unseen until dressed
      model:Hide()
      body.scene:SetAlpha(0)
      body.scene:Show()
      C_Timer.After(MODEL_DRESS_AFTER, Dress)
      return
    end
    GiveBack()
    if not model or route.kind == "wait" or route.kind == "none" then
      self.modelBody = nil
      ShowModel(false, WaitHint(m, route))
      return
    end
    if self.modelFor ~= m.key then
      model.zoom, model.yaw = 0, 0
      self.modelFor = m.key
    end
    pcall(model.TransitionToModelSceneID, model, MODEL_SCENE, 1, 1, true)
    local actor = ns.Try(model.GetPlayerActor, model)
    model.actor = type(actor) == "table" and actor or nil
    local camera = type(model.GetActiveCamera) == "function" and ns.Try(model.GetActiveCamera, model)
    local distance = type(camera) == "table" and ns.Try(camera.GetZoomDistance, camera)
    model.distance = type(distance) == "number" and not ns.IsSecret(distance) and distance or nil
    if not (model.actor and ns.GameGear.LoadModel(model.actor, route)) then
      self.modelBody = nil
      ShowModel(false)
      return
    end
    model:ApplyView()
    if route.kind ~= "donor" then
      self.modelBody = { key = m.key }
      ShowModel(true)
      return
    end
    -- the donor's body takes the stored items a moment later; until then a hidden model stays unseen
    if not model:IsShown() then
      model:SetAlpha(0)
      model:Show()
    end
    C_Timer.After(MODEL_DRESS_AFTER, function()
      if page.modelDress ~= token then return end
      ns.SafeCall(ns.GameGear.DressStored, actor, m)
      page.modelBody = { key = m.key, race = route.race, sex = route.sex }
      ShowModel(true)
    end)
  end

  -- the classic art's four tiles: x, y, width, height in its 320x384 picture
  local TILES = { { 0, 0, 256, 256 }, { 256, 0, 64, 256 }, { 0, 256, 256, 128 }, { 256, 256, 64, 128 } }

  -- The picture behind the model of member m (Game/Gear.lua), scaled to fill the model area with its
  -- shape kept: what sticks out is cut off through the texture coordinates
  function page:RenderBackground(m)
    local area = hero.ModelArea
    local guild = ns.GuildData()
    local rec = guild and type(guild.gear) == "table" and guild.gear[m.key]
    local info = RaceInfo(m)
    local raceFile = info and info.file or (type(rec) == "table" and ns.GameGear.RACE_FILES[rec.race]) or nil
    local w, h = area:GetWidth() or 0, area:GetHeight() or 0
    local key = ("%s:%s:%s:%s"):format(tostring(raceFile), tostring(m.classFile), w, h)
    if key == self.bgKey then return end
    self.bgKey = key
    local bg = ns.GameGear.ModelBackground(raceFile, m.classFile, hero.BgPieces[1])
    hero.Background = bg or {}
    local pieces, picW, picH = {}, 0, 0
    if bg and bg.info then
      local a = bg.info
      local file = a.file or a.filename
      if file and type(a.width) == "number" and type(a.height) == "number" and a.width > 0 and a.height > 0 then
        picW, picH = a.width, a.height
        pieces[1] = { file = file, x = 0, y = 0, w = picW, h = picH, l = a.leftTexCoord or 0, r = a.rightTexCoord or 1,
          t = a.topTexCoord or 0, b = a.bottomTexCoord or 1 }
      end
    elseif bg then
      -- the art fades to black in its lowest 64 rows (made for the old dressing room's bottom bar): only
      -- the 320 rows above count as the picture, so no dark band sits under the model
      picW, picH = 320, 320
      for i, tile in ipairs(TILES) do
        pieces[i] = { file = bg.path .. i, x = tile[1], y = tile[2], w = tile[3], h = tile[4], l = 0, r = 1, t = 0, b = 1 }
      end
    end
    local s = picW > 0 and w > 0 and h > 0 and math.max(w / picW, h / picH)
    local vw, vh = s and w / s or 0, s and h / s or 0
    local vx, vy = (picW - vw) / 2, (picH - vh) / 2
    local any = false
    for i, texture in ipairs(hero.BgPieces) do
      local p = pieces[i]
      local x0, x1 = p and math.max(p.x, vx), p and math.min(p.x + p.w, vx + vw)
      local y0, y1 = p and math.max(p.y, vy), p and math.min(p.y + p.h, vy + vh)
      if not (s and p and x1 > x0 and y1 > y0) then
        texture:Hide()
      else
        texture:SetTexture(p.file)
        texture:ClearAllPoints()
        texture:SetPoint("TOPLEFT", area, "TOPLEFT", (x0 - vx) * s, -(y0 - vy) * s)
        texture:SetSize((x1 - x0) * s, (y1 - y0) * s)
        local function U(x) return p.l + (x - p.x) / p.w * (p.r - p.l) end
        local function V(y) return p.t + (y - p.y) / p.h * (p.b - p.t) end
        texture:SetTexCoord(U(x0), U(x1), V(y0), V(y1))
        texture:Show()
        any = true
      end
    end
    hero.BgShade:SetShown(any)
  end

  -- while the model waits for a player of the member's sex: looks again when one may have come in sight
  local watcher = CreateFrame("Frame")
  for _, event in ipairs({ "PLAYER_TARGET_CHANGED", "NAME_PLATE_UNIT_ADDED", "GROUP_ROSTER_UPDATE", "UPDATE_MOUSEOVER_UNIT" }) do
    watcher:RegisterEvent(event)
  end
  watcher:SetScript("OnEvent", function()
    if not page.modelWaiting or page.modelRetry or not page:IsShown() then return end
    page.modelRetry = true
    C_Timer.After(MODEL_RETRY_AFTER, function()
      page.modelRetry = nil
      local m = page.member and (ns.Roster.Find(page.member.key) or page.member)
      if m and page.modelWaiting and page:IsShown() then ns.SafeCall(page.RenderModel, page, m) end
    end)
  end)
  -- the pool built bodies (Game/ModelPool.lua): a waiting model may take one now
  ns.On("MODEL_POOL", function()
    local m = page.member and (ns.Roster.Find(page.member.key) or page.member)
    if m and page.modelWaiting and page:IsShown() then page:RenderModel(m) end
  end)

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

  function page:RenderStats(m)
    local S = ns.Stats
    local guild = ns.GuildData()
    local record = guild and guild.members[m.key]
    local rec = record and record.stats
    local t = self.Tiles
    local function Fill(tile, id)
      local value = S.Value(rec, id, "all", ns.Now(), ns.GameStats.Date)
      tile.Value:SetText(value and Number(value) or "–")
      local place, count = Place(m.key, id)
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
    place, count = Place(m.key, S.GEAR.ILVL)
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

  -- The shared score panel (UI/ScorePanel.lua) under the tile owner, for the shown member
  function page:ShowScorePanel(owner)
    self.ScorePanel = UI.ScorePanel.Show(owner, self.member and self.member.key)
  end

  -- The guild's ready mark for level (median average item level of the roster members of that level,
  -- tenths) and the highest stored item level (the bars' scale); kept until statistics, members or gear
  -- change
  local function GuildGear(level)
    local d = GuildData()
    if d.top and d.ready[level] ~= nil then return d.ready[level] or nil, d.top end
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
    local ready = ns.Gear.ReadyMark(list, level)
    d.ready[level], d.top = ready or false, top
    return ready, top
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
    -- the heading in one line: the title, the summary after it, the column label at the right over the
    -- bars, ending where they end; a summary too long for the room is cut, never wrapped
    local barsEnd = 12 + 28 + 8
    gear.Head:ClearAllPoints()
    gear.Head:SetPoint("TOPRIGHT", -barsEnd, -11)
    gear.Note:ClearAllPoints()
    gear.Note:SetPoint("TOPLEFT", gear.Title, "TOPRIGHT", 10, -2)
    gear.Note:SetJustifyH("LEFT")
    gear.Note:SetWordWrap(false)
    gear.Note:SetWidth(math.max(1, width - 12 - TextWidth(gear.Title) - 10 - 16 - TextWidth(gear.Head) - barsEnd))
    gear.Empty:SetShown(rec == nil)
    gear.EmptyHint:SetShown(rec == nil)
    gear.EmptyHint:SetWidth(math.max(120, math.min(360, width - 60)))
    gear.Head:SetShown(rec ~= nil)
    gear.Note:SetShown(rec ~= nil)
    gear.Foot:SetShown(rec ~= nil)
    if not rec then
      for _, row in ipairs(gear.Rows) do row:Hide() end
      gear.Note:SetText("")
      gear.Foot:SetText("")
      return nil
    end
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
        local name, gone = ItemName(item)
        if not name and not gone then self.waiting = true end
        row.Name:SetText(Hex(color) .. (name or "…") .. "|r")
        local enchant, enchantColor
        if item.e ~= 0 then
          local loading
          enchant, loading = ns.GameGear.EnchantText(item.id, item.e)
          enchantColor = ENCHANT_COLOR
          if loading then self.waiting = true end
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
    if rec.src == "self" then
      gear.Foot:SetText(L.GEAR_SELF_AGO:format(name, Span(ns.Now() - (rec.ts or 0))))
    elseif rec.src == "api" then
      gear.Foot:SetText(L.GEAR_API_AGO:format(Span(ns.Now() - (rec.ts or 0))))
    else
      gear.Foot:SetText(L.GEAR_SEEN_AGO:format(Span(ns.Now() - (rec.ts or 0))))
    end
    return rec
  end

  -- The line under an upgrade's name: "Slot · von A, B (Beruf) · online", never wider than width. The
  -- profession goes first when room is short, then the names are cut, then the slot; each maker's
  -- click target stays on their name.
  local function MakerLine(line, row, x0, width)
    local SEP = ns.L.SEP
    local makers = {}
    for j = 1, #line.Makers do
      local maker = row.makers[j]
      local other = maker and ns.Roster.Find(maker.key) -- (names made up for pictures by the roster)
      if other then makers[#makers + 1] = { maker = maker, member = other } end
    end
    -- one profession (one recipe: the makers share it as a rule), the state of the first online maker,
    -- else when the first was last online
    local prof = makers[1] and ns.TradeSkill.Name(makers[1].maker.skillLine)
    local state
    for _, entry in ipairs(makers) do
      if entry.maker.online and not state then state = "|cff4ce64c" .. L.ONLINE .. "|r" end
    end
    if not state and makers[1] then state = ns.Roster.LastOnlineText(makers[1].member) end
    line.Sub:SetText(SlotName(row.slot) .. SEP .. L.UPGRADE_BY .. " ")
    local names, nameW = 0, {}
    for j, button in ipairs(line.Makers) do
      local entry = makers[j]
      button.member = entry and entry.member or nil
      button:SetShown(entry ~= nil)
      if entry then
        button.Name:SetWidth(0)
        button.Name:SetText(entry.member.name)
        button.Info:SetText(j < #makers and ", " or "")
        nameW[j] = math.ceil(TextWidth(button.Name))
        names = names + nameW[j] + (j < #makers and math.ceil(TextWidth(button.Info)) or 0)
      end
    end
    local function Info(withProf)
      local text = (withProf and prof and (" (" .. prof .. ")") or "") .. (state and ("|cff9d9d9d" .. SEP .. "|r" .. state) or "")
      line.Info:SetText(text)
      return math.ceil(TextWidth(line.Info))
    end
    local subW = math.ceil(TextWidth(line.Sub))
    local infoW = Info(true)
    if subW + names + infoW > width then infoW = Info(false) end
    -- the names share what is left, each cut with an ellipsis; the slot gives way last
    local commas = 0
    for j, button in ipairs(line.Makers) do
      if makers[j] and j < #makers then commas = commas + math.ceil(TextWidth(button.Info)) end
    end
    local wantNames = names - commas
    local roomNames = width - subW - infoW - commas
    if roomNames < math.min(wantNames, 40 * #makers) then
      subW = math.max(0, width - infoW - commas - math.min(wantNames, 40 * #makers))
      roomNames = width - subW - infoW - commas
    end
    local scale = wantNames > 0 and math.min(1, math.max(0, roomNames) / wantNames) or 1
    line.Sub:ClearAllPoints()
    line.Sub:SetPoint("TOPLEFT", line, "TOPLEFT", x0, -24)
    line.Sub:SetWidth(math.max(1, subW))
    local x = x0 + subW
    for j, button in ipairs(line.Makers) do
      if makers[j] then
        local w = math.max(1, math.floor(nameW[j] * scale))
        button.Name:SetWidth(w)
        button:ClearAllPoints()
        button:SetPoint("TOPLEFT", line, "TOPLEFT", x, -23)
        button:SetWidth(w)
        x = x + w + (j < #makers and math.ceil(TextWidth(button.Info)) or 0)
      end
    end
    line.Info:ClearAllPoints()
    line.Info:SetPoint("TOPLEFT", line, "TOPLEFT", x, -24)
    line.Info:SetWidth(math.max(1, math.min(infoW, x0 + width - x)))
    line.lineStart, line.lineWidth = x0, width
  end

  -- The talent spec the upgrades were rated for, as the heading says it: the tree's name in the client's
  -- language where known (Game/Talents.lua), a feral druid with cat or bear; nil spec: by the worn gear
  local function RatedFor(classFile, spec, tree)
    if not spec then return L.UPGRADES_RATED_GEAR end
    local name = ns.GameTalents.TreeName(classFile, tree) or L.TALENT_TREE:format(tree or 0)
    if spec == "DRUID_CAT" then name = L.TALENT_CAT:format(name)
    elseif spec == "DRUID_BEAR" then name = L.TALENT_BEAR:format(name) end
    return L.UPGRADES_RATED_SPEC:format(name)
  end

  -- "Upgrades aus der Gilde": up to five better crafted pieces with their makers. Returns the height the
  -- box wants; LayoutColumn gives it the rest of the column and FitUpgrades drops what does not fit.
  function page:RenderUpgrades(m)
    local rows, state, missing, spec, tree = ns.GameGear.UpgradesFor(m)
    local guild = ns.GuildData()
    local rec = guild and type(guild.gear) == "table" and guild.gear[m.key] or nil
    local worn = type(rec) == "table" and type(rec.items) == "table" and rec.items or {}
    if missing and #missing > 0 then self.waiting = true end
    self.makers = rows
    local rowW = (upgrades:GetWidth() or 300) - 24
    for i, line in ipairs(upgrades.Rows) do
      local row = rows[i]
      if row then
        local color = QUALITY[row.quality or 1] or QUALITY[1]
        local info, gone = ns.GameGear.ItemInfo(row.itemID)
        if not info and not gone then self.waiting = true end
        line.itemID, line.diff, line.worn = row.itemID, row.diff, worn[row.slot]
        line.Icon:SetTexture(ItemIcon(row.itemID) or "Interface\\Icons\\INV_Misc_QuestionMark")
        line.Icon:Show()
        line.Border:SetColorTexture(color[1], color[2], color[3], 1)
        local have = row.have or 0
        -- the item level difference stays the big number; a better piece may also be of a lower level
        local levels = row.offer - have
        line.Gain:SetText(levels > 0 and ("+" .. levels) or levels < 0 and ("−" .. -levels) or "±0")
        line.GainSub:SetText(have > 0 and L.UPGRADE_GAIN:format(tostring(have), row.offer) or L.UPGRADE_EMPTY)
        local gainW = math.ceil(math.max(TextWidth(line.Gain), TextWidth(line.GainSub)))
        local x0 = UPGRADE_ICON + 8
        local width = math.max(40, rowW - x0 - 8 - gainW)
        line.Name:SetText(Hex(color) .. (info and info.name or "…") .. "|r")
        line.Name:SetWidth(width)
        MakerLine(line, row, x0, width)
        line:Show()
      else
        line.itemID, line.diff, line.worn = nil, nil, nil
        line:Hide()
      end
    end
    upgrades.count = state == "rows" and #rows or 0
    upgrades.Note:SetText(state == "rows" and L.UPGRADES_COUNT:format(#rows) or "")
    upgrades.Basis:SetText(state ~= "nodata" and RatedFor(m.classFile, spec, tree) or "")
    upgrades.Basis:SetWidth(math.max(1, (upgrades:GetWidth() or 300) - 12 - TextWidth(upgrades.Title) - 8
      - TextWidth(upgrades.Note) - 12 - 8))
    -- nothing better: said as praise of the gear, the own page with "your", others by name
    local none = m.key == ns.Names.Key(ns.PlayerName()) and L.UPGRADES_NONE_OWN or L.UPGRADES_NONE:format(m.name or "")
    upgrades.Empty:SetText(state == "none" and none or L.UPGRADES_NO_DATA)
    upgrades.Empty:SetShown(state ~= "rows")
    return state == "rows" and (UPGRADE_TOP + 6 + #rows * UPGRADE_H) or upgrades.want
  end

  -- the upgrade rows the box of height has room for
  function page:FitUpgrades(height)
    for i, line in ipairs(upgrades.Rows) do
      if i <= (upgrades.count or 0) then line:SetShown(UPGRADE_TOP + i * UPGRADE_H + 2 <= height) end
    end
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
        row.Bar:SetBarWidth(math.max(40, rowWidth - 14 - 6 - nameWidth - 4 - 56 - 8 - 8 - (atCap and (row.Trainer:GetStringWidth() or 40) or 0)))
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
    return 34 + math.max(1, math.min(#list, PROF_ROWS)) * PROF_H
  end

  -- sizes of everything from the page's own size (the smallest window is 1130 x 560: content 1108 x 518)
  function page:Layout()
    local pageW, pageH = self:GetWidth() or 0, self:GetHeight() or 0
    local bodyH = math.max(200, pageH - (W.BAR_H + 6))
    local rightW = math.max(400, pageW - HERO_WIDTH - W.GAP)
    hero:SetSize(HERO_WIDTH, bodyH) -- the model area's height follows from the card's content (RenderHero)
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

  -- the column: professions only as tall as their rows, family as many lines as remain after what the
  -- upgrades want, the upgrades take the rest
  function page:LayoutColumn(m, y, areaH, gearW, lap)
    lap = lap or ns.Perf.Lap()
    local upWant = self:RenderUpgrades(m)
    lap("character page:", "upgrades")
    local profsH = self:RenderProfs(m)
    lap("character page:", "professions")
    local free = areaH - upWant - profsH - 2 * W.GAP - 36
    local familyH = self:RenderFamily(m, math.floor(free / LINE_H))
    lap("character page:", "family")
    local upH = math.max(0, areaH - familyH - profsH - 2 * W.GAP)
    family:ClearAllPoints()
    family:SetPoint("TOPLEFT", right, "TOPLEFT", gearW + W.GAP, y)
    family:SetHeight(familyH)
    upgrades:ClearAllPoints()
    upgrades:SetPoint("TOPLEFT", family, "BOTTOMLEFT", 0, -W.GAP)
    upgrades:SetHeight(upH)
    self:FitUpgrades(upH)
    profs:ClearAllPoints()
    profs:SetPoint("TOPLEFT", upgrades, "BOTTOMLEFT", 0, -W.GAP)
    profs:SetHeight(profsH)
    lap("character page:", "column layout")
  end

  -- What the roster shows of member m and of the makers of their upgrades: the page draws again on a
  -- roster update only when this changed
  local function RosterSig(m)
    local parts = { m.name, m.level, m.online and 1 or 0, m.zone, m.rank, m.note, m.officerNote, m.className,
      m.classFile, m.daysOffline, m.joinedDay, m.joinedExact and 1 or 0, m.guid, m.isMobile and 1 or 0 }
    for i = 1, 14 do parts[i] = tostring(parts[i]) end
    for _, row in ipairs(page.makers or {}) do
      for _, maker in ipairs(row.makers) do
        local other = ns.Roster.Find(maker.key)
        parts[#parts + 1] = maker.key .. (other and other.online and "+" or "-")
      end
    end
    return table.concat(parts, "\031")
  end

  -- Each part is measured on its own while /guildy perf runs ("character page: hero (first title)" ...)
  function page:Render()
    local lap = ns.Perf.Lap()
    local m = self.member and ns.Roster.Find(self.member.key) or self.member
    self.member = m
    self.dirty = false
    if not m then return end
    self.waiting = false
    local y, areaH, gearW = self:Layout()
    lap("character page:", "layout")
    self:RenderHero(m)
    lap("character page:", "hero (first title)")
    self:RenderModel(m)
    lap("character page:", "model")
    self:RenderBackground(m)
    lap("character page:", "background")
    self:RenderStats(m)
    lap("character page:", "stats tiles (places)")
    self:RenderScore(m)
    lap("character page:", "score")
    self:RenderGear(m)
    lap("character page:", "gear rows (enchant texts)")
    self:LayoutColumn(m, y, areaH, gearW, lap)
    self.rosterSig, self.rosterVersion = RosterSig(m), ns.Roster.version
    self.books = ns.GameGear.books
  end
  ns.Perf.Wrap(page, "Render", "render", "character page")

  -- A render a moment later: the events of a burst (a roster update, items loading) give one render.
  -- An explicit show draws at once and makes a pending one void.
  local RENDER_AFTER = 0.2
  function page:Schedule()
    if not self:IsShown() then return end
    self.dirty = true
    if self.pending then return end
    self.pending = true
    C_Timer.After(RENDER_AFTER, function()
      page.pending = false
      if page.dirty and page:IsShown() then ns.SafeCall(page.Render, page) end
    end)
  end
  page:SetScript("OnHide", function()
    UI.Notes.Hide()
    UI.ItemTips.Hide()
    UI.ScorePanel.Hide()
  end)
  page:SetScript("OnSizeChanged", function(self) if self.member and self:IsShown() then self:Render() end end)

  -- Which events concern what the page shows: data of the shown member (an event naming another member
  -- draws nothing; what it changes in rankings or the ready mark shows with the next render), the roster
  -- only when it shows something new of them or the member list changed, item infos only while the page
  -- waits for one or when the game named what a recipe makes since the last render (the books changed)
  local function Shown(key) return key == nil or (page.member ~= nil and page.member.key == key) end
  ns.On("ROSTER", function()
    local m = page:IsShown() and page.member and ns.Roster.Find(page.member.key)
    if m and (page.rosterVersion ~= ns.Roster.version or page.rosterSig ~= RosterSig(m)) then page:Schedule() end
  end)
  ns.On("STATS", function(key) if Shown(key) then page:Schedule() end end)
  ns.On("GEAR", function(key) if Shown(key) then page:Schedule() end end)
  ns.On("TALENTS", function(key) if Shown(key) then page:Schedule() end end)
  ns.On("GEAR_INFO", function()
    if page.waiting or page.books ~= ns.GameGear.books then page:Schedule() end
  end)
  ns.On("PROFS", function() page:Schedule() end)
  ns.On("FAMILY", function() page:Schedule() end)
end

-- Open the character page of roster member m (left click on a member anywhere)
function UI.ShowMember(m)
  if not m then return end
  if not page then Build() end
  if not page:IsShown() then page.backTab = UI.Current() end
  page.member = m
  page.modelKey, page.bgKey = nil, nil -- opening a page always loads its model and background anew
  UI.ShowPage(page)
  page:Render()
end

function UI.MemberPage()
  return page
end

-- Building blocks the communities view shares (UI/TabCommunities.lua)
UI.CharParts = { Portrait = Portrait }
