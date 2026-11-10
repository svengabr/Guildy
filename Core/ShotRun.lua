-- /guildy shots all: the decisions of a screenshot run over every language. Pure: takes and returns
-- tables. The run sets Guildy's language, reloads the interface, takes its pictures and goes on to the
-- next language, so its state has to survive the reloads: it is kept in GuildyDB.shotRun (UI/Shots.lua).
--   run = { queue = { code, ... },        languages still to do
--           language = code | false,      the language setting before the run (false: automatic)
--           width, height,                the window size before the run
--           touched }                     when the run last made a step
local _, ns = ...
local ShotRun = {}
ns.ShotRun = ShotRun

-- seconds without a step after which a saved run counts as cut off (a crash, a logout): it is put
-- back instead of continued, so no login ever starts reloading again
ShotRun.STALE = 180

function ShotRun.Start(settings, languages, now)
  local queue = {}
  for i, code in ipairs(languages) do queue[i] = code end
  return { queue = queue, language = settings.language or false, width = settings.width, height = settings.height,
    touched = now }
end

-- The next language (taken off the queue), nil when all are done
function ShotRun.Next(run, now)
  local code = table.remove(run.queue, 1)
  if code then run.touched = now end
  return code
end

function ShotRun.Stale(run, now)
  if type(run) ~= "table" or type(run.queue) ~= "table" then return true end
  return now - (run.touched or 0) > ShotRun.STALE
end

-- A run that was cut off is put back and forgotten (true); a fresh one or none is left alone. db: GuildyDB.
-- Called before the saved language is applied, so the language from before the run is in force at once.
function ShotRun.Recover(db, now)
  if db.shotRun == nil or not ShotRun.Stale(db.shotRun, now) then return false end
  if type(db.shotRun) == "table" and type(db.settings) == "table" then ShotRun.Restore(db.shotRun, db.settings) end
  db.shotRun = nil
  return true
end

-- Language and window size as they were before the run
function ShotRun.Restore(run, settings)
  settings.language = run.language or nil
  settings.width, settings.height = run.width, run.height
end
