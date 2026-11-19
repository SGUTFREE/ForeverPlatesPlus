local _, ns = ...
local L = ns.L

-- Round button on the minimap edge (drag to move) + entry in the game's addon compartment.
local M = ns.RegisterModule("Minimap", {})

local ICON = "Interface\\Icons\\INV_Misc_Spyglass_03"
local DEFAULT_ANGLE = 200
local button

local function GetAngle()
	local angle = ns.db and ns.db.minimapAngle
	return type(angle) == "number" and angle or DEFAULT_ANGLE
end

local function UpdatePosition()
	if not button then
		return
	end
	local angle = math.rad(GetAngle())
	local radius = (Minimap:GetWidth() / 2) + 5
	button:ClearAllPoints()
	button:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * radius, math.sin(angle) * radius)
end

local function OnDragUpdate()
	local centerX, centerY = Minimap:GetCenter()
	if not centerX then
		return
	end
	local cursorX, cursorY = GetCursorPosition()
	local scale = Minimap:GetEffectiveScale()
	cursorX, cursorY = cursorX / scale, cursorY / scale
	ns.db.minimapAngle = math.deg(math.atan2(cursorY - centerY, cursorX - centerX)) % 360
	UpdatePosition()
end

local function ShowTooltip(owner)
	GameTooltip:SetOwner(owner, "ANCHOR_LEFT")
	GameTooltip:AddLine(L.ADDON)
	GameTooltip:AddLine(L.PRESET .. ": " .. (L[ns.PresetLabelKey[ns.GetActivePreset()]] or ns.GetActivePreset()), 1, 1, 1)
	if ns.KillZoneSummary then
		GameTooltip:AddLine(L.SECTION_KILLZONE .. ": " .. ns.KillZoneSummary(), 1, 1, 1)
	end
	GameTooltip:AddLine(L.MINIMAP_HINT, 0.8, 0.8, 0.8)
	GameTooltip:Show()
end

local function CreateButton()
	button = CreateFrame("Button", "ForeverPlatesPlusMinimapButton", Minimap)
	button:SetSize(31, 31)
	button:SetFrameStrata("MEDIUM")
	button:SetFrameLevel(8)
	button:RegisterForClicks("AnyUp")
	button:RegisterForDrag("LeftButton")
	button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

	local background = button:CreateTexture(nil, "BACKGROUND")
	background:SetSize(20, 20)
	background:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
	background:SetPoint("TOPLEFT", 7, -5)

	local icon = button:CreateTexture(nil, "ARTWORK")
	icon:SetSize(17, 17)
	icon:SetTexture(ICON)
	icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
	icon:SetPoint("TOPLEFT", 7, -6)

	local border = button:CreateTexture(nil, "OVERLAY")
	border:SetSize(53, 53)
	border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
	border:SetPoint("TOPLEFT")

	button:SetScript("OnClick", function()
		ns.OpenOptions()
	end)
	button:SetScript("OnDragStart", function(self)
		self:SetScript("OnUpdate", OnDragUpdate)
	end)
	button:SetScript("OnDragStop", function(self)
		self:SetScript("OnUpdate", nil)
	end)
	button:SetScript("OnEnter", ShowTooltip)
	button:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)

	UpdatePosition()
end

function M:OnLogin()
	if Minimap and not button then
		CreateButton()
	end
	self:Apply(nil)
end

function M:Apply(key)
	if key and key ~= "ui.minimap" then
		return
	end
	if button then
		button:SetShown(ns.Get("ui.minimap") and true or false)
	end
end

-- addon compartment (the addons button next to the minimap); referenced from the .toc
function ForeverPlatesPlus_OnAddonCompartmentClick()
	ns.OpenOptions()
end
