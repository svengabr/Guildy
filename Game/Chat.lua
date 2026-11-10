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
local pending = {} -- "club:stream" -> time of its outstanding "older messages" request
local asked = {}   -- "club:stream" -> {mark, ts}: where its history began at the last request
local ASKED_KEEP = 60 -- a request that brought nothing older counts as the start for this long
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
  if #Chat.History(kind or "guild", Chat.WINDOW) < Chat.WINDOW then Chat.LoadOlder(kind or "guild") end
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
  return Chat.StreamState(GuildStream(kind))
end

local function StreamKey(clubId, streamId)
  return tostring(clubId) .. ":" .. tostring(streamId)
end

-- Where a stream's loaded history begins: "epoch:position" of its oldest message, "none" when empty
local function OldestMark(clubId, streamId)
  local ranges = ns.Try(C_Club.GetMessageRanges, clubId, streamId)
  local newest = Chat.NewestRange(ranges)
  local oldest = newest and newest.oldestMessageId or nil
  if type(oldest) ~= "table" then return nil, "none" end
  return oldest, tostring(oldest.epoch) .. ":" .. tostring(oldest.position)
end

local function Pending(key)
  return pending[key] and ns.Now() - pending[key] < REQUEST_TIMEOUT
end

-- The last request came back (or ran out) and the history still begins where it began then: nothing
-- older exists. Without this an empty or short channel asked again on every render (the view sits at
-- its top), and its "loading" line never went away (found in game 2026-11-09).
local function NothingOlder(key, mark)
  local last = asked[key]
  return last ~= nil and last.mark == mark and not Pending(key) and ns.Now() - last.ts < ASKED_KEEP
end

-- The same for any club stream (communities)
function Chat.StreamState(clubId, streamId)
  if not clubId or not streamId or not C_Club or not C_Club.GetMessageRanges then return nil end
  local key = StreamKey(clubId, streamId)
  if Pending(key) then return "loading" end
  local oldest, mark = OldestMark(clubId, streamId)
  if oldest and ns.Try(C_Club.IsBeginningOfStream, clubId, streamId, oldest) then return "start" end
  if NothingOlder(key, mark) then return "start" end
  return nil
end

-- History arrived from the server (for one stream, or all when the event names none)
function Chat.OnHistoryReceived(clubId, streamId)
  if clubId and streamId then pending[StreamKey(clubId, streamId)] = nil else pending = {} end
end

-- Ask the server for older messages of a channel (scrolled to the top). Returns false at the
-- beginning of the stream or when there is no club stream.
function Chat.LoadOlder(kind)
  return Chat.StreamLoadOlder(GuildStream(kind))
end

-- The same for any club stream (communities)
function Chat.StreamLoadOlder(clubId, streamId)
  if not clubId or not streamId or not C_Club or not C_Club.RequestMoreMessagesBefore then return false end
  local key = StreamKey(clubId, streamId)
  local oldest, mark = OldestMark(clubId, streamId)
  if oldest and ns.Try(C_Club.IsBeginningOfStream, clubId, streamId, oldest) then return false end
  if Pending(key) then return true end
  if NothingOlder(key, mark) then return false end
  pending[key] = ns.Now()
  asked[key] = { mark = mark, ts = ns.Now() }
  ns.Try(C_Club.RequestMoreMessagesBefore, clubId, streamId, oldest, oldest and CLUB_MORE or CLUB_LINES)
  return true
end

-- What the history of a stream looks like to Guildy (/guildy communitydebug)
function Chat.StreamDebug(clubId, streamId)
  local key = StreamKey(clubId, streamId)
  local ranges = ns.Try(C_Club.GetMessageRanges, clubId, streamId)
  local _, mark = OldestMark(clubId, streamId)
  local last = asked[key]
  return ("stream %s: ranges %s oldest %s pending %s asked %s state %s lines %s"):format(key,
    tostring(type(ranges) == "table" and #ranges or ranges), mark, tostring(Pending(key)),
    tostring(last and (last.mark .. " " .. math.floor(ns.Now() - last.ts) .. "s ago")),
    tostring(Chat.StreamState(clubId, streamId)), tostring(#(Chat.StreamLines(clubId, streamId, "community") or {})))
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

-- The chat shows the newest lines only, like Blizzard's guild window, and more when the player
-- scrolls up (Chat.WINDOW lines, then Chat.MORE at a time). Reading and writing the whole history
-- for every new line cost 25 ms on average and up to 106 ms in a guild with a long history (measured
-- in game 2026-11-10). Per stream Guildy remembers the oldest message of the window, so the next
-- read asks the client for the messages from there on only.
Chat.WINDOW = 100
Chat.MORE = 100
local SLACK = 50 -- new lines the window may grow by before it is cut back to its size
local windows = {} -- "club:stream:kind" -> { id = oldest message shown, limit }

local function SameId(a, b)
  return type(a) == "table" and type(b) == "table" and a.epoch == b.epoch and a.position == b.position
end

local AddLines

-- Lines of a club stream, oldest first: the guild's (kind "guild" / "officer") or a community's.
-- limit: only the newest lines (see above); without it everything loaded, up to CLUB_MAX.
-- Second result: true when older messages are loaded than the lines returned.
function Chat.StreamLines(clubId, streamId, kind, limit)
  if not clubId or not streamId or not C_Club or not C_Club.GetMessageRanges then return nil end
  local ranges = ns.Try(C_Club.GetMessageRanges, clubId, streamId)
  if not ranges or #ranges == 0 then return nil end
  -- the newest range is the contiguous history up to now; older ranges have gaps before it
  local range = Chat.NewestRange(ranges)
  if not range then return nil end
  local key = StreamKey(clubId, streamId) .. ":" .. tostring(kind)
  local window = limit and windows[key]
  local messages
  if window and window.limit == limit and range.newestMessageId then
    -- from the window's oldest message on; anything unexpected (the message is gone, the client
    -- answers something else) falls back to reading everything
    messages = ns.Try(C_Club.GetMessagesInRange, clubId, streamId, window.id, range.newestMessageId)
    if type(messages) ~= "table" or #messages == 0 or not SameId(messages[1].messageId, window.id)
      or #messages > limit + SLACK then
      messages = nil
    end
  end
  local from = 1
  if not messages and limit and range.newestMessageId then
    -- the newest `limit` messages only: asking for the whole range made the client hand over every
    -- loaded message, 8 MB and more per read in a guild with a long history (measured in game
    -- 2026-11-10). Used when the answer is what was asked for: in time order, ending with the newest
    -- message; else everything is read as before.
    local newest = ns.Try(C_Club.GetMessagesBefore, clubId, streamId, range.newestMessageId, limit)
    local count = type(newest) == "table" and #newest or 0
    if count > 0 and count <= limit and SameId(newest[count].messageId, range.newestMessageId)
      and type(newest[1].messageId) == "table" and (count == 1 or not SameId(newest[1].messageId, range.newestMessageId))
      and (newest[1].messageId.epoch or 0) <= (newest[count].messageId.epoch or 0)
      -- fewer than asked for must be all there is
      and (count == limit or SameId(newest[1].messageId, range.oldestMessageId)) then
      messages = newest
      windows[key] = { id = messages[1].messageId, limit = limit }
    end
  end
  if not messages then
    messages = range.oldestMessageId and range.newestMessageId
      and ns.Try(C_Club.GetMessagesInRange, clubId, streamId, range.oldestMessageId, range.newestMessageId)
    if not messages or #messages == 0 then
      messages = range.newestMessageId and ns.Try(C_Club.GetMessagesBefore, clubId, streamId, range.newestMessageId, CLUB_MAX)
    end
    if not messages or #messages == 0 then return nil end
    from = math.max(1, #messages - (limit or CLUB_MAX) + 1)
    if limit then windows[key] = { id = messages[from].messageId, limit = limit } end
  end
  local first = messages[from] and messages[from].messageId
  local more = limit ~= nil and not SameId(first, range.oldestMessageId)
  return AddLines({}, clubId, kind, messages, from), more
end

-- Adds messages[from ...] of a stream to lines
AddLines = function(lines, clubId, kind, messages, from)
  for i = from, #messages do
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

local function ClubHistory(kind, limit)
  local clubId, streamId = GuildStream(kind)
  return Chat.StreamLines(clubId, streamId, kind, limit)
end

-- /guildy chatdebug: where the history goes missing (stream, ranges, messages, lines)
function Chat.Debug(kind)
  kind = kind or "guild"
  local out = {}
  local function Add(text) out[#out + 1] = text end
  local clubId, streamId = GuildStream(kind)
  Add("club " .. tostring(clubId) .. " stream " .. tostring(streamId) .. " focused " .. tostring(focused ~= nil)
    .. " pending " .. tostring(clubId and Pending(StreamKey(clubId, streamId)) or false))
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

-- Lines to show for a channel ("guild" or "officer"), oldest first. limit: only the newest lines.
-- Second result: true when older lines are loaded than the ones returned (scrolling up shows them).
function Chat.History(kind, limit)
  local lines, more = ClubHistory(kind, limit)
  if not lines or #lines == 0 then
    lines, more = {}, false
    for i, line in ipairs(buffers[kind] or {}) do lines[i] = line end
  end
  if kind ~= "guild" or #systemLines == 0 then return lines, more end
  -- join and leave lines go in by their time (both lists are in time order already); those from
  -- before the first line shown wait for the player to scroll up
  local merged, s = {}, 1
  local firstTs = more and lines[1] and lines[1].ts or nil
  while firstTs and systemLines[s] and (systemLines[s].ts or 0) < firstTs do s = s + 1 end
  for _, line in ipairs(lines) do
    while systemLines[s] and (systemLines[s].ts or 0) < (line.ts or 0) do
      merged[#merged + 1] = systemLines[s]
      s = s + 1
    end
    merged[#merged + 1] = line
  end
  for i = s, #systemLines do merged[#merged + 1] = systemLines[i] end
  return merged, more
end

function Chat.Send(kind, text)
  if type(text) ~= "string" or text:match("^%s*$") then return end
  local send = (C_ChatInfo and C_ChatInfo.SendChatMessage) or rawget(_G, "SendChatMessage")
  if send then pcall(send, text, kind == "officer" and "OFFICER" or "GUILD") end
end
