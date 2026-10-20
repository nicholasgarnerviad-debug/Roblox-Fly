-- The island ladder. The goal of the game is to get as far as you can.
-- Each route = one weather event; intensity climbs the further you go.
-- Every 5th island is a boss island. Islands with built = false are planned content.
local Voyage = {}

Voyage.Islands = {
	[1] = {
		name = "Driftwood Cove",
		built = true,
		center = Vector3.new(0, 0, 0),
		unlocks = { "Wood", "Cloth", "Scrap" },
		hangar = {
			coreCFrame = CFrame.new(0, 52.55, -130), -- plane core spawn, facing -Z
			railLength = 105,
		},
	},
	[2] = {
		name = "Rustbucket Reef",
		built = true,
		center = Vector3.new(0, 0, -2600),
		unlocks = { "Bamboo" },
		runway = { start = Vector3.new(0, 10.5, -2405), length = 330, width = 44, dir = Vector3.new(0, 0, -1) },
		-- the parachute pops within `range` studs of the runway's centreline, below `ceiling` altitude
		parachute = { range = 220, ceiling = 110 },
		spawn = CFrame.new(40, 16, -2640), -- where a landed crew respawns while exploring
		exploreHint = "Follow the lantern trail to the Skylark wreck",
		exploreUnlock = "BalloonReinforce",
		-- everything to discover here (GameState unlock attributes), counted on the explore banner
		finds = { "BalloonReinforce", "Weapon_ScrapCleaver", "Weapon_CaptainsSaber" },
		mobs = { -- wild boar dens in the jungle along the trail (y is found at runtime)
			{ kind = "Boar", at = Vector3.new(-60, 0, -2871) },
			{ kind = "Boar", at = Vector3.new(5, 0, -2965) },
			{ kind = "Boar", at = Vector3.new(-53, 0, -3043), count = 2 },
			{ kind = "Boar", at = Vector3.new(-120, 0, -3150) },
			{ kind = "Boar", at = Vector3.new(-270, 0, -3060) },
			{ kind = "Boar", at = Vector3.new(-305, 0, -2862) }, -- guards the pirate camp
			{ kind = "Boar", at = Vector3.new(150, 0, -2900), count = 2 },
		},
		reward = { Coins = 150, Wood = 15, Cloth = 10, Scrap = 8, Bamboo = 20, Tin = 12 },
	},
	[3] = { name = "Thunderhead Peak", built = false, unlocks = { "Scrap", "Rubber", "Copper" } },
	[4] = { name = "Frostbite Atoll", built = false, unlocks = { "Tin", "Felt" } },
	[5] = { name = "Stormwatch Spire", built = false, boss = true, unlocks = { "Steel" } },
	[6] = { name = "Fogbank Hollow", built = false, unlocks = { "Glass" } },
	[7] = { name = "Cinder Isle", built = false, unlocks = { "Skywood" } },
	[8] = { name = "Hailstone Shelf", built = false, unlocks = { "Aerogel" } },
	[9] = { name = "Mirage Dunes", built = false, unlocks = { "Sunsteel" } },
	[10] = { name = "Skyhaven", built = false, boss = true, unlocks = { "Stormglass" } },
}

-- curve = { {progress, intensity}, ... } piecewise-linear, multiplied by route.intensity.
Voyage.Routes = {
	-- Route 1 is the tutorial hop: short, rain + wind only. Rain fills the decks with water
	-- the crew bails out; wind gently pushes the ship. Rocks and fog come later.
	[1] = {
		from = 1,
		to = 2,
		weather = "Rain",
		intensity = 1.0,
		start = Vector3.new(0, 0, -240),
		finish = Vector3.new(0, 0, -2400),
		curve = { { 0, 0 }, { 0.1, 0.25 }, { 0.3, 1 }, { 0.72, 1 }, { 0.9, 0.15 }, { 1, 0 } },
		-- Pilot challenges, re-rolled every voyage
		hazards = { stormCells = 3, downdrafts = 3 },
		powerUps = 10,
		corridorWidth = 600, -- hazards and pickups spawn within this width of the route line
	},
	[2] = { from = 2, to = 3, weather = "Wind", intensity = 1.4, hazards = { seaStacks = true } },
	[3] = { from = 3, to = 4, weather = "Thunderstorm", intensity = 1.8 },
	[4] = { from = 4, to = 5, weather = "Blizzard", intensity = 2.1, hazards = { fog = true } },
	[5] = { from = 5, to = 6, weather = "SquallKing", intensity = 2.5, boss = true },
}

function Voyage.progress(route, pos)
	local a = Vector3.new(route.start.X, 0, route.start.Z)
	local b = Vector3.new(route.finish.X, 0, route.finish.Z)
	local p = Vector3.new(pos.X, 0, pos.Z)
	local ab = b - a
	local len = ab.Magnitude
	local t = (p - a):Dot(ab.Unit) / len
	local closest = a + ab.Unit * math.clamp(t, 0, 1) * len
	return t, (p - closest).Magnitude, len
end

function Voyage.intensity(route, t)
	local curve = route.curve
	if not curve or t <= 0 or t >= 1 then
		return 0
	end
	for i = 1, #curve - 1 do
		local p0, p1 = curve[i], curve[i + 1]
		if t >= p0[1] and t <= p1[1] then
			local f = (t - p0[1]) / math.max(p1[1] - p0[1], 1e-6)
			return (p0[2] + (p1[2] - p0[2]) * f) * route.intensity
		end
	end
	return 0
end

-- Weather at a world position for a given route index.
function Voyage.weatherAt(routeIndex, pos)
	local route = Voyage.Routes[routeIndex]
	if not route or not route.start then
		return nil, 0, 0
	end
	local t, lateral = Voyage.progress(route, pos)
	local i = Voyage.intensity(route, t)
	-- fade out if far off the route line
	i *= math.clamp(1 - (lateral - 900) / 600, 0, 1)
	return route.weather, i, t
end

return Voyage
