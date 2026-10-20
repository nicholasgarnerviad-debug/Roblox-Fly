-- Build-grid helpers. Cells are integer (x, y, z) offsets from the cockpit core.
local Config = require(script.Parent.Config)

local Grid = {}

Grid.Dirs = {
	Vector3.new(1, 0, 0),
	Vector3.new(-1, 0, 0),
	Vector3.new(0, 1, 0),
	Vector3.new(0, -1, 0),
	Vector3.new(0, 0, 1),
	Vector3.new(0, 0, -1),
}

function Grid.key(x, y, z)
	return x .. "," .. y .. "," .. z
end

function Grid.keyV(v)
	return Grid.key(v.X, v.Y, v.Z)
end

function Grid.parse(key)
	local x, y, z = string.match(key, "^(-?%d+),(-?%d+),(-?%d+)$")
	return tonumber(x), tonumber(y), tonumber(z)
end

function Grid.parseV(key)
	local x, y, z = Grid.parse(key)
	return Vector3.new(x, y, z)
end

function Grid.offset(cell)
	return cell * Config.CELL
end

function Grid.inBounds(cell)
	local b = Config.BUILD_BOUNDS
	return cell.X >= b.minX
		and cell.X <= b.maxX
		and cell.Y >= b.minY
		and cell.Y <= b.maxY
		and cell.Z >= b.minZ
		and cell.Z <= b.maxZ
end

-- Snap an arbitrary direction to the nearest axis unit vector.
function Grid.roundNormal(v)
	local ax, ay, az = math.abs(v.X), math.abs(v.Y), math.abs(v.Z)
	if ax >= ay and ax >= az then
		return Vector3.new(math.sign(v.X), 0, 0)
	elseif ay >= az then
		return Vector3.new(0, math.sign(v.Y), 0)
	end
	return Vector3.new(0, 0, math.sign(v.Z))
end

-- Rotations are quarter turns about Y (0..3). rot 0 faces forward (-Z).
function Grid.rotCFrame(rot)
	return CFrame.Angles(0, (rot or 0) * math.pi / 2, 0)
end

-- Facing of a rotation as a cell direction.
function Grid.rotForward(rot)
	local v = Grid.rotCFrame(rot):VectorToWorldSpace(Vector3.new(0, 0, -1))
	return Vector3.new(math.round(v.X), 0, math.round(v.Z))
end

-- Rotation mirrored across the ship's centre line (x -> -x).
function Grid.mirrorRot(rot)
	return (4 - (rot or 0)) % 4
end

-- Edges (Rust-style walls) -----------------------------------------------------
-- An edge is the face between two tiles. Key "E:x,y,z,A": (x,z) is the tile on the
-- negative side, A is "X" (face between x and x+1) or "Z" (between z and z+1), and
-- y is the lowest level the piece fills. Face keys mark each level it covers.

function Grid.edgeKey(x, y, z, axis)
	return string.format("E:%d,%d,%d,%s", x, y, z, axis)
end

function Grid.isEdgeKey(key)
	return string.sub(key, 1, 2) == "E:"
end

function Grid.parseEdge(key)
	local x, y, z, a = string.match(key, "^E:(-?%d+),(-?%d+),(-?%d+),([XZ])$")
	return tonumber(x), tonumber(y), tonumber(z), a
end

function Grid.faceKey(x, y, z, axis)
	return x .. "," .. y .. "," .. z .. "," .. axis
end

-- Core-local CFrame at the bottom-middle of an edge: X runs along it, Z points to the + side.
function Grid.edgeCFrame(x, y, z, axis)
	local c = Config.CELL
	if axis == "X" then
		return CFrame.new((x + 0.5) * c, y * c - c / 2, z * c) * CFrame.Angles(0, math.pi / 2, 0)
	end
	return CFrame.new(x * c, y * c - c / 2, (z + 0.5) * c)
end

-- The face between tile (x,z) and its neighbour in horizontal direction d.
function Grid.faceToward(x, z, d)
	if d.X > 0.5 then
		return x, z, "X"
	elseif d.X < -0.5 then
		return x - 1, z, "X"
	elseif d.Z > 0.5 then
		return x, z, "Z"
	end
	return x, z - 1, "Z"
end

-- Tiles on either side of an edge.
function Grid.edgeSides(x, z, axis)
	if axis == "X" then
		return x, z, x + 1, z
	end
	return x, z, x, z + 1
end

-- Edge mirrored across the ship's centre line.
function Grid.mirrorEdge(x, y, z, axis)
	if axis == "X" then
		return -x - 1, y, z, axis
	end
	return -x, y, z, axis
end

-- Mirror any piece key (cell or edge).
function Grid.mirrorKey(key)
	if Grid.isEdgeKey(key) then
		return Grid.edgeKey(Grid.mirrorEdge(Grid.parseEdge(key)))
	end
	local x, y, z = Grid.parse(key)
	return Grid.key(-x, y, z)
end

-- Nearest cell to a position given in the core's local space.
function Grid.cellFromLocal(localPos)
	local c = Config.CELL
	return Vector3.new(math.round(localPos.X / c), math.round(localPos.Y / c), math.round(localPos.Z / c))
end

return Grid
