-- Crew-wide state: shared materials, game phase, voyage stats and alerts.
-- Replicated to clients as attributes on ReplicatedStorage.GameState.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Materials = require(Shared.Materials)
local Remotes = require(Shared.Remotes)

local CrewService = {}

local state
local stats = {}

function CrewService.init()
	state = Instance.new("Folder")
	state.Name = "GameState"
	for k, v in pairs(Config.StartInventory) do
		state:SetAttribute(k, v)
	end
	state:SetAttribute("Phase", "Build")
	state:SetAttribute("Island", 1) -- island the crew is currently at / departed from
	state:SetAttribute("Route", 1)
	state:SetAttribute("UnlockedIsland", 1) -- materials unlocked up to this island
	state:SetAttribute("FurthestIsland", 1)
	state:SetAttribute("BalloonReinforce", false) -- found at the Skylark wreck (Rustbucket Reef)
	state:SetAttribute("Voyages", 0)
	state.Parent = ReplicatedStorage
	CrewService.resetStats()
end

function CrewService.state()
	return state
end

function CrewService.get(name)
	return state:GetAttribute(name) or 0
end

function CrewService.add(name, amount)
	state:SetAttribute(name, CrewService.get(name) + amount)
end

function CrewService.spend(name, amount)
	if CrewService.get(name) < amount then
		return false
	end
	CrewService.add(name, -amount)
	return true
end

function CrewService.getPhase()
	return state:GetAttribute("Phase")
end

function CrewService.setPhase(phase)
	state:SetAttribute("Phase", phase)
end

function CrewService.isMaterialUnlocked(name)
	local def = Materials.get(name)
	return def ~= nil and def.unlockedAtIsland <= CrewService.get("UnlockedIsland")
end

-- Can the Hammer upgrade pieces into this material yet? (One new tier per island.)
function CrewService.isUpgradeUnlocked(name)
	local island = Materials.upgradeIsland(name)
	return island ~= nil and island <= CrewService.get("UnlockedIsland")
end

-- kind: "info" | "good" | "warn" | "danger"
function CrewService.notify(text, kind, player)
	local remote = Remotes.get("Notify")
	if player then
		remote:FireClient(player, text, kind or "info")
	else
		remote:FireAllClients(text, kind or "info")
	end
end

-- Ask every client to play a sound (optionally at a world position or attached to a part).
function CrewService.sfx(name, where)
	Remotes.get("Sfx"):FireAllClients(name, where)
end

function CrewService.resetStats()
	stats = { puddles = 0, repairs = 0, restarts = 0, partsLost = 0, powerUps = 0, hits = 0, started = os.clock() }
end

function CrewService.stat(name, amount)
	stats[name] = (stats[name] or 0) + (amount or 1)
end

function CrewService.getStats()
	return stats
end

return CrewService
