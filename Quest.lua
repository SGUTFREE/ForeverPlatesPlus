local _, ns = ...

-- Quest marker: a small "!" to the left of the health bar on mobs and NPCs that belong to one of
-- your active quests (kill, loot or talk targets).
local M = ns.RegisterModule("Quest", {})

local SIZE = 14
local ATLASES = { "QuestNormal", "smallquestbang", "questlog-questtypeicon-quest" }
local FALLBACK_TEXTURE = "Interface\\GossipFrame\\AvailableQuestIcon"

local markers = setmetatable({}, { __mode = "k" }) -- game unit frame -> our marker frame
local refreshQueued = false

local function PickAtlas()
	if not (C_Texture and C_Texture.GetAtlasInfo) then
		return nil
	end
	for _, atlas in ipairs(ATLASES) do
		if C_Texture.GetAtlasInfo(atlas) then
			return atlas
		end
	end
end

local function CreateMarker(unitFrame)
	local container = unitFrame.HealthBarsContainer
	if not container then
		return nil
	end
	local marker = CreateFrame("Frame", nil, unitFrame)
	marker:SetSize(SIZE, SIZE)
	marker:SetPoint("RIGHT", container, "LEFT", -2, 0)
	if marker.EnableMouse then
		marker:EnableMouse(false)
	end
	local icon = marker:CreateTexture(nil, "OVERLAY")
	icon:SetAllPoints()
	local atlas = PickAtlas()
	if atlas then
		icon:SetAtlas(atlas)
	else
		icon:SetTexture(FALLBACK_TEXTURE)
	end
	marker:Hide()
	return marker
end

local function IsQuestUnit(unit)
	if not (C_QuestLog and C_QuestLog.UnitIsRelatedToActiveQuest) then
		return false
	end
	if ns.SafeBool(UnitIsPlayer(unit)) ~= false then
		return false -- players never are (and unknown stays unmarked)
	end
	local ok, related = pcall(C_QuestLog.UnitIsRelatedToActiveQuest, unit)
	return ok and ns.SafeBool(related) == true
end

local function Update(unit, unitFrame)
	local marker = markers[unitFrame]
	if not ns.Get("info.quest") or not IsQuestUnit(unit) then
		if marker then
			marker:Hide()
		end
		return
	end
	if not marker then
		marker = CreateMarker(unitFrame)
		if not marker then
			return
		end
		markers[unitFrame] = marker
	end
	marker:Show()
end

local function UpdateAll()
	ns.ForEachPlate(Update)
end

-- quest log events come in bursts: refresh once
local function QueueRefresh()
	if refreshQueued then
		return
	end
	refreshQueued = true
	C_Timer.After(0.2, function()
		refreshQueued = false
		UpdateAll()
	end)
end

function M:OnInit()
	local events = CreateFrame("Frame")
	for _, event in ipairs({ "QUEST_LOG_UPDATE", "QUEST_ACCEPTED", "QUEST_REMOVED", "QUEST_TURNED_IN" }) do
		pcall(events.RegisterEvent, events, event)
	end
	events:SetScript("OnEvent", QueueRefresh)
end

function M:OnPlateAdded(unit, unitFrame)
	Update(unit, unitFrame)
end

function M:OnPlateRemoved(_, unitFrame)
	local marker = markers[unitFrame]
	if marker then
		marker:Hide()
	end
end

function M:Apply(key)
	if key and key ~= "info.quest" then
		return
	end
	UpdateAll()
end
