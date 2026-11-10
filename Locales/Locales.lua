-- Which language Guildy's own texts are in. One file per language fills ns.LocaleTables (they stand
-- before this file in the TOC). ns.L reads from the language in force: the client's while the files
-- load, the saved choice from ADDON_LOADED on (Core/Init.lua), so no text may be read at load time.
-- A text missing in a language reads in English, a key nobody has reads as the key name.
local _, ns = ...
ns.LocaleTables = ns.LocaleTables or {}
local TABLES = ns.LocaleTables

local Locale = {}
ns.Locale = Locale

-- every language Guildy can have, in the order they are listed and photographed (/guildy shots all)
Locale.ORDER = { "enUS", "deDE", "frFR", "esES", "ruRU", "ptBR" }
-- each in its own language, never translated: found again from any language
Locale.NAMES = { enUS = "English", deDE = "Deutsch", frFR = "Français", esES = "Español", ruRU = "Русский",
  ptBR = "Português (Brasil)" }
-- client locales that share another one's texts
local SAME = { esMX = "esES", enGB = "enUS" }

-- The languages there are texts for, in order
function Locale.Languages()
  local list = {}
  for _, code in ipairs(Locale.ORDER) do
    if TABLES[code] then list[#list + 1] = code end
  end
  return list
end

local function Known(code)
  if type(code) ~= "string" then return nil end
  code = SAME[code] or code
  return TABLES[code] and code or nil
end

-- setting: the saved choice (nil: automatic), clientLocale: GetLocale()
function Locale.Resolve(setting, clientLocale)
  return Known(setting) or Known(clientLocale) or "enUS"
end

local current, english = TABLES.enUS or {}, TABLES.enUS or {}

function Locale.Apply(code)
  code = Known(code) or "enUS"
  Locale.current = code
  current = TABLES[code] or english
end

ns.L = setmetatable({}, { __index = function(_, key) return current[key] or english[key] or key end })

Locale.Apply(Locale.Resolve(nil, rawget(_G, "GetLocale") and GetLocale() or nil))
