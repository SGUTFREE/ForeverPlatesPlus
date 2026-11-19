local _, ns = ...

-- Quest marker: a small "!" to the left of the health bar on mobs and NPCs that belong to one of
-- your active quests (kill, loot or talk targets). It takes its place in the game's line of icons left
-- of the bar (after the raid mark and the elite dragon); the game's buffs move over for it (Auras).
local M = ns.RegisterModule("Quest", {})

local SIZE = 14 -- at 100% on the appearance page
local ATLASES = { "QuestNormal", "smallquestbang", "questlog-questtypeicon-quest" }
local FALLBACK_TEXTURE = "Interface\\GossipFrame\\AvailableQuestIcon"

local markers = setmetatable({}, { __mode = "k" }) -- game unit frame -> our marker frame
local refreshQueued = false

-- also used by the appearance page's sketch
function ns.PickQuestAtlas()
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
	if marker.EnableMouse then
		marker:EnableMouse(false)
	end
	local icon = marker:CreateTexture(nil, "OVERLAY")
	icon:SetAllPoints()
	local atlas = ns.PickQuestAtlas()
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

-- size, opacity and place from the appearance page
local function ApplyLook(marker, unitFrame)
	local size = math.floor(SIZE * ns.LookScale("quest") + 0.5)
	local dx, dy = ns.LookOffset("quest")
	marker:SetSize(size, size)
	marker:SetAlpha(ns.LookAlpha("quest"))
	marker:ClearAllPoints()
	local classification = unitFrame.ClassificationFrame
	if type(classification) == "table" then
		-- hidden icons of that line take no room in the game's layout, so this is right next to the bar
		-- when there is no raid mark or elite dragon
		marker:SetPoint("RIGHT", classification, "LEFT", -3 + dx, dy)
	else
		marker:SetPoint("RIGHT", unitFrame.HealthBarsContainer, "LEFT", -2 + dx, dy)
	end
end

function ns.GetQuestMarker(unitFrame)
	return markers[unitFrame]
end

local function Update(unit, unitFrame)
	local marker = markers[unitFrame]
	if not ns.Get("info.quest") or ns.LeftToGame(unit) or not IsQuestUnit(unit) then
		if marker and marker:IsShown() then
			marker:Hide()
			if ns.PlaceGameAuras then
				ns.PlaceGameAuras(unitFrame) -- the game's buffs take the marker's place
			end
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
	ApplyLook(marker, unitFrame)
	marker:Show()
	if ns.PlaceGameAuras then
		ns.PlaceGameAuras(unitFrame)
	end
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
	if marker and marker:IsShown() then
		marker:Hide()
		if ns.PlaceGameAuras then
			ns.PlaceGameAuras(unitFrame)
		end
	end
end

function M:Apply(key)
	if key and key ~= "info.quest" and not key:find("^look%.") and key ~= "plates.enemies" and key ~= "plates.friends" then
		return
	end
	UpdateAll()
end
