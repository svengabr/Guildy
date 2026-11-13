local T = ...
local ns = T.pureNs()
local Tenure = ns.Tenure

local TODAY = 20770

T.describe("Tenure", function()
  T.it("turns a time into a day", function()
    T.eq(Tenure.Day(0), 0)
    T.eq(Tenure.Day(86400 * 3 + 5), 3)
  end)

  T.it("notes a first date", function()
    local joined = {}
    T.eq(Tenure.Note(joined, "anna", 20700, false, TODAY), true)
    T.eq(joined, { anna = { d = 20700 } })
    T.eq(Tenure.Note(joined, "bert", 20701, true, TODAY), true)
    T.eq(joined.bert, { d = 20701, x = true })
    T.eq(Tenure.Note(joined, "bert", 20701, true, TODAY), false)
  end)

  T.it("refuses what is no day", function()
    local joined = {}
    T.eq(Tenure.Note(joined, "anna", "20700", true, TODAY), false)
    T.eq(Tenure.Note(joined, "anna", 20700.5, true, TODAY), false)
    T.eq(Tenure.Note(joined, "anna", 0, true, TODAY), false)
    T.eq(Tenure.Note(joined, "anna", TODAY + 2, true, TODAY), false)
    T.eq(Tenure.Note(joined, "anna", 0 / 0, true, TODAY), false)
    T.eq(Tenure.Note(joined, 7, 20700, true, TODAY), false)
    T.eq(joined, {})
  end)

  T.it("lets a date from the log beat a first seen one", function()
    local joined = { anna = { d = 20700 } }
    T.eq(Tenure.Note(joined, "anna", 20750, true, TODAY), true)
    T.eq(joined.anna, { d = 20750, x = true })
    T.eq(Tenure.Note(joined, "anna", 20600, false, TODAY), false)
    T.eq(joined.anna, { d = 20750, x = true })
    -- the same day from the log makes it exact
    joined = { anna = { d = 20700 } }
    T.eq(Tenure.Note(joined, "anna", 20700, true, TODAY), true)
    T.eq(joined.anna.x, true)
  end)

  T.it("keeps the earlier of two first seen dates", function()
    local joined = { anna = { d = 20700 } }
    T.eq(Tenure.Note(joined, "anna", 20710, false, TODAY), false)
    T.eq(Tenure.Note(joined, "anna", 20690, false, TODAY), true)
    T.eq(joined.anna, { d = 20690 })
  end)

  T.it("takes the later log date as a rejoin, else the earlier one", function()
    local joined = { anna = { d = 20700, x = true } }
    T.eq(Tenure.Note(joined, "anna", 20702, true, TODAY), false) -- the same join, read later
    T.eq(Tenure.Note(joined, "anna", 20699, true, TODAY), true)
    T.eq(joined.anna.d, 20699)
    T.eq(Tenure.Note(joined, "anna", 20740, true, TODAY), true) -- left and came back
    T.eq(joined.anna.d, 20740)
    T.eq(Tenure.Note(joined, "anna", 20699, true, TODAY), false) -- the old membership
    T.eq(joined.anna.d, 20740)
  end)

  T.it("ends on the same date on both sides", function()
    for _, pair in ipairs({ { 20700, 20701 }, { 20700, 20740 }, { 20702, 20700 } }) do
      local a, b = { m = { d = pair[1], x = true } }, { m = { d = pair[2], x = true } }
      Tenure.Note(a, "m", pair[2], true, TODAY)
      Tenure.Note(b, "m", pair[1], true, TODAY)
      T.eq(a.m.d, b.m.d)
      T.eq(Tenure.Differs(Tenure.Digest(a), Tenure.Digest(b)), false)
    end
  end)

  T.it("replaces a broken entry", function()
    local joined = { anna = "x", bert = { d = "y" } }
    T.eq(Tenure.Note(joined, "anna", 20700, false, TODAY), true)
    T.eq(Tenure.Note(joined, "bert", 20700, false, TODAY), true)
    T.eq(joined, { anna = { d = 20700 }, bert = { d = 20700 } })
  end)

  T.it("forgets who left", function()
    local joined = { anna = { d = 1 }, bert = { d = 2 } }
    T.eq(Tenure.Prune(joined, { anna = true }), 1)
    T.eq(joined, { anna = { d = 1 } })
  end)

  T.it("sums up what it knows", function()
    T.eq(Tenure.Digest(nil), { n = 0, x = 0, s = 0 })
    local digest = Tenure.Digest({ anna = { d = 10 }, bert = { d = 20, x = true }, broken = 5 })
    T.eq(digest, { n = 2, x = 1, s = 30 })
    T.eq(Tenure.Differs(digest, { n = 2, x = 1, s = 30 }), false)
    T.eq(Tenure.Differs(digest, { n = 2, x = 1, s = 31 }), true)
    T.eq(Tenure.Differs(digest, { n = 2, x = 2, s = 30 }), true)
    T.eq(Tenure.Differs(digest, "x"), true)
  end)

  T.it("goes over the wire and back", function()
    local joined = { anna = { d = 20700 }, bert = { d = 20701, x = true } }
    local messages = Tenure.Wire(joined, { anna = "Anna", bert = "Bert" })
    T.eq(messages, { { { "Anna", 20700, 0 }, { "Bert", 20701, 1 } } })
    local theirs = {}
    T.eq(Tenure.Apply(theirs, messages[1], TODAY, function() return true end), true)
    T.eq(theirs, joined)
    T.eq(Tenure.Apply(theirs, messages[1], TODAY, function() return true end), false)
  end)

  T.it("sends a large guild in several messages", function()
    local joined = {}
    for i = 1, Tenure.WIRE_MEMBERS * 2 + 1 do joined["m" .. i] = { d = 20000 + i } end
    local messages = Tenure.Wire(joined, {})
    T.eq(#messages, 3)
    T.eq(#messages[1], Tenure.WIRE_MEMBERS)
    T.eq(#messages[3], 1)
    T.eq(Tenure.Wire({}, {}), {})
  end)

  T.it("takes nothing from a message of rubbish", function()
    local joined = {}
    local function Member(name) return name ~= "Stranger" end
    T.eq(Tenure.Apply(joined, "x", TODAY, Member), false)
    T.eq(Tenure.Apply(joined, { "x", 5, {}, { 7, 20700, 1 }, { "Anna", "20700", 1 }, { "Anna", TODAY + 9, 1 },
      { "Stranger", 20700, 1 }, { ("x"):rep(80), 20700, 1 } }, TODAY, Member), false)
    T.eq(joined, {})
    T.eq(Tenure.Apply(joined, { { "Anna", 20700, "yes" } }, TODAY, Member), true)
    T.eq(joined, { anna = { d = 20700 } }) -- only a 1 says "from the log"
  end)

  T.it("names a span", function()
    T.eq({ Tenure.Span(0) }, { "d", 0 })
    T.eq({ Tenure.Span(30) }, { "d", 30 })
    T.eq({ Tenure.Span(31) }, { "mo", 1 })
    T.eq({ Tenure.Span(400) }, { "mo", 13 })
    T.eq({ Tenure.Span(730) }, { "y", 2 })
    T.eq({ Tenure.Span(-3) }, { "d", 0 })
  end)
end)
