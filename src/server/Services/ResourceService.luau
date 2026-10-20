-- Gatherable nodes (tag "ResourceNode"). Attributes on the model:
-- Resource, Amount, Respawn, Action, ObjectText
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Materials = require(Shared.Materials)
local CrewService = require(script.Parent.CrewService)

local ResourceService = {}

local SOUNDS = { Wood = "Chop", Cloth = "Splash", Scrap = "Hammer" }

local function setVisible(model, visible)
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			if d:GetAttribute("BaseTransparency") == nil then
				d:SetAttribute("BaseTransparency", d.Transparency)
			end
			d.Transparency = visible and d:GetAttribute("BaseTransparency") or 0.8
		end
	end
end

local function setup(model)
	local anchor = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart")
	if not anchor or anchor:FindFirstChild("GatherPrompt") then
		return
	end
	local resource = model:GetAttribute("Resource")
	local amount = model:GetAttribute("Amount") or 1
	local respawn = model:GetAttribute("Respawn") or 30
	local mat = Materials.get(resource)
	local display = mat and mat.display or resource

	local p = Instance.new("ProximityPrompt")
	p.Name = "GatherPrompt"
	p.ActionText = model:GetAttribute("Action") or "Gather"
	p.ObjectText = string.format("%s  (+%d %s)", model:GetAttribute("ObjectText") or model.Name, amount, display)
	p.HoldDuration = 1.2
	p.MaxActivationDistance = 12
	p.RequiresLineOfSight = false
	p.Parent = anchor

	p.Triggered:Connect(function(player)
		if model:GetAttribute("Depleted") then
			return
		end
		model:SetAttribute("Depleted", true)
		p.Enabled = false
		setVisible(model, false)
		CrewService.add(resource, amount)
		CrewService.notify(
			string.format("%s gathered +%d %s %s", player.DisplayName, amount, mat and mat.icon or "", display),
			"good"
		)
		CrewService.sfx(SOUNDS[resource] or "Hammer", anchor.Position)
		task.delay(respawn, function()
			model:SetAttribute("Depleted", false)
			setVisible(model, true)
			p.Enabled = true
		end)
	end)
end

function ResourceService.init()
	for _, node in ipairs(CollectionService:GetTagged("ResourceNode")) do
		setup(node)
	end
	CollectionService:GetInstanceAddedSignal("ResourceNode"):Connect(setup)
end

return ResourceService
