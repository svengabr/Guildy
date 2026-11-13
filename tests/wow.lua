-- The WoW client as far as the tests need it: permissive stubs (any frame method exists), the game
-- functions Guildy calls, and the addon loaded into it file by file in TOC order.
-- dofile(...)(T, opts) returns a fresh world: { env, ns, errors, Fire, RunTimers, SECRET, calls }.
--   opts.roster          guild roster rows (GetGuildRosterInfo values), default three members
--   opts.width / height  size every stub frame reports (lists size their rows from it), default 100
--   opts.setup(env)      changes the environment before the addon loads
--   opts.afterFile(file, ns)  called after each file of the addon has run
--   opts.items           the game's item client as it behaves (world.items, see ItemClient below):
--                        { [itemID] = { name, level, equipLoc, reqLevel, quality, classID, subclassID, bind,
--                        stats = { ITEM_MOD_* = n }, tip = { lines } } }; an ID the table lacks never resolves
--   opts.noCachedCheck   with opts.items: the client has no C_Item.IsItemDataCachedByID
return function(T, opts)
  opts = opts or {}
  local errors = {}
  local calls = { n = 0, objects = 0 } -- widget method calls and widgets created (tests/bench.lua)
  local registered = {}   -- event -> {frames}
  local timers = {}
  local FireEvent -- set once the addon is loaded

  -- The item client: nothing is known until asked; every call that makes the client ask the server for an
  -- item it does not have (RequestLoadItemDataByID, GetItemInfo, GetItemStats, a tooltip, TryOn) while no
  -- query for it is in flight counts in items.requests[itemID]; the answer comes on the next timer round as GET_ITEM_INFO_RECEIVED(itemID,
  -- success), success false for an ID the game does not have (it stays unknown). GetItemStats hands out a
  -- new table on every call. items.tips counts tooltip reads, items.Prime(id) marks an item as loaded.
  local items
  local function IdOf(item)
    return type(item) == "number" and item or tonumber(tostring(item):match("item:(%d+)"))
  end
  if opts.items then
    items = { data = opts.items, cached = {}, pending = {}, requests = {}, tips = 0 }
    function items.Ask(id)
      if not id or items.cached[id] or items.pending[id] then return end -- one query in flight per item
      items.requests[id] = (items.requests[id] or 0) + 1
      items.pending[id] = true
      timers[#timers + 1] = function()
        items.pending[id] = nil
        local ok = items.data[id] ~= nil
        if ok then items.cached[id] = true end
        FireEvent("GET_ITEM_INFO_RECEIVED", id, ok)
      end
    end
    function items.Prime(id) if items.data[id] then items.cached[id] = true end end
    function items.Requests()
      local n = 0
      for _, count in pairs(items.requests) do n = n + count end
      return n
    end
  end

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
    function methods:GetFrameLevel() return rawget(self, "_level") or 1 end
    function methods:SetFrameLevel(level) self._level = level end
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
    function methods:CreateFontString(_, _, template)
      local text = Stub()
      text._font = template
      return text
    end
    function methods:SetBackdropColor(r, g, b, a) self._backdrop = { r, g, b, a or 1 } end
    function methods:GetBackdropColor() return unpack(self._backdrop or { 0, 0, 0, 0 }) end
    function methods:SetBackdropBorderColor(r, g, b, a) self._border = { r, g, b, a or 1 } end
    function methods:GetBackdropBorderColor() return unpack(self._border or { 0, 0, 0, 0 }) end
    -- the height of the text wrapped to its width, as the game's fonts write it: the small fonts 5.5 px
    -- a character and 12 px a line, the huge ones 12 and 24, the others 6.5 and 14
    function methods:GetStringHeight()
      local font = rawget(self, "_font") or ""
      local per, line = 6.5, 14
      if font:find("Small") then per, line = 5.5, 12 elseif font:find("Huge") then per, line = 12, 24 end
      local width = self._w and self._w > 0 and self._w or math.huge
      local lines = 0
      for part in (tostring(self._text):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "") .. "\n"):gmatch("([^\n]*)\n") do
        local chars = 0
        for _ in part:gmatch("[^\128-\191]") do chars = chars + 1 end
        lines = lines + math.max(1, math.ceil(chars * per / width))
      end
      return self._text == "" and 0 or lines * line
    end
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
  env.UIParent._shown = true -- the screen itself: what hangs on it is visible when shown
  env.CreateFrame = function(kind, name, parent, template)
    local frame = Stub(name)
    frame._parent = parent
    if name then env[name] = frame end
    frame._fs = Stub()
    -- a model scene of the game's template: scene IDs, a player actor and a camera (any method exists).
    -- The actor notes its bodies and dressing in actor._log: unit = { "unit:race" }, undress, tryOn.
    -- SetAlpha and EnableMouse are kept (GetAlpha, IsMouseEnabled).
    if kind == "ModelScene" and template == "ModelSceneMixinTemplate" then
      local actor, camera = Stub(), Stub()
      local log = { unit = {}, undress = 0, tryOn = {} }
      rawset(actor, "_log", log)
      rawset(actor, "SetModelByUnit", function(_, unit, _, _, _, _, _, race)
        log.unit[#log.unit + 1] = tostring(unit) .. ":" .. tostring(race)
        return true
      end)
      rawset(actor, "Undress", function() log.undress = log.undress + 1 end)
      rawset(actor, "TryOn", function(_, item)
        log.tryOn[#log.tryOn + 1] = item
        if items then items.Ask(IdOf(item)) end
      end)
      rawset(frame, "SetAlpha", function(self, a) rawset(self, "_alpha", a) end)
      rawset(frame, "GetAlpha", function(self) return rawget(self, "_alpha") or 1 end)
      rawset(frame, "EnableMouse", function(self, on) rawset(self, "_mouse", on and true or false) end)
      rawset(frame, "IsMouseEnabled", function(self) return rawget(self, "_mouse") == true end)
      rawset(frame, "TransitionToModelSceneID", function() end)
      rawset(frame, "GetPlayerActor", function() return actor end)
      rawset(frame, "GetActiveCamera", function() return camera end)
    end
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
  env.ReloadUI = function() calls.reloads = (calls.reloads or 0) + 1 end -- counted, nothing reloads
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

  if items then
    local function Info(item)
      local id = IdOf(item)
      local it = id and items.data[id]
      if not (it and items.cached[id]) then
        items.Ask(id)
        return nil
      end
      -- the link as the game writes it: colour, the item string and the name
      local link = ("|cff1eff00|Hitem:%d::::::::%d:::::::|h[%s]|h|r"):format(id, it.level, it.name)
      return it.name, link, it.quality or 2, it.level, it.reqLevel or 1, "Rüstung", "Leder", 1, it.equipLoc, 134, 1,
        it.classID or 4, it.subclassID or 2, it.bind or 2
    end
    -- a tooltip as C_TooltipInfo hands it out: a new table per call, each line with its colours and args
    local function Line(text)
      local color = { r = 1, g = 1, b = 1, a = 1 }
      return { type = 0, leftText = text, leftColor = color, wrapText = false,
        args = { { field = "type", intVal = 0 }, { field = "leftText", stringVal = text }, { field = "leftColor", colorVal = color } } }
    end
    local function Tip(id, enchant)
      items.tips = items.tips + 1
      local it = id and items.data[id]
      if not (it and items.cached[id]) then
        items.Ask(id)
        return { type = 0, id = id, lines = {}, args = {} }
      end
      local lines = {}
      for i, text in ipairs(it.tip or { it.name }) do lines[i] = Line(text) end
      lines[#lines + 1] = Line("Binden beim Ausrüsten")
      lines[#lines + 1] = Line("Benötigt Stufe " .. (it.reqLevel or 1))
      lines[#lines + 1] = Line("Haltbarkeit 40 / 40")
      if enchant then lines[#lines + 1] = Line("+5 Ausdauer") end
      return { type = 0, id = id, lines = lines, args = { { field = "hyperlink", stringVal = "item:" .. id } }, dataInstanceID = id }
    end
    env.GetItemInfo = Info
    env.C_Item = {
      GetItemInfo = Info,
      RequestLoadItemDataByID = function(id) items.Ask(id) end,
      IsItemDataCachedByID = not opts.noCachedCheck and function(id) return items.cached[id] == true end or nil,
      GetItemStats = function(link)
        local id = IdOf(link)
        local it = id and items.data[id]
        if not (it and items.cached[id]) then
          items.Ask(id)
          return nil
        end
        local copy = {}
        for k, v in pairs(it.stats or {}) do copy[k] = v end
        return copy
      end,
      GetItemInfoInstant = function(item)
        local id = IdOf(item)
        local it = id and items.data[id]
        if it then return id, "Rüstung", "Leder", it.equipLoc end
      end,
    }
    env.C_TooltipInfo = {
      GetItemByID = function(id) return Tip(id) end,
      GetHyperlink = function(link)
        local id, enchant = tostring(link):match("item:(%d+):?(%d*)")
        return Tip(tonumber(id), enchant ~= "" and enchant ~= "0")
      end,
    }
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
  FireEvent = Fire

  local function RunTimers(rounds)
    for _ = 1, rounds or 5 do
      local pending = timers
      timers = {}
      for _, fn in ipairs(pending) do fn() end
    end
  end

  return { env = env, ns = ns, errors = errors, Fire = Fire, RunTimers = RunTimers, SECRET = SECRET, calls = calls,
    items = items }
end
