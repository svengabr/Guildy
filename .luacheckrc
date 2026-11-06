-- luacheck config: every WoW global the addon touches must be listed here, so a typo or an accidental
-- global fails the check instead of erroring in the client.
std = "lua51"
max_line_length = false
self = false -- methods with an unused self (widget callbacks) are fine
exclude_files = { "tests/", "Libs/", ".luacheckrc" }

-- Globals the addon writes to
globals = {
  "GuildyDB",
  "SLASH_GUILDY1",
  "SlashCmdList",
  "StaticPopupDialogs",
  "_G",
}

read_globals = {
  "C_AddOns", "C_CVar", "C_ChatInfo", "C_Club", "C_CreatureInfo", "C_GuildInfo", "C_Item", "C_PartyInfo", "C_Spell", "C_Texture",
  "C_Timer", "C_TradeSkillUI", "Enum",
  "ACCEPT", "CANCEL", "YES", "NO",
  "BackdropTemplateMixin", "ClearOverrideBindings", "SetOverrideBindingClick", "ButtonFrameTemplate_HideButtonBar", "ChatFrameUtil", "ChatTypeInfo", "ClearCursor",
  "CreateFrame", "DEFAULT_CHAT_FRAME", "GameTooltip", "GetCursorInfo", "GetGuildInfo", "GetGuildRosterInfo",
  "GetGuildRosterLastOnline", "GetLocale", "GetTime", "GetUnitName", "InCombatLockdown", "IsInGuild",
  "IsShiftKeyDown", "PanelTemplates_SetNumTabs", "PanelTemplates_SetTab", "PanelTemplates_TabResize", "QuestTitleFont", "StaticPopup_Show", "UIParent", "UISpecialFrames",
  "UnitExists", "UnitIsPlayer", "UnitIsUnit", "UnitName", "hooksecurefunc", "tinsert",
}
