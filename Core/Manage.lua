-- Guild management rules, pure: what the player may do with a member (Blizzard's own checks from its
-- member detail frame) and the slash commands that do it. On Forever /gpromote, /gdemote and /gremove
-- are Blizzard's secure slash commands; run from a secure macro button they reach the server untainted
-- (verified in game, see UI/Commands.lua).
local _, ns = ...

local Manage = {}
ns.Manage = Manage

local COMMANDS = { promote = "/gpromote", demote = "/gdemote", remove = "/gremove" }

-- Rank indexes are GetGuildRosterInfo's: 0 = guild master, numRanks - 1 = lowest rank.
-- can = { promote, demote, remove } from CanGuildPromote/CanGuildDemote/CanGuildRemove.
function Manage.Rights(targetRank, myRank, numRanks, can, isSelf)
  local rights = { promote = false, demote = false, remove = false }
  if isSelf or type(targetRank) ~= "number" or type(myRank) ~= "number" or type(numRanks) ~= "number" then
    return rights
  end
  can = can or {}
  -- promoting never reaches the player's own rank; demoting stops at the lowest rank
  rights.promote = can.promote and targetRank > myRank + 1 or false
  rights.demote = can.demote and targetRank > myRank and targetRank < numRanks - 1 or false
  rights.remove = can.remove and targetRank > myRank or false
  return rights
end

-- "/gdemote Xii Lightspark"; nil for an unknown kind or a missing name. The guild slash commands want
-- Forever's name with the space ("Dr Doomshot"); "Dr-Doomshot" is silently ignored by the server
-- (verified in game; Blizzard's invite dialog is the other way round, see Names.ToServer).
function Manage.Command(kind, name)
  local command = COMMANDS[kind]
  local full = ns.Names.Normalize(name)
  if not command or full == "" then return nil end
  return command .. " " .. full
end

-- Batch: several picked members, one secure click each (UI/Commands.lua, UI.RunBatch). Forever runs
-- /gpromote, /gdemote and /gremove only from the player's own click, so Guildy steps through the picks:
-- the button names the next member, a click sends the command, and the button stays locked until the
-- roster shows the change. Then the next member comes. b = { kind, keys, at, done, skipped, waiting }.
function Manage.NewBatch(kind, keys)
  local list = {}
  for i, key in ipairs(keys or {}) do list[i] = key end
  return { kind = kind, keys = list, at = 1, done = 0, skipped = 0 }
end

-- The member to act on now: the first pick from b.at that find(key) still knows and rights(m)[kind]
-- still allows; the others are skipped (left the guild, the rank changed meanwhile). nil = finished.
function Manage.BatchCurrent(b, find, rights)
  while b.at <= #b.keys do
    local key = b.keys[b.at]
    local m = find(key)
    if b.waiting and b.waiting.key == key then return m end
    if m and rights(m)[b.kind] then return m end
    b.skipped = b.skipped + 1
    b.at = b.at + 1
  end
  return nil
end

-- The command for m went out at now: wait for the roster
function Manage.BatchSent(b, m, now)
  b.waiting = { key = m.key, rank = m.rankIndex, at = now }
end

-- Whether the roster now shows the change waited for (removed: gone; rank: one step the right way).
-- Then the batch moves on to the next pick.
function Manage.BatchConfirm(b, find)
  local w = b.waiting
  if not w then return false end
  local m = find(w.key)
  local changed
  if not m then
    changed = true -- removed (or left on their own: nothing more to do for them)
  elseif b.kind == "promote" then
    changed = type(m.rankIndex) == "number" and type(w.rank) == "number" and m.rankIndex < w.rank
  elseif b.kind == "demote" then
    changed = type(m.rankIndex) == "number" and type(w.rank) == "number" and m.rankIndex > w.rank
  end
  if not changed then return false end
  b.waiting = nil
  b.done = b.done + 1
  b.at = b.at + 1
  return true
end

-- No change after limit seconds: the lock goes, the same member can be clicked again
function Manage.BatchTimedOut(b, now, limit)
  if b.waiting and now - b.waiting.at >= limit then
    b.waiting = nil
    return true
  end
  return false
end

-- The player passes over the current member
function Manage.BatchSkip(b)
  if b.at > #b.keys then return end
  b.waiting = nil
  b.skipped = b.skipped + 1
  b.at = b.at + 1
end
