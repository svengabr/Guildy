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
    -- Guildy's own names in every language it has, not only the one it is set to: the game reports
    -- names in the client's language, whatever Guildy's is
    for _, texts in pairs(ns.LocaleTables) do
      for skillLine, key in pairs(P.SKILL_LINES) do
        local localized = texts["PROF_" .. key]
        if localized then nameToSkill[ns.Names.Lower(localized)] = nameToSkill[ns.Names.Lower(localized)] or skillLine end
      end
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
-- A window opened by a clicked link shows the book that was open before until the answer for the new
-- one arrives (found 2026-11-12: members got the professions and recipes of whoever was read before
-- them, and as the newest data those pushed their real professions out). So what a link's window shows
-- only counts when it is the profession the link asked for (expectedSkill) and not, recipe for
-- recipe, the book just read from another member (lastBook).
local expectedSkill
local lastBook -- { key, skillLine, rank, recipes, at } of the last book read from another member
local rejected -- the scan in progress showed a book that is not the target's
local SAME_BOOK_MIN, SAME_BOOK_SECONDS = 6, 120

-- Whether the player knows a spell. Clients differ in which of these they have and answer for passive
-- spells such as a specialization, so any of them saying yes counts (/guildy spec shows each one).
local function KnownFns()
  local book = rawget(_G, "C_SpellBook")
  local fns = {}
  for _, fn in ipairs({ book and rawget(book, "IsSpellKnown") or false, rawget(_G, "IsPlayerSpell") or false,
    rawget(_G, "IsSpellKnown") or false }) do
    if fn then fns[#fns + 1] = fn end
  end
  return fns
end
-- true, false, or nil when the client answered with a secret value and nothing said yes: it cannot tell
local function SpellKnown(id)
  local secret = false
  for _, fn in ipairs(KnownFns()) do
    local known = ns.Try(fn, id)
    if ns.IsSecret(known) then
      secret = true
    elseif known == true then
      return true
    end
  end
  if secret then return nil end
  return false
end
TradeSkill.SpellKnown = SpellKnown
TradeSkill.KnownFns = KnownFns

-- The specialization a book shows (Core/Specs.lua), merged into its record. Returns true when it changed.
local function InferSpec(rec, skillLine)
  if type(rec) ~= "table" or type(rec.recipes) ~= "table" or type(rec.ts) ~= "number" then return false end
  local id = ns.Specs.FromBook(skillLine, rec.recipes)
  return id ~= nil and ns.Specs.Merge(rec, { id = id, src = "book", ts = rec.ts })
end
TradeSkill.InferSpec = InferSpec

-- Every stored book of the guild through InferSpec (after login: books read before this version)
function TradeSkill.InferAll()
  local guild = not ns.Anon.on and ns.GuildData() or nil
  if not guild then return end
  local changed = false
  for _, member in pairs(guild.members) do
    for skillLine, rec in pairs(type(member) == "table" and member.profs or {}) do
      if InferSpec(rec, skillLine) then changed = true end
    end
  end
  if changed then ns.Fire("PROFS") end
end

-- Names of every recipe in the guild's books and of the specializations, in the client's language:
-- tools/bnet-sync matches the profile API's names against them (GuildyDB.recipeNames). Only once the
-- script asked for them (settings.recipeNames, set by the script): nobody else needs them.
function TradeSkill.RememberNames()
  local db = ns.DB()
  if not db or not (type(db.settings) == "table" and db.settings.recipeNames) then return end
  local locale = ns.Try(rawget(_G, "GetLocale")) or "enUS"
  if type(db.recipeNames) ~= "table" or db.recipeNames.locale ~= locale or type(db.recipeNames.names) ~= "table" then
    db.recipeNames = { locale = locale, names = {} }
  end
  local names = db.recipeNames.names
  local function Remember(id)
    if names[id] == nil then
      local name = SpellName(id)
      if type(name) == "string" and name ~= "" and not ns.IsSecret(name) then names[id] = name end
    end
  end
  for id in pairs(ns.Specs.SKILL_OF) do Remember(id) end
  for _, guild in pairs(db.guilds or {}) do
    for _, member in pairs(type(guild) == "table" and guild.members or {}) do
      for _, rec in pairs(type(member) == "table" and member.profs or {}) do
        for _, id in ipairs(type(rec) == "table" and rec.recipes or {}) do Remember(id) end
      end
    end
  end
end

-- Names tools/bnet-sync could not translate (GuildyDB.wantedNames): rare recipes no book Guildy read
-- contained. Guildy looks for each among the spells where crafts lie (the classic ones, and Forever's own
-- far above them) and keeps a name that belongs to exactly one spell. The script names the item each
-- recipe makes (wantedNames.items): that item's use effect, often named like the craft (bombs, target
-- dummies, fireworks), is no candidate. A name still shared by several spells (a craft and a buff, say)
-- is left out rather than guessed. A few thousand spells a frame, once a login.
local SEARCH_RANGES = { { 1, 60000 }, { 1200000, 1400000 } }
local SEARCH_CHUNK = 4000
function TradeSkill.SearchNames()
  local db = ns.DB()
  local wanted = db and db.wantedNames
  if not (db and type(db.settings) == "table" and db.settings.recipeNames and type(wanted) == "table"
    and type(wanted.names) == "table") then
    return
  end
  local locale = ns.Try(rawget(_G, "GetLocale")) or "enUS"
  local want, items = {}, {}
  local request = C_Item and C_Item.RequestLoadItemDataByID
  if wanted.locale == locale then
    for _, name in ipairs(wanted.names) do
      if type(name) == "string" and name ~= "" then
        want[name] = {}
        -- the item the recipe makes: its use effect often bears the craft's name (bombs, dummies,
        -- fireworks). Loaded now, read once the search is through.
        local item = type(wanted.items) == "table" and wanted.items[name]
        if type(item) == "number" and item > 0 then
          items[name] = item
          if request then ns.Try(request, item) end
        end
      end
    end
  end
  if not next(want) then
    db.wantedNames = nil
    return
  end
  if type(db.recipeNames) ~= "table" or db.recipeNames.locale ~= locale or type(db.recipeNames.names) ~= "table" then
    db.recipeNames = { locale = locale, names = {} }
  end
  local names = db.recipeNames.names
  local range, id = 1, SEARCH_RANGES[1][1]
  local function Step()
    local done = 0
    while range <= #SEARCH_RANGES and done < SEARCH_CHUNK do
      local name = SpellName(id)
      if name and want[name] then table.insert(want[name], id) end
      id, done = id + 1, done + 1
      if id > SEARCH_RANGES[range][2] then
        range = range + 1
        id = SEARCH_RANGES[range] and SEARCH_RANGES[range][1]
      end
    end
    if range <= #SEARCH_RANGES then
      C_Timer.After(0, function() ns.SafeCall(Step) end)
      return
    end
    local found = 0
    local itemSpell = (C_Item and C_Item.GetItemSpell) or rawget(_G, "GetItemSpell")
    for name, ids in pairs(want) do
      if #ids > 1 and items[name] and itemSpell then
        local _, useSpell = ns.Try(itemSpell, items[name])
        for i = #ids, 1, -1 do
          if ids[i] == useSpell then table.remove(ids, i) end
        end
      end
      if #ids == 1 then
        names[ids[1]] = name
        found = found + 1
      end
    end
    db.wantedNames = nil
    ns.Print(("bnet-sync: %d recipe names found in the game, the script's next run writes their books"):format(found))
  end
  Step()
end

-- The own character's specializations, from the game itself: only it and the script may replace or
-- revoke one (Core/Specs.lua). A changed specialization makes the record news for the others.
local confirmed = {} -- skill lines whose own specialization the game confirmed this session
local function NoteOwnSpecs(present)
  if #KnownFns() == 0 then return end -- a client that cannot tell must not say "none"
  local member = OwnMember()
  if not member then return end
  local now, changed = ns.Now(), false
  for skillLine in pairs(present) do
    local id = ns.Specs.Detect(skillLine, SpellKnown)
    local rec = member.profs[skillLine]
    local have = rec and rec.spec
    if id and rec and type(have) == "table" and have.src == "known" and have.id == id then
      -- the same answer as before (every skill-up scans): no news for the guild. Its age is renewed
      -- once a session, quietly, so a later entry of the script does not outrank the game's own word.
      if not confirmed[skillLine] then have.ts = math.max(have.ts or 0, now) end
      confirmed[skillLine] = true
    elseif id and rec and ns.Specs.Merge(rec, { id = id, src = "known", ts = now }) then
      rec.ts = math.max(rec.ts or 0, now)
      confirmed[skillLine] = true
      changed = true
    end
  end
  if changed then
    ns.Fire("PROFS")
    if ns.Sync then ns.Sync.OwnChanged() end
  end
end

-- /guildy spec: what the client answers for each specialization spell
function TradeSkill.SpecDebug()
  local fns = KnownFns()
  ns.Print(("spec: %d of C_SpellBook.IsSpellKnown, IsPlayerSpell, IsSpellKnown exist"):format(#fns))
  for skillLine, spells in pairs(ns.Specs.ORDER) do
    for _, id in ipairs(spells) do
      local answers = {}
      for _, fn in ipairs(fns) do answers[#answers + 1] = tostring(ns.Try(fn, id)) end
      ns.Print(("spec %s %d %s: %s"):format(TradeSkill.Name(skillLine), id, tostring(SpellName(id)), table.concat(answers, "/")))
    end
  end
  local member = OwnMember()
  for skillLine, rec in pairs(member and member.profs or {}) do
    if rec.spec then
      ns.Print(("spec stored %s: %d (%s)"):format(TradeSkill.Name(skillLine), rec.spec.id, tostring(rec.spec.src)))
    end
  end
end

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
  if scanTarget then
    -- the book that was open before, still showing in the window of the link just clicked
    if expectedSkill and skillLine ~= expectedSkill then
      rejected = true
      return
    end
    local last = lastBook
    if recipes and last and last.key ~= scanTarget.key and last.skillLine == skillLine and last.rank == rank
      and #recipes >= SAME_BOOK_MIN and GetTime() - last.at < SAME_BOOK_SECONDS and SameList(last.recipes, recipes) then
      rejected = true
      return
    end
    if recipes then lastBook = { key = scanTarget.key, skillLine = skillLine, rank = rank, recipes = recipes, at = GetTime() } end
  end
  local existing = member.profs[skillLine]
  if existing and existing.rank == rank and existing.max == max and (recipes == nil or SameList(existing.recipes, recipes)) then
    return
  end
  local src = scanTarget and "link" or "scan"
  local record = P.ValidateRecord({ ts = ns.Now(), src = src, rank = rank, max = max, recipes = recipes })
  if record and P.Merge(member, skillLine, record, { isOwnChar = not scanTarget }) then
    if scanTarget then InferSpec(member.profs[skillLine], skillLine) end
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

-- Forgets what Guildy knows of a member's professions, so the next reading starts from nothing: for a
-- member whose professions are wrong (an older Guildy stored the book of another member on them).
-- Everything read or received before this moment stays out (Professions.Merge); the marks "does not
-- have it" and "does not answer" go too, so the next run asks for every profession again.
function TradeSkill.Forget(m)
  local guild = ns.GuildData()
  local member = guild and m and guild.members[m.key]
  if not member then return false end
  for skillLine, rec in pairs(member.profs or {}) do
    if rec.src ~= "note" then member.profs[skillLine] = nil end
  end
  member.profsCleared = ns.Now()
  if type(guild.absent) == "table" then guild.absent[m.key] = nil end
  if type(guild.silent) == "table" then guild.silent[m.key] = nil end
  ns.Fire("PROFS")
  return true
end

-- TRADE_SKILL_CLOSE: a later own window must not be taken for the linked one
function TradeSkill.OnClose()
  pendingLink = nil
end

-- Decides whose window is open. Returns false when it should not be scanned at all.
local function ResolveTarget()
  scanTarget, expectedSkill = nil, nil
  local isLinked, linkedName
  local linkedFn = (C_TradeSkillUI and rawget(C_TradeSkillUI, "IsTradeSkillLinked")) or rawget(_G, "IsTradeSkillLinked")
  if linkedFn then
    isLinked, linkedName = ns.Try(linkedFn)
  end
  local pending = pendingLink and GetTime() - pendingLink.at < 30 and pendingLink or nil
  if linkedFn and not isLinked then return true end -- own window (the client says so)
  if not linkedFn and not pending then return true end -- no way to tell: only a clicked link counts as foreign
  local clicked = pending and ns.Roster.FindByGuid(pending.guid) or nil
  local named = type(linkedName) == "string" and not ns.IsSecret(linkedName) and ns.Roster.Find(linkedName) or nil
  -- the window names someone else than the link that was clicked: it still shows the book before
  if clicked and named and clicked.key ~= named.key then return false end
  local m = clicked or named
  if not m then return false end -- someone outside the guild
  if not IsOwnChar(m) then
    scanTarget = m
    if clicked then expectedSkill = pending.skillLine end
  end
  return true
end

-- Professions the current character no longer has (unlearned) leave its record
local function PruneOwn(present)
  local member = OwnMember()
  if member and P.Prune(member, present) then
    ns.Fire("PROFS")
    if ns.Sync then ns.Sync.OwnChanged() end
  end
end

-- Skill levels of all professions of the current character (no recipes). Professions it no longer has
-- are removed, but only when the client really handed out the skill list (it can be empty right after login).
function TradeSkill.ScanSkills()
  local getProfessions, getInfo = rawget(_G, "GetProfessions"), rawget(_G, "GetProfessionInfo")
  local present, seen = {}, false
  if getProfessions and getInfo then
    for _, index in ipairs({ ns.Try(getProfessions) }) do
      if index then
        local name, _, rank, max, _, _, skillLine = ns.Try(getInfo, index)
        skillLine = (skillLine and P.SKILL_LINES[skillLine]) and skillLine or SkillByName(name)
        if skillLine then
          seen = true
          present[skillLine] = true
          StoreOwn(skillLine, rank, max, nil)
        end
      end
    end
  end
  if seen then
    if not scanTarget then
      PruneOwn(present)
      NoteOwnSpecs(present)
    end
    return
  end
  local count = ns.Try(rawget(_G, "GetNumSkillLines")) or 0
  local getLine = rawget(_G, "GetSkillLineInfo")
  local lines, collapsed = 0, false
  for i = 1, count do
    local name, isHeader, isExpanded, rank, _, _, max = ns.Try(getLine, i)
    if name then lines = lines + 1 end
    if isHeader and not isExpanded then collapsed = true end
    if not isHeader then
      local skillLine = SkillByName(name)
      if skillLine then
        present[skillLine] = true
        StoreOwn(skillLine, rank, max, nil)
      end
    end
  end
  -- the skill list always has headers and languages: with no lines it isn't loaded yet; a collapsed
  -- header (the player folded it in the skill window) hides its professions
  if lines > 0 and not collapsed and not scanTarget then PruneOwn(present) end
  if not scanTarget then NoteOwnSpecs(present) end
end

local function IdFromLink(link)
  if type(link) ~= "string" then return nil end
  return tonumber(link:match("enchant:(%d+)")) or tonumber(link:match("spell:(%d+)"))
end

-- The open profession window (legacy trade skill frame, craft frame, or the C_TradeSkillUI one)
function TradeSkill.ScanOpen()
  TradeSkill.lastScan = { path = "none" }
  rejected = false
  if C_TradeSkillUI and C_TradeSkillUI.IsNPCCrafting and ns.Try(C_TradeSkillUI.IsNPCCrafting) then return end
  if ns.Try(rawget(_G, "IsTradeSkillGuild")) then return end
  if not ResolveTarget() then
    TradeSkill.lastScan = { path = "linked window of someone outside the guild" }
    return
  end

  -- crafts with a cooldown in the player's own window: spellID -> seconds left (Game/Cooldowns.lua)
  local ownCooldowns = {}
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
          if ns.GameGear then ns.GameGear.LearnCraft(id, ns.Try(rawget(_G, "GetTradeSkillItemLink"), i)) end
          local left = ns.Try(rawget(_G, "GetTradeSkillCooldown"), i)
          if not scanTarget and not ns.IsSecret(left) and type(left) == "number" and left > 0 then ownCooldowns[id] = left end
        end
      end
    end
    if next(ownCooldowns) and ns.GameCooldowns then ns.GameCooldowns.FromWindow(SkillByName(lineName), ownCooldowns) end
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
          if ns.GameGear then ns.GameGear.LearnCraft(id, ns.Try(rawget(_G, "GetCraftItemLink"), i)) end
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
        local output = rawget(C_TradeSkillUI, "GetRecipeOutputItemData")
        local made = output and ns.Try(output, id)
        if ns.GameGear and type(made) == "table" then ns.GameGear.LearnCraft(id, made.itemID) end
        local left = ns.Try(rawget(C_TradeSkillUI, "GetRecipeCooldown"), id)
        if not scanTarget and not ns.IsSecret(left) and type(left) == "number" and left > 0 then ownCooldowns[id] = left end
      end
    end
    if next(ownCooldowns) and ns.GameCooldowns and skillLine then ns.GameCooldowns.FromWindow(skillLine, ownCooldowns) end
    TradeSkill.lastScan = { path = "C_TradeSkillUI", name = info.professionName, skillLine = skillLine,
      rank = info.skillLevel, recipes = #recipes }
    if skillLine and #recipes > 0 then StoreOwn(skillLine, info.skillLevel, info.maxSkillLevel, recipes) end
  end
  TradeSkill.lastScan.target = scanTarget and scanTarget.name or "own"
  TradeSkill.lastScan.stale = rejected or nil -- (not the target's book: no answer to whoever asked)
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