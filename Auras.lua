local _, ns = ...

-- Extra aura rows on the game's nameplates, drawn with the game's own aura containers
-- (the way Forever lets addons show auras without reading them). The row sits where the
-- game's debuff row would be: above the name, growing to the right.
local M = ns.RegisterModule("Auras", {})

local HAS_CONTAINERS = C_XMLUtil and C_XMLUtil.GetTemplateInfo
	and C_XMLUtil.GetTemplateInfo("CustomAuraContainerTemplate") and true or false

-- size = icon pixels at 100% on the appearance page (the element has the group's name)
local GROUPS = {
	-- buffs on enemies that you can remove (Dispel Magic, Purge, Spellsteal...), with a blue frame
	purge = { filter = "HELPFUL|RAID_PLAYER_DISPELLABLE", size = 20, maxKey = "auras.purgeMax", timerKey = "auras.purgeTimer",
		order = 1, frame = { 0.25, 0.55, 1, 1 } },
	-- all your debuffs on enemies (DoTs, slows, fears...)
	mine = { filter = "HARMFUL|PLAYER", size = 22, maxKey = "auras.mineMax", timerKey = "auras.mineTimer", order = 2 },
	-- debuffs you can dispel, on allies
	dispel = { filter = "HARMFUL|RAID_PLAYER_DISPELLABLE", size = 16, maxKey = "auras.dispelMax", timerKey = "auras.dispelTimer",
		order = 3 },
}

-- icon size in pixels for a group
local function GroupSize(groupKey)
	return math.floor(GROUPS[groupKey].size * ns.LookScale(groupKey) + 0.5)
end

-- the game's own aura lists on the plate: on enemies each list has its appearance element, on allies
-- one element (friendGame) covers them all. The game sets the loss-of-control frame's scale itself,
-- so only its opacity and place are ours.
local GAME_LISTS = {
	{ element = "gameBuffs", key = "BuffListFrame" },           -- left of the bar
	{ element = "gameDebuffs", key = "DebuffListFrame" },       -- above the name
	{ element = "gameCC", key = "CrowdControlListFrame" },      -- right of the bar
	{ element = "gameCC", key = "LossOfControlFrame", noScale = true },
}
local plateIsFriend = setmetatable({}, { __mode = "k" }) -- unit frame -> true on allies
local plateLeft = setmetatable({}, { __mode = "k" }) -- unit frame -> true: a friendly plate left to the game
local GROUP_ORDER = { "purge", "mine", "dispel" }
local FRAME_COLOR = { 0, 0, 0, 0.9 }

local SPACING = 2
local MAX_LINE = 150

local containers = setmetatable({}, { __mode = "k" }) -- game unit frame -> our container

------------------------------------------------------------------------
-- timer text formatter (same rules as the game's cooldown text)
------------------------------------------------------------------------

local formatter
local function GetFormatter()
	if formatter == nil then
		formatter = false
		if C_StringUtil and C_StringUtil.CreateNumericRuleFormatter then
			local ok, created = pcall(C_StringUtil.CreateNumericRuleFormatter)
			if ok and created then
				created:AddBreakpoint({ threshold = 0, step = 1, format = "%d" })
				created:AddBreakpoint({ threshold = 60, format = "%d:%02d", components = { { div = 60 }, { mod = 60 } } })
				created:AddBreakpoint({ threshold = 180, format = "%dm", components = { { div = 60, step = 1 } } })
				formatter = created
			end
		end
	end
	return formatter or nil
end

------------------------------------------------------------------------
-- buttons
------------------------------------------------------------------------

local function StyleButton(button, size, timerOn)
	button:SetSize(size, size)
	local timer = button.fpTimer
	if timer then
		timer:SetTextHeight(math.max(8, math.floor(size * 0.5 + 0.5)))
	end
	local count = button.fpCount
	if count then
		count:SetTextHeight(math.max(7, math.floor(size * 0.42 + 0.5)))
	end
	if timerOn and button.fpTimer then
		button:SetDurationText(button.fpTimer, { textFormatter = GetFormatter() })
		button.fpTimer:Show()
	else
		if button.ClearDurationText then
			button:ClearDurationText()
		end
		if button.fpTimer then
			button.fpTimer:Hide()
		end
	end
end

-- called by the game for every button it creates in one of our groups
local function InitButton(container, groupKey, button)
	if button.SetMouseMotionEnabled then
		button:SetMouseMotionEnabled(false)
	end
	if button.SetMouseClickEnabled then
		button:SetMouseClickEnabled(false)
	end

	-- thin dark frame + cropped icon, like the game's own aura icons
	local back = button:CreateTexture(nil, "BACKGROUND")
	back:SetAllPoints()
	local color = GROUPS[groupKey].frame or FRAME_COLOR
	back:SetColorTexture(color[1], color[2], color[3], color[4])

	local icon = button:CreateTexture(nil, "ARTWORK")
	icon:SetPoint("TOPLEFT", 1, -1)
	icon:SetPoint("BOTTOMRIGHT", -1, 1)
	icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	button:SetIcon(icon)

	local cooldown = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
	cooldown:SetAllPoints(icon)
	cooldown:SetReverse(true)
	cooldown:SetDrawEdge(false)
	cooldown:SetDrawBling(false)
	cooldown:SetHideCountdownNumbers(true)
	if cooldown.EnableMouse then
		cooldown:EnableMouse(false)
	end
	button:SetDurationCooldown(cooldown)

	local overlay = CreateFrame("Frame", nil, button)
	overlay:SetAllPoints()
	overlay:SetFrameLevel(cooldown:GetFrameLevel() + 1)
	if overlay.EnableMouse then
		overlay:EnableMouse(false)
	end

	local count = overlay:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
	count:SetPoint("BOTTOMRIGHT", 2, -1)
	count:SetJustifyH("RIGHT")
	button:SetApplicationCount(count)
	button.fpCount = count

	local timer = overlay:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
	timer:SetPoint("CENTER", 0, 0)
	button.fpTimer = timer

	table.insert(container.fpButtons[groupKey], button)
	StyleButton(button, GroupSize(groupKey), ns.Get(GROUPS[groupKey].timerKey))
	button:SetAlpha(ns.LookAlpha(groupKey))
end

local function GroupLayout(groupKey)
	local size = GroupSize(groupKey)
	return {
		elementSpacing = SPACING,
		lineSpacing = SPACING,
		groupSpacing = SPACING,
		groupLineSpacing = SPACING,
		elementWidth = size,
		elementHeight = size,
		layoutIndex = GROUPS[groupKey].order,
	}
end

------------------------------------------------------------------------
-- containers
------------------------------------------------------------------------

local function CreateContainer(unitFrame)
	local container = CreateFrame("AuraContainer", nil, unitFrame, "CustomAuraContainerTemplate")
	container:SetSize(1, 1)
	container.fpButtons = {}

	for _, groupKey in ipairs(GROUP_ORDER) do
		local info = GROUPS[groupKey]
		container.fpButtons[groupKey] = {}
		container:AddAuraGroup(groupKey, info.filter, {
			maxFrameCount = ns.Get(info.maxKey),
			initializeFrame = function(button)
				InitButton(container, groupKey, button)
			end,
			layout = GroupLayout(groupKey),
		})
		container:SetAuraGroupEnabled(groupKey, false)
	end

	container:SetFlowLayoutAnchorPoint("BOTTOMLEFT")
	container:SetFlowLayoutGrowthDirection(AnchorUtil.FlowDirection.Right, AnchorUtil.FlowDirection.Up)
	container:SetFlowLayoutMaximumLineSize(MAX_LINE)
	container:SetEnabled(false)
	return container
end

local function NameIsInsideBar()
	-- prefer the game's own layout options, fall back to the style CVar
	local setup = NamePlateSetupOptions
	local constants = NamePlateConstants
	if setup and setup.unitNameAnchorStyle and constants and constants.NAME_ANCHOR_STYLES then
		return setup.unitNameAnchorStyle == constants.NAME_ANCHOR_STYLES.InsideHealthBar
	end
	local style = tonumber(C_CVar.GetCVar("nameplateStyle"))
	local styles = Enum and Enum.NamePlateStyle
	return style == (styles and styles.Modern or 0) or style == (styles and styles.Block or 2)
end

-- for the settings sketch
ns.GameNameInsideBar = NameIsInsideBar

-- Anchored to the health bar, not to the name: the name's text can be secret, the bar's size never is.
-- The offset reproduces where the game puts its own debuff row (just above the name).
local function AnchorContainer(container, unitFrame)
	local padding = tonumber(C_CVar.GetCVar("nameplateDebuffPadding")) or 2
	local offset = padding
	local place = ns.GetNamePlace and ns.GetNamePlace(unitFrame)
	local nameInside = place == "inside" or (place == nil and NameIsInsideBar())
	if not nameInside then
		local setup = NamePlateSetupOptions
		local nameHeight = ((setup and setup.healthBarFontHeight) or 14) * (ns.GetNameScale and ns.GetNameScale(unitFrame) or 1)
		local nameSpacing = (setup and setup.healthBarToNameAboveSpacing) or 2
		-- the row follows the name when it is moved up or down
		offset = offset + nameHeight + nameSpacing + (ns.GetNameOffsetY and ns.GetNameOffsetY(unitFrame) or 0)
	end
	-- a guild line above the name (HealthText) takes room as well
	offset = offset + (ns.GetSubtitleHeight and ns.GetSubtitleHeight(unitFrame) or 0)
	-- the enemy's two rows share one offset; the ally row has its own
	local dx, dy = ns.LookOffset(plateIsFriend[unitFrame] and "dispel" or "mine")
	container:ClearAllPoints()
	container:SetPoint("BOTTOMLEFT", unitFrame.HealthBarsContainer, "TOPLEFT", dx, offset + dy)
end

-- Left of the bar the game lines up its icons (raid mark, elite dragon, then its buffs). Our quest
-- marker joins that line: while it is shown the game's buffs move left of it, otherwise they keep the
-- game's own place right next to the others, so nothing leaves a gap.
local buffsMoved = setmetatable({}, { __mode = "k" }) -- unit frame -> true while its buffs follow our marker

local function AnchorGameBuffs(unitFrame, buffs)
	local marker = ns.GetQuestMarker and ns.GetQuestMarker(unitFrame)
	local classification = unitFrame.ClassificationFrame
	if marker and marker:IsShown() then
		buffs:ClearAllPoints()
		buffs:SetPoint("RIGHT", marker, "LEFT", -3, 0)
		buffsMoved[unitFrame] = true
	elseif buffsMoved[unitFrame] then
		buffs:ClearAllPoints()
		if type(classification) == "table" then
			buffs:SetPoint("RIGHT", classification, "LEFT", -5, 0) -- where the game's own layout puts them
		else
			buffs:SetPoint("RIGHT", unitFrame.HealthBarsContainer, "LEFT", -5, 0)
		end
		buffsMoved[unitFrame] = nil
	end
end

-- size, opacity and place of the game's own aura lists
local function ApplyGameLook(unitFrame)
	local auras = unitFrame.AurasFrame
	if type(auras) ~= "table" then
		return
	end
	if type(auras.BuffListFrame) == "table" and auras.BuffListFrame.SetPoint then
		AnchorGameBuffs(unitFrame, auras.BuffListFrame)
	end
	for _, list in ipairs(GAME_LISTS) do
		local frame = auras[list.key]
		if type(frame) == "table" and frame.SetAlpha then
			local element = plateIsFriend[unitFrame] and "friendGame" or list.element
			local left = plateLeft[unitFrame]
			local scale = left and 1 or ns.LookScale(element)
			local dx, dy = 0, 0
			if not left then
				dx, dy = ns.LookOffset(element)
			end
			if not list.noScale then
				ns.ApplyScale(frame, scale)
			else
				scale = 1
			end
			ns.ApplyAlpha(frame, left and 1 or ns.LookAlpha(element))
			-- a scaled frame's offsets count in its own scale: divide, so a pixel stays a pixel
			ns.PlaceRegion(frame, dx / scale, dy / scale)
		end
	end
end

function ns.ReanchorAuras(unitFrame)
	local container = containers[unitFrame]
	if container then
		AnchorContainer(container, unitFrame)
	end
end

-- which rows this unit gets: { purge = bool, mine = bool, dispel = bool }
local function WantedGroups(unit)
	local kind = ns.GetUnitKind(unit)
	local enemy = kind == "enemyNpc" or kind == "enemyPlayer"
	return {
		purge = (ns.Get("auras.purge") and enemy) and true or false,
		mine = (ns.Get("auras.mine") and (kind == "enemyNpc" or (kind == "enemyPlayer" and ns.Get("auras.minePlayers")))) and true or false,
		dispel = (ns.Get("auras.dispel") and kind == "friendlyPlayer") and true or false,
	}
end

local function Disable(container)
	container:SetEnabled(false)
	container:Hide()
end

function M:OnPlateAdded(unit, unitFrame)
	local kind = ns.GetUnitKind(unit)
	plateIsFriend[unitFrame] = (kind == "friendlyPlayer" or kind == "friendlyNpc") or nil
	plateLeft[unitFrame] = ns.LeftToGame(unit) or nil
	ApplyGameLook(unitFrame)
	if not HAS_CONTAINERS or not unitFrame.HealthBarsContainer then
		return
	end
	local wanted = WantedGroups(unit)
	if plateLeft[unitFrame] then
		wanted = {}
	end
	local container = containers[unitFrame]

	if not (wanted.purge or wanted.mine or wanted.dispel) then
		if container then
			Disable(container)
		end
		return
	end

	if not container then
		container = CreateContainer(unitFrame)
		containers[unitFrame] = container
	end

	for _, groupKey in ipairs(GROUP_ORDER) do
		container:SetAuraGroupEnabled(groupKey, wanted[groupKey])
	end
	AnchorContainer(container, unitFrame)
	container:SetEnabled(true)
	container:SetUnit(unit)
	container:Show()
	container:UpdateAllAuras() -- the same token (nameplate3) can come back for a different unit
end

-- the quest marker appeared or went away (Quest)
function ns.PlaceGameAuras(unitFrame)
	ApplyGameLook(unitFrame)
end

-- the game re-anchors its lists (and the name) on a new layout
function M:OnPlateLayout(_, unitFrame)
	ApplyGameLook(unitFrame)
	ns.ReanchorAuras(unitFrame)
end

function M:OnPlateRemoved(_, unitFrame)
	local container = containers[unitFrame]
	if container then
		Disable(container)
	end
end

function M:Apply(key)
	if key and not key:find("^auras%.") and not key:find("^look%.") and key ~= "plates.friends" and key ~= "plates.petNamesOnly" then
		return
	end
	if not HAS_CONTAINERS then
		ns.ForEachPlate(function(_, unitFrame)
			ApplyGameLook(unitFrame)
		end)
		return
	end
	for _, container in pairs(containers) do
		for _, groupKey in ipairs(GROUP_ORDER) do
			local info = GROUPS[groupKey]
			container:SetAuraGroupMaxFrameCount(groupKey, ns.Get(info.maxKey))
			container:SetAuraGroupLayout(groupKey, GroupLayout(groupKey))
			local size, alpha, timerOn = GroupSize(groupKey), ns.LookAlpha(groupKey), ns.Get(info.timerKey)
			for _, button in ipairs(container.fpButtons[groupKey]) do
				StyleButton(button, size, timerOn)
				button:SetAlpha(alpha)
			end
		end
	end
	ns.ForEachPlate(function(unit, unitFrame)
		M:OnPlateAdded(unit, unitFrame)
	end)
end
