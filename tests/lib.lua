-- Tiny test helpers (same as Raidy's): describe/it, assertions, deep equality and the module loader that
-- hands the addon table to each file like WoW does (file vararg: addonName, ns).
local lib = {}

lib.passed, lib.failed, lib.failures = 0, 0, {}
local prefix = {}

function lib.describe(name, fn)
  prefix[#prefix + 1] = name
  fn()
  prefix[#prefix] = nil
end

function lib.it(name, fn)
  local full = table.concat(prefix, " > ") .. " > " .. name
  local ok, err = xpcall(fn, debug.traceback)
  if ok then
    lib.passed = lib.passed + 1
  else
    lib.failed = lib.failed + 1
    lib.failures[#lib.failures + 1] = full .. "\n    " .. tostring(err)
  end
end

local function Show(v)
  if type(v) == "string" then return string.format("%q", v) end
  return tostring(v)
end

function lib.diff(a, b, path)
  path = path or "$"
  if type(a) ~= type(b) then return path .. ": " .. Show(a) .. " vs " .. Show(b) end
  if type(a) ~= "table" then
    if a ~= b then return path .. ": " .. Show(a) .. " vs " .. Show(b) end
    return nil
  end
  for k, v in pairs(a) do
    local d = lib.diff(v, b[k], path .. "." .. tostring(k))
    if d then return d end
  end
  for k, v in pairs(b) do
    if a[k] == nil then return path .. "." .. tostring(k) .. ": missing vs " .. Show(v) end
  end
  return nil
end

function lib.eq(actual, expected, message)
  local d = lib.diff(actual, expected)
  if d then error((message and (message .. ": ") or "") .. d, 2) end
end

function lib.truthy(value, message)
  if not value then error(message or "expected a truthy value", 2) end
end

function lib.readFile(path)
  local f = assert(io.open(path, "rb"))
  local content = f:read("*a")
  f:close()
  return content
end

lib.testsDir = (debug.getinfo(1, "S").source:sub(2):gsub("\\", "/"):match("^(.*)/[^/]*$")) or "."
lib.addonDir = lib.testsDir .. "/.."

function lib.loadInto(ns, relative)
  local chunk, err = loadfile(lib.addonDir .. "/" .. relative)
  if not chunk then error(err) end
  return chunk("Guildy", ns)
end

-- Pure modules in TOC order (no WoW API at load time)
lib.PURE = {
  "Libs/LibDeflate/LibDeflate.lua", "Libs/json/json.lua",
  "Core/Names.lua", "Core/Store.lua", "Core/Census.lua", "Core/Professions.lua", "Core/Search.lua", "Core/Protocol.lua",
  "Core/Manage.lua", "Core/Stats.lua", "Core/Family.lua", "Core/ShotRun.lua",
}

function lib.pureNs()
  local ns = {}
  for _, file in ipairs(lib.PURE) do lib.loadInto(ns, file) end
  return ns
end

-- Files listed in Guildy.toc, in order
function lib.tocFiles()
  local files = {}
  for line in lib.readFile(lib.addonDir .. "/Guildy.toc"):gmatch("[^\r\n]+") do
    if not line:match("^#") and line:match("%S") then
      files[#files + 1] = (line:gsub("\\", "/"):gsub("%s+$", ""))
    end
  end
  return files
end

return lib
