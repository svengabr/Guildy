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
  T.it("keeps only the names of the own characters", function()
    local db = Store.Init({ ownChars = { drache = { name = "Drache", level = 3, guild = "Katzen" }, old = true } })
    T.eq(db.ownChars, { drache = true, old = true })
  end)
end)

T.describe("Store.Guild", function()
  T.it("throws away once what was read through profession links", function()
    local db = Store.Init(nil)
    db.guilds.cats = { members = {
      a = { name = "A", profs = { [171] = { ts = 5, src = "link", rank = 100 }, [197] = { ts = 6, src = "self", rank = 200 },
        [186] = { ts = 1, src = "note" } } },
      b = { name = "B", profs = { [164] = { ts = 7, src = "relay" }, [333] = { ts = 8, src = "link" } } },
      c = { name = "C", profs = { [185] = { ts = 9, src = "scan" } } },
    } }
    local guild = Store.Guild(db, "cats")
    T.eq(guild.members.a.profs[171], nil)
    T.eq(guild.members.a.profs[197].rank, 200)
    T.eq(guild.members.a.profs[186].src, "note")
    T.eq(guild.members.b.profs, { [164] = { ts = 7, src = "relay" } })
    T.eq(guild.members.c.profs[185].src, "scan")
    T.eq(guild.profsVersion, Store.PROFS_VERSION)
    -- only once: what is read afterwards stays
    guild.members.a.profs[171] = { ts = 20, src = "link", rank = 120 }
    T.eq(Store.Guild(db, "cats").members.a.profs[171].rank, 120)
    -- a guild seen for the first time has nothing to throw away
    T.eq(Store.Guild(db, "dogs").profsVersion, Store.PROFS_VERSION)
  end)
end)
