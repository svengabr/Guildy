-- Sharing profession data between Guildy users on the guild addon channel.
--   SUM  {d = {nameKey = newestTs}}            "this is what I know" (after login)
--   PROF {m = name, p = {["171"] = ProfRec}}   records of one member
--   SUM also carries s = {nameKey = statsTs}, STAT {m = name, s = StatRec} (Core/Stats.lua): statistics
--   of one member, own or read nearby; older Guildy versions ignore both.
--   SUM also carries f = {ownerKey = ts}, FAM {m = owner, f = FamilyRec} (Core/Family.lua): the characters
--   a Guildy user has in the guild (main and twinks); sent only with settings.share, relayed like the rest.
--   SUM also carries b = {at, ts, n} (Core/Bank.lua: newest reading, newest entry, entries), BANK {at, by,
--   money, tabs, logs}: what was read of the guild bank at a banker. Whoever knows more than a summary
--   says offers the entries after its newest one; a reading is shared right after it was taken.
--   HI   {q = true}                         "I use Guildy" (q: please answer); every envelope since 0.3
--   carries the sender's addon version (v), so any message marks its sender as a Guildy user.
-- On a SUM, everyone who knows newer data about some member offers it after a random delay, unless
-- someone else sent it first. Own changes are sent right away (debounced). The member's own data is
-- marked "self" by the receiver; everything else counts as "relay". Sending own data can be switched
-- off (settings.share); relaying others still works.
local _, ns = ...
local P, Proto = ns.Professions, ns.Protocol

local Sync = {}
ns.Sync = Sync

-- The game lets an addon send ten messages in a row and then one a second, per prefix; what goes
-- beyond that it drops without a word, and a message that lost a part never arrives. Up to 1.6.1
-- Guildy sent by bytes (about three parts a second), so after a login, when a member who knows little
-- is offered statistics, professions and the bank at once, most of it was lost. Now it counts messages
-- and stays under the game's limit, and what the game still refuses stays in the queue.
local SEND_BURST, SEND_PER_SECOND = 9, 0.9
local EXPIRE_ROOM = 45 -- parts a message can still send at that rate before its receivers give it up
local queue, allowance, lastRefill, ticker = {}, SEND_BURST, nil, nil -- queue: { { parts, next = index } }
local msgCounter = 0
local assembler = Proto.NewAssembler()
local limiter = Proto.NewLimiter(30, 10)
local seen = {}          -- nameKey -> newest ts seen on the channel (to skip duplicate offers)
local seenStats = {}     -- same for statistics
local seenFamilies = {}  -- same for families
local seenBank, bankMessages = 0, 0 -- newest bank reading seen on the channel, how many of them
local MAX_BYTES = 14000  -- a message of more parts than Protocol.MAX_PARTS is dropped by its receivers
local warnedNewer = false
local ownTimer
local MAX_OFFERS = 25
local users = {}         -- nameKey -> { name, v = addon version or nil (Guildy before 0.3), at }
local lastHello = -math.huge

function Sync.Register()
  local register = (C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix) or rawget(_G, "RegisterAddonMessagePrefix")
  if register then pcall(register, Proto.PREFIX) end
end

-- Sends one part. Returns false when the game refused it for now (its limit): it is to be sent again.
local function RawSend(text)
  local send = (C_ChatInfo and C_ChatInfo.SendAddonMessage) or rawget(_G, "SendAddonMessage")
  if not send then return true end
  local ok, result = pcall(send, Proto.PREFIX, text, "GUILD")
  if not ok or type(result) ~= "number" then return true end -- (older clients return nothing or true)
  local codes = rawget(_G, "Enum") and Enum.SendAddonMessageResult or {}
  return not (result == (codes.AddonMessageThrottle or 3) or result == (codes.ChannelThrottle or 8))
end

local function Pump()
  local now = GetTime()
  allowance = math.min(SEND_BURST, allowance + (now - (lastRefill or now)) * SEND_PER_SECOND)
  lastRefill = now
  while queue[1] and allowance >= 1 do
    local message = queue[1]
    -- a long message only starts once it can be through before its receivers drop what they have of it
    if message.next == 1 and #message.parts - allowance > EXPIRE_ROOM then break end
    if not RawSend(message.parts[message.next]) then
      allowance = 0 -- the game's own count is lower than ours: wait
      break
    end
    allowance = allowance - 1
    message.next = message.next + 1
    if message.next > #message.parts then table.remove(queue, 1) end
  end
  if not queue[1] and ticker then
    ticker:Cancel()
    ticker = nil
  end
end

-- How many messages wait to be sent (for /guildy debug and tests)
function Sync.Waiting()
  return #queue
end

-- Sends what waits as far as the game's limit allows now (the ticker does that; tests call it)
function Sync.Pump()
  Pump()
end

local function SendNow(kind, data)
  if not IsInGuild() then return end
  msgCounter = msgCounter + 1
  local msgId = string.format("%x", ns.Now() % 65536) .. msgCounter
  local message = { parts = Proto.Chunk(msgId, Proto.Encode(kind, data, ns.Version())), next = 1, kind = kind }
  -- the bank is one small message a member waits for: ahead of the statistics and professions in line
  -- (behind a message that is already on its way)
  local at = #queue + 1
  if kind == "BANK" or kind == "HI" then
    at = 1
    while queue[at] and (queue[at].next > 1 or queue[at].kind == "BANK" or queue[at].kind == "HI") do at = at + 1 end
  end
  table.insert(queue, at, message)
  Pump()
  if queue[1] and not ticker then ticker = C_Timer.NewTicker(0.25, Pump) end
end

-- encoding and compressing a message is the expensive part of sending (measured: /guildy perf)
local function Send(kind, data)
  ns.Perf.Call("send", kind, SendNow, kind, data)
end

local function IsOwnKey(key)
  local db = ns.DB()
  return (db and db.ownChars and db.ownChars[key]) and true or false
end

local function SendMember(key)
  local guild = ns.GuildData()
  local record = guild and guild.members[key]
  if not record or not next(record.profs or {}) then return end
  if IsOwnKey(key) and not ns.Settings().share then return end
  local profs = {}
  local any = false
  for skillLine, rec in pairs(record.profs) do
    if rec.src ~= "note" then -- everyone reads guild notes themselves
      profs[tostring(skillLine)] = { ts = rec.ts, src = rec.src, rank = rec.rank, max = rec.max, recipes = rec.recipes }
      any = true
    end
  end
  if not any then return end
  Send("PROF", { m = record.name, p = profs })
  local digest = P.Digest({ members = { [key] = record } })
  seen[key] = math.max(seen[key] or 0, digest[key] or 0)
end

function Sync.SendSummary()
  local guild = ns.GuildData()
  if guild then
    -- (b also when nothing of the bank is known yet: "I can take it", so someone offers it)
    Send("SUM", { d = P.Digest(guild), s = ns.Stats.Digest(guild), f = ns.Family.Digest(guild),
      b = ns.Bank.Digest(guild.bank) or { at = 0, ts = 0, n = 0 } })
  end
end

-- The guild bank as far as it is newer than `since` (a time, nil: all of it). Too much for one message:
-- first without the tabs' contents, then fewer entries.
function Sync.ShareBank(since)
  local guild = ns.GuildData()
  local bank = guild and guild.bank
  if type(bank) ~= "table" or not bank.at then return end
  bank = ns.Bank.Get(guild)
  for _, try in ipairs({ { ns.Bank.WIRE_ENTRIES, true }, { ns.Bank.WIRE_ENTRIES, false }, { 80, false }, { 25, false } }) do
    local data = ns.Bank.Excerpt(bank, since, try[1], try[2])
    if #Proto.Encode("BANK", data, ns.Version()) <= MAX_BYTES then
      Send("BANK", data)
      seenBank, bankMessages = math.max(seenBank, bank.at), bankMessages + 1
      return
    end
  end
end

-- The account's characters in this guild as the own family record (kept while they stay the same)
local function UpdateOwnFamily()
  local guild, db = ns.GuildData(), ns.DB()
  if not guild or not db then return nil end
  local keys, names = {}, {}
  for _, m in ipairs(ns.Roster.Members()) do
    keys[m.key] = true
    names[m.key] = m.name
  end
  local me = ns.Names.Key(ns.PlayerName())
  guild.families = type(guild.families) == "table" and guild.families or {}
  local own = ns.Family.Own(db.ownChars, keys, names, guild.families[me], ns.Now())
  if own then guild.families[me] = own end
  return own
end

local function SendFamily(ownerKey)
  local guild = ns.GuildData()
  local rec = guild and type(guild.families) == "table" and guild.families[ownerKey]
  if type(rec) ~= "table" or not rec.ts then return end
  if IsOwnKey(ownerKey) and not ns.Settings().share then return end
  local owner = guild.members[ownerKey] and guild.members[ownerKey].name or ownerKey
  Send("FAM", { m = owner, f = ns.Family.Wire(rec) })
  seenFamilies[ownerKey] = math.max(seenFamilies[ownerKey] or 0, rec.ts)
end

local function SendStats(key)
  local guild = ns.GuildData()
  local record = guild and guild.members[key]
  local stats = record and record.stats
  if type(stats) ~= "table" or not stats.ts or not stats.v then return end
  if IsOwnKey(key) and not ns.Settings().share then return end
  Send("STAT", { m = record.name, s = ns.Stats.Wire(stats) })
  seenStats[key] = math.max(seenStats[key] or 0, stats.ts)
end

-- Statistics of a member changed (own or read nearby): share them
function Sync.ShareStats(key)
  SendStats(key)
end

-- Data of another member changed (their recipe book was opened through a link): share it
function Sync.Share(key)
  SendMember(key)
end

-- Own data changed: share it a few seconds later (several scans in a row become one message)
function Sync.OwnChanged()
  if ownTimer then ownTimer:Cancel() end
  ownTimer = C_Timer.NewTimer(5, function()
    ownTimer = nil
    SendMember(ns.Names.Key(ns.PlayerName()))
  end)
end

local function OnSummary(data, sender)
  local guild = ns.GuildData()
  if not guild or ns.Names.Same(sender, ns.PlayerName()) then return end
  local theirs = type(data.d) == "table" and data.d or {}
  local mine = P.Digest(guild)
  local offers = P.Outdated(mine, theirs)
  for i = 1, math.min(#offers, MAX_OFFERS) do
    local key = offers[i]
    local myTs = mine[key]
    C_Timer.After(2 + math.random() * 6 + i * 0.3, function()
      if (seen[key] or 0) >= myTs then return end -- someone else already sent it
      SendMember(key)
    end)
  end
  -- families the same way (older Guildy versions send no f)
  if type(data.f) == "table" then
    local myFamilies = ns.Family.Digest(guild)
    local famOffers = P.Outdated(myFamilies, data.f)
    for i = 1, math.min(#famOffers, MAX_OFFERS) do
      local key = famOffers[i]
      local myTs = myFamilies[key]
      C_Timer.After(4 + math.random() * 6 + i * 0.3, function()
        if (seenFamilies[key] or 0) >= myTs then return end
        SendFamily(key)
      end)
    end
  end
  -- the guild bank: one offer for all of it. A Guildy before 1.6.0 sends no b and could not use it;
  -- 1.6.0 itself sent no b while it knew nothing of the bank, which is when it needs the offer most
  -- (found 2026-11-12: a member who installed 1.6.0 never got the bank), so its version counts too.
  local myBank = ns.Bank.Digest(guild.bank)
  local theirDigest = type(data.b) == "table" and data.b
    or (Sync.KnowsBank(Sync.UserVersion(sender)) and {} or nil)
  if theirDigest and ns.Bank.Newer(myBank, theirDigest) then
    local theirBank, before = tonumber(theirDigest.ts) or 0, bankMessages
    C_Timer.After(6 + math.random() * 10, function()
      if bankMessages > before and seenBank >= myBank.at then return end -- someone else sent it meanwhile
      Sync.ShareBank(theirBank)
    end)
  end
  -- statistics the same way (an older Guildy sends no s: then offer nothing, it can't use them)
  if type(data.s) ~= "table" then return end
  local myStats = ns.Stats.Digest(guild)
  local statOffers = P.Outdated(myStats, data.s)
  for i = 1, math.min(#statOffers, MAX_OFFERS) do
    local key = statOffers[i]
    local myTs = myStats[key]
    C_Timer.After(8 + math.random() * 8 + i * 0.5, function()
      if (seenStats[key] or 0) >= myTs then return end
      SendStats(key)
    end)
  end
end

local function OnStats(data, sender)
  local guild = ns.GuildData()
  if not guild or type(data.m) ~= "string" then return end
  if not ns.Roster.IsMember(data.m) and #ns.Roster.Members() > 0 then return end
  local record = ns.Stats.Validate(data.s)
  if not record then return end
  if ns.Names.Same(sender, data.m) then
    record.src = "self"
  elseif record.src == "self" then
    record.src = "relay"
  end
  local key = ns.Names.Key(data.m)
  seenStats[key] = math.max(seenStats[key] or 0, record.ts)
  if ns.Stats.Merge(ns.Store.Member(guild, data.m), record) then ns.Fire("STATS") end
end

local function OnFamily(data)
  local guild = ns.GuildData()
  if not guild or type(data.m) ~= "string" then return end
  if not ns.Roster.IsMember(data.m) and #ns.Roster.Members() > 0 then return end
  local rec = ns.Family.Validate(data.f)
  if not rec then return end
  local key = ns.Names.Key(data.m)
  seenFamilies[key] = math.max(seenFamilies[key] or 0, rec.ts)
  if ns.Family.Merge(guild, data.m, rec) then ns.Fire("FAMILY") end
end

local function OnBank(data, sender)
  local guild = ns.GuildData()
  if not guild then return end
  local reading = ns.Bank.Validate(data, sender, ns.Now())
  if not reading then return end
  seenBank, bankMessages = math.max(seenBank, reading.at), bankMessages + 1
  if ns.Bank.Apply(ns.Bank.Get(guild), reading) then ns.Fire("BANK") end
end

-- Books read through a profession link are only taken from a Guildy that reads them right: before
-- 1.6.0 the book of the member read before was stored on the next one (Game/TradeSkill.lua), and such a
-- Guildy would hand the wrong data back to everyone who threw it away (Core/Store.lua). What a member
-- shares of themselves is taken from any version.
Sync.LINKS_SINCE = "1.6.0"
function Sync.ReadsLinksRight(version)
  if version == "dev" then return true end
  local order = type(version) == "string" and Proto.CompareVersions(version, Sync.LINKS_SINCE)
  return order ~= nil and order ~= false and order >= 0
end

-- Whether a Guildy of that version takes the guild bank (the Bank tab came with 1.6.0 as well)
function Sync.KnowsBank(version)
  return Sync.ReadsLinksRight(version)
end

local function OnProfessions(data, sender)
  local guild = ns.GuildData()
  if not guild or type(data.m) ~= "string" or type(data.p) ~= "table" then return end
  local key = ns.Names.Key(data.m)
  if not ns.Roster.IsMember(data.m) and #ns.Roster.Members() > 0 then return end
  local fromSelf = ns.Names.Same(sender, data.m)
  local member = ns.Store.Member(guild, data.m)
  local changed = false
  local linksRight = Sync.ReadsLinksRight(Sync.UserVersion(sender))
  for skillText, raw in pairs(data.p) do
    local skillLine = tonumber(skillText)
    local record = P.ValidateRecord(raw)
    if record and not fromSelf and record.src == "link" and not linksRight then record = nil end
    if skillLine and record then
      if fromSelf then
        record.src = "self"
      elseif record.src ~= "link" then
        record.src = "relay"
      end
      seen[key] = math.max(seen[key] or 0, record.ts)
      if P.Merge(member, skillLine, record, { isOwnChar = IsOwnKey(key) }) then changed = true end
    end
  end
  if changed then ns.Fire("PROFS") end
end

-- Guildy users seen this session ---------------------------------------------------------------------

local function MarkUser(name, version)
  local key = ns.Names.Key(name)
  local known = users[key]
  local changed = not known or (version and known.v ~= version)
  users[key] = { name = name, v = version or (known and known.v), at = ns.Now() }
  if changed then ns.Fire("USERS") end
  -- a release newer than this one: remembered (settings.newestVersion), so the window keeps saying so
  -- when that member is offline again
  local settings = ns.Settings()
  local newest = ns.Protocol.NewerVersion(ns.Version(), settings.newestVersion, version)
  if newest ~= settings.newestVersion then
    settings.newestVersion = newest
    ns.Fire("VERSION", newest)
  end
end

-- The newest Guildy release seen in the guild when it is newer than this one, else nil
function Sync.NewerVersion()
  local settings = ns.Settings()
  local newest = ns.Protocol.NewerVersion(ns.Version(), settings.newestVersion, nil)
  if newest ~= settings.newestVersion then settings.newestVersion = newest end -- updated since
  return newest
end

-- Addon version of a member who used Guildy this session: "0.3.0", "dev", or "" for a Guildy too
-- old to send its version; nil when not seen
function Sync.UserVersion(name)
  local user = name and users[ns.Names.Key(name)]
  if not user then return nil end
  return user.v or ""
end

local function SendHello(ask)
  lastHello = GetTime()
  Send("HI", { q = ask or nil })
end

-- "I use Guildy" to the guild now (tests)
function Sync.SendHello()
  SendHello()
end

-- Someone logged in and asks who else uses Guildy: answer once, after a random delay (a crowd of
-- Guildy users mustn't answer at the same moment; one answer covers several askers in a row)
local function OnHello(data)
  if not data.q then return end
  C_Timer.After(1 + math.random() * 4, function()
    if GetTime() - lastHello < 5 then return end
    SendHello(false)
  end)
end

local HANDLERS = { SUM = OnSummary, PROF = OnProfessions, STAT = OnStats, FAM = OnFamily, BANK = OnBank, HI = OnHello }

-- CHAT_MSG_ADDON: prefix, text, channel, sender
function Sync.OnAddonMessage(prefix, text, channel, sender)
  if ns.AnySecret(prefix, text, channel, sender) then return end
  if prefix ~= Proto.PREFIX or channel ~= "GUILD" or not Proto.IsPart(text) then return end
  if ns.Names.Same(sender, ns.PlayerName()) then return end
  local payload = Proto.AddPart(assembler, sender, text, ns.Now())
  if not payload then return end
  local envelope, err = Proto.Decode(payload)
  if not envelope then
    if err == "newer" and not warnedNewer then
      warnedNewer = true
      ns.Print(ns.L.SYNC_NEWER)
    end
    return
  end
  if not Proto.Allow(limiter, sender, ns.Now()) then return end
  local name = ns.Names.Normalize(sender)
  ns.SafeCall(MarkUser, name, envelope.v)
  local handler = HANDLERS[envelope.t]
  if handler then ns.SafeCall(handler, envelope.d, name) end
end

-- After login: say what we know once the roster is there
function Sync.Start()
  MarkUser(ns.PlayerName(), ns.Version())
  C_Timer.After(3 + math.random() * 3, function() ns.SafeCall(SendHello, true) end)
  C_Timer.After(10 + math.random() * 10, function()
    ns.SafeCall(UpdateOwnFamily)
    ns.SafeCall(Sync.SendSummary)
    if ns.Settings().share then
      SendMember(ns.Names.Key(ns.PlayerName()))
      SendFamily(ns.Names.Key(ns.PlayerName()))
    end
  end)
end
