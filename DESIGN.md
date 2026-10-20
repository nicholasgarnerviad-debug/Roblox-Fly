# Patchwork Skies — Game Design (working title)

> Up to 4 friends bolt an **airship** together out of driftwood, canvas and scrap, then fly it
> island to island through storms. One player flies; the rest run the deck, bailing water,
> cranking the bilge pump, patching balloons and coaxing the engines back to life. Every
> island unlocks new materials, so the ship keeps getting better while the weather keeps
> getting worse.
>
> (Code names still say "plane" in places, e.g. `PlaneService` and `CrewPlane`. In game it's always "airship".)

---

## 1. Core loop

1. **Gather** — on an island, chop palms, scavenge scrap and harvest flax for materials.
2. **Build** — in the hangar, spend materials on parts. Every part trades weight against lift, durability and thrust.
3. **Launch** — the pilot takes the controls and the cliff-top catapult throws the plane off the island.
4. **Fly the route** — the pilot steers while the crew runs around the deck dealing with the weather.
5. **Land**: get low near the next island's runway and the parachute brings you down, earning coins, materials and unlocks.
6. **Upgrade and go again** — better materials, bigger planes, worse weather.

A run fails when the plane hits the ocean or flies into terrain. The crew washes back to the last
hangar, and the blueprint is kept so they can rebuild and try again.

---

## 2. The crew (4 players, roles are soft)

Anyone can do anything. The weather creates more jobs than one person can cover, so roles
form naturally.

| Role | Station / tool | Job |
|---|---|---|
| **Pilot** | Helm (ship's wheel) | Flies (W/S climb/dive, A/D turn, Shift boost, R/F throttle), dodges hazards, grabs power-ups, lands |
| **Pump hand** | Bilge pump station | Cranks the pump to halve every puddle at once (6 s recharge) |
| **Engineer** | Hammer, wrench | Repairs damaged parts, restarts sputtering engines, refuels |
| **Deckhand** | Bucket (later: scraper, extinguisher) | Bails puddles, scrapes ice, puts out fires |
| **Navigator** | Spyglass, map (later) | Calls out gusts and lightning, steers the pilot around storm cells, works the grapple for floating crates |

There are **safety ropes**: a crew member who falls overboard is pulled back onto the deck a few
seconds later, so falling is a setback rather than an elimination.

---

## 3. The airship

Ships are big enough that the crew actually walks around and works on them. The free starter
ship has a 7×9 railed deck with a planked hull and raked bow, **two big hot-air balloons** side
by side mid-ship on three-section masts, **one big propeller on the bow**, stubby wings, two bilge pumps, two crew
seats and a fuel barrel.

### 3.0 Rust-style building (tools, tiers)
Building works like **Rust**. Every player spawns with three tools:

| Tool | What it does |
|---|---|
| 📘 **Building Plan** | **Q** opens a radial piece wheel (Structure / Ship Gear pages). Pieces **snap** into place with a **blue (valid) / red (invalid) hologram**. Structural pieces go down as **Wood**. **R** rotates, **M** mirrors. |
| 🔨 **Hammer** | Look at a piece and press **Q** (or click) for the upgrade wheel, plus **Rotate** and **Demolish** (refund). **Upgrades unlock one tier per island:** landing on island 2 unlocks **Bamboo**, island 3 **Scrap**, island 4 **Tin** (each tier has its own stats and look). Locked tiers show 🔒 and the island that unlocks them. **In flight, click damaged parts to repair them.** |
| 🖌 **Paint Brush** | Pick a colour and click pieces to paint them (mirror works too). **Balloons are two-tone:** **T** switches between painting the envelope (Body) and its belt and crown (Stripe). "Natural" resets the body to its material colour, or the stripe to an automatic colour that contrasts the envelope. |

**Upgrade gating (for now):** on Driftwood Cove the Hammer can't upgrade anything. Wood and Cloth are
starting materials, not upgrade tiers. Scrap gear (engines, cannons) can still be *built* from day one;
only hammering pieces *into* Scrap waits for island 3. Twig placement (Rust's first tier) is still in
the code behind `PartTypes.TWIG_PLACEMENT`, switched off.

**Walls live on tile edges, like Rust.** Wall, Doorway, Window and Half Wall snap to the **edge of a floor**. Floors snap on **top of walls** for the next story (2 cells = one 8-stud story). Walls can also stack on walls. That gives real hollow rooms, cabins and multi-story ships.

### 3.1 Building rules
- Airships are built on a **4-stud grid** (17 wide × 7 tall × 22 long cells) around the **Helm**, which holds the pilot seat and can't be removed.
- Each piece has to stay connected to the helm, so a removal that would split the ship is blocked. Walls connect through the floors they stand on.
- **Railings build themselves** on every open edge of the deck, so the crew can't stumble overboard. Open deck edges also get a pirate-ship hull side:
  - a planked strake with a dark rub rail and a gold line
  - brass portholes on every other cell
  - the lower hull curving in underneath
- **Wings and tail fins are canvas on a frame.**
  - **Wings:** bat-wing canvas, one rib per cell and a billowing lobe, so rows of wing cells get a scalloped trailing edge.
  - **Tail:** a swept fin with a striped rudder on brass hinges.
  - **Materials:** the frame takes the build material, and Scrap or Tin turns the canvas to plate. Unpainted canvas is cream.
- **The Flag** is a Jolly Roger built from parts: a swallowtail, a skull and crossbones, and a halyard rope.
- **Balloons** are gored hot-air envelopes, built from 10 gores × 9 bands of cloth panels that follow a teardrop profile (`ENVELOPE` in PartBuilder).
  - **Look:** alternate gores are a shade darker, and every panel's tone varies a little for a patchwork feel.
  - **Seams:** a darker backing behind each panel shows between the gores as seams.
  - **Stripe colour:** it paints one band of panels, the crown cap and the throat skirt.
  - **Patches:** sometimes the balloon gets a sewn-on scrap patch.
  - **Raycasts:** they hit a hidden core inside the envelope.
- **Mirror mode** places a matching part on the other side of the center line.
- Every part can be **painted** with any palette color. Balloons take a second colour for their stripe (`PartTypes` `trim = true`; stored as `blueprint[key].trim`).
- Engines need open air in front of them for the propeller.
- Seats and pumps have to stand on the deck.
- Removing a part refunds its materials.

### 3.2 Parts (v1 = bold)

| Part | Base weight | Base HP | Gives | Allowed materials |
|---|---|---|---|---|
| **Helm (core)** | 6 | 300 | Pilot seat and ship's wheel, 60 fuel | fixed |
| **Deck Plank** | 1.2 | 60 | Light walkable deck (rain pools here) | Wood, Bamboo, Scrap, Tin |
| **Hull Block** | 3 | 100 | Heavy, tough structure (bow, keel) | Wood, Scrap, Bamboo, Tin |
| **Balloon** | 4 | 200 | Big hot-air balloon: huge **static lift** at any speed. **Max 4 per ship**: 1 for a skiff, 2 for a mid-size ship, 4 in the corners of a galleon. Players choose where they go (usually on masts). Losing one really hurts! | Cloth |
| **Mast** | 0.8 | 90 | Holds balloons above the crew's heads | Wood, Bamboo, Scrap, Tin |
| **Wing** | 1.5 | 60 | **Dynamic lift** that needs airspeed | Wood, Cloth, Scrap, Bamboo, Tin |
| **Engine** | 5 | 140 | **Thrust** from a big radial propeller, burns fuel | Wood, Scrap, Tin |
| **Tail Fin** | 1 | 60 | Stability (less wobble, sharper turns) | Wood, Cloth, Scrap, Bamboo, Tin |
| **Fuel Tank** | 2 | 80 | +50 fuel capacity | Wood, Scrap, Tin |
| **Crew Seat** | 1 | 50 | A safe spot to ride out turbulence | Wood, Cloth, Bamboo |
| **Bilge Pump** | 2 | 90 | Crew station that drains every puddle by half | Wood, Scrap, Tin |
| **Wall** | 2 | 90 | Cabin walls; the top is walkable | Wood, Bamboo, Scrap, Tin |
| **Porthole** | 1.8 | 70 | Wall with brass portholes | Wood, Scrap, Tin |
| **Roof** | 1.5 | 70 | Sloped shingle roof (rotates) | all |
| **Stairs** | 1.5 | 70 | Climbs one level (rotates) | Wood, Bamboo, Scrap, Tin |
| **Ladder** | 0.6 | 50 | Climbable (rotates) | Wood, Bamboo, Scrap, Tin |
| **Sail** | 1.2 | 60 | Mast section with a square sail on a yard: **free thrust with no fuel**. Sails hung higher up a mast are narrower, so a stack reads as course, topsail and topgallant | Cloth |
| **Bowsprit** | 1 | 60 | Spar angled up off the bow with a triangular jib: a little free thrust (8). Needs open air in front | Wood |
| **Cannon** | 3 | 120 | Crew station, hold F to fire (rotates; boss fights later) | Scrap, Tin |
| **Crow's Nest** | 1.5 | 80 | Lookout basket on top of a mast | Wood, Bamboo |
| **Flag** | 0.3 | 30 | Jolly Roger in any color | Cloth |

**Multi-story ships:** stack walls 2 high and put deck planks on top for an upper deck (2 cells
= one 8-stud story). Stairs and ladders connect the levels. Railings appear only on edges you can
walk off. **Anything built above a deck keeps the rain off it**, so roofs and upper decks mean
fewer puddles, at the cost of extra weight (more balloons). The build menu is grouped into
**Hull / Flight / Crew** (Q cycles), and **R rotates** stairs, ladders, roofs, seats, pumps,
cannons, crow's nests and flags.

**Later parts:** Shield Generator (charges from power-ups), Lightning Rod, Heater/De-icer,
Cargo Hold, Armor Plate, Searchlight, Grapple Winch, Parachute Rack, Jet Engine, Figurehead.

### 3.3 Materials

Every part's stats are its base stats multiplied by its material.

| Material | Weight | HP | Lift | Thrust | Gets wet? | Where | Notes |
|---|---|---|---|---|---|---|---|
| **Wood** | 1.0 | 1.0 | 1.0 | 0.9 | +15% weight when soaked | Island 1 (palms) | The all-rounder |
| **Cloth** (canvas) | 0.45 | 0.6 | 1.3 | — | +50% weight when soaked | Island 1 (flax) | Balloons and wings, tears easily in gusts |
| **Scrap Metal** | 1.8 | 2.0 | 0.85 | 1.15 | waterproof | Island 1 (wreck) for gear; **upgrade tier at island 3** | Tough and heavy, best engines |
| Bamboo | 0.6 | 0.9 | 1.1 | — | +10% | **Upgrade tier at island 2** | Light and decent |
| Tin | 1.3 | 1.5 | 0.95 | 1.05 | waterproof | **Upgrade tier at island 4** | A lighter scrap |
| Rubber | 1.1 | 1.2 | — | — | waterproof, seals puddles | Island 3 | Waterproof deck |
| Copper | 1.6 | 1.4 | — | — | conducts lightning safely | Island 3 | Lightning rods |
| Felt | 0.5 | 0.8 | — | — | insulates against ice | Island 4 | Anti-icing |
| Steel | 2.2 | 3.0 | 0.9 | 1.3 | waterproof | Island 4 | End-game armor |
| Skywood | 0.3 | 1.0 | 1.6 | — | — | Island 6 (rare) | Naturally buoyant |
| Stormglass | 0.8 | 2.5 | 1.4 | 1.5 | immune to weather | Final island | Prestige material |

### 3.4 Derived plane stats (shown live in the build panel)
- **Weight** = parts + puddles + cargo + crew (2 per player aboard). Later weather can also soak wood and cloth.
- **Water capacity** (the WATER gauge) = lift at cruising speed − dry weight: how much rainwater the ship can carry before it sinks
- **Lift** = balloon lift + wing lift × speed factor.
  - **Balloons** lift the same at any speed and are never weakened by weight or speed. Only weather damage tears them, which is why they can be reinforced.
  - **Wings** lift more the faster you fly.
- **Lift margin** = Lift ÷ Weight. **≥ 1.0 holds altitude.** Below 1.0 the plane sinks even at full throttle. This is the number the whole game revolves around, and the **only** place weight matters.
- **Top speed** = base 22 + engines + sails + wings (+ perks and upgrades later, via `speedBonus`). **Weight and drag never slow you down.**
  - Each extra engine, sail or wing adds a little less than the last.
  - Engines give 15 × their material's thrust, sails 1.4 each and wings 1.6 each.
  - The throttle and fuel only govern the engines' share.
  - With empty tanks only sails keep you going; without sails you glide.
  - Examples: the starter does 47 (67 with two extra engines), and the sail-only pirate galleon does 44 (61 with one engine).
  - Tuning lives in `Config.Flight.Speed`.
- **Handling** = tail fins − weight
- **Fuel** = core + tanks; each engine burns fuel at throttle

---

## 4. Pilot gameplay: dodge and collect

**One player flies; everyone else keeps the plane alive.** Flying is never just holding W. The
pilot is busy:

- **Dodging hazards.** Each route has obstacles that fit its weather:
  - Rain route: **sea stacks** (rock pillars), **storm cells** (dark downpour columns that flood the deck), **downdrafts** (push the plane toward the sea)
  - Later routes: waterspouts, lightning strike zones, ice spires, fog-hidden rocks, ash plumes, the boss's attacks
- **Grabbing power-ups.** Glowing pickups float along the route, and the pilot flies through them:

| Power-up | Effect |
|---|---|
| 🛡 **Shield** | A bubble that blocks all gust, hazard and collision damage for 12 s |
| 🔧 **Repair Kit** | Heals every part by 35% |
| 💧 **Bilge Pump** | Drains every puddle instantly |
| ⚡ **Boost** | Big speed burst for 4 s |
| ⛽ **Fuel Can** | +40 fuel |
| *(later)* Magnet, Lift Balloon, Lightning Rod, Freeze Time | |

- **Controls (sailing, not dogfighting):** W/S climb/sink · A/D rudder · **Shift boost** (burns fuel) · R/F throttle · **H** shows the controls again. Mobile and gamepad use the stick plus on-screen buttons. The controls legend shows for 8 s after take-off and then folds into a small "H flight controls" pill.
- Hitting a hazard doesn't instantly end the run. It **damages the parts nearest the impact** and knocks the plane back, so the crew has to repair. Only the sea is instant failure.
- The pilot and crew depend on each other. A good pilot means fewer repairs, and a good crew lets the pilot take risky lines for power-ups.

## 4b. Flight model (arcade, server-authoritative)

- The plane is one welded assembly. A `LinearVelocity` and an `AlignOrientation` on the core drive it, so custom shapes never tumble out of control.
- **It sails rather than flies (user direction: "pirates in the sky").** All tuning is in `Config.Flight`:
  - **Rudder:** it takes about `RudderLag` (0.9 s) to come round and to straighten up. A full turn is about 22°/s on the starter ship (`TurnBonus` 0.8).
  - **Heel:** the hull leans only `BankAngle` (9°) into a turn.
  - **W/S ballast:** W/S trims the ballast. The ship eases toward `SailClimb` (16 studs/s) or `SailDive` (20 studs/s) over `BallastLag`, and the bow tips at most `MaxPitch` (7°).
  - **Swell:** a slow roll, pitch and heave (`Swell`) keeps her rocking like a ship at sea.
  - **Hull weight:** the gyro is soft (`Responsiveness` 10), so the hull feels heavy.
- **Sails fill gradually:** speed eases toward `topSpeed × throttle` at `SailAccel + SailAccelPerSpeed × top`. Climbing costs a little speed and sinking wins it back (`ClimbDrag`).
- Climb rate is capped by lift margin: `climbCap = (margin − 1) × 80`. At a margin of 0.8 the plane sinks about 16 studs/s whatever the pilot does.
- Below stall speed, lift falls off quickly.
- Weather adds wind drift, gust impulses and turbulence wobble. Tail fins damp the wobble.
- **Crashing:** touching the sea or hitting terrain at speed.
- **Landing (parachute):** landing is meant to be easy, not a skill test. Get within **220 studs of the runway centreline below 110 altitude**, from any direction and at any speed. A **small drogue chute** (the same size on every ship) shoots out of the stern, forward speed bleeds off, and the ship glides down a slope onto the runway. On the way it swings round to face down the runway, stays clear of hills and never dips into the sea, and touches down about 5–6 s after the chute opens. The chute then sags and fades. The tips say when the island is ahead and when you're over the runway but too high. Tuning: `Voyage.Islands[i].parachute` (range, ceiling) and `Config.Flight.ChuteDrift/ChuteSink/ChuteBrake`.

---

## 5. Weather events

Each route between two islands has one signature weather event that builds, peaks and clears.
The weather creates **jobs** for the crew, and those jobs are the co-op gameplay.

| # | Weather | What it does to the plane | Crew counter-play |
|---|---|---|---|
| **1** | **Rain & wind** (tutorial, kept gentle) | **The ship fills with water:** puddles form on open decks (roofs keep them dry) and grow until they cover the tile, each full one adding 3 weight. The HUD's **WATER** gauge shows how much of the ship's spare lift the water has eaten: at 100% it starts to sink. A gentle crosswind (6) pushes the ship sideways, and every 8–14 s a gust shoves it, with a 1.5 s warning and a HUD wind arrow. Gusts don't break anything here. Storm cells (heavier rain) and downdrafts appear along the way. **No soaking, flooded engines, rocks or fog yet**: those are saved for later routes. | **Bail puddles** (hold E), **crank the bilge pump** (F, halves every puddle, 6 s recharge), and the pilot **steers into the wind** and around storm cells |
| 2 | Strong winds | Strong steady crosswind plus violent gusts. Cloth tears and loose parts rattle off. | Tail fins, heavier builds, tie-down repairs |
| 3 | Thunderstorm | Lightning strikes the tallest parts and starts fires. Metal attracts strikes. | Extinguish fires, build copper lightning rods, the navigator reads the flashes |
| 4 | Blizzard | Ice builds up on wings (weight up, lift down) and the controls get sluggish. | Scrape ice, felt insulation, heaters |
| 5 | Fog bank | Near-zero visibility and hidden sea stacks. | Navigator's compass and searchlight, slow flying |
| 6 | Ash storm | Ash clogs engines, hot updrafts and down-drafts. | Clean the intakes, ride the thermals |
| 7 | **The Eye** (finale) | A hurricane that combines everything | The whole crew working together |

**Random route encounters (later):** floating supply crates to grapple, bird flocks that dent
propellers, thermals that give free lift, rainbows for bonus coins, sky pirates.

---

## 6. Islands: the "how far can you get?" ladder

The goal of the game is **distance**: how many islands your crew can reach. Every route is harder
than the last, the weather gets more intense and more inventive, and **every 5th island is a
boss island** with a challenge route and a big material upgrade.

| # | Island | Theme | Unlocks on landing | Route weather out | Intensity |
|---|---|---|---|---|---|
| **1** | **Driftwood Cove** | Sunny starter island with a cliff-top hangar and catapult, palms, a flax meadow and an old wreck on the beach | Wood, Cloth, Scrap | **Rain & wind**: a short ~1-minute tutorial hop | ★ |
| **2** | **Rustbucket Reef** | Junkyard atoll | Bamboo upgrades | **Strong winds + sea stacks** (the first rocks to dodge) | ★★ |
| 3 | Thunderhead Peak | Mountain with copper mines | Scrap upgrades, Rubber, Copper | Thunderstorm | ★★★ |
| 4 | Frostbite Atoll | Ice shelves | Tin upgrades, Felt | Blizzard | ★★★ |
| **5** | **Stormwatch Spire (BOSS)** | A lighthouse fortress in a permanent storm | **Steel** (tier-2 material) | **Boss route: "The Squall King"**, a living storm cell that chases the plane, throws lightning and gusts, and spawns waterspouts. The crew has to survive it and hit 3 storm beacons to break it | ★★★★ |
| 6 | Fogbank Hollow | Misty sea stacks | Glass (searchlights) | Fog | ★★★★ |
| 7 | Cinder Isle | Volcano | Skywood | Ash storm | ★★★★ |
| 8 | Hailstone Shelf | Floating ice | Aerogel | Hail (punctures cloth) | ★★★★★ |
| 9 | Mirage Dunes | Desert island | Sunsteel | Heat shimmer and sandstorm | ★★★★★ |
| **10** | **Skyhaven (BOSS)** | A floating island at the top of the world | **Stormglass** (tier-3) | **Boss route: "The Eye"**, a hurricane that combines everything | ★★★★★★ |
| 11+ | Endless Skies | Procedurally generated islands | Prestige cosmetics | Random mixes of weather that stack harder each island | ∞ |

**How the escalation works (in code):** every route is one entry in a data table with a weather
type, an intensity multiplier, a length, and optional "modifiers" (gusts, lightning, waterspouts,
ice and so on). Adding a new weather event or island means adding one table entry plus one effect
handler, so new ideas can be dropped in quickly.

**Boss islands (every 5th):**
- The route has a boss: a big set-piece hazard with phases, not just weather.
- Clearing it unlocks a **material tier** (Steel at 5, Stormglass at 10) that makes the next stretch possible.
- Boss islands are **checkpoints**: after clearing one, the crew can start future voyages from there.

Each island has a hangar (rebuild and upgrade), resource nodes, a trading post (coins for
materials) and an NPC with a quest. The furthest island reached is shown on a **leaderboard**
("Furthest island" and "Fastest crew"). **Driftwood Cove stays the home base**: the hangar now,
shops and other services later.

### 6.1 Exploring islands on foot (Sea of Thieves style)
After landing the crew **stays on the island** (no auto-tow). The result card offers **🏝 Explore**
or **Tow home**, and a **⛵ Tow home** button stays at the top while exploring. Anyone who dies while
exploring respawns on that island (`Voyage.Islands[i].spawn`), not back home.

**Rustbucket Reef (built):** about 960 × 1,100 studs. Around the runway is a flat junkyard plain
(the hangar under construction and scrap piles), and beyond it rolling jungle hills, a valley pond
and wide sandy beaches ring the island.
- **Plants:** about 200 jungle trees, 180 palms (choppable for Wood), bushes, ferns, elephant-ear
  plants, flowers, flax (Cloth) and boulders.
  - Ferns arch over and droop. `ReefFlora.arch` builds them from tapering segments.
  - Palms stand upright on the beaches. The first generation laid all of them on their sides; `ReefFlora.palm` now keeps the template's rotation and measures its height on the trunk, and `standPalm` and `polishFern` fixed the existing ones in place.
- **Lantern trail (about 830 studs):** runs from the end of the runway past the pond, through the
  jungle and up around **Skylark Peak** to the **Skylark wreck** on the summit. The wreck is a
  crashed old airship whose deflated balloon still wears iron hoops and a rope net. A light beam
  marks it from across the island.
- **Discovery:** studying the plans on the wreck's workbench unlocks **Reinforced Rigging** for
  the crew (`GameState.BalloonReinforce`).
- **Reinforced Rigging:** back at the hangar, the Hammer wheel on a balloon offers **🔗 Reinforce**
  (4 Cloth + 3 Scrap). It doubles the balloon's HP, a torn balloon keeps most of its lift, it costs
  +1.2 weight, and the balloon gets iron hoops and a rope net. Demolish refunds it.
- **Wild boars (9, in 7 dens along the trail):** they wander near their den, snort ("!") and
  charge anyone within 30 studs, gore for 10 damage, back off and charge again. They give up past
  75 studs from home. 60 HP. Each one drops +12 coins and +2 Cloth (hide) and respawns after 45 s.
  - **Look:** a long barrel body with a shoulder hump and paler belly, a swept-back bristly mane, a low head with muzzle, pink snout, upright ears and curved tusks, and jointed legs (ham, shin, hoof). Each coat is a shade lighter or darker.
  - **Hit flash:** a hit flashes every part tagged `Hide`, and each part returns to its own `BaseColor`.
  - **Animation:** `Leg` parts, each with its `Hip` weld, still drive the trot animation.
- **Cutlass (starter weapon):** click to slash, 20 damage with knockback and a short stagger. Three
  hits kill a boar.
- **Weapons to find (swords for now):** some islands hide better blades. Finding one unlocks it for
  the **whole crew**: everyone gets one in their backpack, and it stays through respawns. The
  explore banner counts the island's finds (🔎 Finds 1/3). Stats live in `Shared.Weapons`, the
  tools in `ServerStorage.Weapons`, and the find spots are Discovery-tagged stands with a
  `Weapon` attribute.

  | Weapon | Where | Damage | Swing | Feel |
  |---|---|---|---|---|
  | Cutlass | starter | 20 | 0.45 s | All-rounder, 3 hits per boar |
  | **Scrap Cleaver** | Reef: stuck in the anvil at **Rusty's Forge**, on the junkyard plain west of the runway | 34 | 0.8 s | Heavy: 2 hits per boar, huge knockback, wide swing |
  | **Captain's Saber** | Reef: on the weapon rack at an **abandoned pirate camp** on the west jungle plateau, guarded by a boar | 16 | 0.28 s | Quick, with extra reach, 4 hits per boar |

  Future islands add their own finds: an entry in `Shared.Weapons`, a tool, a stand on the island,
  and its unlock key in `Voyage.Islands[i].finds`.

---

## 7. Economy and progression

- **Shared crew materials**, because everyone builds the same plane. Gathering and building feed the same pool.
- **Coins** come from landing and are spent at trading posts.
- **Landing reward** = base + plane integrity bonus + tasks done (puddles bailed, repairs) + cargo delivered (cargo is a later feature: optional crates that add weight for a bigger payout, and can be thrown overboard in an emergency).
- **Personal progression (persisted, later):** pilot level, saved blueprints, cosmetics (paint finishes, propeller skins, smoke trails, horns), and island checkpoints you can start a voyage from.
- **Monetization (no pay-to-win):** cosmetics, extra blueprint slots, private servers.

---

## 8. Tech architecture

```
ReplicatedStorage/Shared     Config, Materials, PartTypes, PlaneStats, PartBuilder, Grid, Weather, Remotes
ServerScriptService/Server   Main (bootstrap) + services:
                             CrewService (inventory, voyage stats, alerts)
                             PlaneService (blueprint, assembly, build/remove/paint, damage, puddles, soak)
                             FlightService (phases, launch, flight physics, landing, crash, overboard)
                             WeatherService (route intensity, rain effects, gusts, sputter)
                             ResourceService (gather nodes on islands)
                             ExploreService (discoveries incl. weapon finds, respawning on the landed island)
                             WeaponService (crew-wide weapon unlocks -> Backpack + StarterGear)
                             BoarService (wild boar AI, melee hits using Shared.Weapons stats)
StarterPlayerScripts/Client  ClientMain + UI (shared kit) + Radial + controllers:
                             HUDController, FlightPanel, ToolController, PilotController, FxController,
                             CombatController (Cutlass swings, boar trot animation),
                             HotbarController (replaces Roblox's backpack bar), PromptController
                             (themed ProximityPrompts)
Workspace/World              Islands (terrain), hangar, catapult, runway, decor (built once in Edit mode)
ServerStorage/DevTools       Edit-time generators, not used at runtime: ReefGen (Rustbucket Reef terrain
                             and trail; re-runnable) and ReefFlora (plant placement)
```

**Game phases:** `Build → Launching → Flying → Landing → Landed` or `→ Crashed`, then back to `Build`.

**Source on disk (Rojo).** The three code folders above live in `src/shared`, `src/server` and `src/client`, and Rojo live-syncs them into Studio.
- **Sync direction:** one way, disk → Studio. Edit the files, not the scripts in Studio.
- **To sync:** run `rojo serve`, then in Studio open Plugins → Rojo → Connect.
- **Checks:** `lune run scripts/check` runs Selene, StyLua and the TestEZ specs in `tests/`, all headless under Lune.
- **Packages:** `wally install` restores them (ProfileStore goes to `ServerScriptService.ServerPackages`).
- **Tools:** the versions are pinned in `rokit.toml`.

### 8.1 UI look ("captain's logbook")

- **One kit (`Client.UI`), every screen.** Every screen is built from it.
  - **Panels:** walnut panels framed in brass, cream text, gold highlights.
  - **Fonts:** FredokaOne for headings, BuilderSans for body text.
  - **Buttons:** hotkeys appear as cream keycaps, and buttons have a hover sheen and a press squish.
  - **Scaling:** `UI.autoScale` scales the whole HUD with the window (0.62–1.15×).
  - **Restyling:** change the look in one place, `UI.Colors` and `UI.Variants`.
- **Bottom-centre docking.** Frames stack upward without overlapping, in `HUD.DOCK` order: hotbar, LAUNCH button, tool panel, pilot hint.
- **The flight view stays clear.** The user found the first pass "unbearable": it covered the ship.
  - **Instruments:** speed, altitude, lift, fuel, hull, water and wind sit on a small see-through card in the **bottom-left corner**.
  - **Route progress:** a slim bar inside the objective banner at the top.
  - **Controls legend:** folds away after take-off.
  - **Tool panel:** collapses to a one-line header outside the hangar.
  - **Rule:** nothing goes in the lower middle of the screen during flight.
- **Hotbar:** custom, numbered 1–9. It hides while you pilot.
- **Prompts:** world prompts use a themed keycap card with a hold bar. Tapping or clicking the card also works.
- **Studio's screen capture doesn't draw BillboardGuis,** so check prompts and markers by their properties, not by screenshot.

---

## 9. Build plan

- **Milestone 1 (built):** airship building and customization, the starting materials, Driftwood Cove, the rain and wind tutorial route, storm cells, downdrafts and power-ups, landing at Rustbucket Reef, and crashing.
- **Milestone 2 (started):** Rustbucket Reef rebuilt as a big explorable island: jungle, the lantern trail, the Skylark wreck with Reinforced Rigging, wild boars and the Cutlass, and exploring after landing. Still to do: the Reef hangar, the crosswind route onward, the trading post, cargo.
- Milestone 3: DataStore persistence (blueprints, coins, unlocks), a lobby with party teleport, a 4-player server cap.
- Milestone 4: Thunderstorm and the islands after it, plus tools (hammer, bucket, extinguisher) as physical items.
