-- Character page ("hero card"): opened by a left click on a member anywhere (chat names, the online
-- list, the members and ranks tab), shown in the content area instead of a tab, with a way back.
-- Left the hero card: portrait (race and gender), level, Hall of Fame title and medals, rank, notes,
-- whisper and invite, and for officers a bar with the rank menu, notes and removal. Right the family
-- (twinks, Core/Family.lua) as compact cards, the big numbers with the place in the guild, the
-- dungeon collection and the professions.
local _, ns = ...
local W = ns.Widgets
local UI = ns.UI

local TEXTURES = "Interface\\AddOns\\Guildy\\Textures\\"
local MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local HERO_WIDTH = 270
local FAMILY_COLS, FAMILY_ROWS = 4, 2
local CARD_H = 58
local MEDALS = 4
local DUNGEON_ICON, DUNGEON_ICON_MAX, GAP = 24, 44, 5
local PROF_ROWS = 6
local MEDAL_COLORS = { { 1, 0.82, 0 }, { 0.78, 0.8, 0.84 }, { 0.78, 0.5, 0.27 } }
-- achievement icons of the races: Interface\Icons\Achievement_Character_<Race>_<Male|Female>
local RACE_ICON = { NightElf = "Nightelf", Human = "Human", Dwarf = "Dwarf", Gnome = "Gnome", Orc = "Orc",
  Scourge = "Undead", Undead = "Undead", Tauren = "Tauren", Troll = "Troll", BloodElf = "Bloodelf", Draenei = "Draenei" }

local page

-- Race, gender and the race icon of a member from the game (known once the client saw the character)
local function RaceInfo(m)
  local localizedRace, englishRace, female
  if m.raceFile then
    -- the account's own characters outside the guild: remembered at their login
    localizedRace, englishRace, female = m.raceName, m.raceFile, m.female and true or false
  else
    local getInfo = rawget(_G, "GetPlayerInfoByGUID")
    if not getInfo or not m.guid or m.guid == "" then return nil end
    local ok, sex
    ok, _, _, localizedRace, englishRace, sex = pcall(getInfo, m.guid)
    if not ok or not englishRace then return nil end
    female = sex == 3
  end
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
    if self.Level then self.Level:SetText(m.level or "") end
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

-- Hall of Fame titles of member key: medals (places 1 to 3, best first) and the title of the first
-- place, from every page's title cards
local function Medals(entries, key)
  local S, list = ns.Stats, {}
  for _, fame in ipairs(S.PAGES) do
    for _, title in ipairs(fame.titles or {}) do
      local place, _, value = Place(entries, key, title.stat)
      if place and place <= 3 and value and value > 0 then
        list[#list + 1] = { place = place, title = title, value = value }
      end
    end
  end
  table.sort(list, function(a, b) return a.place < b.place end)
  local first = list[1] and list[1].place == 1 and list[1].title
  return list, first and ns.L["FAME_TITLE_" .. first.key] or nil
end

-- The stored record of a character: the current guild's, or for the account's characters in other
-- guilds the one Guildy keeps for that guild
local function RecordOf(m)
  if m.elsewhere then
    local db = ns.DB()
    -- remembered before the guild key was stored: built like ns.GuildKey()
    local guildKey = m.guildKey or (m.guildName and (m.guildName .. "@" .. (ns.Try(rawget(_G, "GetNormalizedRealmName")) or "?")))
    local guild = guildKey and db and db.guilds and db.guilds[guildKey]
    return guild and type(guild.members) == "table" and guild.members[m.key] or nil
  end
  return ns.TradeSkill.Record(m)
end

local function ProfList(m)
  local record = RecordOf(m)
  local list = {}
  for _, skillLine in ipairs(ns.Professions.ORDER) do
    local prof = record and record.profs[skillLine]
    if prof then list[#list + 1] = { skillLine = skillLine, prof = prof } end
  end
  return list
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

-- Family card: portrait, name, level and last seen, class icon, professions with their skill
local function FamilyCard(parent)
  local card = CreateFrame("Button", nil, parent)
  card:SetHeight(CARD_H)
  card:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  -- a card of its own: lighter ground, thin bronze frame (gold on hover), a stripe in the class color
  local back = card:CreateTexture(nil, "BACKGROUND")
  back:SetAllPoints()
  back:SetColorTexture(0.11, 0.09, 0.065, 0.95)
  local shine = card:CreateTexture(nil, "BACKGROUND", nil, 1)
  shine:SetPoint("TOPLEFT")
  shine:SetPoint("TOPRIGHT")
  shine:SetHeight(CARD_H / 2)
  shine:SetColorTexture(1, 1, 1, 0.025)
  card.Edges = {}
  for _, side in ipairs({ { "TOPLEFT", "TOPRIGHT", true }, { "BOTTOMLEFT", "BOTTOMRIGHT", true },
    { "TOPLEFT", "BOTTOMLEFT" }, { "TOPRIGHT", "BOTTOMRIGHT" } }) do
    local edge = card:CreateTexture(nil, "BORDER")
    edge:SetPoint(side[1])
    edge:SetPoint(side[2])
    if side[3] then edge:SetHeight(1) else edge:SetWidth(1) end
    card.Edges[#card.Edges + 1] = edge
  end
  function card:SetEdge(r, g, b, a)
    for _, edge in ipairs(self.Edges) do edge:SetColorTexture(r, g, b, a) end
  end
  function card:RestEdge()
    if self.active then self:SetEdge(1, 0.82, 0, 1) else self:SetEdge(W.GOLD[1], W.GOLD[2], W.GOLD[3], 0.45) end
  end
  card:RestEdge()
  card.ActiveTint = card:CreateTexture(nil, "BACKGROUND", nil, 2)
  card.ActiveTint:SetAllPoints()
  card.ActiveTint:SetColorTexture(1, 0.82, 0, 0.08)
  card.ActiveTint:Hide()
  -- the character the page or tab is about, in a list that stays the same while navigating
  function card:SetActive(on)
    self.active = on and true or nil
    self.ActiveTint:SetShown(self.active == true)
    self:RestEdge()
  end
  card.Stripe = card:CreateTexture(nil, "ARTWORK")
  card.Stripe:SetPoint("TOPLEFT", 1, -1)
  card.Stripe:SetPoint("BOTTOMLEFT", 1, 1)
  card.Stripe:SetWidth(2)
  local glow = card:CreateTexture(nil, "HIGHLIGHT")
  glow:SetAllPoints()
  glow:SetColorTexture(1, 0.82, 0, 0.06)
  card.Portrait = Portrait(card, 36, 18)
  card.Portrait:SetPoint("TOPLEFT", 9, -7)
  card.Class = card:CreateTexture(nil, "ARTWORK")
  card.Class:SetSize(16, 16)
  card.Class:SetPoint("TOPRIGHT", -6, -6)
  card.Name = W.Text(card, "GameFontHighlight")
  card.Name:SetPoint("TOPLEFT", card.Portrait, "TOPRIGHT", 8, -2)
  card.Name:SetPoint("RIGHT", card.Class, "LEFT", -4, 0)
  card.Name:SetWordWrap(false)
  card.Sub = W.Text(card, "GameFontDisableSmall")
  card.Sub:SetPoint("TOPLEFT", card.Name, "BOTTOMLEFT", 0, -2)
  card.Sub:SetPoint("RIGHT", -6, 0)
  card.Sub:SetWordWrap(false)
  card.Profs = W.Text(card, "GameFontHighlightSmall")
  card.Profs:SetPoint("BOTTOMLEFT", card.Portrait, "BOTTOMRIGHT", 8, -4)
  card.Profs:SetPoint("RIGHT", -6, 0)
  card.Profs:SetWordWrap(false)
  card:SetScript("OnClick", function(self, button)
    if self.elsewhere then
      if button ~= "RightButton" then UI.ShowMember(self.elsewhere, true) end
      return
    end
    if not self.member then return end
    if button == "RightButton" then
      UI.MemberMenu(self.member, self)
    elseif self.account and not IsShiftKeyDown() then
      UI.ShowMember(self.member, true) -- from the account: stay in the account view
    else
      UI.MemberClick(self.member)
    end
  end)
  card:SetScript("OnEnter", function(self)
    self:SetEdge(1, 0.82, 0, 0.9)
    if self.member then
      UI.MemberTooltip(self, self.member)
    elseif self.elsewhere then
      local e = self.elsewhere
      GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
      GameTooltip:SetText(W.ClassName(e.name, e.classFile))
      GameTooltip:AddLine(e.guildName and ns.L.FAMILY_OTHER_GUILD:format(e.guildName) or ns.L.FAMILY_NO_GUILD, 1, 1, 1)
      GameTooltip:AddLine(ns.L.FAMILY_ELSEWHERE_TIP, 0.6, 0.6, 0.6, true)
      GameTooltip:AddLine(" ")
      GameTooltip:AddLine(ns.L.FAMILY_OPEN_HINT, 0.6, 0.6, 0.6, true)
      GameTooltip:Show()
    end
  end)
  card:SetScript("OnLeave", function(self)
    self:RestEdge()
    GameTooltip:Hide()
  end)
  function card:SetMember(m)
    -- the account's own characters outside this guild: no roster member, no menu
    self.member = not m.elsewhere and m or nil
    self.elsewhere = m.elsewhere and m or nil
    self.Portrait:SetMember(m)
    local r, g, b = W.ClassColor(m.classFile)
    self.Stripe:SetColorTexture(r or 0.6, g or 0.6, b or 0.6, 0.9)
    SetClassIcon(self.Class, m.classFile)
    self.Name:SetText(W.ClassName(m.name, m.classFile))
    if m.elsewhere then
      -- the guild tag green like in Blizzard's tooltips
      self.Sub:SetText(m.guildName and ("|cff40ff40<" .. m.guildName .. ">|r") or ns.L.FAMILY_NO_GUILD)
    else
      self.Sub:SetText(ns.Roster.LastOnlineText(m))
    end
    local parts = {}
    for _, p in ipairs(ProfList(m)) do
      if #parts < 3 then
        parts[#parts + 1] = "|T" .. ns.Professions.ICONS[p.skillLine] .. ":13|t " .. (p.prof.rank or "?")
      end
    end
    self.Profs:SetText(table.concat(parts, "   "))
  end
  return card
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

local function Build()
  local L = ns.L
  page = CreateFrame("Frame", nil, UI.Content())
  page:SetAllPoints()
  page:Hide()

  page.Back = W.Button(page, L.BACK, function() UI.SelectTab(page.backTab or "chat") end, 90)
  page.Back:SetPoint("TOPLEFT", 54, -2) -- clear of the portrait

  -- hero card --------------------------------------------------------------------------------------
  local hero = W.Box(page)
  hero:SetPoint("TOPLEFT", 0, -30)
  hero:SetPoint("BOTTOMLEFT", 0, 0)
  hero:SetWidth(HERO_WIDTH)
  page.Hero = hero
  hero.Portrait = Portrait(hero, 104, 30)
  hero.Portrait:SetPoint("TOP", 0, -16)
  hero.Name = W.Text(hero, "GameFontNormalHuge")
  hero.Name:SetPoint("TOP", hero.Portrait, "BOTTOM", 0, -10)
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
  hero.Medals = {}
  for i = 1, MEDALS do
    local medal = CreateFrame("Frame", nil, hero)
    medal:SetSize(40, 40)
    medal:EnableMouse(true)
    medal.Icon = Portrait(medal, 40)
    medal.Icon:SetAllPoints()
    medal.Place = W.Text(medal, "GameFontNormalSmall")
    medal.Place:SetPoint("BOTTOMRIGHT", 4, -2)
    medal:SetScript("OnEnter", function(self)
      if not self.info then return end
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      GameTooltip:SetText(L.MEDAL_TIP:format(self.info.place, L["FAME_TITLE_" .. self.info.title.key]))
      GameTooltip:AddLine(UI.Fame.Format(self.info.title.stat, self.info.value) .. " · " .. UI.Fame.StatName(self.info.title.stat), 1, 1, 1)
      GameTooltip:Show()
    end)
    medal:SetScript("OnLeave", function() GameTooltip:Hide() end)
    hero.Medals[i] = medal
  end
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
  local right = CreateFrame("Frame", nil, page)
  right:SetPoint("TOPLEFT", hero, "TOPRIGHT", 8, 0)
  right:SetPoint("BOTTOMRIGHT", 0, 0)
  page.Right = right

  local family = Section(right, L.FAMILY)
  page.Family = family
  family.Empty = W.Text(family, "GameFontDisableSmall", L.FAMILY_EMPTY)
  family.Empty:SetPoint("TOPLEFT", 12, -32)
  family.Empty:SetPoint("RIGHT", -12, 0)
  family.Cards = {}
  for i = 1, FAMILY_COLS * FAMILY_ROWS do family.Cards[i] = FamilyCard(family) end
  family.More = W.Text(family, "GameFontDisableSmall")
  family.More:SetPoint("BOTTOMRIGHT", -12, 8)

  page.Tiles = {
    kills = Tile(right, L.STAT_KILLS), quests = Tile(right, L.STAT_QUESTS),
    deaths = Tile(right, L.STAT_DEATHS), gear = Tile(right, L.STAT_ILVL),
  }
  -- equipment by quality: Guildy knows how many items of each quality, not the items
  local gear = page.Tiles.gear
  gear.Bars = {}
  for i, color in ipairs({ { 1, 0.5, 0 }, { 0.64, 0.21, 0.93 }, { 0, 0.44, 0.87 }, { 0.12, 1, 0 }, { 1, 1, 1 }, { 0.62, 0.62, 0.62 } }) do
    local bar = gear:CreateTexture(nil, "ARTWORK")
    bar:SetHeight(8)
    bar:SetColorTexture(color[1], color[2], color[3], 0.9)
    gear.Bars[i] = bar
  end
  gear.Line:Hide()

  local dungeons = Section(right, L.DUNGEON_COLLECTION)
  page.Dungeons = dungeons
  dungeons.Icons = {}
  for i, dungeon in ipairs(ns.Stats.DUNGEONS or {}) do
    local icon = CreateFrame("Frame", nil, dungeons)
    icon:SetSize(DUNGEON_ICON, DUNGEON_ICON)
    icon:EnableMouse(true)
    icon.Texture = icon:CreateTexture(nil, "ARTWORK")
    icon.Texture:SetAllPoints()
    local path, cropped = UI.Fame.DungeonIcon(dungeon)
    icon.Texture:SetTexture(path or "Interface\\Icons\\INV_Misc_QuestionMark")
    if cropped then icon.Texture:SetTexCoord(0.08, 0.92, 0.08, 0.92) end
    icon.dungeon = dungeon
    icon:SetScript("OnEnter", function(self)
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      GameTooltip:SetText(UI.Fame.DungeonTitle(self.dungeon))
      GameTooltip:AddLine(self.kills and self.kills > 0 and L.DUNGEON_KILLS:format(self.kills) or L.DUNGEON_OPEN, 1, 1, 1)
      GameTooltip:Show()
    end)
    icon:SetScript("OnLeave", function() GameTooltip:Hide() end)
    dungeons.Icons[i] = icon
  end

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
    hero.Name:SetText(W.ClassName(m.name, m.classFile))
    local medals, title = Medals(entries, m.key)
    hero.Title:SetText(title and ("„" .. title .. "“") or "")
    local ident = {}
    if info and info.race then ident[#ident + 1] = info.race end
    if info then ident[#ident + 1] = info.female and L.FEMALE or L.MALE end
    ident[#ident + 1] = m.className or ""
    hero.Ident:SetText(ClassIconString(m.classFile) .. table.concat(ident, " · "))
    if m.elsewhere then
      hero.Where:SetText((m.guildName and ("|cff40ff40<" .. m.guildName .. ">|r") or L.FAMILY_NO_GUILD) .. " · " ..
        L.LAST_LOGIN:format(ns.Roster.LastOnlineText(m)))
    else
      hero.Where:SetText((m.rank or "") .. (m.zone and m.zone ~= "" and (" · " .. m.zone) or "") .. " · " ..
        (m.online and ("|cff4ce64c" .. L.ONLINE .. "|r") or ns.Roster.LastOnlineText(m)))
    end

    local notes = {}
    if m.note and m.note ~= "" then notes[#notes + 1] = "|cffffd100" .. L.NOTE .. ":|r " .. m.note end
    if can.viewOfficer and m.officerNote and m.officerNote ~= "" then
      notes[#notes + 1] = "|cffffd100" .. L.OFFICER_NOTE .. ":|r " .. m.officerNote
    end
    local guildy = not m.elsewhere and UI.GuildyVersionText and UI.GuildyVersionText(m)
    if guildy then notes[#notes + 1] = "|cffffd100" .. L.COL_GUILDY .. ":|r " .. guildy end
    hero.Notes:SetText(table.concat(notes, "\n"))
    hero.Notes:ClearAllPoints()
    hero.Notes:SetPoint("TOP", hero.Where, "BOTTOM", 0, -10)
    hero.Notes:SetWidth(HERO_WIDTH - 28)

    local shown = math.min(#medals, MEDALS)
    local width = shown * 40 + math.max(0, shown - 1) * 10
    for i, medal in ipairs(hero.Medals) do
      local entry = medals[i]
      medal.info = entry
      if entry and i <= MEDALS then
        medal:ClearAllPoints()
        medal:SetPoint("TOP", hero.Notes, "BOTTOM", -width / 2 + 20 + (i - 1) * 50, -12)
        medal.Icon.Picture:SetTexture(UI.Fame.Icon(entry.title.icon))
        medal.Icon.Picture:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        local color = MEDAL_COLORS[entry.place]
        medal.Icon.Ring:SetVertexColor(color[1], color[2], color[3])
        medal.Place:SetText(entry.place)
        medal:Show()
      else
        medal:Hide()
      end
    end

    -- the account's characters in other guilds: no rank, no notes, nothing to do from here
    local officer = not m.elsewhere and can.remove
    hero.OfficerLabel:SetShown(officer)
    hero.Remove:SetShown(officer and can.remove)
    hero.Remove:SetEnabled(not m.elsewhere and ns.Roster.Rights(m).remove or false)
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
    hero.Whisper:SetShown(not m.elsewhere)
    hero.Invite:SetShown(not m.elsewhere)
    hero.Whisper:SetEnabled(m.online or false)
    hero.Invite:SetEnabled(m.online or false)
    UI.Notes.Show(m)
  end

  function page:RenderFamily(m)
    local guild, db = ns.GuildData(), ns.DB()
    local members = ns.Roster.Members()
    local list = ns.Family.Of(m.key, members, guild and guild.families, db and db.ownChars)
    -- opened from the account tab (or a character outside this guild): the family is the whole
    -- account, the characters in this guild as members with a menu
    local account = (self.account or m.elsewhere) and db and db.ownChars and true or false
    family.Title:SetText(account and L.ACCOUNT_OTHERS or L.FAMILY)
    family.Empty:SetText(account and L.ACCOUNT_OTHERS_EMPTY or L.FAMILY_EMPTY)
    if account then
      list = {}
      for _, other in ipairs(ns.Family.OwnElsewhere(db.ownChars, {}, ns.Now())) do
        list[#list + 1] = ns.Roster.Find(other.key) or other
      end
    end
    local width = (right:GetWidth() or 600) - 24
    local cardW = math.floor((width - (FAMILY_COLS - 1) * 6) / FAMILY_COLS)
    local maxCards = FAMILY_COLS * FAMILY_ROWS
    for i, card in ipairs(family.Cards) do
      local other = list[i]
      if other and i <= maxCards then
        card:ClearAllPoints()
        card:SetWidth(cardW)
        card:SetPoint("TOPLEFT", 12 + ((i - 1) % FAMILY_COLS) * (cardW + 6), -30 - math.floor((i - 1) / FAMILY_COLS) * (CARD_H + 6))
        card:SetMember(other)
        card.account = account
        card:SetActive(account and other.key == m.key)
        card:Show()
      else
        card:Hide()
      end
    end
    family.Empty:SetShown(#list == 0)
    family.More:SetText(#list > maxCards and L.FAMILY_MORE:format(#list - maxCards) or "")
    local rows = math.min(FAMILY_ROWS, math.ceil(#list / FAMILY_COLS))
    family:SetHeight(#list == 0 and 66 or (36 + rows * (CARD_H + 6) + (#list > maxCards and 12 or 0)))
    if #list > 0 then
      -- in account mode the page's character is one of the cards already
      local levels, profsSeen, count = account and 0 or (m.level or 0), {}, 0
      for _, p in ipairs(ProfList(m)) do profsSeen[p.skillLine] = true end
      for _, other in ipairs(list) do
        levels = levels + (other.level or 0)
        for _, p in ipairs(ProfList(other)) do profsSeen[p.skillLine] = true end
      end
      for _ in pairs(profsSeen) do count = count + 1 end
      family.Note:SetText(L.FAMILY_SUMMARY:format(#list + (account and 0 or 1), levels, count))
    else
      family.Note:SetText("")
    end
  end

  function page:RenderStats(m, entries)
    local S = ns.Stats
    local guild = ns.GuildData()
    local record = m.elsewhere and RecordOf(m) or (guild and guild.members[m.key])
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
    local counts = { values[S.GEAR.LEGENDARY] or 0, values[S.GEAR.EPIC] or 0, values[S.GEAR.RARE] or 0,
      values[S.GEAR.UNCOMMON] or 0, values[S.GEAR.COMMON] or 0, values[S.GEAR.POOR] or 0 }
    local total = 0
    for _, n in ipairs(counts) do total = total + n end
    local barWidth = (t.gear:GetWidth() or 120) - 24
    local x = 12
    for i, bar in ipairs(t.gear.Bars) do
      local w = total > 0 and math.floor(counts[i] / total * barWidth + 0.5) or 0
      bar:ClearAllPoints()
      bar:SetPoint("BOTTOMLEFT", t.gear, "BOTTOMLEFT", x, 12)
      bar:SetWidth(math.max(w, 0.01))
      bar:SetShown(w > 0)
      x = x + w
    end
    return rec
  end

  function page:RenderDungeons(rec)
    -- as big as the panel allows with all dungeons in two rows (16 per row), within limits
    local width = (dungeons:GetWidth() or 400) - 24
    local perRow = math.ceil(#dungeons.Icons / 2)
    local size = math.max(DUNGEON_ICON, math.min(DUNGEON_ICON_MAX, math.floor((width + GAP) / math.max(1, perRow)) - GAP))
    perRow = math.max(1, math.floor((width + GAP) / (size + GAP)))
    local cleared, known = 0, 0
    for i, icon in ipairs(dungeons.Icons) do
      local kills = rec and UI.Fame.DungeonKills(rec, icon.dungeon, "all")
      icon.kills = kills
      if kills ~= nil then known = known + 1 end
      local done = kills and kills > 0
      if done then cleared = cleared + 1 end
      icon.Texture:SetDesaturated(not done)
      icon:SetAlpha(done and 1 or 0.35)
      icon:ClearAllPoints()
      icon:SetSize(size, size)
      icon:SetPoint("TOPLEFT", 12 + ((i - 1) % perRow) * (size + GAP), -32 - math.floor((i - 1) / perRow) * (size + GAP))
    end
    dungeons.Note:SetText(rec and L.DUNGEON_COUNT:format(cleared, #dungeons.Icons) or L.NO_STATS_SHORT)
  end

  function page:RenderProfs(m)
    local list = ProfList(m)
    for i, row in ipairs(profs.Rows) do
      local p = list[i]
      if p then
        row.Icon:SetTexture(ns.Professions.ICONS[p.skillLine])
        row.Name:SetText(ns.TradeSkill.Name(p.skillLine))
        local prof = p.prof
        row.Level:SetText(prof.rank and (prof.rank .. (prof.max and ("|cff999999/" .. prof.max .. "|r") or "")) or "|cff999999–|r")
        local atCap = prof.rank ~= nil and prof.max ~= nil and prof.rank >= prof.max and prof.max < W.SKILL_SCALE
        row.Trainer:SetShown(atCap)
        -- the bar takes the room between the number and the "Trainer" label
        local rowWidth = (profs:GetWidth() or 300) - 24
        row.Bar:SetBarWidth(rowWidth - 16 - 6 - 110 - 4 - 56 - 8 - 8 - (row.Trainer:GetStringWidth() or 40))
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
  end

  function page:Layout()
    local width = right:GetWidth() or 700
    local top = page.Family:GetHeight() or 66
    page.Family:ClearAllPoints()
    page.Family:SetPoint("TOPLEFT", right, "TOPLEFT", 0, 0)
    page.Family:SetPoint("RIGHT", right, "RIGHT", 0, 0)
    local tileW = math.floor((width - 3 * 8) / 4)
    local y = -(top + 8)
    for i, key in ipairs({ "kills", "quests", "deaths", "gear" }) do
      local tile = page.Tiles[key]
      tile:ClearAllPoints()
      tile:SetSize(tileW, 78)
      tile:SetPoint("TOPLEFT", right, "TOPLEFT", (i - 1) * (tileW + 8), y)
    end
    y = y - 78 - 8
    local dungeonW = math.floor(width * 0.58)
    page.Dungeons:ClearAllPoints()
    page.Dungeons:SetPoint("TOPLEFT", right, "TOPLEFT", 0, y)
    page.Dungeons:SetPoint("BOTTOM", right, "BOTTOM", 0, 0)
    page.Dungeons:SetWidth(dungeonW)
    page.Profs:ClearAllPoints()
    page.Profs:SetPoint("TOPLEFT", page.Dungeons, "TOPRIGHT", 8, 0)
    page.Profs:SetPoint("BOTTOMRIGHT", right, "BOTTOMRIGHT", 0, 0)
  end

  function page:Render()
    local m = self.member and not self.member.elsewhere and ns.Roster.Find(self.member.key) or self.member
    self.member = m
    if not m then return end
    local entries = ns.GameStats.Entries()
    self:RenderHero(m, entries)
    self:RenderFamily(m)
    self:Layout()
    local rec = self:RenderStats(m, entries)
    self:RenderDungeons(rec)
    self:RenderProfs(m)
  end
  page:SetScript("OnHide", function()
    UI.Notes.Hide()
  end)
  page:SetScript("OnSizeChanged", function(self) if self.member and self:IsShown() then self:Render() end end)

  for _, event in ipairs({ "ROSTER", "PROFS", "STATS", "FAMILY" }) do
    ns.On(event, function() if page:IsShown() then page:Render() end end)
  end
end

-- Open the character page of roster member m (left click on a member anywhere)
-- account: opened from the account tab; the family shows the whole account then
function UI.ShowMember(m, account)
  if not m then return end
  if not page then Build() end
  if not page:IsShown() then page.backTab = UI.Current() end
  page.member = m
  page.account = account and true or nil
  UI.ShowPage(page)
  page:Render()
end

function UI.MemberPage()
  return page
end

-- Building blocks the account tab shares (UI/TabAccount.lua)
UI.CharParts = {
  Portrait = Portrait, Section = Section, FamilyCard = FamilyCard, SetClassIcon = SetClassIcon,
  ProfList = ProfList, RecordOf = RecordOf, Number = Number, CARD_H = CARD_H, ClassIconString = ClassIconString,
}
