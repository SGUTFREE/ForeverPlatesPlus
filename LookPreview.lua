local _, ns = ...
local L = ns.L

-- The sketch at the top of the Враг / Союзник / Питомец pages: one drawn nameplate, every part drawn
-- with the current settings (shown or not, colour, size, opacity, offset). Clicking a part selects it:
-- the page then lists only that part's settings. Parts that are turned off are drawn faint.
-- Only plain textures and font strings of our own: the game's nameplates are not used here.

local BAR_WIDTH, BAR_HEIGHT, CAST_HEIGHT = 160, 12, 8
local BAR_X = 210 -- left edge of the bar in the sketch
local NAME_HEIGHT = 13 -- name line height at 100%
local SUBTITLE_SIZE = 0.85 -- as on the plates (HealthText)
local OFF_ALPHA = 0.25 -- a part that is turned off
local NAME_FONTS = { "SystemFont_NamePlate_Outlined", "SystemFont_NamePlate", "GameFontHighlight" }
local SMALL_FONTS = { "SystemFont_NamePlateCastBar", "GameFontHighlightSmall" }
local ICON_SIZE = { mine = 22, purge = 20, dispel = 16, game = 18, quest = 14 }
local DARK, BLUE, PURPLE, GREY = { 0, 0, 0 }, { 0.25, 0.55, 1 }, { 0.6, 0.2, 0.9 }, { 0.45, 0.45, 0.45 }
local WHITE = { 1, 1, 1 }

-- colours the sketch uses for "as in the game" and "class colour"
local SAMPLE_COLOR = {
	enemyName = { game = { 1, 0.25, 0.25 }, class = { 0.78, 0.61, 0.43 } }, -- hostile red; a warrior
	friendName = { class = { 1, 1, 1 } },                                   -- a priest
	petName = { class = { 0.67, 0.83, 0.45 } },                             -- a hunter's pet
}

ns.SKETCH_HEIGHT = { enemy = 200, ally = 150, pet = 124 }

-- sketch region -> part of the page (the regions are built in Build)
local REGIONS = {
	enemy = {
		{ "bar", "plate" }, { "aggro", "aggro" }, { "killzone", "killzone" }, { "health", "health" },
		{ "enemyName", "name" }, { "enemyGuild", "guild" }, { "cast", "cast" }, { "castText", "castText" },
		{ "castTimer", "castTimer" }, { "purge", "purge" }, { "mine", "mine" }, { "gameDebuffs", "gameDebuffs" },
		{ "gameBuffs", "gameBuffs" }, { "gameCC", "gameCC" }, { "quest", "quest" },
	},
	ally = {
		{ "bar", "plate" }, { "health", "health" }, { "allyName", "name" }, { "allyGuild", "guild" },
		{ "dispel", "dispel" }, { "friendGame", "friendGame" },
	},
	pet = {
		{ "bar", "plate" }, { "petName", "name" }, { "petOwner", "owner" },
	},
}

-- is a part shown at all; parts not listed are always on
local function Any(...)
	for i = 1, select("#", ...) do
		if ns.Get((select(i, ...))) then
			return true
		end
	end
	return false
end
local IS_ON = {
	enemy = {
		guild = function() return Any("plates.guildEnemies") end,
		health = function() return ns.Get("enemyText.idle") ~= "none" or ns.Get("enemyText.mouseover") ~= "none" or ns.Get("enemyText.target") ~= "none" end,
		aggro = function() return Any("threat.warn") or ns.Get("native.threat") ~= "none" end,
		killzone = function() return Any("killzone.enabled") end,
		castText = function() return Any("native.castName") end,
		castTimer = function() return Any("cast.timer") end,
		mine = function() return Any("auras.mine") end,
		purge = function() return Any("auras.purge") end,
		gameBuffs = function() return Any("native.npcBuffs", "native.pvpBuffs") end,
		gameDebuffs = function() return Any("native.npcDebuffs", "native.pvpDebuffs") end,
		gameCC = function() return Any("native.npcCC", "native.pvpLoC") end,
		quest = function() return Any("info.quest") end,
	},
	ally = {
		guild = function() return Any("plates.guildFriends") end,
		health = function() return ns.Get("plates.friendHealth") ~= "none" and ns.Get("native.friendNamesOnly") ~= "always" end,
		dispel = function() return Any("auras.dispel") end,
		friendGame = function() return Any("native.friendBuffs", "native.friendDebuffs", "native.friendLoC") end,
	},
	pet = {
		owner = function() return Any("plates.petOwner") end,
	},
}

function ns.IsPartOn(kind, part)
	local check = IS_ON[kind] and IS_ON[kind][part]
	return not check or check()
end

local shownSketches = {} -- kind -> the frame showing it

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

local function NewText(parent, text, fonts)
	local fontString = parent:CreateFontString(nil, "OVERLAY")
	local font = FontObject(fonts)
	if font then
		fontString:SetFontObject(font)
	end
	fontString:SetText(text)
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

local function Faint(kind, part)
	return ns.IsPartOn(kind, part) and 1 or OFF_ALPHA
end

------------------------------------------------------------------------
-- build: one set of regions per kind, inside one settings list frame
------------------------------------------------------------------------

local function BuildEnemy(canvas, parts)
	local bar = NewBar(canvas, BAR_WIDTH, BAR_HEIGHT, { 0.8, 0.1, 0.1 }, 0.7)
	bar:SetPoint("TOPLEFT", canvas, "TOPLEFT", BAR_X, -84)
	parts.bar = bar
	local aggro = bar:CreateTexture(nil, "OVERLAY")
	aggro:SetPoint("BOTTOMLEFT", bar, "TOPLEFT", 0, 0)
	aggro:SetSize(BAR_WIDTH * 0.6, 3)
	aggro:SetColorTexture(1, 0.85, 0.1, 0.9)
	parts.aggro = aggro
	local killzone = bar:CreateTexture(nil, "OVERLAY")
	killzone:SetPoint("TOPLEFT", bar, "TOPLEFT", BAR_WIDTH * 0.3, 0)
	killzone:SetSize(2, BAR_HEIGHT)
	killzone:SetColorTexture(0.75, 0.3, 1, 1)
	parts.killzone = killzone

	local cast = NewBar(canvas, BAR_WIDTH, CAST_HEIGHT, { 1, 0.7, 0 }, 0.55)
	cast:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", 0, -3)
	parts.cast = cast
	local castIcon = cast:CreateTexture(nil, "ARTWORK")
	castIcon:SetSize(12, 12)
	castIcon:SetPoint("TOPLEFT", cast, "BOTTOMLEFT", 0, -1)
	castIcon:SetTexture("Interface\\Icons\\Spell_Fire_FlameBolt")
	castIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	parts.castIcon = castIcon

	parts.enemyName = NewText(canvas, L.SKETCH_ENEMY, NAME_FONTS)
	parts.enemyGuild = NewText(canvas, L.SKETCH_GUILD, NAME_FONTS)
	parts.health = NewText(bar, "12.3" .. L.ABBR_THOUSAND .. "  70%", SMALL_FONTS)
	parts.castText = NewText(cast, L.SKETCH_SPELL, SMALL_FONTS)
	parts.castTimer = NewText(cast, "1.4", SMALL_FONTS)

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
end

local function BuildAlly(canvas, parts)
	local bar = NewBar(canvas, BAR_WIDTH, BAR_HEIGHT, { 0.1, 0.75, 0.1 }, 0.85)
	bar:SetPoint("TOPLEFT", canvas, "TOPLEFT", BAR_X, -66)
	parts.bar = bar
	parts.health = NewText(bar, "2.9" .. L.ABBR_THOUSAND .. "  85%", SMALL_FONTS)
	parts.allyName = NewText(canvas, L.SKETCH_ALLY, NAME_FONTS)
	parts.allyGuild = NewText(canvas, L.SKETCH_GUILD, NAME_FONTS)
	parts.dispel = NewRow(canvas, { { "Interface\\Icons\\Spell_Shadow_CurseOfTounges", PURPLE } })
	parts.friendGame = NewRow(canvas, { { "Interface\\Icons\\Spell_Nature_Sleep", GREY } })
end

local function BuildPet(canvas, parts)
	local bar = NewBar(canvas, BAR_WIDTH, BAR_HEIGHT, { 0.1, 0.75, 0.1 }, 1)
	bar:SetPoint("TOPLEFT", canvas, "TOPLEFT", BAR_X, -46)
	parts.bar = bar
	parts.petName = NewText(canvas, L.SKETCH_PET, NAME_FONTS)
	parts.petOwner = NewText(canvas, L.SKETCH_ALLY, NAME_FONTS)
end

local BUILDERS = { enemy = BuildEnemy, ally = BuildAlly, pet = BuildPet }

local function BuildKind(self, kind)
	local sketch = { kind = kind, parts = {}, buttons = {} }
	local canvas = CreateFrame("Frame", nil, self)
	canvas:SetPoint("TOPLEFT", self, "TOPLEFT", 0, -24)
	canvas:SetPoint("BOTTOMRIGHT", self, "BOTTOMRIGHT", 0, 32)
	local back = canvas:CreateTexture(nil, "BACKGROUND")
	back:SetPoint("TOPLEFT", 4, 0)
	back:SetPoint("BOTTOMRIGHT", -24, 0)
	back:SetColorTexture(0, 0, 0, 0.35)
	sketch.canvas = canvas
	BUILDERS[kind](canvas, sketch.parts)

	-- a button over every part; the bar's button lies under the parts drawn on the bar
	for index, entry in ipairs(REGIONS[kind]) do
		local region, part = sketch.parts[entry[1]], entry[2]
		if region then
			local button = CreateFrame("Button", nil, canvas)
			button:SetFrameLevel(canvas:GetFrameLevel() + 10 + index)
			button:SetPoint("TOPLEFT", region, "TOPLEFT", -2, 2)
			button:SetPoint("BOTTOMRIGHT", region, "BOTTOMRIGHT", 2, -2)
			local selected = button:CreateTexture(nil, "BACKGROUND")
			selected:SetAllPoints()
			selected:SetColorTexture(1, 0.82, 0, 0.3)
			button.selected = selected
			local hover = button:CreateTexture(nil, "HIGHLIGHT")
			hover:SetAllPoints()
			hover:SetColorTexture(1, 1, 1, 0.15)
			button.part = part
			button:SetScript("OnClick", function()
				if ns.SelectPart then
					ns.SelectPart(kind, part)
				end
			end)
			button:SetScript("OnEnter", function(owner)
				if GameTooltip then
					GameTooltip:SetOwner(owner, "ANCHOR_TOP")
					GameTooltip:SetText(ns.PartLabel and ns.PartLabel(kind, part) or part)
					GameTooltip:Show()
				end
			end)
			button:SetScript("OnLeave", function()
				if GameTooltip then
					GameTooltip:Hide()
				end
			end)
			table.insert(sketch.buttons, button)
		end
	end

	local hint = canvas:CreateFontString(nil, "OVERLAY")
	local font = FontObject({ "GameFontHighlightSmall", "GameFontHighlight" })
	if font then
		hint:SetFontObject(font)
	end
	hint:SetPoint("TOPLEFT", canvas, "BOTTOMLEFT", 7, -4)
	hint:SetWidth(560)
	hint:SetJustifyH("LEFT")
	hint:SetJustifyV("TOP")
	hint:SetWordWrap(true)
	sketch.hint = hint
	return sketch
end

------------------------------------------------------------------------
-- draw with the current settings
------------------------------------------------------------------------

local function NameColor(element)
	local mode = ns.LookColorMode(element)
	if mode == "custom" then
		return { ns.LookRGB(element) }
	elseif mode == "white" then
		return WHITE
	end
	local samples = SAMPLE_COLOR[element]
	return samples and samples[mode] or WHITE
end

-- a name line: colour, size, opacity, offset from its place above the bar
local function PlaceName(fontString, bar, element)
	local scale, alpha = ns.LookScale(element), ns.LookAlpha(element)
	local dx, dy = ns.LookOffset(element)
	local color = NameColor(element)
	fontString:SetTextColor(color[1], color[2], color[3])
	SetTextScale(fontString, scale)
	fontString:SetAlpha(alpha)
	fontString:ClearAllPoints()
	fontString:SetPoint("BOTTOM", bar, "TOP", dx, 2 + dy)
	return scale, alpha, dy, color
end

-- the small second line; nameOnly: the plate shows only the name ("auto" puts the line under it).
-- Returns the room it takes above the name.
local function PlaceSubtitle(fontString, name, element, nameScale, nameAlpha, nameOnly, color, faint)
	local scale = nameScale * SUBTITLE_SIZE * ns.LookScale(element)
	SetTextScale(fontString, scale)
	fontString:SetTextColor(color[1], color[2], color[3])
	fontString:SetAlpha(nameAlpha * ns.LookAlpha(element) * faint)
	local place = ns.LookPlace(element)
	local above = place == "above" or (place == "auto" and not nameOnly)
	local dx, dy = ns.LookOffset(element)
	fontString:ClearAllPoints()
	if above then
		fontString:SetPoint("BOTTOM", name, "TOP", dx, 1 + dy)
		return faint == 1 and math.max(0, NAME_HEIGHT * scale + 1 + dy) or 0
	end
	fontString:SetPoint("TOP", name, "BOTTOM", dx, -1 + dy)
	return 0
end

local function PlaceIcons(row, element, base, faint, point, relativeTo, relativePoint, x, y)
	local dx, dy = ns.LookOffset(element)
	SizeRow(row, base * ns.LookScale(element))
	row:SetAlpha(ns.LookAlpha(element) * faint)
	row:ClearAllPoints()
	row:SetPoint(point, relativeTo, relativePoint, x + dx, y + dy)
end

local function PlaceText(fontString, element, faint, point, relativeTo, relativePoint, x, y)
	local dx, dy = ns.LookOffset(element)
	SetTextScale(fontString, ns.LookScale(element))
	fontString:SetAlpha(ns.LookAlpha(element) * faint)
	fontString:ClearAllPoints()
	fontString:SetPoint(point, relativeTo, relativePoint, x + dx, y + dy)
end

local function DrawEnemy(parts)
	local nameScale, nameAlpha, nameDy = PlaceName(parts.enemyName, parts.bar, "enemyName")
	local guildRoom = PlaceSubtitle(parts.enemyGuild, parts.enemyName, "enemyGuild", nameScale, nameAlpha, false,
		{ ns.LookRGB("enemyGuild") }, Faint("enemy", "guild"))
	PlaceText(parts.health, "enemyHealth", Faint("enemy", "health"), "RIGHT", parts.bar, "RIGHT", -4, 0)
	PlaceText(parts.castText, "castText", Faint("enemy", "castText"), "LEFT", parts.castIcon, "RIGHT", 2, 0)
	PlaceText(parts.castTimer, "castTimer", Faint("enemy", "castTimer"), "LEFT", parts.cast, "RIGHT", 3, 0)
	parts.aggro:SetAlpha(Faint("enemy", "aggro"))
	parts.killzone:SetAlpha(Faint("enemy", "killzone"))

	-- the addon's row above the name (purge, then my debuffs), like AnchorContainer in Auras
	local rowY = 2 + NAME_HEIGHT * nameScale + 2 + nameDy + guildRoom
	PlaceIcons(parts.purge, "purge", ICON_SIZE.purge, Faint("enemy", "purge"), "BOTTOMLEFT", parts.bar, "TOPLEFT", 0, rowY)
	SizeRow(parts.mine, ICON_SIZE.mine * ns.LookScale("mine"))
	parts.mine:SetAlpha(ns.LookAlpha("mine") * Faint("enemy", "mine"))
	parts.mine:ClearAllPoints()
	parts.mine:SetPoint("BOTTOMLEFT", parts.purge, "BOTTOMRIGHT", 2, 0) -- one shared offset: follows the purge row
	PlaceIcons(parts.gameDebuffs, "gameDebuffs", ICON_SIZE.game, Faint("enemy", "gameDebuffs"), "BOTTOMLEFT", parts.mine, "BOTTOMRIGHT", 8, 0)
	PlaceIcons(parts.gameBuffs, "gameBuffs", ICON_SIZE.game, Faint("enemy", "gameBuffs"), "RIGHT", parts.bar, "LEFT", -22, 0)
	PlaceIcons(parts.gameCC, "gameCC", ICON_SIZE.game, Faint("enemy", "gameCC"), "LEFT", parts.bar, "RIGHT", 5, 0)

	local questSize = math.floor(ICON_SIZE.quest * ns.LookScale("quest") + 0.5)
	local questDx, questDy = ns.LookOffset("quest")
	parts.quest:SetSize(questSize, questSize)
	parts.quest:SetAlpha(ns.LookAlpha("quest") * Faint("enemy", "quest"))
	parts.quest:ClearAllPoints()
	parts.quest:SetPoint("RIGHT", parts.bar, "LEFT", -2 + questDx, questDy)
end

local function DrawAlly(parts)
	-- name only (the usual) or with a health bar
	local nameOnly = ns.Get("native.friendNamesOnly") ~= "never"
	parts.bar:SetAlpha(nameOnly and OFF_ALPHA or 1)
	local nameScale, nameAlpha, nameDy = PlaceName(parts.allyName, parts.bar, "friendName")
	local guildRoom = PlaceSubtitle(parts.allyGuild, parts.allyName, "friendGuild", nameScale, nameAlpha, nameOnly,
		{ ns.LookRGB("friendGuild") }, Faint("ally", "guild"))
	PlaceText(parts.health, "friendHealth", Faint("ally", "health"), "RIGHT", parts.bar, "RIGHT", -4, 0)
	PlaceIcons(parts.dispel, "dispel", ICON_SIZE.dispel, Faint("ally", "dispel"), "BOTTOMLEFT", parts.bar, "TOPLEFT",
		0, 2 + NAME_HEIGHT * nameScale + 2 + nameDy + guildRoom)
	PlaceIcons(parts.friendGame, "friendGame", ICON_SIZE.game, Faint("ally", "friendGame"), "LEFT", parts.bar, "RIGHT", 5, 0)
end

local function DrawPet(parts)
	local nameOnly = ns.Get("plates.petNamesOnly") and true or false
	parts.bar:SetAlpha(OFF_ALPHA)
	local nameScale, nameAlpha, _, color = PlaceName(parts.petName, parts.bar, "petName")
	parts.petName:SetAlpha(nameAlpha * (nameOnly and 1 or OFF_ALPHA))
	PlaceSubtitle(parts.petOwner, parts.petName, "petOwner", nameScale, nameAlpha, true, color,
		Faint("pet", "owner") * (nameOnly and 1 or OFF_ALPHA))
end

local DRAW = { enemy = DrawEnemy, ally = DrawAlly, pet = DrawPet }

local function Draw(sketch)
	DRAW[sketch.kind](sketch.parts)
	local selected = ns.GetPart and ns.GetPart(sketch.kind) or "plate"
	for _, button in ipairs(sketch.buttons) do
		button.selected:SetShown(button.part == selected)
	end
	local label = ns.PartLabel and ns.PartLabel(sketch.kind, selected) or selected
	local text = label .. ": " .. (L["HINT_" .. sketch.kind .. "_" .. selected] or "")
	if not ns.IsPartOn(sketch.kind, selected) then
		text = text .. " " .. L.PART_OFF_NOW
	end
	sketch.hint:SetText(text)
end

-- show the sketch of one kind in a settings list frame (frames are reused between the pages)
local function Show(self, kind)
	self.fpSketches = self.fpSketches or {}
	if not self.fpSketches[kind] then
		self.fpSketches[kind] = BuildKind(self, kind)
	end
	for otherKind, sketch in pairs(self.fpSketches) do
		sketch.canvas:SetShown(otherKind == kind)
	end
	for otherKind, frame in pairs(shownSketches) do
		if rawequal(frame, self) then
			shownSketches[otherKind] = nil
		end
	end
	self.fpKind = kind
	shownSketches[kind] = self
	Draw(self.fpSketches[kind])
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
		local data = initializer.data or {}
		local ok, err = pcall(Show, self, data.kind or "enemy")
		if not ok then
			geterrorhandler()("ForeverPlates sketch: " .. tostring(err))
		end
	end
	return true
end

ns.SetUpPreviewMixin() -- as early as possible (again when the pages are built, if the game's mixin wasn't there yet)

-- redraw the sketches on screen after a change
function ns.RefreshLookPreview()
	for kind, frame in pairs(shownSketches) do
		if frame.fpKind == kind and frame:IsVisible() then
			local ok, err = pcall(Draw, frame.fpSketches[kind])
			if not ok then
				geterrorhandler()("ForeverPlates sketch: " .. tostring(err))
			end
		end
	end
end

-- for tests
function ns.ShowSketch(frame, kind)
	Show(frame, kind)
	return frame.fpSketches[kind]
end
