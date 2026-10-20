-- Global tuning values shared by server and client.
local Config = {}

Config.GAME_NAME = "Patchwork Skies"

-- Plane grid
Config.CELL = 4 -- studs per build cell
Config.BUILD_BOUNDS = { minX = -8, maxX = 8, minY = 0, maxY = 6, minZ = -10, maxZ = 11 }
Config.MAX_PARTS = 400

-- World
Config.WATER_LEVEL = 0

-- Crew inventory at the start of a session
Config.StartInventory = { Wood = 60, Cloth = 30, Scrap = 20, Bamboo = 0, Tin = 0, Coins = 0 }
Config.Currencies = { "Wood", "Cloth", "Scrap", "Bamboo", "Tin", "Coins" }

Config.PaintColors = {
	Color3.fromRGB(156, 103, 64), -- wood
	Color3.fromRGB(232, 222, 192), -- canvas
	Color3.fromRGB(124, 126, 132), -- scrap grey
	Color3.fromRGB(196, 58, 52), -- red
	Color3.fromRGB(235, 140, 46), -- orange
	Color3.fromRGB(246, 205, 72), -- yellow
	Color3.fromRGB(88, 170, 82), -- green
	Color3.fromRGB(64, 138, 214), -- blue
	Color3.fromRGB(122, 84, 190), -- purple
	Color3.fromRGB(240, 240, 240), -- white
	Color3.fromRGB(40, 40, 46), -- black
	Color3.fromRGB(236, 120, 170), -- pink
}

Config.Flight = {
	StallSpeed = 26, -- below this, lift collapses
	FullLiftSpeed = 38, -- at/above this, wings give full lift
	-- Top speed comes from engines, sails and wings (plus perks later), never from weight:
	-- weight only decides whether your lift can carry you. Each extra engine, sail or wing
	-- adds a little less than the one before it (Falloff).
	Speed = {
		Base = 22, -- a bare hull drifting along
		PerEngine = 15, -- times the engine material's thrust
		PerSail = 1.4, -- per full square sail (a bowsprit's jib counts for less)
		PerWing = 1.6,
		Falloff = { Engine = 0.75, Sail = 0.92, Wing = 0.92 },
		Max = 95,
	},
	-- Handling: an airship sails rather than flies. The rudder takes a moment to bite and to
	-- let go, the hull heels gently into turns, and W/S trims the ballast to climb or sink
	-- (the bow only tips a few degrees). A slow swell keeps her rocking.
	TurnBonus = 0.8, -- multiplier on the stat-derived turn rate
	RudderLag = 0.9, -- seconds for the rudder to come round (and to straighten up again)
	BankAngle = math.rad(9), -- heel at a full turn
	SailClimb = 16, -- studs/s climb with W (if lift allows)
	SailDive = 20, -- studs/s sink with S
	BallastLag = 1.1, -- seconds to reach the climb or sink asked for
	MaxPitch = math.rad(7), -- bow tilt at a full climb or dive
	ClimbDrag = 0.12, -- climbing trades a little speed (sinking wins it back)
	SailAccel = 6, -- speed gained per second, plus SailAccelPerSpeed x top speed
	SailAccelPerSpeed = 0.08,
	SailDecel = 4, -- speed lost per second when over top speed
	Swell = { Roll = math.rad(2.2), Pitch = math.rad(1.2), Heave = 1.0 },
	Responsiveness = 10, -- how stiffly the hull follows its heading (lower = heavier)
	BoostMultiplier = 1.55, -- top speed while holding boost
	BoostFuelMultiplier = 3, -- fuel burn while boosting
	PowerBoostMultiplier = 1.8, -- the Boost power-up
	HitInvulnerability = 1.5, -- seconds after a hazard hit
	HitDamage = { 18, 34 },
	HitRadius = 8,
	ClimbPerMargin = 80, -- climb cap studs/s per 1.0 of lift margin above 1
	MaxClimb = 28,
	MaxSinkRate = 45,
	CeilingSoft = 340,
	CeilingHard = 420,
	LaunchSpeed = 52,
	LaunchTime = 3,
	CrewWeight = 2, -- weight added per player aboard
	FuelBurnPerEngine = 0.45, -- fuel/s at full throttle
	CrashCheckAhead = 10,
	OverboardDistance = 60,
	OverboardDelay = 2.5,
	-- parachute landings: near the runway and low enough, the chute brings the ship down
	ChuteDrift = 45, -- max speed drifting toward the touchdown spot
	ChuteSink = 24, -- max sink rate under the canopy
	ChuteBrake = 2.2, -- how fast forward momentum bleeds off (per second)
}

-- Free Creator Store audio (swap freely)
Config.Sounds = {
	Rain = "rbxassetid://5911952995",
	Wind = "rbxassetid://9114057128",
	Gust = "rbxassetid://110536638811166",
	Thunder = "rbxassetid://72113341430811",
	Engine = "rbxassetid://8907185231",
	Splash = "rbxassetid://9125703162",
	Hammer = "rbxassetid://9114753855",
	Chop = "rbxassetid://7091906373",
	Fanfare = "rbxassetid://1836473422",
	Crash = "rbxassetid://115664312809163",
	PowerUp = "rbxassetid://138277374585498",
}

Config.SoundVolumes = {
	Hammer = 0.45,
	Chop = 0.6,
	Splash = 0.7,
	Gust = 0.55,
	Crash = 0.8,
	Fanfare = 0.6,
	Thunder = 0.8,
	PowerUp = 0.8,
}
-- Clip long one-shots (seconds)
Config.SoundMaxLength = { Hammer = 0.9, Chop = 1.2, Gust = 2.5, Fanfare = 6, Thunder = 6 }

return Config
