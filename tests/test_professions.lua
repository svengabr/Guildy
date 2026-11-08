local T = ...
local ns = T.pureNs()
local P = ns.Professions

T.describe("Professions.ValidateRecord", function()
  T.it("rejects records without a numeric timestamp", function()
    T.eq(P.ValidateRecord({ ts = "x" }), nil)
    T.eq(P.ValidateRecord(nil), nil)
    T.eq(P.ValidateRecord({ ts = -1 }), nil)
  end)
  T.it("cleans values", function()
    local r = P.ValidateRecord({ ts = 100.7, src = "evil", rank = 900, max = "150", recipes = { 5, -1, 2.5, "x", 5, 7 } })
    T.eq(r, { ts = 100, src = "relay", rank = 450, max = 150, recipes = { 5, 7 } })
  end)
  T.it("caps the recipe list", function()
    local list = {}
    for i = 1, 1500 do list[i] = i end
    T.eq(#P.ValidateRecord({ ts = 1, recipes = list }).recipes, 1000)
  end)
end)

T.describe("Professions.Merge", function()
  local function rec(ts, src, rank, recipes) return { ts = ts, src = src, rank = rank, max = 300, recipes = recipes } end

  T.it("takes newer and ignores older data", function()
    local m = {}
    T.eq(P.Merge(m, 171, rec(10, "relay", 50, { 1 })), true)
    T.eq(P.Merge(m, 171, rec(5, "self", 99, { 2 })), false)
    T.eq(m.profs[171].rank, 50)
    T.eq(P.Merge(m, 171, rec(20, "relay", 60, { 3 })), true)
    T.eq(m.profs[171].recipes, { 3 })
  end)
  T.it("prefers the member's own data at equal age", function()
    local m = {}
    P.Merge(m, 171, rec(10, "relay", 50))
    T.eq(P.Merge(m, 171, rec(10, "self", 51)), true)
    T.eq(P.Merge(m, 171, rec(10, "relay", 52)), false)
    T.eq(m.profs[171].rank, 51)
  end)
  T.it("keeps recipes and rank when newer data has none", function()
    local m = {}
    P.Merge(m, 171, rec(10, "self", 50, { 1, 2 }))
    T.eq(P.Merge(m, 171, { ts = 20, src = "link" }), true)
    T.eq(m.profs[171].recipes, { 1, 2 })
    T.eq(m.profs[171].rank, 50)
  end)
  T.it("accepts only own scans for own characters", function()
    local m = {}
    T.eq(P.Merge(m, 171, rec(10, "relay", 50), { isOwnChar = true }), false)
    T.eq(P.Merge(m, 171, rec(10, "scan", 50), { isOwnChar = true }), true)
  end)
  T.it("ignores unknown skill lines", function()
    T.eq(P.Merge({}, 99999, rec(1, "self", 1)), false)
  end)
end)

T.describe("Professions digests", function()
  T.it("takes the newest record per member", function()
    local guild = { members = {
      a = { profs = { [171] = { ts = 5 }, [182] = { ts = 9 } } },
      b = { profs = {} },
    } }
    T.eq(P.Digest(guild), { a = 9 })
  end)
  T.it("finds members where mine is newer", function()
    T.eq(P.Outdated({ a = 9, b = 3, c = 1 }, { a = 9, b = 5 }), { "c" })
    T.eq(P.Outdated({ a = 9, b = 3 }, { a = 4 }), { "a", "b" })
    T.eq(P.Outdated({ a = 1 }, "junk"), { "a" })
  end)
  T.it("builds skill-line sets", function()
    T.eq(P.SetOf({ profs = { [171] = {}, [182] = {} } }), { [171] = true, [182] = true })
    T.eq(P.SetOf({ profs = {} }), nil)
  end)
end)

T.describe("Professions.ParseNote", function()
  local function set(...) local s = {} for _, v in ipairs({ ... }) do s[v] = true end return s end
  T.it("reads common guild note styles", function()
    T.eq(P.ParseNote("Herb/ Alch"), set(182, 171))
    T.eq(P.ParseNote("Tank Schmied"), set(164))
    T.eq(P.ParseNote("Tank Schmi"), set(164))
    T.eq(P.ParseNote("VZ 150, Schneiderin"), set(333, 197))
    T.eq(P.ParseNote("Kürsch + Leder"), set(393, 165))
    T.eq(P.ParseNote("Bergbau/Ingi"), set(186, 202))
    T.eq(P.ParseNote("Erste Hilfe, Kochen"), set(129, 185))
    T.eq(P.ParseNote("Mining & Engineering"), set(186, 202))
    T.eq(P.ParseNote("LW BS"), set(165, 164))
  end)
  T.it("ignores ordinary notes", function()
    T.eq(P.ParseNote("Österreich Connection"), {})
    T.eq(P.ParseNote("Salubri / Feleanor"), {})
    T.eq(P.ParseNote("Twink von Ran Fred"), {})
    T.eq(P.ParseNote("Heiler, Raid Di/Do"), {})
    T.eq(P.ParseNote(nil), {})
  end)
  T.it("adds note records only where no data exists and removes stale ones", function()
    local m = { profs = { [171] = { ts = 50, src = "link", rank = 80, recipes = { 1 } } } }
    T.eq(P.ApplyNotes(m, set(171, 182)), true)
    T.eq(m.profs[171].src, "link")
    T.eq(m.profs[182], { ts = P.NOTE_TS, src = "note" })
    T.eq(P.ApplyNotes(m, set(171, 182)), false)
    T.eq(P.ApplyNotes(m, set(171)), true)
    T.eq(m.profs[182], nil)
  end)
  T.it("lets real data replace note records", function()
    local m = {}
    P.ApplyNotes(m, set(182))
    T.eq(P.Merge(m, 182, { ts = 10, src = "relay", rank = 90 }), true)
    T.eq(m.profs[182].rank, 90)
  end)
end)

T.describe("Professions.ParseTradeLinks", function()
  T.it("reads the guid format", function()
    local text = "kann ich: |cffffd000|Htrade:Player-4711-0ABCDEF0:2259:171|h[Alchemie]|h|r"
    T.eq(P.ParseTradeLinks(text), { { guid = "Player-4711-0ABCDEF0", spellID = 2259, skillLine = 171 } })
  end)
  T.it("reads the classic format with rank", function()
    local text = "|Htrade:3908:120:150:Player-4711-0ABCDEF0:AAAAgA|h[Schneiderei]|h"
    T.eq(P.ParseTradeLinks(text), { { spellID = 3908, rank = 120, max = 150, guid = "Player-4711-0ABCDEF0", skillLine = 197 } })
  end)
  T.it("ignores garbage", function()
    T.eq(P.ParseTradeLinks("|Htrade:abc|h |Htrade:|h hello"), {})
    T.eq(P.ParseTradeLinks(nil), {})
  end)
end)

T.describe("Professions.PlaceholderIcons", function()
  T.it("finds the icon most recipes of a profession share", function()
    local icons = { "a", "b", "c", "d" }
    for _ = 1, 6 do icons[#icons + 1] = "w" end
    T.eq(P.PlaceholderIcons(icons), { w = true })
  end)
  T.it("leaves a few shared icons alone", function()
    T.eq(P.PlaceholderIcons({ "p", "p", "p", "a", "b" }), {}) -- fewer than 5
    local icons = { "p", "p", "p", "p", "p" }
    for i = 1, 30 do icons[#icons + 1] = "i" .. i end
    T.eq(P.PlaceholderIcons(icons), {}) -- not a quarter of the book
  end)
end)
