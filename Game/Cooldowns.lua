-- The player's own profession cooldowns (Core/Cooldowns.lua has the rules). Two sources, because
-- clients differ in what they answer: the craft's spell (C_Spell.GetSpellCooldown / GetSpellCooldown,
-- no window needed) and the player's own profession window (GetTradeSkillCooldown, Game/TradeSkill.lua).
-- Items such as the Salt Shaker come from the bags. A character without any cooldown craft stays out.
local _, ns = ...
local C = ns.Cooldowns

local GameCooldowns = {}
ns.GameCooldowns = GameCooldowns

local fromWindow = {} -- spellID -> readyAt seen in the own window this session
local pending = false

local function Learned()
  local db = ns.DB()
  if not db then return {} end
  if type(db.cooldownSpells) ~= "table" then db.cooldownSpells = {} end
  return db.cooldownSpells
end

-- The guild's readings (created on first use); nil without a guild or while names are made up
function GameCooldowns.Book()
  local guild = not ns.Anon.on and ns.GuildData() or nil
  if not guild then return nil end
  if type(guild.cooldowns) ~= "table" then guild.cooldowns = {} end
  return guild.cooldowns
end

local function SpellCooldown(id)
  local cs = rawget(_G, "C_Spell")
  local info = cs and ns.Try(rawget(cs, "GetSpellCooldown"), id)
  if type(info) == "table" then return info.startTime, info.duration end
  return ns.Try(rawget(_G, "GetSpellCooldown"), id)
end

-- Seconds left on a craft's spell, nil when the player does not know it
local function SpellLeft(id)
  if not ns.TradeSkill.SpellKnown(id) then return nil end
  local start, duration = SpellCooldown(id)
  -- (two seconds and less is the global cooldown, not the craft's)
  if type(start) ~= "number" or type(duration) ~= "number" or duration <= 2 or start <= 0 then return 0 end
  return math.max(0, start + duration - GetTime())
end

local function Container(name)
  local container = rawget(_G, "C_Container")
  return (container and rawget(container, name)) or rawget(_G, name)
end

-- Seconds left on an item in the bags, nil when it is not there
local function ItemLeft(itemID)
  local slots, itemOf, cooldownOf = Container("GetContainerNumSlots"), Container("GetContainerItemID"),
    Container("GetContainerItemCooldown")
  if not (slots and itemOf and cooldownOf) then return nil end
  for bag = 0, 4 do
    for slot = 1, ns.Try(slots, bag) or 0 do
      if ns.Try(itemOf, bag, slot) == itemID then
        local start, duration = ns.Try(cooldownOf, bag, slot)
        if type(start) ~= "number" or type(duration) ~= "number" or duration <= 2 or start <= 0 then return 0 end
        return math.max(0, start + duration - GetTime())
      end
    end
  end
  return nil
end

local function Changed(key)
  ns.Fire("PROFS")
  if ns.Sync and ns.Sync.ShareCooldowns then ns.Sync.ShareCooldowns(key) end
end

-- Reads every watched craft of the current character and stores it when something changed
function GameCooldowns.Read()
  pending = false
  local book = GameCooldowns.Book()
  if not book then return end
  local now = ns.Now()
  local cd, any = {}, false
  local function Put(spell, left)
    local at = left > 0 and now + math.floor(left + 0.5) or 0
    -- the own window saw a cooldown the spell does not report: the window is right
    local seen = fromWindow[spell]
    if seen and seen > now and at == 0 then at = seen end
    cd[spell] = at
    any = true
  end
  for spell in pairs(C.Watched(Learned())) do
    local left = SpellLeft(spell)
    if left then Put(spell, left) elseif fromWindow[spell] then Put(spell, 0) end
  end
  for item, spell in pairs(C.ITEMS) do
    local left = ItemLeft(item)
    if left then Put(spell, left) end
  end
  local key = ns.Names.Key(ns.PlayerName())
  if not any and not book[key] then return end
  if C.Note(book, key, cd, now) then Changed(key) end
end

-- Crafts with a cooldown in the own window (Game/TradeSkill.lua): spellID -> seconds left
function GameCooldowns.FromWindow(skillLine, seen)
  local learned, now = Learned(), ns.Now()
  for spell, left in pairs(seen) do
    if skillLine then C.Learn(learned, spell, skillLine) end
    fromWindow[spell] = now + math.floor(left + 0.5)
  end
  GameCooldowns.Schedule()
end

-- Many events in a row become one reading
function GameCooldowns.Schedule()
  if pending then return end
  pending = true
  C_Timer.After(2, function() ns.SafeCall(GameCooldowns.Read) end)
end

-- /guildy cd: what the client answers for each watched craft
function GameCooldowns.Debug()
  for spell, skillLine in pairs(C.Watched(Learned())) do
    local start, duration = SpellCooldown(spell)
    ns.Print(("cd %s %d %s: known=%s start=%s duration=%s window=%s"):format(ns.TradeSkill.Name(skillLine), spell,
      tostring(ns.TradeSkill.RecipeName(spell)), tostring(ns.TradeSkill.SpellKnown(spell)), tostring(start),
      tostring(duration), tostring(fromWindow[spell])))
  end
  for item, spell in pairs(C.ITEMS) do
    ns.Print(("cd item %d (spell %d): left=%s"):format(item, spell, tostring(ItemLeft(item))))
  end
  local book = GameCooldowns.Book()
  local key = ns.Names.Key(ns.PlayerName())
  for _, entry in ipairs(book and C.Of(book, key, ns.Now()) or {}) do
    ns.Print(("cd stored %d: %d s left"):format(entry.spell, entry.left))
  end
end
