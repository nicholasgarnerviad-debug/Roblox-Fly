-- Derives flight stats from a set of plane cells.
-- cells: { [key] = { type, material, hp?, maxHp?, soak?, sputter? } }
-- extras: { crew = number, water = number (puddle weight), speedBonus = number (perks) }
--
-- The split: balloons give lift at any speed and only weather damage weakens them;
-- engines, sails and wings give speed (weight never slows you down); wings also give lift
-- that needs airspeed. Weight is only ever weighed against lift.
local Config = require(script.Parent.Config)
local Materials = require(script.Parent.Materials)
local PartTypes = require(script.Parent.PartTypes)

local PlaneStats = {}

function PlaneStats.maxHp(typeName, materialName, reinforced)
	local def = PartTypes.get(typeName)
	local mat = Materials.get(materialName)
	local rf = reinforced and PartTypes.Reinforce[typeName]
	return math.floor(def.hp * mat.hp * (rf and rf.hp or 1) + 0.5)
end

function PlaneStats.compute(cells, extras)
	extras = extras or {}
	local s = {
		weight = 0,
		dryWeight = 0,
		lift = 0,
		staticLift = 0,
		dynamicLift = 0,
		thrust = 0,
		drag = 0,
		stability = 0,
		engineThrust = 0,
		sailThrust = 0,
		sails = 0,
		fuelMax = 0,
		engines = 0,
		parts = 0,
		wings = 0,
		balloons = 0,
		hpNow = 0,
		hpMax = 0,
	}
	local engineSpeeds, sailSpeeds, wingSpeeds = {}, {}, {}
	local SP = Config.Flight.Speed
	for _, cell in pairs(cells) do
		local def = PartTypes.get(cell.type)
		local mat = Materials.get(cell.material)
		if def and mat then
			local rf = cell.reinforced and PartTypes.Reinforce[cell.type]
			local maxHp = cell.maxHp or PlaneStats.maxHp(cell.type, cell.material, cell.reinforced)
			local hp = cell.hp or maxHp
			local hpFrac = math.clamp(hp / maxHp, 0, 1)
			local soak = cell.soak or 0

			local dry = def.weight * mat.weight + (rf and rf.extraWeight or 0)
			s.dryWeight += dry
			s.weight += dry * (1 + mat.soak * soak)
			s.dynamicLift += (def.lift or 0) * mat.lift * (0.4 + 0.6 * hpFrac)
			-- a reinforced balloon holds together when torn, so it keeps more of its lift
			s.staticLift += (def.staticLift or 0) * mat.lift * (rf and (0.6 + 0.4 * hpFrac) or (0.3 + 0.7 * hpFrac))
			s.drag += def.drag or 0
			s.stability += (def.stability or 0) * (0.5 + 0.5 * hpFrac)
			s.fuelMax += def.fuel or 0
			s.parts += 1
			s.hpNow += hp
			s.hpMax += maxHp
			if cell.type == "Wing" then
				s.wings += 1
				table.insert(wingSpeeds, SP.PerWing * (0.4 + 0.6 * hpFrac))
			elseif cell.type == "Balloon" then
				s.balloons += 1
			end
			if def.thrust then
				s.engines += 1
				local t = def.thrust * mat.thrust * (0.3 + 0.7 * hpFrac)
				local v = SP.PerEngine * mat.thrust * (0.3 + 0.7 * hpFrac)
				if cell.sputter then
					t *= 0.25
					v *= 0.25
				end
				s.engineThrust += t
				table.insert(engineSpeeds, v)
			end
			if def.sailThrust then
				s.sails += 1
				s.sailThrust += def.sailThrust * (0.3 + 0.7 * hpFrac)
				table.insert(sailSpeeds, SP.PerSail * (def.sailThrust / 14) * (0.3 + 0.7 * hpFrac))
			end
		end
	end

	s.weight += (extras.crew or 0) * Config.Flight.CrewWeight + (extras.water or 0)
	s.lift = s.staticLift + s.dynamicLift
	s.margin = s.weight > 0 and s.lift / s.weight or 0

	s.thrust = s.engineThrust + s.sailThrust
	-- speed: each extra engine/sail/wing adds a little less than the one before
	local function stack(list, falloff)
		table.sort(list, function(a, b)
			return a > b
		end)
		local sum = 0
		for i, v in ipairs(list) do
			sum += v * falloff ^ (i - 1)
		end
		return sum
	end
	s.engineSpeed = stack(engineSpeeds, SP.Falloff.Engine)
	s.sailSpeed = stack(sailSpeeds, SP.Falloff.Sail)
	s.wingSpeed = stack(wingSpeeds, SP.Falloff.Wing)
	-- base speed and wings count while something pushes: running engines, or sails
	local carried = SP.Base + s.wingSpeed + (extras.speedBonus or 0)
	s.topSpeed = s.thrust > 0 and math.min(SP.Max, carried + s.sailSpeed + s.engineSpeed) or 0
	-- with empty tanks only sails keep you going (no sails: you glide)
	s.sailTopSpeed = s.sailThrust > 0 and math.min(SP.Max, carried + s.sailSpeed) or 0
	s.turnRate = math.clamp(26 + 12 * math.min(s.stability, 3) - s.weight * 0.08, 14, 60)
	s.integrity = s.hpMax > 0 and s.hpNow / s.hpMax or 1
	return s
end

-- Short human-readable verdict for the build panel.
function PlaneStats.verdict(s)
	if s.engines == 0 and (s.sails or 0) == 0 then
		return "No engine or sail! Add one to fly.", Color3.fromRGB(235, 80, 70)
	elseif s.margin < 1.0 then
		return "Too heavy: it will sink. Add balloons/wings or remove weight.", Color3.fromRGB(235, 80, 70)
	elseif s.margin < 1.15 then
		return "Barely flies. The rain will drag you down.", Color3.fromRGB(245, 180, 60)
	elseif s.margin < 1.4 then
		return "Flight-worthy. Keep that deck dry!", Color3.fromRGB(120, 210, 110)
	end
	return "Soars like a gull!", Color3.fromRGB(110, 200, 240)
end

return PlaneStats
