local _, ns = ...
local L = ns.L

-- Settings panel: Esc > Options > AddOns > ForeverPlatesPlus (or /fpl, or the minimap button).
--
-- The main page holds the preset and what concerns every plate. Then one page per kind of nameplate:
-- Враг, Союзник, Питомец союзника. Each starts with a sketch of that nameplate; clicking a part of it
-- (or picking it in the list under the sketch) leaves on the page only that part's settings: whether to
-- show it, its colour, size, opacity, place and its own options. The game's settings list hides and
-- shows them by itself (shown predicates are re-checked whenever a setting changes).
local M = ns.RegisterModule("Options", {})

local mainCategory
local category, layout -- the page being built
local settings = {} -- every registered setting, refreshed when values change outside the panel
local pageKind, partKey -- the part being built: its controls show only while it is selected
local partKeys = {} -- kind -> part -> setting keys (for "reset this part")
local partLabels = {} -- kind -> part -> label
local partSettings = {} -- kind -> the setting of the part list

local usedVariables = {}

-- the settings variable for a key; a key shown in two places (the enemy's shared aura row offset)
-- gets a second variable, both kept in sync by OnSettingsRefreshed
local function Var(key)
	local base = "FOREVERPLATESPLUS_" .. key:gsub("%.", "_"):upper()
	local name, n = base, 1
	while usedVariables[name] do
		n = n + 1
		name = base .. "_" .. n
	end
	usedVariables[name] = true
	return name
end

local function Percent(value)
	return ("%d%%"):format(math.floor(value + 0.5))
end

local function Signed(value)
	value = math.floor(value + 0.5)
	return value > 0 and ("+" .. value) or tostring(value)
end

------------------------------------------------------------------------
-- parts
------------------------------------------------------------------------

local firstPart = {} -- kind -> the part shown until you pick another on the sketch
local pageParts = {} -- kind -> { { key, label }, ... } in page order

function ns.GetPart(kind)
	local parts = ns.db and ns.db.parts
	local part = type(parts) == "table" and parts[kind]
	if part and partLabels[kind] and partLabels[kind][part] then
		return part
	end
	return firstPart[kind] or "plate"
end

function ns.PartLabel(kind, part)
	return partLabels[kind] and partLabels[kind][part] or part
end

-- select a part on a page (from the sketch): the list, the controls and the sketch follow
function ns.SelectPart(kind, part)
	local setting = partSettings[kind]
	if setting and setting.SetValue then
		setting:SetValue(part)
	else
		ns.db.parts = ns.db.parts or {}
		ns.db.parts[kind] = part
		if ns.RefreshLookPreview then
			ns.RefreshLookPreview()
		end
	end
end

local function ResetPart(kind, part)
	for _, key in ipairs(partKeys[kind] and partKeys[kind][part] or {}) do
		ns.db.overrides[key] = nil
	end
	ns.Refresh()
end

-- while set, every control built after it shows only when it returns true (the Friendly page's master switch)
local pageGate

-- initializer belongs to the part being built (and shows only when extra() is true as well)
local function InPart(initializer, extra)
	if initializer and initializer.AddShownPredicate then
		if pageGate then
			initializer:AddShownPredicate(pageGate)
		end
		if pageKind and partKey then
			local kind, part = pageKind, partKey
			initializer:AddShownPredicate(function()
				return ns.GetPart(kind) == part
			end)
		end
		if extra then
			initializer:AddShownPredicate(function()
				return extra() and true or false
			end)
		end
	end
	return initializer
end

local function Track(key)
	if pageKind then
		-- a control above the sketch belongs to the page's main block
		table.insert(partKeys[pageKind][partKey or "main"], key)
	end
end

------------------------------------------------------------------------
-- page descriptions: a few lines of plain text at the top of a page
------------------------------------------------------------------------

-- Drawn with our template (Options.xml): the game's section header, re-styled as wrapped body text.
-- Without it (template or game mixin missing) the text goes into a header's tooltip instead.
local DESCRIPTION_TEMPLATE = "ForeverPlatesPlusDescriptionTemplate"
local DESCRIPTION_WIDTH = 560
local CHARS_PER_LINE = 95
local LINE_HEIGHT = 15

local function SetUpDescriptionMixin()
	if ForeverPlatesPlusDescriptionMixin or not SettingsListSectionHeaderMixin then
		return ForeverPlatesPlusDescriptionMixin ~= nil
	end
	ForeverPlatesPlusDescriptionMixin = CreateFromMixins(SettingsListSectionHeaderMixin)
	function ForeverPlatesPlusDescriptionMixin:Init(initializer)
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

------------------------------------------------------------------------
-- controls (each returns its initializer, already placed in the current part)
------------------------------------------------------------------------

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
	local initializer = CreateSettingsListSectionHeaderInitializer(text, tooltip)
	layout:AddInitializer(initializer)
	return InPart(initializer)
end

local function Checkbox(key, label, tooltip, extra)
	local setting = Register(key, Settings.VarType.Boolean, label,
		function()
			return ns.Get(key) and true or false
		end,
		function(value)
			ns.Set(key, value and true or false)
		end)
	Track(key)
	return InPart(Settings.CreateCheckbox(category, setting, tooltip), extra)
end

-- a game option the addon leaves alone until it is changed here: shows what the game has meanwhile
local function GameCheckbox(key, label, tooltip, extra)
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
	Track(key)
	return InPart(Settings.CreateCheckbox(category, setting, tooltip), extra)
end

local function Slider(key, label, tooltip, minValue, maxValue, step, format, extra)
	local setting = Register(key, Settings.VarType.Number, label,
		function()
			local value = tonumber(ns.Get(key)) or 0
			return math.max(minValue, math.min(maxValue, value))
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
	Track(key)
	return InPart(Settings.CreateSlider(category, setting, options, tooltip), extra)
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
	Track(key)
	return InPart(Settings.CreateSlider(category, setting, options, tooltip))
end

-- returns the initializer and the setting
local function Dropdown(key, label, tooltip, entries, extra, getValue, setValue, explicitDefault)
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
	if not getValue then
		Track(key)
	end
	return InPart(Settings.CreateDropdown(category, setting, GetOptions, tooltip), extra), setting
end

-- a colour (stored as "AARRGGBB", the way the game's colour swatch gives it)
local function ColorSwatch(key, label, tooltip, extra)
	if not Settings.CreateColorSwatch then
		return nil -- an older client without colour swatches in the settings
	end
	local setting = Register(key, Settings.VarType.String, label,
		function()
			return ns.Get(key) or "ffffffff"
		end,
		function(value)
			if type(value) == "string" and value:match("^%x%x%x%x%x%x%x%x$") then
				ns.Set(key, value:lower())
			end
		end)
	Track(key)
	return InPart(Settings.CreateColorSwatch(category, setting, tooltip), extra)
end

local function Button(label, buttonText, onClick, tooltip)
	local initializer = CreateSettingsButtonInitializer(label, buttonText, onClick, tooltip, true)
	layout:AddInitializer(initializer)
	return InPart(initializer)
end

-- size, opacity, offsets (and place for the small second line) of an appearance element;
-- relative: size and opacity count from the name's (guild, pet owner)
local function LookControls(element, relative)
	local limits = ns.LOOK_LIMITS
	local function LookSlider(prop, label, tooltip, format)
		local range = limits[prop]
		Slider(ns.LookKey(element, prop), label, tooltip, range[1], range[2], range[3], format)
	end
	LookSlider("scale", L.LOOK_SCALE, relative and L.LOOK_SCALE_REL_TT or L.LOOK_SCALE_TT, Percent)
	LookSlider("alpha", L.LOOK_ALPHA, relative and L.LOOK_ALPHA_REL_TT or L.LOOK_ALPHA_TT, Percent)
	if ns.LookHas(element, "place") then
		Dropdown(ns.LookKey(element, "place"), L.LOOK_PLACE, L.LOOK_PLACE_TT, {
			{ "auto", L.LOOK_PLACE_AUTO },
			{ "above", L.LOOK_PLACE_ABOVE },
			{ "below", L.LOOK_PLACE_BELOW },
		})
	end
	LookSlider("x", L.LOOK_X, L.LOOK_X_TT, Signed)
	LookSlider("y", L.LOOK_Y, L.LOOK_Y_TT, Signed)
end

-- colour of a name: a choice, plus a colour swatch shown only for "custom"
local function NameColor(element, entries, tooltip)
	local colorKey = "look." .. element .. ".color"
	Dropdown(colorKey, L.COLOR, tooltip, entries)
	ColorSwatch("look." .. element .. ".rgb", L.CUSTOM_COLOR, nil, function()
		return ns.Get(colorKey) == "custom"
	end)
end

------------------------------------------------------------------------
-- pages
------------------------------------------------------------------------

local SKETCH_TEMPLATE = "ForeverPlatesPlusPreviewTemplate"

-- A page for one kind of nameplate (or the unit frames). Top to bottom: a short description; "Main" with
-- what you set most often (MainBlock), always shown; "Fine-tuning" with the sketch, where a click on a
-- part leaves only that part's settings under it (Details, then Part for each part).
local function NameplatePage(kind, name, about, parts)
	category, layout = Settings.RegisterVerticalLayoutSubcategory(mainCategory, name)
	pageKind, partKey, pageGate = kind, nil, nil
	partKeys[kind], partLabels[kind] = { main = {} }, {}
	for _, part in ipairs(parts) do
		partKeys[kind][part[1]] = {}
		partLabels[kind][part[1]] = part[2]
	end
	firstPart[kind] = parts[1][1]
	pageParts[kind] = parts
	Description(about)
end

local function MainBlock()
	partKey = nil
	Header(L.SECTION_MAIN)
end

local function MainResetButton()
	local kind = pageKind
	Button(L.RESET_MAIN, L.BUTTON_RESET, function()
		ResetPart(kind, "main")
	end, L.RESET_MAIN_TT)
end

-- the sketch and the selected part
local function Details(sketchTitle, partLabel)
	local kind = pageKind
	partKey = nil
	Header(L.SECTION_PARTS)

	local hasSketch = ns.SetUpPreviewMixin and ns.SetUpPreviewMixin() and C_XMLUtil and C_XMLUtil.GetTemplateInfo
		and C_XMLUtil.GetTemplateInfo(SKETCH_TEMPLATE) and Settings.CreateElementInitializer and true or false
	if hasSketch then
		local initializer = Settings.CreateElementInitializer(SKETCH_TEMPLATE, { name = sketchTitle or L.SKETCH_TITLE, tooltip = L.SKETCH_TT, kind = kind })
		local height = ns.SKETCH_HEIGHT and ns.SKETCH_HEIGHT[kind] or 160
		initializer.GetExtent = function()
			return height
		end
		layout:AddInitializer(initializer)
		InPart(initializer)
	end

	-- the selected part is a setting of its own: changing it makes the game re-check which options
	-- are listed. With the sketch on the page the part is picked there only (no second list for it).
	local function GetSelected()
		return ns.GetPart(kind)
	end
	local function SetSelected(value)
		ns.db.parts = ns.db.parts or {}
		ns.db.parts[kind] = value
		if ns.RefreshLookPreview then
			ns.RefreshLookPreview()
		end
	end
	local entries = pageParts[kind]
	local setting
	if hasSketch then
		setting = Register("ui.part." .. kind, Settings.VarType.String, partLabel or L.PART, GetSelected, SetSelected, firstPart[kind])
	else
		local _
		_, setting = Dropdown("ui.part." .. kind, partLabel or L.PART, L.PART_TT, entries, nil, GetSelected, SetSelected, firstPart[kind])
	end
	partSettings[kind] = setting
end

local function Part(key)
	partKey = key
end

local function ResetButton()
	local kind, part = pageKind, partKey
	Button(L.RESET_PART, L.BUTTON_RESET, function()
		ResetPart(kind, part)
	end, L.RESET_PART_TT)
end

local function BuildMain()
	mainCategory, layout = Settings.RegisterVerticalLayoutCategory(L.ADDON)
	category = mainCategory
	pageKind, partKey = nil, nil
	Description(L.ABOUT_MAIN)

	Header(L.SECTION_PROFILE)
	local presetEntries = {}
	for _, preset in ipairs(ns.PresetOrder) do
		table.insert(presetEntries, { preset, L[ns.PresetLabelKey[preset]] or preset })
	end
	Dropdown("profile.preset", L.PRESET, L.PRESET_TT, presetEntries, nil,
		function()
			return ns.db.preset
		end,
		function(value)
			ns.SetPreset(value)
		end,
		"auto")
	Button(L.RESET, L.BUTTON_RESET, function()
		ns.ResetOverrides()
		ns.Print(L.RESET_DONE, ns.GetActivePreset())
	end, L.RESET_TT)

	Header(L.SECTION_GENERAL)
	Checkbox("ui.minimap", L.MINIMAP_BUTTON)
	Checkbox("native.manage", L.MANAGE_NATIVE, L.MANAGE_NATIVE_TT)

	Header(L.SECTION_ALL_PLATES, L.SECTION_ALL_PLATES_TT)
	Checkbox("native.alwaysShow", L.ALWAYS_SHOW)
	Checkbox("native.offscreen", L.OFFSCREEN, L.OFFSCREEN_TT)
	if ns.ClientHasCVar("nameplateOccludedAlphaMult") then
		Slider("native.losFade", L.LOS_FADE, L.LOS_FADE_TT, 0, 1, 0.05, function(value)
			return ("%.2f"):format(value)
		end)
	end
end

local NAME_WHERE = {
	{ "game", L.NAME_WHERE_GAME },
	{ "above", L.NAME_WHERE_ABOVE },
	{ "inside", L.NAME_WHERE_INSIDE },
}

local NUMBERS = {
	{ "none", L.NUM_NONE },
	{ "value", L.NUM_VALUE },
	{ "percent", L.NUM_PERCENT },
	{ "both", L.NUM_BOTH },
}

local function BuildEnemy()
	NameplatePage("enemy", L.PAGE_ENEMY, L.ABOUT_ENEMY, {
		{ "plate", L.PART_PLATE },
		{ "name", L.PART_NAME },
		{ "guild", L.PART_GUILD },
		{ "health", L.PART_HEALTH },
		{ "killzone", L.PART_KILLZONE },
		{ "cast", L.PART_CAST },
		{ "castText", L.PART_CAST_TEXT },
		{ "castTimer", L.PART_CAST_TIMER },
		{ "mine", L.PART_MINE },
		{ "purge", L.PART_PURGE },
		{ "gameBuffs", L.PART_GAME_BUFFS },
		{ "gameDebuffs", L.PART_GAME_DEBUFFS },
		{ "gameCC", L.PART_GAME_CC },
		{ "quest", L.PART_QUEST },
	})

	MainBlock()
	Checkbox("plates.enemies", L.ENEMIES_ON, L.ENEMIES_ON_TT)
	-- off: enemy plates are the game's, so the rest of the page has nothing to set
	pageGate = function()
		return ns.Get("plates.enemies") ~= false
	end
	if ns.ClientHasCVar("nameplateMaxDistance") then
		GameSlider("native.maxDistance", L.MAX_DISTANCE, L.MAX_DISTANCE_TT, 10, 60, 1, function(value)
			return L.YARDS:format(math.floor(value + 0.5))
		end)
	end
	Checkbox("native.stackEnemies", L.STACK_ENEMIES, L.STACK_ENEMIES_TT)
	Checkbox("auras.mine", L.PART_MINE, L.MINE_TT)
	Checkbox("auras.purge", L.PART_PURGE, L.PURGE_TT)
	Checkbox("killzone.enabled", L.KZ_ENABLED, L.KZ_ENABLED_TT)
	Checkbox("threat.warn", L.THREAT_WARN, L.THREAT_WARN_TT)
	local function WarnOn()
		return ns.Get("threat.warn")
	end
	Slider("threat.warnFrom", L.THREAT_WARN_FROM, L.THREAT_WARN_FROM_TT, 30, 95, 5, Percent, WarnOn)
	Checkbox("threat.warnPulse", L.THREAT_PULSE, L.THREAT_PULSE_TT, WarnOn)
	Dropdown("native.threat", L.THREAT, L.THREAT_TT, {
		{ "none", L.THREAT_NONE },
		{ "progressive", L.THREAT_PROGRESSIVE },
		{ "flash", L.THREAT_FLASH },
		{ "bar", L.THREAT_BAR },
	})
	Checkbox("cast.timer", L.CAST_TIMER_SHOW, L.CAST_TIMER_TT)
	Checkbox("plates.guildEnemies", L.GUILD_ENEMIES, L.GUILD_TT)
	Checkbox("info.quest", L.QUEST_SHOW, L.QUEST_MARK_TT)
	Checkbox("fade.range", L.FADE_RANGE, L.FADE_RANGE_TT)
	Slider("fade.rangeAlpha", L.FADE_RANGE_ALPHA, nil, 20, 90, 5, Percent, function()
		return ns.Get("fade.range")
	end)
	Checkbox("fade.nonTarget", L.FADE_NONTARGET, L.FADE_NONTARGET_TT)
	Slider("fade.nonTargetAlpha", L.FADE_NONTARGET_ALPHA, nil, 20, 90, 5, Percent, function()
		return ns.Get("fade.nonTarget")
	end)
	MainResetButton()

	Details()

	Part("plate")
	GameCheckbox("native.enemyMinions", L.ENEMY_MINIONS, L.GAME_OPTION_TT)
	GameCheckbox("native.smallMinions", L.SMALL_MINIONS, L.GAME_OPTION_TT)
	GameCheckbox("native.enemyMinus", L.ENEMY_MINUS, L.GAME_OPTION_TT)
	GameCheckbox("native.smallMinus", L.SMALL_MINUS, L.GAME_OPTION_TT)
	ResetButton()

	Part("name")
	NameColor("enemyName", {
		{ "game", L.COLOR_GAME },
		{ "class", L.COLOR_CLASS_PLAYERS },
		{ "white", L.COLOR_WHITE },
		{ "custom", L.COLOR_CUSTOM },
	}, L.ENEMY_COLOR_TT)
	Dropdown("look.enemyName.where", L.NAME_WHERE, L.NAME_WHERE_TT, NAME_WHERE)
	Checkbox("plates.enemyFullNames", L.FULL_NAMES, L.ENEMY_FULL_NAMES_TT)
	LookControls("enemyName")
	ResetButton()

	Part("guild")
	ColorSwatch("look.enemyGuild.rgb", L.COLOR)
	LookControls("enemyGuild", true)
	ResetButton()

	Part("health")
	Dropdown("enemyText.idle", L.ENEMY_IDLE, L.ENEMY_TEXT_TT, NUMBERS)
	Dropdown("enemyText.mouseover", L.ENEMY_MOUSEOVER, L.ENEMY_TEXT_TT, NUMBERS)
	Dropdown("enemyText.target", L.ENEMY_TARGET, L.ENEMY_TEXT_TT, NUMBERS)
	Dropdown("health.format", L.HEALTH_FORMAT, L.HEALTH_FORMAT_TT, {
		{ "short", L.HEALTH_FORMAT_SHORT },
		{ "full", L.HEALTH_FORMAT_FULL },
		{ "game", L.HEALTH_FORMAT_GAME },
	})
	Slider("health.decimals", L.HEALTH_DECIMALS, L.HEALTH_DECIMALS_TT, 0, 2, 1, nil, function()
		return ns.Get("health.format") == "short"
	end)
	LookControls("enemyHealth")
	ResetButton()

	Part("killzone")
	local function KillZoneOn()
		return ns.Get("killzone.enabled")
	end
	Dropdown("killzone.style", L.KZ_STYLE, L.KZ_STYLE_TT, {
		{ "line", L.KZ_STYLE_LINE },
		{ "zone", L.KZ_STYLE_ZONE },
	}, KillZoneOn)
	Checkbox("killzone.targetOnly", L.KZ_TARGET_ONLY, L.KZ_TARGET_ONLY_TT, KillZoneOn)
	Checkbox("killzone.combatOnly", L.KZ_COMBAT_ONLY, L.KZ_COMBAT_ONLY_TT, KillZoneOn)
	Dropdown("killzone.mode", L.KZ_MODE, L.KZ_MODE_TT, {
		{ "spell", L.KZ_MODE_SPELL },
		{ "value", L.KZ_MODE_VALUE },
		{ "percent", L.KZ_MODE_PERCENT },
	}, KillZoneOn)
	Slider("killzone.spellBonus", L.KZ_BONUS, L.KZ_BONUS_TT, -50, 100, 5, function(value)
		return ("%+d%%"):format(math.floor(value + 0.5))
	end, function()
		return KillZoneOn() and ns.Get("killzone.mode") == "spell"
	end)
	Slider("killzone.value", L.KZ_VALUE, L.KZ_VALUE_TT, 10, 5000, 10, nil, function()
		return KillZoneOn() and ns.Get("killzone.mode") ~= "percent"
	end)
	Slider("killzone.percent", L.KZ_PERCENT, nil, 1, 50, 1, Percent, function()
		return KillZoneOn() and ns.Get("killzone.mode") == "percent"
	end)
	Checkbox("killzone.crit", L.KZ_CRIT, L.KZ_CRIT_TT, KillZoneOn)
	Slider("killzone.critMult", L.KZ_CRIT_MULT, L.KZ_CRIT_MULT_TT, 120, 300, 5, Percent, function()
		return KillZoneOn() and ns.Get("killzone.crit")
	end)
	ColorSwatch("killzone.rgb", L.KZ_COLOR, L.KZ_COLOR_TT, KillZoneOn)
	Slider("killzone.width", L.KZ_WIDTH, nil, 1, 4, 1, function(value)
		return L.PIXELS:format(math.floor(value + 0.5))
	end, KillZoneOn)
	Slider("killzone.alpha", L.LOOK_ALPHA, L.KZ_ALPHA_TT, 10, 100, 5, Percent, KillZoneOn)
	ResetButton()

	Part("cast")
	Checkbox("native.castIcon", L.CAST_ICON)
	Checkbox("native.castTarget", L.CAST_TARGET)
	Checkbox("native.castImportant", L.CAST_IMPORTANT)
	Checkbox("native.castOnMe", L.CAST_ON_ME)
	Checkbox("cast.interruptReady", L.CAST_INTERRUPT, L.CAST_INTERRUPT_TT)
	ResetButton()

	Part("castText")
	Checkbox("native.castName", L.SHOW, L.CAST_NAME_TT)
	LookControls("castText")
	ResetButton()

	Part("castTimer")
	LookControls("castTimer")
	ResetButton()

	Part("mine")
	Checkbox("auras.minePlayers", L.MINE_PLAYERS)
	Slider("auras.mineMax", L.HOW_MANY, nil, 1, 12, 1)
	Checkbox("auras.mineTimer", L.TIMER)
	LookControls("mine")
	ResetButton()

	Part("purge")
	Slider("auras.purgeMax", L.HOW_MANY, nil, 1, 6, 1)
	Checkbox("auras.purgeTimer", L.TIMER)
	LookControls("purge")
	ResetButton()

	Part("gameBuffs")
	Checkbox("native.npcBuffs", L.ON_MOBS)
	Checkbox("native.pvpBuffs", L.ON_ENEMY_PLAYERS)
	LookControls("gameBuffs")
	ResetButton()

	Part("gameDebuffs")
	Checkbox("native.npcDebuffs", L.ON_MOBS, L.NPC_DEBUFFS_TT)
	Checkbox("native.pvpDebuffs", L.ON_ENEMY_PLAYERS, L.NPC_DEBUFFS_TT)
	LookControls("gameDebuffs")
	ResetButton()

	Part("gameCC")
	Checkbox("native.npcCC", L.CC_ON_MOBS)
	Checkbox("native.pvpLoC", L.LOC_ON_ENEMY_PLAYERS)
	LookControls("gameCC")
	ResetButton()

	Part("quest")
	LookControls("quest")
	ResetButton()
end

local function BuildAlly()
	NameplatePage("ally", L.PAGE_ALLY, L.ABOUT_ALLY, {
		{ "plate", L.PART_PLATE },
		{ "name", L.PART_NAME },
		{ "guild", L.PART_GUILD },
		{ "health", L.PART_HEALTH },
		{ "dispel", L.PART_DISPEL },
		{ "friendGame", L.PART_FRIEND_GAME },
	})

	MainBlock()
	Checkbox("plates.friends", L.FRIENDS_ON, L.FRIENDS_ON_TT)
	-- off: friendly plates are the game's, so the rest of the page has nothing to set
	pageGate = function()
		return ns.Get("plates.friends") ~= false
	end
	Dropdown("native.friendNamesOnly", L.FRIEND_NAMES_ONLY, L.FRIEND_NAMES_ONLY_TT, {
		{ "never", L.NAMES_ONLY_NEVER },
		{ "instance", L.NAMES_ONLY_INSTANCE },
		{ "always", L.NAMES_ONLY_ALWAYS },
	})
	Checkbox("plates.guildFriends", L.GUILD_FRIENDS, L.GUILD_TT)
	Checkbox("auras.dispel", L.PART_DISPEL, L.DISPEL_TT)
	MainResetButton()

	Details()

	Part("plate")
	Checkbox("native.stackFriends", L.STACK_FRIENDS, L.STACK_FRIENDS_TT)
	Checkbox("native.friendlyNpcs", L.FRIENDLY_NPCS)
	ResetButton()

	Part("name")
	NameColor("friendName", {
		{ "class", L.COLOR_CLASS },
		{ "white", L.COLOR_WHITE },
		{ "custom", L.COLOR_CUSTOM },
	}, L.FRIEND_COLOR_TT)
	Dropdown("look.friendName.where", L.NAME_WHERE, L.NAME_WHERE_ALLY_TT, NAME_WHERE, function()
		return ns.Get("native.friendNamesOnly") ~= "always"
	end)
	Checkbox("plates.friendFullNames", L.FULL_NAMES, L.FRIEND_FULL_NAMES_TT)
	LookControls("friendName")
	ResetButton()

	Part("guild")
	ColorSwatch("look.friendGuild.rgb", L.COLOR)
	LookControls("friendGuild", true)
	ResetButton()

	Part("health")
	Dropdown("plates.friendHealth", L.FRIEND_HEALTH_MODE, L.FRIEND_HEALTH_MODE_TT, NUMBERS)
	LookControls("friendHealth")
	ResetButton()

	Part("dispel")
	Slider("auras.dispelMax", L.HOW_MANY, nil, 1, 6, 1)
	Checkbox("auras.dispelTimer", L.TIMER)
	LookControls("dispel")
	ResetButton()

	Part("friendGame")
	Checkbox("native.friendBuffs", L.FRIEND_BUFFS)
	Checkbox("native.friendDebuffs", L.FRIEND_DEBUFFS)
	Checkbox("native.friendLoC", L.FRIEND_LOC)
	LookControls("friendGame")
	ResetButton()
end

local function BuildPet()
	NameplatePage("pet", L.PAGE_PET, L.ABOUT_PET, {
		{ "name", L.PART_NAME },
		{ "owner", L.PART_OWNER },
	})

	MainBlock()
	Checkbox("plates.petNamesOnly", L.PET_NAMES_ONLY, L.PET_NAMES_ONLY_TT)
	-- off: the game's own pet labels, nothing here to set
	pageGate = function()
		return ns.Get("plates.petNamesOnly") and true or false
	end
	Checkbox("plates.petOwner", L.OWNER_SHOW, L.PET_OWNER_TT)
	MainResetButton()

	Details()

	Part("name")
	NameColor("petName", {
		{ "friend", L.COLOR_LIKE_FRIENDS },
		{ "class", L.COLOR_OWNER_CLASS },
		{ "white", L.COLOR_WHITE },
		{ "custom", L.COLOR_CUSTOM },
	}, L.PET_COLOR_TT)
	LookControls("petName")
	ResetButton()

	Part("owner")
	LookControls("petOwner", true)
	ResetButton()
end

local FRAME_TEXT = {
	{ "game", L.FT_GAME },
	{ "none", L.FT_NONE },
	{ "current", L.FT_CURRENT },
	{ "percent", L.FT_PERCENT },
	{ "currentPercent", L.FT_CURRENT_PERCENT },
	{ "currentMax", L.FT_CURRENT_MAX },
	{ "currentMaxPercent", L.FT_CURRENT_MAX_PERCENT },
	{ "missing", L.FT_MISSING },
	{ "missingPercent", L.FT_MISSING_PERCENT },
	{ "split", L.FT_SPLIT },
}

local function BuildFrames()
	NameplatePage("frames", L.PAGE_FRAMES, L.ABOUT_FRAMES, {
		{ "player", L.PART_FRAME_PLAYER },
		{ "target", L.PART_FRAME_TARGET },
		{ "tot", L.PART_FRAME_TOT },
	})

	MainBlock()
	Dropdown("frames.number", L.FRAMES_NUMBER, nil, {
		{ "short", L.HEALTH_FORMAT_SHORT },
		{ "full", L.HEALTH_FORMAT_FULL },
		{ "game", L.HEALTH_FORMAT_GAME },
	})
	Slider("frames.decimals", L.HEALTH_DECIMALS, L.HEALTH_DECIMALS_TT, 0, 2, 1, nil, function()
		return ns.Get("frames.number") == "short"
	end)
	MainResetButton()

	Details(L.SKETCH_TITLE_FRAMES, L.PART_FRAME)

	for _, frameKey in ipairs(ns.UNIT_FRAMES) do
		Part(frameKey)
		local prefix = "frames." .. frameKey .. "."
		Dropdown(prefix .. "health", L.FRAMES_HEALTH, L.FRAMES_TEXT_TT, FRAME_TEXT)
		Dropdown(prefix .. "mana", L.FRAMES_MANA, L.FRAMES_TEXT_TT, FRAME_TEXT)
		Dropdown(prefix .. "when", L.FRAMES_WHEN, nil, {
			{ "always", L.WHEN_ALWAYS },
			{ "combat", L.WHEN_COMBAT },
			{ "noCombat", L.WHEN_NO_COMBAT },
		})
		Slider(prefix .. "scale", L.FRAMES_SCALE, nil, 50, 200, 5, Percent)
		Button(L.FRAMES_COPY, L.BUTTON_APPLY, function()
			ns.CopyFrameText(frameKey)
		end, L.FRAMES_COPY_TT)
		ResetButton()
	end
end

local function Build()
	BuildMain()
	BuildEnemy()
	BuildAlly()
	BuildPet()
	BuildFrames()
	pageKind, partKey = nil, nil
	Settings.RegisterAddOnCategory(mainCategory)
end

function M:OnLogin()
	local ok, err = pcall(Build)
	if not ok then
		geterrorhandler()("ForeverPlatesPlus options: " .. tostring(err))
	end
end

-- keep the panel in sync after slash commands, preset switches, resets and settings shown twice.
-- Only settings whose value changed are told (each one makes the game re-check the whole page).
local lastValues = {}
function ns.OnSettingsRefreshed()
	for _, setting in ipairs(settings) do
		local ok, value = true, nil
		if setting.GetValue then
			ok, value = pcall(setting.GetValue, setting)
		end
		if not ok or value == nil or lastValues[setting] ~= value then
			lastValues[setting] = value
			if setting.NotifyUpdate then
				setting:NotifyUpdate()
			end
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
