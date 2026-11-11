-- Forever's character statistics (Blizzard's Statistics window, achievement API underneath) for the
-- Hall of Fame. Pure: catalog, parsing of the game's value strings, records, merging and month values.
--   StatRec = { ts, src = "self" | "seen" | "relay", v = { [statID] = number },
--               months = { ["2026-11"] = { ts, v } } }   -- first values seen in each month
-- Labels come from the game at runtime (GetAchievementInfo / GetCategoryInfo), so they are localized.
-- Records keep EVERY statistic the game reports (not only the catalog), zeros left out, so features
-- added later can use data collected before. A missing value in a record counts as 0.
local _, ns = ...

local Stats = {}
ns.Stats = Stats

Stats.MONTHS_KEPT = 3
Stats.LAUNCH_MONTH = "2026-11" -- WoW Forever went live in November 2026
Stats.MAX_VALUES = 500

-- Equipment of Guildy users, read by Guildy itself (Stats.ReadGear) and kept in the same record as
-- the game's statistics under IDs far above Blizzard's, so it is shared, relayed (older Guildy
-- versions keep unknown IDs too) and snapshotted per month without a new message type.
-- COUNT = number of equipped items read. Equipment read nearby (src "seen") without it is from before
-- Guildy checked that every slot had arrived (often only a few items) and is dropped (Stats.CleanRecord);
-- a member's own equipment ("self", "relay") was always complete and is kept.
-- COMMON/POOR = white/grey items, LEGENDARY = legendary or better, EMPTY = empty slots (the off hand
-- next to a two-hander is not empty). Readings of older versions have none of these and count
-- legendaries as epic.
Stats.GEAR = { ILVL = 9900001, EPIC = 9900002, RARE = 9900003, UNCOMMON = 9900004, COUNT = 9900005,
  COMMON = 9900006, POOR = 9900007, EMPTY = 9900008, LEGENDARY = 9900009 }
Stats.GEAR_BASE = 9900000
Stats.GEAR_SLOTS = { 1, 2, 3, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18 } -- no shirt, tabard, ammo
-- Quality per slot: ID GEAR_SLOT_BASE + slot, value quality + 1 (1 grey .. 6 legendary or better) or
-- SLOT_TWO_HANDED for an off hand taken by a two-hander; an empty slot has no value. Readings of older
-- versions have no slot values at all.
Stats.GEAR_SLOT_BASE = 9900100
Stats.SLOT_TWO_HANDED = 7
-- Slots in the character window's order, in groups: armor, rings and trinkets, weapons
Stats.GEAR_SLOT_GROUPS = { { 1, 2, 3, 15, 5, 9, 10, 6, 7, 8 }, { 11, 12, 13, 14 }, { 16, 17, 18 } }

-- Days on which the character was played, counted by its own Guildy (Game/Activity.lua) and kept in
-- the same record, so it is shared and snapshotted per month like the game's statistics. The ID lies
-- above Blizzard's and BELOW GEAR_BASE on purpose: released versions take every ID above GEAR_BASE
-- for equipment (HasGear, CleanGear) and would drop a member's known equipment over it. The counter
-- only grows; a record without it (read nearby, relayed by an older version) keeps the highest known.
Stats.DAYS = 9800001

-- Categories (Blizzard statistic category IDs) and the statistics Guildy tracks, in display order.
-- isLocal = read by Guildy itself, never asked from the game; label = locale key for the name.
Stats.CATALOG = {
  { id = 128, stats = { 107, 1487, 108 } },                           -- victories: creatures, killing blows, critters
  { id = 122, stats = { 60, 594, 112, 114, 115, 113, 321, 918 } },    -- deaths: total, Hogger, drowning, falls, fire, fatigue, instances, 5-man
  { id = 133, stats = { 98, 94 } },                                   -- quests: completed, abandoned
  { id = 140, stats = { 328, 333, 326, 919, 921, 334, 1146, 1148, 1150, 1147, 329, 330, 331, 332 } }, -- wealth
  { id = 14807, stats = { 932 } },                                    -- dungeons entered
  { id = 14821, bosses = true, stats = {} },                          -- end boss kills (Stats.DUNGEONS)
  { id = 145, stats = { 347, 346, 345, 922, 923, 344 } },             -- consumables
  { id = 191, stats = { 1044, 1043, 339, 338, 342 } },                -- gear: need, greed, mounts, pets, epics
  { id = "gear", label = "FAME_GEAR", isLocal = true,
    stats = { Stats.GEAR.ILVL, Stats.GEAR.EPIC, Stats.GEAR.RARE, Stats.GEAR.UNCOMMON } },
  { id = 134, stats = { 349, 353 } },                                 -- travel: flight paths, hearthstone
  { id = 131, stats = { 1042, 1066, 1045, 1065, 1047, 1067 } },       -- social emotes
  { id = 21, stats = { 588, 319, 320, 839 } },                        -- PvP: honorable kills, duels, battlegrounds
  { id = 147, stats = { 931, 1466, 529, 378, 377 } },                 -- reputation: met, friendly/honored/revered/exalted or higher
}

-- Five-player dungeons of Forever by minimum level (as on raidy.app), then the raids; stats = their end
-- boss statistics (Dalaran and the Scarlet Monastery have two, dungeons the game has no statistic for
-- yet none: their name is the locale key FAME_DUNGEON_<KEY>). icon = the game's dungeon picture
-- Interface\LFGFrame\LFGIcon-<icon>; art = an icon of Interface\Icons in its place (the new Forever
-- dungeons have no picture, older clients may lack one). new = added by WoW Forever.
-- Faction (Stats.SetFaction): Blizzard counts an Alliance character's Hall of Thanes end boss as
-- Bazzalan (Ragefire Chasm, 15027). For the Alliance `alliance` adds those statistics to the Hall of
-- Thanes, and Ragefire Chasm (`allianceLost`) stays in the list without a statistic. A Blizzard bug:
-- once fixed (Alliance kills show up in Durgen Dirgehammer, 63573), drop both fields.
-- uncounted = Blizzard does not count this dungeon yet (the Stockade: neither Bazil Thredd nor
-- "dungeons entered" go up); grey with a note until a member has a kill in it.
Stats.ALL_DUNGEONS = {
  { key = "thanes", new = true, min = 13, max = 18, stats = { 63573 }, alliance = { 15027 }, art = "INV_Hammer_09" },
  { key = "ragefire", allianceLost = true, min = 13, max = 18, stats = { 15027 }, icon = "RagefireChasm", art = "Spell_Fire_Incinerate" },
  { key = "lordaeron", new = true, min = 15, max = 20, stats = { 63571 }, art = "INV_Misc_Bone_HumanSkull_01" },
  { key = "wailing", min = 17, max = 24, stats = { 15028 }, icon = "WailingCaverns", art = "Spell_Nature_NullifyPoison" },
  { key = "deadmines", min = 17, max = 26, stats = { 63570 }, icon = "Deadmines", art = "INV_Pick_02" },
  { key = "shadowfang", min = 22, max = 30, stats = { 1092 }, icon = "ShadowfangKeep", art = "Spell_Shadow_SummonFelHunter" },
  { key = "excavation", new = true, min = 24, max = 29, stats = {}, art = "Trade_Archaeology" },
  { key = "blackfathom", min = 24, max = 32, stats = { 6137 }, icon = "BlackfathomDeeps", art = "Spell_Frost_SummonWaterElemental" },
  { key = "stockade", uncounted = true, min = 24, max = 32, stats = { 15029 }, icon = "StormwindStockades", art = "INV_Misc_Key_04" },
  { key = "dalaran", new = true, min = 28, max = 33, stats = { 63572, 63589 }, art = "Spell_Holy_MagicalSentry" },
  { key = "gnomeregan", min = 29, max = 38, stats = { 6140 }, icon = "Gnomeregan", art = "INV_Gizmo_02" },
  { key = "kraul", min = 29, max = 38, stats = { 6139 }, icon = "RazorfenKraul", art = "INV_Misc_Root_01" },
  { key = "scarlet", min = 34, max = 45, stats = { 6786, 1093 }, icon = "ScarletMonastery", art = "INV_Helmet_17" },
  { key = "drowned", new = true, min = 35, max = 40, stats = {}, art = "Spell_Frost_FrostWard" },
  { key = "downs", min = 37, max = 46, stats = { 6141 }, icon = "RazorfenDowns", art = "Spell_Frost_FrostNova" },
  { key = "kroldok", new = true, min = 40, max = 45, stats = {}, art = "Ability_Warrior_WarCry" },
  { key = "uldaman", min = 41, max = 51, stats = { 6142 }, icon = "Uldaman", art = "INV_Misc_StoneTablet_05" },
  { key = "zulfarrak", min = 44, max = 54, stats = { 1094 }, icon = "ZulFarak", art = "INV_Misc_Head_Troll_01" },
  { key = "maraudon", min = 46, max = 55, stats = { 6143 }, icon = "Maraudon", art = "Spell_Nature_EarthBindTotem" },
  { key = "alcaz", new = true, min = 48, max = 53, stats = { 63575 }, art = "Spell_Shadow_Teleport" },
  { key = "sunken", min = 50, max = 60, stats = { 6144 }, icon = "SunkenTemple", art = "INV_Misc_Head_Dragon_Green" },
  { key = "brd", min = 52, max = 60, stats = { 1095 }, icon = "BlackrockDepths", art = "INV_Hammer_Unique_Sulfuras" },
  { key = "blackmaw", new = true, min = 55, max = 60, stats = {}, art = "Ability_Hunter_Pet_Bear" },
  { key = "lbrs", min = 55, max = 60, stats = { 6145 }, icon = "BlackrockSpire", art = "INV_Misc_Head_Orc_01" },
  { key = "ubrs", min = 55, max = 60, stats = { 1096 }, icon = "BlackrockSpire", art = "INV_Misc_Head_Dragon_Black" },
  { key = "diremaul", min = 56, max = 60, stats = { 6146 }, icon = "DireMaul", art = "INV_Misc_Head_Ogre_01" },
  { key = "shaper", new = true, min = 58, max = 60, stats = { 63574 }, art = "INV_Misc_Rune_01" },
  { key = "scholomance", min = 58, max = 60, stats = { 15030 }, icon = "Scholomance", art = "Spell_Shadow_Charm" },
  { key = "stratholme", min = 58, max = 60, stats = { 15031 }, icon = "Stratholme", art = "Spell_Shadow_RaiseDead" },
  { key = "barrow", raid = true, stats = { 63581 }, art = "INV_Misc_Bone_ElfSkull_01" },
  { key = "hyjal", raid = true, stats = { 63580 }, art = "INV_Misc_Herb_02" },
  { key = "onyxia", raid = true, stats = { 1098 }, icon = "Onyxia", art = "INV_Misc_Head_Dragon_01" },
}
for _, category in ipairs(Stats.CATALOG) do
  if category.bosses then
    for _, dungeon in ipairs(Stats.ALL_DUNGEONS) do
      for _, id in ipairs(dungeon.stats) do category.stats[#category.stats + 1] = id end
    end
  end
end

-- The dungeons as the player's faction ("Alliance", "Horde", nil = both) sees them: Stats.DUNGEONS.
-- An entry with statistics added for the faction has merged = true and nameStat = its own statistic
-- (the name), its stats start with the added ones (the ranking of a click); one whose statistic
-- counts elsewhere has lost = true, no stats and nameStat for the name.
local dungeonOf, faction = {}, false
function Stats.SetFaction(new)
  if new == faction then return end
  faction = new
  local list = {}
  for _, def in ipairs(Stats.ALL_DUNGEONS) do
    local alliance = faction == "Alliance"
    if alliance and (def.alliance or def.allianceLost) then
      local copy = {}
      for k, v in pairs(def) do copy[k] = v end
      copy.stats, copy.nameStat = {}, def.stats[1]
      if def.alliance then
        copy.merged = true
        for _, id in ipairs(def.alliance) do copy.stats[#copy.stats + 1] = id end
        for _, id in ipairs(def.stats) do copy.stats[#copy.stats + 1] = id end
      else
        copy.lost = true
      end
      def = copy
    end
    list[#list + 1] = def
  end
  Stats.DUNGEONS = list
  dungeonOf = {}
  for _, dungeon in ipairs(list) do
    for _, id in ipairs(dungeon.stats) do dungeonOf[id] = dungeon end
  end
end
Stats.SetFaction(nil)

-- Level bands of the dungeon table: the dungeons up to and including `last`, the raids last
Stats.DUNGEON_BANDS = { { last = "dalaran" }, { last = "kroldok" }, { last = "stratholme" }, { raid = true } }

-- { {raid, min, max, dungeons = {...}} } in table order; min/max span the band's dungeons
function Stats.DungeonBands()
  local bands, b = {}, 1
  for _, def in ipairs(Stats.DUNGEON_BANDS) do bands[#bands + 1] = { raid = def.raid, dungeons = {} } end
  for _, dungeon in ipairs(Stats.DUNGEONS) do
    if dungeon.raid then b = #bands end
    local band = bands[b]
    band.dungeons[#band.dungeons + 1] = dungeon
    if not dungeon.raid then
      band.min = math.min(band.min or dungeon.min, dungeon.min)
      band.max = math.max(band.max or dungeon.max, dungeon.max)
    end
    if Stats.DUNGEON_BANDS[b].last == dungeon.key then b = b + 1 end
  end
  return bands
end

-- Kill count at a check mark of the dungeon table: nothing for one kill, "99+" from 100 on (the exact
-- number is in the cell's tooltip), so it never gets wider than two digits
function Stats.ShortCount(kills)
  if not kills or kills <= 1 then return "" end
  return kills > 99 and "99+" or tostring(kills)
end

-- Stats.DUNGEONS entry of an end boss statistic
function Stats.DungeonOf(id)
  return dungeonOf[id]
end

-- money = the game shows the value as gold/silver/copper; tenths = stored times ten
Stats.MONEY = { [328] = true, [333] = true, [326] = true, [919] = true, [921] = true, [334] = true, [1146] = true,
  [1147] = true, [1148] = true, [1150] = true, [331] = true, [332] = true, spent = true }
Stats.TENTHS = { [Stats.GEAR.ILVL] = true }

-- Where the gold comes from (adds up to 328, total gold acquired) and where it goes (Forever counts
-- no repairs or training)
Stats.INCOME = { 326, 333, 921, 919 }      -- quests, loot, vendors, auctions
Stats.SPENDING = { 1146, 1148, 1150, 1147 } -- travel, postage, talent resets, barber

-- The pages of the Hall of Fame: big guild totals and title cards (holder = highest value in
-- the chosen period). Special IDs: "bosses" = all end boss kills, "dungeons" = dungeons whose end
-- boss was defeated, "spent" = all gold spending. A title with current = true always shows the current
-- value (a state like the item level), whatever the period.
Stats.PAGES = {
  -- no pets (338) for now: Forever leaves the statistic at "--" however many pets a character has;
  -- back in the headline and as a title card once Blizzard fixes it
  { key = "general", headline = { 107, 98, 60, 349, 339, 342, 1044 }, gear = true, titles = {
    { stat = 107, key = "SLAYER", icon = "Ability_Warrior_SavageBlow" },
    { stat = 98, key = "QUESTER", icon = "INV_Scroll_03" },
    { stat = Stats.GEAR.ILVL, key = "GEAR", icon = "INV_Chest_Plate06", current = true }, -- a state, not growth
    { stat = 339, key = "MOUNTS", icon = "Ability_Mount_RidingHorse" },
    { stat = 60, key = "DEATHS", icon = "Ability_Rogue_FeignDeath" },
    { stat = 347, key = "FOOD", icon = "INV_Misc_Food_14" },
    { stat = 112, key = "DROWNED", icon = "Spell_Shadow_DemonBreath" },
    { stat = 114, key = "FALLS", icon = "Spell_Magic_FeatherFall" },
    { stat = 594, key = "HOGGER", icon = "INV_Misc_MonsterClaw_04" },
    { stat = 1042, key = "HUGS", icon = "Spell_Holy_Heal" },
    { stat = 349, key = "TRAVEL", icon = "INV_Misc_Map_01" },
    { stat = 1044, key = "NEED", icon = "INV_Misc_Gem_Pearl_04" },
    { stat = 1487, key = "BLOWS", icon = "Ability_BackStab" },
  } },
  { key = "economy", headline = { 328, "spent", 329, 330 }, flows = true, titles = {
    { stat = 328, key = "GOLD", icon = "INV_Misc_Coin_02" },
    { stat = 329, key = "AUCTION", icon = "INV_Misc_Bag_10" },
    { stat = 330, key = "BUYER", icon = "INV_Misc_Note_02" },
    { stat = 921, key = "VENDOR", icon = "INV_Misc_Coin_04" },
    { stat = 333, key = "LOOTER", icon = "INV_Misc_Bag_11" },
    { stat = 1146, key = "FLYER", icon = "Ability_Hunter_EagleEye" },
    { stat = 1148, key = "POSTAGE", icon = "INV_Letter_15" },
    { stat = 1150, key = "RESPEC", icon = "INV_Misc_Book_09" },
    { stat = 1147, key = "BARBER", icon = "INV_Misc_Comb_02" },
  } },
  { key = "dungeons", headline = { "bosses", "dungeons", 932, 918 }, dungeons = true, titles = {
    { stat = "dungeons", key = "VETERAN", icon = "INV_Misc_Head_Dragon_01" },
    { stat = "bosses", key = "BOSSES", icon = "Ability_Warrior_DecisiveStrike" },
    { stat = 932, key = "DUNGEONS", icon = "INV_Misc_Key_03" },
    { stat = 918, key = "FODDER", icon = "Spell_Shadow_DeathScream" },
  } },
  { key = "reputation", headline = { 931, 1466, 529, 378, 377 }, reputation = true, titles = {
    { stat = 377, key = "EXALTED", icon = "INV_Crown_01" },
    { stat = 378, key = "REVERED", icon = "INV_Misc_Ribbon_01" },
    { stat = 529, key = "HONORED", icon = "Spell_Holy_SealOfSalvation" },
    { stat = 931, key = "FACTIONS", icon = "INV_Misc_Map_01" },
  } },
  -- honorable kills, duels won and lost, battlegrounds played. No killing blows (1487): they count
  -- creatures too, tens of thousands against a hundred honorable kills.
  { key = "pvp", headline = { 588, 319, 320, 839 }, pvp = true, titles = {
    { stat = 588, key = "HEADHUNTER", icon = "INV_BannerPVP_02" },
    { stat = 319, key = "DUELIST", icon = "Ability_DualWield" },
    { stat = 839, key = "FRONTLINE", icon = "Ability_Warrior_Challange" },
    { stat = 320, key = "PUNCHBAG", icon = "Spell_Holy_SealOfSacrifice" },
  } },
}

-- The tiles and title cards on top of a page are the player's choice (settings.fameTiles[page.key]
-- and settings.fameCards[page.key], Guildy's options)
Stats.MAX_TILES = 7
Stats.MAX_CARDS = 8

-- What a page's tiles can show: its default headline first, then the statistics of its title cards,
-- then the same of every other page, then every other statistic Guildy tracks (Stats.CATALOG, the
-- end boss kills included). No states like the item level and the worn items per quality (the
-- catalog's local category): a guild total of them says nothing.
function Stats.TileChoices(page)
  local list, seen = {}, {}
  local function Add(from)
    for _, id in ipairs(from.headline) do
      if not seen[id] then list[#list + 1] = id; seen[id] = true end
    end
    for _, fame in ipairs(from.titles) do
      if not fame.current and not seen[fame.stat] then list[#list + 1] = fame.stat; seen[fame.stat] = true end
    end
  end
  Add(page)
  for _, other in ipairs(Stats.PAGES) do
    if other ~= page then Add(other) end
  end
  for _, category in ipairs(Stats.CATALOG) do
    if not category.isLocal then
      for _, id in ipairs(category.stats) do
        if not seen[id] then list[#list + 1] = id; seen[id] = true end
      end
    end
  end
  return list
end

-- The tiles of a page for a chosen list of statistics: those of them the page offers, in the chosen
-- order, each once, at most Stats.MAX_TILES; the default headline when nothing valid is chosen.
function Stats.Headline(page, chosen)
  if type(chosen) ~= "table" then return page.headline end
  local offered = {}
  for _, id in ipairs(Stats.TileChoices(page)) do offered[id] = true end
  local list = {}
  for _, id in ipairs(chosen) do
    if offered[id] and #list < Stats.MAX_TILES then
      list[#list + 1] = id
      offered[id] = nil
    end
  end
  return #list > 0 and list or page.headline
end

-- The title cards a page can show: its own titles first, then those of every other page
function Stats.TitleChoices(page)
  local list = {}
  for _, fame in ipairs(page.titles) do list[#list + 1] = fame end
  for _, other in ipairs(Stats.PAGES) do
    if other ~= page then
      for _, fame in ipairs(other.titles) do list[#list + 1] = fame end
    end
  end
  return list
end

-- The title cards of a page for a chosen list of title keys ("SLAYER", ...): those titles in the chosen
-- order, each once, at most Stats.MAX_CARDS; the page's own titles when nothing valid is chosen.
function Stats.Titles(page, chosen)
  if type(chosen) ~= "table" then return page.titles end
  local byKey = {}
  for _, fame in ipairs(Stats.TitleChoices(page)) do byKey[fame.key] = fame end
  local list = {}
  for _, key in ipairs(chosen) do
    if byKey[key] and #list < Stats.MAX_CARDS then
      list[#list + 1] = byKey[key]
      byKey[key] = nil
    end
  end
  return #list > 0 and list or page.titles
end

local wanted
-- { [statID] = true } for every statistic Guildy asks the game for
function Stats.Wanted()
  if not wanted then
    wanted = {}
    for _, category in ipairs(Stats.CATALOG) do
      if not category.isLocal then
        for _, id in ipairs(category.stats) do wanted[id] = true end
      end
    end
  end
  return wanted
end

function Stats.Bosses()
  for _, category in ipairs(Stats.CATALOG) do
    if category.bosses then return category.stats end
  end
  return {}
end

-- Own equipment: { [GEAR id] = value } (average item level times ten, count of items per quality,
-- empty slots; zeros left out), {} with nothing equipped, or nil while an item's info is not loaded
-- yet. getLink(slot) -> item link; getInfo(link) -> GetItemInfo's returns (quality 3rd, item level
-- 4th, equip location 9th).
local QUALITY_IDS = { [0] = "POOR", [1] = "COMMON", [2] = "UNCOMMON", [3] = "RARE", [4] = "EPIC", [5] = "LEGENDARY" }
function Stats.ReadGear(getLink, getInfo)
  local levels, count, empty, twoHanded = 0, 0, 0, false
  local qualities = { [0] = 0, [1] = 0, [2] = 0, [3] = 0, [4] = 0, [5] = 0 }
  local slots = {}
  local emptyOffHand = false
  for _, slot in ipairs(Stats.GEAR_SLOTS) do
    local link = getLink(slot)
    if link then
      local _, _, quality, level, _, _, _, _, equipLoc = getInfo(link)
      if type(quality) ~= "number" or type(level) ~= "number" then return nil end
      levels, count = levels + level, count + 1
      local q = math.max(0, math.min(quality, 5))
      qualities[q] = qualities[q] + 1
      slots[slot] = q + 1
      if slot == 16 and equipLoc == "INVTYPE_2HWEAPON" then twoHanded = true end
    elseif slot == 17 then
      emptyOffHand = true
    else
      empty = empty + 1
    end
  end
  if emptyOffHand then
    if twoHanded then slots[17] = Stats.SLOT_TWO_HANDED else empty = empty + 1 end
  end
  local values = {}
  if count > 0 then
    values[Stats.GEAR.ILVL] = math.floor(levels / count * 10 + 0.5)
    values[Stats.GEAR.COUNT] = count
    if empty > 0 then values[Stats.GEAR.EMPTY] = empty end
    for slot, value in pairs(slots) do values[Stats.GEAR_SLOT_BASE + slot] = value end
  end
  for q, key in pairs(QUALITY_IDS) do
    if qualities[q] > 0 then values[Stats.GEAR[key]] = qualities[q] end
  end
  return values
end

-- Quality per slot in the character window's order: { { value per slot }, ... } per group (value as
-- in GEAR_SLOT_BASE, false for an empty slot), or nil for a reading without slot values
function Stats.GearSlots(values)
  local any = false
  for _, slot in ipairs(Stats.GEAR_SLOTS) do
    if values[Stats.GEAR_SLOT_BASE + slot] then any = true end
  end
  if not any then return nil end
  local groups = {}
  for g, group in ipairs(Stats.GEAR_SLOT_GROUPS) do
    groups[g] = {}
    for i, slot in ipairs(group) do groups[g][i] = values[Stats.GEAR_SLOT_BASE + slot] or false end
  end
  return groups
end

-- Removes equipment values without an item count (incomplete reads of older versions); returns values
function Stats.CleanGear(values)
  if type(values) ~= "table" or values[Stats.GEAR.COUNT] then return values end
  for id in pairs(values) do
    if type(id) == "number" and id > Stats.GEAR_BASE then values[id] = nil end
  end
  return values
end

-- CleanGear on a whole StatRec read nearby (current values and month snapshots)
function Stats.CleanRecord(rec)
  if type(rec) ~= "table" or rec.src ~= "seen" then return end
  Stats.CleanGear(rec.v)
  for _, snap in pairs(type(rec.months) == "table" and rec.months or {}) do
    if type(snap) == "table" then Stats.CleanGear(snap.v) end
  end
end

function Stats.HasGear(values)
  for id in pairs(values or {}) do
    if type(id) == "number" and id > Stats.GEAR_BASE then return true end
  end
  return false
end

-- Reputation statistics count factions at a standing "or higher"
Stats.REP = { MET = 931, FRIENDLY = 1466, HONORED = 529, REVERED = 378, EXALTED = 377 }

-- Factions at exactly each standing: { exalted, revered, honored, friendly }
function Stats.RepTiers(values)
  local R = Stats.REP
  local exalted = values[R.EXALTED] or 0
  local revered = values[R.REVERED] or 0
  local honored = values[R.HONORED] or 0
  local friendly = values[R.FRIENDLY] or 0
  return { exalted = exalted, revered = math.max(0, revered - exalted), honored = math.max(0, honored - revered),
    friendly = math.max(0, friendly - honored) }
end

-- How the average item level compares to the character level: "good", "ok" or "behind"
function Stats.GearRating(itemLevel, level)
  if not itemLevel or not level or level < 10 then return "ok" end
  if itemLevel >= level then return "good" end
  if itemLevel < level - 7 then return "behind" end
  return "ok"
end

local function Digits(text)
  return tonumber((text:gsub("[%.,%s]", "")))
end

-- Number from the game's statistic text: "1298", "672 (Humanoid)", "--", or money with coin icons
-- ("6|T...GoldIcon...|t 88|T...SilverIcon...|t 93|T...CopperIcon...|t"; money is returned in copper).
function Stats.Parse(raw)
  if type(raw) == "number" then return raw end
  if type(raw) ~= "string" then return 0 end
  if raw:find("Icon", 1, true) then
    local total = 0
    for amount, coin in raw:gmatch("([%d%.,]+)%s*|T[^|]-UI%-(%a+)Icon") do
      local n = Digits(amount) or 0
      if coin == "Gold" then total = total + n * 10000
      elseif coin == "Silver" then total = total + n * 100
      elseif coin == "Copper" then total = total + n end
    end
    return total
  end
  local number = raw:match("^%s*([%d%.,]+)")
  return number and Digits(number) or 0
end

-- "2026-11" for a timestamp; date is os.date or WoW's date
function Stats.MonthKey(ts, date)
  date = date or os.date
  return date("%Y-%m", ts)
end

-- The month before "2026-11" -> "2026-10"
function Stats.PreviousMonth(key)
  local year, month = key:match("^(%d+)%-(%d+)$")
  year, month = tonumber(year), tonumber(month)
  if not year then return nil end
  month = month - 1
  if month == 0 then year, month = year - 1, 12 end
  return string.format("%04d-%02d", year, month)
end

local function Copy(values)
  local out = {}
  for id, value in pairs(values) do out[id] = value end
  return out
end

local function PruneMonths(months)
  local keys = {}
  for key in pairs(months) do keys[#keys + 1] = key end
  table.sort(keys)
  for i = 1, #keys - Stats.MONTHS_KEPT do months[keys[i]] = nil end
end

local PRIORITY = { self = 3, seen = 2, relay = 1 }

-- The days counter never goes down: the highest of what the record had and what comes in stays
local function KeepDays(rec, before, incoming)
  local days = math.max(before or 0, incoming or 0, rec.v and rec.v[Stats.DAYS] or 0)
  if days > 0 and rec.v then rec.v[Stats.DAYS] = days end
end

-- Stores newly read values (own or read nearby) for a member. Returns true when anything changed.
function Stats.Update(member, values, ts, src, date)
  local rec = member.stats
  if type(rec) ~= "table" then
    rec = { months = {} }
    member.stats = rec
  end
  rec.months = type(rec.months) == "table" and rec.months or {}
  local month = Stats.MonthKey(ts, date)
  local changed = false
  values = Copy(values)
  if src == "seen" then Stats.CleanGear(values) end
  Stats.CleanRecord(rec)
  local daysBefore = rec.v and rec.v[Stats.DAYS]
  if not rec.ts or ts > rec.ts or (ts == rec.ts and (PRIORITY[src] or 0) > (PRIORITY[rec.src] or 0)) then
    local new = Copy(values)
    -- a reading without equipment (read nearby, item info not loaded) keeps the last known equipment
    if not Stats.HasGear(values) then
      for id, value in pairs(rec.v or {}) do
        if id > Stats.GEAR_BASE then new[id] = value end
      end
    end
    rec.ts, rec.src, rec.v = ts, src, new
    changed = true
  end
  KeepDays(rec, daysBefore, values[Stats.DAYS])
  if not rec.months[month] then
    rec.months[month] = { ts = ts, v = Copy(values) }
    changed = true
  elseif Stats.HasGear(values) and not Stats.HasGear(rec.months[month].v) then
    -- equipment first seen this month: it is the month's starting point
    for id, value in pairs(values) do
      if id > Stats.GEAR_BASE then rec.months[month].v[id] = value end
    end
    changed = true
  end
  PruneMonths(rec.months)
  return changed
end

local function ValidValues(raw)
  if type(raw) ~= "table" then return nil end
  local values, count = {}, 0
  for id, value in pairs(raw) do
    id = tonumber(id)
    if id and id > 0 and id < 1e7 and type(value) == "number" and value > 0 and value < 1e12 then
      values[id] = math.floor(value)
      count = count + 1
      if count > Stats.MAX_VALUES then return nil end
    end
  end
  return values
end

-- Checks a record from the addon channel; returns a clean StatRec or nil
function Stats.Validate(raw)
  if type(raw) ~= "table" or type(raw.ts) ~= "number" then return nil end
  local values = ValidValues(raw.v)
  if not values then return nil end
  local rec = { ts = raw.ts, src = PRIORITY[raw.src] and raw.src or "relay", v = values, months = {} }
  if type(raw.m) == "table" then
    for month, snap in pairs(raw.m) do
      if type(month) == "string" and month:match("^%d%d%d%d%-%d%d$") and type(snap) == "table" and type(snap.ts) == "number" then
        local snapValues = ValidValues(snap.v)
        if snapValues then rec.months[month] = { ts = snap.ts, v = snapValues } end
      end
    end
  end
  Stats.CleanRecord(rec)
  return rec
end

-- Merges an incoming StatRec into member: newer current values win; per month the earliest snapshot.
function Stats.Merge(member, incoming)
  local rec = member.stats
  if type(rec) ~= "table" then
    rec = { months = {} }
    member.stats = rec
  end
  rec.months = type(rec.months) == "table" and rec.months or {}
  Stats.CleanRecord(rec)
  local changed = false
  local daysBefore = rec.v and rec.v[Stats.DAYS]
  if not rec.ts or incoming.ts > rec.ts
    or (incoming.ts == rec.ts and (PRIORITY[incoming.src] or 0) > (PRIORITY[rec.src] or 0)) then
    local values = Copy(incoming.v)
    if not Stats.HasGear(values) then
      for id, value in pairs(rec.v or {}) do
        if id > Stats.GEAR_BASE then values[id] = value end
      end
    end
    rec.ts, rec.src, rec.v = incoming.ts, incoming.src, values
    changed = true
  end
  KeepDays(rec, daysBefore, incoming.v and incoming.v[Stats.DAYS])
  for month, snap in pairs(incoming.months or {}) do
    local mine = rec.months[month]
    if not mine or snap.ts < mine.ts then
      rec.months[month] = { ts = snap.ts, v = Copy(snap.v) }
      changed = true
    end
  end
  PruneMonths(rec.months)
  return changed
end

-- The record as sent on the channel (string keys for JSON)
function Stats.Wire(rec)
  local function Keys(values)
    local out = {}
    for id, value in pairs(values or {}) do out[tostring(id)] = value end
    return out
  end
  local months = {}
  for month, snap in pairs(rec.months or {}) do months[month] = { ts = snap.ts, v = Keys(snap.v) } end
  return { ts = rec.ts, src = rec.src, v = Keys(rec.v), m = months }
end

-- { [nameKey] = ts } of the members with statistics
function Stats.Digest(guild)
  local digest = {}
  for key, member in pairs(guild.members or {}) do
    if type(member.stats) == "table" and member.stats.ts then digest[key] = member.stats.ts end
  end
  return digest
end

local function Sum(values, ids)
  local sum = 0
  for _, id in ipairs(ids) do sum = sum + (values[id] or 0) end
  return sum
end

local function StatValue(values, id)
  if not values then return nil end
  if id == "bosses" then return Sum(values, Stats.Bosses()) end
  if id == "raidBosses" or id == "dungeonBosses" then
    local sum = 0
    for _, dungeon in ipairs(Stats.DUNGEONS) do
      if (dungeon.raid and true or false) == (id == "raidBosses") then sum = sum + Sum(values, dungeon.stats) end
    end
    return sum
  end
  if id == "spent" then return Sum(values, Stats.SPENDING) end
  if id == "dungeons" then
    local count = 0
    for _, dungeon in ipairs(Stats.DUNGEONS) do
      if Sum(values, dungeon.stats) > 0 then count = count + 1 end
    end
    return count
  end
  if type(id) == "number" and id > Stats.GEAR_BASE then return values[id] end -- unknown, not 0
  return values[id] or 0
end

-- Value of statistic id (or a special ID of Stats.PAGES) for a member record in a period:
--   "all"   = the current value
--   "month" = growth in the month of now (since the first values seen this month)
--   "last"  = growth in the month before (between the first values of both months)
-- Returns value (or nil when unknown) and the timestamp the period's count starts at.
function Stats.Value(rec, id, period, now, date)
  if type(rec) ~= "table" or not rec.v then return nil end
  local current = StatValue(rec.v, id)
  if period == "all" or not period then return current, nil end
  local months = rec.months or {}
  local this = Stats.MonthKey(now, date)
  if period == "month" then
    local start, ts = Stats.MonthStart(months, this, id)
    if not current or not start then return nil end
    return math.max(0, current - start), ts
  end
  local from, ts = Stats.MonthStart(months, Stats.PreviousMonth(this), id)
  local after = months[this]
  local to = after and StatValue(after.v, id)
  if not from or not to then return nil end
  return math.max(0, to - from), ts
end

-- Value of id at the start of month and the timestamp it was read: the first values seen in the
-- month; in Forever's launch month 0, since nothing happened before the launch (Guildy's first
-- reading came days later). Equipment always counts from the first reading.
function Stats.MonthStart(months, month, id)
  local snap = months[month]
  local gear = type(id) == "number" and id > Stats.GEAR_BASE
  if month == Stats.LAUNCH_MONTH and not gear then return 0, snap and snap.ts end
  if not snap then return nil end
  return StatValue(snap.v, id), snap.ts
end

-- Ranking of a statistic over records { {key, name, rec} }: { {key, name, value, rec} } sorted desc
function Stats.Ranking(entries, id, period, now, date)
  local list = {}
  for _, entry in ipairs(entries) do
    local value = Stats.Value(entry.rec, id, period, now, date)
    if value then list[#list + 1] = { key = entry.key, name = entry.name, value = value, rec = entry.rec } end
  end
  table.sort(list, function(a, b)
    if a.value ~= b.value then return a.value > b.value end
    return a.name < b.name
  end)
  return list
end

-- Sum over a ranking
function Stats.Total(ranking)
  local sum = 0
  for _, row in ipairs(ranking) do sum = sum + row.value end
  return sum
end
