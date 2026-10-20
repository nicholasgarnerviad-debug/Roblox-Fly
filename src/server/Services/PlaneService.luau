-- Owns the crew airship: blueprint, live assembly, Rust-style build rules and stats.
-- Every piece is welded to the helm (core); the core is the assembly root.
--
-- Pieces live in PlaneService.cells keyed by:
--   "x,y,z"      cell pieces (floors, hull, gear...)
--   "E:x,y,z,A"  edge pieces (walls on the face between two tiles; see Grid)
-- Edge pieces also claim face slots (PlaneService.faces) for every level they span.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Grid = require(Shared.Grid)
local Materials = require(Shared.Materials)
local PartTypes = require(Shared.PartTypes)
local PlaneStats = require(Shared.PlaneStats)
local PartBuilder = require(Shared.PartBuilder)
local Remotes = require(Shared.Remotes)
local CrewService = require(script.Parent.CrewService)

local PlaneService = {}

PlaneService.cells = {} -- key -> live record (cells and edges)
PlaneService.faces = {} -- face key -> edge key
PlaneService.blueprint = {} -- key -> { type, material, color, rot }
PlaneService.model = nil
PlaneService.core = nil
PlaneService.stats = nil
PlaneService.crewCount = 0
PlaneService.waterWeight = 0
PlaneService.waterMax = 0
-- hooks (set by PlaneCare / FlightService)
PlaneService.onCellAdded = nil
PlaneService.onCellRemoved = nil
PlaneService.repairHook = nil -- function(rec, player) set by PlaneCare

local CORE_KEY = Grid.key(0, 0, 0)
local RESERVED = { [Grid.key(0, 1, 0)] = true } -- pilot seat space above the core
local DECK_PHYS = PhysicalProperties.new(0.7, 1.8, 0, 100, 1)
local UP = Vector3.new(0, 1, 0)
local FORWARD = Vector3.new(0, 0, -1)
local HORIZ = { Vector3.new(1, 0, 0), Vector3.new(-1, 0, 0), Vector3.new(0, 0, 1), Vector3.new(0, 0, -1) }

PlaneService.CORE_KEY = CORE_KEY

function PlaneService.isOccupied(key)
	return PlaneService.cells[key] ~= nil or RESERVED[key] == true
end

local function cellAt(x, y, z)
	return PlaneService.cells[Grid.key(x, y, z)]
end

local function edgeAtFace(x, y, z, axis)
	local k = PlaneService.faces[Grid.faceKey(x, y, z, axis)]
	return k and PlaneService.cells[k]
end

local function isDeck(rec)
	return rec ~= nil and rec.kind ~= "edge" and PartTypes.get(rec.type).deck == true
end

-- Railings --------------------------------------------------------------------

-- An open edge gets a railing unless a wall stands on it or a walkable piece is beside it.
local function needsRail(rec, d)
	local c = rec.cell
	local fx, fz, fa = Grid.faceToward(c.X, c.Z, d)
	if PlaneService.faces[Grid.faceKey(fx, c.Y + 1, fz, fa)] then
		return false -- a wall/half wall stands on this edge
	end
	local nKey = Grid.keyV(c + d)
	if RESERVED[nKey] then
		return false
	end
	local n = PlaneService.cells[nKey]
	return n == nil or PartTypes.get(n.type).railBeside == true
end

-- Rebuild railings (and, on the bottom deck, hull skirts and the bow) for one cell.
local function railsFor(rec)
	if
		not rec
		or rec.kind == "edge"
		or not PartTypes.get(rec.type).rails
		or not rec.main.Parent
		or not PlaneService.core
	then
		return
	end
	local dirs = {}
	local above = PlaneService.cells[Grid.keyV(rec.cell + UP)]
	if not (above and PartTypes.get(above.type).solid) then -- only walkable tops get railings
		for _, d in ipairs(HORIZ) do
			if needsRail(rec, d) then
				table.insert(dirs, d)
			end
		end
	end
	local ground = rec.cell.Y == 0
	local prow = ground
		and rec.type == "Hull"
		and not PlaneService.isOccupied(Grid.keyV(rec.cell + FORWARD))
		and not edgeAtFace(rec.cell.X, 1, rec.cell.Z - 1, "Z")
	PartBuilder.buildRails(
		rec.model,
		rec.main,
		PlaneService.core.CFrame * CFrame.new(Grid.offset(rec.cell)),
		dirs,
		ground and rec.type == "Deck",
		prow
	)
end

-- Refresh rails around a cell (itself, below it and its four neighbours).
function PlaneService.refreshRails(cellV)
	railsFor(PlaneService.cells[Grid.keyV(cellV)])
	railsFor(PlaneService.cells[Grid.keyV(cellV - UP)])
	for _, d in ipairs(HORIZ) do
		railsFor(PlaneService.cells[Grid.keyV(cellV + d)])
	end
end

-- Refresh rails on the floors an edge stands on / sits beside.
local function refreshRailsForEdge(x, y, z, axis)
	local ax, az, bx, bz = Grid.edgeSides(x, z, axis)
	for _, ly in ipairs({ y - 1, y }) do
		railsFor(cellAt(ax, ly, az))
		railsFor(cellAt(bx, ly, bz))
	end
end

-- Spawning ----------------------------------------------------------------------

local function finishSpawn(key, entry, model, main, rec)
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = false
			d.Massless = true
		end
	end
	if PartTypes.get(entry.type).deck then
		main.CustomPhysicalProperties = DECK_PHYS
	end
	local maxHp = PlaneStats.maxHp(entry.type, entry.material, entry.reinforced)
	rec.reinforced = entry.reinforced == true
	main:SetAttribute("MaxHP", maxHp)
	main:SetAttribute("HP", maxHp)
	main:SetAttribute("Key", key)
	rec.hp, rec.maxHp, rec.soak, rec.sputter = maxHp, maxHp, 0, false
	if entry.type == "Core" then
		main.Anchored = true
		main.Massless = false
		main.RootPriority = 100
		PlaneService.core = main
	else
		local w = Instance.new("WeldConstraint")
		w.Name = "PlaneWeld"
		w.Part0 = PlaneService.core
		w.Part1 = main
		w.Parent = main
	end
	model.Parent = PlaneService.model
	PlaneService.cells[key] = rec
	PlaneService.exposedDirty = true
	if PlaneService.onCellAdded then
		PlaneService.onCellAdded(rec)
	end
	return rec
end

local function spawnCell(key, entry)
	local cellV = Grid.parseV(key)
	local model, main = PartBuilder.build(
		entry.type,
		entry.material,
		entry.color,
		{ reinforced = entry.reinforced, cell = cellV, trim = entry.trim }
	)
	model.Name = (entry.type == "Core") and "Core" or key
	local coreCF = PlaneService.core and PlaneService.core.CFrame or PlaneService.coreCFrame
	model:PivotTo(coreCF * CFrame.new(Grid.offset(cellV)) * Grid.rotCFrame(entry.rot))
	main:SetAttribute("Cell", key)
	local rec = {
		key = key,
		kind = "cell",
		cell = cellV,
		type = entry.type,
		material = entry.material,
		color = entry.color,
		rot = entry.rot or 0,
		model = model,
		main = main,
	}
	return finishSpawn(key, entry, model, main, rec)
end

local function spawnEdge(key, entry)
	local x, y, z, axis = Grid.parseEdge(key)
	local def = PartTypes.get(entry.type)
	local model, main = PartBuilder.build(entry.type, entry.material, entry.color, { reinforced = entry.reinforced })
	model.Name = key
	local coreCF = PlaneService.core and PlaneService.core.CFrame or PlaneService.coreCFrame
	model:PivotTo(coreCF * Grid.edgeCFrame(x, y, z, axis) * Grid.rotCFrame(entry.rot))
	main:SetAttribute("Edge", key)
	local rec = {
		key = key,
		kind = "edge",
		cell = Vector3.new(x, y, z),
		axis = axis,
		span = def.span or 2,
		type = entry.type,
		material = entry.material,
		color = entry.color,
		rot = entry.rot or 0,
		model = model,
		main = main,
	}
	for i = 0, rec.span - 1 do
		PlaneService.faces[Grid.faceKey(x, y + i, z, axis)] = key
	end
	return finishSpawn(key, entry, model, main, rec)
end

local function spawnPiece(key, entry)
	if Grid.isEdgeKey(key) then
		return spawnEdge(key, entry)
	end
	return spawnCell(key, entry)
end

local function clearFaces(rec)
	if rec.kind == "edge" then
		for i = 0, rec.span - 1 do
			local fk = Grid.faceKey(rec.cell.X, rec.cell.Y + i, rec.cell.Z, rec.axis)
			if PlaneService.faces[fk] == rec.key then
				PlaneService.faces[fk] = nil
			end
		end
	end
end

function PlaneService.despawnCell(key)
	local rec = PlaneService.cells[key]
	if not rec then
		return
	end
	PlaneService.cells[key] = nil
	clearFaces(rec)
	PlaneService.exposedDirty = true
	if PlaneService.onCellRemoved then
		PlaneService.onCellRemoved(rec)
	end
	rec.model:Destroy()
end

local function refreshAround(rec)
	if rec.kind == "edge" then
		refreshRailsForEdge(rec.cell.X, rec.cell.Y, rec.cell.Z, rec.axis)
	else
		PlaneService.refreshRails(rec.cell)
	end
end

function PlaneService.resetBlueprint()
	local bp = {}
	bp[CORE_KEY] = { type = "Core", material = "Wood", color = Materials.get("Wood").color }
	for _, e in ipairs(PartTypes.StarterPlane) do
		bp[Grid.key(e[1], e[2], e[3])] = { type = e[4], material = e[5], color = e[6] or Materials.get(e[5]).color }
	end
	PlaneService.blueprint = bp
end

-- (Re)builds the whole ship from the blueprint, anchored at coreCFrame.
function PlaneService.buildPlane(coreCFrame)
	if PlaneService.model then
		PlaneService.model:Destroy()
	end
	PlaneService.cells = {}
	PlaneService.faces = {}
	PlaneService.core = nil
	PlaneService.coreCFrame = coreCFrame
	PlaneService.waterWeight = 0
	local m = Instance.new("Model")
	m.Name = "CrewPlane"
	m.Parent = workspace
	PlaneService.model = m
	spawnCell(CORE_KEY, PlaneService.blueprint[CORE_KEY])
	m.PrimaryPart = PlaneService.core
	for key, entry in pairs(PlaneService.blueprint) do
		if key ~= CORE_KEY then
			spawnPiece(key, entry)
		end
	end
	for _, rec in pairs(PlaneService.cells) do
		railsFor(rec)
	end
	PlaneService.recompute()
	return m
end

function PlaneService.recompute()
	local s =
		PlaneStats.compute(PlaneService.cells, { crew = PlaneService.crewCount, water = PlaneService.waterWeight })
	PlaneService.stats = s
	-- how much rainwater the ship can carry at cruising speed before it starts to sink
	PlaneService.waterMax = math.max(0, s.lift - (s.weight - PlaneService.waterWeight))
	local m = PlaneService.model
	if m then
		m:SetAttribute("Weight", s.weight)
		m:SetAttribute("DryWeight", s.dryWeight)
		m:SetAttribute("Lift", s.lift)
		m:SetAttribute("Margin", s.margin)
		m:SetAttribute("Thrust", s.thrust)
		m:SetAttribute("TopSpeed", s.topSpeed)
		m:SetAttribute("TurnRate", s.turnRate)
		m:SetAttribute("Stability", s.stability)
		m:SetAttribute("FuelMax", s.fuelMax)
		m:SetAttribute("Integrity", s.integrity)
		m:SetAttribute("Parts", s.parts)
		m:SetAttribute("Engines", s.engines)
		m:SetAttribute("Sails", s.sails)
		m:SetAttribute("Water", PlaneService.waterWeight)
		m:SetAttribute("WaterMax", PlaneService.waterMax)
		m:SetAttribute("Crew", PlaneService.crewCount)
	end
	return s
end

-- Connectivity -------------------------------------------------------------------

-- Keys of every piece touching `rec` (cells share faces; walls touch the floors they
-- stand on, the tiles beside them and walls stacked above/below).
local function neighbours(rec)
	local out = {}
	local function addKey(k)
		if k and PlaneService.cells[k] then
			table.insert(out, k)
		end
	end
	local c = rec.cell
	if rec.kind == "edge" then
		local ax, az, bx, bz = Grid.edgeSides(c.X, c.Z, rec.axis)
		for ly = c.Y - 1, c.Y + rec.span - 1 do
			addKey(Grid.key(ax, ly, az))
			addKey(Grid.key(bx, ly, bz))
		end
		addKey(PlaneService.faces[Grid.faceKey(c.X, c.Y - 1, c.Z, rec.axis)])
		addKey(PlaneService.faces[Grid.faceKey(c.X, c.Y + rec.span, c.Z, rec.axis)])
	else
		for _, d in ipairs(Grid.Dirs) do
			addKey(Grid.keyV(c + d))
		end
		for _, d in ipairs(HORIZ) do
			local fx, fz, fa = Grid.faceToward(c.X, c.Z, d)
			addKey(PlaneService.faces[Grid.faceKey(fx, c.Y, fz, fa)])
			addKey(PlaneService.faces[Grid.faceKey(fx, c.Y + 1, fz, fa)])
		end
	end
	return out
end

-- Keys reachable from the core (optionally pretending `excludeKey` is gone).
function PlaneService.connected(excludeKey)
	local seen = { [CORE_KEY] = true }
	local stack = { CORE_KEY }
	while #stack > 0 do
		local rec = PlaneService.cells[table.remove(stack)]
		if rec then
			for _, k in ipairs(neighbours(rec)) do
				if not seen[k] and k ~= excludeKey then
					seen[k] = true
					table.insert(stack, k)
				end
			end
		end
	end
	return seen
end

-- Placement rules ------------------------------------------------------------------

local function countPieces(typeName)
	local count, same = 0, 0
	for _, r in pairs(PlaneService.cells) do
		count += 1
		if r.type == typeName then
			same += 1
		end
	end
	return count, same
end

local function commonChecks(def, typeName, materialName)
	local mat = Materials.get(materialName)
	if not def or def.fixed then
		return false, "Unknown piece"
	elseif not mat then
		return false, "Unknown material"
	elseif not PartTypes.allows(typeName, materialName) then
		return false, def.display .. " can't be made of " .. mat.display
	elseif not CrewService.isMaterialUnlocked(materialName) then
		return false, mat.display .. " is still locked"
	end
	local count, same = countPieces(typeName)
	if count >= Config.MAX_PARTS then
		return false, "Piece limit reached"
	elseif def.maxPerShip and same >= def.maxPerShip then
		return false, string.format("Max %d %ss per ship: make them count!", def.maxPerShip, def.display)
	end
	return true
end

function PlaneService.canPlace(cellV, typeName, materialName)
	local def = PartTypes.get(typeName)
	if def and def.kind == "edge" then
		return false, "That piece snaps to edges"
	end
	local ok, err = commonChecks(def, typeName, materialName)
	if not ok then
		return false, err
	elseif not Grid.inBounds(cellV) then
		return false, "Outside the build bay"
	end
	local key = Grid.keyV(cellV)
	if PlaneService.isOccupied(key) then
		return false, "Something's already there"
	end
	local touching = false
	for _, d in ipairs(Grid.Dirs) do
		if PlaneService.isOccupied(Grid.keyV(cellV + d)) then
			touching = true
			break
		end
	end
	if not touching then
		for _, d in ipairs(HORIZ) do
			local fx, fz, fa = Grid.faceToward(cellV.X, cellV.Z, d)
			if
				PlaneService.faces[Grid.faceKey(fx, cellV.Y, fz, fa)]
				or PlaneService.faces[Grid.faceKey(fx, cellV.Y + 1, fz, fa)]
			then
				touching = true
				break
			end
		end
	end
	if not touching then
		return false, "Must attach to the airship"
	end
	if def.needsSupport then
		local below = PlaneService.cells[Grid.keyV(cellV - UP)]
		if not isDeck(below) or below.type == "Core" then
			return false, def.display .. " must stand on a floor"
		end
	end
	if def.needsMast then
		local below = PlaneService.cells[Grid.keyV(cellV - UP)]
		if not below or (below.type ~= "Mast" and below.type ~= "Sail") then
			return false, def.display .. " goes on top of a mast"
		end
	end
	if
		def.needsFrontClear
		and (PlaneService.isOccupied(Grid.keyV(cellV + FORWARD)) or edgeAtFace(cellV.X, cellV.Y, cellV.Z - 1, "Z"))
	then
		return false, "Propeller needs open air in front"
	end
	local behind = PlaneService.cells[Grid.keyV(cellV - FORWARD)]
	if behind and behind.type == "Engine" then
		return false, "That would block a propeller"
	end
	return true
end

function PlaneService.canPlaceEdge(x, y, z, axis, typeName, materialName)
	local def = PartTypes.get(typeName)
	if not def or def.kind ~= "edge" then
		return false, "That piece isn't a wall"
	end
	local ok, err = commonChecks(def, typeName, materialName)
	if not ok then
		return false, err
	end
	local span = def.span or 2
	local b = Config.BUILD_BOUNDS
	local ax, az, bx, bz = Grid.edgeSides(x, z, axis)
	local inA = ax >= b.minX and ax <= b.maxX and az >= b.minZ and az <= b.maxZ
	local inB = bx >= b.minX and bx <= b.maxX and bz >= b.minZ and bz <= b.maxZ
	if not (inA or inB) or y < 1 or y + span - 1 > b.maxY then
		return false, "Outside the build bay"
	end
	for i = 0, span - 1 do
		if PlaneService.faces[Grid.faceKey(x, y + i, z, axis)] then
			return false, "There's already a wall there"
		end
	end
	-- Rust rule: walls stand on a floor's edge (or on top of another wall)
	local floorBelow = isDeck(cellAt(ax, y - 1, az)) or isDeck(cellAt(bx, y - 1, bz))
	local wallBelow = PlaneService.faces[Grid.faceKey(x, y - 1, z, axis)] ~= nil
	if not floorBelow and not wallBelow then
		return false, def.display .. " must stand on the edge of a floor"
	end
	-- don't wall off a propeller
	for i = 0, span - 1 do
		if axis == "Z" then
			local e = cellAt(x, y + i, z + 1)
			if e and e.type == "Engine" then
				return false, "That would block a propeller"
			end
		end
	end
	return true
end

local function chargeFor(typeName, materialName)
	local currency, amount = PartTypes.cost(typeName, materialName, Materials)
	if not CrewService.spend(currency, amount) then
		return false,
			string.format("Need %d %s", amount, Materials.get(currency) and Materials.get(currency).display or currency)
	end
	return true
end

local function refundFor(typeName, materialName)
	local currency, amount = PartTypes.cost(typeName, materialName, Materials)
	CrewService.add(currency, amount)
end

-- spec = { cell = Vector3 } or { edge = { x, y, z, axis } }
function PlaneService.placePiece(spec, typeName, color, rot)
	local def = PartTypes.get(typeName)
	if not def then
		return false, "Unknown piece"
	end
	local material = PartTypes.placeMaterial(typeName)
	local key, ok, err
	if spec.edge then
		local e = spec.edge
		ok, err = PlaneService.canPlaceEdge(e[1], e[2], e[3], e[4], typeName, material)
		key = Grid.edgeKey(e[1], e[2], e[3], e[4])
	else
		ok, err = PlaneService.canPlace(spec.cell, typeName, material)
		key = Grid.keyV(spec.cell)
	end
	if not ok then
		return false, err
	end
	ok, err = chargeFor(typeName, material)
	if not ok then
		return false, err
	end
	local mat = Materials.get(material)
	local entry = {
		type = typeName,
		material = material,
		color = color or def.defaultColor or mat.color,
		rot = (def.rotatable or def.kind == "edge") and ((rot or 0) % 4) or 0,
	}
	PlaneService.blueprint[key] = entry
	local rec = spawnPiece(key, entry)
	refreshAround(rec)
	PlaneService.recompute()
	return true, rec
end

function PlaneService.removeKey(key)
	local rec = PlaneService.cells[key]
	if not rec then
		return false, "Nothing there"
	elseif rec.type == "Core" then
		return false, "The helm stays!"
	end
	if rec.kind ~= "edge" then
		local above = PlaneService.cells[Grid.keyV(rec.cell + UP)]
		if above and (PartTypes.get(above.type).needsSupport or PartTypes.get(above.type).needsMast) then
			return false, "Remove the " .. PartTypes.get(above.type).display .. " on top first"
		end
	end
	local seen = PlaneService.connected(key)
	for k in pairs(PlaneService.cells) do
		if k ~= key and not seen[k] then
			return false, "That would break off other pieces"
		end
	end
	refundFor(rec.type, rec.material)
	local rf = rec.reinforced and PartTypes.Reinforce[rec.type]
	if rf then
		for currency, amount in pairs(rf.cost) do
			CrewService.add(currency, amount)
		end
	end
	PlaneService.blueprint[key] = nil
	PlaneService.despawnCell(key)
	refreshAround(rec)
	PlaneService.recompute()
	return true
end

-- Rebuild one piece from its (changed) blueprint entry.
local function respawn(key)
	local entry = PlaneService.blueprint[key]
	PlaneService.despawnCell(key)
	local rec = spawnPiece(key, entry)
	refreshAround(rec)
	return rec
end

-- part = "trim" paints a piece's second colour (a balloon's stripe); color nil = automatic
function PlaneService.paintKey(key, color, part)
	local rec = PlaneService.cells[key]
	if not rec or not PlaneService.blueprint[key] then
		return false, "Nothing there"
	elseif rec.type == "Core" then
		return false, "The helm keeps its brass and oak!"
	end
	if part == "trim" then
		if not PartTypes.get(rec.type).trim then
			return false, "Only balloons have a stripe to paint"
		end
		PlaneService.blueprint[key].trim = color
	else
		PlaneService.blueprint[key].color = color
	end
	respawn(key)
	return true
end

-- Hammer: upgrade a piece to another material tier (pays the new cost, refunds the old).
-- Only tiers unlocked by landing on later islands count: Bamboo 2, Scrap 3, Tin 4.
function PlaneService.upgradeKey(key, materialName)
	local rec = PlaneService.cells[key]
	local entry = PlaneService.blueprint[key]
	if not rec or not entry then
		return false, "Nothing there"
	elseif rec.type == "Core" then
		return false, "The helm can't be upgraded"
	end
	local def = PartTypes.get(rec.type)
	local mat = Materials.get(materialName)
	if not mat or not PartTypes.allows(rec.type, materialName) then
		return false, def.display .. " can't be made of " .. tostring(materialName)
	elseif materialName == rec.material then
		return false, "It's already " .. mat.display
	elseif not Materials.upgradeIsland(materialName) then
		return false, mat.display .. " isn't an upgrade tier"
	elseif not CrewService.isUpgradeUnlocked(materialName) then
		return false,
			string.format("%s upgrades unlock at island %d", mat.display, Materials.upgradeIsland(materialName))
	end
	local ok, err = chargeFor(rec.type, materialName)
	if not ok then
		return false, err
	end
	refundFor(rec.type, rec.material)
	-- an unpainted piece takes on the new material's natural colour
	local oldMat = Materials.get(entry.material)
	if entry.color == oldMat.color or entry.color == def.defaultColor then
		entry.color = def.defaultColor or mat.color
	end
	entry.material = materialName
	respawn(key)
	PlaneService.recompute()
	return true
end

-- Hammer: add a discovered reinforcement (PartTypes.Reinforce) to a piece.
function PlaneService.reinforceKey(key)
	local rec = PlaneService.cells[key]
	local entry = PlaneService.blueprint[key]
	local rf = rec and PartTypes.Reinforce[rec.type]
	if not rec or not entry then
		return false, "Nothing there"
	elseif not rf then
		return false, PartTypes.get(rec.type).display .. " can't be reinforced"
	elseif entry.reinforced then
		return false, "Already reinforced"
	elseif not CrewService.state():GetAttribute(rf.unlock) then
		return false, "Find the plans first: they're at " .. rf.where
	end
	for currency, amount in pairs(rf.cost) do
		if CrewService.get(currency) < amount then
			return false,
				string.format(
					"Need %d %s",
					amount,
					Materials.get(currency) and Materials.get(currency).display or currency
				)
		end
	end
	for currency, amount in pairs(rf.cost) do
		CrewService.spend(currency, amount)
	end
	entry.reinforced = true
	respawn(key)
	PlaneService.recompute()
	return true
end

function PlaneService.rotateKey(key)
	local rec = PlaneService.cells[key]
	local entry = PlaneService.blueprint[key]
	if not rec or not entry then
		return false, "Nothing there"
	end
	local def = PartTypes.get(rec.type)
	if rec.kind == "edge" then
		entry.rot = ((entry.rot or 0) + 2) % 4
	elseif def.rotatable then
		entry.rot = ((entry.rot or 0) + 1) % 4
	else
		return false, def.display .. " can't be rotated"
	end
	respawn(key)
	return true
end

-- Detach a piece mid-flight (destroyed by damage). Cascades to anything left floating.
function PlaneService.breakOff(key, velocity)
	local rec = PlaneService.cells[key]
	if not rec or rec.type == "Core" then
		return
	end
	PlaneService.cells[key] = nil
	clearFaces(rec)
	if PlaneService.onCellRemoved then
		PlaneService.onCellRemoved(rec)
	end
	local model = rec.model
	for _, d in ipairs(model:GetDescendants()) do
		if d.Name == "PlaneWeld" or d:IsA("ProximityPrompt") then
			d:Destroy()
		elseif d:IsA("BasePart") then
			d.Massless = false
		end
	end
	model.Parent = workspace
	velocity = velocity or Vector3.zero
	rec.main.AssemblyLinearVelocity = velocity
		+ Vector3.new(math.random(-15, 15), math.random(5, 20), math.random(-15, 15))
	rec.main.AssemblyAngularVelocity = Vector3.new(math.random(-5, 5), math.random(-5, 5), math.random(-5, 5))
	Debris:AddItem(model, 12)
	CrewService.stat("partsLost")

	PlaneService.exposedDirty = true
	local seen = PlaneService.connected()
	local orphans = {}
	for k, r in pairs(PlaneService.cells) do
		local unsupported = r.kind ~= "edge"
			and PartTypes.get(r.type).needsSupport
			and not PlaneService.cells[Grid.keyV(r.cell - UP)]
		if not seen[k] or unsupported then
			table.insert(orphans, k)
		end
	end
	for _, k in ipairs(orphans) do
		PlaneService.breakOff(k, velocity)
	end
	PlaneService.recompute()
end

-- Break every piece off (crash).
function PlaneService.explode()
	local vel = PlaneService.core and PlaneService.core.AssemblyLinearVelocity or Vector3.zero
	local keys = {}
	for k, r in pairs(PlaneService.cells) do
		if r.type ~= "Core" then
			table.insert(keys, k)
		end
	end
	for _, k in ipairs(keys) do
		if PlaneService.cells[k] then
			PlaneService.breakOff(k, vel * 0.4 + Vector3.new(0, 25, 0))
		end
	end
end

-- Is this character standing on / sitting in the ship?
function PlaneService.isAboard(character)
	local core = PlaneService.core
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	if not core or not hrp then
		return false
	end
	local hum = character:FindFirstChildOfClass("Humanoid")
	if hum and hum.SeatPart and hum.SeatPart:IsDescendantOf(PlaneService.model) then
		return true
	end
	local p = core.CFrame:PointToObjectSpace(hrp.Position)
	return math.abs(p.X) < 38 and p.Y > -6 and p.Y < 34 and p.Z > -46 and p.Z < 50
end

-- Anything built anywhere above a floor keeps the rain off it.
local function covered(cellV)
	for y = cellV.Y + 1, Config.BUILD_BOUNDS.maxY do
		if PlaneService.isOccupied(Grid.key(cellV.X, y, cellV.Z)) then
			return true
		end
	end
	return false
end

-- Open floor cells (rain collects here). Cached until the ship changes.
local exposedCache = {}
function PlaneService.exposedDeckKeys()
	if not PlaneService.exposedDirty then
		return exposedCache
	end
	local list = {}
	for k, r in pairs(PlaneService.cells) do
		if r.kind ~= "edge" and PartTypes.get(r.type).rails and r.type ~= "Core" and not covered(r.cell) then
			table.insert(list, k)
		end
	end
	exposedCache = list
	PlaneService.exposedDirty = false
	return list
end

-- Build remote ------------------------------------------------------------------------

local function worldPosOf(key)
	local rec = PlaneService.cells[key]
	return rec and rec.main.Position or (PlaneService.core and PlaneService.core.Position)
end

local lastAction = {}
local function handleBuild(player, action, data)
	if typeof(data) ~= "table" then
		return false, "Bad request"
	end
	local now = os.clock()
	if lastAction[player] and now - lastAction[player] < 0.08 then
		return false, nil
	end
	lastAction[player] = now
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not hrp or not PlaneService.core then
		return false, "No airship"
	end

	-- Hammer repairs work in the air too (that's the crew's job!)
	if action == "repair" then
		local rec = typeof(data.key) == "string" and PlaneService.cells[data.key]
		if not rec then
			return false, nil
		end
		-- balloons float high on their tethers, so they're mended from below: only the flat
		-- distance to their cell counts
		local reach
		if rec.type == "Balloon" then
			local p = worldPosOf(rec.key)
			reach = Vector3.new(hrp.Position.X - p.X, 0, hrp.Position.Z - p.Z).Magnitude
		else
			reach = (hrp.Position - rec.main.Position).Magnitude
		end
		if reach > 14 then
			return false, "Get closer to repair it"
		end
		if rec.hp >= rec.maxHp then
			return false, "It's in good shape"
		end
		if PlaneService.repairHook then
			PlaneService.repairHook(rec, player)
		end
		return true
	end

	if CrewService.getPhase() ~= "Build" then
		return false, "You can only build in the hangar"
	end
	if (hrp.Position - PlaneService.core.Position).Magnitude > 90 then
		return false, "Get closer to the airship"
	end
	local doMirror = data.mirror == true
	local ok, err, where
	if action == "place" then
		local color = typeof(data.color) == "Color3" and data.color or nil
		local rot = typeof(data.rot) == "number" and math.clamp(math.floor(data.rot), 0, 3) or 0
		if typeof(data.edge) == "table" then
			local e = data.edge
			local x, y, z, axis = tonumber(e[1]), tonumber(e[2]), tonumber(e[3]), e[4]
			if not (x and y and z) or (axis ~= "X" and axis ~= "Z") then
				return false, "Bad request"
			end
			x, y, z = math.round(x), math.round(y), math.round(z)
			ok, err = PlaneService.placePiece({ edge = { x, y, z, axis } }, data.partType, color, rot)
			if ok and doMirror then
				local mx, my, mz, ma = Grid.mirrorEdge(x, y, z, axis)
				if Grid.edgeKey(mx, my, mz, ma) ~= Grid.edgeKey(x, y, z, axis) then
					PlaneService.placePiece({ edge = { mx, my, mz, ma } }, data.partType, color, rot)
				end
			end
			where = PlaneService.core.CFrame * Grid.edgeCFrame(x, y, z, axis).Position
		elseif typeof(data.cell) == "Vector3" then
			local cell = Vector3.new(math.round(data.cell.X), math.round(data.cell.Y), math.round(data.cell.Z))
			ok, err = PlaneService.placePiece({ cell = cell }, data.partType, color, rot)
			if ok and doMirror and cell.X ~= 0 then
				PlaneService.placePiece(
					{ cell = Vector3.new(-cell.X, cell.Y, cell.Z) },
					data.partType,
					color,
					Grid.mirrorRot(rot)
				)
			end
			where = PlaneService.core.CFrame * Grid.offset(cell)
		else
			return false, "Bad request"
		end
	else
		local key = data.key
		if typeof(key) ~= "string" or not PlaneService.cells[key] then
			return false, "Nothing there"
		end
		where = worldPosOf(key)
		local mirrorKey = Grid.mirrorKey(key)
		local mirrorOk = doMirror and mirrorKey ~= key and PlaneService.cells[mirrorKey] ~= nil
		if action == "remove" then
			ok, err = PlaneService.removeKey(key)
			if ok and mirrorOk then
				PlaneService.removeKey(mirrorKey)
			end
		elseif action == "paint" then
			local part = data.part == "trim" and "trim" or nil
			-- a stripe can go back to automatic (no colour); a body always needs one
			if typeof(data.color) ~= "Color3" and not (part == "trim" and data.color == nil) then
				return false, "Pick a colour"
			end
			ok, err = PlaneService.paintKey(key, data.color, part)
			if ok and mirrorOk then
				PlaneService.paintKey(mirrorKey, data.color, part)
			end
		elseif action == "upgrade" then
			ok, err = PlaneService.upgradeKey(key, data.material)
			if ok and mirrorOk then
				PlaneService.upgradeKey(mirrorKey, data.material)
			end
		elseif action == "reinforce" then
			ok, err = PlaneService.reinforceKey(key)
			if ok and mirrorOk then
				PlaneService.reinforceKey(mirrorKey)
			end
		elseif action == "rotate" then
			ok, err = PlaneService.rotateKey(key)
		else
			return false, "Unknown action"
		end
	end
	if ok then
		CrewService.sfx("Hammer", where)
		return true
	end
	return false, err
end

function PlaneService.init()
	PlaneService.resetBlueprint()
	Remotes.get("BuildAction").OnServerInvoke = handleBuild
end

return PlaneService
