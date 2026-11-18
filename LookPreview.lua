local _, ns = ...
local L = ns.L

-- The sketch at the top of the appearance page: an enemy plate, an ally and an ally's pet, every part
-- drawn with the current size, opacity and offset. Clicking a part selects it for the sliders below.
-- Only plain textures and font strings of our own: the game's nameplates are not used here.

local BAR_WIDTH, BAR_HEIGHT, CAST_HEIGHT = 150, 12, 8
local NAME_HEIGHT = 13 -- name line height at 100%
local SUBTITLE_SIZE = 0.85 -- as on the plates (HealthText)
local NAME_FONTS = { "SystemFont_NamePlate_Outlined", "SystemFont_NamePlate", "GameFontHighlight" }
local SMALL_FONTS = { "SystemFont_NamePlateCastBar", "GameFontHighlightSmall" }
local ICON_SIZE = { mine = 22, purge = 20, dispel = 16, game = 18, quest = 14 }
local DARK, BLUE, PURPLE, GREY = { 0, 0, 0 }, { 0.25, 0.55, 1 }, { 0.6, 0.2, 0.9 }, { 0.45, 0.45, 0.45 }
local PET_COLOR = { 0.67, 0.83, 0.45 } -- a hunter's pet
local GUILD_COLOR = { 0.85, 0.85, 0.85 }

-- which parts of the sketch belong to an element (built in Build)
local REGIONS = {
	enemyName = { "enemyName" },
	friendName = { "allyName", "petName" },
	guild = { "enemyGuild", "allyGuild" },
	petOwner = { "petOwner" },
	health = { "health" },
	castText = { "castText" },
	castTimer = { "castTimer" },
	mine = { "mine" },
	purge = { "purge" },
	dispel = { "dispel" },
	gameBuffs = { "gameBuffs" },
	gameDebuffs = { "gameDebuffs" },
	gameCC = { "gameCC" },
	quest = { "quest" },
}

-- is the part shown at all (other pages); for the line under the sketch
local function Any(...)
	for i = 1, select("#", ...) do
		if ns.Get((select(i, ...))) then
			return true
		end
	end
	return false
end
local IS_ON = {
	guild = function() return Any("plates.guildFriends", "plates.guildEnemies") end,
	petOwner = function() return Any("plates.petOwner") and Any("plates.petNamesOnly") end,
	health = function() return Any("native.healthValue", "native.healthPercent") end,
	castText = function() return Any("native.castName") end,
	castTimer = function() return Any("cast.timer") end,
	mine = function() return Any("auras.mine") end,
	purge = function() return Any("auras.purge") end,
	dispel = function() return Any("auras.dispel") end,
	gameBuffs = function() return Any("native.npcBuffs", "native.pvpBuffs", "native.friendBuffs") end,
	gameDebuffs = function() return Any("native.npcDebuffs", "native.pvpDebuffs", "native.friendDebuffs") end,
	gameCC = function() return Any("native.npcCC", "native.pvpLoC", "native.friendLoC") end,
	quest = function() return Any("info.quest") end,
}

local current -- the sketch on screen

------------------------------------------------------------------------
-- drawing helpers
------------------------------------------------------------------------

local function FontObject(names)
	for _, name in ipairs(names) do
		local font = _G[name]
		if type(font) == "table" then
			return font
		end
	end
end

local function NewText(parent, text, color, fonts)
	local fontString = parent:CreateFontString(nil, "OVERLAY")
	local font = FontObject(fonts)
	if font then
		fontString:SetFontObject(font)
	end
	fontString:SetText(text)
	fontString:SetTextColor(color[1], color[2], color[3])
	return fontString
end

local function NewBar(parent, width, height, fill, fraction)
	local bar = CreateFrame("Frame", nil, parent)
	bar:SetSize(width, height)
	local back = bar:CreateTexture(nil, "BACKGROUND")
	back:SetAllPoints()
	back:SetColorTexture(0, 0, 0, 0.7)
	local filled = bar:CreateTexture(nil, "ARTWORK")
	filled:SetPoint("TOPLEFT", 1, -1)
	filled:SetPoint("BOTTOMLEFT", 1, 1)
	filled:SetWidth((width - 2) * fraction)
	filled:SetColorTexture(fill[1], fill[2], fill[3], 1)
	return bar
end

-- a row of aura icons: { { texture, border colour }, ... }
local function NewRow(parent, icons)
	local row = CreateFrame("Frame", nil, parent)
	row.icons = {}
	for i, spec in ipairs(icons) do
		local icon = CreateFrame("Frame", nil, row)
		local back = icon:CreateTexture(nil, "BACKGROUND")
		back:SetAllPoints()
		back:SetColorTexture(spec[2][1], spec[2][2], spec[2][3], 1)
		local art = icon:CreateTexture(nil, "ARTWORK")
		art:SetPoint("TOPLEFT", 1, -1)
		art:SetPoint("BOTTOMRIGHT", -1, 1)
		art:SetTexture(spec[1])
		art:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		row.icons[i] = icon
	end
	return row
end

local function SizeRow(row, size)
	size = math.max(4, math.floor(size + 0.5))
	for i, icon in ipairs(row.icons) do
		icon:SetSize(size, size)
		icon:ClearAllPoints()
		icon:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", (i - 1) * (size + 2), 0)
	end
	row:SetSize(#row.icons * (size + 2) - 2, size)
end

local function SetTextScale(fontString, scale)
	if fontString.SetTextScale then
		fontString:SetTextScale(scale)
	end
end

------------------------------------------------------------------------
-- build once per frame
------------------------------------------------------------------------

local function Build(self)
	local canvas = CreateFrame("Frame", nil, self)
	canvas:SetPoint("TOPLEFT", self, "TOPLEFT", 0, -24)
	canvas:SetPoint("BOTTOMRIGHT", self, "BOTTOMRIGHT", 0, 32)
	local back = canvas:CreateTexture(nil, "BACKGROUND")
	back:SetPoint("TOPLEFT", 4, 0)
	back:SetPoint("BOTTOMRIGHT", -24, 0)
	back:SetColorTexture(0, 0, 0, 0.35)
	self.canvas = canvas
	local parts = {}
	self.parts = parts

	-- enemy: name (guild above it), aura rows above, health bar, cast bar under it
	local bar = NewBar(canvas, BAR_WIDTH, BAR_HEIGHT, { 0.8, 0.1, 0.1 }, 0.7)
	bar:SetPoint("TOPLEFT", canvas, "TOPLEFT", 110, -80)
	parts.bar = bar
	local cast = NewBar(canvas, BAR_WIDTH, CAST_HEIGHT, { 1, 0.7, 0 }, 0.55)
	cast:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", 0, -3)
	parts.cast = cast
	local castIcon = cast:CreateTexture(nil, "ARTWORK")
	castIcon:SetSize(12, 12)
	castIcon:SetPoint("TOPLEFT", cast, "BOTTOMLEFT", 0, -1)
	castIcon:SetTexture("Interface\\Icons\\Spell_Fire_FlameBolt")
	castIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	parts.castIcon = castIcon

	parts.enemyName = NewText(canvas, L.SKETCH_ENEMY, { 1, 1, 1 }, NAME_FONTS)
	parts.enemyGuild = NewText(canvas, L.SKETCH_GUILD, GUILD_COLOR, NAME_FONTS)
	parts.health = NewText(bar, "12.3" .. L.ABBR_THOUSAND .. "  70%", { 1, 1, 1 }, SMALL_FONTS)
	parts.castText = NewText(cast, L.SKETCH_SPELL, { 1, 1, 1 }, SMALL_FONTS)
	parts.castTimer = NewText(cast, "1.4", { 1, 1, 1 }, SMALL_FONTS)

	parts.purge = NewRow(canvas, { { "Interface\\Icons\\Spell_Holy_PowerWordShield", BLUE } })
	parts.mine = NewRow(canvas, {
		{ "Interface\\Icons\\Spell_Shadow_ShadowWordPain", DARK },
		{ "Interface\\Icons\\Spell_Shadow_BlackPlague", DARK },
	})
	parts.gameDebuffs = NewRow(canvas, { { "Interface\\Icons\\Ability_Warrior_Sunder", GREY } })
	parts.gameBuffs = NewRow(canvas, { { "Interface\\Icons\\Spell_Holy_InnerFire", GREY } })
	parts.gameCC = NewRow(canvas, { { "Interface\\Icons\\Spell_Nature_Polymorph", GREY } })

	local quest = CreateFrame("Frame", nil, canvas)
	local questIcon = quest:CreateTexture(nil, "OVERLAY")
	questIcon:SetAllPoints()
	local atlas = ns.PickQuestAtlas and ns.PickQuestAtlas()
	if atlas then
		questIcon:SetAtlas(atlas)
	else
		questIcon:SetTexture("Interface\\GossipFrame\\AvailableQuestIcon")
	end
	parts.quest = quest

	-- ally (name only) with a guild line, and its pet with the owner under the name
	local allyBar = CreateFrame("Frame", nil, canvas)
	allyBar:SetSize(BAR_WIDTH, BAR_HEIGHT)
	allyBar:SetPoint("TOPLEFT", canvas, "TOPLEFT", 390, -62)
	parts.allyBar = allyBar
	local petBar = CreateFrame("Frame", nil, canvas)
	petBar:SetSize(BAR_WIDTH, BAR_HEIGHT)
	petBar:SetPoint("TOPLEFT", canvas, "TOPLEFT", 390, -112)
	parts.petBar = petBar
	parts.allyName = NewText(canvas, L.SKETCH_ALLY, { 1, 1, 1 }, NAME_FONTS)
	parts.allyGuild = NewText(canvas, L.SKETCH_GUILD, GUILD_COLOR, NAME_FONTS)
	parts.dispel = NewRow(canvas, { { "Interface\\Icons\\Spell_Shadow_CurseOfTounges", PURPLE } })
	parts.petName = NewText(canvas, L.SKETCH_PET, PET_COLOR, NAME_FONTS)
	parts.petOwner = NewText(canvas, L.SKETCH_ALLY, PET_COLOR, NAME_FONTS)

	-- a button over every part
	self.buttons = {}
	for _, element in ipairs(ns.LOOK_ELEMENTS) do
		for _, regionKey in ipairs(REGIONS[element] or {}) do
			local region = parts[regionKey]
			if region then
				local button = CreateFrame("Button", nil, canvas)
				button:SetFrameLevel(canvas:GetFrameLevel() + 10)
				button:SetPoint("TOPLEFT", region, "TOPLEFT", -2, 2)
				button:SetPoint("BOTTOMRIGHT", region, "BOTTOMRIGHT", 2, -2)
				local selected = button:CreateTexture(nil, "BACKGROUND")
				selected:SetAllPoints()
				selected:SetColorTexture(1, 0.82, 0, 0.3)
				button.selected = selected
				local hover = button:CreateTexture(nil, "HIGHLIGHT")
				hover:SetAllPoints()
				hover:SetColorTexture(1, 1, 1, 0.15)
				button.element = element
				button:SetScript("OnClick", function()
					if ns.SelectLookElement then
						ns.SelectLookElement(element)
					end
				end)
				button:SetScript("OnEnter", function(self)
					if GameTooltip then
						GameTooltip:SetOwner(self, "ANCHOR_TOP")
						GameTooltip:SetText(L["LOOK_" .. element] or element)
						GameTooltip:Show()
					end
				end)
				button:SetScript("OnLeave", function()
					if GameTooltip then
						GameTooltip:Hide()
					end
				end)
				table.insert(self.buttons, button)
			end
		end
	end

	local hint = self:CreateFontString(nil, "OVERLAY")
	hint:SetFontObject(FontObject({ "GameFontHighlightSmall", "GameFontHighlight" }))
	hint:SetPoint("TOPLEFT", canvas, "BOTTOMLEFT", 7, -4)
	hint:SetWidth(560)
	hint:SetJustifyH("LEFT")
	hint:SetJustifyV("TOP")
	hint:SetWordWrap(true)
	self.hint = hint
end

------------------------------------------------------------------------
-- draw with the current settings
------------------------------------------------------------------------

-- a name line: size, opacity, offset from where it sits above its bar
local function PlaceName(fontString, bar, element)
	local scale, alpha = ns.LookScale(element), ns.LookAlpha(element)
	local dx, dy = ns.LookOffset(element)
	SetTextScale(fontString, scale)
	fontString:SetAlpha(alpha)
	fontString:ClearAllPoints()
	fontString:SetPoint("BOTTOM", bar, "TOP", dx, 2 + dy)
	return scale, alpha, dy
end

-- the small second line; nameOnly: the plate shows only the name (auto puts the line under it)
-- returns the room it takes above the name
local function PlaceSubtitle(fontString, name, element, nameScale, nameAlpha, nameOnly)
	local scale = nameScale * SUBTITLE_SIZE * ns.LookScale(element)
	SetTextScale(fontString, scale)
	fontString:SetAlpha(nameAlpha * ns.LookAlpha(element))
	local place = ns.LookPlace(element)
	local above = place == "above" or (place == "auto" and not nameOnly)
	local dx, dy = ns.LookOffset(element)
	fontString:ClearAllPoints()
	if above then
		fontString:SetPoint("BOTTOM", name, "TOP", dx, 1 + dy)
		return math.max(0, NAME_HEIGHT * scale + 1 + dy)
	end
	fontString:SetPoint("TOP", name, "BOTTOM", dx, -1 + dy)
	return 0
end

local function PlaceIcons(row, element, base, point, relativeTo, relativePoint, x, y)
	local dx, dy = ns.LookOffset(element)
	SizeRow(row, base * ns.LookScale(element))
	row:SetAlpha(ns.LookAlpha(element))
	row:ClearAllPoints()
	row:SetPoint(point, relativeTo, relativePoint, x + dx, y + dy)
end

local function Refresh(self)
	local parts = self.parts
	local selected = ns.GetLookElement and ns.GetLookElement() or ns.LOOK_ELEMENTS[1]

	-- enemy
	local nameScale, nameAlpha, nameDy = PlaceName(parts.enemyName, parts.bar, "enemyName")
	local guildRoom = PlaceSubtitle(parts.enemyGuild, parts.enemyName, "guild", nameScale, nameAlpha, false)

	local healthDx, healthDy = ns.LookOffset("health")
	SetTextScale(parts.health, ns.LookScale("health"))
	parts.health:SetAlpha(ns.LookAlpha("health"))
	parts.health:ClearAllPoints()
	parts.health:SetPoint("RIGHT", parts.bar, "RIGHT", -4 + healthDx, healthDy)

	local castDx, castDy = ns.LookOffset("castText")
	SetTextScale(parts.castText, ns.LookScale("castText"))
	parts.castText:SetAlpha(ns.LookAlpha("castText"))
	parts.castText:ClearAllPoints()
	parts.castText:SetPoint("LEFT", parts.castIcon, "RIGHT", 2 + castDx, castDy)
	local timerDx, timerDy = ns.LookOffset("castTimer")
	SetTextScale(parts.castTimer, ns.LookScale("castTimer"))
	parts.castTimer:SetAlpha(ns.LookAlpha("castTimer"))
	parts.castTimer:ClearAllPoints()
	parts.castTimer:SetPoint("LEFT", parts.cast, "RIGHT", 3 + timerDx, timerDy)

	-- the addon's row above the name (purge, then my debuffs), like AnchorContainer in Auras
	local rowY = 2 + NAME_HEIGHT * nameScale + 2 + nameDy + guildRoom
	PlaceIcons(parts.purge, "purge", ICON_SIZE.purge, "BOTTOMLEFT", parts.bar, "TOPLEFT", 0, rowY)
	PlaceIcons(parts.mine, "mine", ICON_SIZE.mine, "BOTTOMLEFT", parts.bar, "TOPLEFT", 0, rowY)
	-- the purge row may have moved with the shared offset: my debuffs follow it
	parts.mine:ClearAllPoints()
	parts.mine:SetPoint("BOTTOMLEFT", parts.purge, "BOTTOMRIGHT", 2, 0)
	PlaceIcons(parts.gameDebuffs, "gameDebuffs", ICON_SIZE.game, "BOTTOMLEFT", parts.mine, "BOTTOMRIGHT", 8, 0)
	PlaceIcons(parts.gameBuffs, "gameBuffs", ICON_SIZE.game, "RIGHT", parts.bar, "LEFT", -22, 0)
	PlaceIcons(parts.gameCC, "gameCC", ICON_SIZE.game, "LEFT", parts.bar, "RIGHT", 5, 0)

	local questSize = math.floor(ICON_SIZE.quest * ns.LookScale("quest") + 0.5)
	local questDx, questDy = ns.LookOffset("quest")
	parts.quest:SetSize(questSize, questSize)
	parts.quest:SetAlpha(ns.LookAlpha("quest"))
	parts.quest:ClearAllPoints()
	parts.quest:SetPoint("RIGHT", parts.bar, "LEFT", -2 + questDx, questDy)

	-- ally and pet: name only
	local allyScale, allyAlpha, allyDy = PlaceName(parts.allyName, parts.allyBar, "friendName")
	PlaceSubtitle(parts.allyGuild, parts.allyName, "guild", allyScale, allyAlpha, true)
	PlaceIcons(parts.dispel, "dispel", ICON_SIZE.dispel, "BOTTOMLEFT", parts.allyBar, "TOPLEFT", 0,
		2 + NAME_HEIGHT * allyScale + 2 + allyDy)
	local rowDx, rowDy = ns.LookOffset("dispel")
	parts.dispel:ClearAllPoints()
	parts.dispel:SetPoint("BOTTOMLEFT", parts.allyBar, "TOPLEFT", rowDx, 2 + NAME_HEIGHT * allyScale + 2 + allyDy + rowDy)
	PlaceName(parts.petName, parts.petBar, "friendName")
	PlaceSubtitle(parts.petOwner, parts.petName, "petOwner", allyScale, allyAlpha, true)

	-- the selected part
	for _, button in ipairs(self.buttons) do
		button.selected:SetShown(button.element == selected)
	end
	local text = (L["LOOK_" .. selected] or selected) .. ": " .. (L["LOOK_HINT_" .. selected] or "")
	if IS_ON[selected] and not IS_ON[selected]() then
		text = text .. " " .. L.LOOK_OFF_NOW
	end
	self.hint:SetText(text)
end

------------------------------------------------------------------------
-- the settings list element (template in Options.xml)
------------------------------------------------------------------------

function ns.SetUpPreviewMixin()
	if ForeverPlatesPreviewMixin then
		return true
	end
	if not SettingsListSectionHeaderMixin or not CreateFromMixins then
		return false
	end
	ForeverPlatesPreviewMixin = CreateFromMixins(SettingsListSectionHeaderMixin)
	function ForeverPlatesPreviewMixin:Init(initializer)
		SettingsListSectionHeaderMixin.Init(self, initializer)
		local title = self.Title
		title:SetFontObject("GameFontNormal")
		title:ClearAllPoints()
		title:SetPoint("TOPLEFT", 7, -6)
		local ok, err = pcall(function()
			if not self.fpBuilt then
				Build(self)
				self.fpBuilt = true
			end
			current = self
			Refresh(self)
		end)
		if not ok then
			geterrorhandler()("ForeverPlates sketch: " .. tostring(err))
		end
	end
	return true
end

ns.SetUpPreviewMixin() -- as early as possible (again when the page is built, if the game's mixin wasn't there yet)

function ns.RefreshLookPreview()
	if current and current.fpBuilt and current:IsVisible() then
		local ok, err = pcall(Refresh, current)
		if not ok then
			geterrorhandler()("ForeverPlates sketch: " .. tostring(err))
		end
	end
end

-- for tests
ns.BuildLookPreview = function(frame)
	Build(frame)
	frame.fpBuilt = true
	current = frame
	Refresh(frame)
end
