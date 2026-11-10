local T = ...
local R = T.pureNs().ShotRun

T.describe("ShotRun", function()
  T.it("walks the languages in order and ends", function()
    local settings = { language = "deDE", width = 1300, height = 700 }
    local run = R.Start(settings, { "enUS", "deDE", "frFR" }, 100)
    T.eq(R.Next(run, 101), "enUS")
    T.eq(R.Next(run, 150), "deDE")
    T.eq(run.touched, 150)
    T.eq(R.Next(run, 200), "frFR")
    T.eq(R.Next(run, 250), nil)
  end)
  T.it("restores what was there, automatic language included", function()
    local settings = { width = 1300, height = 700 }
    local run = R.Start(settings, { "enUS" }, 100)
    settings.language, settings.width, settings.height = "enUS", 1130, 560
    R.Restore(run, settings)
    T.eq(settings, { width = 1300, height = 700 })
  end)
  T.it("knows a cut-off run", function()
    local run = R.Start({}, { "enUS" }, 100)
    T.eq(R.Stale(run, 100 + R.STALE), false)
    T.eq(R.Stale(run, 101 + R.STALE), true)
    T.eq(R.Stale("junk", 0), true)
    T.eq(R.Stale({ touched = 100 }, 100), true)
  end)
  T.it("does not share the language list with the caller", function()
    local languages = { "enUS", "deDE" }
    local run = R.Start({}, languages, 0)
    R.Next(run, 1)
    T.eq(#languages, 2)
  end)
  T.it("puts a cut-off run back and leaves a fresh one alone", function()
    local db = { settings = { language = "ruRU", width = 1130, height = 560 } }
    db.shotRun = { queue = { "ptBR" }, language = false, width = 1300, height = 700, touched = 100 }
    T.eq(R.Recover(db, 100 + R.STALE), false)
    T.truthy(db.shotRun, "still running")
    T.eq(R.Recover(db, 101 + R.STALE), true)
    T.eq(db, { settings = { width = 1300, height = 700 } })
    T.eq(R.Recover(db, 0), false) -- no run at all
    db.shotRun = "junk"
    T.eq(R.Recover(db, 0), true)
    T.eq(db.shotRun, nil)
  end)
end)
