-- Sharing profession data between Guildy users on the guild addon channel.
--   SUM  {d = {nameKey = newestTs}}            "this is what I know" (after login)
--   PROF {m = name, p = {["171"] = ProfRec}}   records of one member
-- On a SUM, everyone who knows newer data about some member offers it after a random delay, unless
-- someone else sent it first. Own changes are sent right away (debounced). The member's own data is
-- marked "self" by the receiver; everything else counts as "relay". Sending own data can be switched
-- off (settings.share); relaying others still works.
local _, ns = ...
local P, Proto = ns.Professions, ns.Protocol

local Sync = {}
ns.Sync = Sync

local BYTES_PER_SECOND, BURST = 800, 2000
local queue, budget, lastRefill, ticker = {}, BURST, nil, nil
local msgCounter = 0
local assembler = Proto.NewAssembler()
local limiter = Proto.NewLimiter(30, 10)
local seen = {}          -- nameKey -> newest ts seen on the channel (to skip duplicate offers)
local warnedNewer = false
local ownTimer
local MAX_OFFERS = 25

function Sync.Register()
  local register = (C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix) or rawget(_G, "RegisterAddonMessagePrefix")
  if register then pcall(register, Proto.PREFIX) end
end

local function RawSend(text)
  local send = (C_ChatInfo and C_ChatInfo.SendAddonMessage) or rawget(_G, "SendAddonMessage")
  if send then pcall(send, Proto.PREFIX, text, "GUILD") end
end

local function Pump()
  local now = GetTime()
  budget = math.min(BURST, budget + (now - (lastRefill or now)) * BYTES_PER_SECOND)
  lastRefill = now
  while queue[1] and budget >= #queue[1] do
    local text = table.remove(queue, 1)
    budget = budget - #text
    RawSend(text)
  end
  if not queue[1] and ticker then
    ticker:Cancel()
    ticker = nil
  end
end

local function Send(kind, data)
  if not IsInGuild() then return end
  msgCounter = msgCounter + 1
  local msgId = string.format("%x", ns.Now() % 65536) .. msgCounter
  for _, part in ipairs(Proto.Chunk(msgId, Proto.Encode(kind, data))) do queue[#queue + 1] = part end
  Pump()
  if queue[1] and not ticker then ticker = C_Timer.NewTicker(0.25, Pump) end
end

local function IsOwnKey(key)
  local db = ns.DB()
  return db and db.ownChars and db.ownChars[key] or false
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
  if guild then Send("SUM", { d = P.Digest(guild) }) end
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
end

local function OnProfessions(data, sender)
  local guild = ns.GuildData()
  if not guild or type(data.m) ~= "string" or type(data.p) ~= "table" then return end
  local key = ns.Names.Key(data.m)
  if not ns.Roster.IsMember(data.m) and #ns.Roster.Members() > 0 then return end
  local fromSelf = ns.Names.Same(sender, data.m)
  local member = ns.Store.Member(guild, data.m)
  local changed = false
  for skillText, raw in pairs(data.p) do
    local skillLine = tonumber(skillText)
    local record = P.ValidateRecord(raw)
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

local HANDLERS = { SUM = OnSummary, PROF = OnProfessions }

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
  local handler = HANDLERS[envelope.t]
  if not handler or not Proto.Allow(limiter, sender, ns.Now()) then return end
  ns.SafeCall(handler, envelope.d, ns.Names.Normalize(sender))
end

-- After login: say what we know once the roster is there
function Sync.Start()
  C_Timer.After(10 + math.random() * 10, function()
    ns.SafeCall(Sync.SendSummary)
    if ns.Settings().share then SendMember(ns.Names.Key(ns.PlayerName())) end
  end)
end
