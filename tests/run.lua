-- Test runner: luajit tests/run.lua (from the repo root).
-- Runs the unit tests of the pure modules, the locale checks and the load smoke test.
local here = (debug.getinfo(1, "S").source:sub(2):gsub("\\", "/"):match("^(.*)/[^/]*$")) or "."
local T = dofile(here .. "/lib.lua")

local FILES = {
  "test_names.lua", "test_census.lua", "test_professions.lua", "test_search.lua", "test_protocol.lua",
  "test_locales.lua", "smoke.lua",
}

for _, file in ipairs(FILES) do
  local chunk, err = loadfile(here .. "/" .. file)
  if not chunk then
    T.failed = T.failed + 1
    T.failures[#T.failures + 1] = file .. ": " .. tostring(err)
  else
    local ok, runErr = xpcall(function() chunk(T) end, debug.traceback)
    if not ok then
      T.failed = T.failed + 1
      T.failures[#T.failures + 1] = file .. ": " .. tostring(runErr)
    end
  end
end

for _, failure in ipairs(T.failures) do print("FAIL " .. failure) end
print(string.format("%d passed, %d failed", T.passed, T.failed))
os.exit(T.failed == 0 and 0 or 1)
