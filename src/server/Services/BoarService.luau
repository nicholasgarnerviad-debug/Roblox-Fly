-- Wild boars roaming the islands the crew explores (Voyage.Islands[i].mobs).
-- Each boar is a Humanoid NPC (server-owned root) with a part-built body and a small
-- state machine: wander near its den -> snort and charge -> gore -> back off -> charge.
-- Players fight back with melee weapons (Shared.Weapons; Swing remote, handled here too).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Materials = require(Shared.Materials)
local Voyage = require(Shared.Voyage)
local Weapons = require(Shared.Weapons)
local Remotes = require(Shared.Remotes)
local CrewService = require(script.Parent.CrewService)

local BoarService = {}

local CFG = {
	maxHealth = 60,
	wanderSpeed = 7,
	chargeSpeed = 21,
	backOffSpeed = 15,
	sight = 30, -- notices players this close
	leash = 75, -- gives up and walks home past this distance from its den
	goreDamage = 10,
	goreRange = 5,
	goreCooldown = 1.6,
	backOffTime = 1.1,
	respawn = 45,
	loot = { Coins = 12, Cloth = 2 }, -- the hide makes decent canvas
	activeRange = 350, -- boars only think when a player is this close
}

local HIDE = Color3.fromRGB(96, 66, 46)
local DARK = Color3.fromRGB(56, 38, 28)
local SNOUT = Color3.fromRGB(198, 140, 124)
local TUSK = Color3.fromRGB(240, 232, 210)
local BELLY = Color3.fromRGB(150, 112, 84)
local HOOF = Color3.fromRGB(32, 25, 22)
local HIT = Color3.fromRGB(220, 120, 110)
local HIP = 1.6 -- HumanoidRootPart bottom above the ground

local boars = {}
local folder
local rng = Random.new()

local groundParams = RaycastParams.new()
groundParams.FilterType = Enum.RaycastFilterType.Include
groundParams.FilterDescendantsInstances = { workspace.Terrain }

local function groundAt(x, z)
	local r = workspace:Raycast(Vector3.new(x, 400, z), Vector3.new(0, -500, 0), groundParams)
	return r and r.Position.Y or 0
end

-- Body building -------------------------------------------------------------

local function bodyPart(model, root, props, offset)
	local p = Instance.new(props.Class or "Part")
	props.Class = nil
	p.CanCollide = false
	p.CanQuery = true
	p.CanTouch = false
	p.Massless = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = Enum.Material.SmoothPlastic
	local mesh = props.Mesh
	props.Mesh = nil
	for k, v in pairs(props) do
		p[k] = v
	end
	if mesh then
		local m = Instance.new("SpecialMesh")
		m.MeshType = Enum.MeshType.Sphere
		m.Parent = p
	end
	p.CFrame = root.CFrame * offset
	local w = Instance.new("Weld")
	w.Part0 = root
	w.Part1 = p
	w.C0 = offset
	w.Parent = p
	p.Parent = model
	return p, w
end

local function shade(c, f)
	return Color3.new(math.clamp(c.R * f, 0, 1), math.clamp(c.G * f, 0, 1), math.clamp(c.B * f, 0, 1))
end

-- A part that rides on a leg (shin, hoof) so it swings with the hip.
local function legPart(model, leg, props, offset)
	local p = Instance.new("Part")
	p.CanCollide = false
	p.CanQuery = true
	p.CanTouch = false
	p.Massless = true
	p.Material = Enum.Material.SmoothPlastic
	for k, v in pairs(props) do
		p[k] = v
	end
	p.CFrame = leg.CFrame * offset
	local w = Instance.new("Weld")
	w.Part0 = leg
	w.Part1 = p
	w.C0 = offset
	w.Parent = p
	p.Parent = model
	return p
end

local function buildBoar(cf)
	local model = Instance.new("Model")
	model.Name = "Boar"
	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic -- clients always get the whole boar
	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = Vector3.new(2.6, 2.6, 4.4)
	root.Transparency = 1
	root.CanCollide = false
	root.CFrame = cf
	root.Parent = model
	model.PrimaryPart = root
	-- every boar's coat is a shade lighter or darker
	local hide = shade(HIDE, 1 + rng:NextNumber(-0.1, 0.1))
	local face = shade(hide, 0.9)
	-- hide parts flash when hit; BaseColor is what they go back to
	local function hidePart(props, offset)
		local p = bodyPart(model, root, props, offset)
		p:SetAttribute("Hide", true)
		p:SetAttribute("BaseColor", p.Color)
		return p
	end
	-- one long barrel of a body with a hump over the shoulders and a paler belly
	local body = hidePart(
		{ Name = "Body", Size = Vector3.new(3.2, 2.9, 5.4), Color = hide, Mesh = true },
		CFrame.new(0, 0, 0.15)
	)
	hidePart({ Name = "Hump", Size = Vector3.new(2.9, 2.6, 2.9), Color = hide, Mesh = true }, CFrame.new(0, 0.5, -0.85))
	bodyPart(
		model,
		root,
		{ Name = "Belly", Size = Vector3.new(2.4, 1.2, 4.3), Color = BELLY, Mesh = true },
		CFrame.new(0, -0.9, 0.15)
	)
	-- a dark mane of bristles swept back along the spine
	bodyPart(
		model,
		root,
		{ Name = "ManeRidge", Size = Vector3.new(1.1, 0.9, 3.6), Color = DARK, Mesh = true },
		CFrame.new(0, 1.42, -0.6)
	)
	for i = 0, 10 do
		local h = 0.75 - math.abs(i - 3) * 0.045
		bodyPart(
			model,
			root,
			{ Class = "WedgePart", Name = "Bristle", Size = Vector3.new(0.14, h, 0.5), Color = DARK },
			CFrame.new(rng:NextNumber(-0.12, 0.12), 1.72 + h * 0.25 - math.max(0, i - 3) * 0.06, -2.1 + i * 0.33)
				* CFrame.Angles(math.rad(30), 0, 0)
		)
	end
	-- head carried low, tapering into the muzzle and snout
	hidePart(
		{ Name = "Head", Size = Vector3.new(2.1, 1.95, 2.5), Color = face, Mesh = true },
		CFrame.new(0, 0.12, -2.55) * CFrame.Angles(math.rad(-18), 0, 0)
	)
	hidePart(
		{ Name = "Muzzle", Size = Vector3.new(1.3, 1.15, 1.9), Color = face, Mesh = true },
		CFrame.new(0, -0.38, -3.65) * CFrame.Angles(math.rad(-10), 0, 0)
	)
	bodyPart(
		model,
		root,
		{ Name = "Snout", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.3, 1.0, 1.0), Color = SNOUT },
		CFrame.new(0, -0.5, -4.55) * CFrame.Angles(0, math.rad(90), 0)
	)
	bodyPart(
		model,
		root,
		{ Name = "Chin", Size = Vector3.new(0.85, 0.45, 1.1), Color = shade(face, 0.85), Mesh = true },
		CFrame.new(0, -0.92, -3.7)
	)
	for _, s in ipairs({ -1, 1 }) do
		bodyPart(model, root, {
			Name = "Nostril",
			Shape = Enum.PartType.Ball,
			Size = Vector3.one * 0.22,
			Color = Color3.fromRGB(60, 30, 28),
		}, CFrame.new(s * 0.2, -0.5, -4.69))
		bodyPart(
			model,
			root,
			{ Name = "Eye", Shape = Enum.PartType.Ball, Size = Vector3.one * 0.28, Color = Color3.fromRGB(18, 14, 12) },
			CFrame.new(s * 0.6, 0.4, -3.28)
		)
		bodyPart(
			model,
			root,
			{ Class = "WedgePart", Name = "Ear", Size = Vector3.new(0.16, 0.9, 0.6), Color = DARK },
			CFrame.new(s * 0.62, 1.35, -2.0) * CFrame.Angles(math.rad(25), 0, math.rad(-s * 20))
		)
		-- curved tusks: a root out of the jaw, then a tip that hooks up
		bodyPart(
			model,
			root,
			{ Name = "Tusk", Size = Vector3.new(0.18, 0.45, 0.18), Color = TUSK },
			CFrame.new(s * 0.5, -0.78, -4.15) * CFrame.Angles(math.rad(-60), 0, math.rad(s * 12))
		)
		bodyPart(
			model,
			root,
			{ Name = "Tusk", Size = Vector3.new(0.15, 0.45, 0.15), Color = TUSK },
			CFrame.new(s * 0.56, -0.48, -4.45) * CFrame.Angles(math.rad(-15), 0, math.rad(s * 22))
		)
	end
	-- curly tail with a tuft
	bodyPart(
		model,
		root,
		{ Name = "Tail", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.9, 0.16, 0.16), Color = DARK },
		CFrame.new(0, 0.45, 2.95) * CFrame.Angles(0, math.rad(90), math.rad(-55))
	)
	bodyPart(
		model,
		root,
		{ Name = "Tuft", Size = Vector3.new(0.35, 0.45, 0.35), Color = DARK, Mesh = true },
		CFrame.new(0, 0.02, 3.2)
	)
	local legs = {}
	for _, l in ipairs({ { -0.9, -1.5 }, { 0.9, -1.5 }, { -0.9, 1.7 }, { 0.9, 1.7 } }) do
		-- the weld's C0 sits at the hip so the client can swing the legs (BoarAnimator)
		local hipCF = CFrame.new(l[1], -1.0, l[2])
		local leg, w = bodyPart(
			model,
			root,
			{ Name = "Leg", Size = Vector3.new(0.85, 1.25, 1.0), Color = shade(hide, 0.8), Mesh = true },
			hipCF
		)
		w.Name = "Hip"
		w.C1 = CFrame.new(0, 0.5, 0)
		leg:SetAttribute("Phase", (l[1] * l[2] > 0) and 0 or math.pi)
		-- shin and hoof ride on the thigh
		legPart(
			model,
			leg,
			{ Name = "Shin", Size = Vector3.new(0.45, 0.75, 0.5), Color = DARK },
			CFrame.new(0, -0.85, 0)
		)
		legPart(
			model,
			leg,
			{ Name = "Hoof", Size = Vector3.new(0.55, 0.25, 0.62), Color = HOOF },
			CFrame.new(0, -1.3, -0.03)
		)
		table.insert(legs, w)
	end
	-- health bar (hidden until hurt)
	local bb = Instance.new("BillboardGui")
	bb.Name = "HealthBar"
	bb.Size = UDim2.fromOffset(74, 11)
	bb.StudsOffset = Vector3.new(0, 3.4, 0)
	bb.AlwaysOnTop = true
	bb.MaxDistance = 80
	bb.Enabled = false
	bb.Parent = body
	-- same look as the HUD's bars: dark well, brass rim, glossy fill
	local back = Instance.new("Frame")
	back.Size = UDim2.fromScale(1, 1)
	back.BackgroundColor3 = Color3.fromRGB(22, 16, 14)
	back.BorderSizePixel = 0
	back.Parent = bb
	local rim = Instance.new("UIStroke")
	rim.Color = Color3.fromRGB(222, 166, 82)
	rim.Thickness = 1.5
	rim.Transparency = 0.2
	rim.Parent = back
	Instance.new("UICorner", back).CornerRadius = UDim.new(0.5, 0)
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = Color3.fromRGB(236, 88, 72)
	fill.BorderSizePixel = 0
	fill.Parent = back
	Instance.new("UICorner", fill).CornerRadius = UDim.new(0.5, 0)
	local gloss = Instance.new("UIGradient")
	gloss.Rotation = 90
	gloss.Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(170, 170, 170))
	gloss.Parent = fill
	-- "!" when it spots you
	local alert = Instance.new("BillboardGui")
	alert.Name = "Alert"
	alert.Size = UDim2.fromOffset(40, 40)
	alert.StudsOffset = Vector3.new(0, 5.2, 0)
	alert.AlwaysOnTop = true
	alert.MaxDistance = 90
	alert.Enabled = false
	alert.Parent = body
	local t = Instance.new("TextLabel")
	t.Size = UDim2.fromScale(1, 1)
	t.BackgroundTransparency = 1
	t.Font = Enum.Font.FredokaOne
	t.TextScaled = true
	t.TextColor3 = Color3.fromRGB(255, 90, 70)
	t.TextStrokeTransparency = 0.2
	t.Text = "!"
	t.Parent = alert

	local hum = Instance.new("Humanoid")
	hum.RigType = Enum.HumanoidRigType.R15
	hum.HipHeight = HIP
	hum.MaxHealth = CFG.maxHealth
	hum.Health = CFG.maxHealth
	hum.WalkSpeed = CFG.wanderSpeed
	hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	hum.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	hum.BreakJointsOnDeath = false
	hum.Parent = model
	model:SetAttribute("Mob", "Boar")
	return model, root, hum, body, legs, fill, bb, alert
end

-- Lifecycle -------------------------------------------------------------------

local spawnBoar

local function setHealthBar(b)
	local frac = math.clamp(b.hum.Health / b.hum.MaxHealth, 0, 1)
	b.fill.Size = UDim2.fromScale(frac, 1)
	b.bar.Enabled = frac < 1 and frac > 0
end

local function onDied(b)
	if b.dead then
		return
	end
	b.dead = true
	b.bar.Enabled = false
	b.alert.Enabled = false
	local killer = b.lastHitBy
	for currency, amount in pairs(CFG.loot) do
		CrewService.add(currency, amount)
	end
	local parts = {}
	for currency, amount in pairs(CFG.loot) do
		local m = Materials.get(currency)
		table.insert(
			parts,
			string.format("+%d %s", amount, currency == "Coins" and "\u{1F4B0}" or (m and m.icon or currency))
		)
	end
	CrewService.notify(
		string.format(
			"\u{1F417} %s took down a wild boar! %s",
			killer and killer.DisplayName or "Someone",
			table.concat(parts, " ")
		),
		"good"
	)
	CrewService.sfx("Crash", b.root.Position)
	-- keel over, fade, respawn at the den later
	b.root.Anchored = true
	local fallen = b.root.CFrame * CFrame.new(0, -0.8, 0) * CFrame.Angles(0, 0, math.rad(90))
	TweenService:Create(b.root, TweenInfo.new(0.5, Enum.EasingStyle.Quad), { CFrame = fallen }):Play()
	task.delay(3, function()
		for _, d in ipairs(b.model:GetDescendants()) do
			if d:IsA("BasePart") and d.Transparency < 1 then
				TweenService:Create(d, TweenInfo.new(1), { Transparency = 1 }):Play()
			end
		end
		task.wait(1.1)
		b.model:Destroy()
	end)
	task.delay(CFG.respawn, function()
		for i, other in ipairs(boars) do
			if other == b then
				table.remove(boars, i)
				break
			end
		end
		spawnBoar(b.home)
	end)
end

spawnBoar = function(home)
	local y = groundAt(home.X, home.Z)
	local cf = CFrame.new(home.X, y + HIP + 1.3, home.Z) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0)
	local model, root, hum, body, legs, fill, bar, alert = buildBoar(cf)
	model.Parent = folder
	root:SetNetworkOwner(nil)
	local b = {
		model = model,
		root = root,
		hum = hum,
		body = body,
		legs = legs,
		fill = fill,
		bar = bar,
		alert = alert,
		home = Vector3.new(home.X, y, home.Z),
		state = "wander",
		nextWander = 0,
		nextGore = 0,
		untilT = 0,
	}
	hum.HealthChanged:Connect(function()
		setHealthBar(b)
	end)
	hum.Died:Connect(function()
		onDied(b)
	end)
	table.insert(boars, b)
	return b
end

-- AI --------------------------------------------------------------------------------

local function nearestPlayer(pos, within)
	local best, bestD, bestHum
	for _, plr in ipairs(Players:GetPlayers()) do
		local char = plr.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if hrp and hum and hum.Health > 0 and not hum.SeatPart then
			local d = (hrp.Position - pos).Magnitude
			if d < within and (not bestD or d < bestD) then
				best, bestD, bestHum = hrp, d, hum
			end
		end
	end
	return best, bestD, bestHum
end

local function flatAway(from, to)
	local v = Vector3.new(to.X - from.X, 0, to.Z - from.Z)
	return v.Magnitude > 0.01 and v.Unit or Vector3.xAxis
end

local function think(b, now)
	local pos = b.root.Position
	local hum = b.hum
	if b.state == "stagger" then
		if now < b.untilT then
			return
		end
		b.state = "charge"
	end
	if b.state == "backoff" and now < b.untilT then
		return
	end
	local fromHome = (Vector3.new(pos.X, 0, pos.Z) - Vector3.new(b.home.X, 0, b.home.Z)).Magnitude
	local target, dist, targetHum = nearestPlayer(pos, CFG.sight)
	if target and fromHome < CFG.leash then
		if b.state ~= "charge" then
			b.state = "charge"
			b.alert.Enabled = true
			task.delay(1.2, function()
				b.alert.Enabled = false
			end)
			CrewService.sfx("Gust", pos)
		end
		hum.WalkSpeed = CFG.chargeSpeed
		hum:MoveTo(target.Position)
		if dist < CFG.goreRange and now >= b.nextGore then
			b.nextGore = now + CFG.goreCooldown
			targetHum:TakeDamage(CFG.goreDamage)
			CrewService.sfx("Crash", pos)
			-- back off for another run
			b.state = "backoff"
			b.untilT = now + CFG.backOffTime
			hum.WalkSpeed = CFG.backOffSpeed
			hum:MoveTo(pos - flatAway(pos, target.Position) * 12)
		end
		return
	end
	if fromHome > CFG.leash then
		b.state = "return"
		hum.WalkSpeed = 12
		hum:MoveTo(b.home)
		hum.Health = math.min(hum.MaxHealth, hum.Health + 2)
		return
	end
	if b.state ~= "wander" or now >= b.nextWander then
		b.state = "wander"
		b.nextWander = now + rng:NextNumber(3, 7)
		hum.WalkSpeed = CFG.wanderSpeed
		local a = rng:NextNumber(0, math.pi * 2)
		local r = rng:NextNumber(4, 24)
		local gx, gz = b.home.X + math.cos(a) * r, b.home.Z + math.sin(a) * r
		hum:MoveTo(Vector3.new(gx, groundAt(gx, gz), gz))
	end
end

-- Melee weapons --------------------------------------------------------------------

local lastSwing = {}
local function swingGrip(tool, def)
	local base = tool:GetAttribute("BaseGrip")
	if not base then
		base = tool.Grip
		tool:SetAttribute("BaseGrip", base)
	end
	local down = base * CFrame.Angles(math.rad(-70), 0, 0)
	local t = TweenService:Create(tool, TweenInfo.new(def.swing, Enum.EasingStyle.Quad), { Grip = down })
	t:Play()
	t.Completed:Once(function()
		TweenService:Create(tool, TweenInfo.new(def.swing * 1.8, Enum.EasingStyle.Quad), { Grip = base }):Play()
	end)
end

-- the weapon a character is holding (a Tool with a Weapon attribute), and its stats
local function heldWeapon(char)
	for _, t in ipairs(char:GetChildren()) do
		local def = t:IsA("Tool") and Weapons.get(t:GetAttribute("Weapon"))
		if def then
			return t, def
		end
	end
	return nil, nil
end

function BoarService.hit(b, def, fromPos, player)
	if b.dead then
		return
	end
	b.lastHitBy = player
	local away = flatAway(fromPos, b.root.Position)
	b.state = "stagger"
	b.untilT = os.clock() + def.stagger
	b.hum:MoveTo(b.root.Position + away * 3)
	b.root.AssemblyLinearVelocity = away * def.knock + Vector3.new(0, 16, 0)
	-- flash the hide
	local hides = {}
	for _, p in ipairs(b.root.Parent:GetChildren()) do
		if p:IsA("BasePart") and p:GetAttribute("Hide") then
			p.Color = HIT
			table.insert(hides, p)
		end
	end
	task.delay(0.12, function()
		for _, p in ipairs(hides) do
			if p.Parent then
				p.Color = p:GetAttribute("BaseColor")
			end
		end
	end)
	CrewService.sfx("Chop", b.root.Position)
	b.hum:TakeDamage(def.damage)
end

local function onSwing(player)
	local char = player.Character
	local tool, def
	if char then
		tool, def = heldWeapon(char)
	end
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not (tool and hrp and hum and hum.Health > 0) then
		return
	end
	local now = os.clock()
	if lastSwing[player] and now - lastSwing[player] < def.cooldown then
		return
	end
	lastSwing[player] = now
	swingGrip(tool, def)
	local look = hrp.CFrame.LookVector
	for _, b in ipairs(boars) do
		if not b.dead then
			local to = b.root.Position - hrp.Position
			local flat = Vector3.new(to.X, 0, to.Z)
			if
				flat.Magnitude < def.range
				and math.abs(to.Y) < 6
				and (flat.Magnitude < 3 or flat.Unit:Dot(look) > def.arc)
			then
				BoarService.hit(b, def, hrp.Position, player)
			end
		end
	end
end

function BoarService.count()
	local n = 0
	for _, b in ipairs(boars) do
		if not b.dead then
			n += 1
		end
	end
	return n
end

function BoarService.init()
	folder = Instance.new("Folder")
	folder.Name = "Mobs"
	folder.Parent = workspace
	for _, island in pairs(Voyage.Islands) do
		for _, mob in ipairs(island.mobs or {}) do
			if mob.kind == "Boar" then
				for _ = 1, mob.count or 1 do
					spawnBoar(mob.at + Vector3.new(rng:NextNumber(-6, 6), 0, rng:NextNumber(-6, 6)))
				end
			end
		end
	end
	Remotes.get("Swing").OnServerEvent:Connect(onSwing)
	Players.PlayerRemoving:Connect(function(plr)
		lastSwing[plr] = nil
	end)
	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc < 0.15 then
			return
		end
		acc = 0
		local now = os.clock()
		for _, b in ipairs(boars) do
			if not b.dead and b.model.Parent and nearestPlayer(b.root.Position, CFG.activeRange) then
				think(b, now)
			end
		end
	end)
end

return BoarService
