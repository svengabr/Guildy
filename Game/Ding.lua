-- The game side of Core/Ding.lua: after every roster scan finds who has just reached the top level,
-- shows the banner (UI/Ding.lua) and says it in guild chat. Only one Guildy user says it: each waits a
-- short random time first and stays quiet when a "[Guildy]" line with the member's name has gone
-- through guild chat by then. Guild chat itself is the signal, nothing is sent between the clients.
-- The game sends the roster only when asked, so Guildy asks every POLL seconds. Nothing is saved: the
-- first roster of a session (or of another guild) only sets the levels to compare with.
local _, ns = ...

local GameDing = {}
ns.GameDing = GameDing

local D = ns.Ding
local POLL = 30 -- seconds between two requests for the roster
local WAIT = 3  -- the longest wait before the line goes to guild chat
local levels, guildKey
local said = {} -- memberKey -> true: the line about this member is in guild chat (or on its way)
local announced = {} -- memberKey -> true: found once this session, never again (a roster can fall back)

local function Max()
  return ns.Census.MAX_LEVEL
end

local function Post(m)
  if said[m.key] then return end
  said[m.key] = true
  ns.Chat.Send("guild", D.Line(ns.L.DING_CHAT, m.name, Max()))
end

local function Announce(m)
  if announced[m.key] then return end
  announced[m.key] = true
  local settings = ns.Settings()
  if settings.ding60 ~= false and ns.UI and ns.UI.ShowDing then ns.UI.ShowDing(m) end
  -- made-up names for pictures (Core/Anon.lua) must not reach the guild
  if settings.ding60Post ~= false and not ns.Anon.on and not said[m.key] then
    C_Timer.After(math.random() * WAIT, function() ns.SafeCall(Post, m) end)
  end
end

ns.On("ROSTER", function()
  local key = ns.GuildKey()
  if key ~= guildKey then guildKey, levels, said, announced = key, nil, {}, {} end
  if not key then return end
  local found
  found, levels = D.Find(levels, ns.Roster.Members(), Max())
  for _, m in ipairs(found) do Announce(m) end
end)

-- A line of guild chat: when it is Guildy's line about a member, nobody here says it again. The own
-- roster may not show the level yet, so every member counts; of several whose names the line holds
-- ("Au" and "Au Tsch") the longest is meant.
function GameDing.OnGuildChat(text)
  if type(text) ~= "string" or text:sub(1, #D.TAG) ~= D.TAG then return end
  local best
  for _, m in ipairs(ns.Roster.Members()) do
    if D.Said(text, m.name) and (not best or #m.name > #best.name) then best = m end
  end
  if best then said[best.key] = true end
end

-- The own character went up a level. At the top level it is announced at once, without waiting for
-- the roster to show it (the game may not answer a request so soon after the last one); the roster
-- is asked all the same, for the tabs.
function GameDing.OnLevelUp(level)
  if type(level) ~= "number" or level < Max() or not ns.GuildKey() then return end
  local _, classFile = UnitClass("player")
  local name = ns.PlayerName()
  Announce(ns.Roster.Me() or { key = ns.Names.Key(name), name = name, classFile = classFile })
  C_Timer.After(1, function() ns.Roster.Request(true) end)
end

function GameDing.Start()
  C_Timer.NewTicker(POLL, function()
    local settings = ns.Settings()
    if settings.ding60 == false and settings.ding60Post == false then return end
    if IsInGuild() then ns.Roster.Request(true, true) end
  end)
end

-- /guildy ding: the banner for the own character, to look at it. Says nothing in guild chat.
function GameDing.Test()
  local _, classFile = UnitClass("player")
  ns.UI.ShowDing(ns.Roster.Me() or { name = ns.PlayerName(), classFile = classFile })
end
