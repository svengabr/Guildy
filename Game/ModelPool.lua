-- Bodies for the character page's model (UI/CharacterPage.lua, routes in Game/Gear.lua): a far member's
-- body needs a player unit of their sex in sight (the donor), and one of the other sex rarely is while
-- the page is open. So whenever a player unit shows up (nameplate, target, mouseover, group), even with
-- the page closed, the pool builds a body per (raceID, sex) that a guild member with stored gear needs:
-- a model scene of the page's template parented to UIParent, small and invisible, whose player actor
-- takes the donor with the member's raceID. A dressed body stays when its donor leaves (checked in game
-- on Forever), so the page later borrows the whole scene into its model area and dresses it there.
-- The viewer's own sex needs no body ("player" is always a donor). At most BUILD_PER_RUN bodies per
-- look, at most one look per THROTTLE seconds, nothing in combat, every unit value checked for secrets.
-- What is missing is kept until the gear (GEAR), the member list (Roster.version) or the pool
-- (MODEL_POOL) changes; while nothing is missing the pool does not listen for player units at all, so a
-- crowded city walks no roster and seeks no donor.
-- /guildy modeltest pool lists the bodies.
local _, ns = ...

local ModelPool = {}
ns.ModelPool = ModelPool

local MODEL_SCENE = 596   -- the scene the page uses (UI/CharacterPage.lua)
local BUILD_PER_RUN = 2   -- bodies built per look
local THROTTLE = 1        -- s between looks
local READY_AFTER = 0.5   -- s a new body needs before it takes items (checked in game)

local bodies = {}         -- "race:sex" -> { scene, actor, race, sex, ready, distance, user }
local spare = {}          -- scenes whose body failed, used again
local lastLook, pending = nil, false
local preferred           -- "race:sex" the open page waits for, built first

local function Key(race, sex) return race .. ":" .. sex end

-- The page waits for a body of race and sex (nil: for none): the next look builds that one first
function ModelPool.Prefer(race, sex)
  preferred = type(race) == "number" and type(sex) == "number" and Key(race, sex) or nil
end

-- The body for raceID race and sex, nil when the pool has none
function ModelPool.Get(race, sex)
  if type(race) ~= "number" or type(sex) ~= "number" then return nil end
  return bodies[Key(race, sex)]
end

-- Puts scene where it waits unseen: on UIParent, tiny, invisible, no mouse
local function Park(scene)
  scene:SetParent(UIParent)
  scene:ClearAllPoints()
  scene:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 0, 0)
  scene:SetSize(8, 8)
  scene:SetAlpha(0)
  scene:EnableMouse(false)
  if scene.EnableMouseWheel then scene:EnableMouseWheel(false) end
  scene:Show()
end

-- The (race, sex) pairs that members with stored gear need and the pool lacks: "race:sex" -> { race, sex }
local function Missing()
  local guild = ns.GuildData()
  local book = guild and type(guild.gear) == "table" and guild.gear
  if not book then return {}, 0 end
  local mine = ns.Try(rawget(_G, "UnitSex"), "player")
  if ns.IsSecret(mine) then mine = nil end
  local own = ns.Names.Key(ns.PlayerName())
  local missing, count = {}, 0
  for _, m in ipairs(ns.Roster.Members()) do
    local rec = m.key ~= own and book[m.key]
    if type(rec) == "table" and type(rec.race) == "number" and (rec.sex == 2 or rec.sex == 3) and rec.sex ~= mine
      and type(rec.items) == "table" and next(rec.items) ~= nil then
      local key = Key(rec.race, rec.sex)
      if not bodies[key] and not missing[key] then
        missing[key] = { race = rec.race, sex = rec.sex }
        count = count + 1
      end
    end
  end
  return missing, count
end

local EVENTS = { "NAME_PLATE_UNIT_ADDED", "PLAYER_TARGET_CHANGED", "UPDATE_MOUSEOVER_UNIT", "GROUP_ROSTER_UPDATE" }
local watcher = CreateFrame("Frame")
local watching = false
local wanted -- { missing, count, roster, guild } from Missing(); nil when stale

-- Missing() as last worked out, again only when stale or the member list or guild changed
local function Wanted()
  local guild = ns.GuildData()
  local w = wanted
  if not (w and w.roster == ns.Roster.version and w.guild == guild) then
    local missing, count = Missing()
    w = { missing = missing, count = count, roster = ns.Roster.version, guild = guild }
    wanted = w
  end
  return w.missing, w.count
end

-- Listens for player units in sight only while a body is missing
local function Watch()
  local _, count = Wanted()
  local want = count > 0
  if want == watching then return end
  watching = want
  local method = want and watcher.RegisterEvent or watcher.UnregisterEvent
  for _, event in ipairs(EVENTS) do pcall(method, watcher, event) end
end

local function Stale()
  wanted = nil
  Watch()
end

-- A scene of the page's template, parked: scene, actor and the camera's distance; nil when the client
-- has no such scene
local function NewScene()
  local scene = table.remove(spare)
  if not scene then
    local ok, frame = pcall(CreateFrame, "ModelScene", nil, UIParent, "ModelSceneMixinTemplate")
    if not ok or type(frame) ~= "table" or type(frame.TransitionToModelSceneID) ~= "function"
      or type(frame.GetPlayerActor) ~= "function" then
      return nil
    end
    scene = frame
  end
  Park(scene)
  pcall(scene.TransitionToModelSceneID, scene, MODEL_SCENE, 1, 1, true)
  local actor = ns.Try(scene.GetPlayerActor, scene)
  if type(actor) ~= "table" then
    scene:Hide()
    spare[#spare + 1] = scene
    return nil
  end
  local camera = type(scene.GetActiveCamera) == "function" and ns.Try(scene.GetActiveCamera, scene)
  local distance = type(camera) == "table" and ns.Try(camera.GetZoomDistance, camera)
  if ns.IsSecret(distance) or type(distance) ~= "number" then distance = nil end
  return scene, actor, distance
end

-- Builds the body of race and sex from donor unit: true when the game took it
local function Build(race, sex, unit)
  local scene, actor, distance = NewScene()
  if not scene then return false end
  if not ns.GameGear.LoadModel(actor, { kind = "donor", unit = unit, race = race, sex = sex }) then
    scene:Hide()
    spare[#spare + 1] = scene
    return false
  end
  local body = { scene = scene, actor = actor, race = race, sex = sex, distance = distance, ready = false }
  bodies[Key(race, sex)] = body
  C_Timer.After(READY_AFTER, function() body.ready = true end)
  return true
end

-- One look: up to BUILD_PER_RUN missing bodies from the player units in sight; looks again a moment later
-- while bodies are missing and donors were found
local function Look()
  pending = false
  if ns.Try(rawget(_G, "InCombatLockdown")) == true then return end
  lastLook = GetTime()
  local missing, count = Wanted()
  if count == 0 then return end
  local order = {}
  for key, pair in pairs(missing) do order[#order + 1] = { key = key, race = pair.race, sex = pair.sex } end
  -- the body the open page waits for first, then by race
  table.sort(order, function(a, b)
    if (a.key == preferred) ~= (b.key == preferred) then return a.key == preferred end
    return a.key < b.key
  end)
  local donors, built = {}, 0
  for _, pair in ipairs(order) do
    if built >= BUILD_PER_RUN then break end
    if donors[pair.sex] == nil then donors[pair.sex] = ns.GameGear.FindDonor(pair.sex) or false end
    local unit = donors[pair.sex]
    if unit and Build(pair.race, pair.sex, unit) then built = built + 1 end
  end
  if built == 0 then return end
  ns.Fire("MODEL_POOL")
  if count > built then ModelPool.Wake() end
end

-- A player unit may have come in sight: looks now, or after the throttle when it looked just before
function ModelPool.Wake()
  if pending then return end
  local now = GetTime()
  if lastLook == nil or now - lastLook >= THROTTLE then return Look() end
  pending = true
  C_Timer.After(THROTTLE - (now - lastLook), function() ns.SafeCall(Look) end)
end

-- The page borrows body for member key: the pool leaves it to the page until Give
function ModelPool.Take(body, key) body.user = key end

-- The page gives body back: parked unseen again, its body and gear kept
function ModelPool.Give(body)
  body.user = nil
  Park(body.scene)
end

-- Lines for /guildy modeltest pool
function ModelPool.Lines()
  local keys = {}
  for key in pairs(bodies) do keys[#keys + 1] = key end
  table.sort(keys)
  if #keys == 0 then return { "modeltest pool: empty" } end
  local lines = {}
  for _, key in ipairs(keys) do
    local b = bodies[key]
    lines[#lines + 1] = ("modeltest pool: race %d (%s), sex %d: %s%s"):format(b.race, ns.GameGear.RACE_FILES[b.race] or "?",
      b.sex, b.ready and "ready" or "loading", b.user and (", on the page for " .. b.user) or "")
  end
  local _, count = Wanted()
  if count > 0 then lines[#lines + 1] = ("modeltest pool: %d more wanted, waiting for a player of that sex"):format(count) end
  return lines
end

watcher:SetScript("OnEvent", function() ns.SafeCall(ModelPool.Wake) end)
ns.On("GEAR", Stale)
ns.On("MODEL_POOL", Stale)
ns.On("ROSTER", Watch) -- a new member list or guild makes Wanted work it out anew
