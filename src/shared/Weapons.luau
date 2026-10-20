-- Melee weapons. The Cutlass is everyone's starter; the rest are found while exploring
-- islands (a find spot tagged "Discovery" with a Weapon attribute) and then the whole crew
-- gets one. Tools live in ServerStorage.Weapons under these keys; each carries a Weapon
-- attribute naming its entry here.
-- arc = how far off to the side a hit still lands (dot product with your facing; lower = wider)
-- swing = seconds for the blade to come down
local Weapons = {}

Weapons.Defs = {
	Cutlass = {
		display = "Cutlass",
		icon = "\u{1F5E1}\u{FE0F}",
		starter = true,
		damage = 20,
		range = 8,
		arc = 0.25,
		cooldown = 0.45,
		knock = 38,
		stagger = 0.6,
		swing = 0.1,
		blurb = "Trusty starter blade.",
	},
	ScrapCleaver = {
		display = "Scrap Cleaver",
		icon = "\u{1FA93}",
		island = 2,
		damage = 34,
		range = 8.5,
		arc = -0.1,
		cooldown = 0.8,
		knock = 62,
		stagger = 1.0,
		swing = 0.16,
		blurb = "Heavy and slow, but it drops a boar in two hits and sends it flying.",
	},
	CaptainsSaber = {
		display = "Captain's Saber",
		icon = "\u{2694}\u{FE0F}",
		island = 2,
		damage = 16,
		range = 9.5,
		arc = 0.3,
		cooldown = 0.28,
		knock = 24,
		stagger = 0.4,
		swing = 0.07,
		blurb = "Light and lightning-quick, with extra reach.",
	},
}

function Weapons.get(name)
	return Weapons.Defs[name]
end

-- GameState attribute that is true once the crew has found this weapon.
function Weapons.unlockKey(name)
	return "Weapon_" .. name
end

return Weapons
