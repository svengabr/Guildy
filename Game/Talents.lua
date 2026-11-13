-- Talent points of guild members from the game (record and spec decision in Core/Talents.lua, weights in
-- Core/StatWeights.lua). Talent specs, not the profession specializations of Core/Specs.lua.
-- Own talents: read with the own statistics (login, every 10 minutes) and a moment after points were spent
-- (CHARACTER_POINTS_CHANGED), src "self", shared like the own gear (only with settings.share).
-- Others: read inside the inspect Game/Stats.lua already runs, after INSPECT_READY, src "seen"; Guildy
-- never inspects for the talents alone. A client without the talent API, or one that gives no points to an
-- inspect, leaves the record alone. Any secret value stops a read: nothing secret is compared or stored.
-- Classic Era reads GetTalentTabInfo; WoW Forever has none and gives the points through C_Traits (below).
-- The trees' names in the client's language are kept per class (GuildyDB.talentNames = { locale,
-- classes = { [classFile] = { name1, name2, name3 } } }) for the upgrades heading; tools/bnet-sync writes
-- them as well.
local _, ns = ...
local Tal = ns.Talents

local GameTalents = {}
ns.GameTalents = GameTalents

local REFRESH = 86400 -- unchanged own talents are stored and sent anew after this many seconds
local POINTS_WAIT = 10 -- seconds after points were spent: several points in a row are one reading

local function Locale() return ns.Try(rawget(_G, "GetLocale")) or "enUS" end

-- The talent tabs through GetTalentTabInfo (Classic Era): { { name, points } } ×3, nil without the API,
-- with anything secret or with other than three tabs
local function ClassicTabs(info, inspect)
  local numTabs = rawget(_G, "GetNumTalentTabs")
  local count = numTabs and ns.Try(numTabs, inspect) or 3
  if ns.IsSecret(count) or count ~= 3 then return nil end
  local tabs = {}
  for i = 1, 3 do
    local a, b, c, d, e = ns.Try(info, i, inspect)
    if ns.AnySecret(a, b, c, d, e) then return nil end
    tabs[i] = Tal.TabPoints(a, b, c, d, e)
    if not tabs[i] then return nil end
  end
  return tabs
end

-- WoW Forever has no GetTalentTabInfo (and one specialization per class in C_SpecializationInfo): the
-- talent points live in the trait system. A config (C_ClassTalents.GetActiveConfigID for the player,
-- Constants.TraitConsts.INSPECT_TRAIT_CONFIG_ID = -1 for the inspected unit) lists treeIDs; the three
-- classic tabs are either three trees (in the config's order) or one tree whose nodes name their tab by
-- subTreeID (on the node, or on its entry; ordered by ID). The real shape is not known yet: /guildy
-- talentprobe prints it. Anything secret stops the read.

-- A function of a C_ namespace, nil when there is none
local function Api(space, name)
  local t = rawget(_G, space)
  if type(t) ~= "table" or ns.IsSecret(t) then return nil end
  local fn = rawget(t, name)
  return type(fn) == "function" and fn or nil
end

-- t[key] of a table that is not secret, nil else; the value may itself be secret
local function Field(t, key)
  if type(t) ~= "table" or ns.IsSecret(t) then return nil end
  return t[key]
end

local function InspectConfigID()
  local id = Field(Field(rawget(_G, "Constants"), "TraitConsts"), "INSPECT_TRAIT_CONFIG_ID")
  return type(id) == "number" and not ns.IsSecret(id) and id or -1
end

local RANK_FIELDS = { "ranksPurchased", "activeRank", "currentRank" }
-- The ranks spent in a node (GetNodeInfo): a number, or nil, true when secret
local function NodeRanks(node)
  for _, key in ipairs(RANK_FIELDS) do
    local v = Field(node, key)
    if ns.IsSecret(v) then return nil, true end
    if type(v) == "number" then return v end
  end
  return 0
end

-- The entry ID of a node: its active entry, else its first
local function EntryOf(node)
  local entry = Field(Field(node, "activeEntry"), "entryID")
  if type(entry) ~= "number" or ns.IsSecret(entry) then entry = Field(Field(node, "entryIDs"), 1) end
  return type(entry) == "number" and not ns.IsSecret(entry) and entry or nil
end

-- The subtree a node belongs to: an ID, nil without one, nil, true when secret
local function SubTreeOf(configID, node)
  local sub = Field(node, "subTreeID")
  if ns.IsSecret(sub) then return nil, true end
  if type(sub) == "number" and sub ~= 0 then return sub end
  local entryInfo = Api("C_Traits", "GetEntryInfo")
  local entry = EntryOf(node)
  if not (entryInfo and entry) then return nil end
  local info = ns.Try(entryInfo, configID, entry)
  if ns.IsSecret(info) then return nil, true end
  sub = Field(info, "subTreeID")
  if ns.IsSecret(sub) then return nil, true end
  return type(sub) == "number" and sub ~= 0 and sub or nil
end

local function SubTreeName(configID, sub)
  local name = Field(ns.Try(Api("C_Traits", "GetSubTreeInfo"), configID, sub), "name")
  return type(name) == "string" and not ns.IsSecret(name) and name ~= "" and name or nil
end

-- The ranks of configID: { trees = { [i] = { id, ranks, nodes = { nodeInfo } } }, subs = { [subTreeID] =
-- ranks }, subOrder = { subTreeID } }, nil without the API or config, with anything secret
local function ReadConfig(configID)
  local getConfig, getNodes, getNode = Api("C_Traits", "GetConfigInfo"), Api("C_Traits", "GetTreeNodes"),
    Api("C_Traits", "GetNodeInfo")
  if not (getConfig and getNodes and getNode) or type(configID) ~= "number" or ns.IsSecret(configID) then return nil end
  local info = ns.Try(getConfig, configID)
  local treeIDs = Field(info, "treeIDs")
  if type(treeIDs) ~= "table" or ns.IsSecret(treeIDs) then return nil end
  local read = { info = info, trees = {}, subs = {}, subOrder = {} }
  for i, treeID in ipairs(treeIDs) do
    if ns.IsSecret(treeID) then return nil end
    local nodes = ns.Try(getNodes, treeID)
    if type(nodes) ~= "table" or ns.IsSecret(nodes) then return nil end
    local tree = { id = treeID, ranks = 0, nodes = {}, nodeIDs = nodes }
    read.trees[i] = tree
    for _, nodeID in ipairs(nodes) do
      if ns.IsSecret(nodeID) then return nil end
      local node = ns.Try(getNode, configID, nodeID)
      if ns.IsSecret(node) then return nil end
      if type(node) == "table" then
        local ranks, secret = NodeRanks(node)
        if secret then return nil end
        tree.ranks = tree.ranks + ranks
        tree.nodes[#tree.nodes + 1] = node
        local sub, subSecret = SubTreeOf(configID, node)
        if subSecret then return nil end
        if sub then
          if not read.subs[sub] then
            read.subs[sub] = 0
            read.subOrder[#read.subOrder + 1] = sub
          end
          read.subs[sub] = read.subs[sub] + ranks
        end
      end
    end
  end
  table.sort(read.subOrder)
  return read
end

-- The three tabs { { name?, points } } of a config read (ReadConfig) and how they were found ("subtrees"
-- or "trees"), nil when it is neither three subtrees nor three trees
local function TabsOf(configID, read)
  if not read then return nil end
  if #read.subOrder == 3 then
    local tabs = {}
    for i, sub in ipairs(read.subOrder) do tabs[i] = { name = SubTreeName(configID, sub), points = read.subs[sub] } end
    return tabs, "subtrees"
  end
  if #read.trees == 3 then
    return { { points = read.trees[1].ranks }, { points = read.trees[2].ranks }, { points = read.trees[3].ranks } }, "trees"
  end
  return nil
end

local function TraitTabs(inspect)
  local configID
  if inspect then
    configID = InspectConfigID()
  else
    configID = ns.Try(Api("C_ClassTalents", "GetActiveConfigID"))
  end
  if type(configID) ~= "number" or ns.IsSecret(configID) then return nil end
  return (TabsOf(configID, ReadConfig(configID)))
end

-- The three talent tabs of the player (inspect false) or of the inspected unit (inspect true): { { name?,
-- points } }, nil without a talent API, with anything secret or with other than three tabs
local function ReadTabs(inspect)
  local info = rawget(_G, "GetTalentTabInfo")
  if info then return ClassicTabs(info, inspect) end
  return TraitTabs(inspect)
end

-- The names of classID's three specializations in tab order (C_SpecializationInfo.GetSpecIDs, then
-- GetSpecializationInfoByID), nil unless all three are known
local function SpecNames(classID)
  if type(classID) ~= "number" or ns.IsSecret(classID) then return nil end
  local ids = ns.Try(Api("C_SpecializationInfo", "GetSpecIDs"), classID)
  if type(ids) ~= "table" or ns.IsSecret(ids) or #ids ~= 3 then return nil end
  local byID = rawget(_G, "GetSpecializationInfoByID") or Api("C_SpecializationInfo", "GetSpecializationInfoByID")
  if not byID then return nil end
  local names = {}
  for i = 1, 3 do
    local specID = ids[i]
    if type(specID) ~= "number" or ns.IsSecret(specID) then return nil end
    local id, name = ns.Try(byID, specID)
    if ns.AnySecret(id, name) or id ~= specID or type(name) ~= "string" or name == "" then return nil end
    names[i] = name
  end
  return names
end

-- The tree names of the tabs, else of the class's specializations; nil unless all three are known
local function NamesOf(tabs, classID)
  if tabs[1].name and tabs[2].name and tabs[3].name then return { tabs[1].name, tabs[2].name, tabs[3].name } end
  return SpecNames(classID)
end

-- Keeps the tree names of classFile (the client's language)
local function RememberNames(classFile, names)
  local db = ns.DB()
  if not db or not names or type(classFile) ~= "string" or classFile == "" then return end
  local locale = Locale()
  local cache = db.talentNames
  if type(cache) ~= "table" or cache.locale ~= locale or type(cache.classes) ~= "table" then
    cache = { locale = locale, classes = {} }
    db.talentNames = cache
  end
  cache.classes[classFile] = names
end

-- The name of classFile's talent tree in the client's language, nil when not known
function GameTalents.TreeName(classFile, tree)
  local db = ns.DB()
  local cache = db and db.talentNames
  if type(cache) ~= "table" or cache.locale ~= Locale() or type(cache.classes) ~= "table" then return nil end
  local names = cache.classes[classFile]
  local name = type(names) == "table" and names[tree]
  return type(name) == "string" and name ~= "" and name or nil
end

-- The talent book of the current guild, created on first use
local function Book(guild)
  if type(guild.talents) ~= "table" then guild.talents = {} end
  return guild.talents
end

local function Share(key)
  if ns.Sync and ns.Sync.ShareGear then ns.Sync.ShareGear(key) end
end

-- Own talents, called with the own statistics (Game/Stats.lua) and after points were spent
function GameTalents.ReadOwn()
  if ns.Anon.on then return end
  local guild = ns.GuildData()
  if not guild then return end
  local tabs = ReadTabs(false)
  local trees = Tal.FromTabs(tabs)
  if not trees then return end
  local _, classFile, classID = ns.Try(rawget(_G, "UnitClass"), "player")
  if not ns.AnySecret(classFile, classID) then RememberNames(classFile, NamesOf(tabs, classID)) end
  local key = ns.Names.Key(ns.PlayerName())
  local book = Book(guild)
  local have = book[key]
  local rec = { src = "self", trees = trees }
  if type(have) == "table" and have.src == "self" and Tal.Same(have, rec) and type(have.ts) == "number"
    and ns.Now() - have.ts < REFRESH then return end
  rec.ts = math.max(ns.Now(), type(have) == "table" and type(have.ts) == "number" and have.ts + 1 or 0)
  book[key] = rec
  ns.Fire("TALENTS", key)
  if ns.Settings().share then Share(key) end
end

local pointsTimer
-- CHARACTER_POINTS_CHANGED: read again a moment later
function GameTalents.OnPointsChanged()
  if pointsTimer then pointsTimer:Cancel() end
  pointsTimer = C_Timer.NewTimer(POINTS_WAIT, function()
    pointsTimer = nil
    ns.SafeCall(GameTalents.ReadOwn)
  end)
end

-- The talents of the member Guildy inspects, read while unit shows them (guid): { trees, classFile }, nil
-- when the game gives none (no API, secret, no points at all: an inspect that brought no talents)
function GameTalents.ReadInspect(unit, guid)
  local now = ns.Try(rawget(_G, "UnitGUID"), unit)
  if ns.IsSecret(now) or not guid or now ~= guid then return nil end
  local tabs = ReadTabs(true)
  local trees = Tal.FromTabs(tabs)
  if not trees or trees[1] + trees[2] + trees[3] == 0 then return nil end
  local _, classFile, classID = ns.Try(rawget(_G, "UnitClass"), unit)
  if ns.AnySecret(classFile, classID) then classFile, classID = nil, nil end
  if classFile then RememberNames(classFile, NamesOf(tabs, classID)) end
  return { trees = trees, classFile = classFile }
end

-- /guildy talentprobe: what the trait system of this client looks like, for the own active config and,
-- with a target that was inspected, the inspect config: config fields, trees with node count and ranks,
-- the first nodes' fields and their entries', and what Guildy reads from it
local function Show(value, depth)
  if ns.IsSecret(value) then return "<secret>" end
  if type(value) ~= "table" then return tostring(value) end
  if (depth or 0) > 0 then return "{…}" end
  local keys = {}
  for k in pairs(value) do keys[#keys + 1] = k end
  table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
  local parts = {}
  for _, k in ipairs(keys) do
    parts[#parts + 1] = (type(k) == "number" and "" or tostring(k) .. "=") .. Show(value[k], (depth or 0) + 1)
    if #parts >= 30 then parts[#parts + 1] = "…" break end
  end
  return "{" .. table.concat(parts, ", ") .. "}"
end

local function ProbeConfig(label, configID)
  local P = ns.Print
  if type(configID) ~= "number" or ns.IsSecret(configID) then
    P(("%s: no config (%s)"):format(label, Show(configID)))
    return
  end
  local info = ns.Try(Api("C_Traits", "GetConfigInfo"), configID)
  P(("%s: config %d info %s"):format(label, configID, Show(info)))
  local read = ReadConfig(configID)
  if not read then
    P(label .. ": nothing readable (no treeIDs, or something secret)")
    return
  end
  local entryInfo = Api("C_Traits", "GetEntryInfo")
  for _, tree in ipairs(read.trees) do
    P(("%s: tree %s, %d nodes, ranksPurchased sum %d"):format(label, Show(tree.id), #tree.nodeIDs, tree.ranks))
    for i = 1, math.min(3, #tree.nodes) do
      local node = tree.nodes[i]
      P(("  node %s"):format(Show(node)))
      local entry = EntryOf(node)
      if entry and entryInfo then P(("  entry %d %s"):format(entry, Show(ns.Try(entryInfo, configID, entry)))) end
    end
  end
  for _, sub in ipairs(read.subOrder) do
    P(("%s: subTreeID %s ranks %d, name %s"):format(label, Show(sub), read.subs[sub], tostring(SubTreeName(configID, sub))))
  end
  local tabs, how = TabsOf(configID, read)
  if tabs then
    P(("%s: Guildy reads %d/%d/%d (by %s)"):format(label, tabs[1].points, tabs[2].points, tabs[3].points, how))
  else
    P(("%s: Guildy reads nothing: %d trees, %d subTreeIDs (wants 3 of either)"):format(label, #read.trees, #read.subOrder))
  end
end

function GameTalents.Probe()
  local P = ns.Print
  P(("talentprobe: GetTalentTabInfo %s, C_Traits %s, C_ClassTalents %s, GetNumSpecializations %s"):format(
    tostring(rawget(_G, "GetTalentTabInfo") ~= nil), type(rawget(_G, "C_Traits")), type(rawget(_G, "C_ClassTalents")),
    Show(ns.Try(rawget(_G, "GetNumSpecializations")))))
  if not Api("C_Traits", "GetConfigInfo") then
    P("talentprobe: no C_Traits.GetConfigInfo on this client")
    return
  end
  ProbeConfig("own", ns.Try(Api("C_ClassTalents", "GetActiveConfigID")))
  local _, _, classID = ns.Try(rawget(_G, "UnitClass"), "player")
  P(("own: class %s, spec IDs %s, names %s"):format(Show(classID),
    Show(ns.Try(Api("C_SpecializationInfo", "GetSpecIDs"), classID)), Show(SpecNames(classID))))
  if ns.Try(rawget(_G, "UnitExists"), "target") then
    ProbeConfig("inspect (target, after an inspect)", InspectConfigID())
  else
    P("inspect: no target")
  end
end

-- Stores the talents read for request's member (ReadInspect); true when they were taken. Sharing goes with
-- the gear read in the same inspect (Game/Gear.lua), or the caller's.
function GameTalents.StoreInspect(request, read)
  if ns.Anon.on or type(read) ~= "table" then return false end
  local guild = ns.GuildData()
  if not guild then return false end
  if Tal.Merge(Book(guild), request.key, { ts = ns.Now(), src = "seen", trees = read.trees }) then
    ns.Fire("TALENTS", request.key)
    return true
  end
  return false
end
