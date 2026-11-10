local T = ...
local ns = T.pureNs()
local P = ns.Protocol

T.describe("Protocol", function()
  T.it("round-trips an envelope", function()
    local env = P.Decode(P.Encode("PROF", { m = "Ran Fred", p = { ["171"] = { ts = 5 } } }))
    T.eq(env.t, "PROF")
    T.eq(env.d.m, "Ran Fred")
    T.eq(env.d.p["171"].ts, 5)
  end)

  T.it("reassembles parts in any order", function()
    local recipes = {}
    for i = 1, 600 do recipes[i] = 100000 + i * 7 end
    local payload = P.Encode("PROF", { r = recipes })
    local parts = P.Chunk("ab1", payload)
    T.truthy(#parts > 2, "expected several parts")
    for _, part in ipairs(parts) do T.truthy(#part <= 250, "part too long") end
    local asm = P.NewAssembler()
    local result
    for i = #parts, 1, -1 do result = P.AddPart(asm, "Ran Fred", parts[i], 0) or result end
    T.eq(result, payload)
    T.eq(#P.Decode(result).d.r, 600)
  end)

  T.it("refuses newer versions and garbage", function()
    local lib = P.Deflate()
    local newer = lib:EncodeForWoWAddonChannel(lib:CompressDeflate(ns.json.encode({ p = 2, t = "X", d = {} })))
    local _, err = P.Decode(newer)
    T.eq(err, "newer")
    local _, err2 = P.Decode("not a message")
    T.eq(err2, "malformed")
    local _, err3 = P.AddPart(P.NewAssembler(), "x", "~a:5/2:zz", 0)
    T.eq(err3, "malformed")
  end)

  T.it("carries the addon version", function()
    T.eq(P.Decode(P.Encode("HI", {}, "0.3.0")).v, "0.3.0")
    T.eq(P.Decode(P.Encode("HI", {})).v, nil)
    T.eq(P.CompareVersions("0.2.0", "0.3.0"), -1)
    T.eq(P.CompareVersions("0.10.0", "0.9.1"), 1)
    T.eq(P.CompareVersions("v0.3", "0.3.0"), 0)
    T.eq(P.CompareVersions("dev", "0.3.0"), nil)
  end)

  T.it("knows the newest release that is newer than the own one", function()
    T.eq(P.NewerVersion("1.1.2", nil, "1.1.3"), "1.1.3")
    T.eq(P.NewerVersion("1.1.2", "1.1.3", "1.2.0"), "1.2.0")
    T.eq(P.NewerVersion("1.1.2", "1.2.0", "1.1.3"), "1.2.0") -- an older one seen later changes nothing
    T.eq(P.NewerVersion("1.1.2", "1.1.3", nil), "1.1.3")     -- remembered while its member is offline
    T.eq(P.NewerVersion("1.2.0", "1.1.3", nil), nil)         -- updated since
    T.eq(P.NewerVersion("1.1.2", nil, "1.1.2"), nil)
    T.eq(P.NewerVersion("1.1.2", nil, "dev"), nil)
    T.eq(P.NewerVersion("1.1.2", nil, "1.1.3-4-gabc123"), nil) -- a packager build is no release
    T.eq(P.NewerVersion("1.1.2", nil, ""), nil)
    T.eq(P.NewerVersion("dev", nil, "9.9.9"), nil)             -- a development copy is never outdated
  end)

  T.it("limits messages per sender", function()
    local limiter = P.NewLimiter(3, 10)
    for _ = 1, 3 do T.eq(P.Allow(limiter, "A", 0), true) end
    T.eq(P.Allow(limiter, "A", 1), false)
    T.eq(P.Allow(limiter, "B", 1), true)
    T.eq(P.Allow(limiter, "A", 11), true)
  end)
end)
