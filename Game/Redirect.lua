-- Puts Guildy on the guild window key (J) without touching Blizzard's code: every key bound to
-- TOGGLEGUILDTAB gets a temporary override binding that clicks a hidden Guildy button. Override
-- bindings are not saved, so disabling Guildy gives J back. Blizzard's window stays untouched and
-- reachable through the guild micro button and Guildy's Blizzard-window buttons, which matters on
-- Forever: guild management only works from an untainted Blizzard window.
local _, ns = ...

local Redirect = {}
ns.Redirect = Redirect

local owner = CreateFrame("Frame")
local toggle = CreateFrame("Button", "GuildyToggleButton", UIParent)
toggle:SetScript("OnClick", function() ns.UI.Toggle() end)
local pending = false

function Redirect.Apply()
  if InCombatLockdown() then
    pending = true
    return
  end
  pending = false
  ClearOverrideBindings(owner)
  local getKeys = rawget(_G, "GetBindingKey")
  if not getKeys then return end
  for _, key in ipairs({ getKeys("TOGGLEGUILDTAB") }) do
    SetOverrideBindingClick(owner, false, key, "GuildyToggleButton", "LeftButton")
  end
end

-- PLAYER_REGEN_ENABLED: bindings changed during combat
function Redirect.AfterCombat()
  if pending then Redirect.Apply() end
end
