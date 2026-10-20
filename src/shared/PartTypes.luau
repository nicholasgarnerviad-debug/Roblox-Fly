-- Airship piece catalog (Rust-style building).
--
-- kind = "cell" (fills a 4-stud grid cell) or "edge" (a wall on the face between two
-- tiles; span = how many cell levels tall). A story is 2 levels: floor at level 0, walls
-- on levels 1-2, the next floor at level 2 sitting on top of the walls.
--
-- tiered = structural piece. Goes down as Wood (or cheap Twig when TWIG_PLACEMENT is on).
-- Other pieces go down in materials[1]. Either way the Hammer can only upgrade a piece into
-- an allowed material once the island that unlocks that tier is reached
-- (Materials.upgradeAtIsland: Bamboo 2, Scrap 3, Tin 4).
--
-- Stats are base values x material multipliers (see Materials). cost = units of the
-- material (twigCost wood while still twig).
-- lift = dynamic lift (needs airspeed); staticLift = balloon lift; sailThrust = free thrust.
-- deck = walkable floor (rain pools on it when nothing covers it)
-- rails = railings build themselves on its open edges
-- railBeside = neighbours still get a railing next to it (it isn't walkable)
-- solid = sitting on top of a floor hides that floor's railings
-- trim = has a second paintable colour (a balloon's stripe)
-- rotatable = R turns it; needsSupport = must stand on a floor; needsMast = must sit on a mast
local PartTypes = {}

local TIERS = { "Twig", "Wood", "Bamboo", "Scrap", "Tin" }

PartTypes.Categories = {
	{
		name = "Structure",
		icon = "\u{1F528}",
		parts = { "Deck", "Hull", "Wall", "Doorway", "Window", "HalfWall", "Stairs", "Ladder", "Roof", "Mast" },
	},
	{
		name = "Ship Gear",
		icon = "\u{1F388}",
		parts = {
			"Balloon",
			"Sail",
			"Bowsprit",
			"Engine",
			"Wing",
			"Tail",
			"FuelTank",
			"CrowsNest",
			"Seat",
			"Pump",
			"Cannon",
			"Flag",
		},
	},
}

PartTypes.Order = {}
for _, cat in ipairs(PartTypes.Categories) do
	for _, name in ipairs(cat.parts) do
		table.insert(PartTypes.Order, name)
	end
end

PartTypes.Defs = {
	Core = {
		display = "Helm",
		icon = "\u{1F579}",
		weight = 6,
		hp = 300,
		lift = 2,
		drag = 1,
		fuel = 60,
		cost = 0,
		materials = { "Wood" },
		fixed = true,
		deck = true,
		rails = true,
		blurb = "The heart of the ship. Holds the pilot seat and 60 fuel.",
	},

	-- Structure ------------------------------------------------------------------
	Deck = {
		display = "Floor",
		icon = "\u{25AC}",
		weight = 1.2,
		hp = 60,
		drag = 0.25,
		cost = 1,
		twigCost = 1,
		materials = TIERS,
		tiered = true,
		deck = true,
		rails = true,
		solid = true,
		blurb = "Foundation tile at the bottom, or a floor on top of walls for an upper story.",
	},
	Hull = {
		display = "Hull Block",
		icon = "\u{1F4E6}",
		weight = 3,
		hp = 100,
		drag = 1,
		cost = 2,
		twigCost = 1,
		materials = TIERS,
		tiered = true,
		deck = true,
		rails = true,
		solid = true,
		blurb = "Heavy, tough foundation block. Front blocks get a raked bow.",
	},
	Wall = {
		display = "Wall",
		icon = "\u{1F3E0}",
		kind = "edge",
		span = 2,
		weight = 2.4,
		hp = 120,
		drag = 1,
		cost = 3,
		twigCost = 1,
		materials = TIERS,
		tiered = true,
		blurb = "Snaps to the edge of a floor. Floors snap on top for the next story.",
	},
	Doorway = {
		display = "Doorway",
		icon = "\u{1F6AA}",
		kind = "edge",
		span = 2,
		weight = 2,
		hp = 100,
		drag = 0.9,
		cost = 3,
		twigCost = 1,
		materials = TIERS,
		tiered = true,
		rotatable = true,
		blurb = "A wall you can walk through.",
	},
	Window = {
		display = "Window",
		icon = "\u{1F5BC}",
		kind = "edge",
		span = 2,
		weight = 2,
		hp = 100,
		drag = 0.9,
		cost = 3,
		twigCost = 1,
		materials = TIERS,
		tiered = true,
		rotatable = true,
		blurb = "A wall with a shuttered window to keep watch from the cabin.",
	},
	HalfWall = {
		display = "Half Wall",
		icon = "\u{2796}",
		kind = "edge",
		span = 1,
		weight = 1.2,
		hp = 70,
		drag = 0.5,
		cost = 2,
		twigCost = 1,
		materials = TIERS,
		tiered = true,
		blurb = "Waist-high bulwark for the edge of a deck. Great gunwales for cannons!",
	},
	Stairs = {
		display = "Stairs",
		icon = "\u{2197}",
		weight = 1.5,
		hp = 70,
		drag = 0.5,
		cost = 2,
		twigCost = 1,
		materials = TIERS,
		tiered = true,
		rotatable = true,
		solid = true,
		blurb = "Climbs one level toward where it faces (R). Two flights reach the next floor.",
	},
	Ladder = {
		display = "Ladder",
		icon = "\u{2195}",
		weight = 0.6,
		hp = 50,
		drag = 0.2,
		cost = 1,
		twigCost = 1,
		materials = TIERS,
		tiered = true,
		rotatable = true,
		blurb = "Climbable. Stack two to reach the floor above, or run them up a mast.",
	},
	Roof = {
		display = "Roof",
		icon = "\u{26FA}",
		weight = 1.5,
		hp = 70,
		drag = 0.6,
		cost = 2,
		twigCost = 1,
		materials = { "Twig", "Wood", "Cloth", "Bamboo", "Scrap", "Tin" },
		tiered = true,
		rotatable = true,
		solid = true,
		defaultColor = Color3.fromRGB(150, 72, 52),
		blurb = "Sloped roof (R to turn). Anything overhead keeps the rain off the floor below!",
	},
	Mast = {
		display = "Mast",
		icon = "\u{1F4CF}",
		weight = 0.8,
		hp = 90,
		drag = 0.2,
		cost = 2,
		twigCost = 1,
		materials = TIERS,
		tiered = true,
		blurb = "Tall pole that holds balloons, sails and crow's nests above the crew.",
	},

	-- Ship gear ------------------------------------------------------------------
	Balloon = {
		display = "Balloon",
		icon = "\u{1F388}",
		weight = 4,
		hp = 200,
		staticLift = 60,
		drag = 4,
		cost = 12,
		materials = { "Cloth" },
		railBeside = true,
		maxPerShip = 4,
		trim = true, -- a second paintable colour: the stripe (Paint Brush, T)
		blurb = "Big hot-air balloon: huge lift at any speed, and only weather damage weakens it. Paint it and its stripe any colours. Max 4 per ship: 1 for a skiff, 2 mid-size, 4 for a galleon.",
	},
	Sail = {
		display = "Sail",
		icon = "\u{26F5}",
		weight = 1.2,
		hp = 60,
		sailThrust = 14,
		drag = 1,
		cost = 4,
		materials = { "Cloth" },
		railBeside = true,
		blurb = "Mast section with a square sail: free thrust, even with no fuel. Stack them up a mast!",
	},
	Bowsprit = {
		display = "Bowsprit",
		icon = "\u{1F6A9}",
		weight = 1,
		hp = 60,
		sailThrust = 8,
		drag = 0.5,
		cost = 3,
		materials = { "Wood" },
		needsFrontClear = true,
		railBeside = true,
		blurb = "A spar jutting off the bow with a triangular jib: a little free thrust, and very piratey. Needs open air in front.",
	},
	Engine = {
		display = "Engine",
		icon = "\u{1F300}",
		weight = 5,
		hp = 140,
		thrust = 60,
		drag = 1,
		cost = 7,
		materials = { "Wood", "Scrap", "Tin" },
		needsFrontClear = true,
		railBeside = true,
		blurb = "Big propeller: thrust that burns fuel. Needs open air in front. Upgrade it to Scrap (island 3) for more power.",
	},
	Wing = {
		display = "Wing",
		icon = "\u{1F6E9}",
		weight = 1.5,
		hp = 60,
		lift = 6,
		drag = 0.5,
		cost = 3,
		materials = { "Cloth", "Wood", "Bamboo", "Scrap", "Tin" },
		railBeside = true,
		blurb = "Lift that grows with speed, plus a little extra top speed.",
	},
	Tail = {
		display = "Tail Fin",
		icon = "\u{1F53A}",
		weight = 1,
		hp = 60,
		lift = 0.5,
		drag = 0.3,
		stability = 1,
		cost = 2,
		materials = { "Wood", "Cloth", "Bamboo", "Scrap", "Tin" },
		railBeside = true,
		blurb = "Stability: less wobble in storms, sharper turns.",
	},
	FuelTank = {
		display = "Fuel Tank",
		icon = "\u{1F6E2}",
		weight = 2,
		hp = 80,
		fuel = 50,
		drag = 0.6,
		cost = 3,
		materials = { "Wood", "Scrap", "Tin" },
		railBeside = true,
		blurb = "+50 fuel capacity.",
	},
	CrowsNest = {
		display = "Crow's Nest",
		icon = "\u{1F441}",
		weight = 1.5,
		hp = 80,
		drag = 0.6,
		cost = 3,
		materials = { "Wood", "Bamboo" },
		needsMast = true,
		rotatable = true,
		blurb = "Lookout basket on top of a mast. The gap faces where it points (R).",
	},
	Seat = {
		display = "Crew Seat",
		icon = "\u{1F4BA}",
		weight = 1,
		hp = 50,
		drag = 0.5,
		cost = 2,
		materials = { "Wood", "Cloth", "Bamboo" },
		needsSupport = true,
		rotatable = true,
		blurb = "A safe spot to ride out turbulence. Goes on a floor (R to turn).",
	},
	Pump = {
		display = "Bilge Pump",
		icon = "\u{1F6B0}",
		weight = 2,
		hp = 90,
		drag = 0.4,
		cost = 4,
		materials = { "Wood", "Scrap", "Tin" },
		needsSupport = true,
		station = true,
		rotatable = true,
		blurb = "Crew station: crank it to drain every puddle on deck at once.",
	},
	Cannon = {
		display = "Cannon",
		icon = "\u{1F4A3}",
		weight = 3,
		hp = 120,
		drag = 0.4,
		cost = 5,
		materials = { "Scrap", "Tin" },
		needsSupport = true,
		station = true,
		rotatable = true,
		defaultColor = Color3.fromRGB(44, 44, 50),
		blurb = "Crew station: hold F to fire! Point it with R. (Boss fights are coming.)",
	},
	Flag = {
		display = "Flag",
		icon = "\u{1F3F4}",
		weight = 0.3,
		hp = 30,
		drag = 0.2,
		cost = 1,
		materials = { "Cloth" },
		rotatable = true,
		defaultColor = Color3.fromRGB(30, 30, 34),
		blurb = "Fly your colours! Paint it with the brush.",
	},
}

-- The free airship every new crew starts with (already upgraded to wood).
-- Forward is -Z; the helm (core) is at the stern. { x, y, z, type, material, color? }
PartTypes.StarterPlane = (function()
	local list = {}
	local function add(x, y, z, t, m, c)
		table.insert(list, { x, y, z, t, m, c })
	end
	local TAN = Color3.fromRGB(222, 198, 150)
	local RUST = Color3.fromRGB(176, 78, 60)
	for x = -3, 3 do
		for z = -7, 1 do
			if not (x == 0 and z == 0) then
				add(x, 0, z, "Deck", "Wood")
			end
		end
	end
	for x = -2, 2 do
		add(x, 0, -8, "Hull", "Wood")
	end
	add(0, 0, -9, "Engine", "Scrap")
	for _, x in ipairs({ -5, -4, 4, 5 }) do
		add(x, 0, -1, "Wing", "Cloth")
	end
	add(-4, 0, 0, "Wing", "Cloth")
	add(4, 0, 0, "Wing", "Cloth")
	for _, x in ipairs({ -2, 2 }) do
		for y = 1, 3 do
			add(x, y, -3, "Mast", "Wood")
		end
		add(x, 4, -3, "Balloon", "Cloth", x < 0 and RUST or TAN)
	end
	add(0, 1, 1, "Tail", "Wood")
	add(-3, 1, 1, "Seat", "Wood")
	add(3, 1, 1, "Seat", "Wood")
	add(-3, 1, -1, "Pump", "Wood")
	add(3, 1, -1, "Pump", "Wood")
	add(-3, 1, -6, "FuelTank", "Wood")
	return list
end)()

function PartTypes.get(name)
	return PartTypes.Defs[name]
end

function PartTypes.isEdge(name)
	local def = PartTypes.Defs[name]
	return def ~= nil and def.kind == "edge"
end

-- Upgrades discovered while exploring islands (not material tiers). Each is locked until the
-- crew finds it: `unlock` names the GameState attribute that turns it on.
PartTypes.Reinforce = {
	Balloon = {
		unlock = "BalloonReinforce",
		where = "the Skylark wreck on Rustbucket Reef",
		display = "Reinforce",
		icon = "\u{1F517}",
		cost = { Scrap = 3, Cloth = 4 },
		hp = 2, -- max HP multiplier
		extraWeight = 1.2, -- iron hoops aren't free
		blurb = "Iron hoops and a rope net: double HP, and a torn balloon keeps most of its lift.",
	},
}

-- Rust-style twig placement is switched off for now: structural pieces go down as Wood.
PartTypes.TWIG_PLACEMENT = false

-- Material a fresh piece goes down in.
function PartTypes.placeMaterial(name)
	local def = PartTypes.Defs[name]
	if def.tiered then
		return PartTypes.TWIG_PLACEMENT and "Twig" or "Wood"
	end
	return def.materials[1]
end

function PartTypes.allows(typeName, materialName)
	local def = PartTypes.Defs[typeName]
	if not def then
		return false
	end
	for _, m in ipairs(def.materials) do
		if m == materialName then
			return true
		end
	end
	return false
end

-- Cost of a piece in a material: (currency, amount).
function PartTypes.cost(typeName, materialName, Materials)
	local def = PartTypes.Defs[typeName]
	local mat = Materials.get(materialName)
	if mat.twig then
		return mat.currency, def.twigCost or 1
	end
	return mat.currency or materialName, def.cost
end

return PartTypes
