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
