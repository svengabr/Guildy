-- Guild and officer chat for the chat tab. History comes from the guild club (C_Club, the same source
-- as Blizzard's window); if that yields nothing, from lines captured since login. Join/leave/rank
-- system messages are captured and merged in by time. Also remembers who whispered the player
-- recently (invite suggestions). Fires ns "CHAT".
local _, ns = ...

local Chat = {}
ns.Chat = Chat

local MAX_LINES = 300
local CLUB_LINES = 150
local buffers = { guild = {}, officer = {} }
local systemLines = {}
local whispers = {}
local systemPatterns
local focused

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

-- Focus the guild streams while the chat tab is shown (the server then sends history and updates)
function Chat.Focus(on)
  if not (C_Club and C_Club.FocusStream) then return end
  local clubId, streamId = GuildStream("guild")
  if not clubId then return end
  if on and not focused then
    focused = ns.Try(C_Club.FocusStream, clubId, streamId) and { clubId, streamId } or nil
    local ranges = ns.Try(C_Club.GetMessageRanges, clubId, streamId)
    if not ranges or #ranges == 0 then ns.Try(C_Club.RequestMoreMessagesBefore, clubId, streamId, nil, CLUB_LINES) end
  elseif not on and focused then
    ns.Try(C_Club.UnfocusStream, focused[1], focused[2])
    focused = nil
  end
end

local function ClubHistory(kind)
  local clubId, streamId = GuildStream(kind)
  if not clubId or not C_Club.GetMessageRanges then return nil end
  local ranges = ns.Try(C_Club.GetMessageRanges, clubId, streamId)
  if not ranges or #ranges == 0 then return nil end
  local newest = ranges[#ranges].newestMessageId
  local messages = newest and ns.Try(C_Club.GetMessagesBefore, clubId, streamId, newest, CLUB_LINES)
  if not messages or #messages == 0 then return nil end
  local lines = {}
  for _, msg in ipairs(messages) do
    if not msg.destroyed and msg.author and not ns.AnySecret(msg.content, msg.author.name) then
      local classInfo = msg.author.classID and ns.Try(C_CreatureInfo and C_CreatureInfo.GetClassInfo, msg.author.classID)
      lines[#lines + 1] = {
        kind = kind, sender = ns.Names.Normalize(msg.author.name or "?"), senderFull = msg.author.name,
        text = msg.content or "", classFile = classInfo and classInfo.classFile,
        ts = msg.messageId and msg.messageId.epoch and math.floor(msg.messageId.epoch / 1000000) or 0,
      }
    end
  end
  return lines
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
