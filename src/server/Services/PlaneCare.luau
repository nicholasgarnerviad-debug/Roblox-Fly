-- The crew's side of the game: damage, repairs, puddles, soaking, sputtering
-- engines and the ProximityPrompts the crew uses to fix them.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Materials = require(Shared.Materials)
local PartTypes = require(Shared.PartTypes)
local CrewService = require(script.Parent.CrewService)
local PlaneService = require(script.Parent.PlaneService)

local PlaneCare = {}

PlaneCare.shieldCheck = function()
	return false
end
PlaneCare.onCoreDestroyed = nil

local PUDDLE_COLOR = Color3.fromRGB(70, 140, 220)
local PUMP_DRAIN = 0.5 -- each crank lowers every puddle by half
local PUMP_RECHARGE = 6
local DAMAGE_TINT = Color3.fromRGB(35, 30, 28)
local WET_TINT = Color3.fromRGB(40, 50, 70)

local function flying()
	return CrewService.getPhase() == "Flying" or CrewService.getPhase() == "Launching"
end

local function prompt(parent, name, action, object, hold, key, pad)
	local p = Instance.new("ProximityPrompt")
	p.Name = name
	p.ActionText = action
	p.ObjectText = object
	p.HoldDuration = hold
	p.KeyboardKeyCode = key
	p.GamepadKeyCode = pad
	p.MaxActivationDistance = 11
	p.RequiresLineOfSight = false
	p.Style = Enum.ProximityPromptStyle.Default
	p.Parent = parent
	return p
end

function PlaneCare.refresh(rec)
	if not rec.main.Parent then
		return
	end
	local frac = rec.hp / rec.maxHp
	local def = PartTypes.get(rec.type)
	rec.main:SetAttribute("HP", rec.hp)
	if rec.repairPrompt then
		rec.repairPrompt.Enabled = flying() and frac < 0.98
		rec.repairPrompt.ObjectText = string.format("%s  %d%%", def.display, math.floor(frac * 100))
	end
	local smoke = rec.main:FindFirstChild("DamageSmoke")
	if frac < 0.6 then
		if not smoke then
			smoke = Instance.new("Smoke")
			smoke.Name = "DamageSmoke"
			smoke.Size = 2.5
			smoke.RiseVelocity = 4
			smoke.Parent = rec.main
		end
		smoke.Color = frac < 0.3 and Color3.fromRGB(45, 45, 45) or Color3.fromRGB(170, 170, 170)
		smoke.Opacity = frac < 0.3 and 0.4 or 0.18
	elseif smoke then
		smoke:Destroy()
	end
	PlaneCare.tint(rec)
end

-- Darken every visible piece of a part by soak and damage.
function PlaneCare.tint(rec)
	local frac = rec.hp / rec.maxHp
	local wet = 0.3 * rec.soak
	local hurt = (1 - frac) * 0.55
	for _, d in ipairs(rec.model:GetDescendants()) do
		if d:IsA("BasePart") and d.Transparency < 1 and d.Material ~= Enum.Material.Neon and d.Name ~= "Puddle" then
			local base = d:GetAttribute("BaseColor")
			if not base then
				base = d.Color
				d:SetAttribute("BaseColor", base)
			end
			d.Color = base:Lerp(WET_TINT, wet):Lerp(DAMAGE_TINT, hurt)
		end
	end
end

function PlaneCare.refreshAll()
	for _, rec in pairs(PlaneService.cells) do
		PlaneCare.refresh(rec)
		if rec.restartPrompt then
			rec.restartPrompt.Enabled = rec.sputter and flying()
		end
	end
end

-- Returns true if damage was applied.
function PlaneCare.damage(rec, amount, reason)
	if not rec or PlaneService.cells[rec.key] ~= rec then
		return false
	end
	if PlaneCare.shieldCheck() then
		return false
	end
	rec.hp = math.max(0, rec.hp - amount)
	if rec.hp <= 0 then
		if rec.type == "Core" then
			if PlaneCare.onCoreDestroyed then
				PlaneCare.onCoreDestroyed(reason)
			end
		else
			CrewService.notify(PartTypes.get(rec.type).display .. " broke off!", "danger")
			CrewService.sfx("Crash", rec.main.Position)
			PlaneService.breakOff(rec.key, PlaneService.core.AssemblyLinearVelocity)
			return true
		end
	end
	PlaneCare.refresh(rec)
	PlaneService.recompute()
	return true
end

function PlaneCare.repair(rec, amountFrac, player)
	if PlaneService.cells[rec.key] ~= rec then
		return
	end
	rec.hp = math.min(rec.maxHp, rec.hp + rec.maxHp * amountFrac)
	PlaneCare.refresh(rec)
	PlaneService.recompute()
	if player then
		CrewService.stat("repairs")
		CrewService.sfx("Hammer", rec.main)
	end
end

function PlaneCare.repairAll(frac)
	for _, rec in pairs(PlaneService.cells) do
		rec.hp = math.min(rec.maxHp, rec.hp + rec.maxHp * frac)
		PlaneCare.refresh(rec)
	end
	PlaneService.recompute()
end

function PlaneCare.setSputter(rec, on)
	if rec.type ~= "Engine" or rec.sputter == on then
		return
	end
	rec.sputter = on
	rec.main:SetAttribute("Sputter", on)
	if rec.restartPrompt then
		rec.restartPrompt.Enabled = on and flying()
	end
	local puff = rec.main:FindFirstChild("SputterSmoke")
	if on and not puff then
		puff = Instance.new("Smoke")
		puff.Name = "SputterSmoke"
		puff.Color = Color3.fromRGB(20, 20, 20)
		puff.Opacity = 0.5
		puff.Size = 1.5
		puff.RiseVelocity = 2
		puff.Parent = rec.main
	elseif not on and puff then
		puff:Destroy()
	end
	PlaneService.recompute()
end

-- Puddles ---------------------------------------------------------------

function PlaneCare.addPuddle(rec)
	if rec.puddle or not rec.main.Parent then
		return
	end
	local part = Instance.new("Part")
	part.Name = "Puddle"
	part.Shape = Enum.PartType.Cylinder
	part.Size = Vector3.new(0.12, 1.2, 1.2)
	part.Material = Enum.Material.Glass
	part.Color = PUDDLE_COLOR
	part.Transparency = 0.25
	part.Reflectance = 0.15
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Massless = true
	part.CFrame = rec.main.CFrame
		* CFrame.new(math.random(-8, 8) / 10, rec.main.Size.Y / 2 + 0.14, math.random(-8, 8) / 10)
		* CFrame.Angles(0, 0, math.rad(90))
	local w = Instance.new("WeldConstraint")
	w.Part0 = rec.main
	w.Part1 = part
	w.Parent = part
	part.Parent = rec.model
	local p = prompt(part, "BailPrompt", "Bail Water", "Puddle", 0.7, Enum.KeyCode.E, Enum.KeyCode.ButtonX)
	p.Triggered:Connect(function(player)
		PlaneCare.removePuddle(rec, player)
	end)
	rec.puddle = { part = part, level = 0.05, prompt = p }
end

function PlaneCare.removePuddle(rec, player)
	local pud = rec.puddle
	if not pud then
		return
	end
	rec.puddle = nil
	CrewService.sfx("Splash", pud.part.Position)
	pud.part:Destroy()
	if player then
		CrewService.stat("puddles")
	end
end

-- Bilge pump station: lowers every puddle by `amount` (0..1); empties the small ones.
function PlaneCare.pumpAll(amount, player)
	local removed = 0
	for _, rec in pairs(PlaneService.cells) do
		local pud = rec.puddle
		if pud then
			pud.level -= amount
			if pud.level <= 0.05 then
				PlaneCare.removePuddle(rec)
				removed += 1
			end
		end
	end
	if player then
		CrewService.stat("puddles", removed)
	end
	return removed
end

function PlaneCare.drainAll()
	for _, rec in pairs(PlaneService.cells) do
		if rec.puddle then
			PlaneCare.removePuddle(rec)
		end
	end
	PlaneService.waterWeight = 0
	PlaneService.recompute()
end

function PlaneCare.puddleCount()
	local n = 0
	for _, rec in pairs(PlaneService.cells) do
		if rec.puddle then
			n += 1
		end
	end
	return n
end

function PlaneCare.tickPuddles(dt, growTime, fullWeight)
	local total = 0
	for _, rec in pairs(PlaneService.cells) do
		local pud = rec.puddle
		if pud then
			pud.level = math.min(1, pud.level + dt / growTime)
			local d = 1.2 + 2.6 * pud.level
			pud.part.Size = Vector3.new(0.12, d, d)
			pud.prompt.ObjectText = string.format("Puddle  %d%%", math.floor(pud.level * 100))
			total += pud.level * fullWeight
		end
	end
	PlaneService.waterWeight = total
end

-- Soaking: rate > 0 soaks, rate < 0 dries.
local tintTimer = 0
function PlaneCare.tickSoak(dt, rate)
	tintTimer += dt
	local retint = tintTimer >= 2
	if retint then
		tintTimer = 0
	end
	for _, rec in pairs(PlaneService.cells) do
		if Materials.get(rec.material).soak > 0 then
			local before = rec.soak
			rec.soak = math.clamp(rec.soak + rate * dt, 0, 1)
			if rec.soak ~= before then
				rec.main:SetAttribute("Soak", rec.soak)
				rec.soakDirty = true
			end
			if retint and rec.soakDirty then
				rec.soakDirty = false
				PlaneCare.tint(rec)
			end
		end
	end
end

function PlaneCare.averageSoak()
	local sum, n = 0, 0
	for _, rec in pairs(PlaneService.cells) do
		if Materials.get(rec.material).soak > 0 then
			sum += rec.soak
			n += 1
		end
	end
	return n > 0 and sum / n or 0
end

-- Damage helpers ----------------------------------------------------------

function PlaneCare.randomParts(count, includeCore)
	local pool = {}
	for _, rec in pairs(PlaneService.cells) do
		if includeCore or rec.type ~= "Core" then
			table.insert(pool, rec)
		end
	end
	local picked = {}
	for _ = 1, math.min(count, #pool) do
		table.insert(picked, table.remove(pool, math.random(1, #pool)))
	end
	return picked
end

-- Damage everything within radius of a world position (falls off with distance).
function PlaneCare.damageNear(position, radius, amount, reason)
	local hits = {}
	for _, rec in pairs(PlaneService.cells) do
		local d = (rec.main.Position - position).Magnitude
		if d <= radius then
			table.insert(hits, { rec = rec, f = 1 - d / radius * 0.6 })
		end
	end
	for _, h in ipairs(hits) do
		PlaneCare.damage(h.rec, amount * h.f, reason)
	end
	return #hits
end

function PlaneCare.engines()
	local list = {}
	for _, rec in pairs(PlaneService.cells) do
		if rec.type == "Engine" then
			table.insert(list, rec)
		end
	end
	return list
end

-- Cannons -------------------------------------------------------------------

local function blast(position, radius)
	local ex = Instance.new("Explosion")
	ex.Position = position
	ex.BlastPressure = 0
	ex.BlastRadius = radius
	ex.DestroyJointRadiusPercent = 0
	ex.Parent = workspace
end

-- Cosmetic for now; boss fights will listen for these hits later.
function PlaneCare.fireCannon(rec)
	local muzzle = rec.model:FindFirstChild("Muzzle")
	if not muzzle then
		return
	end
	local cf = muzzle.CFrame
	local ball = Instance.new("Part")
	ball.Name = "Cannonball"
	ball.Shape = Enum.PartType.Ball
	ball.Size = Vector3.new(1.3, 1.3, 1.3)
	ball.Material = Enum.Material.Metal
	ball.Color = Color3.fromRGB(30, 30, 32)
	ball.CanCollide = false
	ball.CanQuery = false
	ball.CFrame = cf * CFrame.new(0, 0, -1)
	ball.Parent = workspace
	ball:SetNetworkOwner(nil)
	ball.AssemblyLinearVelocity = rec.main.AssemblyLinearVelocity + cf.LookVector * 190 + Vector3.new(0, 12, 0)
	local done = false
	ball.Touched:Connect(function(hit)
		if done or (PlaneService.model and hit:IsDescendantOf(PlaneService.model)) then
			return
		end
		if hit.Parent and hit.Parent:FindFirstChildOfClass("Humanoid") then
			return
		end
		done = true
		blast(ball.Position, 6)
		CrewService.sfx("Crash", ball.Position)
		ball:Destroy()
	end)
	Debris:AddItem(ball, 5)
	blast(cf.Position, 0)
	CrewService.sfx("Crash", cf.Position)
end

-- Hook up prompts when a cell spawns ---------------------------------------

local function attach(rec)
	local def = PartTypes.get(rec.type)
	-- high pieces (balloons on their tethers) are worked on from a reachable point below
	local anchor = rec.main:FindFirstChild("PromptPoint") or rec.main
	local rp = prompt(anchor, "RepairPrompt", "Repair", def.display, 1.1, Enum.KeyCode.E, Enum.KeyCode.ButtonX)
	rp.Enabled = false
	rp.Triggered:Connect(function(player)
		PlaneCare.repair(rec, 0.35, player)
	end)
	rec.repairPrompt = rp

	if rec.type == "Engine" then
		local sp = prompt(
			rec.main,
			"RestartPrompt",
			"Restart Engine",
			"Sputtering!",
			1.6,
			Enum.KeyCode.F,
			Enum.KeyCode.ButtonY
		)
		sp.Enabled = false
		sp.UIOffset = Vector2.new(0, 60)
		sp.Triggered:Connect(function(player)
			if rec.sputter then
				PlaneCare.setSputter(rec, false)
				CrewService.stat("restarts")
				CrewService.notify(player.DisplayName .. " got the engine running again!", "good")
			end
		end)
		rec.restartPrompt = sp
	end

	if rec.type == "Pump" then
		local pp = prompt(rec.main, "PumpPrompt", "Pump Bilge", "Bilge Pump", 1.5, Enum.KeyCode.F, Enum.KeyCode.ButtonY)
		pp.UIOffset = Vector2.new(0, 60)
		pp.MaxActivationDistance = 9
		pp.Triggered:Connect(function(player)
			if CrewService.getPhase() ~= "Flying" then
				CrewService.notify("The bilge is dry. Save it for the storm!", "info", player)
				return
			end
			local n = PlaneCare.pumpAll(PUMP_DRAIN, player)
			CrewService.sfx("Splash", rec.main)
			CrewService.notify(
				string.format(
					"%s cranked the bilge pump! Every puddle drained by half (%d emptied)",
					player.DisplayName,
					n
				),
				"good"
			)
			pp.Enabled = false
			pp.ObjectText = "Recharging..."
			local light = rec.model:FindFirstChild("Indicator")
			if light then
				light.Color = Color3.fromRGB(235, 70, 60)
			end
			task.delay(PUMP_RECHARGE, function()
				if pp.Parent then
					pp.Enabled = true
					pp.ObjectText = "Bilge Pump"
					if light then
						light.Color = Color3.fromRGB(90, 230, 110)
					end
				end
			end)
		end)
	end

	if rec.type == "Cannon" then
		local fp = prompt(rec.main, "FirePrompt", "Fire!", "Cannon", 0.25, Enum.KeyCode.F, Enum.KeyCode.ButtonY)
		fp.UIOffset = Vector2.new(0, 60)
		fp.MaxActivationDistance = 9
		fp.Triggered:Connect(function(player)
			local phase = CrewService.getPhase()
			if phase ~= "Flying" and phase ~= "Landing" and phase ~= "Launching" then
				CrewService.notify("Save the cannonballs for the sky!", "info", player)
				return
			end
			PlaneCare.fireCannon(rec)
			fp.Enabled = false
			fp.ObjectText = "Reloading..."
			task.delay(2.5, function()
				if fp.Parent then
					fp.Enabled = true
					fp.ObjectText = "Cannon"
				end
			end)
		end)
	end

	local seat = rec.model:FindFirstChild("PilotSeat") or rec.model:FindFirstChild("CrewSeat")
	if seat then
		local isPilot = seat.Name == "PilotSeat"
		local sit = prompt(
			seat,
			"SitPrompt",
			isPilot and "Take the Controls" or "Sit",
			isPilot and "Pilot Seat" or "Crew Seat",
			0,
			Enum.KeyCode.E,
			Enum.KeyCode.ButtonX
		)
		sit.MaxActivationDistance = 9
		sit.Triggered:Connect(function(player)
			local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
			if hum and hum.Health > 0 and not seat.Occupant and not hum.SeatPart then
				seat:Sit(hum)
			end
		end)
		seat:GetPropertyChangedSignal("Occupant"):Connect(function()
			sit.Enabled = seat.Occupant == nil
		end)
	end
end

local function detach(rec)
	if rec.puddle then
		rec.puddle.part:Destroy()
		rec.puddle = nil
	end
end

-- Hammer hits from the crew: small, quick patches (the prompt does bigger, slower ones).
local lastHammer = {}
local function hammerRepair(rec, player)
	local now = os.clock()
	if lastHammer[player] and now - lastHammer[player] < 0.35 then
		return
	end
	lastHammer[player] = now
	PlaneCare.repair(rec, 0.12, player)
end

function PlaneCare.init()
	PlaneService.onCellAdded = attach
	PlaneService.onCellRemoved = detach
	PlaneService.repairHook = hammerRepair
	CrewService.state():GetAttributeChangedSignal("Phase"):Connect(PlaneCare.refreshAll)
end

return PlaneCare
