-- Addon-to-addon protocol between Guildy users in the guild (prefix GUILDY, channel GUILD).
-- Envelope {p = protocol, t = type, d = data, v = addon version (since 0.3, optional)} -> JSON -> LibDeflate deflate -> EncodeForWoWAddonChannel
-- -> parts of at most 250 bytes "~<msgId>:<i>/<n>:<piece>". Same scheme as Raidy. Pure apart from the
-- bundled libraries.
local _, ns = ...

local Protocol = {}
ns.Protocol = Protocol

Protocol.PREFIX = "GUILDY"
Protocol.VERSION = 1
Protocol.MAX_PART = 250
Protocol.MAX_PARTS = 64
Protocol.EXPIRE = 60 -- incomplete messages are dropped after 60 s

function Protocol.Deflate()
  if ns.LibDeflate then return ns.LibDeflate end
  local stub = rawget(_G, "LibStub")
  if stub then
    local ok, lib = pcall(stub.GetLibrary, stub, "LibDeflate", true)
    if ok then return lib end
  end
end

function Protocol.Encode(kind, data, version)
  local envelope = { p = Protocol.VERSION, t = kind, d = data }
  if type(version) == "string" and version ~= "" then envelope.v = version:sub(1, 24) end
  local text = ns.json.encode(envelope)
  local lib = Protocol.Deflate()
  return lib:EncodeForWoWAddonChannel(lib:CompressDeflate(text))
end

-- Returns the envelope or nil plus "malformed" / "newer" (sent by a newer protocol version)
function Protocol.Decode(payload)
  local lib = Protocol.Deflate()
  local compressed = type(payload) == "string" and lib:DecodeForWoWAddonChannel(payload)
  if not compressed then return nil, "malformed" end
  local ok, text = pcall(lib.DecompressDeflate, lib, compressed)
  if not ok or type(text) ~= "string" then return nil, "malformed" end
  local parsed, envelope = pcall(ns.json.decode, text)
  if not parsed or type(envelope) ~= "table" or type(envelope.t) ~= "string" then return nil, "malformed" end
  if type(envelope.p) ~= "number" then return nil, "malformed" end
  if envelope.p > Protocol.VERSION then return nil, "newer" end
  if type(envelope.d) ~= "table" then envelope.d = {} end
  if type(envelope.v) ~= "string" or envelope.v == "" or #envelope.v > 24 then envelope.v = nil end
  return envelope
end

function Protocol.IsPart(message)
  return type(message) == "string" and message:sub(1, 1) == "~"
end

function Protocol.Chunk(msgId, payload)
  local pieces = {}
  local headerRoom = #("~" .. msgId .. ":64/64:")
  local size = Protocol.MAX_PART - headerRoom
  for i = 1, math.max(1, math.ceil(#payload / size)) do
    pieces[i] = payload:sub((i - 1) * size + 1, i * size)
  end
  local parts = {}
  for i, piece in ipairs(pieces) do
    parts[i] = "~" .. msgId .. ":" .. i .. "/" .. #pieces .. ":" .. piece
  end
  return parts
end

function Protocol.NewAssembler()
  return { pending = {} }
end

-- Returns the full payload once all parts of a message arrived, else nil (or nil, "malformed")
function Protocol.AddPart(assembler, sender, message, now)
  local msgId, index, total, piece = message:match("^~([%w]+):(%d+)/(%d+):(.*)$")
  index, total = tonumber(index), tonumber(total)
  if not msgId or not index or not total or index < 1 or total < 1 or index > total or total > Protocol.MAX_PARTS then
    return nil, "malformed"
  end
  for key, entry in pairs(assembler.pending) do
    if now - entry.at > Protocol.EXPIRE then assembler.pending[key] = nil end
  end
  if total == 1 then return piece end
  local key = ns.Names.Key(sender) .. "/" .. msgId
  local entry = assembler.pending[key]
  if not entry or entry.total ~= total then
    entry = { total = total, parts = {}, count = 0, at = now }
    assembler.pending[key] = entry
  end
  if not entry.parts[index] then
    entry.parts[index] = piece
    entry.count = entry.count + 1
  end
  if entry.count < total then return nil end
  assembler.pending[key] = nil
  return table.concat(entry.parts)
end

-- Per-sender rate limit: at most `limit` messages per `window` seconds
function Protocol.NewLimiter(limit, window)
  return { limit = limit, window = window, senders = {} }
end

function Protocol.Allow(limiter, sender, now)
  local key = ns.Names.Key(sender)
  local entry = limiter.senders[key]
  if not entry or now - entry.start >= limiter.window then
    entry = { start = now, count = 0 }
    limiter.senders[key] = entry
  end
  entry.count = entry.count + 1
  return entry.count <= limiter.limit
end

-- Compares two addon versions ("0.2.0", "v0.10.1-beta"): -1, 0 or 1; nil when either has no numbers
-- (like "dev")
function Protocol.CompareVersions(a, b)
  if type(a) ~= "string" or type(b) ~= "string" then return nil end
  local x, y = {}, {}
  for n in a:gmatch("%d+") do x[#x + 1] = tonumber(n) end
  for n in b:gmatch("%d+") do y[#y + 1] = tonumber(n) end
  if #x == 0 or #y == 0 then return nil end
  for i = 1, math.max(#x, #y) do
    local p, q = x[i] or 0, y[i] or 0
    if p ~= q then return p < q and -1 or 1 end
  end
  return 0
end
