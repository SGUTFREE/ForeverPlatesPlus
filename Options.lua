local _, ns = ...
local L = ns.L

-- Settings panel: Esc > Options > AddOns > Forever Plates (or /fpl, or the minimap button).
-- A main page (preset, general) and one page per topic under it.
local M = ns.RegisterModule("Options", {})

local mainCategory
local category, layout -- the page being built
local settings = {} -- every registered setting, refreshed when values change outside the panel

local function Var(key)
	return "FOREVERPLATES_" .. key:gsub("%.", "_"):upper()
end

local function Percent(value)
	return ("%d%%"):format(math.floor(value + 0.5))
end

local function Page(name)
	category, layout = Settings.RegisterVerticalLayoutSubcategory(mainCategory, name)
end

local function Register(key, varType, label, getValue, setValue, explicitDefault)
	local default = explicitDefault
	if default == nil then
		default = ns.GetPresetDefault(key)
	end
	if default == nil then
		if varType == Settings.VarType.Boolean then
			default = false
		elseif varType == Settings.VarType.Number then
			default = 0
		else
			default = ""
		end
	end
	local setting = Settings.RegisterProxySetting(category, Var(key), varType, label, default, getValue, setValue)
	table.insert(settings, setting)
	return setting
end

local function Header(text)
	layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(text))
end

local function Checkbox(key, label, tooltip)
	local setting = Register(key, Settings.VarType.Boolean, label,
		function()
			return ns.Get(key) and true or false
		end,
		function(value)
			ns.Set(key, value and true or false)
		end)
	Settings.CreateCheckbox(category, setting, tooltip)
end

-- a game option the addon leaves alone until it is changed here: shows what the game has meanwhile
local function GameCheckbox(key, label, tooltip)
	local setting = Register(key, Settings.VarType.Boolean, label,
		function()
			local value = ns.Get(key)
			if value == nil and ns.GetGameOption then
				value = ns.GetGameOption(key)
			end
			return value and true or false
		end,
		function(value)
			ns.Set(key, value and true or false)
		end)
	Settings.CreateCheckbox(category, setting, tooltip)
end

local function Slider(key, label, tooltip, minValue, maxValue, step, format)
	local setting = Register(key, Settings.VarType.Number, label,
		function()
			return ns.Get(key)
		end,
		function(value)
			value = math.floor(value / step + 0.5) * step
			if step >= 1 then
				value = math.floor(value + 0.5)
			end
			ns.Set(key, value)
		end)
	local options = Settings.CreateSliderOptions(minValue, maxValue, step)
	options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, format or function(value)
		return tostring(math.floor(value + 0.5))
	end)
	Settings.CreateSlider(category, setting, options, tooltip)
end

local function Dropdown(key, label, tooltip, entries, getValue, setValue, explicitDefault)
	local setting = Register(key, Settings.VarType.String, label,
		getValue or function()
			return ns.Get(key)
		end,
		setValue or function(value)
			ns.Set(key, value)
		end,
		explicitDefault)
	local function GetOptions()
		local container = Settings.CreateControlTextContainer()
		for _, entry in ipairs(entries) do
			container:Add(entry[1], entry[2])
		end
		return container:GetData()
	end
	Settings.CreateDropdown(category, setting, GetOptions, tooltip)
end

------------------------------------------------------------------------
-- pages
------------------------------------------------------------------------

local function BuildMain()
	mainCategory, layout = Settings.RegisterVerticalLayoutCategory(L.ADDON)
	category = mainCategory

	Header(L.SECTION_PROFILE)
	local presetEntries = {}
	for _, preset in ipairs(ns.PresetOrder) do
		table.insert(presetEntries, { preset, L[ns.PresetLabelKey[preset]] or preset })
	end
	Dropdown("profile.preset", L.PRESET, L.PRESET_TT, presetEntries,
		function()
			return ns.db.preset
		end,
		function(value)
			ns.SetPreset(value)
		end,
		"auto")
	layout:AddInitializer(CreateSettingsButtonInitializer(L.RESET, L.BUTTON_RESET, function()
		ns.ResetOverrides()
		ns.Print(L.RESET_DONE, ns.GetActivePreset())
	end, L.RESET_TT, true))

	Header(L.SECTION_GENERAL)
	Checkbox("ui.minimap", L.MINIMAP_BUTTON)
	Checkbox("native.manage", L.MANAGE_NATIVE, L.MANAGE_NATIVE_TT)
end

local function BuildEnemies()
	Page(L.PAGE_ENEMIES)

	Header(L.SECTION_HEALTH)
	Checkbox("native.healthValue", L.HEALTH_VALUE)
	Checkbox("native.healthPercent", L.HEALTH_PERCENT)
	Dropdown("health.format", L.HEALTH_FORMAT, L.HEALTH_FORMAT_TT, {
		{ "short", L.HEALTH_FORMAT_SHORT },
		{ "full", L.HEALTH_FORMAT_FULL },
		{ "game", L.HEALTH_FORMAT_GAME },
	})
	Slider("health.decimals", L.HEALTH_DECIMALS, L.HEALTH_DECIMALS_TT, 0, 2, 1)

	Header(L.SECTION_ENEMY_TEXT)
	local numberEntries = {
		{ "none", L.NUM_NONE },
		{ "value", L.NUM_VALUE },
		{ "percent", L.NUM_PERCENT },
		{ "both", L.NUM_BOTH },
	}
	Dropdown("enemyText.idle", L.ENEMY_IDLE, L.ENEMY_TEXT_TT, numberEntries)
	Dropdown("enemyText.mouseover", L.ENEMY_MOUSEOVER, L.ENEMY_TEXT_TT, numberEntries)
	Dropdown("enemyText.target", L.ENEMY_TARGET, L.ENEMY_TEXT_TT, numberEntries)

	Header(L.SECTION_NAME_MARKS)
	Checkbox("plates.enemyFullNames", L.ENEMY_FULL_NAMES, L.ENEMY_FULL_NAMES_TT)
	Checkbox("info.quest", L.QUEST_MARK, L.QUEST_MARK_TT)

	Header(L.SECTION_WHICH_ENEMIES)
	GameCheckbox("native.enemyMinions", L.ENEMY_MINIONS, L.GAME_OPTION_TT)
	GameCheckbox("native.smallMinions", L.SMALL_MINIONS, L.GAME_OPTION_TT)
	GameCheckbox("native.enemyMinus", L.ENEMY_MINUS, L.GAME_OPTION_TT)
	GameCheckbox("native.smallMinus", L.SMALL_MINUS, L.GAME_OPTION_TT)
end

local function BuildAllies()
	Page(L.PAGE_ALLIES)

	Header(L.SECTION_ALLY_LOOK)
	Dropdown("native.friendNamesOnly", L.FRIEND_NAMES_ONLY, L.FRIEND_NAMES_ONLY_TT, {
		{ "never", L.NAMES_ONLY_NEVER },
		{ "instance", L.NAMES_ONLY_INSTANCE },
		{ "always", L.NAMES_ONLY_ALWAYS },
	})
	Checkbox("native.friendClassColor", L.FRIEND_CLASS_COLOR, L.FRIEND_CLASS_COLOR_TT)
	Slider("plates.friendNameAlpha", L.FRIEND_NAME_ALPHA, L.FRIEND_NAME_ALPHA_TT, 20, 100, 5, Percent)
	Checkbox("plates.friendFullNames", L.FRIEND_FULL_NAMES, L.FRIEND_FULL_NAMES_TT)
	Checkbox("plates.petNamesOnly", L.PET_NAMES_ONLY, L.PET_NAMES_ONLY_TT)

	Header(L.SECTION_ALLY_BARS)
	Checkbox("plates.friendHealthText", L.FRIEND_HEALTH, L.FRIEND_HEALTH_TT)
	Checkbox("native.friendlyNpcs", L.FRIENDLY_NPCS)
end

local function BuildCast()
	Page(L.PAGE_CAST)

	Header(L.SECTION_CAST_GAME)
	Checkbox("native.castName", L.CAST_NAME)
	Checkbox("native.castIcon", L.CAST_ICON)
	Checkbox("native.castTarget", L.CAST_TARGET)
	Checkbox("native.castImportant", L.CAST_IMPORTANT)
	Checkbox("native.castOnMe", L.CAST_ON_ME)

	Header(L.SECTION_CAST_EXTRA)
	Checkbox("cast.timer", L.CAST_TIMER, L.CAST_TIMER_TT)
	Checkbox("cast.interruptReady", L.CAST_INTERRUPT, L.CAST_INTERRUPT_TT)
end

local function BuildAuras()
	Page(L.PAGE_AURAS)

	Header(L.SECTION_MY_DEBUFFS)
	Checkbox("auras.mine", L.MINE, L.MINE_TT)
	Checkbox("auras.minePlayers", L.MINE_PLAYERS)
	Slider("auras.mineSize", L.MINE_SIZE, nil, 14, 36, 1)
	Slider("auras.mineMax", L.MINE_MAX, nil, 1, 12, 1)

	Header(L.SECTION_PURGE)
	Checkbox("auras.purge", L.PURGE, L.PURGE_TT)
	Slider("auras.purgeSize", L.PURGE_SIZE, nil, 12, 32, 1)
	Slider("auras.purgeMax", L.PURGE_MAX, nil, 1, 6, 1)

	Header(L.SECTION_DISPEL)
	Checkbox("auras.dispel", L.DISPEL, L.DISPEL_TT)
	Slider("auras.dispelSize", L.DISPEL_SIZE, nil, 12, 30, 1)
	Slider("auras.dispelMax", L.DISPEL_MAX, nil, 1, 6, 1)

	Header(L.SECTION_ICONS)
	Checkbox("auras.timer", L.TIMER)

	Header(L.SECTION_GAME_AURAS)
	Checkbox("native.npcBuffs", L.NPC_BUFFS)
	Checkbox("native.npcDebuffs", L.NPC_DEBUFFS, L.NPC_DEBUFFS_TT)
	Checkbox("native.npcCC", L.NPC_CC)
	Checkbox("native.pvpBuffs", L.PVP_BUFFS)
	Checkbox("native.pvpDebuffs", L.PVP_DEBUFFS, L.NPC_DEBUFFS_TT)
	Checkbox("native.pvpLoC", L.PVP_LOC)
	Checkbox("native.friendBuffs", L.FRIEND_BUFFS)
	Checkbox("native.friendDebuffs", L.FRIEND_DEBUFFS)
	Checkbox("native.friendLoC", L.FRIEND_LOC)
end

local function BuildVisibility()
	Page(L.PAGE_VISIBILITY)

	Header(L.SECTION_LAYOUT)
	Checkbox("native.alwaysShow", L.ALWAYS_SHOW)
	Checkbox("native.stackEnemies", L.STACK_ENEMIES, L.STACK_ENEMIES_TT)
	Checkbox("native.stackFriends", L.STACK_FRIENDS, L.STACK_FRIENDS_TT)
	Checkbox("native.offscreen", L.OFFSCREEN, L.OFFSCREEN_TT)

	Header(L.SECTION_FADE)
	Checkbox("fade.range", L.FADE_RANGE, L.FADE_RANGE_TT)
	Slider("fade.rangeAlpha", L.FADE_RANGE_ALPHA, nil, 20, 90, 5, Percent)
	Checkbox("fade.nonTarget", L.FADE_NONTARGET, L.FADE_NONTARGET_TT)
	Slider("fade.nonTargetAlpha", L.FADE_NONTARGET_ALPHA, nil, 20, 90, 5, Percent)
	if ns.ClientHasCVar("nameplateOccludedAlphaMult") then
		Slider("native.losFade", L.LOS_FADE, L.LOS_FADE_TT, 0, 1, 0.05, function(value)
			return ("%.2f"):format(value)
		end)
	end
end

local function BuildThreat()
	Page(L.PAGE_THREAT)

	Dropdown("native.threat", L.THREAT, L.THREAT_TT, {
		{ "none", L.THREAT_NONE },
		{ "progressive", L.THREAT_PROGRESSIVE },
		{ "flash", L.THREAT_FLASH },
		{ "bar", L.THREAT_BAR },
	})
	Checkbox("threat.warn", L.THREAT_WARN, L.THREAT_WARN_TT)
	Slider("threat.warnFrom", L.THREAT_WARN_FROM, L.THREAT_WARN_FROM_TT, 30, 95, 5, Percent)
end

local function BuildKillZone()
	Page(L.PAGE_KILLZONE)

	Checkbox("killzone.enabled", L.KZ_ENABLED, L.KZ_ENABLED_TT)
	Checkbox("killzone.combatOnly", L.KZ_COMBAT_ONLY, L.KZ_COMBAT_ONLY_TT)
	Dropdown("killzone.mode", L.KZ_MODE, L.KZ_MODE_TT, {
		{ "spell", L.KZ_MODE_SPELL },
		{ "value", L.KZ_MODE_VALUE },
		{ "percent", L.KZ_MODE_PERCENT },
	})
	Slider("killzone.spellBonus", L.KZ_BONUS, L.KZ_BONUS_TT, -50, 100, 5, function(value)
		return ("%+d%%"):format(math.floor(value + 0.5))
	end)
	Slider("killzone.value", L.KZ_VALUE, L.KZ_VALUE_TT, 10, 5000, 10)
	Slider("killzone.percent", L.KZ_PERCENT, nil, 1, 50, 1, Percent)
	Checkbox("killzone.crit", L.KZ_CRIT, L.KZ_CRIT_TT)
	Slider("killzone.critMult", L.KZ_CRIT_MULT, L.KZ_CRIT_MULT_TT, 120, 300, 5, Percent)
end

local function Build()
	BuildMain()
	BuildEnemies()
	BuildAllies()
	BuildCast()
	BuildAuras()
	BuildVisibility()
	BuildThreat()
	BuildKillZone()
	Settings.RegisterAddOnCategory(mainCategory)
end

function M:OnLogin()
	local ok, err = pcall(Build)
	if not ok then
		geterrorhandler()("ForeverPlates options: " .. tostring(err))
	end
end

-- keep the panel in sync after slash commands, preset switches and resets
function ns.OnSettingsRefreshed()
	for _, setting in ipairs(settings) do
		if setting.NotifyUpdate then
			setting:NotifyUpdate()
		end
	end
end

function ns.OpenOptions()
	if mainCategory and Settings.OpenToCategory then
		Settings.OpenToCategory(mainCategory:GetID())
	end
end
