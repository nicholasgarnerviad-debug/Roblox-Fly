-- Patchwork Skies server bootstrap.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Remotes"))
for _, name in ipairs({
	"BuildAction",
	"PilotInput",
	"Launch",
	"Continue",
	"Notify",
	"Sfx",
	"Gust",
	"VoyageResult",
	"Swing",
}) do
	Remotes.get(name)
end

Players.RespawnTime = 3

local Services = script.Parent:WaitForChild("Services")
local CrewService = require(Services.CrewService)
local PlaneService = require(Services.PlaneService)
local PlaneCare = require(Services.PlaneCare)
local ResourceService = require(Services.ResourceService)
local WeaponService = require(Services.WeaponService)
local ExploreService = require(Services.ExploreService)
local BoarService = require(Services.BoarService)
local FlightService = require(Services.FlightService)

CrewService.init()
PlaneService.init()
PlaneCare.init()
ResourceService.init()
WeaponService.init()
ExploreService.init()
BoarService.init()
FlightService.init()

print("[Patchwork Skies] server ready")
