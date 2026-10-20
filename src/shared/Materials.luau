-- Building materials. A part's stats = part base stats x these multipliers.
-- soak = extra weight fraction when fully soaked by rain (0 = waterproof).
-- tear = gust damage multiplier.
-- variant = custom MaterialVariant in MaterialService (its BaseMaterial must equal robloxMaterial).
local Materials = {}

Materials.Order = { "Wood", "Cloth", "Scrap", "Bamboo", "Tin" }

-- Upgrade ladder shown by the Hammer (each piece only offers the ones it allows).
-- unlockedAtIsland = when parts can be built in it at all (Scrap engines from day one).
-- upgradeAtIsland  = when the Hammer can upgrade pieces into it: one new tier per island.
--                    Materials without one (Wood, Cloth) are starting materials, not upgrades.
Materials.TierOrder = { "Twig", "Wood", "Bamboo", "Scrap", "Tin", "Cloth" }

Materials.Defs = {
	-- Rust-style starting tier: every structural piece goes down as twig first.
	Twig = {
		display = "Twig",
		icon = "\u{1F33F}",
		weight = 0.35,
		hp = 0.25,
		lift = 0.7,
		thrust = 0.6,
		soak = 0.05,
		tear = 2.0,
		robloxMaterial = Enum.Material.Wood,
		color = Color3.fromRGB(198, 160, 108),
		unlockedAtIsland = 1,
		currency = "Wood",
		twig = true,
		blurb = "Flimsy stick frame. Upgrade it with the Hammer!",
	},
	Wood = {
		display = "Wood",
		icon = "\u{1F334}",
		weight = 1.0,
		hp = 1.0,
		lift = 1.0,
		thrust = 0.9,
		soak = 0.15,
		tear = 1.0,
		robloxMaterial = Enum.Material.WoodPlanks,
		variant = "PS_DeckWood2",
		color = Color3.fromRGB(156, 103, 64),
		unlockedAtIsland = 1,
		blurb = "All-rounder. Soaks up some rain.",
	},
	Cloth = {
		display = "Cloth",
		icon = "\u{1F9F5}",
		weight = 0.45,
		hp = 0.6,
		lift = 1.3,
		thrust = 0,
		soak = 0.50,
		tear = 1.6,
		robloxMaterial = Enum.Material.Fabric,
		variant = "PS_Canvas3",
		color = Color3.fromRGB(236, 226, 198),
		unlockedAtIsland = 1,
		blurb = "Light, great wings. Gets heavy in rain and tears in gusts.",
	},
	Scrap = {
		display = "Scrap Metal",
		icon = "\u{2699}",
		weight = 1.8,
		hp = 2.0,
		lift = 0.85,
		thrust = 1.15,
		soak = 0,
		tear = 0.6,
		robloxMaterial = Enum.Material.CorrodedMetal,
		variant = "PS_Scrap1",
		color = Color3.fromRGB(150, 150, 154),
		unlockedAtIsland = 1,
		upgradeAtIsland = 3,
		blurb = "Tough, heavy, waterproof. Best for engines.",
	},
	Bamboo = {
		display = "Bamboo",
		icon = "\u{1F38B}",
		weight = 0.6,
		hp = 0.9,
		lift = 1.1,
		thrust = 0,
		soak = 0.10,
		tear = 0.9,
		robloxMaterial = Enum.Material.Wood,
		variant = "PS_Bamboo1",
		color = Color3.fromRGB(206, 190, 110),
		unlockedAtIsland = 2,
		upgradeAtIsland = 2,
		blurb = "Light and springy.",
	},
	Tin = {
		display = "Tin",
		icon = "\u{1F96B}",
		weight = 1.3,
		hp = 1.5,
		lift = 0.95,
		thrust = 1.05,
		soak = 0,
		tear = 0.7,
		robloxMaterial = Enum.Material.Metal,
		variant = "PS_Tin",
		color = Color3.fromRGB(200, 205, 212),
		unlockedAtIsland = 4,
		upgradeAtIsland = 4,
		blurb = "A lighter, shinier scrap.",
	},
}

function Materials.get(name)
	return Materials.Defs[name]
end

-- Island whose landing lets the Hammer upgrade into this material (nil = not an upgrade tier).
function Materials.upgradeIsland(name)
	local def = Materials.Defs[name]
	return def and def.upgradeAtIsland
end

return Materials
