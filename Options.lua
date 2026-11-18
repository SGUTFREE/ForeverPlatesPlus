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

------------------------------------------------------------------------
-- page descriptions: a few lines of plain text at the top of a page
------------------------------------------------------------------------

-- Drawn with our template (Options.xml): the game's section header, re-styled as wrapped body text.
-- Without it (template or game mixin missing) the text goes into a header's tooltip instead.
local DESCRIPTION_TEMPLATE = "ForeverPlatesDescriptionTemplate"
local DESCRIPTION_WIDTH = 560
local CHARS_PER_LINE = 95
local LINE_HEIGHT = 15

local function SetUpDescriptionMixin()
	if ForeverPlatesDescriptionMixin or not SettingsListSectionHeaderMixin then
		return ForeverPlatesDescriptionMixin ~= nil
	end
	ForeverPlatesDescriptionMixin = CreateFromMixins(SettingsListSectionHeaderMixin)
	function ForeverPlatesDescriptionMixin:Init(initializer)
		SettingsListSectionHeaderMixin.Init(self, initializer)
		local title = self.Title
		title:SetFontObject("GameFontHighlight")
		title:ClearAllPoints()
		title:SetPoint("TOPLEFT", 7, -4)
		title:SetWidth(DESCRIPTION_WIDTH)
		title:SetJustifyH("LEFT")
		title:SetJustifyV("TOP")
		title:SetWordWrap(true)
		title:SetText(initializer:GetName())
	end
	return true
end

SetUpDescriptionMixin() -- as early as possible (again at login if the game's mixin wasn't there yet)

local function CanDrawDescriptions()
	return C_XMLUtil and C_XMLUtil.GetTemplateInfo and C_XMLUtil.GetTemplateInfo(DESCRIPTION_TEMPLATE) ~= nil
		and Settings.CreateElementInitializer ~= nil and SetUpDescriptionMixin()
end

local function Description(text)
	if CanDrawDescriptions() then
		local initializer = Settings.CreateElementInitializer(DESCRIPTION_TEMPLATE, { name = text })
		local chars = #text:gsub("[\128-\191]", "") -- letters, not bytes (Cyrillic takes two)
		local lines = math.max(1, math.ceil(chars / CHARS_PER_LINE))
		local height = 10 + lines * LINE_HEIGHT
		initializer.GetExtent = function()
			return height
		end
		layout:AddInitializer(initializer)
	else
		layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(L.ABOUT_PAGE, text))
	end
end

local function Page(name, about)
	category, layout = Settings.RegisterVerticalLayoutSubcategory(mainCategory, name)
	if about then
		Description(about)
	end
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

local function Header(text, tooltip)
	layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(text, tooltip))
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

-- a game number the addon leaves alone until it is changed here: shows what the game has meanwhile
local function GameSlider(key, label, tooltip, minValue, maxValue, step, format)
	local setting = Register(key, Settings.VarType.Number, label,
		function()
			local value = tonumber(ns.Get(key))
			if value == nil and ns.GetGameOption then
				value = ns.GetGameOption(key)
			end
			return value or minValue
		end,
		function(value)
			ns.Set(key, math.floor(value / step + 0.5) * step)
		end)
	local options = Settings.CreateSliderOptions(minValue, maxValue, step)
	options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, format)
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
	Description(L.ABOUT_MAIN)

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

------------------------------------------------------------------------
-- appearance: pick a part (in the sketch or the list), then its sliders
------------------------------------------------------------------------

local PREVIEW_TEMPLATE = "ForeverPlatesPreviewTemplate"
local PREVIEW_HEIGHT = 196

local function SelectedElement()
	local element = ns.db and ns.db.lookElement
	for _, known in ipairs(ns.LOOK_ELEMENTS) do
		if known == element then
			return element
		end
	end
	return ns.LOOK_ELEMENTS[1]
end
ns.GetLookElement = SelectedElement

local function BuildLook()
	Page(L.PAGE_LOOK, L.ABOUT_LOOK)

	local propSettings = {}
	local elementSetting

	-- the sketch (LookPreview.lua); clicking a part selects it below
	if ns.SetUpPreviewMixin and ns.SetUpPreviewMixin() and C_XMLUtil and C_XMLUtil.GetTemplateInfo
		and C_XMLUtil.GetTemplateInfo(PREVIEW_TEMPLATE) and Settings.CreateElementInitializer then
		local initializer = Settings.CreateElementInitializer(PREVIEW_TEMPLATE, { name = L.LOOK_PREVIEW_TITLE, tooltip = L.LOOK_PREVIEW_TT })
		initializer.GetExtent = function()
			return PREVIEW_HEIGHT
		end
		layout:AddInitializer(initializer)
	end

	local function OnElementChanged()
		for _, setting in ipairs(propSettings) do
			setting:NotifyUpdate()
		end
		if ns.RefreshLookPreview then
			ns.RefreshLookPreview()
		end
	end

	local elementEntries = {}
	for _, element in ipairs(ns.LOOK_ELEMENTS) do
		table.insert(elementEntries, { element, L["LOOK_" .. element] or element })
	end
	elementSetting = Register("ui.lookElement", Settings.VarType.String, L.LOOK_ELEMENT,
		SelectedElement,
		function(value)
			ns.db.lookElement = value
			OnElementChanged()
		end,
		ns.LOOK_ELEMENTS[1])
	local elementInit = Settings.CreateDropdown(category, elementSetting, function()
		local container = Settings.CreateControlTextContainer()
		for _, entry in ipairs(elementEntries) do
			container:Add(entry[1], entry[2])
		end
		return container:GetData()
	end, L.LOOK_ELEMENT_TT)

	function ns.SelectLookElement(element)
		if elementSetting.SetValue then
			elementSetting:SetValue(element) -- the dropdown, the sliders and the sketch follow
		else
			ns.db.lookElement = element
			OnElementChanged()
		end
	end

	local function Child(initializer, prop)
		if initializer and initializer.SetParentInitializer and elementInit then
			initializer:SetParentInitializer(elementInit, function()
				return ns.LookHas(SelectedElement(), prop)
			end)
		end
	end

	local function PropSlider(prop, label, tooltip, format)
		local limits = ns.LOOK_LIMITS[prop]
		local fallback = (prop == "scale" or prop == "alpha") and 100 or 0
		local setting = Register("look.current." .. prop, Settings.VarType.Number, label,
			function()
				local value = tonumber(ns.Get(ns.LookKey(SelectedElement(), prop))) or fallback
				return math.max(limits[1], math.min(limits[2], value))
			end,
			function(value)
				value = math.floor(value / limits[3] + 0.5) * limits[3]
				ns.Set(ns.LookKey(SelectedElement(), prop), value)
			end,
			fallback)
		local options = Settings.CreateSliderOptions(limits[1], limits[2], limits[3])
		options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, format)
		Child(Settings.CreateSlider(category, setting, options, tooltip), prop)
		table.insert(propSettings, setting)
	end

	local function Offset(value)
		value = math.floor(value + 0.5)
		return value > 0 and ("+" .. value) or tostring(value)
	end
	PropSlider("scale", L.LOOK_SCALE, L.LOOK_SCALE_TT, Percent)
	PropSlider("alpha", L.LOOK_ALPHA, L.LOOK_ALPHA_TT, Percent)
	PropSlider("x", L.LOOK_X, L.LOOK_X_TT, Offset)
	PropSlider("y", L.LOOK_Y, L.LOOK_Y_TT, Offset)

	local placeSetting = Register("look.current.place", Settings.VarType.String, L.LOOK_PLACE,
		function()
			local element = SelectedElement()
			return ns.LookHas(element, "place") and ns.LookPlace(element) or "auto"
		end,
		function(value)
			local element = SelectedElement()
			if ns.LookHas(element, "place") then
				ns.Set(ns.LookKey(element, "place"), value)
			end
		end,
		"auto")
	Child(Settings.CreateDropdown(category, placeSetting, function()
		local container = Settings.CreateControlTextContainer()
		container:Add("auto", L.LOOK_PLACE_AUTO)
		container:Add("above", L.LOOK_PLACE_ABOVE)
		container:Add("below", L.LOOK_PLACE_BELOW)
		return container:GetData()
	end, L.LOOK_PLACE_TT), "place")
	table.insert(propSettings, placeSetting)

	local reset = CreateSettingsButtonInitializer(L.LOOK_RESET, L.BUTTON_RESET, function()
		ns.ResetLook(SelectedElement())
	end, L.LOOK_RESET_TT, true)
	Child(reset, "scale")
	layout:AddInitializer(reset)
	layout:AddInitializer(CreateSettingsButtonInitializer(L.LOOK_RESET_ALL, L.BUTTON_RESET, function()
		ns.ResetLook(nil)
	end, L.LOOK_RESET_ALL_TT, true))
end

local function BuildEnemies()
	Page(L.PAGE_ENEMIES, L.ABOUT_ENEMIES)

	Header(L.SECTION_HEALTH)
	Checkbox("native.healthValue", L.HEALTH_VALUE, L.HEALTH_SHARED_TT)
	Checkbox("native.healthPercent", L.HEALTH_PERCENT, L.HEALTH_SHARED_TT)
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
	Checkbox("plates.guildEnemies", L.GUILD_ENEMIES, L.GUILD_TT)
	Checkbox("info.quest", L.QUEST_MARK, L.QUEST_MARK_TT)

	Header(L.SECTION_WHICH_ENEMIES)
	GameCheckbox("native.enemyMinions", L.ENEMY_MINIONS, L.GAME_OPTION_TT)
	GameCheckbox("native.smallMinions", L.SMALL_MINIONS, L.GAME_OPTION_TT)
	GameCheckbox("native.enemyMinus", L.ENEMY_MINUS, L.GAME_OPTION_TT)
	GameCheckbox("native.smallMinus", L.SMALL_MINUS, L.GAME_OPTION_TT)
end

local function BuildAllies()
	Page(L.PAGE_ALLIES, L.ABOUT_ALLIES)

	Header(L.SECTION_ALLY_LOOK)
	Dropdown("native.friendNamesOnly", L.FRIEND_NAMES_ONLY, L.FRIEND_NAMES_ONLY_TT, {
		{ "never", L.NAMES_ONLY_NEVER },
		{ "instance", L.NAMES_ONLY_INSTANCE },
		{ "always", L.NAMES_ONLY_ALWAYS },
	})
	Checkbox("native.friendClassColor", L.FRIEND_CLASS_COLOR, L.FRIEND_CLASS_COLOR_TT)
	Checkbox("plates.friendFullNames", L.FRIEND_FULL_NAMES, L.FRIEND_FULL_NAMES_TT)
	Checkbox("plates.guildFriends", L.GUILD_FRIENDS, L.GUILD_TT)
	Checkbox("plates.petNamesOnly", L.PET_NAMES_ONLY, L.PET_NAMES_ONLY_TT)
	Checkbox("plates.petClassColor", L.PET_CLASS_COLOR, L.PET_CLASS_COLOR_TT)
	Checkbox("plates.petOwner", L.PET_OWNER, L.PET_OWNER_TT)

	Header(L.SECTION_ALLY_BARS)
	Checkbox("plates.friendHealthText", L.FRIEND_HEALTH, L.FRIEND_HEALTH_TT)

	Header(L.SECTION_WHICH_ALLIES)
	Checkbox("native.friendlyNpcs", L.FRIENDLY_NPCS)
end

local function BuildCast()
	Page(L.PAGE_CAST, L.ABOUT_CAST)

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
	Page(L.PAGE_AURAS, L.ABOUT_AURAS)

	Header(L.SECTION_MY_DEBUFFS)
	Checkbox("auras.mine", L.MINE, L.MINE_TT)
	Checkbox("auras.minePlayers", L.MINE_PLAYERS)
	Slider("auras.mineMax", L.MINE_MAX, nil, 1, 12, 1)

	Header(L.SECTION_PURGE)
	Checkbox("auras.purge", L.PURGE, L.PURGE_TT)
	Slider("auras.purgeMax", L.PURGE_MAX, nil, 1, 6, 1)

	Header(L.SECTION_DISPEL)
	Checkbox("auras.dispel", L.DISPEL, L.DISPEL_TT)
	Slider("auras.dispelMax", L.DISPEL_MAX, nil, 1, 6, 1)

	Header(L.SECTION_ICONS)
	Checkbox("auras.timer", L.TIMER)

	Header(L.SECTION_GAME_AURAS, L.SECTION_GAME_AURAS_TT)
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
	Page(L.PAGE_VISIBILITY, L.ABOUT_VISIBILITY)

	Header(L.SECTION_LAYOUT)
	Checkbox("native.alwaysShow", L.ALWAYS_SHOW)
	if ns.ClientHasCVar("nameplateMaxDistance") then
		GameSlider("native.maxDistance", L.MAX_DISTANCE, L.MAX_DISTANCE_TT, 10, 60, 1, function(value)
			return L.YARDS:format(math.floor(value + 0.5))
		end)
	end
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
	Page(L.PAGE_THREAT, L.ABOUT_THREAT)

	Header(L.SECTION_THREAT_GAME)
	Dropdown("native.threat", L.THREAT, L.THREAT_TT, {
		{ "none", L.THREAT_NONE },
		{ "progressive", L.THREAT_PROGRESSIVE },
		{ "flash", L.THREAT_FLASH },
		{ "bar", L.THREAT_BAR },
	})
	Header(L.SECTION_THREAT_WARN)
	Checkbox("threat.warn", L.THREAT_WARN, L.THREAT_WARN_TT)
	Slider("threat.warnFrom", L.THREAT_WARN_FROM, L.THREAT_WARN_FROM_TT, 30, 95, 5, Percent)
end

local function BuildKillZone()
	Page(L.PAGE_KILLZONE, L.ABOUT_KILLZONE)

	Header(L.SECTION_KILLZONE)
	Checkbox("killzone.enabled", L.KZ_ENABLED, L.KZ_ENABLED_TT)
	Dropdown("killzone.style", L.KZ_STYLE, L.KZ_STYLE_TT, {
		{ "line", L.KZ_STYLE_LINE },
		{ "zone", L.KZ_STYLE_ZONE },
	})
	Checkbox("killzone.targetOnly", L.KZ_TARGET_ONLY, L.KZ_TARGET_ONLY_TT)
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
	BuildLook()
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
	if ns.RefreshLookPreview then
		ns.RefreshLookPreview()
	end
end

function ns.OpenOptions()
	if mainCategory and Settings.OpenToCategory then
		Settings.OpenToCategory(mainCategory:GetID())
	end
end
