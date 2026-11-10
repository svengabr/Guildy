-- Account tab: the logged-in character as a hero card with numbers over the whole account, the
-- account's other characters as cards (any guild or none) and every profession of the account with
-- its skill. Built from GuildyDB.ownChars, which stays on this computer. Without a guild it is the only
-- tab (UI/Main.lua).
local _, ns = ...
local W = ns.Widgets
local UI = ns.UI

local HERO_WIDTH = W.SIDE
local CARD_COLS, CARD_ROWS = 4, 3
-- a profession tile: its fixed part (name, best skill, bar) and one line per character under it
local TILE_HEAD, TILE_LINE, TILE_LINES = 66, 15, 3
local TILE_MIN_W, TILE_GAP = 130, 6
local ACCOUNT_ICON = "Interface\\Icons\\INV_Misc_GroupNeedMore"

-- The account's characters: roster members for those in the current guild (with menu and live data),
-- else the remembered details. The logged-in character first, then by level.
local function Characters()
  local db = ns.DB()
  local own = db and db.ownChars or {}
  local meKey = ns.Names.Key(ns.PlayerName() or "")
  local list, all, me = {}, {}, nil
  for _, c in ipairs(ns.Family.OwnElsewhere(own, {}, ns.Now())) do
    local m = (IsInGuild() and ns.Roster.Find(c.key)) or c
    all[#all + 1] = m
    if c.key == meKey then me = m else list[#list + 1] = m end
  end
  return me, list, all
end

local function Build(panel)
  local L = ns.L
  local P = UI.CharParts
  local view = {}

  -- hero ---------------------------------------------------------------------------------------------
  local page = W.Page(panel)
  panel = page.Body
  local hero = W.Box(panel)
  hero:SetPoint("TOPLEFT", 0, 0)
  hero:SetPoint("BOTTOMLEFT", 0, 0)
  hero:SetWidth(W.SIDE)
  -- the account card: no character chosen yet, the account as a whole
  hero.Portrait = P.Portrait(hero, 68) -- small enough that the guild list clears the numbers at the bottom
  hero.Portrait:SetPoint("TOP", 0, -12)
  hero.Portrait.Picture:SetTexture(W.TextureExists(ACCOUNT_ICON) and ACCOUNT_ICON or "Interface\\Icons\\INV_Misc_Book_09")
  hero.Portrait.Picture:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  hero.Portrait.Ring:SetVertexColor(W.GOLD[1], W.GOLD[2], W.GOLD[3])
  hero.Name = W.Text(hero, "GameFontNormalHuge", L.ACCOUNT_TITLE)
  hero.Name:SetPoint("TOP", hero.Portrait, "BOTTOM", 0, -10)
  hero.Ident = W.Text(hero, "GameFontHighlightSmall")
  hero.Ident:SetPoint("TOP", hero.Name, "BOTTOM", 0, -8)
  hero.Ident:SetWidth(HERO_WIDTH - 24)
  hero.Ident:SetJustifyH("CENTER")
  hero.Ident:SetSpacing(2)
  hero.Where = W.Text(hero, "GameFontDisableSmall")
  hero.Where:SetPoint("TOP", hero.Ident, "BOTTOM", 0, -5)
  hero.Where:SetJustifyH("CENTER")
  hero.Where:SetWidth(HERO_WIDTH - 24)
  hero.Where:SetSpacing(2)

  -- without a guild: why the window is so empty
  hero.NoGuild = W.Box(hero, 0.05, 0.5)
  hero.NoGuild:SetPoint("TOP", hero.Where, "BOTTOM", 0, -10)
  hero.NoGuild:SetSize(HERO_WIDTH - 28, 60)
  hero.NoGuild.Title = W.Text(hero.NoGuild, "GameFontNormal", L.ACCOUNT_NO_GUILD)
  hero.NoGuild.Title:SetPoint("TOPLEFT", 10, -8)
  hero.NoGuild.Text = W.Text(hero.NoGuild, "GameFontHighlightSmall", L.ACCOUNT_NO_GUILD_TEXT)
  hero.NoGuild.Text:SetPoint("TOPLEFT", hero.NoGuild.Title, "BOTTOMLEFT", 0, -4)
  hero.NoGuild.Text:SetPoint("RIGHT", -10, 0)
  hero.NoGuild.Text:SetSpacing(2)

  -- together over all characters (as far as Guildy knows them), then the guilds
  local function Block(title)
    local block = CreateFrame("Frame", nil, hero)
    block:SetWidth(HERO_WIDTH - 28)
    block.Title = W.Text(block, "GameFontNormal", title)
    block.Title:SetPoint("TOPLEFT")
    block.Rows = {}
    function block:Row(i)
      local row = self.Rows[i]
      if not row then
        row = {}
        row.Label = W.Text(self, "GameFontHighlightSmall")
        row.Label:SetPoint("TOPLEFT", 4, -20 - (i - 1) * 17)
        row.Label:SetPoint("RIGHT", -60, 0)
        row.Label:SetWordWrap(false)
        row.Value = W.Text(self, "GameFontNormalSmall")
        row.Value:SetPoint("TOPRIGHT", -2, -20 - (i - 1) * 17)
        row.Value:SetJustifyH("RIGHT")
        self.Rows[i] = row
      end
      return row
    end
    function block:Fill(rows)
      for i, data in ipairs(rows) do
        local row = self:Row(i)
        row.Label:SetText(data[1])
        row.Value:SetText(data[2])
        row.Label:Show()
        row.Value:Show()
      end
      for i = #rows + 1, #self.Rows do
        self.Rows[i].Label:Hide()
        self.Rows[i].Value:Hide()
      end
      self:SetHeight(22 + #rows * 17)
    end
    return block
  end
  hero.Totals = Block(L.ACCOUNT_TOGETHER)
  hero.Guilds = Block(L.ACCOUNT_GUILDS)
  hero.Guilds:SetPoint("TOPLEFT", hero.Totals, "BOTTOMLEFT", 0, -12)

  -- numbers over the account
  hero.Numbers = {}
  local boxW = math.floor((HERO_WIDTH - 24 - 12) / 3)
  for i, label in ipairs({ L.ACCOUNT_CHARS, L.ACCOUNT_LEVELS, L.ACCOUNT_PROFS }) do
    local box = W.Box(hero, 0.05, 0.4)
    box:SetSize(boxW, 54)
    box:SetPoint("BOTTOMLEFT", 12 + (i - 1) * (boxW + 6), 12)
    box.Value = W.Text(box, "GameFontNormalLarge")
    box.Value:SetPoint("TOP", 0, -9)
    box.Label = W.Text(box, "GameFontDisableSmall", label)
    box.Label:SetPoint("BOTTOM", 0, 9)
    hero.Numbers[i] = box
  end

  -- characters -----------------------------------------------------------------------------------------
  local right = CreateFrame("Frame", nil, panel)
  right:SetPoint("TOPLEFT", hero, "TOPRIGHT", 8, 0)
  right:SetPoint("BOTTOMRIGHT", 0, 0)

  local chars = P.Section(right, L.ACCOUNT_OTHERS)
  chars:SetPoint("TOPLEFT")
  chars:SetPoint("RIGHT")
  chars.Note:SetText(L.ACCOUNT_ONLY_YOU)
  chars.Empty = W.Text(chars, "GameFontDisableSmall", L.ACCOUNT_OTHERS_EMPTY)
  chars.Empty:SetPoint("TOPLEFT", 12, -32)
  chars.Empty:SetPoint("RIGHT", -12, 0)
  chars.Cards = {}
  for i = 1, CARD_COLS * CARD_ROWS do chars.Cards[i] = P.FamilyCard(chars) end
  chars.More = W.Text(chars, "GameFontDisableSmall")
  chars.More:SetPoint("BOTTOMRIGHT", -12, 8)

  -- professions of the whole account ----------------------------------------------------------------
  local profs = P.Section(right, L.ACCOUNT_PROFESSIONS)
  profs:SetPoint("TOPLEFT", chars, "BOTTOMLEFT", 0, -8)
  profs:SetPoint("BOTTOMRIGHT")
  profs.Note:SetText(L.ACCOUNT_PROFS_NOTE)
  profs.Empty = W.Text(profs, "GameFontDisableSmall", L.NO_PROFESSIONS)
  profs.Empty:SetPoint("TOPLEFT", 12, -32)
  -- one tile per profession somebody on the account has: icon and name, the best skill big with its
  -- bar, under it the characters with the profession (best first; the rest in the tooltip)
  profs.Tiles = {}
  for i = 1, #ns.Professions.ORDER do
    local tile = W.Box(profs, 0.05, 0.45)
    tile.Icon = tile:CreateTexture(nil, "ARTWORK")
    tile.Icon:SetSize(16, 16)
    tile.Icon:SetPoint("TOPLEFT", 8, -8)
    tile.Name = W.Text(tile, "GameFontHighlightSmall")
    tile.Name:SetPoint("LEFT", tile.Icon, "RIGHT", 6, 0)
    tile.Name:SetPoint("RIGHT", tile, "RIGHT", -6, 0)
    tile.Name:SetWordWrap(false)
    tile.Best = W.Text(tile, "GameFontNormalLarge")
    tile.Best:SetPoint("TOPLEFT", 8, -29)
    tile.Max = W.Text(tile, "GameFontDisableSmall")
    tile.Max:SetPoint("BOTTOMLEFT", tile.Best, "BOTTOMRIGHT", 3, 1)
    tile.Bar = W.SkillBar(tile, 80)
    tile.Bar:SetPoint("TOPLEFT", 8, -51)
    tile.Lines = {}
    for line = 1, TILE_LINES + 1 do -- the last one may say "+2 more"
      local who = W.Text(tile, "GameFontHighlightSmall")
      who:SetPoint("TOPLEFT", 8, -TILE_HEAD - (line - 1) * TILE_LINE + 2)
      who:SetPoint("RIGHT", tile, "RIGHT", -40, 0)
      who:SetWordWrap(false)
      local rank = W.Text(tile, "GameFontHighlightSmall")
      rank:SetPoint("TOPRIGHT", -8, -TILE_HEAD - (line - 1) * TILE_LINE + 2)
      rank:SetJustifyH("RIGHT")
      tile.Lines[line] = { Who = who, Rank = rank }
    end
    tile:EnableMouse(true)
    tile:SetScript("OnEnter", function(self)
      if not self.group then return end
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      GameTooltip:SetText(ns.TradeSkill.Name(self.group.skillLine), 1, 0.82, 0)
      for _, e in ipairs(self.group.entries) do
        local r, g, b = W.ClassColor(e.m.classFile)
        local prof = e.prof
        GameTooltip:AddDoubleLine(e.m.name or "?", prof.rank and (prof.rank .. (prof.max and (" / " .. prof.max) or "")) or "–",
          r, g, b, 1, 1, 1)
      end
      GameTooltip:Show()
    end)
    tile:SetScript("OnLeave", function() GameTooltip:Hide() end)
    profs.Tiles[i] = tile
  end

  -- render -----------------------------------------------------------------------------------------------
  function view:RenderHero(me, list)
    local m = me or { name = ns.Anon.Name(ns.PlayerName() or "?"), level = UnitLevel("player") }
    hero.Ident:SetText(L.ACCOUNT_LOGGED_IN:format(W.ClassName(m.name, m.classFile)))
    local guild = IsInGuild() and ns.Anon.Guild(GetGuildInfo("player")) or nil
    hero.Where:SetText(guild and ("|cff40ff40<" .. guild .. ">|r") or L.FAMILY_NO_GUILD)
    hero.NoGuild:SetShown(not IsInGuild())
    hero.Totals:ClearAllPoints()
    if IsInGuild() then
      hero.Totals:SetPoint("TOP", hero.Where, "BOTTOM", 0, -18)
    else
      hero.Totals:SetPoint("TOP", hero.NoGuild, "BOTTOM", 0, -10)
    end

    -- kills, quests, deaths summed over the characters with known statistics; dungeons any of them
    -- cleared (the union, out of all)
    local everyone = { m }
    for _, other in ipairs(list) do everyone[#everyone + 1] = other end
    local S, now = ns.Stats, ns.Now()
    local sums, known, cleared = { 0, 0, 0 }, false, {}
    for _, c in ipairs(everyone) do
      local record = P.RecordOf(c)
      local rec = record and record.stats
      if rec then
        for i, id in ipairs({ 107, 98, 60 }) do
          local value = S.Value(rec, id, "all", now, ns.GameStats.Date)
          if value then sums[i], known = sums[i] + value, true end
        end
        for _, dungeon in ipairs(S.DUNGEONS or {}) do
          local kills = UI.Fame.DungeonKills(rec, dungeon, "all")
          if kills and kills > 0 then cleared[dungeon] = true end
        end
      end
    end
    local clearedCount = 0
    for _ in pairs(cleared) do clearedCount = clearedCount + 1 end
    local function Number(n) return known and P.Number(n) or "–" end
    hero.Totals:Fill({
      { L.STAT_KILLS, Number(sums[1]) }, { L.STAT_QUESTS, Number(sums[2]) }, { L.STAT_DEATHS, Number(sums[3]) },
      { L.ACCOUNT_DUNGEONS, clearedCount .. "/" .. #(S.DUNGEONS or {}) },
    })

    -- guilds with how many characters, "No guild" last
    local byGuild, order, none = {}, {}, 0
    for _, c in ipairs(everyone) do
      local name = c.guildName or (not c.elsewhere and guild) or nil
      if name then
        if not byGuild[name] then byGuild[name] = 0; order[#order + 1] = name end
        byGuild[name] = byGuild[name] + 1
      else
        none = none + 1
      end
    end
    table.sort(order, function(a, b)
      if byGuild[a] ~= byGuild[b] then return byGuild[a] > byGuild[b] end
      return a < b
    end)
    local rows = {}
    for _, name in ipairs(order) do rows[#rows + 1] = { "|cff40ff40<" .. name .. ">|r", byGuild[name] } end
    if none > 0 then rows[#rows + 1] = { "|cff8f8268" .. L.FAMILY_NO_GUILD .. "|r", none } end
    -- as many rows as fit above the number boxes; the rest as "+N more"
    local top, floor = hero.Guilds:GetTop(), hero.Numbers[1]:GetTop()
    if top and floor then
      local fit = math.max(1, math.floor((top - floor - 8 - 22) / 17))
      if #rows > fit then
        -- the last row that fits sums up the rest: "+N more" guilds, with their characters
        local hiddenGuilds, hiddenChars = #rows - fit + 1, 0
        for i = fit, #rows do hiddenChars = hiddenChars + (tonumber(rows[i][2]) or 0) end
        for i = #rows, fit, -1 do rows[i] = nil end
        rows[fit] = { "|cff8f8268" .. L.FAMILY_MORE:format(hiddenGuilds) .. "|r", hiddenChars }
      end
    end
    hero.Guilds:Fill(rows)

    local levels, kinds, count = m.level or 0, {}, 0
    for _, p in ipairs(P.ProfList(m)) do kinds[p.skillLine] = true end
    for _, other in ipairs(list) do
      levels = levels + (other.level or 0)
      for _, p in ipairs(P.ProfList(other)) do kinds[p.skillLine] = true end
    end
    for skillLine in pairs(kinds) do
      if ns.Professions.PRIMARY[skillLine] then count = count + 1 end
    end
    hero.Numbers[1].Value:SetText(#list + 1)
    hero.Numbers[2].Value:SetText(levels)
    hero.Numbers[3].Value:SetText(count)
  end

  -- every character of the account in a fixed order (level, name), none highlighted (overview)
  function view:RenderChars(list)
    local width = (right:GetWidth() or 600) - 24
    local cardW = math.floor((width - (CARD_COLS - 1) * 6) / CARD_COLS)
    local maxCards = CARD_COLS * CARD_ROWS
    for i, card in ipairs(chars.Cards) do
      local other = list[i]
      if other then
        card:ClearAllPoints()
        card:SetWidth(cardW)
        card:SetPoint("TOPLEFT", 12 + ((i - 1) % CARD_COLS) * (cardW + 6), -30 - math.floor((i - 1) / CARD_COLS) * (P.CARD_H + 6))
        card:SetMember(other)
        card.account = true
        card:SetActive(false) -- the overview has no character chosen
        card:Show()
      else
        card:Hide()
      end
    end
    chars.Empty:SetShown(#list == 0)
    chars.More:SetText(#list > maxCards and L.FAMILY_MORE:format(#list - maxCards) or "")
    local rows = math.min(CARD_ROWS, math.ceil(#list / CARD_COLS))
    chars:SetHeight(#list == 0 and 66 or (36 + rows * (P.CARD_H + 6) + (#list > maxCards and 12 or 0)))
  end

  function view:RenderProfs(me, list)
    -- the account's professions in the game's order (primary ones first), each with its characters,
    -- highest skill first
    local everyone = { me }
    for _, other in ipairs(list) do everyone[#everyone + 1] = other end
    local bySkill = {}
    for _, m in ipairs(everyone) do
      for _, p in ipairs(P.ProfList(m)) do
        bySkill[p.skillLine] = bySkill[p.skillLine] or { skillLine = p.skillLine, entries = {} }
        table.insert(bySkill[p.skillLine].entries, { m = m, prof = p.prof })
      end
    end
    local groups = {}
    for _, skillLine in ipairs(ns.Professions.ORDER) do
      local group = bySkill[skillLine]
      if group then
        table.sort(group.entries, function(a, b)
          local x, y = a.prof.rank or 0, b.prof.rank or 0
          if x ~= y then return x > y end
          return (a.m.name or "") < (b.m.name or "")
        end)
        groups[#groups + 1] = group
      end
    end
    -- as many columns as fit (tiles at least TILE_MIN_W wide), at most six; the character lines take
    -- what height the rows leave, so the tiles never run out of the box
    local width = (profs:GetWidth() or 600) - 24
    local height = (profs:GetHeight() or 300) - 30 - 10
    local columns = math.max(1, math.min(6, math.floor((width + TILE_GAP) / (TILE_MIN_W + TILE_GAP))))
    local tileW = math.floor((width - (columns - 1) * TILE_GAP) / columns)
    local rows = math.max(1, math.ceil(#groups / columns))
    local room = math.floor((height - (rows - 1) * TILE_GAP) / rows)
    local lines = math.max(0, math.min(TILE_LINES, math.floor((room - TILE_HEAD - 6) / TILE_LINE)))
    local tileH = TILE_HEAD + (lines > 0 and (lines * TILE_LINE + 6) or 0)
    for i, tile in ipairs(profs.Tiles) do
      local group = groups[i]
      tile.group = group
      tile:SetShown(group ~= nil)
      if group then
        tile:ClearAllPoints()
        tile:SetSize(tileW, tileH)
        tile:SetPoint("TOPLEFT", 12 + ((i - 1) % columns) * (tileW + TILE_GAP),
          -30 - math.floor((i - 1) / columns) * (tileH + TILE_GAP))
        tile.Icon:SetTexture(ns.Professions.ICONS[group.skillLine])
        tile.Name:SetText(ns.TradeSkill.Name(group.skillLine))
        local best = group.entries[1].prof
        tile.Best:SetText(best.rank and tostring(best.rank) or "–")
        tile.Max:SetText(best.rank and best.max and ("/ " .. best.max) or "")
        tile.Bar:SetBarWidth(tileW - 16)
        tile.Bar:SetShown(best.rank ~= nil)
        if best.rank then tile.Bar:SetSkill(best.rank, best.max) end
        -- with more characters than lines the last line counts the rest
        local fits = #group.entries <= lines
        for index, line in ipairs(tile.Lines) do
          local e = group.entries[index]
          local more = not fits and index == lines
          if index <= lines and e and not more then
            line.Who:SetText(W.ClassName(e.m.name, e.m.classFile))
            line.Rank:SetText(e.prof.rank and tostring(e.prof.rank) or "|cff999999–|r")
          elseif more then
            line.Who:SetText("|cff8f8268" .. L.FAMILY_MORE:format(#group.entries - lines + 1) .. "|r")
            line.Rank:SetText("")
          end
          local on = index <= lines and (e ~= nil or more) and (e ~= nil)
          line.Who:SetShown(on)
          line.Rank:SetShown(on and not more)
        end
      end
    end
    profs.Empty:SetShown(#groups == 0)
  end

  function view:Refresh()
    if ns.RememberSelf then ns.SafeCall(ns.RememberSelf) end
    local me, list, all = Characters()
    self:RenderHero(me, list)
    self:RenderChars(all)
    self:RenderProfs(me or {}, list)
  end
  function view:OnResize() self:Refresh() end

  return view
end

UI.RegisterTab("account", 7, "TAB_ACCOUNT", Build, true)
