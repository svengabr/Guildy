-- Profession data of the player's own characters (skill list on login, recipes when a profession
-- window is open) and of others from profession links in chat. Writes into the guild's member records
-- and fires ns "PROFS"; own changes are handed to Sync.
local _, ns = ...
local P = ns.Professions

local TradeSkill = {}
ns.TradeSkill = TradeSkill

local nameToSkill   -- localized profession name (lowercase) -> skill line
local recipeNames = {}

local function SpellName(id)
  if C_Spell and C_Spell.GetSpellName then return ns.Try(C_Spell.GetSpellName, id) end
  local getInfo = rawget(_G, "GetSpellInfo")
  return getInfo and (ns.Try(getInfo, id)) or nil
end

local function SkillByName(name)
  if type(name) ~= "string" then return nil end
  if not nameToSkill then
    nameToSkill = {}
    for skillLine in pairs(P.SKILL_LINES) do
      local display = C_TradeSkillUI and C_TradeSkillUI.GetTradeSkillDisplayName
        and ns.Try(C_TradeSkillUI.GetTradeSkillDisplayName, skillLine)
      if display and display ~= "" then nameToSkill[ns.Names.Lower(display)] = skillLine end
    end
    for spell, skillLine in pairs(P.SPELL_TO_SKILL) do
      local display = SpellName(spell)
      if display and display ~= "" and not nameToSkill[ns.Names.Lower(display)] then
        nameToSkill[ns.Names.Lower(display)] = skillLine
      end
    end
    for skillLine, key in pairs(P.SKILL_LINES) do
      local localized = ns.L["PROF_" .. key]
      if localized then nameToSkill[ns.Names.Lower(localized)] = nameToSkill[ns.Names.Lower(localized)] or skillLine end
    end
  end
  return nameToSkill[ns.Names.Lower(name)]
end
TradeSkill.SkillByName = SkillByName

-- Recipe (spell) name, cached; nil while unknown
function TradeSkill.RecipeName(spellID)
  local name = recipeNames[spellID]
  if name == nil then
    name = SpellName(spellID) or false
    if name then recipeNames[spellID] = name end
  end
  return name or nil
end

-- Icons of what recipes make, as the open recipe book shows them (the recipe spells themselves often only
-- have a stand-in icon). Kept per account in GuildyDB.recipeIcons, not shared: spellID -> icon
local function RememberIcon(spellID, icon)
  local db = ns.DB()
  if not (db and spellID) or ns.IsSecret(icon) then return end
  if type(icon) ~= "number" and type(icon) ~= "string" then return end
  db.recipeIcons = db.recipeIcons or {}
  db.recipeIcons[spellID] = icon
end

-- Icon of what a recipe makes: from a recipe book read earlier, else what the client knows about the
-- made item; nil when neither is known
function TradeSkill.RecipeIcon(spellID)
  local db = ns.DB()
  local known = db and db.recipeIcons and db.recipeIcons[spellID]
  if known then return known end
  local output = C_TradeSkillUI and rawget(C_TradeSkillUI, "GetRecipeOutputItemData")
  local data = output and ns.Try(output, spellID)
  local itemID = type(data) == "table" and data.itemID
  if not itemID then return nil end
  local getIcon = (C_Item and C_Item.GetItemIconByID) or rawget(_G, "GetItemIcon")
  local icon = getIcon and ns.Try(getIcon, itemID)
  if icon then RememberIcon(spellID, icon) end
  return icon
end

function TradeSkill.Name(skillLine)
  local key = P.SKILL_LINES[skillLine]
  return key and ns.L["PROF_" .. key] or tostring(skillLine)
end

local function OwnMember()
  local guild = ns.GuildData()
  if not guild then return nil end
  local db = ns.DB()
  local me = ns.PlayerName()
  db.ownChars = db.ownChars or {}
  local key = ns.Names.Key(me)
  db.ownChars[key] = db.ownChars[key] or true
  return ns.Store.Member(guild, me)
end

local function SameList(a, b)
  if (a == nil) ~= (b == nil) then return false end
  if not a then return true end
  if #a ~= #b then return false end
  for i = 1, #a do
    if a[i] ~= b[i] then return false end
  end
  return true
end

-- Whose profession window is open: nil = the player's own, else the roster member whose profession
-- link the player clicked (Blizzard opens their recipe book read-only)
local scanTarget
local pendingLink -- {guid, skillLine, at} of the last clicked profession link

local function IsOwnChar(m)
  local db = ns.DB()
  return m and db and db.ownChars and db.ownChars[m.key] or (m and ns.Names.Same(m.name, ns.PlayerName())) or false
end

-- Stores scanned data for a profession when something changed; recipes nil = unknown (keep old list)
local function StoreOwn(skillLine, rank, max, recipes)
  if not skillLine then return end
  local member
  if scanTarget then
    local guild = ns.GuildData()
    member = guild and ns.Store.Member(guild, scanTarget.name)
  else
    member = OwnMember()
  end
  if not member then return end
  if recipes then table.sort(recipes) end
  local existing = member.profs[skillLine]
  if existing and existing.rank == rank and existing.max == max and (recipes == nil or SameList(existing.recipes, recipes)) then
    return
  end
  local src = scanTarget and "link" or "scan"
  local record = P.ValidateRecord({ ts = ns.Now(), src = src, rank = rank, max = max, recipes = recipes })
  if record and P.Merge(member, skillLine, record, { isOwnChar = not scanTarget }) then
    ns.Fire("PROFS")
    if ns.Sync then
      if scanTarget then ns.Sync.Share(scanTarget.key) else ns.Sync.OwnChanged() end
    end
  end
end

-- SetItemRef post-hook: remember a clicked profession link, its window opens right after
function TradeSkill.OnLinkClicked(link)
  if ns.IsSecret(link) or type(link) ~= "string" or link:sub(1, 6) ~= "trade:" then return end
  local parsed = P.ParseTradeLinks("|H" .. link .. "|h")[1]
  if parsed and parsed.guid then pendingLink = { guid = parsed.guid, skillLine = parsed.skillLine, at = GetTime() } end
end

-- TRADE_SKILL_CLOSE: a later own window must not be taken for the linked one
function TradeSkill.OnClose()
  pendingLink = nil
end

-- Decides whose window is open. Returns false when it should not be scanned at all.
local function ResolveTarget()
  scanTarget = nil
  local isLinked, linkedName
  local linkedFn = (C_TradeSkillUI and rawget(C_TradeSkillUI, "IsTradeSkillLinked")) or rawget(_G, "IsTradeSkillLinked")
  if linkedFn then
    isLinked, linkedName = ns.Try(linkedFn)
  end
  local pending = pendingLink and GetTime() - pendingLink.at < 30 and pendingLink or nil
  if linkedFn and not isLinked then return true end -- own window (the client says so)
  if not linkedFn and not pending then return true end -- no way to tell: only a clicked link counts as foreign
  local m = (pending and ns.Roster.FindByGuid(pending.guid))
    or (type(linkedName) == "string" and not ns.IsSecret(linkedName) and ns.Roster.Find(linkedName)) or nil
  if not m then return false end -- someone outside the guild
  if not IsOwnChar(m) then scanTarget = m end
  return true
end

-- Skill levels of all professions of the current character (no recipes)
function TradeSkill.ScanSkills()
  local getProfessions, getInfo = rawget(_G, "GetProfessions"), rawget(_G, "GetProfessionInfo")
  local seen = false
  if getProfessions and getInfo then
    for _, index in ipairs({ ns.Try(getProfessions) }) do
      if index then
        local name, _, rank, max, _, _, skillLine = ns.Try(getInfo, index)
        skillLine = (skillLine and P.SKILL_LINES[skillLine]) and skillLine or SkillByName(name)
        if skillLine then
          seen = true
          StoreOwn(skillLine, rank, max, nil)
        end
      end
    end
  end
  if seen then return end
  local count = ns.Try(rawget(_G, "GetNumSkillLines")) or 0
  local getLine = rawget(_G, "GetSkillLineInfo")
  for i = 1, count do
    local name, isHeader, _, rank, _, _, max = ns.Try(getLine, i)
    if not isHeader then
      local skillLine = SkillByName(name)
      if skillLine then StoreOwn(skillLine, rank, max, nil) end
    end
  end
end

local function IdFromLink(link)
  if type(link) ~= "string" then return nil end
  return tonumber(link:match("enchant:(%d+)")) or tonumber(link:match("spell:(%d+)"))
end

-- The open profession window (legacy trade skill frame, craft frame, or the C_TradeSkillUI one)
function TradeSkill.ScanOpen()
  TradeSkill.lastScan = { path = "none" }
  if C_TradeSkillUI and C_TradeSkillUI.IsNPCCrafting and ns.Try(C_TradeSkillUI.IsNPCCrafting) then return end
  if ns.Try(rawget(_G, "IsTradeSkillGuild")) then return end
  if not ResolveTarget() then
    TradeSkill.lastScan = { path = "linked window of someone outside the guild" }
    return
  end

  local lineName, rank, max = ns.Try(rawget(_G, "GetTradeSkillLine"))
  if lineName and lineName ~= "UNKNOWN" then
    local recipes = {}
    for i = 1, ns.Try(rawget(_G, "GetNumTradeSkills")) or 0 do
      local _, kind = ns.Try(rawget(_G, "GetTradeSkillInfo"), i)
      if kind and kind ~= "header" and kind ~= "subheader" then
        local id = IdFromLink(ns.Try(rawget(_G, "GetTradeSkillRecipeLink"), i))
        if id then
          recipes[#recipes + 1] = id
          RememberIcon(id, ns.Try(rawget(_G, "GetTradeSkillIcon"), i))
        end
      end
    end
    TradeSkill.lastScan = { path = "GetTradeSkillLine", name = lineName, skillLine = SkillByName(lineName), rank = rank,
      entries = ns.Try(rawget(_G, "GetNumTradeSkills")) or 0, recipes = #recipes,
      hasRecipeLink = rawget(_G, "GetTradeSkillRecipeLink") ~= nil, sample = ns.Try(rawget(_G, "GetTradeSkillRecipeLink"), 2) }
    if #recipes > 0 then StoreOwn(SkillByName(lineName), rank, max, recipes) end
  end

  local craftName, craftRank, craftMax = ns.Try(rawget(_G, "GetCraftDisplaySkillLine"))
  if craftName then
    local recipes = {}
    for i = 1, ns.Try(rawget(_G, "GetNumCrafts")) or 0 do
      local _, _, kind = ns.Try(rawget(_G, "GetCraftInfo"), i)
      if kind and kind ~= "header" then
        local id = IdFromLink(ns.Try(rawget(_G, "GetCraftRecipeLink"), i))
        if id then
          recipes[#recipes + 1] = id
          RememberIcon(id, ns.Try(rawget(_G, "GetCraftIcon"), i))
        end
      end
    end
    TradeSkill.lastScan = { path = "GetCraftDisplaySkillLine", name = craftName, skillLine = SkillByName(craftName),
      rank = craftRank, entries = ns.Try(rawget(_G, "GetNumCrafts")) or 0, recipes = #recipes,
      hasRecipeLink = rawget(_G, "GetCraftRecipeLink") ~= nil, sample = ns.Try(rawget(_G, "GetCraftRecipeLink"), 1) }
    if #recipes > 0 then StoreOwn(SkillByName(craftName), craftRank, craftMax, recipes) end
  end

  local getAll = C_TradeSkillUI and rawget(C_TradeSkillUI, "GetAllRecipeIDs")
  local info = C_TradeSkillUI and C_TradeSkillUI.GetBaseProfessionInfo and ns.Try(C_TradeSkillUI.GetBaseProfessionInfo)
  if getAll and type(info) == "table" and info.professionID then
    local skillLine = P.SKILL_LINES[info.professionID] and info.professionID or SkillByName(info.professionName)
    local recipes = {}
    for _, id in ipairs(ns.Try(getAll) or {}) do
      local recipe = ns.Try(C_TradeSkillUI.GetRecipeInfo, id)
      if recipe and recipe.learned then
        recipes[#recipes + 1] = id
        RememberIcon(id, recipe.icon)
      end
    end
    TradeSkill.lastScan = { path = "C_TradeSkillUI", name = info.professionName, skillLine = skillLine,
      rank = info.skillLevel, recipes = #recipes }
    if skillLine and #recipes > 0 then StoreOwn(skillLine, info.skillLevel, info.maxSkillLevel, recipes) end
  end
  TradeSkill.lastScan.target = scanTarget and scanTarget.name or "own"
  TradeSkill.lastScan.at = GetTime()
  if ns.Harvest then
    if scanTarget then ns.Harvest.OnScanned(TradeSkill.lastScan) else ns.Harvest.OnOwnWindow() end
  end
end

-- Profession links in chat: "I can do this" for the linking member (or the guid in the link)
function TradeSkill.OnChatMessage(text, sender, guid)
  if ns.AnySecret(text, sender, guid) or type(text) ~= "string" or not text:find("|Htrade:", 1, true) then return end
  local guild = ns.GuildData()
  if not guild then return end
  local db = ns.DB()
  local changed = false
  for _, link in ipairs(P.ParseTradeLinks(text)) do
    local member = ns.Roster.FindByGuid(link.guid) or (not link.guid and ns.Roster.Find(sender))
      or (link.guid == guid and ns.Roster.Find(sender))
    if member and not (db.ownChars and db.ownChars[member.key]) then
      local record = P.ValidateRecord({ ts = ns.Now(), src = "link", rank = link.rank, max = link.max })
      if record and P.Merge(ns.Store.Member(guild, member.name), link.skillLine, record) then changed = true end
    end
  end
  if changed then ns.Fire("PROFS") end
end

-- Profession set of a roster member (for census and filters)
function TradeSkill.ProfsOf(m)
  local guild = ns.GuildData()
  local record = guild and guild.members[m.key]
  return P.SetOf(record)
end

function TradeSkill.Record(m)
  local guild = ns.GuildData()
  return guild and guild.members[m.key] or nil
end

-- All known recipes as search entries { {memberName, memberKey, skillLine, spellID, recipeName, online} }
function TradeSkill.RecipeEntries()
  local guild = ns.GuildData()
  local entries = {}
  if not guild then return entries end
  for key, record in pairs(guild.members) do
    local m = ns.Roster.Find(key)
    for skillLine, prof in pairs(record.profs or {}) do
      for _, spellID in ipairs(prof.recipes or {}) do
        local name = TradeSkill.RecipeName(spellID)
        if name then
          entries[#entries + 1] = { memberName = record.name, memberKey = key, skillLine = skillLine,
            spellID = spellID, recipeName = name, online = m and m.online or false }
        end
      end
    end
  end
  return entries
end

-- Spell a profession link carries where it isn't the lowest rank spell: mining's recipe book is Smelting
local LINK_SPELL = { [186] = 2656 }

-- First profession spell of a skill line (the spell a profession link carries)
local function ProfessionSpell(skillLine)
  if LINK_SPELL[skillLine] then return LINK_SPELL[skillLine] end
  local best
  for spell, line in pairs(P.SPELL_TO_SKILL) do
    if line == skillLine and (not best or spell < best) then best = spell end
  end
  return best
end

-- Builds the profession link of a roster member: "trade:<guid>:<spellID>:<skillLine>"
function TradeSkill.BuildLink(m, skillLine)
  local spell = ProfessionSpell(skillLine)
  if not (m and m.guid and spell) then return nil end
  return ("trade:%s:%d:%d"):format(m.guid, spell, skillLine)
end

-- Whether Blizzard may show this member's recipe book now: online (it opens only when they are on the
-- player's current server, which no data tells beforehand)
function TradeSkill.CanOpenBook(m)
  return m and m.online and m.guid and true or false
end

-- Opens a member's recipe book in Blizzard's window (it gets stored like a clicked link)
function TradeSkill.OpenBook(m, skillLine)
  local link = TradeSkill.BuildLink(m, skillLine)
  local setItemRef = rawget(_G, "SetItemRef")
  if not (link and setItemRef) then return false end
  return (pcall(setItemRef, link, "[" .. TradeSkill.Name(skillLine) .. "]", "LeftButton"))
end

-- /guildy probe <name> <profession>: opens a self-built profession link of a guild member. Experiment:
-- does Forever open recipe books that nobody posted, also of offline members?
function TradeSkill.Probe(args)
  local print = ns.Print
  local words = {}
  for word in (args or ""):gmatch("%S+") do words[#words + 1] = word end
  local profWord = table.remove(words)
  local m = ns.Roster.Find(table.concat(words, " "))
  local skillLine = profWord and SkillByName(profWord)
  if not m or not skillLine then
    print("probe: usage /guildy probe <member name> <profession>, e.g. /guildy probe Makira Farron Alchemie")
    return
  end
  local link = TradeSkill.BuildLink(m, skillLine)
  print(("probe: %s (%s), %s -> %s"):format(m.name, m.online and "online" or "offline", TradeSkill.Name(skillLine), tostring(link)))
  local setItemRef = rawget(_G, "SetItemRef")
  if link and setItemRef then
    local ok, err = pcall(setItemRef, link, "[" .. TradeSkill.Name(skillLine) .. "]", "LeftButton")
    if not ok then print("probe: SetItemRef failed: " .. tostring(err)) end
  end
  local enabled = C_TradeSkillUI and rawget(C_TradeSkillUI, "IsGuildTradeSkillsEnabled")
  print("probe: guild tradeskills enabled = " .. tostring(enabled and ns.Try(enabled)))
end

-- /guildy profdump: every profession info the client hands out right now (experiment: while another
-- member's recipe book is open, does it also tell their other professions, e.g. herbalism skill?)
function TradeSkill.ProfDump()
  local print = ns.Print
  local ui = C_TradeSkillUI or {}
  local linkedFn = rawget(ui, "IsTradeSkillLinked")
  print("profdump: linked = " .. tostring(linkedFn and select(1, ns.Try(linkedFn))) .. ", name = "
    .. tostring(linkedFn and select(2, ns.Try(linkedFn))))
  local base = ui.GetBaseProfessionInfo and ns.Try(ui.GetBaseProfessionInfo)
  if type(base) == "table" then
    print(("  base: %s id %s, %s/%s"):format(tostring(base.professionName), tostring(base.professionID),
      tostring(base.skillLevel), tostring(base.maxSkillLevel)))
  end
  for _, skillLine in ipairs(P.ORDER) do
    local info = ui.GetProfessionInfoBySkillLineID and ns.Try(ui.GetProfessionInfoBySkillLineID, skillLine)
    if type(info) == "table" then
      print(("  %s (%d): %s/%s, name %s"):format(TradeSkill.Name(skillLine), skillLine, tostring(info.skillLevel),
        tostring(info.maxSkillLevel), tostring(info.professionName)))
    else
      print(("  %s (%d): -"):format(TradeSkill.Name(skillLine), skillLine))
    end
  end
  local children = ui.GetChildProfessionInfos and ns.Try(ui.GetChildProfessionInfos)
  if type(children) == "table" then
    for _, info in ipairs(children) do
      print(("  child: %s id %s, %s/%s"):format(tostring(info.professionName), tostring(info.professionID),
        tostring(info.skillLevel), tostring(info.maxSkillLevel)))
    end
  end
end

-- /guildy debug: what Guildy knows about the current character and how the last scan went
function TradeSkill.Debug()
  local print = ns.Print
  local guild = ns.GuildData()
  local me = ns.PlayerName()
  local record = guild and guild.members[ns.Names.Key(me)]
  print(("debug: %s, guild data %s"):format(me, guild and "yes" or "no"))
  for skillLine, prof in pairs(record and record.profs or {}) do
    print(("  %s (%d): %s/%s, recipes %s, %s, src %s"):format(TradeSkill.Name(skillLine), skillLine,
      tostring(prof.rank), tostring(prof.max), prof.recipes and #prof.recipes or "none", ns.UI.Age(prof.ts), prof.src))
  end
  local s = TradeSkill.lastScan
  if not s then
    print("  last scan: never since login/reload")
  else
    print(("  last scan (%s): path %s, name %s, skillLine %s, rank %s, entries %s, recipes %s, recipeLink %s"):format(
      tostring(s.target), tostring(s.path), tostring(s.name), tostring(s.skillLine), tostring(s.rank), tostring(s.entries),
      tostring(s.recipes), tostring(s.hasRecipeLink)))
    if s.sample then print("  sample link: " .. s.sample:gsub("|", "||")) end
  end
  print(("  trade skill events seen: %d, linked check function: %s"):format(TradeSkill.events or 0,
    tostring((C_TradeSkillUI and rawget(C_TradeSkillUI, "IsTradeSkillLinked")) ~= nil or rawget(_G, "IsTradeSkillLinked") ~= nil)))
  if ns.Harvest then
    if ns.Harvest.IsRunning() then
      local done, total, found, look, looks = ns.Harvest.Progress()
      local name, skill = ns.Harvest.Current()
      local wait, slowed = ns.Harvest.Waiting()
      print(("  reading members: running, %d/%d members, %d found, look %d/%d, now %s %s"):format(done, total, found,
        look, looks, tostring(name), tostring(skill)))
      print(("  waiting: %s s%s, combat pause %s, InCombatLockdown %s"):format(
        wait and string.format("%.1f", wait) or "-", slowed and " (slowed)" or "",
        tostring(ns.Harvest.InCombatPause()), tostring(InCombatLockdown())))
    else
      print("  reading members: not running")
    end
  end
  local log = ns.Harvest and ns.Harvest.log or {}
  if #log > 0 then print("  last looks while reading members (newest first):") end
  for i = 1, math.min(#log, 12) do
    local e = log[i]
    print(("    %s %s: %s (%s, rank %s, recipes %s, %ss)"):format(e.member, e.skill, e.result, tostring(e.path),
      tostring(e.rank), tostring(e.recipes), tostring(e.seconds)))
  end
end