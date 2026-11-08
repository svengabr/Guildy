-- Guild and officer chat for the chat tab. History comes from the guild club (C_Club, the same source
-- as Blizzard's window); if that yields nothing, from lines captured since login. Join/leave/rank
-- system messages are captured and merged in by time. Also remembers who whispered the player
-- recently (invite suggestions). Fires ns "CHAT".
local _, ns = ...

local Chat = {}
ns.Chat = Chat

local MAX_LINES = 300
local CLUB_LINES = 150   -- first request when the stream has nothing cached
local CLUB_MORE = 100    -- each further request when scrolling up
local CLUB_MAX = 3000    -- lines kept for display
local REQUEST_TIMEOUT = 5
local RELOAD_GAP = 300   -- a logout followed by a login within this many seconds counts as a reload
local buffers = { guild = {}, officer = {} }
local systemLines = {}
local whispers = {}
local systemPatterns
local focused
local pending -- time of the outstanding "older messages" request
local seenMark -- lines after this time are new for this session (see Chat.InitSeen)

local function Push(list, line, max)
  list[#list + 1] = line
  while #list > (max or MAX_LINES) do table.remove(list, 1) end
end

local function ClassOfGuid(guid)
  if not guid or guid == "" then return nil end
  local getInfo = rawget(_G, "GetPlayerInfoByGUID")
  local ok, _, classFile = pcall(getInfo or error, guid)
  return ok and classFile or nil
end

local function SystemPatterns()
  if systemPatterns then return systemPatterns end
  systemPatterns = {}
  for _, global in ipairs({ "ERR_GUILD_JOIN_S", "ERR_GUILD_LEAVE_S", "ERR_GUILD_REMOVE_SS", "ERR_GUILD_PROMOTE_SSS",
    "ERR_GUILD_DEMOTE_SSS", "ERR_GUILD_LEADER_CHANGED_SS" }) do
    local fmt = rawget(_G, global)
    if type(fmt) == "string" then systemPatterns[#systemPatterns + 1] = ns.Search.FormatToPattern(fmt) end
  end
  return systemPatterns
end

-- Game events ------------------------------------------------------------------------------------

function Chat.OnGuildMessage(kind, text, sender, guid)
  if ns.AnySecret(text, sender, guid) then return end
  local member = ns.Roster.Find(sender)
  Push(buffers[kind], {
    kind = kind, sender = ns.Names.Normalize(sender), senderFull = sender, text = text, ts = ns.Now(),
    classFile = (member and member.classFile) or ClassOfGuid(guid),
  })
  ns.Fire("CHAT", kind)
end

function Chat.OnSystemMessage(text)
  if ns.IsSecret(text) or type(text) ~= "string" then return end
  for _, pattern in ipairs(SystemPatterns()) do
    if text:match(pattern) then
      Push(systemLines, { system = true, text = text, ts = ns.Now() }, 50)
      ns.Fire("CHAT", "guild")
      ns.Roster.Request(true)
      return
    end
  end
end

function Chat.OnWhisper(sender)
  if ns.IsSecret(sender) then return end
  local name = ns.Names.Normalize(sender)
  if name == "" or ns.Roster.IsMember(name) then return end
  for i = #whispers, 1, -1 do
    if ns.Names.Same(whispers[i].name, name) then table.remove(whispers, i) end
  end
  table.insert(whispers, 1, { name = name, full = sender })
  while #whispers > 5 do table.remove(whispers) end
end

-- Recent whisper senders not in the guild, newest first: { {name, full} }
function Chat.RecentWhispers()
  return whispers
end

-- Club history -----------------------------------------------------------------------------------

local function GuildStream(kind)
  if not (C_Club and C_Club.GetGuildClubId and C_Club.GetStreams) then return nil end
  local clubId = ns.Try(C_Club.GetGuildClubId)
  if not clubId then return nil end
  local streams = ns.Try(C_Club.GetStreams, clubId) or {}
  local types = Enum and Enum.ClubStreamType or {}
  local wanted = kind == "officer" and (types.Officer or 2) or (types.Guild or 1)
  for _, stream in ipairs(streams) do
    if stream.streamType == wanted then return clubId, stream.streamId end
  end
  return nil
end

-- The range holding the newest message: the contiguous history up to now. The client does not keep
-- the ranges in a fixed order (a guild with a gap in its cache got the old range last).
local function MessageOrder(id)
  if type(id) ~= "table" then return -1, -1 end
  return tonumber(id.epoch) or -1, tonumber(id.position) or -1
end

function Chat.NewestRange(ranges)
  local best, bestEpoch, bestPos
  for _, range in ipairs(type(ranges) == "table" and ranges or {}) do
    local epoch, pos = MessageOrder(range.newestMessageId)
    if not best or epoch > bestEpoch or (epoch == bestEpoch and pos > bestPos) then
      best, bestEpoch, bestPos = range, epoch, pos
    end
  end
  return best
end

-- Focus the stream of a channel while the chat tab is shown (the server then sends history and updates)
function Chat.Focus(on, kind)
  if not (C_Club and C_Club.FocusStream) then return end
  if focused and (not on or focused.kind ~= kind) then
    ns.Try(C_Club.UnfocusStream, focused[1], focused[2])
    focused = nil
  end
  if not on or focused then return end
  local clubId, streamId = GuildStream(kind or "guild")
  if not clubId then return end
  focused = ns.Try(C_Club.FocusStream, clubId, streamId) and { clubId, streamId, kind = kind } or nil
  -- only a few lines cached (e.g. just what came in since login): fetch a first page right away
  if #Chat.History(kind or "guild") < CLUB_LINES then Chat.LoadOlder(kind or "guild") end
end

-- "New since your last login": the time the player left last. A reload or quick relog keeps the
-- mark of the session before, so new lines stay marked until a real break. settings: saved settings.
function Chat.InitSeen(settings, now)
  local lastLogout = tonumber(settings.lastLogout)
  if lastLogout and settings.seenMark and now - lastLogout < RELOAD_GAP then
    seenMark = tonumber(settings.seenMark)
  else
    seenMark = lastLogout
  end
  settings.seenMark = seenMark
  return seenMark
end

function Chat.OnLogout(settings, now)
  settings.lastLogout = now
end

function Chat.SeenMark()
  return seenMark
end

-- State at the top of the loaded history: "loading" while older lines are requested, "start" at
-- the beginning of the stream, nil otherwise (or without a club stream)
function Chat.HistoryState(kind)
  if pending and ns.Now() - pending < REQUEST_TIMEOUT then return "loading" end
  local clubId, streamId = GuildStream(kind)
  if not clubId or not C_Club.GetMessageRanges then return nil end
  local ranges = ns.Try(C_Club.GetMessageRanges, clubId, streamId)
  local newest = Chat.NewestRange(ranges)
  local oldest = newest and newest.oldestMessageId or nil
  if oldest and ns.Try(C_Club.IsBeginningOfStream, clubId, streamId, oldest) then return "start" end
  return nil
end

-- History arrived from the server
function Chat.OnHistoryReceived()
  pending = nil
end

-- Ask the server for older messages of a channel (scrolled to the top). Returns false at the
-- beginning of the stream or when there is no club stream.
function Chat.LoadOlder(kind)
  local clubId, streamId = GuildStream(kind)
  if not clubId or not C_Club.RequestMoreMessagesBefore then return false end
  local ranges = ns.Try(C_Club.GetMessageRanges, clubId, streamId)
  local newest = Chat.NewestRange(ranges)
  local oldest = newest and newest.oldestMessageId or nil
  if oldest and ns.Try(C_Club.IsBeginningOfStream, clubId, streamId, oldest) then return false end
  if pending and ns.Now() - pending < REQUEST_TIMEOUT then return true end
  pending = ns.Now()
  ns.Try(C_Club.RequestMoreMessagesBefore, clubId, streamId, oldest, oldest and CLUB_MORE or CLUB_LINES)
  return true
end

-- The author's name: older lines (members who left, not yet loaded) carry none in the message, but
-- the club member info or the character cache may still know it
-- Secret values (names in instances) must not even be compared: they are skipped like before.
local function Usable(name)
  return name ~= nil and not ns.IsSecret(name) and type(name) == "string" and name ~= ""
end

local function AuthorName(clubId, author)
  if Usable(author.name) then return author.name end
  local info = author.memberId and C_Club.GetMemberInfo and ns.Try(C_Club.GetMemberInfo, clubId, author.memberId)
  if info and Usable(info.name) then return info.name end
  local byGuid = rawget(_G, "GetPlayerInfoByGUID")
  if author.guid and not ns.IsSecret(author.guid) and byGuid then
    local ok, _, _, _, _, _, name = pcall(byGuid, author.guid)
    if ok and Usable(name) then return name end
  end
  return nil
end

local function ClubHistory(kind)
  local clubId, streamId = GuildStream(kind)
  if not clubId or not C_Club.GetMessageRanges then return nil end
  local ranges = ns.Try(C_Club.GetMessageRanges, clubId, streamId)
  if not ranges or #ranges == 0 then return nil end
  -- the newest range is the contiguous history up to now; older ranges have gaps before it
  local range = Chat.NewestRange(ranges)
  if not range then return nil end
  local messages = range.oldestMessageId and range.newestMessageId
    and ns.Try(C_Club.GetMessagesInRange, clubId, streamId, range.oldestMessageId, range.newestMessageId)
  if not messages or #messages == 0 then
    messages = range.newestMessageId and ns.Try(C_Club.GetMessagesBefore, clubId, streamId, range.newestMessageId, CLUB_MAX)
  end
  if not messages or #messages == 0 then return nil end
  local lines = {}
  for i = math.max(1, #messages - CLUB_MAX + 1), #messages do
    local msg = messages[i]
    -- a secret author or text is left out as before; one line that fails does not empty the chat
    local usable = not msg.destroyed and msg.author and not ns.AnySecret(msg.content, msg.author.name)
    local ok, name = true, nil
    if usable then ok, name = pcall(AuthorName, clubId, msg.author) end
    if usable and ok then
      local classInfo = msg.author.classID and ns.Try(C_CreatureInfo and C_CreatureInfo.GetClassInfo, msg.author.classID)
      lines[#lines + 1] = {
        kind = kind, sender = name and ns.Names.Normalize(name) or ns.L.UNKNOWN_SENDER, senderFull = name,
        unknown = not name or nil,
        text = msg.content or "", classFile = classInfo and classInfo.classFile,
        ts = msg.messageId and msg.messageId.epoch and math.floor(msg.messageId.epoch / 1000000) or 0,
      }
    end
  end
  return lines
end

-- /guildy chatdebug: where the history goes missing (stream, ranges, messages, lines)
function Chat.Debug(kind)
  kind = kind or "guild"
  local out = {}
  local function Add(text) out[#out + 1] = text end
  local clubId, streamId = GuildStream(kind)
  Add("club " .. tostring(clubId) .. " stream " .. tostring(streamId) .. " focused " .. tostring(focused ~= nil)
    .. " pending " .. tostring(pending))
  if clubId then
    local ok, ranges = pcall(C_Club.GetMessageRanges, clubId, streamId)
    Add("ranges ok " .. tostring(ok) .. " count " .. tostring(type(ranges) == "table" and #ranges or ranges))
    if ok and type(ranges) == "table" then
      for i, r in ipairs(ranges) do
        Add("range " .. i .. " newest " .. tostring(MessageOrder(r.newestMessageId)) .. " oldest " .. tostring(MessageOrder(r.oldestMessageId)))
      end
    end
    local range = ok and Chat.NewestRange(ranges)
    if range then
      local okIn, messages = pcall(C_Club.GetMessagesInRange, clubId, streamId, range.oldestMessageId, range.newestMessageId)
      Add("in range ok " .. tostring(okIn) .. " " .. tostring(type(messages) == "table" and #messages or messages))
      local okBefore, before = pcall(C_Club.GetMessagesBefore, clubId, streamId, range.newestMessageId, 50)
      Add("before ok " .. tostring(okBefore) .. " " .. tostring(type(before) == "table" and #before or before))
    end
  end
  local okClub, lines = pcall(ClubHistory, kind)
  Add("club history ok " .. tostring(okClub) .. " " .. tostring(type(lines) == "table" and #lines or lines))
  Add("buffer " .. #(buffers[kind] or {}) .. " system " .. #systemLines)
  local okAll, all = pcall(Chat.History, kind)
  Add("history ok " .. tostring(okAll) .. " " .. tostring(type(all) == "table" and #all or all))
  return out
end

-- Lines to show for a channel ("guild" or "officer"), oldest first
function Chat.History(kind)
  local lines = ClubHistory(kind)
  if not lines or #lines == 0 then
    lines = {}
    for i, line in ipairs(buffers[kind] or {}) do lines[i] = line end
  end
  if kind == "guild" then
    for _, line in ipairs(systemLines) do lines[#lines + 1] = line end
    table.sort(lines, function(a, b) return (a.ts or 0) < (b.ts or 0) end)
  end
  return lines
end

function Chat.Send(kind, text)
  if type(text) ~= "string" or text:match("^%s*$") then return end
  local send = (C_ChatInfo and C_ChatInfo.SendChatMessage) or rawget(_G, "SendChatMessage")
  if send then pcall(send, text, kind == "officer" and "OFFICER" or "GUILD") end
end
