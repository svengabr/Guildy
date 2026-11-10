-- The player's communities (character and Battle.net communities, not the guild) for the
-- communities view: list, channels (streams), members and chat. All of it comes from C_Club, the
-- same source as Blizzard's window; the chat lines go through ns.Chat's club stream reader. Counts
-- unread lines per community in this session (lines that came in while it was not shown). Fires ns
-- "COMMUNITY" (list, channels, members) and "CHAT" with kind "community" (new lines).
local _, ns = ...

local Communities = {}
ns.Communities = Communities

local GUILD_TYPE = 2 -- Enum.ClubType.Guild
local PRESENCE = { online = 1, mobile = 2, offline = 3, away = 4, busy = 5 } -- Enum.ClubMemberPresence

local focused  -- { clubId, streamId } while the view shows a channel
local unread = {} -- clubId -> lines that came in while it was not shown
local viewed = {} -- clubId -> true once Guildy showed it in this session

local function GuildType()
  local types = Enum and Enum.ClubType
  return types and types.Guild or GUILD_TYPE
end

local function Lower(text)
  return type(text) == "string" and text:lower() or ""
end

-- Blizzard's own list (its favorites prediction, hooked once to render again)
local favoritesHooked
local function BlizzardList()
  local frame = rawget(_G, "CommunitiesFrame")
  local list = frame and frame.CommunitiesList
  if type(list) ~= "table" then return nil end
  -- "Set favorite" in Blizzard's menu: Guildy shows it right away (the server reports it later)
  if not favoritesHooked and type(list.SetFavorite) == "function" then
    favoritesHooked = true
    hooksecurefunc(list, "SetFavorite", function() C_Timer.After(0, function() ns.Fire("COMMUNITY") end) end)
  end
  return list
end

-- Whether a community is a favorite: Blizzard's prediction right after its menu set it, else the
-- server's favoriteTimeStamp (as Blizzard's list decides it)
local function IsFavorite(club)
  local list = BlizzardList()
  local pending = list and type(list.pendingFavorites) == "table" and list.pendingFavorites[club.clubId]
  if pending then return pending ~= 0 end
  return club.favoriteTimeStamp ~= nil
end

-- The player's communities, favorites first, then by name: { {clubId, name, clubType, memberCount,
-- unread, favorite} }
function Communities.List()
  if not (C_Club and C_Club.GetSubscribedClubs) then return {} end
  local list = {}
  for _, club in ipairs(ns.Try(C_Club.GetSubscribedClubs) or {}) do
    if type(club) == "table" and club.clubId and club.clubType ~= GuildType() then
      list[#list + 1] = {
        clubId = club.clubId, name = ns.Anon.Guild(club.name or "?"), clubType = club.clubType,
        shortName = not ns.Anon.on and club.shortName or nil, -- made-up names for pictures: Core/Anon.lua
        avatarId = club.avatarId, memberCount = club.memberCount, unread = unread[club.clubId] or 0,
        hasUnread = Communities.HasUnread(club.clubId),
        favorite = IsFavorite(club),
      }
    end
  end
  table.sort(list, function(a, b)
    if a.favorite ~= b.favorite then return a.favorite end
    if Lower(a.name) ~= Lower(b.name) then return Lower(a.name) < Lower(b.name) end
    return tostring(a.clubId) < tostring(b.clubId)
  end)
  return list
end

-- Whether clubId is one of the player's communities
function Communities.Has(clubId)
  for _, club in ipairs(Communities.List()) do
    if club.clubId == clubId then return true end
  end
  return false
end

-- A community's channels in Blizzard's order (the general channel first): { {streamId, name} }
function Communities.Streams(clubId)
  if not (clubId and C_Club and C_Club.GetStreams) then return {} end
  local list = {}
  for _, stream in ipairs(ns.Try(C_Club.GetStreams, clubId) or {}) do
    if type(stream) == "table" and stream.streamId then
      list[#list + 1] = { streamId = stream.streamId, name = (type(stream.name) == "string" and stream.name ~= "" and stream.name) or rawget(_G, "COMMUNITIES_DEFAULT_CHANNEL_NAME") or "?", sortOrder = stream.sortOrder }
    end
  end
  table.sort(list, function(a, b)
    local sa, sb = tonumber(a.sortOrder) or 0, tonumber(b.sortOrder) or 0
    if sa ~= sb then return sa < sb end
    return (tonumber(a.streamId) or 0) < (tonumber(b.streamId) or 0)
  end)
  return list
end

-- A community without channels yet: asks the server for them (as Blizzard's window does when it
-- opens), at most every few seconds; they arrive as CLUB_STREAMS_LOADED
local streamsAsked = {}
function Communities.RequestStreams(clubId)
  if not (clubId and C_Club) then return end
  if streamsAsked[clubId] and ns.Now() - streamsAsked[clubId] < 5 then return end
  streamsAsked[clubId] = ns.Now()
  ns.Try(C_Club.FocusCommunityStreams)
end

-- A community's chosen icon (the avatar picked when it was created). Only C_Club.SetAvatarTexture
-- knows the picture, and it is protected: it works right after a click of the player, but is blocked
-- in combat and from game events (ADDON_ACTION_BLOCKED, found in game 2026-11-09; a blocked call
-- raises no error, the texture just stays as it was). So Guildy draws each avatar once, right after a
-- click, into a texture of its own and keeps the file and texture coordinates it got; rows show those
-- with plain SetTexture / SetTexCoord, never calling the protected function again.
local avatars = {}  -- "clubType:avatarId" -> { file, coords }
local scratch       -- hidden texture the avatars are drawn into

local function AvatarKey(club)
  return tostring(club.clubType) .. ":" .. tostring(club.avatarId)
end

-- The remembered picture of club's avatar ({file, coords}), drawing it first when draw is true (right
-- after a click of the player, out of combat). nil while it is not known.
function Communities.Avatar(club, draw)
  if not (club and club.avatarId) then return nil end
  local key = AvatarKey(club)
  if avatars[key] then return avatars[key] end
  if not draw or InCombatLockdown() or not (C_Club and C_Club.SetAvatarTexture) then return nil end
  scratch = scratch or CreateFrame("Frame", nil, UIParent):CreateTexture()
  scratch:SetTexture(nil)
  if not pcall(C_Club.SetAvatarTexture, scratch, club.avatarId, club.clubType) then return nil end
  local file = scratch:GetTexture()
  if not file then return nil end -- blocked: nothing was drawn
  avatars[key] = { file = file, coords = { scratch:GetTexCoord() } }
  return avatars[key]
end

-- Whether the player may invite to a community (its owner and moderators, or everyone when allowed)
function Communities.CanInvite(clubId)
  local privileges = clubId and C_Club and ns.Try(C_Club.GetClubPrivileges, clubId)
  return type(privileges) == "table" and privileges.canSendInvitation and true or false
end

-- (No inviting from Guildy: InviteToClub is forbidden for addons, ADDON_ACTION_FORBIDDEN, found in
-- game 2026-11-09. Blizzard's own invite button in its window, with the community picked there by the
-- player, is the clean way; Guildy only shows that window.)

-- Online states: online, away and busy count as online (mobile is the Battle.net app, not in game)
function Communities.IsOnline(presence)
  return presence == PRESENCE.online or presence == PRESENCE.away or presence == PRESENCE.busy
end

local function ClassFile(classID)
  local info = classID and C_CreatureInfo and ns.Try(C_CreatureInfo.GetClassInfo, classID)
  return info and info.classFile or nil
end

-- A community's members, online first, then by name: { {name, level, classFile, zone, presence, online, isSelf} }
function Communities.Members(clubId)
  if not (clubId and C_Club and C_Club.GetClubMembers and C_Club.GetMemberInfo) then return {} end
  local list = {}
  for _, memberId in ipairs(ns.Try(C_Club.GetClubMembers, clubId) or {}) do
    local info = ns.Try(C_Club.GetMemberInfo, clubId, memberId)
    if type(info) == "table" and type(info.name) == "string" and not ns.IsSecret(info.name) and info.name ~= "" then
      list[#list + 1] = {
        name = ns.Anon.Name(ns.Names.Normalize(info.name)), full = info.name, level = info.level,
        classFile = ClassFile(info.classID), zone = info.zone, presence = info.presence,
        online = Communities.IsOnline(info.presence), isSelf = info.isSelf or nil,
        memberId = info.memberId or memberId, guid = not ns.IsSecret(info.guid) and info.guid or nil,
        note = type(info.memberNote) == "string" and info.memberNote ~= "" and not ns.IsSecret(info.memberNote)
          and info.memberNote or nil,
      }
    end
  end
  table.sort(list, function(a, b)
    if a.online ~= b.online then return a.online end
    return Lower(a.name) < Lower(b.name)
  end)
  return list
end

-- Chat lines of a channel, oldest first (same shape as the guild chat's)
function Communities.History(clubId, streamId)
  return ns.Anon.Lines(ns.Chat.StreamLines(clubId, streamId, "community") or {})
end

function Communities.HistoryState(clubId, streamId)
  return ns.Chat.StreamState(clubId, streamId)
end

function Communities.LoadOlder(clubId, streamId)
  local asked = ns.Chat.StreamLoadOlder(clubId, streamId)
  -- an empty channel gets no answer: render again once the request ran out, so "loading" goes away
  if asked then
    C_Timer.After(6, function() ns.Fire("CHAT", "community", clubId, streamId) end)
  end
  return asked
end

-- Focus a channel while the view shows it (the server then sends history and updates); nil unfocuses
function Communities.Focus(clubId, streamId)
  if not (C_Club and C_Club.FocusStream) then return end
  if focused and (focused[1] ~= clubId or focused[2] ~= streamId) then
    ns.Try(C_Club.UnfocusStream, focused[1], focused[2])
    if focused[1] ~= clubId then ns.Try(C_Club.ClearClubPresenceSubscription) end
    focused = nil
  end
  if clubId then unread[clubId], viewed[clubId] = nil, true end
  if not clubId or not streamId or focused then return end
  -- the members' online state only arrives for the community subscribed to (as Blizzard's window does)
  ns.Try(C_Club.SetClubPresenceSubscription, clubId)
  focused = ns.Try(C_Club.FocusStream, clubId, streamId) and { clubId, streamId } or nil
  -- only a few lines cached: fetch a first page right away
  if #Communities.History(clubId, streamId) < 50 then Communities.LoadOlder(clubId, streamId) end
end

function Communities.Focused()
  return focused and focused[1], focused and focused[2]
end

-- Sends a line to a channel. Returns false when the client refused it.
function Communities.Send(clubId, streamId, text)
  if type(text) ~= "string" or text:match("^%s*$") then return true end
  if not (clubId and streamId and C_Club and C_Club.SendMessage) then return false end
  return (pcall(C_Club.SendMessage, clubId, streamId, text))
end

-- Joining ------------------------------------------------------------------------------------------
-- Blizzard's "Join or create a community" does not work under Guildy (and creating is broken on
-- Forever), so Guildy offers the two ways in itself: invitations a member sent to the player, and an
-- invite link or code.

-- Invitations to the player: { {clubId, name, inviter, memberCount} }
function Communities.Invitations()
  if not (C_Club and C_Club.GetInvitationsForSelf) then return {} end
  local list = {}
  for _, invitation in ipairs(ns.Try(C_Club.GetInvitationsForSelf) or {}) do
    local club = type(invitation) == "table" and invitation.club
    if type(club) == "table" and club.clubId then
      local inviter = type(invitation.inviter) == "table" and invitation.inviter.name or nil
      if ns.IsSecret(inviter) then inviter = nil end
      list[#list + 1] = { clubId = club.clubId, name = ns.Anon.Guild(club.name or "?"), inviter = ns.Anon.Name(inviter),
        memberCount = club.memberCount, clubType = club.clubType, avatarId = club.avatarId,
        shortName = not ns.Anon.on and club.shortName or nil }
    end
  end
  return list
end

-- (Accepting and declining: Blizzard's own buttons of its invitation frame, UI/Commands.lua.
-- C_Club.AcceptInvitation from addon code is protected like the other joins.)

-- The ticket of an invite link: a chat link (|HclubTicket:…|h), a link with /invite/…, or the code itself
function Communities.ParseTicket(text)
  if type(text) ~= "string" then return nil end
  text = text:match("^%s*(.-)%s*$")
  local ticket = text:match("clubTicket:([%w%-_]+)") or text:match("/invite/([%w%-_]+)")
  if ticket then return ticket end
  if text:match("^[%w%-_]+$") and #text >= 4 then return text end
  return nil
end

-- The clickable invite link of a ticket, as Blizzard writes it into the chat
function Communities.TicketLink(ticket)
  return "|cffffd100|HclubTicket:" .. ticket .. "|h[" .. ns.L.COMMUNITIES_LINK_NAME .. "]|h|r"
end

-- Joins with an invite link or code. C_Club.RedeemTicket is protected (ADDON_ACTION_FORBIDDEN for
-- Guildy, found in game 2026-11-09; pcall does not catch it), so Guildy never calls it: it writes the
-- invite as a link into Blizzard's chat window. A click there runs Blizzard's own link handler (its
-- invite preview with the join button), untainted. Returns "invalid" (no ticket in the text) or "linked".
function Communities.Redeem(text)
  local ticket = Communities.ParseTicket(text)
  if not ticket then return "invalid" end
  ns.Print(ns.L.COMMUNITIES_LINK_CLICK:format(Communities.TicketLink(ticket)))
  return "linked"
end

-- Opens Blizzard's "Create a community" dialog. It lives in Blizzard_CommunitiesSecure, a secure part
-- that the rest of the UI only steers by attributes (CommunitiesCreateCommunityDialog in
-- CommunitiesAddDialogInsecure.lua); C_Club.CreateClub runs there on the player's click of its Create
-- button, so Guildy opening it taints nothing. Returns false when the dialog is missing (Blizzard's
-- communities not loaded) or in combat (attributes of secure frames are locked then).
function Communities.OpenCreate()
  if InCombatLockdown() then return false end
  local open = rawget(_G, "CommunitiesCreateCommunityDialog")
  if type(open) ~= "function" then return false end
  return (pcall(open))
end

-- /guildy communitydebug: Blizzard's join / create dialogs (do they exist, are they shown and where,
-- did addon code taint the values they read) and the protected C_Club calls
local DEBUG_FRAMES = { "CommunitiesFrame", "CommunitiesAddDialog", "CommunitiesCreateDialog", "CommunitiesTicketPreviewDialog",
  "ClubFinderCommunityAndGuildFinderFrame", "CommunitiesFrameCommunitiesList" }
local DEBUG_FIELDS = { "selectedClubId", "selectedStreamId", "displayMode", "privilegesClubId" }

function Communities.Debug()
  local out = {}
  local secure = rawget(_G, "issecurevariable")
  local function Secure(tbl, key)
    if not secure then return "?" end
    local ok, isSecure, taintedBy = pcall(secure, tbl, key)
    if not ok then return "err" end
    return isSecure and "secure" or ("TAINTED by " .. tostring(taintedBy))
  end
  for _, name in ipairs(DEBUG_FRAMES) do
    local frame = rawget(_G, name)
    if type(frame) ~= "table" then
      out[#out + 1] = name .. ": missing"
    else
      local left, bottom, width, height = ns.Try(frame.GetRect, frame)
      out[#out + 1] = ("%s: shown %s visible %s strata %s level %s rect %s,%s %sx%s alpha %s global %s"):format(name,
        tostring((ns.Try(frame.IsShown, frame))), tostring((ns.Try(frame.IsVisible, frame))),
        tostring((ns.Try(frame.GetFrameStrata, frame))), tostring((ns.Try(frame.GetFrameLevel, frame))),
        tostring(left and math.floor(left)), tostring(bottom and math.floor(bottom)),
        tostring(width and math.floor(width)), tostring(height and math.floor(height)),
        tostring((ns.Try(frame.GetEffectiveAlpha, frame))), Secure(_G, name))
    end
  end
  local host = rawget(_G, "CommunitiesFrame")
  if type(host) == "table" then
    for _, key in ipairs(DEBUG_FIELDS) do
      out[#out + 1] = "CommunitiesFrame." .. key .. " = " .. tostring(rawget(host, key)) .. " (" .. Secure(host, key) .. ")"
    end
  end
  local clubId, streamId = Communities.Focused()
  if clubId then out[#out + 1] = ns.Chat.StreamDebug(clubId, streamId) end
  for _, fn in ipairs({ "CreateClub", "RedeemTicket", "AcceptInvitation", "ValidateTicket" }) do
    out[#out + 1] = "C_Club." .. fn .. ": " .. tostring(C_Club and C_Club[fn] ~= nil)
  end
  return out
end

-- Game events -------------------------------------------------------------------------------------

-- A new line in any club stream. Returns true when it was a community's (not the guild's).
function Communities.OnMessageAdded(clubId, streamId)
  if not clubId or clubId == ns.Try(C_Club and C_Club.GetGuildClubId) then return false end
  local shown = focused and focused[1] == clubId and focused[2] == streamId and ns.UI and ns.UI.IsShown()
    and ns.UI.Current() == "communities"
  if not shown then unread[clubId] = (unread[clubId] or 0) + 1 end
  ns.Fire("CHAT", "community", clubId, streamId)
  if not shown then ns.Fire("COMMUNITY") end
  return true
end

function Communities.Changed()
  ns.Fire("COMMUNITY")
end

function Communities.Unread(clubId)
  return unread[clubId] or 0
end

-- Whether a community has something new: lines that came in while Guildy did not show it, or, until
-- Guildy showed it in this session, what Blizzard's own window marks as unread (lines from before
-- the login).
function Communities.HasUnread(clubId)
  if (unread[clubId] or 0) > 0 then return true end
  if viewed[clubId] then return false end
  local util = rawget(_G, "CommunitiesUtil")
  local check = type(util) == "table" and util.DoesCommunityHaveUnreadMessages
  return check and ns.Try(check, clubId) == true or false
end

-- Whether any community (not the guild) has something new
function Communities.AnyUnread()
  for _, club in ipairs(Communities.List()) do
    if club.hasUnread then return true end
  end
  return false
end
