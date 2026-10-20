-- Pilot challenges re-rolled every voyage: storm cells, downdrafts and power-up orbs.
-- (Sea stacks are static terrain in Workspace.World.SeaStacks.)
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Voyage = require(Shared.Voyage)
local PowerUps = require(Shared.PowerUps)
local CrewService = require(script.Parent.CrewService)

local HazardService = {}

HazardService.onPickup = nil -- function(name)
HazardService.effects = { storm = 0, down = 0 }

local rng = Random.new()
local folder
local stormCells, drafts, pickups = {}, {}, {}

local function flatDist(a, b)
	return Vector2.new(a.X - b.X, a.Z - b.Z).Magnitude
end

local function corridorPoint(route, t, width)
	local a, b = route.start, route.finish
	local dir = (b - a).Unit
	local right = dir:Cross(Vector3.yAxis).Unit
	return a:Lerp(b, t) + right * rng:NextNumber(-width / 2, width / 2)
end

local function part(props)
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for k, v in pairs(props) do
		p[k] = v
	end
	return p
end

local function streaks(parent, color, rate, speed, size)
	local e = Instance.new("ParticleEmitter")
	e.EmissionDirection = Enum.NormalId.Bottom
	e.Shape = Enum.ParticleEmitterShape.Box
	e.Rate = rate
	e.Speed = NumberRange.new(speed * 0.85, speed)
	e.Lifetime = NumberRange.new(2.5, 3.2)
	e.Size = NumberSequence.new(size)
	e.Squash = NumberSequence.new(3)
	e.Orientation = Enum.ParticleOrientation.VelocityParallel
	e.Color = ColorSequence.new(color)
	e.Transparency = NumberSequence.new(0.35)
	e.LightEmission = 0.2
	e.Parent = parent
	return e
end

local function makeStormCell(pos, r)
	local m = Instance.new("Model")
	m.Name = "StormCell"
	part({
		Name = "Column",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(480, r * 2, r * 2),
		CFrame = CFrame.new(pos.X, 230, pos.Z) * CFrame.Angles(0, 0, math.rad(90)),
		Material = Enum.Material.SmoothPlastic,
		Color = Color3.fromRGB(64, 68, 82),
		Transparency = 0.5,
	}).Parent =
		m
	local top = part({
		Name = "Top",
		Size = Vector3.new(r * 1.8, 1, r * 1.8),
		CFrame = CFrame.new(pos.X, 420, pos.Z),
		Transparency = 1,
	})
	streaks(top, Color3.fromRGB(190, 210, 235), 260, 150, 0.7)
	top.Parent = m
	m.Parent = folder
	table.insert(stormCells, { pos = pos, r = r, warned = false })
end

local function makeDowndraft(pos, r, strength)
	local m = Instance.new("Model")
	m.Name = "Downdraft"
	part({
		Name = "Column",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(420, r * 2, r * 2),
		CFrame = CFrame.new(pos.X, 210, pos.Z) * CFrame.Angles(0, 0, math.rad(90)),
		Material = Enum.Material.ForceField,
		Color = Color3.fromRGB(200, 230, 255),
		Transparency = 0.2,
	}).Parent =
		m
	local top = part({
		Name = "Top",
		Size = Vector3.new(r * 1.6, 1, r * 1.6),
		CFrame = CFrame.new(pos.X, 400, pos.Z),
		Transparency = 1,
	})
	streaks(top, Color3.fromRGB(255, 255, 255), 90, 120, 1.2)
	top.Parent = m
	m.Parent = folder
	table.insert(drafts, { pos = pos, r = r, strength = strength, warned = false })
end

local function makePickup(pos, name)
	local def = PowerUps.Defs[name]
	local m = Instance.new("Model")
	m.Name = "PowerUp_" .. name
	local orb = part({
		Name = "Orb",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(6, 6, 6),
		CFrame = CFrame.new(pos),
		Material = Enum.Material.Neon,
		Color = def.color,
	})
	orb:SetAttribute("PowerUp", name)
	orb.Parent = m
	part({
		Name = "Halo",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(10, 10, 10),
		CFrame = CFrame.new(pos),
		Material = Enum.Material.ForceField,
		Color = def.color,
	}).Parent =
		m
	local light = Instance.new("PointLight")
	light.Color = def.color
	light.Range = 30
	light.Brightness = 3
	light.Parent = orb
	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.fromScale(8, 8)
	bb.StudsOffset = Vector3.new(0, 7, 0)
	bb.MaxDistance = 700
	bb.LightInfluence = 0
	bb.Parent = orb
	local t = Instance.new("TextLabel")
	t.Size = UDim2.fromScale(1, 1)
	t.BackgroundTransparency = 1
	t.Text = def.icon
	t.TextScaled = true
	t.Parent = bb
	m.PrimaryPart = orb
	m.Parent = folder
	table.insert(pickups, { name = name, model = m, part = orb })
end

function HazardService.clear()
	if folder then
		folder:Destroy()
	end
	folder = nil
	stormCells, drafts, pickups = {}, {}, {}
	HazardService.effects = { storm = 0, down = 0 }
end

function HazardService.spawn(routeIndex)
	HazardService.clear()
	local route = Voyage.Routes[routeIndex]
	if not route or not route.start then
		return
	end
	folder = Instance.new("Folder")
	folder.Name = "Hazards"
	folder.Parent = workspace
	local hz = route.hazards or {}
	local width = route.corridorWidth or 600
	for _ = 1, hz.stormCells or 0 do
		makeStormCell(corridorPoint(route, rng:NextNumber(0.22, 0.85), width * 0.7), rng:NextNumber(70, 110))
	end
	for _ = 1, hz.downdrafts or 0 do
		makeDowndraft(
			corridorPoint(route, rng:NextNumber(0.15, 0.9), width * 0.7),
			rng:NextNumber(50, 70),
			rng:NextNumber(9, 15)
		)
	end
	local n = route.powerUps or 0
	for i = 1, n do
		local t = math.clamp((i - 0.5) / n + rng:NextNumber(-0.02, 0.02), 0.06, 0.95)
		local p = corridorPoint(route, t, width * 0.45)
		makePickup(Vector3.new(p.X, rng:NextNumber(70, 230), p.Z), PowerUps.random(rng))
	end
end

function HazardService.tick(_dt, corePos, radius)
	local storm, down = 0, 0
	for _, c in ipairs(stormCells) do
		local d = flatDist(corePos, c.pos)
		if d < c.r then
			storm = math.max(storm, 1.2 * (1 - d / c.r * 0.5))
			if not c.warned then
				c.warned = true
				CrewService.notify("Storm cell! The deck is flooding, bail fast!", "danger")
			end
		end
	end
	for _, dd in ipairs(drafts) do
		local d = flatDist(corePos, dd.pos)
		if d < dd.r then
			down = math.max(down, dd.strength * (1 - d / dd.r * 0.4))
			if not dd.warned then
				dd.warned = true
				CrewService.notify("Downdraft! Pilot, pull up!", "warn")
			end
		end
	end
	HazardService.effects.storm = storm
	HazardService.effects.down = down
	for i = #pickups, 1, -1 do
		local pk = pickups[i]
		if (pk.part.Position - corePos).Magnitude < radius + 7 then
			table.remove(pickups, i)
			pk.model:Destroy()
			if HazardService.onPickup then
				HazardService.onPickup(pk.name)
			end
		end
	end
end

return HazardService
