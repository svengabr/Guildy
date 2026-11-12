-- Reads the guild bank while its window is open at a guild banker: the game answers nothing about the
-- bank anywhere else. On opening, Guildy asks for the money log and for the contents, the log and the
-- info text of every tab the player may view, a few at a time; every answer is read into
-- guild.bank (Core/Bank.lua) and, once the window closes or a moment after the last answer, shared
-- with the guild (Game/Sync.lua). All of the bank's functions are old globals, not in the documented
-- API (taken from Blizzard_GuildBankUI on the Forever branch); a missing one reads as "nothing".
local _, ns = ...
local B = ns.Bank

local GameBank = {}
ns.GameBank = GameBank

local QUERY_GAP = 0.3   -- seconds between two questions to the server
local FIRST_ASK = 0.8   -- after the window opened: a question in the same moment got no answer (in game 2026-11-12)
-- seconds after the opening: once more for every log still empty. The first questions of a visit often
-- stay without an answer for ten seconds and more (in game 2026-11-12, with a bag addon asking as well)
local ASK_AGAIN = { 2, 4, 7, 11, 16, 25 }
local REOPEN = 5        -- an opening said twice within these seconds is one
local STALE = 300       -- news about the bank this long after the last asking: ask for everything anew
local SETTLE = 1.5      -- after the last question: the tabs' contents count as answered
local SHARE_DELAY = 6

local open = false
local visit = 0 -- counts the visits: a timer of an earlier one does nothing
local asked, settledAt = nil, nil -- tabs asked this visit, when their answers count
local askedAt -- when this visit last asked for everything
local readTimer, shareTimer
local since -- newest entry known before this visit: what is shared afterwards is what came on top

local function G(name)
  return rawget(_G, name)
end

-- the money log has the index after the last bank tab
local function MaxTabs()
  return tonumber(G("MAX_GUILDBANK_TABS")) or 8
end

local function NumTabs()
  return math.min(B.MAX_TABS, tonumber(ns.Try(G("GetNumGuildBankTabs"))) or 0)
end

-- Seconds an entry is old: the game gives years, months, days and hours ago
local function Age(years, months, days, hours)
  local age = ns.Census.DaysOffline(tonumber(years), tonumber(months), tonumber(days), tonumber(hours))
  return math.floor((age or 0) * 86400)
end

-- oldest first, as Core/Bank.lua joins them (Blizzard prints them in that order; turned if not)
local function Ordered(entries)
  if #entries > 1 and entries[1].ts > entries[#entries].ts then
    local turned = {}
    for i = #entries, 1, -1 do turned[#turned + 1] = entries[i] end
    return turned
  end
  return entries
end

local function Name(name)
  if ns.IsSecret(name) or type(name) ~= "string" or name == "" then return nil end
  return ns.Names.Normalize(name)
end

local function MoneyLog(now, by)
  local entries = {}
  local get = G("GetGuildBankMoneyTransaction")
  for i = 1, tonumber(ns.Try(G("GetNumGuildBankMoneyTransactions"))) or 0 do
    local kind, name, amount, years, months, days, hours = ns.Try(get, i)
    if type(kind) == "string" and not ns.AnySecret(kind, name, amount) then
      entries[#entries + 1] = { k = kind, w = Name(name), c = tonumber(amount) or 0,
        ts = now - Age(years, months, days, hours), at = now, by = by }
    end
  end
  return Ordered(entries)
end

local function TabLog(tab, now, by)
  local entries = {}
  local get = G("GetGuildBankTransaction")
  for i = 1, tonumber(ns.Try(G("GetNumGuildBankTransactions"), tab)) or 0 do
    local kind, name, link, count, tab1, tab2, years, months, days, hours = ns.Try(get, tab, i)
    if type(kind) == "string" and not ns.AnySecret(kind, name, link) then
      local item, id, itemName = B.ItemOf(link)
      entries[#entries + 1] = { k = kind, w = Name(name), i = item, id = id, nm = itemName, n = tonumber(count) or 1,
        a = tonumber(tab1) or tab, b = tonumber(tab2), ts = now - Age(years, months, days, hours), at = now, by = by }
    end
  end
  return Ordered(entries)
end

local function Slots(tab)
  local slots = {}
  local info, link = G("GetGuildBankItemInfo"), G("GetGuildBankItemLink")
  for slot = 1, B.SLOTS do
    local item, id, name = B.ItemOf(ns.Try(link, tab, slot))
    if item then
      local _, count = ns.Try(info, tab, slot)
      slots[slot] = { i = item, id = id, nm = name, n = tonumber(count) or 1 }
    end
  end
  return slots
end

-- Everything the game says about the bank right now, into guild.bank
function GameBank.Read()
  if not open then return end
  local guild = ns.GuildData()
  if not guild then return end
  local now, by = ns.Now(), ns.PlayerName()
  if by == "" then return end -- the own name is not there yet: no reading without a reader
  local bank = B.Get(guild)
  local settled = settledAt ~= nil and GetTime() >= settledAt
  local reading = { at = now, by = by, money = tonumber(ns.Try(G("GetGuildBankMoney"))), tabs = {}, logs = {} }
  reading.cost = tonumber(ns.Try(G("GetGuildBankTabCost")))
  local mine = { at = now, gold = tonumber(ns.Try(G("GetGuildBankWithdrawMoney"))), tabs = {} }
  reading.logs[B.MONEY] = B.Run(MoneyLog(now, by))
  local tabInfo, tabText = G("GetGuildBankTabInfo"), G("GetGuildBankText")
  for tab = 1, NumTabs() do
    local name, icon, view, deposit, limit, left = ns.Try(tabInfo, tab)
    if type(name) == "string" then
      mine.tabs[tab] = { view = view and true or false, deposit = deposit and true or false,
        limit = tonumber(limit), left = tonumber(left) }
      local entry = { name = name, icon = icon }
      if view and settled and asked and asked[tab] then
        entry.slots = Slots(tab)
        local text = ns.Try(tabText, tab)
        if type(text) == "string" then entry.text = text end
      end
      reading.tabs[tab] = entry
      if view then reading.logs[tostring(tab)] = B.Run(TabLog(tab, now, by)) end
    end
  end
  local changed = B.Apply(bank, reading)
  bank.mine[ns.Names.Key(by)] = mine
  ns.Fire("BANK")
  if changed then GameBank.ShareSoon() end
end

function GameBank.ShareSoon()
  if shareTimer then shareTimer:Cancel() end
  shareTimer = C_Timer.NewTimer(SHARE_DELAY, function()
    shareTimer = nil
    ns.SafeCall(ns.Sync.ShareBank, since)
  end)
end

-- several answers in a row become one reading
local function ReadSoon()
  if readTimer then return end
  readTimer = C_Timer.NewTimer(0.5, function()
    readTimer = nil
    ns.SafeCall(GameBank.Read)
  end)
end

-- Asks the server for the logs, contents and texts: the game holds only what was asked for
-- Asks once more for every log that is still empty: it may really be empty, or the question got lost
function GameBank.AskAgain()
  if not open then return end
  local queryLog = G("QueryGuildBankLog")
  local delay = 0
  local function Later(index)
    C_Timer.After(delay, function()
      if open then ns.Try(queryLog, index) end
    end)
    delay = delay + QUERY_GAP
  end
  if (tonumber(ns.Try(G("GetNumGuildBankMoneyTransactions"))) or 0) == 0 then Later(MaxTabs() + 1) end
  for tab in pairs(asked or {}) do
    if (tonumber(ns.Try(G("GetNumGuildBankTransactions"), tab)) or 0) == 0 then Later(tab) end
  end
end

local function Ask()
  local steps = {}
  local queryLog, queryTab, queryText = G("QueryGuildBankLog"), G("QueryGuildBankTab"), G("QueryGuildBankText")
  steps[#steps + 1] = function() ns.Try(queryLog, MaxTabs() + 1) end
  local tabInfo = G("GetGuildBankTabInfo")
  asked = {}
  for tab = 1, NumTabs() do
    local _, _, view = ns.Try(tabInfo, tab)
    if view then
      asked[tab] = true
      steps[#steps + 1] = function() ns.Try(queryTab, tab) end
      steps[#steps + 1] = function() ns.Try(queryLog, tab) end
      steps[#steps + 1] = function() ns.Try(queryText, tab) end
    end
  end
  for i, step in ipairs(steps) do
    C_Timer.After(FIRST_ASK + (i - 1) * QUERY_GAP, function()
      if open then step() end
    end)
  end
  local wait = FIRST_ASK + #steps * QUERY_GAP + SETTLE
  askedAt = GetTime()
  settledAt = askedAt + wait
  C_Timer.After(wait + 0.1, function() ns.SafeCall(GameBank.Read) end)
  local this = visit
  for _, later in ipairs(ASK_AGAIN) do
    C_Timer.After(later, function()
      if this == visit then ns.SafeCall(GameBank.AskAgain) end
    end)
  end
end

-- A visit starts. Nothing here looks at Blizzard's bank window: bag addons replace it with their own.
-- Should the client never say that the bank closed, the visit just stays open: reading only ever
-- follows news about the bank, and those come at a banker alone. A new opening then asks anew.
function GameBank.OnOpened()
  if open and askedAt and GetTime() - askedAt < REOPEN then return end
  open = true
  visit = visit + 1
  local guild = ns.GuildData()
  local digest = guild and B.Digest(guild.bank)
  since = digest and digest.ts or 0
  ns.SafeCall(Ask)
  ReadSoon()
  if ns.UI and ns.UI.ShowAtBank then ns.SafeCall(ns.UI.ShowAtBank) end
end

-- Nothing is read here: what the game answers about a bank that just closed is not known to be true,
-- and every change during the visit was read when it happened
function GameBank.OnClosed()
  if open and ns.UI and ns.UI.HideAtBank then ns.SafeCall(ns.UI.HideAtBank) end
  open = false
  asked, settledAt, askedAt = nil, nil, nil
end

-- a tab was bought or the player's rank changed what they see: ask once more
function GameBank.OnTabsChanged()
  if not open then return end
  local tabInfo = G("GetGuildBankTabInfo")
  for tab = 1, NumTabs() do
    local _, _, view = ns.Try(tabInfo, tab)
    if view and not (asked and asked[tab]) then
      ns.SafeCall(Ask)
      break
    end
  end
  ReadSoon()
end

-- Whether the player stands at a guild banker right now, as the client says it: true, false, or nil
-- where the client cannot tell
local function AtBanker()
  local manager = G("C_PlayerInteractionManager")
  local kinds = Enum and Enum.PlayerInteractionType
  if type(manager) ~= "table" or not manager.IsInteractingWithNpcOfType or not (kinds and kinds.GuildBanker) then return nil end
  local ok, at = pcall(manager.IsInteractingWithNpcOfType, kinds.GuildBanker)
  if not ok then return nil end
  return at and true or false
end

-- News about the bank. They also come without a bank: at login the client sends them and answers
-- "no gold" (found in game 2026-11-13: Guildy opened at login and kept a bank of 0 gold). So they
-- start a visit only while the client says the player is at a guild banker; else only the events of
-- the bank opening do.
function GameBank.OnChanged()
  if not open then
    if AtBanker() == true then GameBank.OnOpened() end
    return
  end
  -- open for so long that this is rather the next visit after a closing nobody told about
  if not askedAt or GetTime() - askedAt > STALE then
    visit = visit + 1
    ns.SafeCall(Ask)
  end
  ReadSoon()
end

-- Gold or items moved while the bank is open: the game keeps showing the log it was handed before, so
-- the log is asked for again, a moment later (several moves in a row are one question) and once more
-- after that, should the first question stay without an answer.
local logTimers = {}
local function AskLogs(which)
  if not open then return end
  local queryLog = G("QueryGuildBankLog")
  if which == "money" then
    ns.Try(queryLog, MaxTabs() + 1)
    return
  end
  local delay = 0
  for tab in pairs(asked or {}) do
    C_Timer.After(delay, function()
      if open then ns.Try(queryLog, tab) end
    end)
    delay = delay + QUERY_GAP
  end
end

local function LogsSoon(which)
  if logTimers[which] then return end
  logTimers[which] = true
  local this = visit
  for i, later in ipairs({ 1, 5 }) do
    C_Timer.After(later, function()
      if i == 1 then logTimers[which] = nil end
      if this == visit then ns.SafeCall(AskLogs, which) end
    end)
  end
end

function GameBank.OnMoneyChanged()
  GameBank.OnChanged()
  if open then LogsSoon("money") end
end

function GameBank.OnSlotsChanged()
  GameBank.OnChanged()
  if open then LogsSoon("tabs") end
end

-- The client's newer way to say that a window of the world opened or closed (kind: Enum.PlayerInteractionType)
function GameBank.OnInteraction(kind, shown)
  local kinds = Enum and Enum.PlayerInteractionType
  if not kinds or kind ~= kinds.GuildBanker then return end
  if shown then GameBank.OnOpened() else GameBank.OnClosed() end
end

-- /guildy bank: what Guildy sees of the bank right now (to find out why nothing is read)
function GameBank.Debug()
  local lines = {}
  local function Has(name) return type(G(name)) == "function" and "yes" or "MISSING" end
  local window = G("GuildBankFrame")
  lines[#lines + 1] = ("at a guild banker, says the client: %s"):format(tostring(AtBanker()))
  lines[#lines + 1] = ("bank: visit %s, Blizzard's window %s"):format(open and "open" or "closed",
    type(window) ~= "table" and "not loaded" or (window:IsShown() and "shown" or "hidden"))
  lines[#lines + 1] = ("tabs %s, money %s, money log %s entries (asked as log %d), max tabs %s"):format(tostring(ns.Try(G("GetNumGuildBankTabs"))),
    tostring(ns.Try(G("GetGuildBankMoney"))), tostring(ns.Try(G("GetNumGuildBankMoneyTransactions"))),
    MaxTabs() + 1, tostring(G("MAX_GUILDBANK_TABS")))
  lines[#lines + 1] = ("functions: money log %s, tab log %s, tab info %s, query %s"):format(Has("GetGuildBankMoneyTransaction"),
    Has("GetGuildBankTransaction"), Has("GetGuildBankTabInfo"), Has("QueryGuildBankLog"))
  local guild = ns.GuildData()
  local digest = guild and guild.bank and B.Digest(guild.bank)
  lines[#lines + 1] = digest and ("stored: %d entries, read %d s ago by %s"):format(digest.n, ns.Now() - digest.at, tostring(guild.bank.by))
    or "stored: nothing"
  return lines
end

function GameBank.IsOpen()
  return open
end

-- What this character may take today, as read at the banker: { at, gold, tabs } or nil
function GameBank.Mine()
  local guild = ns.GuildData()
  local bank = guild and guild.bank
  return bank and type(bank.mine) == "table" and bank.mine[ns.Names.Key(ns.PlayerName())] or nil
end
