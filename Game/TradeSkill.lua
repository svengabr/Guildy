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
  db.ownChars[ns.Names.Key(me)] = true
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

-- Stores own data for a profession when something changed; recipes nil = unknown (keep old list)
local function StoreOwn(skillLine, rank, max, recipes)
  local member = OwnMember()
  if not member or not skillLine then return end
  if recipes then table.sort(recipes) end
  local existing = member.profs[skillLine]
  if existing and existing.rank == rank and existing.max == max and (recipes == nil or SameList(existing.recipes, recipes)) then
    return
  end
  local record = P.ValidateRecord({ ts = ns.Now(), src = "scan", rank = rank, max = max, recipes = recipes })
  if record and P.Merge(member, skillLine, record, { isOwnChar = true }) then
    ns.Fire("PROFS")
    if ns.Sync then ns.Sync.OwnChanged() end
  end
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
  if ns.Try(rawget(_G, "IsTradeSkillLinked")) or ns.Try(rawget(_G, "IsTradeSkillGuild")) then return end

  local lineName, rank, max = ns.Try(rawget(_G, "GetTradeSkillLine"))
  if lineName and lineName ~= "UNKNOWN" then
    local recipes = {}
    for i = 1, ns.Try(rawget(_G, "GetNumTradeSkills")) or 0 do
      local _, kind = ns.Try(rawget(_G, "GetTradeSkillInfo"), i)
      if kind and kind ~= "header" and kind ~= "subheader" then
        local id = IdFromLink(ns.Try(rawget(_G, "GetTradeSkillRecipeLink"), i))
        if id then recipes[#recipes + 1] = id end
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
        if id then recipes[#recipes + 1] = id end
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
      if recipe and recipe.learned then recipes[#recipes + 1] = id end
    end
    TradeSkill.lastScan = { path = "C_TradeSkillUI", name = info.professionName, skillLine = skillLine,
      rank = info.skillLevel, recipes = #recipes }
    if skillLine and #recipes > 0 then StoreOwn(skillLine, info.skillLevel, info.maxSkillLevel, recipes) end
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
    print("  last scan: never (open a profession window)")
    return
  end
  print(("  last scan: path %s, name %s, skillLine %s, rank %s, entries %s, recipes %s, recipeLink %s"):format(
    tostring(s.path), tostring(s.name), tostring(s.skillLine), tostring(s.rank), tostring(s.entries), tostring(s.recipes),
    tostring(s.hasRecipeLink)))
  if s.sample then print("  sample link: " .. s.sample:gsub("|", "||")) end
end