-- Client-side atmosphere: rain, storm lighting, thunder, wind, camera shake,
-- propeller spin, engine audio and one-shot sound effects.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")
local SoundService = game:GetService("SoundService")
local Debris = game:GetService("Debris")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Voyage = require(Shared.Voyage)
local Weather = require(Shared.Weather)
local PartBuilder = require(Shared.PartBuilder)
local Remotes = require(Shared.Remotes)

local state = ReplicatedStorage:WaitForChild("GameState")
local rng = Random.new()

local Fx = {}

local base = {}
local atm, clouds, cc
local rainPart, rainEmitter
local rainSound, windSound, engineSound
local engineCore
local intensity = 0
local thunderTimer = 8
local flash = 0
local shake = 0
local propAngle = 0
local lastCam

local function lerp(a, b, t)
	return a + (b - a) * t
end

local function loopSound(id, parent)
	local s = Instance.new("Sound")
	s.SoundId = id
	s.Looped = true
	s.Volume = 0
	s.Parent = parent or SoundService
	s:Play()
	return s
end

-- One-shot sounds from the server: where = Vector3 | BasePart | nil (2D)
function Fx.sfx(name, where)
	local id = Config.Sounds[name]
	if not id then
		return
	end
	local s = Instance.new("Sound")
	s.SoundId = id
	s.Volume = Config.SoundVolumes[name] or 0.6
	s.PlaybackSpeed = rng:NextNumber(0.94, 1.06)
	local holder
	if typeof(where) == "Vector3" then
		holder = Instance.new("Attachment")
		holder.WorldPosition = where
		holder.Parent = workspace.Terrain
		s.RollOffMaxDistance = 400
		s.Parent = holder
	elseif typeof(where) == "Instance" and where:IsA("BasePart") and where:IsDescendantOf(workspace) then
		s.RollOffMaxDistance = 400
		s.Parent = where
	else
		s.Parent = SoundService
	end
	s:Play()
	local life = Config.SoundMaxLength[name] or 4
	Debris:AddItem(holder or s, life)
end

local function setupWeather()
	atm = Lighting:FindFirstChildOfClass("Atmosphere")
	clouds = workspace.Terrain:FindFirstChildOfClass("Clouds")
	base = {
		brightness = Lighting.Brightness,
		ambient = Lighting.OutdoorAmbient,
		density = atm and atm.Density or 0.3,
		haze = atm and atm.Haze or 1,
		atmColor = atm and atm.Color or Color3.new(1, 1, 1),
		cover = clouds and clouds.Cover or 0.5,
		cloudDensity = clouds and clouds.Density or 0.6,
		cloudColor = clouds and clouds.Color or Color3.new(1, 1, 1),
	}
	cc = Instance.new("ColorCorrectionEffect")
	cc.Name = "StormGrade"
	cc.Parent = Lighting

	rainPart = Instance.new("Part")
	rainPart.Name = "RainEmitter"
	rainPart.Anchored = true
	rainPart.CanCollide = false
	rainPart.CanQuery = false
	rainPart.CanTouch = false
	rainPart.Transparency = 1
	rainPart.Size = Vector3.new(110, 1, 110)
	rainPart.Parent = workspace.CurrentCamera
	rainEmitter = Instance.new("ParticleEmitter")
	rainEmitter.EmissionDirection = Enum.NormalId.Bottom
	rainEmitter.Rate = 0
	rainEmitter.Speed = NumberRange.new(130, 150)
	rainEmitter.Lifetime = NumberRange.new(0.55, 0.7)
	rainEmitter.Size = NumberSequence.new(0.5)
	rainEmitter.Squash = NumberSequence.new(2.8)
	rainEmitter.Orientation = Enum.ParticleOrientation.FacingCameraWorldUp
	rainEmitter.Color = ColorSequence.new(Color3.fromRGB(200, 220, 245))
	rainEmitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.15, 0.35),
		NumberSequenceKeypoint.new(1, 0.35),
	})
	rainEmitter.LightEmission = 0.5
	rainEmitter.Brightness = 2
	rainEmitter.LockedToPart = true
	rainEmitter.Parent = rainPart

	rainSound = loopSound(Config.Sounds.Rain)
	windSound = loopSound(Config.Sounds.Wind)
end

local function stormIntensityAt(pos)
	local hz = workspace:FindFirstChild("Hazards")
	local extra = 0
	if hz then
		for _, m in ipairs(hz:GetChildren()) do
			if m.Name == "StormCell" then
				local col = m:FindFirstChild("Column")
				if col then
					local r = col.Size.Y / 2
					local d = Vector2.new(pos.X - col.Position.X, pos.Z - col.Position.Z).Magnitude
					if d < r then
						extra = math.max(extra, 1.2 * (1 - d / r * 0.5))
					end
				end
			end
		end
	end
	return extra
end

local function updateWeather(dt)
	local cam = workspace.CurrentCamera
	local camPos = cam.CFrame.Position
	local camVel = lastCam and (camPos - lastCam) / math.max(dt, 1 / 240) or Vector3.zero
	lastCam = camPos
	if camVel.Magnitude > 400 then
		camVel = Vector3.zero
	end
	local routeIndex = state:GetAttribute("Route") or 1
	local wtype, target = Voyage.weatherAt(routeIndex, camPos)
	target = (target or 0) + stormIntensityAt(camPos)
	local def = wtype and Weather.get(wtype)
	local cl = def and def.client or {}
	intensity = lerp(intensity, target, math.min(1, dt * 0.7))
	local k = math.clamp(intensity, 0, 1.4)
	local kk = math.min(k, 1)

	Lighting.Brightness = lerp(base.brightness, cl.brightness or base.brightness, kk) + flash * 3
	Lighting.OutdoorAmbient = base.ambient:Lerp(Color3.fromRGB(95, 100, 115), kk * 0.8)
	if atm then
		atm.Density = lerp(base.density, cl.density or base.density, kk)
		atm.Haze = lerp(base.haze, cl.haze or base.haze, kk)
		atm.Color = base.atmColor:Lerp(cl.atmosphereColor or base.atmColor, kk)
	end
	if clouds then
		clouds.Cover = lerp(base.cover, cl.cloudCover or base.cover, kk)
		clouds.Density = lerp(base.cloudDensity, cl.cloudDensity or base.cloudDensity, kk)
		clouds.Color = base.cloudColor:Lerp(cl.cloudColor or base.cloudColor, kk)
	end
	cc.Saturation = -0.3 * kk
	cc.Contrast = 0.05 * kk
	cc.Brightness = flash * 0.5
	flash = math.max(0, flash - dt * 4)

	rainEmitter.Rate = (cl.rain or 0) * k
	rainPart.CFrame = CFrame.new(camPos + Vector3.new(0, 45, 0) + Vector3.new(camVel.X, 0, camVel.Z) * 0.35)
	rainSound.Volume = lerp(rainSound.Volume, (cl.rainVolume or 0) * k, math.min(1, dt * 2))
	local phase = state:GetAttribute("Phase")
	local airborne = phase == "Flying" or phase == "Launching" or phase == "Landing"
	local windTarget = (airborne and 0.12 or 0.03) + (cl.windVolume or 0) * k
	windSound.Volume = lerp(windSound.Volume, windTarget, math.min(1, dt * 2))

	if cl.thunderEvery and k > 0.55 then
		thunderTimer -= dt
		if thunderTimer <= 0 then
			thunderTimer = rng:NextNumber(cl.thunderEvery[1], cl.thunderEvery[2])
			flash = 0.35
			task.delay(rng:NextNumber(0.3, 1.2), function()
				Fx.sfx("Thunder")
			end)
		end
	end
end

local function updatePlane(dt)
	local m = workspace:FindFirstChild("CrewPlane")
	if not m or not m.PrimaryPart then
		return
	end
	local phase = state:GetAttribute("Phase")
	local airborne = phase == "Flying" or phase == "Launching" or phase == "Landing"
	local thr = m:GetAttribute("Throttle") or 1
	local pilotIn = (m:GetAttribute("Pilot") or "") ~= ""
	local boosting = m:GetAttribute("Boosting") or (m:GetAttribute("BoostTime") or 0) > 0
	local rate = airborne and (16 + 26 * thr + (boosting and 14 or 0)) or (pilotIn and 7 or 0)
	if airborne and (m:GetAttribute("Fuel") or 1) <= 0 then
		rate = 3
	end
	propAngle += rate * dt
	for _, cellModel in ipairs(m:GetChildren()) do
		local hub = cellModel:FindFirstChild("PropHub")
		local weld = hub and hub:FindFirstChild("PropWeld")
		if weld then
			local main = cellModel:FindFirstChild("Main")
			local a = propAngle
			if main and main:GetAttribute("Sputter") then
				a = propAngle * 0.25 + math.sin(os.clock() * 25) * 0.4
			end
			weld.C0 = (weld:GetAttribute("BaseC0") or PartBuilder.PROP_OFFSET) * CFrame.Angles(0, 0, a)
		end
	end
	-- engine audio follows the current plane core
	if engineCore ~= m.PrimaryPart then
		if engineSound then
			engineSound:Destroy()
		end
		engineCore = m.PrimaryPart
		engineSound = loopSound(Config.Sounds.Engine, engineCore)
		engineSound.RollOffMaxDistance = 600
	end
	local vol = airborne and 0.55 or (pilotIn and 0.2 or 0)
	if (m:GetAttribute("Engines") or 0) == 0 then
		vol = 0
	end
	engineSound.Volume = lerp(engineSound.Volume, vol, math.min(1, dt * 3))
	engineSound.PlaybackSpeed = 0.75 + 0.45 * (airborne and thr or 0.2) + (boosting and 0.2 or 0)
end

local function applyShake()
	if shake <= 0.01 then
		return
	end
	local cam = workspace.CurrentCamera
	local t = os.clock() * 30
	local a = math.rad(shake * 2.2)
	cam.CFrame = cam.CFrame * CFrame.Angles(math.noise(t, 1) * a, math.noise(t, 2) * a, math.noise(t, 3) * a)
end

function Fx.start()
	setupWeather()
	Remotes.get("Sfx").OnClientEvent:Connect(Fx.sfx)
	Remotes.get("Gust").OnClientEvent:Connect(function(amount)
		shake = math.max(shake, (amount or 1) * 1.2)
	end)
	RunService.RenderStepped:Connect(function(dt)
		updateWeather(dt)
		updatePlane(dt)
		shake = math.max(0, shake - dt * 2)
	end)
	RunService:BindToRenderStep("GustShake", Enum.RenderPriority.Camera.Value + 1, applyShake)
end

return Fx
