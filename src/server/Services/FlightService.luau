-- Game phases + arcade flight model (server-authoritative).
-- Build -> Launching -> Flying -> Landing -> Landed | Crashed -> Build
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Voyage = require(Shared.Voyage)
local PowerUps = require(Shared.PowerUps)
local Materials = require(Shared.Materials)
local Remotes = require(Shared.Remotes)
local CrewService = require(script.Parent.CrewService)
local PlaneService = require(script.Parent.PlaneService)
local PlaneCare = require(script.Parent.PlaneCare)
local WeatherService = require(script.Parent.WeatherService)
local HazardService = require(script.Parent.HazardService)

local F = Config.Flight
local FlightService = {}

local flight = { speed = 0, yaw = 0, pitch = 0, roll = 0, gust = Vector3.zero, vy = 0 }
local input = { pitch = 0, steer = 0, boost = false }
local throttle = 1
local fuel = 0
local launchT = 0
local constraints = nil
local overboard = {}
local crewTimer, hudTimer = 0, 0
local landing = nil
local chute = nil -- the drogue parachute while landing (declared up here so resetToHangar can clear it)
local shieldUntil, boostUntil, invulnUntil = 0, 0, 0
local shieldPart = nil
local lastWarn = {}
local cachedRadius, cachedMin, cachedMax = 10, Vector3.new(-6, -2, -6), Vector3.new(6, 6, 6)
local outOfFuelWarned = false

local obstacleParams = RaycastParams.new()
obstacleParams.FilterType = Enum.RaycastFilterType.Include
obstacleParams.IgnoreWater = true
local groundParams = RaycastParams.new()
groundParams.FilterType = Enum.RaycastFilterType.Include
groundParams.FilterDescendantsInstances = { workspace.Terrain }
groundParams.IgnoreWater = true

local function warnOnce(id, text, kind, every)
	local now = os.clock()
	if not lastWarn[id] or now - lastWarn[id] > (every or 5) then
		lastWarn[id] = now
		CrewService.notify(text, kind)
	end
end

local function wrapAngle(a)
	return (a + math.pi) % (2 * math.pi) - math.pi
end

local function currentRoute()
	return Voyage.Routes[CrewService.get("Route")]
end

local function hangarCFrame()
	return Voyage.Islands[1].hangar.coreCFrame
end

local function pilotSeat()
	local core = PlaneService.core
	return core and core.Parent and core.Parent:FindFirstChild("PilotSeat")
end

function FlightService.pilotPlayer()
	local seat = pilotSeat()
	local hum = seat and seat.Occupant
	return hum and Players:GetPlayerFromCharacter(hum.Parent)
end

local function cacheShape()
	local minV, maxV = Vector3.new(math.huge, math.huge, math.huge), Vector3.new(-math.huge, -math.huge, -math.huge)
	local r = 6
	for _, rec in pairs(PlaneService.cells) do
		local o = rec.cell * Config.CELL
		minV = minV:Min(o)
		maxV = maxV:Max(o)
		r = math.max(r, o.Magnitude + 3)
	end
	cachedMin, cachedMax, cachedRadius = minV - Vector3.new(2, 2, 2), maxV + Vector3.new(2, 2, 2), r
end

local function orientation()
	return CFrame.Angles(0, flight.yaw, 0) * CFrame.Angles(flight.pitch, 0, 0) * CFrame.Angles(0, 0, flight.roll)
end

local function removeConstraints()
	if constraints then
		for _, c in pairs(constraints) do
			c:Destroy()
		end
	end
	constraints = nil
end

local function attachConstraints()
	removeConstraints()
	local core = PlaneService.core
	local att = Instance.new("Attachment")
	att.Name = "FlightAttachment"
	att.Parent = core
	local lv = Instance.new("LinearVelocity")
	lv.Name = "FlightVelocity"
	lv.Attachment0 = att
	lv.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
	lv.RelativeTo = Enum.ActuatorRelativeTo.World
	lv.MaxForce = math.huge
	lv.VectorVelocity = Vector3.zero
	lv.Parent = core
	local ao = Instance.new("AlignOrientation")
	ao.Name = "FlightGyro"
	ao.Mode = Enum.OrientationAlignmentMode.OneAttachment
	ao.Attachment0 = att
	ao.MaxTorque = math.huge
	ao.Responsiveness = F.Responsiveness
	ao.CFrame = core.CFrame
	ao.Parent = core
	constraints = { att = att, lv = lv, ao = ao }
end

local function unseatAll()
	if not PlaneService.model then
		return
	end
	for _, d in ipairs(PlaneService.model:GetDescendants()) do
		if d:IsA("Seat") or d:IsA("VehicleSeat") then
			local w = d:FindFirstChild("SeatWeld")
			if w then
				w:Destroy()
			end
		end
	end
end

-- Put a player back on the plane (free crew seat first, else the deck).
function FlightService.pullAboard(plr)
	local char = plr.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not hrp or not hum or not PlaneService.core then
		return
	end
	for _, rec in pairs(PlaneService.cells) do
		local seat = rec.type == "Seat" and rec.model:FindFirstChild("CrewSeat")
		if seat and not seat.Occupant then
			char:PivotTo(seat.CFrame * CFrame.new(0, 3, 0))
			seat:Sit(hum)
			return
		end
	end
	local keys = PlaneService.exposedDeckKeys()
	local spot
	if #keys > 0 then
		spot = PlaneService.cells[keys[math.random(1, #keys)]].main.CFrame * CFrame.new(0, 5, 0)
	else
		spot = PlaneService.core.CFrame * CFrame.new(0, 8, 2)
	end
	char:PivotTo(spot)
end

local function makeShield(duration)
	if shieldPart then
		shieldPart:Destroy()
	end
	local core = PlaneService.core
	local p = Instance.new("Part")
	p.Name = "ShieldBubble"
	p.Shape = Enum.PartType.Ball
	local d = cachedRadius * 2 + 8
	p.Size = Vector3.new(d, d, d)
	p.Material = Enum.Material.ForceField
	p.Color = PowerUps.Defs.Shield.color
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Massless = true
	p.CastShadow = false
	p.CFrame = core.CFrame * CFrame.new((cachedMin + cachedMax) / 2)
	local w = Instance.new("WeldConstraint")
	w.Part0 = core
	w.Part1 = p
	w.Parent = p
	p.Parent = PlaneService.model
	shieldPart = p
	local token = p
	task.delay(duration, function()
		if shieldPart == token then
			token:Destroy()
			shieldPart = nil
			CrewService.notify("Shield faded.", "info")
		end
	end)
end

local function applyPowerUp(name)
	local def = PowerUps.Defs[name]
	if not def then
		return
	end
	CrewService.stat("powerUps")
	local now = os.clock()
	if name == "Shield" then
		shieldUntil = now + def.duration
		makeShield(def.duration)
	elseif name == "Repair" then
		PlaneCare.repairAll(def.amount)
	elseif name == "Pump" then
		PlaneCare.drainAll()
	elseif name == "Boost" then
		boostUntil = now + def.duration
	elseif name == "Fuel" then
		fuel = math.min(PlaneService.stats.fuelMax, fuel + def.amount)
		outOfFuelWarned = false
	end
	CrewService.notify(def.icon .. " " .. def.display .. "! " .. def.blurb, "good")
	CrewService.sfx("PowerUp", PlaneService.core)
end

function FlightService.launch(player)
	if CrewService.getPhase() ~= "Build" or not PlaneService.core then
		return
	end
	if FlightService.pilotPlayer() ~= player then
		CrewService.notify("Only the pilot can launch. Take the cockpit seat!", "warn", player)
		return
	end
	local s = PlaneService.recompute()
	if s.engines == 0 and s.sails == 0 then
		CrewService.notify("No engine or sail! Build one before launching.", "danger", player)
		return
	end
	if s.margin < 1 then
		CrewService.notify("Warning: the airship is too heavy to hold altitude!", "danger")
	end
	for _, plr in ipairs(Players:GetPlayers()) do
		if plr.Character and not PlaneService.isAboard(plr.Character) then
			FlightService.pullAboard(plr)
		end
	end
	CrewService.resetStats()
	WeatherService.reset()
	HazardService.spawn(CrewService.get("Route"))
	cacheShape()
	local look = PlaneService.core.CFrame.LookVector
	flight = { speed = 0, yaw = math.atan2(-look.X, -look.Z), pitch = 0, roll = 0, gust = Vector3.zero, vy = 0 }
	throttle = 1
	launchT = 0
	fuel = s.fuelMax
	outOfFuelWarned = false
	attachConstraints()
	PlaneService.core.Anchored = false
	PlaneService.core:SetNetworkOwner(nil)
	CrewService.setPhase("Launching")
	CrewService.notify("LAUNCH! Hold onto your hats!", "good")
	CrewService.sfx("Gust")
end

function FlightService.crash(reason)
	local phase = CrewService.getPhase()
	if phase ~= "Flying" and phase ~= "Launching" and phase ~= "Landing" then
		return
	end
	CrewService.setPhase("Crashed")
	local pos = PlaneService.core.Position
	removeConstraints()
	unseatAll()
	PlaneService.explode()
	local ex = Instance.new("Explosion")
	ex.Position = pos
	ex.BlastPressure = 0
	ex.BlastRadius = 0
	ex.DestroyJointRadiusPercent = 0
	ex.Parent = workspace
	CrewService.sfx("Crash", pos)
	local st = CrewService.getStats()
	local route = currentRoute()
	local t = route and route.start and Voyage.progress(route, pos) or 0
	Remotes.get("VoyageResult"):FireAllClients({
		success = false,
		title = reason,
		progress = math.clamp(t, 0, 1),
		stats = st,
		time = os.clock() - st.started,
		destination = Voyage.Islands[route.to].name,
	})
	task.delay(8, function()
		if CrewService.getPhase() == "Crashed" then
			FlightService.resetToHangar("Back at the hangar. Your blueprint survived, so try again!")
		end
	end)
end

function FlightService.resetToHangar(message)
	removeConstraints()
	unseatAll()
	HazardService.clear()
	WeatherService.reset()
	landing = nil
	if chute then
		chute:Destroy()
		chute = nil
	end
	input = { pitch = 0, steer = 0, boost = false }
	shieldUntil, boostUntil, invulnUntil = 0, 0, 0
	if shieldPart then
		shieldPart:Destroy()
		shieldPart = nil
	end
	flight = { speed = 0, yaw = 0, pitch = 0, roll = 0, gust = Vector3.zero, vy = 0 }
	CrewService.setPhase("Build")
	PlaneService.buildPlane(hangarCFrame())
	fuel = PlaneService.stats.fuelMax
	for _, plr in ipairs(Players:GetPlayers()) do
		task.spawn(function()
			plr:LoadCharacter()
		end)
	end
	CrewService.resetStats()
	if message then
		CrewService.notify(message, "info")
	end
end

-- Parachute ------------------------------------------------------------------------

local CHUTE_RED = Color3.fromRGB(205, 70, 55)
local CHUTE_CREAM = Color3.fromRGB(240, 228, 196)
local CHUTE_SIZE = 9 -- canopy diameter: the same little drogue on every ship

-- A part welded to the helm by a Weld (not a WeldConstraint) so its C0 can be animated.
-- c0 is in the helm's local space (+Z is the stern).
local function chutePart(props, c0, sphere)
	local core = PlaneService.core
	local p = Instance.new("Part")
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Massless = true
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = Enum.Material.Fabric
	for k, v in pairs(props) do
		p[k] = v
	end
	if sphere then
		local m = Instance.new("SpecialMesh")
		m.MeshType = Enum.MeshType.Sphere
		m.Scale = Vector3.one * 0.15 -- pops open when deployed
		m.Parent = p
	end
	p.CFrame = core.CFrame * c0
	local w = Instance.new("Weld")
	w.Part0 = core
	w.Part1 = p
	w.C0 = c0
	w.Parent = p
	p.Parent = chute
	return p, w
end

-- A small drogue chute that shoots out of the stern and streams behind the ship.
local function deployChute()
	if chute then
		chute:Destroy()
	end
	chute = Instance.new("Model")
	chute.Name = "Parachute"
	local stern = Vector3.new(0, 2, cachedMax.Z) -- where the riser is tied on
	local knot = stern + Vector3.new(0, 1.5, 5) -- where the shroud lines meet
	local centre = stern + Vector3.new(0, 4, 17)
	local d = CHUTE_SIZE
	local packed = CFrame.new(stern + Vector3.new(0, 1, 1)) -- canopy starts folded at the stern
	local open = TweenInfo.new(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	local function canopyPiece(name, size, offset, color, roll)
		local final = CFrame.new(centre + offset) * CFrame.Angles(0, 0, roll or 0)
		local p, w =
			chutePart({ Name = name, Size = size, Color = color }, packed * CFrame.Angles(0, 0, roll or 0), true)
		TweenService:Create(w, open, { C0 = final }):Play()
		TweenService:Create(p:FindFirstChildOfClass("SpecialMesh"), open, { Scale = Vector3.one }):Play()
	end
	-- canopy faces the ship (flat along Z), cream crown at the back, cream seams
	canopyPiece("Canopy", Vector3.new(d, d, d * 0.5), Vector3.zero, CHUTE_RED)
	canopyPiece("Crown", Vector3.new(d * 0.5, d * 0.5, d * 0.28), Vector3.new(0, 0, d * 0.16), CHUTE_CREAM)
	for i = 0, 1 do
		canopyPiece("Seam", Vector3.new(0.3, d + 0.05, d * 0.5 + 0.05), Vector3.zero, CHUTE_CREAM, math.rad(90 * i))
	end
	-- riser and shroud lines (shown once the canopy is out)
	local lines = {}
	local function line(a, b)
		local p = chutePart(
			{ Name = "Line", Size = Vector3.new(0.14, 0.14, (b - a).Magnitude), Color = CHUTE_CREAM, Transparency = 1 },
			CFrame.lookAt((a + b) / 2, b)
		)
		table.insert(lines, p)
	end
	line(stern, knot)
	for i = 0, 5 do
		local ang = math.rad(60 * i + 30)
		line(knot, centre + Vector3.new(math.cos(ang) * d * 0.46, math.sin(ang) * d * 0.46, -d * 0.18))
	end
	chute.Parent = PlaneService.model
	task.delay(0.4, function()
		for _, l in ipairs(lines) do
			if l.Parent then
				l.Transparency = 0
			end
		end
	end)
	CrewService.sfx("Gust", PlaneService.core.Position)
end

-- On touchdown the drogue sags to the ground behind the ship and fades.
local function collapseChute()
	local c = chute
	chute = nil
	if not c then
		return
	end
	local fold = TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	for _, p in ipairs(c:GetChildren()) do
		if p:IsA("BasePart") then
			TweenService:Create(p, fold, { Transparency = 1 }):Play()
			local w = p:FindFirstChildOfClass("Weld")
			if w and p.Name ~= "Line" then
				TweenService:Create(w, fold, { C0 = w.C0 * CFrame.new(0, -5, -3) }):Play()
				TweenService:Create(p:FindFirstChildOfClass("SpecialMesh"), fold, { Scale = Vector3.new(1, 0.4, 0.4) })
					:Play()
			end
		end
	end
	task.delay(1, function()
		c:Destroy()
	end)
end

local function finishLanding()
	local island = landing.island
	local route = currentRoute()
	PlaneService.core.Anchored = true
	removeConstraints()
	CrewService.setPhase("Landed")
	local st = CrewService.getStats()
	local s = PlaneService.recompute()
	local rewards = table.clone(island.reward or {})
	rewards.Coins = (rewards.Coins or 0)
		+ math.floor(s.integrity * 100)
		+ 5 * (st.puddles + st.repairs + st.restarts)
		+ 10 * st.powerUps
	for k, v in pairs(rewards) do
		CrewService.add(k, v)
	end
	local unlocked = {}
	if route.to > CrewService.get("UnlockedIsland") then
		CrewService.state():SetAttribute("UnlockedIsland", route.to)
		for _, name in ipairs(Materials.Order) do
			local mat = Materials.get(name)
			if mat.upgradeAtIsland == route.to then
				table.insert(unlocked, mat.display .. " upgrades")
			elseif mat.unlockedAtIsland == route.to then
				table.insert(unlocked, mat.display)
			end
		end
	end
	CrewService.state():SetAttribute("FurthestIsland", math.max(CrewService.get("FurthestIsland"), route.to))
	CrewService.add("Voyages", 1)
	local nextIsland = Voyage.Islands[route.to + 1]
	Remotes.get("VoyageResult"):FireAllClients({
		success = true,
		title = "Landed at " .. island.name .. "!",
		time = os.clock() - st.started,
		stats = st,
		rewards = rewards,
		unlocked = unlocked,
		integrity = s.integrity,
		nextIsland = nextIsland and nextIsland.name,
		nextWeather = Voyage.Routes[route.to] and Voyage.Routes[route.to].weather,
	})
	CrewService.sfx("Fanfare")
	-- the crew stays to explore the island on foot; "Tow home" (Continue) takes them back
	CrewService.notify(
		"\u{1F3DD} Welcome to " .. island.name .. "! Hop off and explore. Hit Tow home when you're ready to head back.",
		"good"
	)
end

-- Where along the runway centreline (0..length) a flat position is, and how far off it.
local function runwayOffset(rw, pos)
	local dir = rw.dir or Vector3.new(0, 0, -1)
	local rel = Vector3.new(pos.X - rw.start.X, 0, pos.Z - rw.start.Z)
	local along = math.clamp(rel:Dot(dir), 0, rw.length)
	local closest = rw.start + dir * along
	return along, Vector3.new(pos.X - closest.X, 0, pos.Z - closest.Z).Magnitude, dir
end

local function beginLanding(island, along)
	local rw = island.runway
	local dir = rw.dir or Vector3.new(0, 0, -1)
	-- touch down a little further along than where we are (the ship keeps some momentum)
	local touch = rw.start + dir * math.clamp(along + 50, 50, rw.length - 70)
	landing = {
		island = island,
		touch = Vector3.new(touch.X, 0, touch.Z),
		targetY = rw.start.Y + 2.1,
		yaw = math.atan2(-dir.X, -dir.Z),
		touched = false,
		carry = Vector3.new(constraints.lv.VectorVelocity.X, 0, constraints.lv.VectorVelocity.Z),
	}
	CrewService.setPhase("Landing")
	deployChute()
	CrewService.notify("\u{1FA82} Parachute deployed! Bringing her down on the runway.", "good")
end

-- Parachute landings: get near the runway and low enough, and the chute does the rest.
local function checkLanding(pos)
	local route = currentRoute()
	local island = route and Voyage.Islands[route.to]
	local chuteDef = island and island.parachute
	if not chuteDef or not island.runway then
		return false
	end
	local along, off = runwayOffset(island.runway, pos)
	local alt = pos.Y - Config.WATER_LEVEL
	if off < chuteDef.range + 450 then
		warnOnce(
			"approach",
			string.format(
				"\u{1F3DD} %s ahead! Get near the runway below %d altitude and the parachute will land you.",
				island.name,
				chuteDef.ceiling
			),
			"info",
			40
		)
	end
	if off > chuteDef.range then
		return false
	elseif alt > chuteDef.ceiling then
		warnOnce(
			"high",
			string.format("\u{1FA82} Runway below! Drop under %d altitude to pop the parachute.", chuteDef.ceiling),
			"warn",
			6
		)
		return false
	end
	beginLanding(island, along)
	return true
end

local function onObstacleHit(res, _vel)
	local now = os.clock()
	if now < invulnUntil then
		return
	end
	invulnUntil = now + F.HitInvulnerability
	CrewService.stat("hits")
	PlaneService.model:SetAttribute(
		"LastHit",
		string.format("%s @ %s n=%s", res.Instance:GetFullName(), tostring(res.Position), tostring(res.Normal))
	)
	local n = res.Normal
	local flatN = Vector3.new(n.X, 0, n.Z)
	local isWall = flatN.Magnitude > 0.5
	if isWall then
		-- glance off walls: shove away and deflect the heading a little
		flatN = flatN.Unit
		flight.gust += flatN * 40 + Vector3.new(0, 12, 0)
		flight.speed *= 0.6
		local fwd = Vector3.new(-math.sin(flight.yaw), 0, -math.cos(flight.yaw))
		if fwd:Dot(flatN) < 0 then
			local refl = fwd - 2 * fwd:Dot(flatN) * flatN
			local target = math.atan2(-refl.X, -refl.Z)
			flight.yaw += math.clamp(wrapAngle(target - flight.yaw) * 0.35, -math.rad(35), math.rad(35))
		end
	else
		-- belly / top hit: bounce vertically, keep heading
		flight.gust += Vector3.new(0, n.Y >= 0 and 30 or -20, 0)
		flight.speed *= 0.8
		flight.pitch = n.Y >= 0 and math.rad(12) or flight.pitch
	end
	Remotes.get("Gust"):FireAllClients(2.5)
	CrewService.sfx("Crash", res.Position)
	if PlaneCare.shieldCheck() then
		CrewService.notify("The shield absorbed the hit!", "good")
		return
	end
	PlaneCare.damageNear(res.Position, F.HitRadius + 3, math.random(F.HitDamage[1], F.HitDamage[2]), "rock")
	local what = res.Instance == workspace.Terrain and "the rocks" or res.Instance.Name
	CrewService.notify("CRUNCH! We hit " .. what .. "! Repair the damage!", "danger")
end

local function obstacleCheck(vel, dt)
	local speed = vel.Magnitude
	if speed < 1 then
		return
	end
	local core = PlaneService.core
	local size = (cachedMax - cachedMin) * 0.8
	local cf = core.CFrame * CFrame.new((cachedMin + cachedMax) / 2)
	local res = workspace:Blockcast(cf, size, vel.Unit * (speed * dt * 1.6 + 3), obstacleParams)
	if res then
		onObstacleHit(res, vel)
	end
end

local function stepLaunch(dt)
	launchT += dt
	local a = math.clamp(launchT / F.LaunchTime, 0, 1)
	flight.speed = F.LaunchSpeed * a * a
	local o = CFrame.Angles(0, flight.yaw, 0)
	constraints.lv.VectorVelocity = o.LookVector * flight.speed
	constraints.ao.CFrame = o
	if launchT >= F.LaunchTime then
		flight.speed = F.LaunchSpeed
		flight.pitch = math.rad(3)
		flight.vy = 6 -- ease up off the catapult
		invulnUntil = os.clock() + 2.5 -- grace while clearing the catapult and cliff
		CrewService.setPhase("Flying")
	end
end

local function stepFlight(dt)
	local core = PlaneService.core
	local s = PlaneService.stats
	local pos = core.Position
	local weather = WeatherService.current
	local now = os.clock()

	-- controls: she sails rather than flies (see Config.Flight). The rudder bites and lets
	-- go over RudderLag seconds, and the hull heels gently with the turn.
	local turnRate = math.rad(s.turnRate * F.TurnBonus)
	local yawRate = flight.yawRate or 0
	yawRate += (-input.steer * turnRate - yawRate) * math.min(1, dt / F.RudderLag)
	flight.yawRate = yawRate
	flight.yaw += yawRate * dt
	local heel = turnRate > 0 and yawRate / turnRate or 0
	flight.roll += (heel * F.BankAngle - flight.roll) * math.min(1, dt * 1.5)

	-- engine, fuel, speed
	-- engines need fuel; sails always pull
	local engineOn = fuel > 0 and s.engineThrust > 0
	local boosting = input.boost and engineOn
	-- sails and wings always pull; throttle (and fuel) only governs the engines' share
	local top = s.sailTopSpeed + (engineOn and (s.topSpeed - s.sailTopSpeed) * math.max(throttle, 0.15) or 0)
	if boosting then
		top = s.topSpeed * F.BoostMultiplier
	end
	if now < boostUntil then
		top = math.max(top, s.topSpeed * F.PowerBoostMultiplier)
	end
	local pulling = engineOn and s.thrust or s.sailThrust
	-- weight never slows you down: the sails fill at a pace set by how fast this rig can go
	local accel = pulling > 0 and (F.SailAccel + F.SailAccelPerSpeed * top) or 0
	if now < boostUntil or boosting then
		accel *= 2
	end
	if flight.speed < top then
		flight.speed = math.min(top, flight.speed + accel * dt)
	else
		flight.speed = math.max(top, flight.speed - F.SailDecel * dt)
	end
	if engineOn then
		fuel = math.max(
			0,
			fuel
				- s.engines
					* F.FuelBurnPerEngine
					* math.max(throttle, 0.15)
					* (boosting and F.BoostFuelMultiplier or 1)
					* dt
		)
		if fuel <= 0 and not outOfFuelWarned then
			outOfFuelWarned = true
			CrewService.notify(
				s.sails > 0 and "Out of fuel! Running on sails, so find a Fuel Can!"
					or "Out of fuel! We're gliding, so find a Fuel Can!",
				"danger"
			)
		end
	end
	-- climbing trades a little speed, sinking wins it back
	flight.speed = math.clamp(flight.speed - flight.vy * F.ClimbDrag * dt, 0, 220)

	-- lift vs weight decides how hard we can climb (or how fast we sink)
	-- wings need airspeed; balloons float regardless
	local liftFactor = math.clamp(flight.speed / F.FullLiftSpeed, 0, 1) ^ 1.5
	local margin = (s.staticLift + s.dynamicLift * liftFactor) / math.max(s.weight, 1)
	local climbCap = math.min((margin - 1) * F.ClimbPerMargin, F.MaxClimb)
	if pos.Y > F.CeilingSoft then
		climbCap = math.min(climbCap, F.MaxClimb * (1 - (pos.Y - F.CeilingSoft) / (F.CeilingHard - F.CeilingSoft)))
	end
	-- W/S trims the ballast: ease toward the climb or sink asked for, within what lift allows
	local want = input.pitch > 0 and F.SailClimb or (input.pitch < 0 and -F.SailDive or 0)
	want = math.max(math.min(want, climbCap), -F.MaxSinkRate)
	flight.vy += (want - flight.vy) * math.min(1, dt / F.BallastLag)
	local vy = flight.vy
	-- the bow only tips a little with the climb
	local pitchGoal = math.clamp(vy / F.SailClimb, -1, 1) * F.MaxPitch
	flight.pitch += (pitchGoal - flight.pitch) * math.min(1, dt * 1.5)
	local flat = Vector3.new(-math.sin(flight.yaw), 0, -math.cos(flight.yaw))
	-- a slow swell: she heaves and rocks like a ship at sea
	local swell = F.Swell
	local vel = flat * flight.speed + Vector3.new(0, vy + swell.Heave * math.sin(now * 0.45), 0)
	vel += weather.wind + flight.gust - Vector3.new(0, HazardService.effects.down, 0)
	flight.gust *= (1 - math.min(1, dt * 1.3))

	-- turbulence wobble (tail fins calm it down), on top of the swell
	local turb = math.rad(weather.turbulence / (1 + s.stability * 0.6))
	local tp = turb * math.noise(now * 0.9, 1.3) + swell.Pitch * math.sin(now * 0.37 + 1.3)
	local tr = turb * 1.6 * math.noise(now * 0.8, 7.7) + swell.Roll * math.sin(now * 0.55)

	constraints.lv.VectorVelocity = vel
	constraints.ao.CFrame = CFrame.Angles(0, flight.yaw, 0)
		* CFrame.Angles(flight.pitch + tp, 0, 0)
		* CFrame.Angles(0, 0, flight.roll + tr)

	-- outcomes
	if pos.Y < Config.WATER_LEVEL + 3 then
		FlightService.crash("Splashdown! The airship hit the sea.")
		return
	end
	if checkLanding(pos) then
		return
	end
	if now >= invulnUntil then
		obstacleCheck(vel, dt)
	end
	local route = currentRoute()
	if route and route.start then
		local t, lateral = Voyage.progress(route, pos)
		if t > 1.1 then
			warnOnce("overshoot", "You flew past " .. Voyage.Islands[route.to].name .. "! Turn around!", "warn", 6)
		elseif lateral > 1300 then
			warnOnce("lost", "You're way off course! Follow the island marker.", "warn", 6)
		end
	end
	if margin < 0.98 and flight.speed > F.StallSpeed then
		warnOnce("heavy", "We're sinking! Too heavy: bail water and patch the balloons!", "danger", 9)
	elseif flight.speed < F.StallSpeed and engineOn and s.staticLift < s.weight then
		warnOnce("stall", "Stalling! Nose down to pick up speed!", "warn", 6)
	end
end

-- Under the parachute: bleed off speed, drift onto the runway, swing round to face down it.
local function stepLanding(dt)
	local core = PlaneService.core
	local pos = core.Position
	landing.carry *= math.exp(-F.ChuteBrake * dt)
	local toTouch = Vector3.new(landing.touch.X - pos.X, 0, landing.touch.Z - pos.Z)
	local drift = toTouch * 1.1
	if drift.Magnitude > F.ChuteDrift then
		drift = drift.Unit * F.ChuteDrift
	end
	local horiz = landing.carry + drift
	-- glide down a slope that ends at the touchdown spot (so we never dip into the sea),
	-- and keep clear of any hills on the way in
	local dist = toTouch.Magnitude
	local floorY = landing.targetY + math.max(0, dist - 12) * 0.3
	if dist > 25 then
		local g = workspace:Raycast(Vector3.new(pos.X, pos.Y + 50, pos.Z), Vector3.new(0, -400, 0), groundParams)
		if g then
			floorY = math.max(floorY, g.Position.Y - cachedMin.Y + 4)
		end
	end
	-- after touchdown, ease the last bit down onto the runway
	local vy = landing.touched and math.clamp((landing.targetY - pos.Y) * 4, -6, 0)
		or math.clamp((floorY - pos.Y) * 1.3, -F.ChuteSink, 10)
	if landing.touched then
		horiz *= 0.2
	end
	flight.yaw += wrapAngle(landing.yaw - flight.yaw) * math.min(1, dt * 2)
	flight.pitch += (0 - flight.pitch) * math.min(1, dt * 4)
	flight.roll += (0 - flight.roll) * math.min(1, dt * 4)
	flight.speed = horiz.Magnitude
	flight.vy = vy
	constraints.lv.VectorVelocity = Vector3.new(horiz.X, vy, horiz.Z)
	constraints.ao.CFrame = orientation()
	if not landing.touched and pos.Y - landing.targetY < 1.5 and dist < 12 then
		landing.touched = true
		landing.touchedAt = os.clock()
		CrewService.notify("Touchdown!", "good")
		Remotes.get("Gust"):FireAllClients(0.8)
		collapseChute()
	end
	if landing.touched and os.clock() - landing.touchedAt > 0.8 then
		finishLanding()
	end
end

local function updateCrew(phase)
	local airborne = phase == "Flying" or phase == "Launching" or phase == "Landing"
	local count = 0
	for _, plr in ipairs(Players:GetPlayers()) do
		local char = plr.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if hum and hum.Health > 0 then
			if PlaneService.isAboard(char) then
				count += 1
				overboard[plr] = nil
			elseif airborne then
				overboard[plr] = (overboard[plr] or 0) + 0.5
				if overboard[plr] >= F.OverboardDelay then
					overboard[plr] = nil
					FlightService.pullAboard(plr)
					CrewService.notify(plr.DisplayName .. " was hauled back aboard by their safety rope!", "info")
				end
			end
		end
	end
	if count ~= PlaneService.crewCount then
		PlaneService.crewCount = count
		PlaneService.recompute()
	end
end

local function publishHud(phase)
	local m = PlaneService.model
	local core = PlaneService.core
	if not m or not core then
		return
	end
	local now = os.clock()
	if phase == "Build" then
		fuel = PlaneService.stats.fuelMax
	end
	local route = currentRoute()
	local t, len = 0, 0
	if route and route.start then
		local _
		t, _, len = Voyage.progress(route, core.Position)
	end
	local pilot = FlightService.pilotPlayer()
	m:SetAttribute("Speed", flight.speed)
	m:SetAttribute("Altitude", core.Position.Y - Config.WATER_LEVEL)
	m:SetAttribute("Climb", flight.vy)
	m:SetAttribute("Fuel", fuel)
	m:SetAttribute("Throttle", throttle)
	m:SetAttribute("Boosting", input.boost)
	m:SetAttribute("BoostTime", math.max(0, boostUntil - now))
	m:SetAttribute("ShieldTime", math.max(0, shieldUntil - now))
	m:SetAttribute("Progress", math.clamp(t, 0, 1))
	m:SetAttribute("Distance", math.max(0, (1 - t) * len))
	m:SetAttribute("Weather", WeatherService.current.type or "")
	m:SetAttribute("WeatherIntensity", WeatherService.current.intensity)
	m:SetAttribute("Puddles", PlaneCare.puddleCount())
	-- wind in the ship's frame (x = right, y = forward) for the pilot's wind arrow
	local w = WeatherService.current.wind + Vector3.new(flight.gust.X, 0, flight.gust.Z)
	local look = core.CFrame.LookVector
	local fwd = Vector3.new(look.X, 0, look.Z)
	fwd = fwd.Magnitude > 0.01 and fwd.Unit or Vector3.new(0, 0, -1)
	m:SetAttribute("WindLocal", Vector2.new(w:Dot(fwd:Cross(Vector3.yAxis)), w:Dot(fwd)))
	m:SetAttribute("Soak", PlaneCare.averageSoak())
	m:SetAttribute("Pilot", pilot and pilot.DisplayName or "")
end

local function step(dt)
	local core = PlaneService.core
	if not core then
		return
	end
	local phase = CrewService.getPhase()
	local storm = 0
	if phase == "Flying" then
		HazardService.tick(dt, core.Position, cachedRadius)
		storm = HazardService.effects.storm
	end
	WeatherService.tick(dt, core.Position, phase, storm)
	crewTimer += dt
	if crewTimer >= 0.5 then
		crewTimer = 0
		updateCrew(phase)
	end
	if constraints then
		if phase == "Launching" then
			stepLaunch(dt)
		elseif phase == "Flying" then
			stepFlight(dt)
		elseif phase == "Landing" then
			stepLanding(dt)
		end
	end
	hudTimer += dt
	if hudTimer >= 0.1 then
		hudTimer = 0
		publishHud(phase)
	end
end

function FlightService.init()
	obstacleParams.FilterDescendantsInstances = { workspace.Terrain, workspace:WaitForChild("World") }
	PlaneService.buildPlane(hangarCFrame())
	fuel = PlaneService.stats.fuelMax

	WeatherService.onGust = function(v)
		flight.gust += v
	end
	HazardService.onPickup = applyPowerUp
	PlaneCare.shieldCheck = function()
		return os.clock() < shieldUntil
	end
	PlaneCare.onCoreDestroyed = function()
		FlightService.crash("The cockpit was smashed to bits!")
	end

	Remotes.get("PilotInput").OnServerEvent:Connect(function(player, pitch, steer, boost, thr)
		if player ~= FlightService.pilotPlayer() then
			return
		end
		input.pitch = typeof(pitch) == "number" and math.clamp(pitch, -1, 1) or 0
		input.steer = typeof(steer) == "number" and math.clamp(steer, -1, 1) or 0
		input.boost = boost == true
		if typeof(thr) == "number" then
			throttle = math.clamp(thr, 0, 1)
		end
	end)
	Remotes.get("Launch").OnServerEvent:Connect(FlightService.launch)
	Remotes.get("Continue").OnServerEvent:Connect(function()
		local phase = CrewService.getPhase()
		if phase == "Landed" then
			FlightService.resetToHangar(
				"Old Gus towed you home with the loot. Rustbucket Reef's hangar is still being built!"
			)
		elseif phase == "Crashed" then
			FlightService.resetToHangar("Back at the hangar. Your blueprint survived, so try again!")
		end
	end)
	Players.PlayerRemoving:Connect(function(plr)
		overboard[plr] = nil
	end)

	-- reset pilot input when the pilot leaves the seat
	RunService.Heartbeat:Connect(function(dt)
		if not FlightService.pilotPlayer() then
			input.pitch, input.steer, input.boost = 0, 0, false
		end
		step(dt)
	end)
end

return FlightService
