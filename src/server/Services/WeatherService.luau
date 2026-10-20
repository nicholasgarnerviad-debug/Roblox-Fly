-- Applies the current route's weather to the plane. Driven by FlightService's tick.
-- Rain (the tutorial): rain fills open decks with puddles the crew bails out, and wind
-- pushes the ship sideways with gusts the pilot is warned about. Soaking, gust damage
-- and flooded engines still work for later weather that sets soakRate / gustDamage /
-- sputterChance in Weather.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Materials = require(Shared.Materials)
local PartTypes = require(Shared.PartTypes)
local Voyage = require(Shared.Voyage)
local Weather = require(Shared.Weather)
local Remotes = require(Shared.Remotes)
local CrewService = require(script.Parent.CrewService)
local PlaneService = require(script.Parent.PlaneService)
local PlaneCare = require(script.Parent.PlaneCare)

local WeatherService = {}

WeatherService.current = { type = nil, intensity = 0, wind = Vector3.zero, turbulence = 0, progress = 0 }
WeatherService.onGust = nil -- function(velocity: Vector3)

local rng = Random.new()
local puddleAcc = 0
local gustTimer = 6
local gustSide = nil -- announced gust: 1 pushes the ship right, -1 left
local recomputeAcc = 0
local lastHeavyNotice = 0
local hints = {} -- tutorial tips already shown this voyage
local DRY_RATE = -0.02
-- Smaller crews get gentler weather so solo/duo voyages are still possible.
local CREW_SCALE = { 0.45, 0.7, 0.85, 1 }

local function crewScale()
	return CREW_SCALE[math.clamp(PlaneService.crewCount, 1, 4)]
end

-- Shows a tip once per voyage. Returns false if it was already shown.
local function hint(id, text, kind)
	if hints[id] then
		return false
	end
	hints[id] = true
	CrewService.notify(text, kind or "info")
	return true
end

local function setGustWarning(side)
	gustSide = side
	if PlaneService.model then
		PlaneService.model:SetAttribute("GustWarn", side or 0)
	end
end

function WeatherService.reset()
	puddleAcc = 0
	gustTimer = 6
	recomputeAcc = 0
	hints = {}
	setGustWarning(nil)
	WeatherService.current = { type = nil, intensity = 0, wind = Vector3.zero, turbulence = 0, progress = 0 }
end

local function spawnPuddle()
	local free = {}
	for _, key in ipairs(PlaneService.exposedDeckKeys()) do
		local rec = PlaneService.cells[key]
		if rec and not rec.puddle then
			table.insert(free, rec)
		end
	end
	if #free == 0 then
		return
	end
	PlaneCare.addPuddle(free[rng:NextInteger(1, #free)])
	hint("puddle", "\u{1F4A7} Water's pooling on the deck! Walk to a puddle and hold E to bail it.", "warn")
end

-- The ship's flat right-hand direction, so gusts are "from the left/right" of the ship.
local function shipRight()
	local core = PlaneService.core
	local r = core and core.CFrame.RightVector or Vector3.xAxis
	r = Vector3.new(r.X, 0, r.Z)
	return r.Magnitude > 0.01 and r.Unit or Vector3.xAxis
end

local function doGust(sv, intensity, side)
	local k = math.min(intensity, 2)
	local push = shipRight() * side * sv.gustPush * k + Vector3.new(0, rng:NextNumber(-0.3, 0.15) * sv.gustPush * k, 0)
	if WeatherService.onGust then
		WeatherService.onGust(push)
	end
	Remotes.get("Gust"):FireAllClients(k)
	CrewService.sfx("Gust")
	if not sv.gustDamage then
		return -- tutorial gusts only shove the ship
	end
	local hits = PlaneCare.randomParts(rng:NextNumber() < 0.35 and 2 or 1, false)
	local names = {}
	for _, rec in ipairs(hits) do
		local tear = Materials.get(rec.material).tear
		local dmg = rng:NextNumber(sv.gustDamage[1], sv.gustDamage[2]) * intensity * tear * crewScale()
		if PlaneCare.damage(rec, dmg, "gust") then
			table.insert(names, Materials.get(rec.material).display .. " " .. PartTypes.get(rec.type).display)
		end
	end
	if #names > 0 then
		CrewService.notify("A gust slammed the " .. table.concat(names, " and ") .. "!", "warn")
	end
end

local function tickGusts(dt, sv, intensity)
	if not sv.gustEvery or intensity <= 0.2 then
		if gustSide then
			setGustWarning(nil)
		end
		return
	end
	gustTimer -= dt * math.min(intensity, 2)
	if not gustSide and gustTimer <= (sv.gustWarning or 0) then
		setGustWarning(rng:NextNumber() < 0.5 and -1 or 1)
		local from = gustSide > 0 and "left" or "right"
		if
			not hint(
				"gust",
				string.format(
					"\u{1F4A8} Gust coming from the %s! Wind shoves the ship sideways. Pilot: steer back on course.",
					from
				),
				"warn"
			)
		then
			CrewService.notify(string.format("\u{1F4A8} Gust from the %s!", from), "info")
		end
	end
	if gustTimer <= 0 then
		gustTimer = rng:NextNumber(sv.gustEvery[1], sv.gustEvery[2])
		doGust(sv, intensity, gustSide or 1)
		setGustWarning(nil)
	end
end

-- Water is the rain's whole threat, so keep the flight stats in step with it.
local function tickWaterWarnings(dt)
	recomputeAcc += dt
	if recomputeAcc >= 0.25 then
		recomputeAcc = 0
		PlaneService.recompute()
	end
	local cap = PlaneService.waterMax or 0
	local water = PlaneService.waterWeight
	if cap > 0 and water > cap * 0.6 and os.clock() - lastHeavyNotice > 12 then
		lastHeavyNotice = os.clock()
		if water >= cap then
			CrewService.notify("\u{1F4A7} Too much water: we're sinking! Bail it out!", "danger")
		else
			CrewService.notify("\u{1F4A7} The ship is filling with water! Bail before it sinks!", "danger")
		end
	end
end

-- extraIntensity: added by hazards (storm cells)
function WeatherService.tick(dt, position, phase, extraIntensity)
	local routeIndex = CrewService.get("Route")
	local wtype, intensity, t = Voyage.weatherAt(routeIndex, position)
	local active = phase == "Flying"
	if not active then
		intensity = 0
	end
	intensity += extraIntensity or 0
	local def = wtype and Weather.get(wtype)
	local sv = def and def.server
	local cur = WeatherService.current
	cur.type, cur.intensity, cur.progress = wtype, intensity, t or 0
	cur.wind = (sv and sv.wind) and sv.wind * intensity or Vector3.zero
	cur.turbulence = (sv and sv.turbulence or 0) * intensity

	if not active or not sv then
		PlaneCare.tickSoak(dt, DRY_RATE)
		if gustSide then
			setGustWarning(nil)
		end
		return
	end

	if intensity > 0.2 and sv.puddleEvery then
		hint(
			"rain",
			"\u{1F327} Rain! Puddles will weigh the ship down. Crew: hold E on puddles, or crank a Bilge Pump (F).",
			"warn"
		)
	end
	if sv.soakRate then
		PlaneCare.tickSoak(dt, intensity > 0.05 and sv.soakRate * intensity or DRY_RATE)
	end
	if sv.puddleEvery and intensity > 0.1 then
		-- bigger decks catch more rain
		local decks = #PlaneService.exposedDeckKeys()
		puddleAcc += dt * intensity * crewScale() * (1 + decks / 30) / sv.puddleEvery
		while puddleAcc >= 1 do
			puddleAcc -= 1
			spawnPuddle()
		end
	end
	if sv.puddleGrowTime then
		PlaneCare.tickPuddles(dt * math.min(intensity, 1.5), sv.puddleGrowTime, sv.puddleWeight)
	end
	tickWaterWarnings(dt)
	tickGusts(dt, sv, intensity)
	if sv.sputterChance and sv.sputterChance > 0 then
		for _, e in ipairs(PlaneCare.engines()) do
			if not e.sputter and rng:NextNumber() < sv.sputterChance * intensity * crewScale() * dt then
				PlaneCare.setSputter(e, true)
				CrewService.notify("Water in the engine! Hold F on it to restart it!", "danger")
				CrewService.sfx("Crash", e.main)
			end
		end
	end
end

return WeatherService
