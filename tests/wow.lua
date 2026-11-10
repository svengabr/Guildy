-- The WoW client as far as the tests need it: permissive stubs (any frame method exists), the game
-- functions Guildy calls, and the addon loaded into it file by file in TOC order.
-- dofile(...)(T, opts) returns a fresh world: { env, ns, errors, Fire, RunTimers, SECRET, calls }.
--   opts.roster          guild roster rows (GetGuildRosterInfo values), default three members
--   opts.width / height  size every stub frame reports (lists size their rows from it), default 100
--   opts.setup(env)      changes the environment before the addon loads
--   opts.afterFile(file, ns)  called after each file of the addon has run
return function(T, opts)
  opts = opts or {}
  local errors = {}
  local calls = { n = 0, objects = 0 } -- widget method calls and widgets created (tests/bench.lua)
  local registered = {}   -- event -> {frames}
  local timers = {}

  -- any other widget method: does nothing, but while calls.texts is a list every text handed to a
  -- widget is noted there (AddMessage, AddLine, SetTitle ...)
  local function Other(_, ...)
    if not calls.texts then return end
    for i = 1, select("#", ...) do
      local value = select(i, ...)
      if type(value) == "string" then calls.texts[#calls.texts + 1] = value end
    end
  end

  local function Stub(name)
    calls.objects = calls.objects + 1
    local stub = { _name = name, _scripts = {}, _shown = false, _text = "", _w = opts.width or 100, _h = opts.height or 100, _checked = false }
    local methods = {}
    function methods:GetName() return self._name end
    function methods:GetWidth() return self._w end
    function methods:GetHeight() return self._h end
    function methods:SetWidth(w) self._w = w end
    function methods:SetHeight(h) self._h = h end
    function methods:SetSize(w, h) self._w, self._h = w, h end
    function methods:GetStringWidth() return 50 end
    function methods:GetFont() return "Fonts\\FRIZQT__.TTF", 12, "" end
    function methods:GetPoint() return "CENTER", nil, "CENTER", 0, 0 end
    function methods:GetFrameLevel() return 1 end
    function methods:IsShown() return self._shown end
    function methods:IsVisible()
      local parent = rawget(self, "_parent")
      return self._shown and (parent == nil or type(parent) ~= "table" or not parent.IsVisible or parent:IsVisible())
    end
    function methods:SetParent(parent) self._parent = parent end
    function methods:Show()
      local was = self._shown
      self._shown = true
      if not was and self._scripts.OnShow then self._scripts.OnShow(self) end
    end
    function methods:Hide()
      local was = self._shown
      self._shown = false
      if was and self._scripts.OnHide then self._scripts.OnHide(self) end
    end
    function methods:SetShown(v) if v then self:Show() else self:Hide() end end
    function methods:HasFocus() return false end
    function methods:GetText() return self._text end
    function methods:SetText(t)
      self._text = t or ""
      if calls.texts and type(t) == "string" then calls.texts[#calls.texts + 1] = t end
    end
    function methods:GetChecked() return self._checked end
    function methods:SetChecked(v) self._checked = v end
    function methods:IsTruncated() return false end
    function methods:SetScript(event, fn) self._scripts[event] = fn end
    function methods:GetScript(event) return self._scripts[event] end
    function methods:HookScript(event, fn)
      local old = self._scripts[event]
      self._scripts[event] = function(...) if old then old(...) end fn(...) end
    end
    function methods:RegisterEvent(event)
      registered[event] = registered[event] or {}
      table.insert(registered[event], self)
    end
    function methods:CreateTexture() return Stub() end
    function methods:CreateFontString() return Stub() end
    function methods:CreateAnimationGroup() return Stub() end
    function methods:GetFontString() return self._fs or Stub() end
    function methods:GetParent() return self._parent or Stub() end
    local CHILDREN = { Inset = true, TitleText = true, Icon = true, Mask = true, HighlightTexture = true, SelectedTexture = true }
    return setmetatable(stub, { __index = function(self, key)
      if methods[key] then
        calls.n = calls.n + 1
        return methods[key]
      end
      if CHILDREN[key] then
        local child = Stub()
        rawset(self, key, child)
        return child
      end
      if type(key) == "string" and key:match("^%l") then return nil end -- fields, not methods
      calls.n = calls.n + 1
      return Other
    end })
  end

  local env = {
    UIParent = Stub("UIParent"),
    GameTooltip = Stub("GameTooltip"),
    DEFAULT_CHAT_FRAME = Stub("ChatFrame1"),
    ChatFontNormal = Stub("ChatFontNormal"),
    QuestTitleFont = Stub("QuestTitleFont"),
    UISpecialFrames = {},
    StaticPopupDialogs = {},
    SlashCmdList = {},
    RAID_CLASS_COLORS = setmetatable({}, { __index = function() return { r = 1, g = 0.5, b = 0.2 } end }),
    ChatTypeInfo = { GUILD = { r = 0.25, g = 1, b = 0.25 }, OFFICER = { r = 0.25, g = 0.75, b = 0.25 } },
    LOCALIZED_CLASS_NAMES_MALE = { DRUID = "Druide", PALADIN = "Paladin", ROGUE = "Schurke" },
    ERR_GUILD_JOIN_S = "%s ist der Gilde beigetreten.",
    ACCEPT = "Annehmen", CANCEL = "Abbrechen", YES = "Ja", NO = "Nein",
  }
  env.CreateFrame = function(_, name, parent)
    local frame = Stub(name)
    frame._parent = parent
    if name then env[name] = frame end
    frame._fs = Stub()
    return frame
  end
  env.C_Timer = {
    After = function(_, fn) timers[#timers + 1] = fn end,
    NewTimer = function(_, fn) timers[#timers + 1] = fn return { Cancel = function() end } end,
    NewTicker = function() return { Cancel = function() end } end,
  }
  env.tinsert = table.insert
  env.GetCursorPosition = function() return 100, 100 end
  env.IsMouseButtonDown = function() return false end
  local SECRET = setmetatable({}, { __index = function() error("secret value inspected") end })
  env.issecretvalue = function(v) return v == SECRET end
  -- Blizzard's guild window, Guildy's host (UI/Main.lua): J shows it, Guildy follows
  env.CommunitiesFrame = Stub("CommunitiesFrame")
  env.GetTime = function() return 1000 end
  env.GetServerTime = function() return 1700000000 end
  env.GetLocale = function() return "deDE" end
  env.IsInGuild = function() return true end
  env.GetGuildInfo = function() return "Murloc Mafia", "Haifutter", 1 end
  env.GetNormalizedRealmName = function() return "Forever" end
  env.UnitName = function() return "Ran", "Fred" end
  env.UnitExists = function() return false end
  env.UnitClass = function() return "Magier", "MAGE" end
  env.UnitLevel = function() return 33 end
  env.UnitRace = function() return "Gnom", "Gnome" end
  env.UnitSex = function() return 3 end
  env.InCombatLockdown = function() return false end
  env.IsShiftKeyDown = function() return false end
  env.IsControlKeyDown = function() return false end
  env.hooksecurefunc = function() end
  env.geterrorhandler = function() return function(err) errors[#errors + 1] = tostring(err) end end
  env.StaticPopup_Show = function() end
  env.PanelTemplates_SetNumTabs = function() end
  env.PanelTemplates_SetTab = function() end
  env.PanelTemplates_TabResize = function() end
  env.ButtonFrameTemplate_HideButtonBar = function() end
  env.ToggleGuildFrame = function() end
  env.CanGuildInvite = function() return true end
  env.CanGuildRemove = function() return true end
  env.CanGuildPromote = function() return true end
  env.CanGuildDemote = function() return true end
  env.CanEditPublicNote = function() return true end
  env.CanEditMOTD = function() return true end
  env.CanEditGuildInfo = function() return true end
  env.GuildControlGetNumRanks = function() return 3 end
  env.GuildControlGetRankName = function(i) return ({ "GM", "Offizier", "Haifutter" })[i] end
  env.C_GuildInfo = {
    GuildRoster = function() end,
    GetMOTD = function() return "Mrglmrglmrgl!" end,
    GetInfoText = function() return "Discord" end,
    CanViewOfficerNote = function() return true end,
    CanEditOfficerNote = function() return true end,
  }
  env.C_ChatInfo = { RegisterAddonMessagePrefix = function() end, SendAddonMessage = function() end, SendChatMessage = function() end }
  env.C_Spell = { GetSpellName = function(id) return "Rezept " .. id end }

  local roster = opts.roster or {
    { "Ran-Fred", "Offizier", 1, 16, "Druide", "Sturmwind", "", "", true, 0, "DRUID", nil, nil, false, nil, nil, "Player-1-01" },
    { "Makira-Farron", "Offizier", 1, 16, "Paladin", "Eisenschmiede", "Heiler", "", false, 0, "PALADIN", nil, nil, false, nil, nil, "Player-1-02" },
    { "Au-Tsch", "Haifutter", 2, 21, "Schurke", "Dämmerwald", "Kürsch", "", true, 0, "ROGUE", nil, nil, false, nil, nil, "Player-1-03" },
  }
  env.GetNumGuildMembers = function() return #roster end
  env.GetGuildRosterInfo = function(i) return unpack(roster[i], 1, 17) end
  env.GetGuildRosterLastOnline = function(i) if i == 2 then return 0, 0, 3, 2 end end
  env.GetNumGuildEvents = function() return 1 end
  env.GetGuildEventInfo = function() return "join", "Au-Tsch", nil, nil, 0, 0, 1, 0 end
  env.GetNumSkillLines = function() return 2 end
  env.GetSkillLineInfo = function(i)
    if i == 1 then return "Berufe", true end
    return "Alchemie", false, nil, 120, 0, 0, 150
  end

  setmetatable(env, { __index = _G })
  env._G = env

  if opts.setup then opts.setup(env) end

  local ns = {}
  for _, file in ipairs(T.tocFiles()) do
    local chunk, err = loadfile(T.addonDir .. "/" .. file)
    if not chunk then error(err) end
    setfenv(chunk, env)
    chunk("Guildy", ns)
    if opts.afterFile then opts.afterFile(file, ns) end
  end

  local function Fire(event, ...)
    for _, frame in ipairs(registered[event] or {}) do
      local handler = frame._scripts.OnEvent
      if handler then handler(frame, event, ...) end
    end
  end

  local function RunTimers(rounds)
    for _ = 1, rounds or 5 do
      local pending = timers
      timers = {}
      for _, fn in ipairs(pending) do fn() end
    end
  end

  return { env = env, ns = ns, errors = errors, Fire = Fire, RunTimers = RunTimers, SECRET = SECRET, calls = calls }
end
