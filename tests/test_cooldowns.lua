local T = ...
local ns = T.pureNs()
local C = ns.Cooldowns

local NOW = 1800000000
local DAY = 86400

T.describe("Cooldowns", function()
  T.it("watches the known cooldown crafts and what was learned", function()
    local watched = C.Watched(nil)
    T.eq(watched[17187], 171) -- Arcanite
    T.eq(watched[1317279], 171) -- Forever's own Legionite
    T.eq(watched[18560], 197) -- Mooncloth
    T.eq(watched[19566], 165) -- Salt Shaker
    T.eq(C.ITEMS[15846], 19566)
    watched = C.Watched({ [99999] = 202, bad = 1, [5] = "x" })
    T.eq(watched[99999], 202)
    T.eq(watched[5], nil)
  end)

  T.it("learns a new cooldown craft once", function()
    local learned = {}
    T.eq(C.Learn(learned, 99999, 202), true)
    T.eq(C.Learn(learned, 99999, 202), false)
    T.eq(C.Learn(learned, 17187, 171), false) -- already known from the start
    T.eq(C.Learn(learned, 1.5, 202), false)
    T.eq(C.Learn(learned, 99998, nil), false)
    T.eq(learned, { [99999] = 202 })
  end)

  T.it("notes an own reading, ready as 0", function()
    local book = {}
    T.eq(C.Note(book, "anna", { [17187] = NOW + 3600, [18560] = NOW - 5 }, NOW), true)
    T.eq(book.anna, { ts = NOW, cd = { [17187] = NOW + 3600, [18560] = 0 } })
  end)

  T.it("does not count seconds of jitter as a change", function()
    local book = {}
    C.Note(book, "anna", { [17187] = NOW + 3600 }, NOW)
    T.eq(C.Note(book, "anna", { [17187] = NOW + 3630 }, NOW + 30), false)
    T.eq(book.anna.ts, NOW)
    T.eq(C.Note(book, "anna", { [17187] = NOW + 7200 }, NOW + 40), true) -- crafted again
    T.eq(C.Note(book, "anna", { [17187] = NOW + 7200, [18560] = 0 }, NOW + 50), true) -- a new craft
    T.eq(C.Note(book, "anna", { [17187] = 0, [18560] = 0 }, NOW + 7300), true) -- became ready
  end)

  T.it("takes an unchanged reading again after a day, so it never goes stale", function()
    local book = {}
    C.Note(book, "anna", { [17187] = 0 }, NOW)
    T.eq(C.Note(book, "anna", { [17187] = 0 }, NOW + 3600), false)
    T.eq(C.Note(book, "anna", { [17187] = 0 }, NOW + DAY), true)
    T.eq(book.anna.ts, NOW + DAY)
  end)

  T.it("neither offers nor keeps a reading older than a week", function()
    local book = { old = { ts = NOW - 8 * DAY, cd = {} }, new = { ts = NOW, cd = {} } }
    T.eq(C.Digest(book, NOW), { new = NOW })
    T.eq(C.DropStale(book, NOW), 1)
    T.eq(book.old, nil)
    T.eq(book.new.ts, NOW)
  end)

  T.it("goes over the wire and back", function()
    local book = {}
    C.Note(book, "anna", { [17187] = NOW + 3600, [18560] = 0 }, NOW)
    local wire = C.Wire(book.anna)
    T.eq(wire, { ts = NOW, cd = { { 17187, NOW + 3600 }, { 18560, 0 } } })
    T.eq(C.Validate(wire, NOW), book.anna)
  end)

  T.it("refuses what is no reading", function()
    T.eq(C.Validate("x", NOW), nil)
    T.eq(C.Validate({ cd = {} }, NOW), nil)
    T.eq(C.Validate({ ts = NOW + 3600, cd = {} }, NOW), nil) -- from the future
    T.eq(C.Validate({ ts = NOW - 8 * DAY, cd = {} }, NOW), nil) -- too old to mean anything
    local rec = C.Validate({ ts = NOW, cd = { { 17187, NOW + 8 * DAY }, { "x", 1 }, { 18560, -4 }, 7, { 11479, NOW + 60 } } }, NOW)
    T.eq(rec, { ts = NOW, cd = { [11479] = NOW + 60 } })
  end)

  T.it("takes the newer reading", function()
    local book = {}
    T.eq(C.Merge(book, "anna", { ts = NOW, cd = { [17187] = 0 } }), true)
    T.eq(C.Merge(book, "anna", { ts = NOW - 1, cd = { [17187] = NOW + 99 } }), false)
    T.eq(C.Merge(book, "anna", { ts = NOW + 1, cd = { [17187] = NOW + 99 } }), true)
    T.eq(book.anna.cd[17187], NOW + 99)
    T.eq(C.Digest(book), { anna = NOW + 1 })
    T.eq(C.Digest(nil), {})
  end)

  T.it("lists a member's cooldowns, ready first", function()
    local book = { anna = { ts = NOW, cd = { [17187] = NOW + 7200, [18560] = 0, [11479] = NOW + 600 } } }
    T.eq(C.Of(book, "anna", NOW + 60), {
      { spell = 18560, readyAt = 0, left = 0 },
      { spell = 11479, readyAt = NOW + 600, left = 540 },
      { spell = 17187, readyAt = NOW + 7200, left = 7140 },
    })
    T.eq(C.Of(book, "bert", NOW), nil)
    T.eq(C.Of(book, "anna", NOW + 8 * DAY), nil) -- a week-old reading says nothing any more
  end)

  T.it("forgets who left", function()
    local book = { anna = { ts = 1, cd = {} }, bert = { ts = 1, cd = {} } }
    T.eq(C.Prune(book, { anna = true }), 1)
    T.eq(book.bert, nil)
  end)

  T.it("names the time left", function()
    T.eq({ C.Span(30) }, { "m", 1 })
    T.eq({ C.Span(1800) }, { "m", 30 })
    T.eq({ C.Span(3600) }, { "h", 1 })
    T.eq({ C.Span(3601) }, { "h", 2 })
    T.eq({ C.Span(47 * 3600) }, { "h", 47 })
    T.eq({ C.Span(71 * 3600) }, { "d", 3 })
  end)
end)
