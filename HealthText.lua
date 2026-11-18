local _, ns = ...
local L = ns.L

-- Health numbers and friendly names.
--
-- Number format: the game writes health with its own abbreviation. After each game update of the text
-- the number is written again in the chosen format (short with N decimals, full, or the game's own).
-- Health may be secret: the game's abbreviation functions accept secret numbers, nothing is compared here.
--
-- Numbers: the game's health text option is one switch for every nameplate. Per plate, the number and
-- the percent are hidden by alpha (the game keeps managing the text as usual): on allies (unless turned
-- on), and on enemies by state: normally / on mouseover / as the target, each with its own choice.
-- Hidden texts are also shrunk to (almost) no width, so in styles with the name inside the bar they
-- don't take room.
--
-- Names: the game pins the name between two points (bar edge to bar edge, or to the level frame), so a
-- long name is cut with "...". The name is re-pinned by one point at the same place (same side, or the
-- same centre for centred names), so it is written in full. The game's own points are kept and put
-- back when the frame goes to another unit; after every game re-layout (UpdateAnchors) they are read again.
local M = ns.RegisterModule("HealthText", {})

local hidden = setmetatable({}, { __mode = "k" }) -- game unit frame -> true while all its numbers are hidden
local savedWordWrap = setmetatable({}, { __mode = "k" }) -- font string we hid -> its word wrap before

local function HideText(text)
	if savedWordWrap[text] ~= nil then
		return -- already hidden; the game never touches alpha or width
	end
	savedWordWrap[text] = text:CanWordWrap() and true or false
	text:SetAlpha(0)
	text:SetWordWrap(false)
	text:SetWidth(1)
end

local function RestoreText(text)
	if savedWordWrap[text] == nil then
		return -- not ours
	end
	text:SetAlpha(1)
	text:SetWidth(0) -- 0 = size to the text again (the game never sets a width on these)
	text:SetWordWrap(savedWordWrap[text])
	savedWordWrap[text] = nil
end

local function SetTextShown(text, shown)
	if text then
		if shown then
			RestoreText(text)
		else
			HideText(text)
		end
	end
end

-- mode: "none" | "value" | "percent" | "both"
local function ShowNumbers(unitFrame, mode)
	local healthBar = unitFrame.HealthBarsContainer and unitFrame.HealthBarsContainer.healthBar
	if not healthBar then
		return
	end
	local showValue = mode == "value" or mode == "both"
	local showPercent = mode == "percent" or mode == "both"
	-- the game's text bar: with both on, RightText = number and LeftText = percent;
	-- with only one on, TextString holds it
	local single
	if healthBar.showNumeric and not healthBar.showPercentage then
		single = showValue
	elseif healthBar.showPercentage and not healthBar.showNumeric then
		single = showPercent
	else
		single = showValue or showPercent
	end
	SetTextShown(healthBar.RightText, showValue)
	SetTextShown(healthBar.LeftText, showPercent)
	SetTextShown(healthBar.TextString or healthBar.Text, single)
	hidden[unitFrame] = (not showValue and not showPercent) or nil
end

------------------------------------------------------------------------
-- full names
------------------------------------------------------------------------

local nameState = setmetatable({}, { __mode = "k" }) -- unit frame -> { points = game's points, want = bool, ours = bool }
local hooked = setmetatable({}, { __mode = "k" })

-- vertical part of a left-side point: BOTTOMLEFT -> BOTTOM etc.
local VERTICAL = { BOTTOMLEFT = "BOTTOM", LEFT = "CENTER", TOPLEFT = "TOP" }

local function CapturePoints(name)
	local ok, count = pcall(name.GetNumPoints, name)
	if not ok or type(count) ~= "number" or ns.IsSecret(count) or count == 0 then
		return nil
	end
	local points = {}
	for i = 1, count do
		local okPoint, point, relativeTo, relativePoint, x, y = pcall(name.GetPoint, name, i)
		if not okPoint or type(point) ~= "string" or ns.IsSecret(x) or ns.IsSecret(y) then
			return nil
		end
		points[i] = { point, relativeTo, relativePoint or point, x or 0, y or 0 }
	end
	return points
end

local function FindPoint(points, side)
	for _, p in ipairs(points) do
		if p[1]:find(side) then
			return p
		end
	end
end

local function IsHealthText(unitFrame, region)
	local healthBar = unitFrame.HealthBarsContainer.healthBar
	return healthBar ~= nil and (rawequal(region, healthBar.Text) or rawequal(region, healthBar.LeftText) or rawequal(region, healthBar.RightText))
end

-- where the game's right edge of the name was, as an offset from the right edge of the health bar container
local function RightOffset(unitFrame, p)
	local container = unitFrame.HealthBarsContainer
	if rawequal(p[2], container) and p[3]:find("RIGHT") then
		return p[4]
	end
	local level = unitFrame.PlayerLevelDiffFrame
	if level and rawequal(p[2], level) and p[3]:find("RIGHT") then
		-- the level frame sits right of the bar; the game reserves its width plus the gap the same way
		local _, _, _, levelX = level:GetPoint()
		local width = level:GetWidth()
		if ns.IsSecret(levelX) or ns.IsSecret(width) then
			return nil
		end
		return (width or 0) + math.abs(levelX or 0) + p[4]
	end
	if IsHealthText(unitFrame, p[2]) and hidden[unitFrame] then
		return -4 -- hidden numbers are collapsed at the bar's right edge
	end
	return nil
end

local function PutBackGamePoints(unitFrame, state)
	local name = unitFrame.name
	name:ClearAllPoints()
	for _, p in ipairs(state.points) do
		name:SetPoint(p[1], p[2], p[3], p[4], p[5])
	end
	state.ours = false
end

-- one point that keeps the name where the game put it but lets it grow; nil = keep the game's points
local function SinglePoint(unitFrame, points)
	local container = unitFrame.HealthBarsContainer
	local left, right = FindPoint(points, "LEFT"), FindPoint(points, "RIGHT")
	-- one point (or a layout we don't know): the name is already free
	if not left or not right or not rawequal(left[2], container) then
		return nil
	end
	-- never let the name run over numbers that are shown
	if IsHealthText(unitFrame, right[2]) and not hidden[unitFrame] then
		return nil
	end

	local justify = unitFrame.name:GetJustifyH()
	if justify == "LEFT" then
		return left[1], left[3], left[4], left[5]
	end
	local rightOffset = RightOffset(unitFrame, right)
	local vertical, relativeVertical = VERTICAL[left[1]], VERTICAL[left[3]]
	if not rightOffset or not vertical or not relativeVertical then
		return nil
	end
	if justify == "RIGHT" then
		return vertical == "CENTER" and "RIGHT" or vertical .. "RIGHT",
			relativeVertical == "CENTER" and "RIGHT" or relativeVertical .. "RIGHT",
			rightOffset, left[5]
	end
	-- centred between the game's two edges
	return vertical, relativeVertical, (left[4] + rightOffset) / 2, left[5]
end

local function ApplyName(unitFrame)
	local state = nameState[unitFrame]
	if not state or not state.points then
		return
	end
	local point, relativePoint, x, y
	if state.want then
		point, relativePoint, x, y = SinglePoint(unitFrame, state.points)
	end
	if not point then
		if state.ours then
			PutBackGamePoints(unitFrame, state)
		end
		return
	end
	local name = unitFrame.name
	name:ClearAllPoints()
	name:SetPoint(point, unitFrame.HealthBarsContainer, relativePoint, x, y)
	name:SetWidth(0) -- no fixed width either: the name takes the width of its text
	state.ours = true
end

-- the game just laid the plate out again: its points replace ours
local function OnGameLayout(unitFrame)
	local state = nameState[unitFrame]
	if not state then
		return
	end
	state.ours = false
	state.points = CapturePoints(unitFrame.name)
	ApplyName(unitFrame)
	if ns.OnNameLayout then
		ns.OnNameLayout(unitFrame) -- the subtitle may have to move (name only <-> with a bar)
	end
end

local function SetFullName(unitFrame, want)
	if not unitFrame.name or not unitFrame.HealthBarsContainer then
		return
	end
	local state = nameState[unitFrame]
	if not state then
		if not want then
			return
		end
		state = {}
		nameState[unitFrame] = state
	end
	if want and not hooked[unitFrame] and type(unitFrame.UpdateAnchors) == "function" then
		hooked[unitFrame] = true
		hooksecurefunc(unitFrame, "UpdateAnchors", OnGameLayout)
	end
	if not state.ours then
		state.points = CapturePoints(unitFrame.name)
	end
	state.want = want
	ApplyName(unitFrame)
end

------------------------------------------------------------------------
-- health number format
------------------------------------------------------------------------

local hookedBars = setmetatable({}, { __mode = "k" })
local shortOptions -- cached abbreviation options for the current decimals

local function BuildShortOptions()
	local decimals = math.floor((tonumber(ns.Get("health.decimals")) or 1) + 0.5)
	decimals = math.max(0, math.min(2, decimals))
	local fraction = 10 ^ decimals
	-- largest first; significand x fraction = the named order (thousands, millions, ...)
	local data = {}
	for _, step in ipairs({ { 1e9, L.ABBR_BILLION }, { 1e6, L.ABBR_MILLION }, { 1e3, L.ABBR_THOUSAND } }) do
		table.insert(data, {
			breakpoint = step[1],
			abbreviation = step[2],
			significandDivisor = step[1] / fraction,
			fractionDivisor = fraction,
			abbreviationIsGlobal = false,
		})
	end
	if CreateAbbreviateConfig then
		local ok, config = pcall(CreateAbbreviateConfig, data)
		if ok and config then
			return { config = config }
		end
	end
	return { breakpointData = data }
end

local function FormatHealth(value)
	local format = ns.Get("health.format")
	if format == "full" then
		return BreakUpLargeNumbers(value)
	elseif format == "short" then
		shortOptions = shortOptions or BuildShortOptions()
		return AbbreviateNumbers(value, shortOptions)
	end
	return AbbreviateLargeNumbers(value) -- what the game itself uses on nameplates
end

-- write the number into the font string the game used for it (only if the game shows it)
local function RenderHealth(healthBar, value, evenForGameFormat)
	-- value may be secret: never compared, only handed to the game's formatters
	if ns.Get("health.format") == "game" and not evenForGameFormat then
		return
	end
	local target
	if healthBar.showNumeric and healthBar.showPercentage then
		target = healthBar.RightText -- both: number here, percent next to it
	elseif healthBar.showNumeric then
		target = healthBar.TextString
	end
	if target and target:IsShown() then
		local ok, text = pcall(FormatHealth, value)
		if ok then
			target:SetText(text)
		end
	end
end

local barOwner = setmetatable({}, { __mode = "k" }) -- health bar -> its unit frame
local modeByFrame = setmetatable({}, { __mode = "k" }) -- unit frame -> numbers mode in effect

local function OnGameHealthText(healthBar, _, value)
	RenderHealth(healthBar, value)
	-- the game may have switched which text it uses (option changed): keep the plate's choice
	local unitFrame = barOwner[healthBar]
	local mode = unitFrame and modeByFrame[unitFrame]
	if mode then
		ShowNumbers(unitFrame, mode)
	end
end

local function HookHealthBar(unitFrame)
	local healthBar = unitFrame.HealthBarsContainer and unitFrame.HealthBarsContainer.healthBar
	if healthBar and not hookedBars[healthBar] and type(healthBar.UpdateTextStringWithValues) == "function" then
		hookedBars[healthBar] = true
		barOwner[healthBar] = unitFrame
		hooksecurefunc(healthBar, "UpdateTextStringWithValues", OnGameHealthText)
	end
	return healthBar
end

------------------------------------------------------------------------

local frameUnit = setmetatable({}, { __mode = "k" }) -- unit frame -> its unit token
local dimmed = setmetatable({}, { __mode = "k" }) -- unit frame -> true while its name is made transparent by us

------------------------------------------------------------------------
-- allies' pets: name only
------------------------------------------------------------------------

-- The game's "name only" option covers ally players, not their pets. For pets the same look is made
-- here: the plate's other parts are made invisible (the game never sets their alpha) and the name is
-- coloured by the owner's class (or white). Not in dungeons and raids, where the game doesn't let
-- addons touch ally plates.
local PET_HIDDEN_PARTS = { "HealthBarsContainer", "CastBarsContainer", "AurasFrame", "PlayerLevelDiffFrame", "ClassificationFrame" }
local petMode = setmetatable({}, { __mode = "k" }) -- unit frame -> { color = { r, g, b }, owner = name|nil } while shown as a name only
local WHITE = { 1, 1, 1 }

-- the pet's tooltip lines after its name ("Pet of X", level...); secret lines are skipped
local function TooltipLines(unit)
	local lines = {}
	if not (C_TooltipInfo and C_TooltipInfo.GetUnit) then
		return lines
	end
	local ok, data = pcall(C_TooltipInfo.GetUnit, unit)
	if not ok or type(data) ~= "table" or type(data.lines) ~= "table" then
		return lines
	end
	for i = 2, #data.lines do
		local line = data.lines[i]
		local text = type(line) == "table" and line.leftText
		if not ns.IsSecret(text) and type(text) ~= "string" and type(line) == "table" and type(line.args) == "table" then
			-- older tooltip data: the text sits in the line's args
			for _, arg in ipairs(line.args) do
				if type(arg) == "table" and arg.field == "leftText" then
					text = arg.stringVal
				end
			end
		end
		if not ns.IsSecret(text) and type(text) == "string" and text ~= "" then
			table.insert(lines, text)
		end
	end
	return lines
end

-- players the owner can be: you, your group, allies whose plates are shown
local function OwnerCandidates()
	local candidates = {}
	local function Add(unit)
		if not UnitExists(unit) then
			return
		end
		local name = UnitName(unit)
		local _, class = UnitClass(unit)
		if type(name) == "string" and not ns.IsSecret(name) and not ns.IsSecret(class) and class then
			table.insert(candidates, { name = name, class = class })
		end
	end
	Add("player")
	for i = 1, 4 do
		Add("party" .. i)
	end
	if IsInRaid and IsInRaid() then
		for i = 1, 40 do
			Add("raid" .. i)
		end
	end
	for unit in pairs(ns.activePlates) do
		if ns.SafeBool(UnitIsPlayer(unit)) and ns.GetUnitKind(unit) == "friendlyPlayer" then
			Add(unit)
		end
	end
	return candidates
end

-- a name without its last letter: Russian tooltips decline names ("Питомец Артроза" for Артроз)
local function Stem(name)
	local letters = select(2, name:gsub("[^\128-\191]", ""))
	if letters < 4 then
		return nil
	end
	return name:match("^(.*)[%z\1-\127\194-\244][\128-\191]*$")
end

-- the pet's owner (class, name), found by the owner's name in the pet's tooltip
local function PetOwner(unit)
	local lines = TooltipLines(unit)
	if #lines == 0 then
		return nil
	end
	local candidates = OwnerCandidates()
	for _, text in ipairs(lines) do
		for _, candidate in ipairs(candidates) do
			if text:find(candidate.name, 1, true) then
				return candidate.class, candidate.name
			end
		end
	end
	for _, text in ipairs(lines) do
		for _, candidate in ipairs(candidates) do
			local stem = Stem(candidate.name)
			if stem and text:find(stem, 1, true) then
				return candidate.class, candidate.name
			end
		end
	end
end

-- for /fpl debug
function ns.DebugPet(unit, unitFrame)
	if not unit then
		return "pet=?"
	end
	local info = petMode[unitFrame]
	local lines = TooltipLines(unit)
	return ("pet=%s owner=%s tooltip=%d [%s]"):format(info == nil and "no" or (info.color == WHITE and "white" or "coloured"),
		tostring((PetOwner(unit))), #lines, lines[1] or "")
end

local function ClassColor(class)
	local color = class and ((C_ClassColor and C_ClassColor.GetClassColor and C_ClassColor.GetClassColor(class))
		or (RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]))
	if color and color.r then
		return { color.r, color.g, color.b }
	end
end

-- { color = { r, g, b }, owner = name|nil } for a pet shown as a name only
local function PetInfo(unit)
	local class, owner = PetOwner(unit)
	local color = ns.Get("plates.petClassColor") and ClassColor(class) or WHITE
	return { color = color, owner = owner }
end

local function IsAllyPet(unit)
	return ns.SafeBool(UnitIsOtherPlayersPet and UnitIsOtherPlayersPet(unit)) == true
		or ns.SafeBool(UnitIsUnit(unit, "pet")) == true
		or ns.SafeBool(UnitIsMinion and UnitIsMinion(unit)) == true
end

-- info: { color, owner } for the name, or nil to show the plate normally again
local function SetPetNameOnly(unitFrame, info)
	if info then
		local color = info.color
		for _, key in ipairs(PET_HIDDEN_PARTS) do
			local part = unitFrame[key]
			if type(part) == "table" and part.SetAlpha then
				part:SetAlpha(0)
			end
		end
		if unitFrame.name then
			unitFrame.name:SetVertexColor(color[1], color[2], color[3])
		end
		petMode[unitFrame] = info
	elseif petMode[unitFrame] then
		for _, key in ipairs(PET_HIDDEN_PARTS) do
			local part = unitFrame[key]
			if type(part) == "table" and part.SetAlpha then
				part:SetAlpha(1)
			end
		end
		petMode[unitFrame] = nil -- the name colour comes back with the game's next name update
	end
end

-- the game recolours names on its own updates: keep our pet name colour
if type(CompactUnitFrame_UpdateName) == "function" then
	hooksecurefunc("CompactUnitFrame_UpdateName", function(frame)
		local info = petMode[frame]
		if info and frame.name then
			frame.name:SetVertexColor(info.color[1], info.color[2], info.color[3])
		end
	end)
end

-- alpha: 0..1, or nil for the game's own (the game never changes the name's alpha itself)
local function SetNameAlpha(unitFrame, alpha)
	local name = unitFrame.name
	if not name then
		return
	end
	if alpha then
		name:SetAlpha(alpha)
		dimmed[unitFrame] = true
	elseif dimmed[unitFrame] then
		name:SetAlpha(1)
		dimmed[unitFrame] = nil
	end
end

-- name size: the game sets the font height itself (and never the text scale), so a scale on top stays
local scaled = setmetatable({}, { __mode = "k" }) -- unit frame -> scale we set
local function SetNameScale(unitFrame, scale)
	local name = unitFrame.name
	if not name or not name.SetTextScale then
		return
	end
	if scale then
		if scaled[unitFrame] ~= scale then
			name:SetTextScale(scale)
			scaled[unitFrame] = scale
		end
	elseif scaled[unitFrame] then
		name:SetTextScale(1)
		scaled[unitFrame] = nil
	end
end

function ns.GetNameScale()
	local percent = tonumber(ns.Get("plates.nameScale")) or 100
	return math.max(50, math.min(200, percent)) / 100
end

------------------------------------------------------------------------
-- subtitle: a small second line with the pet's owner or the player's guild
------------------------------------------------------------------------

-- Under the name when the plate shows only the name; above it when there is a health bar under the
-- name (the extra aura row then moves up, see Auras).
local SUBTITLE_SIZE = 0.85 -- of the name's font size
local SUBTITLE_GAP = 1
local GUILD_COLOR = { 0.85, 0.85, 0.85 }
local subtitles = setmetatable({}, { __mode = "k" }) -- unit frame -> our font string
local subtitleAbove = setmetatable({}, { __mode = "k" }) -- unit frame -> height of a subtitle shown above the name

local function ShowsOnlyName(unitFrame)
	return unitFrame.showOnlyName == true or petMode[unitFrame] ~= nil
end

local function SetSubtitle(unitFrame, text, color, alpha)
	local line = subtitles[unitFrame]
	local name = unitFrame.name
	if not text or not name then
		if line then
			line:Hide()
		end
		if subtitleAbove[unitFrame] then
			subtitleAbove[unitFrame] = nil
			if ns.ReanchorAuras then
				ns.ReanchorAuras(unitFrame)
			end
		end
		return
	end
	if not line then
		line = unitFrame:CreateFontString(nil, "OVERLAY")
		subtitles[unitFrame] = line
	end
	local font, size, flags = name:GetFont()
	size = (tonumber(size) or 12) * SUBTITLE_SIZE
	if font then
		line:SetFont(font, size, flags)
	else
		line:SetFontObject("SystemFont_NamePlate_Outlined")
	end
	if line.SetTextScale then
		line:SetTextScale(ns.GetNameScale())
	end
	line:SetText(text)
	line:SetTextColor(color[1], color[2], color[3])
	line:SetAlpha(alpha or 1)
	line:ClearAllPoints()
	local above = not ShowsOnlyName(unitFrame)
	if above then
		line:SetPoint("BOTTOM", name, "TOP", 0, SUBTITLE_GAP)
	else
		line:SetPoint("TOP", name, "BOTTOM", 0, -SUBTITLE_GAP)
	end
	line:Show()
	local height = above and (size * ns.GetNameScale() + SUBTITLE_GAP) or nil
	if subtitleAbove[unitFrame] ~= height then
		subtitleAbove[unitFrame] = height
		if ns.ReanchorAuras then
			ns.ReanchorAuras(unitFrame)
		end
	end
end

-- the subtitle font string of a plate (for /fpl debug and tests)
function ns.GetSubtitleLine(unitFrame)
	return subtitles[unitFrame]
end

-- extra room the aura row has to leave above the name
function ns.GetSubtitleHeight(unitFrame)
	return subtitleAbove[unitFrame] or 0
end

local function GuildTag(unit, kind)
	local mode = ns.Get("plates.guild")
	if mode ~= "allies" and mode ~= "all" then
		return nil
	end
	if kind ~= "friendlyPlayer" and not (mode == "all" and kind == "enemyPlayer") then
		return nil
	end
	if not GetGuildInfo then
		return nil
	end
	local ok, guild = pcall(GetGuildInfo, unit)
	if not ok or ns.IsSecret(guild) or type(guild) ~= "string" or guild == "" then
		return nil
	end
	return "<" .. guild .. ">"
end

local function PlateFrame(token)
	local plate = C_NamePlate.GetNamePlateForUnit(token)
	return plate and plate.UnitFrame
end

local function NumbersMode(unit, unitFrame)
	local kind = ns.GetUnitKind(unit)
	if kind == "friendlyPlayer" or kind == "friendlyNpc" then
		return ns.Get("plates.friendHealthText") and "both" or "none", true
	end
	if rawequal(unitFrame, PlateFrame("target")) then
		return ns.Get("enemyText.target"), false
	end
	if rawequal(unitFrame, PlateFrame("mouseover")) then
		return ns.Get("enemyText.mouseover"), false
	end
	return ns.Get("enemyText.idle"), false
end

local function Update(unit, unitFrame)
	local mode, isFriendly = NumbersMode(unit, unitFrame)
	modeByFrame[unitFrame] = mode
	ShowNumbers(unitFrame, mode)
	local wantFull
	if isFriendly then
		wantFull = ns.Get("plates.friendFullNames")
	else
		wantFull = ns.Get("plates.enemyFullNames")
	end
	SetFullName(unitFrame, wantFull and true or false)

	local isPet = isFriendly and ns.Get("plates.petNamesOnly") and IsAllyPet(unit)
	local pet = isPet and PetInfo(unit) or nil
	SetPetNameOnly(unitFrame, pet)

	local opacity = isFriendly and tonumber(ns.Get("plates.friendNameAlpha")) or 100
	local nameAlpha = opacity < 100 and math.max(opacity, 10) / 100 or nil
	SetNameAlpha(unitFrame, nameAlpha)

	local scale = ns.GetNameScale()
	SetNameScale(unitFrame, scale ~= 1 and scale or nil)

	if pet and pet.owner and ns.Get("plates.petOwner") then
		SetSubtitle(unitFrame, pet.owner, pet.color, (nameAlpha or 1) * 0.85)
	else
		local guild = GuildTag(unit, ns.GetUnitKind(unit))
		SetSubtitle(unitFrame, guild, GUILD_COLOR, (nameAlpha or 1) * 0.85)
	end
end

local function Refresh(unitFrame)
	local unit = unitFrame and frameUnit[unitFrame]
	if unit and rawequal(ns.activePlates[unit], unitFrame) then
		Update(unit, unitFrame)
	end
end

function ns.OnNameLayout(unitFrame)
	if subtitles[unitFrame] and subtitles[unitFrame]:IsShown() then
		Refresh(unitFrame)
	end
end

-- /fpl debug: what the addon sees on the plate under the cursor / of the target
function ns.DebugNames()
	local count = 0
	for _ in pairs(ns.activePlates) do
		count = count + 1
	end
	ns.Print(("debug: plates managed %d"):format(count))
	for _, token in ipairs({ "mouseover", "target" }) do
		if UnitExists(token) then
			local plate = C_NamePlate.GetNamePlateForUnit(token)
			if not plate then
				ns.Print(token .. ": plate closed to addons by the game (or no plate)")
			else
				local unitFrame = plate.UnitFrame
				local state = nameState[unitFrame]
				local parts = {
					token,
					"unit=" .. tostring(frameUnit[unitFrame]),
					"kind=" .. tostring(frameUnit[unitFrame] and ns.GetUnitKind(frameUnit[unitFrame])),
					"onlyName=" .. tostring(unitFrame.showOnlyName),
					"hooked=" .. tostring(hooked[unitFrame] == true),
					"want=" .. tostring(state and state.want),
					"ours=" .. tostring(state and state.ours),
					"captured=" .. tostring(state and state.points and #state.points),
					"justify=" .. tostring(unitFrame.name:GetJustifyH()),
				}
				local okCount, n = pcall(unitFrame.name.GetNumPoints, unitFrame.name)
				table.insert(parts, "points=" .. tostring(okCount and n))
				if okCount and type(n) == "number" then
					for i = 1, n do
						local ok, point, relativeTo, relativePoint, x, y = pcall(unitFrame.name.GetPoint, unitFrame.name, i)
						if ok then
							local relName = relativeTo and (rawequal(relativeTo, unitFrame.HealthBarsContainer) and "bars"
								or rawequal(relativeTo, unitFrame.PlayerLevelDiffFrame) and "level" or "other") or "nil"
							table.insert(parts, ("[%s %s %s %s %s]"):format(tostring(point), relName, tostring(relativePoint),
								ns.IsSecret(x) and "secret" or tostring(x), ns.IsSecret(y) and "secret" or tostring(y)))
						else
							table.insert(parts, "[error]")
						end
					end
				end
				if ns.DebugPet then
					table.insert(parts, ns.DebugPet(frameUnit[unitFrame], unitFrame))
				end
				ns.Print(table.concat(parts, " "))
			end
		end
	end
end

------------------------------------------------------------------------
-- target and mouseover
------------------------------------------------------------------------

local events = CreateFrame("Frame")
local lastTarget, lastMouseover
local sinceCheck = 0

local function OnTargetChanged()
	local new = PlateFrame("target")
	if not rawequal(new, lastTarget) then
		local old = lastTarget
		lastTarget = new
		Refresh(old)
		Refresh(new)
	end
end

local CheckMouseover

local function WatchMouseover(_, elapsed)
	sinceCheck = sinceCheck + (elapsed or 0)
	if sinceCheck >= 0.1 then
		sinceCheck = 0
		CheckMouseover()
	end
end

function CheckMouseover()
	local new = PlateFrame("mouseover")
	if not rawequal(new, lastMouseover) then
		local old = lastMouseover
		lastMouseover = new
		Refresh(old)
		Refresh(new)
	end
	-- no event fires when the cursor leaves a unit: watch while it is on one
	events:SetScript("OnUpdate", lastMouseover and WatchMouseover or nil)
end

-- pets whose owner wasn't known yet (white): look again when the group changes or a player plate appears
local petRefreshQueued = false
local function QueuePetRefresh()
	if petRefreshQueued then
		return
	end
	petRefreshQueued = true
	C_Timer.After(0.2, function()
		petRefreshQueued = false
		for unitFrame, info in pairs(petMode) do
			if not info.owner then
				Refresh(unitFrame)
			end
		end
	end)
end

events:SetScript("OnEvent", function(_, event)
	if event == "PLAYER_TARGET_CHANGED" then
		OnTargetChanged()
	elseif event == "GROUP_ROSTER_UPDATE" then
		QueuePetRefresh()
	else
		CheckMouseover()
	end
end)

------------------------------------------------------------------------

function M:OnInit()
	ns.RegisterUnitEvent("UNIT_FACTION")
	ns.RegisterUnitEvent("UNIT_NAME_UPDATE")
	events:RegisterEvent("PLAYER_TARGET_CHANGED")
	events:RegisterEvent("UPDATE_MOUSEOVER_UNIT")
	pcall(events.RegisterEvent, events, "GROUP_ROSTER_UPDATE")
end

function M:OnPlateAdded(unit, unitFrame)
	frameUnit[unitFrame] = unit
	HookHealthBar(unitFrame)
	Update(unit, unitFrame)
	if ns.Get("plates.petClassColor") and ns.GetUnitKind(unit) == "friendlyPlayer" then
		QueuePetRefresh() -- maybe the owner of a pet shown in white
	end
end

function M:OnPlateRemoved(_, unitFrame)
	-- unit frames are reused: give everything back before another unit takes this frame
	frameUnit[unitFrame] = nil
	modeByFrame[unitFrame] = nil
	SetFullName(unitFrame, false)
	SetNameAlpha(unitFrame, nil)
	SetNameScale(unitFrame, nil)
	SetPetNameOnly(unitFrame, nil)
	SetSubtitle(unitFrame, nil)
	ShowNumbers(unitFrame, "both")
	hidden[unitFrame] = nil
end

function M:OnUnitEvent(event, unit, unitFrame)
	if event == "UNIT_FACTION" or event == "UNIT_NAME_UPDATE" then
		Update(unit, unitFrame)
	end
end

function M:Apply(key)
	if key == nil or key:find("^health%.") then
		shortOptions = nil
		ns.ForEachPlate(function(_, unitFrame)
			local healthBar = HookHealthBar(unitFrame)
			if healthBar then
				RenderHealth(healthBar, healthBar:GetValue(), true)
			end
		end)
	end
	if key == nil or key:find("^plates%.") or key:find("^enemyText%.") then
		ns.ForEachPlate(Update)
	end
end
