-- Stat weights per class and talent spec, pure: what "better" means for a member whose talent spec is known
-- (Core/Talents.lua decides the spec, Core/Upgrades.lua scores with the weights). Guildy's own coarse table
-- from the commonly known stat priorities of the Classic-era specs, not taken from any other addon.
-- Keys are the client's GetItemStats keys (ITEM_MOD_*_SHORT); a key the client never gives costs nothing.
-- Weights run from 0 to 1: 1 is the spec's main stat, a stat left out counts nothing. Stamina is low for
-- every spec but the tanks (nearly every piece has it). Ratings count per point as the item lists them, so
-- a "+1 % crit" piece weighs little next to a pile of agility: the weights are coarse on purpose.
-- (Talent specs are not profession specializations: those are Core/Specs.lua.)
local _, ns = ...

local StatWeights = {}
ns.StatWeights = StatWeights

local STR, AGI, STA, INT, SPI = "ITEM_MOD_STRENGTH_SHORT", "ITEM_MOD_AGILITY_SHORT", "ITEM_MOD_STAMINA_SHORT",
  "ITEM_MOD_INTELLECT_SHORT", "ITEM_MOD_SPIRIT_SHORT"
local AP, RAP = "ITEM_MOD_ATTACK_POWER_SHORT", "ITEM_MOD_RANGED_ATTACK_POWER_SHORT"
local SP, DMG, HEAL = "ITEM_MOD_SPELL_POWER_SHORT", "ITEM_MOD_SPELL_DAMAGE_DONE_SHORT", "ITEM_MOD_SPELL_HEALING_DONE_SHORT"
local MP5, MP5B = "ITEM_MOD_MANA_REGENERATION_SHORT", "ITEM_MOD_POWER_REGEN0_SHORT"
local CRIT, HIT = "ITEM_MOD_CRIT_RATING_SHORT", "ITEM_MOD_HIT_RATING_SHORT"
local SCRIT, SHIT = "ITEM_MOD_CRIT_SPELL_RATING_SHORT", "ITEM_MOD_HIT_SPELL_RATING_SHORT"
local DEF, DODGE, PARRY = "ITEM_MOD_DEFENSE_SKILL_RATING_SHORT", "ITEM_MOD_DODGE_RATING_SHORT", "ITEM_MOD_PARRY_RATING_SHORT"
local BLOCK, BLOCKV = "ITEM_MOD_BLOCK_RATING_SHORT", "ITEM_MOD_BLOCK_VALUE_SHORT"
local ARMOR = "RESISTANCE0_NAME" -- armour, only for the tanks: it comes in hundreds, so its weight is small
local ARMOR_W = 0.02

StatWeights.WEIGHTS = {
  -- plate DPS: strength, crit and hit, then attack power and agility
  WARRIOR_DPS = { [STR] = 1, [CRIT] = 1, [HIT] = 1, [AP] = 0.5, [AGI] = 0.6, [STA] = 0.1 },
  -- tank: stamina, defense and armour, then avoidance and block
  WARRIOR_TANK = { [STA] = 1, [DEF] = 1, [ARMOR] = ARMOR_W, [DODGE] = 0.8, [PARRY] = 0.6, [BLOCK] = 0.5, [BLOCKV] = 0.3,
    [STR] = 0.4, [AGI] = 0.4, [HIT] = 0.3 },
  -- healer: healing and intellect, mana per 5 and spell crit, a little spirit
  PALADIN_HOLY = { [HEAL] = 1, [SP] = 0.9, [INT] = 1, [MP5] = 0.8, [MP5B] = 0.8, [SCRIT] = 0.8, [SPI] = 0.3, [STA] = 0.1 },
  -- tank: stamina, defense and armour, block, then spell power for the holy damage
  PALADIN_PROT = { [STA] = 1, [DEF] = 1, [ARMOR] = ARMOR_W, [BLOCK] = 0.6, [BLOCKV] = 0.5, [DODGE] = 0.7, [PARRY] = 0.6,
    [SP] = 0.5, [DMG] = 0.5, [INT] = 0.3, [STR] = 0.3 },
  -- plate DPS: strength, crit and hit, then attack power and agility
  PALADIN_RET = { [STR] = 1, [CRIT] = 1, [HIT] = 1, [AP] = 0.5, [AGI] = 0.5, [INT] = 0.2, [SP] = 0.2, [STA] = 0.1 },
  -- caster DPS: spell power, spell crit and hit, intellect
  SHAMAN_ELE = { [SP] = 1, [DMG] = 1, [SCRIT] = 1, [SHIT] = 1, [INT] = 0.7, [MP5] = 0.4, [MP5B] = 0.4, [STA] = 0.1 },
  -- melee: strength, crit and hit, agility, attack power
  SHAMAN_ENH = { [STR] = 1, [CRIT] = 1, [HIT] = 1, [AGI] = 0.7, [AP] = 0.5, [INT] = 0.2, [STA] = 0.1 },
  -- healer: healing, mana per 5, intellect
  SHAMAN_RESTO = { [HEAL] = 1, [SP] = 0.9, [MP5] = 1, [MP5B] = 1, [INT] = 0.8, [SCRIT] = 0.6, [SPI] = 0.2, [STA] = 0.1 },
  -- healer: healing and intellect, spirit and mana per 5
  PRIEST_HEAL = { [HEAL] = 1, [SP] = 0.9, [INT] = 0.9, [SPI] = 0.6, [MP5] = 0.8, [MP5B] = 0.8, [SCRIT] = 0.5, [STA] = 0.1 },
  -- caster DPS: spell power and spell hit, then intellect, spirit and crit
  PRIEST_SHADOW = { [SP] = 1, [DMG] = 1, [SHIT] = 1, [INT] = 0.5, [SPI] = 0.4, [SCRIT] = 0.4, [STA] = 0.2 },
  -- caster DPS: spell power, spell crit and hit, intellect
  DRUID_BALANCE = { [SP] = 1, [DMG] = 1, [SCRIT] = 1, [SHIT] = 1, [INT] = 0.7, [SPI] = 0.3, [MP5] = 0.4, [MP5B] = 0.4,
    [STA] = 0.1 },
  -- feral cat: agility and strength high, crit and hit, attack power medium, stamina low
  DRUID_CAT = { [AGI] = 1, [STR] = 0.9, [CRIT] = 0.8, [HIT] = 0.8, [AP] = 0.5, [STA] = 0.1 },
  -- feral bear: stamina, armour, agility and defense high, then dodge and strength
  DRUID_BEAR = { [STA] = 1, [ARMOR] = ARMOR_W, [AGI] = 0.8, [DEF] = 0.8, [DODGE] = 0.7, [STR] = 0.5, [HIT] = 0.3, [AP] = 0.2 },
  -- healer: healing, intellect and spirit, mana per 5
  DRUID_RESTO = { [HEAL] = 1, [SP] = 0.9, [INT] = 0.8, [SPI] = 0.8, [MP5] = 0.8, [MP5B] = 0.8, [SCRIT] = 0.4, [STA] = 0.1 },
  -- ranged: agility, crit and hit, then ranged attack power
  HUNTER = { [AGI] = 1, [CRIT] = 1, [HIT] = 1, [RAP] = 0.5, [AP] = 0.4, [INT] = 0.2, [STA] = 0.1 },
  -- melee: agility, crit and hit, then strength and attack power
  ROGUE = { [AGI] = 1, [CRIT] = 1, [HIT] = 1, [STR] = 0.5, [AP] = 0.5, [STA] = 0.1 },
  -- caster DPS: spell power, spell crit and hit, intellect
  MAGE = { [SP] = 1, [DMG] = 1, [SCRIT] = 1, [SHIT] = 1, [INT] = 0.6, [SPI] = 0.2, [STA] = 0.1 },
  -- caster DPS: spell power and spell hit, then crit and intellect
  WARLOCK = { [SP] = 1, [DMG] = 1, [SHIT] = 1, [SCRIT] = 0.6, [INT] = 0.5, [SPI] = 0.2, [STA] = 0.2 },
}

StatWeights.TANK = { WARRIOR_TANK = true, PALADIN_PROT = true, DRUID_BEAR = true }

-- Whether weights are a tank spec's (the table StatWeights.For gave): stamina is their main stat
function StatWeights.IsTank(weights)
  if type(weights) ~= "table" then return false end
  for spec in pairs(StatWeights.TANK) do
    if StatWeights.WEIGHTS[spec] == weights then return true end
  end
  return false
end

-- The spec of each talent tree, in the game's tab order. DRUID_FERAL is cat or bear by the worn gear
-- (Core/Talents.lua).
StatWeights.TREES = {
  WARRIOR = { "WARRIOR_DPS", "WARRIOR_DPS", "WARRIOR_TANK" },        -- Arms, Fury, Protection
  PALADIN = { "PALADIN_HOLY", "PALADIN_PROT", "PALADIN_RET" },       -- Holy, Protection, Retribution
  HUNTER = { "HUNTER", "HUNTER", "HUNTER" },                         -- Beast Mastery, Marksmanship, Survival
  ROGUE = { "ROGUE", "ROGUE", "ROGUE" },                             -- Assassination, Combat, Subtlety
  PRIEST = { "PRIEST_HEAL", "PRIEST_HEAL", "PRIEST_SHADOW" },        -- Discipline, Holy, Shadow
  SHAMAN = { "SHAMAN_ELE", "SHAMAN_ENH", "SHAMAN_RESTO" },           -- Elemental, Enhancement, Restoration
  MAGE = { "MAGE", "MAGE", "MAGE" },                                 -- Arcane, Fire, Frost
  WARLOCK = { "WARLOCK", "WARLOCK", "WARLOCK" },                     -- Affliction, Demonology, Destruction
  DRUID = { "DRUID_BALANCE", "DRUID_FERAL", "DRUID_RESTO" },         -- Balance, Feral Combat, Restoration
}

-- The weights of spec, nil for none. The same table on every call: callers must not change it.
function StatWeights.For(spec)
  return spec and StatWeights.WEIGHTS[spec] or nil
end
