-- Exploring islands on foot: discoveries (parts tagged "Discovery" with an Unlock attribute,
-- plus a Weapon attribute for weapon finds) and respawning on the island the crew has landed
-- at instead of back home.
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local PartTypes = require(Shared.PartTypes)
local Voyage = require(Shared.Voyage)
local Weapons = require(Shared.Weapons)
local CrewService = require(script.Parent.CrewService)
local WeaponService = require(script.Parent.WeaponService)

local ExploreService = {}

-- Where a landed crew respawns (nil = the normal spawn at the home hangar).
function ExploreService.islandSpawn()
	if CrewService.getPhase() ~= "Landed" then
		return nil
	end
	local route = Voyage.Routes[CrewService.get("Route")]
	local island = route and Voyage.Islands[route.to]
	return island and island.spawn
end

local function setBeacons(unlock, on)
	for _, d in ipairs(workspace.World:GetDescendants()) do
		if d:IsA("BasePart") and d:GetAttribute("BeaconFor") == unlock then
			d.Transparency = on and 0.55 or 1
		end
	end
end

-- What a discovery unlocks, for the announcement.
local function describe(unlock)
	for typeName, rf in pairs(PartTypes.Reinforce) do
		if rf.unlock == unlock then
			return string.format(
				"Back at the hangar, hammer a %s and pick %s %s.",
				PartTypes.get(typeName).display,
				rf.icon,
				rf.display
			)
		end
	end
	return ""
end

-- A weapon find shows the weapon itself on its stand; it vanishes once taken.
local function showDisplay(part, visible)
	local display = part:FindFirstAncestorWhichIsA("Model")
	if not display or not display:GetAttribute("WeaponDisplay") then
		return
	end
	for _, d in ipairs(display:GetDescendants()) do
		if d:IsA("BasePart") then
			if d:GetAttribute("BaseTransparency") == nil then
				d:SetAttribute("BaseTransparency", d.Transparency)
			end
			d.Transparency = visible and d:GetAttribute("BaseTransparency") or 1
		end
	end
end

local function setupDiscovery(part)
	local unlock = part:GetAttribute("Unlock")
	if not unlock or part:FindFirstChild("DiscoverPrompt") then
		return
	end
	local weapon = part:GetAttribute("Weapon")
	local title = part:GetAttribute("Title") or unlock
	local p = Instance.new("ProximityPrompt")
	p.Name = "DiscoverPrompt"
	p.ActionText = part:GetAttribute("Action") or "Study the Plans"
	p.ObjectText = title
	p.HoldDuration = weapon and 1.2 or 2.5
	p.MaxActivationDistance = 10
	p.RequiresLineOfSight = false
	p.Parent = part
	local state = CrewService.state()
	local function refresh()
		local found = state:GetAttribute(unlock) == true
		p.Enabled = not found
		setBeacons(unlock, not found)
		showDisplay(part, not found)
		local sparkle = part:FindFirstChild("Sparkle")
		if sparkle then
			sparkle.Enabled = not found
		end
	end
	p.Triggered:Connect(function(player)
		if state:GetAttribute(unlock) then
			return
		end
		if weapon then
			if WeaponService.unlock(weapon) then
				local def = Weapons.get(weapon)
				CrewService.notify(
					string.format(
						"\u{2694} %s found the %s! Everyone has one in their backpack now. %s",
						player.DisplayName,
						def.display,
						def.blurb
					),
					"good"
				)
				CrewService.sfx("Fanfare", part.Position)
			end
			return
		end
		state:SetAttribute(unlock, true)
		CrewService.notify(
			string.format("\u{1F388} %s found the %s plans! %s", player.DisplayName, title, describe(unlock)),
			"good"
		)
		CrewService.sfx("Fanfare", part.Position)
	end)
	state:GetAttributeChangedSignal(unlock):Connect(refresh)
	refresh()
end

local function onCharacter(character)
	task.defer(function()
		local cf = ExploreService.islandSpawn()
		if cf and character.Parent then
			character:PivotTo(cf * CFrame.new(math.random(-6, 6), 0, math.random(-6, 6)))
		end
	end)
end

local function onPlayer(player)
	player.CharacterAdded:Connect(onCharacter)
end

function ExploreService.init()
	for _, part in ipairs(CollectionService:GetTagged("Discovery")) do
		setupDiscovery(part)
	end
	CollectionService:GetInstanceAddedSignal("Discovery"):Connect(setupDiscovery)
	for _, player in ipairs(Players:GetPlayers()) do
		onPlayer(player)
	end
	Players.PlayerAdded:Connect(onPlayer)
end

return ExploreService
