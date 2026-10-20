-- Builds the visual model for one airship cell. Shared so the client build
-- preview looks exactly like the real part.
-- Returns (model, main). model.WorldPivot is the cell centre; parts are unanchored
-- and welded to `main`, which the server welds to the ship's helm (core).
-- Only `main` collides/queries (plus a few walk-on/lean-on bits); decor is massless.
local Materials = require(script.Parent.Materials)
local PartTypes = require(script.Parent.PartTypes)

local PartBuilder = {}

PartBuilder.PROP_OFFSET = CFrame.new(0, 0, -2.3)

local IRON = Color3.fromRGB(58, 60, 66)
local STEEL = Color3.fromRGB(150, 152, 158)
local BRASS = Color3.fromRGB(212, 170, 70)
local DARKWOOD = Color3.fromRGB(88, 58, 36)
local ROPE = Color3.fromRGB(156, 124, 80)
local RED = Color3.fromRGB(190, 56, 48)
local CREAM = Color3.fromRGB(240, 228, 196)

local VERTICAL = CFrame.Angles(0, 0, math.rad(90)) -- cylinder axis X -> Y
-- Balloon envelopes float this far above their cell on long tethers, clear of the deck and
-- the rigging. (Envelope radii 6.5 x 7.7, centred 5 + LIFT above the cell.)
local BALLOON_LIFT = 12
PartBuilder.BALLOON_LIFT = BALLOON_LIFT
local ALONG_Z = CFrame.Angles(0, math.rad(90), 0) -- cylinder axis X -> Z
local UP = Vector3.new(0, 1, 0)

local function shade(c, f)
	return Color3.new(math.clamp(c.R * f, 0, 1), math.clamp(c.G * f, 0, 1), math.clamp(c.B * f, 0, 1))
end

local function newPart(class, props)
	local p = Instance.new(class)
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Anchored = false
	for k, v in pairs(props) do
		p[k] = v
	end
	return p
end

-- Apply a building material (with its custom MaterialVariant when it has one).
-- plain = skip the variant (curved meshes smear tiled textures).
local function skin(part, mat, color, plain)
	part.Material = mat.robloxMaterial
	if mat.variant and not plain then
		part.MaterialVariant = mat.variant
	end
	if color then
		part.Color = color
	end
	return part
end

local function decor(model, main, class, props, cf)
	props.CanCollide = props.CanCollide or false
	props.CanQuery = props.CanQuery or false
	props.CanTouch = false
	props.Massless = true
	props.CastShadow = props.CastShadow ~= false
	local p = newPart(class, props)
	p.CFrame = cf
	p.Parent = model
	local w = Instance.new("WeldConstraint")
	w.Part0 = main
	w.Part1 = p
	w.Parent = p
	return p
end

local function cyl(model, main, length, diameter, cf, props)
	props.Shape = Enum.PartType.Cylinder
	props.Size = Vector3.new(length, diameter, diameter)
	return decor(model, main, "Part", props, cf)
end

local function ball(model, main, d, cf, props)
	props.Shape = Enum.PartType.Ball
	props.Size = Vector3.new(d, d, d)
	return decor(model, main, "Part", props, cf)
end

local function egg(model, main, size, cf, props)
	props.Size = size
	local p = decor(model, main, "Part", props, cf)
	local m = Instance.new("SpecialMesh")
	m.MeshType = Enum.MeshType.Sphere
	m.Parent = p
	return p
end

-- Boards across the top of a deck-style cell (surface at y = +2).
local function planks(model, main, mat, color, rng)
	for i = 0, 3 do
		local tone = 0.86 + rng:NextNumber() * 0.22
		local p = decor(model, main, "Part", { Size = Vector3.new(0.92, 0.12, 4) }, CFrame.new(-1.5 + i, 2.04, 0))
		skin(p, mat, shade(color, tone))
	end
end

local builders = {}

builders.Deck = function(model, mat, color, rng)
	local main = skin(newPart("Part", { Size = Vector3.new(4, 0.8, 4) }), mat, shade(color, 0.5))
	main.CFrame = CFrame.new(0, 1.6, 0)
	main.Parent = model
	planks(model, main, mat, color, rng)
	-- cross beam underneath
	decor(
		model,
		main,
		"Part",
		{ Size = Vector3.new(4, 0.5, 0.5), Material = Enum.Material.Wood, Color = DARKWOOD },
		CFrame.new(0, 1.0, 0)
	)
	return main
end

builders.Hull = function(model, mat, color, rng)
	local main = skin(newPart("Part", { Size = Vector3.new(4, 4, 4) }), mat, shade(color, 0.6))
	main.Parent = model
	-- overlapping strakes (siding), darkest at the bottom like a weathered hull
	for i, y in ipairs({ -1.3, -0.1, 1.1 }) do
		local p = decor(model, main, "Part", { Size = Vector3.new(4.1, 1.15, 4.1) }, CFrame.new(0, y, 0))
		skin(p, mat, shade(color, 0.82 + i * 0.08 + rng:NextNumber(-0.03, 0.03)))
	end
	planks(model, main, mat, color, rng)
	return main
end

builders.Core = function(model, mat, color, rng)
	local main = skin(newPart("Part", { Size = Vector3.new(4, 4, 4) }), mat, shade(color, 0.6))
	main.Parent = model
	for i, y in ipairs({ -1.3, -0.1, 1.1 }) do
		local p = decor(model, main, "Part", { Size = Vector3.new(4.1, 1.15, 4.1) }, CFrame.new(0, y, 0))
		skin(p, mat, shade(color, (i % 2 == 0) and 0.86 or 1.04))
	end
	planks(model, main, mat, color, rng)
	-- brass trim band marks the helm
	decor(
		model,
		main,
		"Part",
		{ Size = Vector3.new(4.16, 0.25, 4.16), Material = Enum.Material.Metal, Color = BRASS },
		CFrame.new(0, 1.75, 0)
	)

	local seat = newPart("VehicleSeat", {
		Name = "PilotSeat",
		Size = Vector3.new(2, 0.6, 2),
		Color = RED,
		Material = Enum.Material.Fabric,
		CanTouch = false,
		MaxSpeed = 0,
		Torque = 0,
		TurnSpeed = 0,
		HeadsUpDisplay = false,
		Massless = true,
	})
	seat.CFrame = CFrame.new(0, 2.4, 0.6)
	seat.Parent = model
	local w = Instance.new("WeldConstraint")
	w.Part0 = main
	w.Part1 = seat
	w.Parent = seat
	decor(
		model,
		main,
		"Part",
		{ Size = Vector3.new(2.2, 1.9, 0.3), Material = Enum.Material.Wood, Color = DARKWOOD, CanCollide = true },
		CFrame.new(0, 3.35, 1.6)
	)
	decor(
		model,
		main,
		"Part",
		{ Size = Vector3.new(2.3, 0.3, 0.45), Material = Enum.Material.Metal, Color = BRASS },
		CFrame.new(0, 4.35, 1.6)
	)

	-- ship's wheel: post, rim, 8 spokes with handles, brass hub
	decor(
		model,
		main,
		"Part",
		{ Size = Vector3.new(0.6, 1.9, 0.6), Material = Enum.Material.Wood, Color = DARKWOOD },
		CFrame.new(0, 2.95, -1.5)
	)
	local wheelCF = CFrame.new(0, 4.0, -1.15)
	cyl(
		model,
		main,
		0.22,
		2.9,
		wheelCF * ALONG_Z,
		{ Material = Enum.Material.Wood, Color = Color3.fromRGB(122, 78, 44) }
	)
	cyl(
		model,
		main,
		0.26,
		2.3,
		wheelCF * CFrame.new(0, 0, 0.01) * ALONG_Z,
		{ Material = Enum.Material.Wood, Color = DARKWOOD }
	)
	for i = 0, 3 do
		decor(
			model,
			main,
			"Part",
			{ Size = Vector3.new(0.15, 3.8, 0.15), Material = Enum.Material.Wood, Color = Color3.fromRGB(122, 78, 44) },
			wheelCF * CFrame.new(0, 0, 0.08) * CFrame.Angles(0, 0, math.rad(45 * i))
		)
	end
	for i = 0, 7 do
		local a = math.rad(45 * i)
		ball(
			model,
			main,
			0.36,
			wheelCF * CFrame.new(math.cos(a) * 1.95, math.sin(a) * 1.95, 0.08),
			{ Material = Enum.Material.Wood, Color = Color3.fromRGB(122, 78, 44) }
		)
	end
	ball(model, main, 0.6, wheelCF * CFrame.new(0, 0, 0.18), { Material = Enum.Material.Metal, Color = BRASS })

	-- binnacle (compass stand)
	cyl(
		model,
		main,
		1.3,
		0.55,
		CFrame.new(1.35, 2.7, -1.25) * VERTICAL,
		{ Material = Enum.Material.Metal, Color = BRASS }
	)
	ball(
		model,
		main,
		0.8,
		CFrame.new(1.35, 3.45, -1.25),
		{ Material = Enum.Material.Glass, Color = Color3.fromRGB(190, 225, 240), Transparency = 0.35 }
	)

	-- storm lantern
	cyl(model, main, 3, 0.22, CFrame.new(-1.7, 3.5, 1.7) * VERTICAL, { Material = Enum.Material.Metal, Color = IRON })
	local lamp = decor(model, main, "Part", {
		Size = Vector3.new(0.6, 0.75, 0.6),
		Material = Enum.Material.Neon,
		Color = Color3.fromRGB(255, 200, 110),
		CastShadow = false,
	}, CFrame.new(-1.7, 4.7, 1.7))
	decor(
		model,
		main,
		"Part",
		{ Size = Vector3.new(0.75, 0.15, 0.75), Material = Enum.Material.Metal, Color = IRON },
		CFrame.new(-1.7, 5.15, 1.7)
	)
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 200, 120)
	light.Range = 20
	light.Brightness = 1.3
	light.Shadows = false
	light.Parent = lamp
	return main
end

-- Hot-air balloon envelope: a teardrop sewn from GORES vertical gores, each cut into
-- bands between the rings below, so it reads as real cloth panels rather than a blob.
-- {height above the envelope centre, radius}, crown to throat. Rings sit closer where the
-- envelope tapers fastest, so each flat panel stays close to the curve. The crown cap
-- covers the hole above the first ring.
local ENVELOPE = {
	{ 7.0, 2.9 },
	{ 6.2, 4.2 },
	{ 5.0, 5.3 },
	{ 3.2, 6.1 },
	{ 1.0, 6.45 },
	{ -1.6, 6.25 },
	{ -4.2, 5.25 },
	{ -6.4, 3.95 },
	{ -8.4, 2.6 },
	{ -10.0, 1.55 },
}
local GORES = 10 -- keep it even so the gores alternate cleanly
local BELT_BAND = 3 -- this band of panels wears the stripe colour
local ENVELOPE_Y = 5.0 + BALLOON_LIFT -- envelope centre above the cell centre
-- odd scraps of cloth for the sewn-on patches
local PATCH_SCRAPS = { Color3.fromRGB(176, 140, 96), Color3.fromRGB(92, 118, 150), Color3.fromRGB(150, 160, 120) }

local function envelopePoint(ring, angle)
	local r = ENVELOPE[ring]
	return Vector3.new(math.cos(angle) * r[2], ENVELOPE_Y + r[1], math.sin(angle) * r[2])
end

-- The flat panel between rings `band` and `band + 1`, gores gore-1 to gore (as fractions of
-- a turn), pushed `lift` studs outward. Returns its CFrame (X across, Y up the gore) and size.
-- A panel is as wide as the band's narrow end, so neighbours never overlap; `full` gives
-- the band's full width instead (for the seam backing that fills the gaps).
local function goreFrame(gore, band, lift, full)
	local a0, a1 = (gore - 1) / GORES * math.pi * 2, gore / GORES * math.pi * 2
	local A, B = envelopePoint(band, a0), envelopePoint(band, a1)
	local C, D = envelopePoint(band + 1, a0), envelopePoint(band + 1, a1)
	local top, bottom = (A + B) / 2, (C + D) / 2
	local up = (top - bottom).Unit
	local across = ((B - A) + (D - C)).Unit
	local out = up:Cross(across)
	local wTop, wBottom = (B - A).Magnitude, (D - C).Magnitude
	local width = full and math.max(wTop, wBottom) or math.min(wTop, wBottom) * 0.99
	-- front panels run a touch long so bands meet without a crack; the backing stays inside
	-- its band or it pokes out where the envelope bends
	local size = Vector3.new(width, (top - bottom).Magnitude * (full and 0.98 or 1.05), 0.12)
	return CFrame.fromMatrix((top + bottom) / 2 + out * lift, across, up), size
end

-- Tall hot-air balloon, most of it high above the cell so the crew walks underneath:
-- gored envelope, crown cap and vent, a cloth skirt and brass mouth ring, then long tethers
-- down to a load ring on the mast top.
-- opts.trim = the stripe colour players picked (otherwise one that contrasts the envelope).
-- The stripe colours one band of panels, the crown and the skirt.
builders.Balloon = function(model, mat, color, rng, opts)
	local fabric = Enum.Material.Fabric
	local seamColor = shade(color, 0.55)
	local lum = color.R * 0.3 + color.G * 0.59 + color.B * 0.11
	local trim = opts and opts.trim
	local beltColor = trim or (lum > 0.55 and RED or CREAM)
	-- hidden core well inside the envelope: it's what raycasts hit (tools, repairs)
	local main =
		skin(newPart("Part", { Size = Vector3.new(10.8, 12.0, 10.8), CanCollide = false }), mat, seamColor, true)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = main
	main.CFrame = CFrame.new(0, ENVELOPE_Y + 0.4, 0)
	main.Parent = model
	for band = 1, #ENVELOPE - 1 do
		local base = band == BELT_BAND and beltColor or color
		for gore = 1, GORES do
			-- the gore panel: alternate gores a shade darker, and no two panels quite the same tone
			local cf, size = goreFrame(gore, band, 0)
			local tone = (gore % 2 == 0 and 0.86 or 1) * (0.95 + rng:NextNumber() * 0.1)
			decor(model, main, "Part", { Size = size, Material = fabric, Color = shade(base, tone) }, cf)
			-- darker backing just behind it, full width: the slivers between gores read as seams
			local backCF, backSize = goreFrame(gore, band, -0.14, true)
			decor(model, main, "Part", { Size = backSize, Material = fabric, Color = shade(base, 0.74) }, backCF)
		end
	end
	-- crown cap with a brass vent on top
	local crownY = ENVELOPE_Y + ENVELOPE[1][1]
	egg(
		model,
		main,
		Vector3.new(6.4, 1.6, 6.4),
		CFrame.new(0, crownY + 0.15, 0),
		{ Material = fabric, Color = trim or seamColor }
	)
	cyl(
		model,
		main,
		0.3,
		2.2,
		CFrame.new(0, crownY + 0.85, 0) * VERTICAL,
		{ Material = Enum.Material.Metal, Color = BRASS }
	)
	ball(model, main, 0.7, CFrame.new(0, crownY + 1.1, 0), { Material = Enum.Material.Metal, Color = BRASS })
	-- skirt and mouth ring at the throat
	local throatY = ENVELOPE_Y + ENVELOPE[#ENVELOPE][1]
	cyl(model, main, 1.0, 3.4, CFrame.new(0, throatY - 0.3, 0) * VERTICAL, { Material = fabric, Color = beltColor })
	cyl(
		model,
		main,
		0.4,
		3.7,
		CFrame.new(0, throatY - 0.85, 0) * VERTICAL,
		{ Material = Enum.Material.Metal, Color = BRASS }
	)
	-- long tethers down to the load ring on the mast top
	cyl(model, main, 0.35, 1.3, CFrame.new(0, -1.7, 0) * VERTICAL, { Material = Enum.Material.Metal, Color = IRON })
	for i = 0, 3 do
		local a = math.rad(90 * i + 45)
		local top = Vector3.new(math.cos(a) * 1.6, throatY - 1.0, math.sin(a) * 1.6)
		local bottom = Vector3.new(math.cos(a) * 0.5, -1.7, math.sin(a) * 0.5)
		local mid = (top + bottom) / 2
		decor(
			model,
			main,
			"Part",
			{ Size = Vector3.new(0.13, (top - bottom).Magnitude, 0.13), Material = fabric, Color = ROPE },
			CFrame.lookAt(mid, mid + (top - bottom)) * CFrame.Angles(math.rad(90), 0, 0)
		)
	end
	-- crew work on the balloon (repairs) from down here at the load ring
	local reach = Instance.new("Attachment")
	reach.Name = "PromptPoint"
	reach.Position = Vector3.new(0, -1.7 - main.CFrame.Y, 0)
	reach.Parent = main
	-- now and then a sewn-on patch, for that patchwork look
	if rng:NextNumber() < 0.5 then
		local cf, size = goreFrame(rng:NextInteger(1, GORES), rng:NextInteger(BELT_BAND + 1, BELT_BAND + 3), 0.1)
		local patch = cf * CFrame.new(rng:NextNumber(-0.25, 0.25), rng:NextNumber(-0.3, 0.3), 0)
		local w, h = size.X * 0.62, math.min(size.Y * 0.5, 1.9)
		decor(model, main, "Part", {
			Size = Vector3.new(w, h, 0.1),
			Material = fabric,
			Color = rng:NextNumber() < 0.6 and PATCH_SCRAPS[rng:NextInteger(1, #PATCH_SCRAPS)] or shade(color, 0.72),
		}, patch)
		-- stitching round the edge
		for _, edge in ipairs({
			{ 0, h / 2, w, 0.07 },
			{ 0, -h / 2, w, 0.07 },
			{ w / 2, 0, 0.07, h },
			{ -w / 2, 0, 0.07, h },
		}) do
			decor(
				model,
				main,
				"Part",
				{ Size = Vector3.new(edge[3], edge[4], 0.12), Material = fabric, Color = seamColor },
				patch * CFrame.new(edge[1], edge[2], -0.02) -- -Z is outward on a gore frame
			)
		end
	end
	return main
end

builders.Mast = function(model, _mat, color, _rng)
	local main = newPart("Part", {
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(4, 0.8, 0.8),
		Material = Enum.Material.Wood,
		Color = color,
	})
	main.CFrame = VERTICAL
	main.Parent = model
	for _, y in ipairs({ -1.6, 1.6 }) do
		cyl(model, main, 0.3, 0.98, CFrame.new(0, y, 0) * VERTICAL, { Material = Enum.Material.Metal, Color = IRON })
	end
	cyl(model, main, 1.4, 0.14, CFrame.new(0, -0.6, 0), { Material = Enum.Material.Metal, Color = BRASS })
	cyl(model, main, 1.4, 0.14, CFrame.new(0, -0.6, 0) * ALONG_Z, { Material = Enum.Material.Metal, Color = BRASS })
	-- rope wrap
	cyl(model, main, 0.5, 0.9, CFrame.new(0, 0.4, 0) * VERTICAL, { Material = Enum.Material.Fabric, Color = ROPE })
	return main
end

-- Wings and tail fins are canvas stretched over a frame (or plate over a frame once they
-- go Scrap or Tin). The frame takes the build material; unpainted canvas is cream.
local function isMetal(mat)
	local r = mat.robloxMaterial
	return r == Enum.Material.Metal or r == Enum.Material.CorrodedMetal or r == Enum.Material.DiamondPlate
end

local function membrane(part, mat, color)
	if isMetal(mat) then
		return skin(part, mat, color)
	end
	part.Material = Enum.Material.Fabric
	part.Color = (mat.robloxMaterial ~= Enum.Material.Fabric and color == mat.color) and CREAM or color
	return part
end

local function frameBit(part, mat)
	if mat.robloxMaterial == Enum.Material.Fabric then
		part.Material = Enum.Material.Wood
		part.Color = DARKWOOD
		return part
	end
	return skin(part, mat, shade(mat.color, 0.8), true)
end

builders.Wing = function(model, mat, color, _rng)
	-- bat-wing canvas: one rib per cell (at its +X seam) and a lobe of cloth billowing
	-- out behind, so a row of wing cells gets a scalloped trailing edge
	local main = membrane(newPart("Part", { Size = Vector3.new(3.95, 0.1, 2.3) }), mat, color)
	main.CFrame = CFrame.new(0, 0.05, -0.15)
	main.Parent = model
	egg(
		model,
		main,
		Vector3.new(3.7, 0.1, 1.6),
		CFrame.new(-0.1, 0.05, 0.95),
		{ Material = main.Material, MaterialVariant = main.MaterialVariant, Color = main.Color }
	)
	-- round leading spar with a brass cap
	frameBit(cyl(model, main, 4.1, 0.46, CFrame.new(0, 0.05, -1.3), {}), mat)
	ball(model, main, 0.5, CFrame.new(-2.08, 0.05, -1.3), { Material = Enum.Material.Metal, Color = BRASS })
	-- the rib tapers back to a point past the canvas
	frameBit(decor(model, main, "Part", { Size = Vector3.new(0.2, 0.2, 1.8) }, CFrame.new(1.85, 0.12, -0.45)), mat)
	frameBit(decor(model, main, "Part", { Size = Vector3.new(0.13, 0.13, 1.7) }, CFrame.new(1.85, 0.1, 1.25)), mat)
	-- a rope brace from the spar to the rib tip keeps it taut
	local a, b = Vector3.new(-1.6, 0.18, -1.2), Vector3.new(1.8, 0.16, 1.9)
	cyl(
		model,
		main,
		(b - a).Magnitude,
		0.06,
		CFrame.fromMatrix((a + b) / 2, (b - a).Unit, UP:Cross((b - a).Unit)),
		{ Material = Enum.Material.Fabric, Color = ROPE }
	)
	return main
end

builders.Tail = function(model, mat, color, _rng)
	-- swept fin: the wedge's slope is the leading edge
	local main = membrane(newPart("WedgePart", { Size = Vector3.new(0.14, 3.6, 3.0) }), mat, color)
	main.CFrame = CFrame.new(0, 0.1, -0.2)
	main.Parent = model
	local slope = Vector3.new(0, 3.6, 3.0).Unit
	frameBit(cyl(model, main, 4.75, 0.3, CFrame.fromMatrix(Vector3.new(0, 0.1, -0.2), slope, Vector3.xAxis), {}), mat)
	frameBit(cyl(model, main, 3.7, 0.3, CFrame.new(0, 0.1, 1.3) * VERTICAL, {}), mat)
	-- ribs from the leading edge back to the post
	for _, y in ipairs({ -0.8, 0.4 }) do
		local front = -1.7 + (y - 0.1 + 1.8) * (3.0 / 3.6)
		local len = 1.3 - front
		frameBit(
			decor(model, main, "Part", { Size = Vector3.new(0.2, 0.14, len) }, CFrame.new(0, y, front + len / 2)),
			mat
		)
	end
	-- striped rudder on brass hinges
	decor(
		model,
		main,
		"Part",
		{ Size = Vector3.new(0.16, 3.0, 1.05), Material = Enum.Material.Fabric, Color = RED },
		CFrame.new(0, -0.15, 2.0)
	)
	for _, y in ipairs({ -0.9, 0.6 }) do
		decor(
			model,
			main,
			"Part",
			{ Size = Vector3.new(0.18, 0.32, 1.05), Material = Enum.Material.Fabric, Color = CREAM },
			CFrame.new(0, y, 2.0)
		)
	end
	for _, y in ipairs({ -1.2, 0.9 }) do
		cyl(
			model,
			main,
			0.4,
			0.22,
			CFrame.new(0, y, 1.45) * VERTICAL,
			{ Material = Enum.Material.Metal, Color = BRASS }
		)
	end
	decor(
		model,
		main,
		"Part",
		{ Size = Vector3.new(0.7, 0.35, 3.9), Material = Enum.Material.Wood, Color = DARKWOOD },
		CFrame.new(0, -1.85, 0.2)
	)
	return main
end

builders.Engine = function(model, mat, color, _rng)
	local main = skin(newPart("Part", { Size = Vector3.new(2.6, 2.6, 3.0) }), mat, color)
	main.CFrame = CFrame.new(0, 0, 0.4)
	main.Parent = model
	-- round cowling and radial cylinder heads
	cyl(model, main, 0.8, 3.3, CFrame.new(0, 0, -1.45) * ALONG_Z, { Material = Enum.Material.Metal, Color = IRON })
	cyl(
		model,
		main,
		0.82,
		2.4,
		CFrame.new(0, 0, -1.47) * ALONG_Z,
		{ Material = Enum.Material.Metal, Color = shade(IRON, 0.7) }
	)
	for i = 0, 6 do
		local a = math.rad(360 / 7 * i)
		local c = CFrame.new(math.cos(a) * 1.55, math.sin(a) * 1.55, -0.85) * CFrame.Angles(0, 0, a)
		cyl(model, main, 0.95, 0.6, c, { Material = Enum.Material.Metal, Color = STEEL })
		cyl(model, main, 0.2, 0.7, c * CFrame.new(0.5, 0, 0), { Material = Enum.Material.Metal, Color = BRASS })
	end
	-- exhaust stacks
	for _, x in ipairs({ -0.75, 0.75 }) do
		cyl(
			model,
			main,
			1.5,
			0.4,
			CFrame.new(x, 1.95, 0.9) * VERTICAL,
			{ Material = Enum.Material.Metal, Color = IRON }
		)
		cyl(
			model,
			main,
			0.25,
			0.55,
			CFrame.new(x, 2.75, 0.9) * VERTICAL,
			{ Material = Enum.Material.Metal, Color = shade(IRON, 0.6) }
		)
	end
	-- mount
	decor(
		model,
		main,
		"Part",
		{ Size = Vector3.new(0.6, 0.6, 3.4), Material = Enum.Material.Wood, Color = DARKWOOD },
		CFrame.new(0, -1.55, 0.4)
	)

	-- Propeller: hub joined with a Weld so clients can spin it locally.
	local hub = newPart("Part", {
		Name = "PropHub",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(1.4, 1.4, 1.4),
		Material = Enum.Material.Metal,
		Color = RED,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		Massless = true,
	})
	hub.CFrame = PartBuilder.PROP_OFFSET
	hub.Parent = model
	local pw = Instance.new("Weld")
	pw.Name = "PropWeld"
	pw.Part0 = main
	pw.Part1 = hub
	pw.C0 = main.CFrame:Inverse() * PartBuilder.PROP_OFFSET
	pw:SetAttribute("BaseC0", pw.C0) -- clients spin the prop around this
	pw.Parent = hub
	local function bladePart(size, cf, tint)
		local b = newPart("Part", {
			Name = "Blade",
			Size = size,
			Material = Enum.Material.Wood,
			Color = tint,
			CanCollide = false,
			CanQuery = false,
			CanTouch = false,
			Massless = true,
		})
		b.CFrame = cf
		b.Parent = model
		local bw = Instance.new("WeldConstraint")
		bw.Part0 = hub
		bw.Part1 = b
		bw.Parent = b
	end
	for i = 0, 2 do
		local r = PartBuilder.PROP_OFFSET * CFrame.Angles(0, 0, math.rad(120 * i))
		bladePart(
			Vector3.new(0.7, 3.4, 0.16),
			r * CFrame.new(0, 1.9, 0) * CFrame.Angles(0, math.rad(18), 0),
			Color3.fromRGB(120, 80, 48)
		)
		bladePart(
			Vector3.new(0.72, 0.55, 0.18),
			r * CFrame.new(0, 3.4, 0) * CFrame.Angles(0, math.rad(18), 0),
			Color3.fromRGB(245, 205, 70)
		)
	end
	return main
end

builders.FuelTank = function(model, mat, color, _rng)
	local main =
		skin(newPart("Part", { Shape = Enum.PartType.Cylinder, Size = Vector3.new(3.6, 3.1, 3.1) }), mat, color)
	main.CFrame = CFrame.new(0, -0.3, 0)
	main.Parent = model
	cyl(model, main, 2.2, 3.35, CFrame.new(0, -0.3, 0), { Material = mat.robloxMaterial, Color = shade(color, 1.05) })
	for _, x in ipairs({ -1.45, 0, 1.45 }) do
		cyl(
			model,
			main,
			0.22,
			(x == 0) and 3.45 or 3.2,
			CFrame.new(x, -0.3, 0),
			{ Material = Enum.Material.Metal, Color = IRON }
		)
	end
	for _, x in ipairs({ -1.82, 1.82 }) do
		cyl(
			model,
			main,
			0.08,
			2.7,
			CFrame.new(x, -0.3, 0),
			{ Material = Enum.Material.Wood, Color = shade(color, 0.75) }
		)
	end
	cyl(model, main, 0.4, 0.6, CFrame.new(0.6, 1.4, 0) * VERTICAL, { Material = Enum.Material.Metal, Color = BRASS })
	for _, x in ipairs({ -1.1, 1.1 }) do
		decor(
			model,
			main,
			"Part",
			{ Size = Vector3.new(0.45, 0.6, 2.8), Material = Enum.Material.Wood, Color = DARKWOOD },
			CFrame.new(x, -1.7, 0)
		)
	end
	return main
end

builders.Seat = function(model, mat, color, _rng)
	local main = skin(newPart("Part", { Size = Vector3.new(3.0, 0.4, 2.6) }), mat, shade(color, 0.85))
	main.CFrame = CFrame.new(0, -1.8, 0.1)
	main.Parent = model
	local seat = newPart("Seat", {
		Name = "CrewSeat",
		Size = Vector3.new(2.4, 0.5, 2.1),
		Material = Enum.Material.Fabric,
		Color = RED,
		CanTouch = false,
		Massless = true,
	})
	seat.CFrame = CFrame.new(0, -0.95, 0)
	seat.Parent = model
	local w = Instance.new("WeldConstraint")
	w.Part0 = main
	w.Part1 = seat
	w.Parent = seat
	for _, x in ipairs({ -1.1, 1.1 }) do
		for _, z in ipairs({ -0.85, 0.85 }) do
			decor(
				model,
				main,
				"Part",
				{ Size = Vector3.new(0.3, 0.7, 0.3), Material = Enum.Material.Wood, Color = DARKWOOD },
				CFrame.new(x, -1.35, z)
			)
		end
	end
	local back =
		decor(model, main, "Part", { Size = Vector3.new(2.6, 2.1, 0.32), CanCollide = true }, CFrame.new(0, 0.05, 1.12))
	skin(back, mat, color)
	cyl(model, main, 2.8, 0.3, CFrame.new(0, 1.15, 1.12), { Material = Enum.Material.Wood, Color = DARKWOOD })
	for _, x in ipairs({ -1.3, 1.3 }) do
		decor(
			model,
			main,
			"Part",
			{ Size = Vector3.new(0.3, 0.3, 2.1), Material = Enum.Material.Wood, Color = DARKWOOD },
			CFrame.new(x, -0.35, 0.05)
		)
		decor(
			model,
			main,
			"Part",
			{ Size = Vector3.new(0.25, 0.6, 0.25), Material = Enum.Material.Wood, Color = DARKWOOD },
			CFrame.new(x, -0.75, -0.85)
		)
	end
	return main
end

builders.Pump = function(model, mat, color, _rng)
	local main = skin(newPart("Part", { Size = Vector3.new(2.2, 1.8, 1.8) }), mat, color)
	main.CFrame = CFrame.new(0, -1.1, 0)
	main.Parent = model
	decor(
		model,
		main,
		"Part",
		{ Size = Vector3.new(2.4, 0.3, 2.0), Material = Enum.Material.Metal, Color = IRON },
		CFrame.new(0, -0.08, 0)
	)
	cyl(
		model,
		main,
		1.8,
		0.75,
		CFrame.new(-0.35, 0.85, -0.2) * VERTICAL,
		{ Material = Enum.Material.Metal, Color = IRON }
	)
	cyl(
		model,
		main,
		0.3,
		0.9,
		CFrame.new(-0.35, 1.8, -0.2) * VERTICAL,
		{ Material = Enum.Material.Metal, Color = BRASS }
	)
	-- big red crank wheel
	local wheelCF = CFrame.new(1.3, 0.25, 0)
	cyl(model, main, 0.22, 2.6, wheelCF, { Material = Enum.Material.Metal, Color = RED })
	cyl(
		model,
		main,
		0.24,
		2.1,
		wheelCF * CFrame.new(0.01, 0, 0),
		{ Material = Enum.Material.Metal, Color = shade(RED, 0.6) }
	)
	for i = 0, 3 do
		decor(
			model,
			main,
			"Part",
			{ Size = Vector3.new(0.12, 2.4, 0.14), Material = Enum.Material.Metal, Color = RED },
			wheelCF * CFrame.new(0.05, 0, 0) * CFrame.Angles(math.rad(45 * i), 0, 0)
		)
	end
	ball(model, main, 0.5, wheelCF * CFrame.new(0.12, 0, 0), { Material = Enum.Material.Metal, Color = BRASS })
	cyl(model, main, 0.7, 0.24, wheelCF * CFrame.new(0.4, 1.0, 0), { Material = Enum.Material.Wood, Color = DARKWOOD })
	-- spout and hose
	decor(
		model,
		main,
		"Part",
		{ Size = Vector3.new(0.45, 0.45, 1.3), Material = Enum.Material.Metal, Color = IRON },
		CFrame.new(-0.35, 1.3, -0.95)
	)
	cyl(
		model,
		main,
		2.2,
		0.42,
		CFrame.new(-0.7, -1.75, 0.9) * ALONG_Z,
		{ Material = Enum.Material.Rubber, Color = Color3.fromRGB(40, 40, 40) }
	)
	-- ready light (PlaneCare turns it red while recharging)
	ball(
		model,
		main,
		0.45,
		CFrame.new(0.6, 0.15, -0.75),
		{ Name = "Indicator", Material = Enum.Material.Neon, Color = Color3.fromRGB(90, 230, 110), CastShadow = false }
	)
	return main
end

-- Edge pieces (Rust-style walls) ------------------------------------------------
-- Local frame: origin at the bottom-middle of the edge, X runs along it (4 studs),
-- Y up, Z across the wall's thickness.
local WALL_T = 0.5

local function panel(model, main, mat, color, size, cf)
	local p = decor(model, main, "Part", { Size = size, CanCollide = true }, cf)
	skin(p, mat, color)
	return p
end

-- end posts plus top (and optionally bottom) beams
local function wallTrim(model, main, h, bottomBeam)
	for _, x in ipairs({ -1.9, 1.9 }) do
		decor(
			model,
			main,
			"Part",
			{ Size = Vector3.new(0.42, h, WALL_T + 0.14), Material = Enum.Material.Wood, Color = DARKWOOD },
			CFrame.new(x, h / 2, 0)
		)
	end
	decor(
		model,
		main,
		"Part",
		{ Size = Vector3.new(4.1, 0.4, WALL_T + 0.12), Material = Enum.Material.Wood, Color = DARKWOOD },
		CFrame.new(0, h - 0.2, 0)
	)
	if bottomBeam then
		decor(
			model,
			main,
			"Part",
			{ Size = Vector3.new(4.1, 0.4, WALL_T + 0.12), Material = Enum.Material.Wood, Color = DARKWOOD },
			CFrame.new(0, 0.2, 0)
		)
	end
end

local function boardLines(model, main, color, h, xs)
	for _, x in ipairs(xs) do
		decor(model, main, "Part", {
			Size = Vector3.new(0.07, h - 0.8, WALL_T + 0.04),
			Material = Enum.Material.Wood,
			Color = shade(color, 0.6),
		}, CFrame.new(x, h / 2, 0))
	end
end

builders.Wall = function(model, mat, color, _rng)
	local h = 8
	local main = skin(newPart("Part", { Size = Vector3.new(4.02, h, WALL_T) }), mat, color)
	main.CFrame = CFrame.new(0, h / 2, 0)
	main.Parent = model
	boardLines(model, main, color, h, { -1.0, 0, 1.0 })
	decor(
		model,
		main,
		"Part",
		{ Size = Vector3.new(4.06, 0.3, WALL_T + 0.08), Material = Enum.Material.Wood, Color = DARKWOOD },
		CFrame.new(0, h / 2, 0)
	)
	wallTrim(model, main, h, true)
	return main
end

builders.HalfWall = function(model, mat, color, _rng)
	local h = 4
	local main = skin(newPart("Part", { Size = Vector3.new(4.02, h, WALL_T) }), mat, color)
	main.CFrame = CFrame.new(0, h / 2, 0)
	main.Parent = model
	boardLines(model, main, color, h, { -1.0, 0, 1.0 })
	wallTrim(model, main, h, true)
	cyl(model, main, 4.14, 0.6, CFrame.new(0, h, 0), { Material = Enum.Material.Wood, Color = DARKWOOD })
	return main
end

builders.Doorway = function(model, mat, color, _rng)
	local h, dw, dh = 8, 2.6, 6.4
	local side = (4.02 - dw) / 2
	local main = skin(newPart("Part", { Size = Vector3.new(side, h, WALL_T) }), mat, color)
	main.CFrame = CFrame.new(-(dw / 2 + side / 2), h / 2, 0)
	main.Parent = model
	panel(model, main, mat, color, Vector3.new(side, h, WALL_T), CFrame.new(dw / 2 + side / 2, h / 2, 0))
	panel(model, main, mat, color, Vector3.new(dw + 0.02, h - dh, WALL_T), CFrame.new(0, dh + (h - dh) / 2, 0))
	-- door frame
	for _, s in ipairs({ -1, 1 }) do
		decor(
			model,
			main,
			"Part",
			{ Size = Vector3.new(0.25, dh, WALL_T + 0.18), Material = Enum.Material.Wood, Color = DARKWOOD },
			CFrame.new(s * (dw / 2 - 0.05), dh / 2, 0)
		)
	end
	decor(
		model,
		main,
		"Part",
		{ Size = Vector3.new(dw + 0.5, 0.35, WALL_T + 0.18), Material = Enum.Material.Wood, Color = DARKWOOD },
		CFrame.new(0, dh, 0)
	)
	ball(
		model,
		main,
		0.3,
		CFrame.new(0, dh + 0.55, WALL_T / 2 + 0.05),
		{ Material = Enum.Material.Metal, Color = BRASS }
	)
	wallTrim(model, main, h, false)
	return main
end

builders.Window = function(model, mat, color, _rng)
	local h, y0, y1, ow = 8, 3.2, 5.8, 2.2
	local sw = (4.02 - ow) / 2
	local main = skin(newPart("Part", { Size = Vector3.new(4.02, y0, WALL_T) }), mat, color)
	main.CFrame = CFrame.new(0, y0 / 2, 0)
	main.Parent = model
	panel(model, main, mat, color, Vector3.new(4.02, h - y1, WALL_T), CFrame.new(0, y1 + (h - y1) / 2, 0))
	for _, s in ipairs({ -1, 1 }) do
		panel(
			model,
			main,
			mat,
			color,
			Vector3.new(sw, y1 - y0, WALL_T),
			CFrame.new(s * (ow / 2 + sw / 2), (y0 + y1) / 2, 0)
		)
	end
	-- sill, lintel and cross bars
	decor(
		model,
		main,
		"Part",
		{ Size = Vector3.new(ow + 0.6, 0.25, WALL_T + 0.5), Material = Enum.Material.Wood, Color = DARKWOOD },
		CFrame.new(0, y0, 0)
	)
	decor(
		model,
		main,
		"Part",
		{ Size = Vector3.new(ow + 0.4, 0.25, WALL_T + 0.2), Material = Enum.Material.Wood, Color = DARKWOOD },
		CFrame.new(0, y1, 0)
	)
	decor(
		model,
		main,
		"Part",
		{ Size = Vector3.new(0.14, y1 - y0, 0.14), Material = Enum.Material.Wood, Color = DARKWOOD },
		CFrame.new(0, (y0 + y1) / 2, 0)
	)
	decor(
		model,
		main,
		"Part",
		{ Size = Vector3.new(ow, 0.14, 0.14), Material = Enum.Material.Wood, Color = DARKWOOD },
		CFrame.new(0, (y0 + y1) / 2, 0)
	)
	wallTrim(model, main, h, true)
	return main
end

-- Roofs rise toward the way they face (local -Z). Wooden roofs get shingles.
builders.Roof = function(model, mat, color, _rng)
	local main = newPart("WedgePart", { Size = Vector3.new(4, 4, 4), Color = color })
	if mat.robloxMaterial == Enum.Material.WoodPlanks then
		main.Material = Enum.Material.RoofShingles
	else
		skin(main, mat, color)
	end
	main.CFrame = CFrame.Angles(0, math.pi, 0)
	main.Parent = model
	cyl(model, main, 4.1, 0.45, CFrame.new(0, 1.95, -1.95), { Material = Enum.Material.Wood, Color = DARKWOOD })
	decor(
		model,
		main,
		"Part",
		{ Size = Vector3.new(4.1, 0.3, 0.35), Material = Enum.Material.Wood, Color = DARKWOOD },
		CFrame.new(0, -1.9, 2.0)
	)
	for _, x in ipairs({ -2.0, 2.0 }) do
		decor(
			model,
			main,
			"WedgePart",
			{ Size = Vector3.new(0.12, 4.02, 4.02), Material = Enum.Material.Wood, Color = DARKWOOD },
			CFrame.new(x, 0, 0) * CFrame.Angles(0, math.pi, 0)
		)
	end
	return main
end

-- Stairs climb one level toward local -Z. An invisible ramp does the walking.
builders.Stairs = function(model, mat, color, _rng)
	local main = newPart("WedgePart", { Size = Vector3.new(4, 4, 4), Transparency = 1 })
	main.CFrame = CFrame.Angles(0, math.pi, 0)
	main.Parent = model
	for i = 0, 3 do
		local h = i + 1
		local step = decor(model, main, "Part", { Size = Vector3.new(3.6, h, 1) }, CFrame.new(0, -2 + h / 2, 1.5 - i))
		skin(step, mat, shade(color, 0.9 + 0.06 * i))
	end
	for _, x in ipairs({ -1.9, 1.9 }) do
		decor(
			model,
			main,
			"WedgePart",
			{ Size = Vector3.new(0.25, 4.1, 4.1), Material = Enum.Material.Wood, Color = DARKWOOD },
			CFrame.new(x, 0, 0) * CFrame.Angles(0, math.pi, 0)
		)
		cyl(
			model,
			main,
			5.4,
			0.22,
			CFrame.new(x, 1.1, 0) * CFrame.Angles(math.rad(45), 0, 0) * ALONG_Z,
			{ Material = Enum.Material.Wood, Color = Color3.fromRGB(122, 78, 44) }
		)
	end
	return main
end

-- Ladder on the cell's front face; a hidden TrussPart makes it climbable.
builders.Ladder = function(model, mat, color, _rng)
	local main = newPart("TrussPart", { Size = Vector3.new(2, 4, 2), Transparency = 1 })
	main.Style = Enum.Style.NoSupports
	main.CFrame = CFrame.new(0, 0, -1)
	main.Parent = model
	for _, x in ipairs({ -0.9, 0.9 }) do
		local rail = decor(model, main, "Part", { Size = Vector3.new(0.28, 4.1, 0.28) }, CFrame.new(x, 0, -1.6))
		skin(rail, mat, shade(color, 0.85))
	end
	for i = 0, 4 do
		local rung = cyl(model, main, 1.8, 0.2, CFrame.new(0, -1.6 + i * 0.8, -1.6), {})
		skin(rung, mat, color)
	end
	return main
end

-- Mast section with a square sail on a yard, bellied forward. Sails hung higher up the mast
-- are narrower (course, topsail, topgallant...), so a stack reads like a real square rig.
builders.Sail = function(model, mat, color, _rng, opts)
	local level = opts and opts.cell and opts.cell.Y or 2
	local w = math.clamp(9.6 - (level - 2) * 1.0, 5.6, 9.6)
	local main = newPart("Part", {
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(4, 0.8, 0.8),
		Material = Enum.Material.Wood,
		Color = Color3.fromRGB(150, 103, 64),
	})
	main.CFrame = VERTICAL
	main.Parent = model
	-- yard across the top, lighter spar along the foot
	cyl(model, main, w + 0.9, 0.38, CFrame.new(0, 1.72, -0.5), { Material = Enum.Material.Wood, Color = DARKWOOD })
	cyl(model, main, w * 0.94, 0.22, CFrame.new(0, -1.72, -0.5), { Material = Enum.Material.Wood, Color = DARKWOOD })
	-- the sail: three panels in a shallow curve, the middle one bellied furthest forward
	local pw = w / 3
	for i = -1, 1 do
		local belly = i == 0 and -1.25 or -0.85
		local cloth = decor(
			model,
			main,
			"Part",
			{ Size = Vector3.new(pw + 0.12, 3.35, 0.12) },
			CFrame.new(i * pw * 0.97, 0, belly) * CFrame.Angles(0, math.rad(-i * 16), 0)
		)
		skin(cloth, mat, shade(color, i == 0 and 1 or 0.93), true)
	end
	-- reef bands and bolt ropes
	for _, y in ipairs({ 0.85, -0.25 }) do
		decor(
			model,
			main,
			"Part",
			{ Size = Vector3.new(pw + 0.14, 0.12, 0.14), Material = Enum.Material.Fabric, Color = shade(color, 0.75) },
			CFrame.new(0, y, -1.26)
		)
	end
	for _, x in ipairs({ -w / 2 + 0.1, w / 2 - 0.1 }) do
		cyl(model, main, 3.5, 0.1, CFrame.new(x, 0, -0.5) * VERTICAL, { Material = Enum.Material.Fabric, Color = ROPE })
	end
	cyl(model, main, 0.3, 0.95, CFrame.new(0, 1.72, 0) * VERTICAL, { Material = Enum.Material.Metal, Color = IRON })
	return main
end

-- Spar jutting up off the bow with a triangular jib beneath it. Points at local -Z.
builders.Bowsprit = function(model, mat, color, _rng)
	local main = skin(newPart("Part", { Size = Vector3.new(1.6, 1, 2.2) }), mat, shade(color, 0.8))
	main.CFrame = CFrame.new(0, -1.5, 0.3)
	main.Parent = model
	local rise = math.rad(22)
	local heel = Vector3.new(0, -1.1, 1.0)
	local dir = Vector3.new(0, math.sin(rise), -math.cos(rise))
	local len = 13
	local tip = heel + dir * len
	local spar = cyl(model, main, len, 0.7, CFrame.lookAt((heel + tip) / 2, tip) * ALONG_Z, {})
	skin(spar, mat, color)
	ball(model, main, 0.55, CFrame.new(tip), { Material = Enum.Material.Metal, Color = BRASS })
	for _, t in ipairs({ 0.35, 0.7 }) do -- iron bands
		cyl(
			model,
			main,
			0.3,
			0.82,
			CFrame.lookAt(heel + dir * len * t, tip) * ALONG_Z,
			{ Material = Enum.Material.Metal, Color = IRON }
		)
	end
	-- the jib: a triangle standing on the spar, its right angle at the heel and its luff
	-- running from the spar tip up and back (a WedgePart's slope)
	local jh, jl = 8, 11
	decor(
		model,
		main,
		"WedgePart",
		{ Size = Vector3.new(0.12, jh, jl), Material = Enum.Material.Fabric, Color = CREAM },
		CFrame.new(heel) * CFrame.Angles(rise, 0, 0) * CFrame.new(0, jh / 2 + 0.3, -jl / 2)
	)
	-- bobstay from the tip back down to the hull
	local low = Vector3.new(0, -2, -1.6)
	decor(
		model,
		main,
		"Part",
		{ Size = Vector3.new(0.14, 0.14, (tip - low).Magnitude), Material = Enum.Material.Fabric, Color = ROPE },
		CFrame.lookAt((tip + low) / 2, tip)
	)
	return main
end

-- Cannon on a wooden carriage, barrel pointing at local -Z.
builders.Cannon = function(model, mat, color, _rng)
	local main = newPart(
		"Part",
		{ Size = Vector3.new(2.2, 0.9, 2.8), Material = Enum.Material.Wood, Color = Color3.fromRGB(110, 70, 42) }
	)
	main.CFrame = CFrame.new(0, -1.45, 0.2)
	main.Parent = model
	for _, x in ipairs({ -1.18, 1.18 }) do
		for _, z in ipairs({ -0.6, 1.0 }) do
			cyl(model, main, 0.3, 1.15, CFrame.new(x, -1.55, z), { Material = Enum.Material.Wood, Color = DARKWOOD })
			cyl(model, main, 0.34, 0.4, CFrame.new(x, -1.55, z), { Material = Enum.Material.Metal, Color = IRON })
		end
	end
	local barrel = cyl(model, main, 3.3, 0.95, CFrame.new(0, -0.5, -0.5) * ALONG_Z, {})
	skin(barrel, mat, color)
	local muzzle = cyl(model, main, 0.4, 1.2, CFrame.new(0, -0.5, -2.1) * ALONG_Z, {})
	skin(muzzle, mat, shade(color, 1.25))
	local breech = ball(model, main, 1.05, CFrame.new(0, -0.5, 1.15), {})
	skin(breech, mat, color)
	cyl(model, main, 0.5, 0.12, CFrame.new(0, -0.05, 1.0) * VERTICAL, { Material = Enum.Material.Fabric, Color = ROPE })
	-- firing point: its LookVector is the shot direction
	decor(
		model,
		main,
		"Part",
		{ Name = "Muzzle", Size = Vector3.new(0.2, 0.2, 0.2), Transparency = 1, CastShadow = false },
		CFrame.new(0, -0.5, -2.5)
	)
	return main
end

-- Round lookout basket around the top of a mast. Gap faces local -Z.
builders.CrowsNest = function(model, mat, color, rng)
	local main = skin(
		newPart("Part", { Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.45, 6, 6) }),
		mat,
		shade(color, 0.85)
	)
	main.CFrame = CFrame.new(0, -1.8, 0) * VERTICAL
	main.Parent = model
	cyl(
		model,
		main,
		3.2,
		0.8,
		CFrame.new(0, -0.1, 0) * VERTICAL,
		{ Material = Enum.Material.Wood, Color = Color3.fromRGB(150, 103, 64), CanCollide = true }
	)
	local n = 14
	for i = 0, n - 1 do
		local a = (i + 0.5) / n * math.pi * 2
		local dir = Vector3.new(math.sin(a), 0, math.cos(a))
		if dir.Z > -0.85 then -- leave an opening at the front
			local p = dir * 2.8 + Vector3.new(0, -0.6, 0)
			local slat = decor(
				model,
				main,
				"Part",
				{ Size = Vector3.new(1.2, 2.0, 0.22), CanCollide = true },
				CFrame.lookAt(p, p + dir)
			)
			skin(slat, mat, shade(color, 0.9 + rng:NextNumber() * 0.2))
			local top = dir * 2.85 + Vector3.new(0, 0.45, 0)
			cyl(
				model,
				main,
				1.35,
				0.22,
				CFrame.lookAt(top, top + dir) * ALONG_Z * CFrame.Angles(0, math.pi / 2, 0),
				{ Material = Enum.Material.Wood, Color = DARKWOOD }
			)
		end
	end
	return main
end

-- Pole with a flag streaming out behind it. Paint it to fly your colours.
builders.Flag = function(model, _mat, color, _rng)
	local main = newPart("Part", {
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(4, 0.3, 0.3),
		Material = Enum.Material.Wood,
		Color = DARKWOOD,
	})
	main.CFrame = VERTICAL
	main.Parent = model
	ball(model, main, 0.5, CFrame.new(0, 2.1, 0), { Material = Enum.Material.Metal, Color = BRASS })
	-- halyard rope down the pole
	cyl(
		model,
		main,
		3.6,
		0.06,
		CFrame.new(0.2, 0.2, 0.12) * VERTICAL,
		{ Material = Enum.Material.Fabric, Color = ROPE }
	)
	-- the flag in two panels so it looks like it's flapping: the inner one carries the
	-- skull, the outer one kinks away and ends in a swallowtail
	decor(
		model,
		main,
		"Part",
		{ Size = Vector3.new(0.08, 1.9, 1.8), Material = Enum.Material.Fabric, Color = color },
		CFrame.new(0, 0.95, 1.05)
	)
	local hinge = CFrame.new(0, 0.95, 1.95) * CFrame.Angles(0, math.rad(-20), 0)
	decor(
		model,
		main,
		"Part",
		{ Size = Vector3.new(0.08, 1.9, 0.9), Material = Enum.Material.Fabric, Color = shade(color, 0.92) },
		hinge * CFrame.new(0, 0, 0.45)
	)
	for _, sgn in ipairs({ -1, 1 }) do
		-- tails: right-angled wedges joined along the panel's end, so the V notch is cut in
		decor(
			model,
			main,
			"WedgePart",
			{ Size = Vector3.new(0.08, 0.95, 0.7), Material = Enum.Material.Fabric, Color = shade(color, 0.92) },
			hinge
				* CFrame.new(0, sgn * 0.475, 1.25)
				* (sgn > 0 and CFrame.Angles(math.pi, 0, 0) or CFrame.Angles(0, math.pi, 0))
		)
	end
	-- skull and crossbones, thicker than the cloth so they show on both sides
	local lum = color.R * 0.3 + color.G * 0.59 + color.B * 0.11
	local bone = lum > 0.6 and Color3.fromRGB(34, 32, 34) or Color3.fromRGB(244, 240, 228)
	local ink = lum > 0.6 and Color3.fromRGB(240, 236, 226) or Color3.fromRGB(26, 24, 26)
	local mid = CFrame.new(0, 1.0, 1.05)
	for _, a in ipairs({ 40, -40 }) do
		decor(
			model,
			main,
			"Part",
			{ Size = Vector3.new(0.12, 0.13, 1.3), Material = Enum.Material.SmoothPlastic, Color = bone },
			mid * CFrame.new(0, -0.42, 0) * CFrame.Angles(math.rad(a), 0, 0)
		)
	end
	egg(
		model,
		main,
		Vector3.new(0.14, 0.8, 0.74),
		mid * CFrame.new(0, 0.12, 0),
		{ Material = Enum.Material.SmoothPlastic, Color = bone }
	)
	decor(
		model,
		main,
		"Part",
		{ Size = Vector3.new(0.13, 0.24, 0.4), Material = Enum.Material.SmoothPlastic, Color = bone },
		mid * CFrame.new(0, -0.26, 0)
	)
	for _, z in ipairs({ -0.15, 0.15 }) do
		egg(
			model,
			main,
			Vector3.new(0.17, 0.22, 0.19),
			mid * CFrame.new(0, 0.17, z),
			{ Material = Enum.Material.SmoothPlastic, Color = ink }
		)
	end
	return main
end

-- Twig look (Rust's first building tier) -----------------------------------------
local TWIG = Color3.fromRGB(198, 160, 108)
-- Frame types become see-through stick frames; everything else is just tinted twig.
local FRAME_TYPES = { Deck = true, Hull = true, Wall = true, Doorway = true, Window = true, HalfWall = true }

local function stick(model, main, a, b, rng)
	local len = (b - a).Magnitude
	if len < 0.6 then
		return
	end
	local mid = (a + b) / 2
	decor(model, main, "Part", {
		Size = Vector3.new(0.2, 0.2, len + 0.1),
		Material = Enum.Material.Wood,
		Color = shade(TWIG, 0.7 + rng:NextNumber() * 0.35),
	}, CFrame.lookAt(mid, b))
end

-- Sticks along a part's box edges (thin sides collapse to one plane) plus an X brace.
local function frameSticks(model, main, part, rng)
	local cf, s = part.CFrame, part.Size / 2
	local function vals(v)
		return v < 0.4 and { 0 } or { -v, v }
	end
	local xs, ys, zs = vals(s.X), vals(s.Y), vals(s.Z)
	for _, y in ipairs(ys) do
		for _, z in ipairs(zs) do
			stick(model, main, cf * Vector3.new(-s.X, y, z), cf * Vector3.new(s.X, y, z), rng)
		end
	end
	for _, x in ipairs(xs) do
		for _, z in ipairs(zs) do
			stick(model, main, cf * Vector3.new(x, -s.Y, z), cf * Vector3.new(x, s.Y, z), rng)
		end
		for _, y in ipairs(ys) do
			stick(model, main, cf * Vector3.new(x, y, -s.Z), cf * Vector3.new(x, y, s.Z), rng)
		end
	end
	-- X brace across the biggest face
	if s.Y >= s.Z then
		stick(model, main, cf * Vector3.new(-s.X, -s.Y, 0), cf * Vector3.new(s.X, s.Y, 0), rng)
		stick(model, main, cf * Vector3.new(-s.X, s.Y, 0), cf * Vector3.new(s.X, -s.Y, 0), rng)
	else
		stick(model, main, cf * Vector3.new(-s.X, 0, -s.Z), cf * Vector3.new(s.X, 0, s.Z), rng)
		stick(model, main, cf * Vector3.new(-s.X, 0, s.Z), cf * Vector3.new(s.X, 0, -s.Z), rng)
	end
end

local function twigLook(model, main, typeName, rng)
	local frame = FRAME_TYPES[typeName]
	local solids = {}
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			if frame and (d == main or d.CanCollide) then
				table.insert(solids, d)
			elseif frame then
				d:Destroy() -- twig is just a frame: drop the dressing
			else
				d.Material = Enum.Material.Wood
				d.MaterialVariant = ""
				d.Color = shade(TWIG, 0.75 + rng:NextNumber() * 0.3)
			end
		end
	end
	for _, p in ipairs(solids) do
		p.Material = Enum.Material.Wood
		p.MaterialVariant = ""
		p.Color = TWIG
		p.Transparency = 0.72
		frameSticks(model, main, p, rng)
	end
end

-- Extra dressing for pieces upgraded with a discovered reinforcement (PartTypes.Reinforce).
local reinforceLook = {}
reinforceLook.Balloon = function(model, main)
	-- iron hoops round the envelope at four of its rings (flat discs: only the rim shows) ...
	for _, ring in ipairs({ 3, 5, 7, 8 }) do
		local r = ENVELOPE[ring]
		egg(
			model,
			main,
			Vector3.new(r[2] * 2 + 0.4, 0.45, r[2] * 2 + 0.4),
			CFrame.new(0, ENVELOPE_Y + r[1], 0),
			{ Material = Enum.Material.Metal, Color = IRON }
		)
	end
	-- ... tied together by a rope net down every other gore seam
	for seam = 0, GORES - 1, 2 do
		local a = seam / GORES * math.pi * 2
		for ring = 1, #ENVELOPE - 1 do
			local p0 = envelopePoint(ring, a) * Vector3.new(1.03, 1, 1.03)
			local p1 = envelopePoint(ring + 1, a) * Vector3.new(1.03, 1, 1.03)
			local mid = (p0 + p1) / 2
			decor(model, main, "Part", {
				Size = Vector3.new(0.2, 0.2, (p1 - p0).Magnitude + 0.15),
				Material = Enum.Material.Fabric,
				Color = ROPE,
			}, CFrame.lookAt(mid, p1))
		end
	end
	-- a heavier brass mouth ring
	local throatY = ENVELOPE_Y + ENVELOPE[#ENVELOPE][1]
	cyl(
		model,
		main,
		0.8,
		4.4,
		CFrame.new(0, throatY - 0.85, 0) * VERTICAL,
		{ Material = Enum.Material.Metal, Color = BRASS }
	)
end

-- opts.reinforced = add the reinforcement look (if the piece has one)
-- opts.cell = the piece's grid cell (some builders vary with height, e.g. sails taper up a mast)
-- opts.trim = a second colour for pieces that have one (PartTypes trim, e.g. a balloon's stripe)
function PartBuilder.build(typeName, materialName, color, opts)
	local mat = Materials.get(materialName)
	local builder = builders[typeName]
	assert(mat and builder, "Unknown part/material: " .. tostring(typeName) .. "/" .. tostring(materialName))
	local model = Instance.new("Model")
	model.Name = typeName
	local def = PartTypes.get(typeName)
	local rng = Random.new()
	local main = builder(model, mat, color or (def and def.defaultColor) or mat.color, rng, opts)
	if mat.twig then
		twigLook(model, main, typeName, rng)
	end
	if opts and opts.reinforced and reinforceLook[typeName] then
		reinforceLook[typeName](model, main)
		main:SetAttribute("Reinforced", true)
	end
	main.Name = "Main"
	main:SetAttribute("PartType", typeName)
	main:SetAttribute("Material", materialName)
	model.WorldPivot = CFrame.new()
	return model, main
end

-- Railings on the open edges of a deck cell. dirs = list of horizontal unit vectors.
-- cellCF = world CFrame of the cell centre (deck surface is at +2).
-- skirt = also hang a sloped, planked hull side under each open edge (thin deck planks).
-- prow = give a forward-facing open edge a raked bow (full hull blocks).
function PartBuilder.buildRails(model, main, cellCF, dirs, skirt, prow)
	local old = model:FindFirstChild("Rails")
	if old then
		old:Destroy()
	end
	if #dirs == 0 then
		return
	end
	local rails = Instance.new("Model")
	rails.Name = "Rails"
	local wood = Color3.fromRGB(110, 72, 44)
	for _, d in ipairs(dirs) do
		local along = Vector3.new(d.Z, 0, d.X)
		local edge = d * 1.85
		-- cylinder axis X must run along the edge
		local rot = d.X ~= 0 and ALONG_Z or CFrame.new()
		cyl(
			rails,
			main,
			4.1,
			0.34,
			cellCF * CFrame.new(edge + Vector3.new(0, 4.55, 0)) * rot,
			{ Material = Enum.Material.Wood, Color = wood }
		)
		cyl(
			rails,
			main,
			4.0,
			0.14,
			cellCF * CFrame.new(edge + Vector3.new(0, 3.4, 0)) * rot,
			{ Material = Enum.Material.Fabric, Color = ROPE }
		)
		for _, s in ipairs({ -1, 1 }) do
			local post = cellCF * CFrame.new(edge + along * 1.85 * s)
			cyl(
				rails,
				main,
				2.6,
				0.3,
				post * CFrame.new(0, 3.3, 0) * VERTICAL,
				{ Material = Enum.Material.Wood, Color = shade(wood, 0.8) }
			)
			ball(
				rails,
				main,
				0.42,
				post * CFrame.new(0, 4.7, 0),
				{ Material = Enum.Material.Wood, Color = shade(wood, 0.8) }
			)
		end
		if prow and d.Z < -0.5 then
			-- wedge flipped about Z: flat top level with the deck, slope raking down and back
			local bow = decor(rails, main, "WedgePart", {
				Size = Vector3.new(4.02, 4, 1.8),
				Material = Enum.Material.WoodPlanks,
				Color = Color3.fromRGB(104, 66, 40),
			}, cellCF * CFrame.new(0, 0, -2.9) * CFrame.Angles(0, 0, math.pi))
			local deckMat = Materials.get("Wood")
			if deckMat.variant then
				bow.MaterialVariant = deckMat.variant
			end
			decor(
				rails,
				main,
				"Part",
				{ Size = Vector3.new(4.06, 0.3, 0.4), Material = Enum.Material.Metal, Color = BRASS },
				cellCF * CFrame.new(0, 1.85, -3.65)
			)
		end
		if skirt then
			-- a pirate-ship side: a planked strake under the deck edge with a dark rub rail
			-- and a gold line, portholes on every other cell, and the hull curving in below
			local planking = Materials.get("Wood")
			local function hullWood(p)
				if planking.variant then
					p.MaterialVariant = planking.variant
				end
				return p
			end
			local frame = CFrame.fromMatrix(Vector3.zero, UP:Cross(d), UP, d)
			local flat = d.X ~= 0 and Vector3.new(0.4, 1.0, 4.02) or Vector3.new(4.02, 1.0, 0.4)
			hullWood(
				decor(
					rails,
					main,
					"Part",
					{ Size = flat, Material = Enum.Material.WoodPlanks, Color = Color3.fromRGB(122, 78, 46) },
					cellCF * CFrame.new(d * 1.82 + Vector3.new(0, 0.65, 0))
				)
			)
			-- upside-down wedge: flat top under the strake, slope curving in and down
			hullWood(decor(rails, main, "WedgePart", {
				Size = Vector3.new(4.02, 1.7, 1.5),
				Material = Enum.Material.WoodPlanks,
				Color = Color3.fromRGB(92, 58, 36),
			}, cellCF * CFrame.new(d * 1.22 + Vector3.new(0, -0.7, 0)) * frame * CFrame.Angles(math.pi, 0, 0)))
			cyl(
				rails,
				main,
				4.04,
				0.4,
				cellCF * CFrame.new(d * 2.0 + Vector3.new(0, 1.2, 0)) * rot,
				{ Material = Enum.Material.Wood, Color = Color3.fromRGB(62, 40, 26) }
			)
			decor(rails, main, "Part", {
				Size = d.X ~= 0 and Vector3.new(0.1, 0.14, 4.02) or Vector3.new(4.02, 0.14, 0.1),
				Material = Enum.Material.Metal,
				Color = BRASS,
			}, cellCF * CFrame.new(d * 2.03 + Vector3.new(0, 0.2, 0)))
			local kx, kz = string.match(main:GetAttribute("Key") or "", "^(%-?%d+),%-?%d+,(%-?%d+)$")
			if kx and (tonumber(kx) + tonumber(kz)) % 2 == 0 then
				local outward = d.X ~= 0 and CFrame.new() or ALONG_Z
				cyl(
					rails,
					main,
					0.14,
					0.72,
					cellCF * CFrame.new(d * 2.04 + Vector3.new(0, 0.66, 0)) * outward,
					{ Material = Enum.Material.Metal, Color = BRASS }
				)
				cyl(
					rails,
					main,
					0.1,
					0.5,
					cellCF * CFrame.new(d * 2.08 + Vector3.new(0, 0.66, 0)) * outward,
					{ Material = Enum.Material.Glass, Color = Color3.fromRGB(36, 48, 62), Reflectance = 0.25 }
				)
			end
		end
		-- invisible wall so the crew can't stumble overboard
		local wallSize = d.X ~= 0 and Vector3.new(0.4, 3.4, 4) or Vector3.new(4, 3.4, 0.4)
		decor(
			rails,
			main,
			"Part",
			{ Name = "RailWall", Size = wallSize, Transparency = 1, CanCollide = true, CastShadow = false },
			cellCF * CFrame.new(edge + Vector3.new(0, 3.7, 0))
		)
	end
	rails.Parent = model
end

-- Turn a built model into a non-interactive see-through preview.
function PartBuilder.makeGhost(model)
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
			d.CastShadow = false
			d.Transparency = math.max(d.Transparency, 0.45)
		elseif d:IsA("JointInstance") or d:IsA("WeldConstraint") or d:IsA("Light") then
			d:Destroy()
		end
	end
	return model
end

return PartBuilder
