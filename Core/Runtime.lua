-- Shared runtime helpers: time, printing, safe calls, the player's name and a tiny internal event bus
-- (ns.On / ns.Fire) the UI listens to. Nothing here touches the game at load time.
local addonName, ns = ...

ns.ADDON = addonName or "Guildy"
ns.CHAT_TAG = "[Guildy]"

function ns.Now()
  local serverTime = rawget(_G, "GetServerTime")
  return serverTime and serverTime() or os.time()
end

function ns.DB()
  return rawget(_G, "GuildyDB")
end

function ns.Settings()
  local db = ns.DB()
  return db and db.settings or {}
end

function ns.Version()
  local getMeta = (C_AddOns and C_AddOns.GetAddOnMetadata) or rawget(_G, "GetAddOnMetadata")
  local version = getMeta and getMeta(ns.ADDON, "Version")
  if not version or version == "" or version:find("@", 1, true) then return "dev" end
  return version
end

-- Own full character name ("First Last"; Forever returns the last name as second value of UnitName)
function ns.PlayerName()
  return ns.Names.FromUnit(UnitName("player"))
end

function ns.Print(text)
  local frame = rawget(_G, "DEFAULT_CHAT_FRAME")
  local line = "|cffd4a017" .. ns.CHAT_TAG .. "|r " .. tostring(text)
  if frame and frame.AddMessage then frame:AddMessage(line) else print(line) end
end

-- Runs fn and reports errors through the client's error handler instead of breaking the caller
function ns.SafeCall(fn, ...)
  local ok, err = pcall(fn, ...)
  if not ok then
    local handler = rawget(_G, "geterrorhandler")
    if handler then handler()(err) else print(err) end
  end
  return ok
end

-- Forever has Retail's secret values: in instances and encounters chat texts and senders can be secret,
-- and addon code must not inspect them (no indexing, comparing or pattern matching).
function ns.IsSecret(value)
  local check = rawget(_G, "issecretvalue")
  return check ~= nil and check(value) == true
end

-- True when any of the values is secret
function ns.AnySecret(...)
  for i = 1, select("#", ...) do
    if ns.IsSecret((select(i, ...))) then return true end
  end
  return false
end

-- Calls fn(...) only if it exists; returns its results, or nil when missing or failing
function ns.Try(fn, ...)
  if type(fn) ~= "function" then return nil end
  local result = { pcall(fn, ...) }
  if not result[1] then return nil end
  return unpack(result, 2, table.maxn(result))
end

-- Internal events: "ROSTER" (roster changed), "PROFS" (profession data changed), "CHAT" (new chat line)
local listeners = {}

function ns.On(event, fn)
  listeners[event] = listeners[event] or {}
  table.insert(listeners[event], fn)
end

local function FireAll(event, ...)
  for _, fn in ipairs(listeners[event] or {}) do ns.SafeCall(fn, ...) end
end

function ns.Fire(event, ...)
  ns.Perf.Call("fire", event, FireAll, event, ...)
end

-- Current guild key: guild name + realm, nil when not in a guild
function ns.GuildKey()
  if not IsInGuild or not IsInGuild() then return nil end
  local name = GetGuildInfo("player")
  if not name then return nil end
  local realm = ns.Try(rawget(_G, "GetNormalizedRealmName")) or "?"
  return name .. "@" .. realm
end

-- Data of the current guild in GuildyDB (created on first use), nil when not in a guild
function ns.GuildData()
  local key, db = ns.GuildKey(), ns.DB()
  if not key or not db then return nil end
  return ns.Store.Guild(db, key)
end
