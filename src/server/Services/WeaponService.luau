-- Hands out melee weapons (Shared.Weapons). Weapons found on islands are crew-wide unlocks:
-- each one goes into every player's Backpack and StarterGear (so it survives respawns), and
-- players who join later get it too.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Weapons = require(Shared.Weapons)
local CrewService = require(script.Parent.CrewService)

local WeaponService = {}

local function holds(container, key)
	if not container then
		return false
	end
	for _, t in ipairs(container:GetChildren()) do
		if t:IsA("Tool") and t:GetAttribute("Weapon") == key then
			return true
		end
	end
	return false
end

local function giveTo(player, key)
	local template = ServerStorage.Weapons:FindFirstChild(key)
	if not template then
		warn("[WeaponService] no tool for " .. key)
		return
	end
	local display = Weapons.get(key).display
	local gear = player:FindFirstChild("StarterGear")
	if gear and not holds(gear, key) then
		local g = template:Clone()
		g.Name = display
		g.Parent = gear
	end
	local backpack = player:FindFirstChild("Backpack")
	if backpack and not holds(backpack, key) and not holds(player.Character, key) then
		local b = template:Clone()
		b.Name = display
		b.Parent = backpack
	end
end

function WeaponService.isUnlocked(key)
	local def = Weapons.get(key)
	return def ~= nil and (def.starter or CrewService.state():GetAttribute(Weapons.unlockKey(key)) == true)
end

-- Unlock a weapon for the whole crew. Returns false if it was already found.
function WeaponService.unlock(key)
	if not Weapons.get(key) or WeaponService.isUnlocked(key) then
		return false
	end
	CrewService.state():SetAttribute(Weapons.unlockKey(key), true)
	for _, player in ipairs(Players:GetPlayers()) do
		giveTo(player, key)
	end
	return true
end

function WeaponService.init()
	for key, def in pairs(Weapons.Defs) do
		if not def.starter then
			CrewService.state():SetAttribute(Weapons.unlockKey(key), false)
		end
	end
	local function onPlayer(player)
		for key in pairs(Weapons.Defs) do
			if not Weapons.get(key).starter and WeaponService.isUnlocked(key) then
				giveTo(player, key)
			end
		end
	end
	Players.PlayerAdded:Connect(onPlayer)
	for _, player in ipairs(Players:GetPlayers()) do
		onPlayer(player)
	end
end

return WeaponService
