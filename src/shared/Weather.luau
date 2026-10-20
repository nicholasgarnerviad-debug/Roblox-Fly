-- Weather event definitions. Add a new event by adding an entry here and
-- (if it needs new mechanics) a handler in WeatherService / WeatherController.
-- All server numbers are at intensity 1.0 and scale with intensity.
local Weather = {}

Weather.Types = {
	-- The tutorial weather. Rain fills open decks with water the crew bails out; wind
	-- pushes the ship around a little. Nothing here breaks parts: soaking (soakRate),
	-- gust damage (gustDamage) and flooded engines (sputterChance) are saved for later
	-- islands' weather.
	Rain = {
		display = "Rain & Wind",
		icon = "\u{1F327}",
		server = {
			puddleEvery = 5, -- seconds between new puddles (faster with a bigger crew and more open deck)
			puddleGrowTime = 12, -- seconds for a puddle to fill its tile
			puddleWeight = 3, -- weight of a full puddle
			gustEvery = { 8, 14 },
			gustWarning = 1.5, -- the pilot gets this much heads-up before a gust hits
			gustPush = 12,
			turbulence = 4, -- degrees of wobble
			wind = Vector3.new(6, 0, 0), -- gentle crosswind the pilot steers into
		},
		client = {
			rain = 2200, -- particles/s
			cloudCover = 0.92,
			cloudDensity = 0.8,
			cloudColor = Color3.fromRGB(120, 126, 138),
			haze = 1.2,
			density = 0.36, -- keep visibility: fog is a later island's weather
			atmosphereColor = Color3.fromRGB(150, 160, 175),
			brightness = 1.1,
			thunderEvery = { 9, 18 },
			rainVolume = 0.7,
			windVolume = 0.35,
		},
	},
	-- Planned events (numbers are first drafts)
	Wind = {
		display = "Gale",
		icon = "\u{1F32C}",
		server = {
			gustEvery = { 4, 8 },
			gustWarning = 1,
			gustDamage = { 8, 18 },
			gustPush = 34,
			turbulence = 9,
			wind = Vector3.new(22, 0, 0),
			sputterChance = 0,
		},
		client = {
			rain = 0,
			cloudCover = 0.7,
			cloudDensity = 0.5,
			haze = 1.5,
			density = 0.4,
			brightness = 2,
			windVolume = 0.8,
		},
	},
	Thunderstorm = { display = "Thunderstorm", icon = "\u{26C8}" },
	Blizzard = { display = "Blizzard", icon = "\u{1F328}" },
	SquallKing = { display = "The Squall King", icon = "\u{1F451}", boss = true },
}

function Weather.get(name)
	return Weather.Types[name]
end

return Weather
