-- Melee weapon swings (any Tool with a Weapon attribute; the server does the hit detection)
-- and the wild boars' trot animation, which runs locally so leg welds never replicate.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Remotes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Remotes"))

local player = Players.LocalPlayer

local Combat = {}

local ANIMATE_RANGE = 160
local baseC0 = setmetatable({}, { __mode = "k" })
local walkPhase = setmetatable({}, { __mode = "k" })

local function hookTool(tool)
	if tool:IsA("Tool") and tool:GetAttribute("Weapon") and not tool:GetAttribute("Hooked") then
		tool:SetAttribute("Hooked", true)
		tool.Activated:Connect(function()
			Remotes.get("Swing"):FireServer()
		end)
	end
end

local function onCharacter(char)
	for _, c in ipairs(char:GetChildren()) do
		hookTool(c)
	end
	char.ChildAdded:Connect(hookTool)
end

local function animateBoars(dt)
	local mobs = workspace:FindFirstChild("Mobs")
	local cam = workspace.CurrentCamera
	if not mobs or not cam then
		return
	end
	local camPos = cam.CFrame.Position
	for _, boar in ipairs(mobs:GetChildren()) do
		local root = boar.PrimaryPart
		if root and (root.Position - camPos).Magnitude < ANIMATE_RANGE then
			local v = root.AssemblyLinearVelocity
			local speed = Vector3.new(v.X, 0, v.Z).Magnitude
			local t = (walkPhase[boar] or 0) + dt * math.clamp(speed, 0, 24) * 0.55
			walkPhase[boar] = t
			local amp = root.Anchored and 0 or math.clamp(speed / 10, 0, 1) * math.rad(32)
			for _, leg in ipairs(boar:GetChildren()) do
				if leg.Name == "Leg" then
					local hip = leg:FindFirstChild("Hip")
					if hip then
						baseC0[hip] = baseC0[hip] or hip.C0
						hip.C0 = baseC0[hip] * CFrame.Angles(math.sin(t + (leg:GetAttribute("Phase") or 0)) * amp, 0, 0)
					end
				end
			end
		end
	end
end

function Combat.start()
	if player.Character then
		onCharacter(player.Character)
	end
	player.CharacterAdded:Connect(onCharacter)
	RunService.RenderStepped:Connect(animateBoars)
end

return Combat
