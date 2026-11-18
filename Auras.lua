local _, ns = ...

-- Extra aura rows on the game's nameplates, drawn with the game's own aura containers
-- (the way Forever lets addons show auras without reading them). The row sits where the
-- game's debuff row would be: above the name, growing to the right.
local M = ns.RegisterModule("Auras", {})

local HAS_CONTAINERS = C_XMLUtil and C_XMLUtil.GetTemplateInfo
	and C_XMLUtil.GetTemplateInfo("CustomAuraContainerTemplate") and true or false

local GROUPS = {
	-- buffs on enemies that you can remove (Dispel Magic, Purge, Spellsteal...), with a blue frame
	purge = { filter = "HELPFUL|RAID_PLAYER_DISPELLABLE", sizeKey = "auras.purgeSize", maxKey = "auras.purgeMax", order = 1,
		frame = { 0.25, 0.55, 1, 1 } },
	-- all your debuffs on enemies (DoTs, slows, fears...)
	mine = { filter = "HARMFUL|PLAYER", sizeKey = "auras.mineSize", maxKey = "auras.mineMax", order = 2 },
	-- debuffs you can dispel, on allies
	dispel = { filter = "HARMFUL|RAID_PLAYER_DISPELLABLE", sizeKey = "auras.dispelSize", maxKey = "auras.dispelMax", order = 3 },
}
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

local function StyleButton(button, size)
	button:SetSize(size, size)
	local timer = button.fpTimer
	if timer then
		timer:SetTextHeight(math.max(8, math.floor(size * 0.5 + 0.5)))
	end
	local count = button.fpCount
	if count then
		count:SetTextHeight(math.max(7, math.floor(size * 0.42 + 0.5)))
	end
	if ns.Get("auras.timer") and button.fpTimer then
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
	StyleButton(button, ns.Get(GROUPS[groupKey].sizeKey))
end

local function GroupLayout(groupKey)
	local size = ns.Get(GROUPS[groupKey].sizeKey)
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

-- Anchored to the health bar, not to the name: the name's text can be secret, the bar's size never is.
-- The offset reproduces where the game puts its own debuff row (just above the name).
local function AnchorContainer(container, unitFrame)
	local padding = tonumber(C_CVar.GetCVar("nameplateDebuffPadding")) or 2
	local offset = padding
	if not NameIsInsideBar() then
		local setup = NamePlateSetupOptions
		local nameHeight = ((setup and setup.healthBarFontHeight) or 14) * (ns.GetNameScale and ns.GetNameScale() or 1)
		local nameSpacing = (setup and setup.healthBarToNameAboveSpacing) or 2
		offset = offset + nameHeight + nameSpacing
	end
	-- a guild line above the name (HealthText) takes room as well
	offset = offset + (ns.GetSubtitleHeight and ns.GetSubtitleHeight(unitFrame) or 0)
	container:ClearAllPoints()
	container:SetPoint("BOTTOMLEFT", unitFrame.HealthBarsContainer, "TOPLEFT", 0, offset)
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
	if not HAS_CONTAINERS or not unitFrame.HealthBarsContainer then
		return
	end
	local wanted = WantedGroups(unit)
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

function M:OnPlateRemoved(_, unitFrame)
	local container = containers[unitFrame]
	if container then
		Disable(container)
	end
end

function M:Apply(key)
	if not HAS_CONTAINERS or (key and not key:find("^auras%.") and key ~= "plates.nameScale") then
		return
	end
	for _, container in pairs(containers) do
		for _, groupKey in ipairs(GROUP_ORDER) do
			local info = GROUPS[groupKey]
			container:SetAuraGroupMaxFrameCount(groupKey, ns.Get(info.maxKey))
			container:SetAuraGroupLayout(groupKey, GroupLayout(groupKey))
			local size = ns.Get(info.sizeKey)
			for _, button in ipairs(container.fpButtons[groupKey]) do
				StyleButton(button, size)
			end
		end
	end
	ns.ForEachPlate(function(unit, unitFrame)
		M:OnPlateAdded(unit, unitFrame)
	end)
end
