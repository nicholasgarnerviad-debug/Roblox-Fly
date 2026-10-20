-- Sky pickups the pilot flies through. Add a new one here and handle its
-- `kind` in FlightService.applyPowerUp.
local PowerUps = {}

PowerUps.Defs = {
	Shield = {
		display = "Shield",
		icon = "\u{1F6E1}",
		color = Color3.fromRGB(90, 190, 255),
		duration = 12,
		weight = 3, -- weight = spawn frequency
		blurb = "Blocks all damage for 12s",
	},
	Repair = {
		display = "Repair Kit",
		icon = "\u{1F527}",
		color = Color3.fromRGB(120, 230, 120),
		amount = 0.35,
		weight = 3,
		blurb = "Heals every part by 35%",
	},
	Pump = {
		display = "Bilge Pump",
		icon = "\u{1F4A7}",
		color = Color3.fromRGB(70, 140, 255),
		weight = 3,
		blurb = "Drains every puddle",
	},
	Boost = {
		display = "Boost",
		icon = "\u{26A1}",
		color = Color3.fromRGB(255, 220, 60),
		duration = 4,
		weight = 2,
		blurb = "Speed burst!",
	},
	Fuel = {
		display = "Fuel Can",
		icon = "\u{26FD}",
		color = Color3.fromRGB(255, 140, 60),
		amount = 40,
		weight = 2,
		blurb = "+40 fuel",
	},
}

PowerUps.Order = { "Shield", "Repair", "Pump", "Boost", "Fuel" }

function PowerUps.random(rng)
	local total = 0
	for _, name in ipairs(PowerUps.Order) do
		total += PowerUps.Defs[name].weight
	end
	local roll = rng:NextNumber() * total
	for _, name in ipairs(PowerUps.Order) do
		roll -= PowerUps.Defs[name].weight
		if roll <= 0 then
			return name
		end
	end
	return PowerUps.Order[1]
end

return PowerUps
