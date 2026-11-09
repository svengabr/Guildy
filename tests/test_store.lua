local T = ...
local ns = T.pureNs()
local Store = ns.Store

T.describe("Store.Init", function()
  T.it("reads guild members under the mouse by default", function()
    T.eq(Store.Init(nil).settings.statMouseover, true)
  end)
  T.it("switches mouseover on once for saves from before 1.0.1", function()
    local db = Store.Init({ settings = { statMouseover = false } })
    T.eq(db.settings.statMouseover, true)
  end)
  T.it("keeps it off when the player switched it off after that", function()
    local db = Store.Init(nil)
    db.settings.statMouseover = false
    T.eq(Store.Init(db).settings.statMouseover, false)
  end)
end)
