-- Character names: Forever puts the last name into the realm slot ("Ranfredo-Blanko" is the character
-- "Ranfredo Blanko"); names that already have a space may carry a "-Realm" suffix. Keys are the
-- normalized name lowercased (ASCII, Latin-1 and Latin Extended-A), so "JÖRG" equals "jörg".
-- Same rules as Raidy's Core/Names.lua. All functions are pure.
local _, ns = ...

local Names = {}
ns.Names = Names

local floor, char, concat = math.floor, string.char, table.concat

local function CodePoints(s)
  local out, i, len = {}, 1, #s
  while i <= len do
    local c = s:byte(i)
    local cp, size = c, 1
    if c >= 0xF0 and i + 3 <= len then
      cp = (c - 0xF0) * 262144 + (s:byte(i + 1) - 0x80) * 4096 + (s:byte(i + 2) - 0x80) * 64 + (s:byte(i + 3) - 0x80)
      size = 4
    elseif c >= 0xE0 and i + 2 <= len then
      cp = (c - 0xE0) * 4096 + (s:byte(i + 1) - 0x80) * 64 + (s:byte(i + 2) - 0x80)
      size = 3
    elseif c >= 0xC0 and i + 1 <= len then
      cp = (c - 0xC0) * 64 + (s:byte(i + 1) - 0x80)
      size = 2
    end
    out[#out + 1] = cp
    i = i + size
  end
  return out
end

local function Utf8(cp)
  if cp < 0x80 then return char(cp) end
  if cp < 0x800 then return char(0xC0 + floor(cp / 64), 0x80 + cp % 64) end
  if cp < 0x10000 then
    return char(0xE0 + floor(cp / 4096), 0x80 + floor(cp / 64) % 64, 0x80 + cp % 64)
  end
  return char(0xF0 + floor(cp / 262144), 0x80 + floor(cp / 4096) % 64, 0x80 + floor(cp / 64) % 64, 0x80 + cp % 64)
end

local function LowerCodePoint(cp)
  if cp >= 65 and cp <= 90 then return cp + 32 end
  if cp >= 0xC0 and cp <= 0xDE and cp ~= 0xD7 then return cp + 32 end
  if cp >= 0x100 and cp <= 0x17F then
    if cp == 0x178 then return 0xFF end
    if (cp >= 0x139 and cp <= 0x148) or (cp >= 0x179 and cp <= 0x17E) then
      return cp % 2 == 1 and cp + 1 or cp
    end
    if cp == 0x130 or cp == 0x131 or cp == 0x138 or cp == 0x149 or cp == 0x17F then return cp end
    return cp % 2 == 0 and cp + 1 or cp
  end
  return cp
end

function Names.Lower(s)
  local out = {}
  for i, cp in ipairs(CodePoints(s or "")) do out[i] = Utf8(LowerCodePoint(cp)) end
  return concat(out)
end

local function Trim(s)
  return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end
Names.Trim = Trim

function Names.Normalize(name)
  if type(name) ~= "string" then return "" end
  name = Trim(name)
  if name:find(" ", 1, true) then
    local cut = name:find("-", 1, true)
    if cut then name = name:sub(1, cut - 1) end
  else
    name = name:gsub("%-", " ", 1)
  end
  return (Trim(name):gsub("%s+", " "))
end

-- True for Forever's secret values (names of other players in instances), which addon code must not
-- compare or inspect
local function Secret(value)
  local check = rawget(_G, "issecretvalue")
  return check ~= nil and check(value) == true
end

-- Name from UnitName(unit): the second value is the last name on Forever. Secret names give "".
function Names.FromUnit(name, lastName)
  if Secret(name) or type(name) ~= "string" or name == "" then return "" end
  if not Secret(lastName) and type(lastName) == "string" and lastName ~= "" then name = name .. " " .. lastName end
  return Names.Normalize(name)
end

-- Name as the server expects it in slash commands: Forever's "First Last" is "First-Last" there.
-- Names that already carry a "-" are left alone.
function Names.ToServer(name)
  if type(name) ~= "string" then return "" end
  name = Trim(name):gsub("%s+", " ")
  if name:find("-", 1, true) then return name end
  return (name:gsub(" ", "-", 1))
end

function Names.Key(name)
  return Names.Lower(Names.Normalize(name))
end

function Names.Same(a, b)
  return Names.Key(a) == Names.Key(b)
end
