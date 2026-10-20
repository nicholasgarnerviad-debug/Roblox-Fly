--[[
	Runs the TestEZ specs in tests/ headlessly with Lune: `lune run scripts/run-tests`

	TestEZ officially runs only inside Roblox (or the retired Lemur emulator), so this builds
	test.project.json with Rojo, loads the place with Lune's roblox library, and gives every
	ModuleScript a small Roblox-like environment: `script`, `game`, instance `require`,
	`tick`, and the datatypes Lune implements (Vector3, CFrame, Color3, ...).

	Code that needs the live engine (services, physics, DataStores) can't run here, so keep
	specs to pure logic.
]]
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local task = require("@lune/task")

local PLACE = "build/tests.rbxl"

if not fs.isDir("build") then
	fs.writeDir("build")
end
local build = process.exec("rojo", { "build", "test.project.json", "-o", PLACE })
if not build.ok then
	print(build.stdout .. build.stderr)
	print("tests: rojo build failed")
	process.exit(1)
end

local game = roblox.deserializePlace(fs.readFile(PLACE))
local outer = getfenv(1)
local shared = {} -- what modules see as _G

local DATATYPES = {
	"Axes",
	"BrickColor",
	"CFrame",
	"Color3",
	"ColorSequence",
	"ColorSequenceKeypoint",
	"Enum",
	"Faces",
	"Font",
	"Instance",
	"NumberRange",
	"NumberSequence",
	"NumberSequenceKeypoint",
	"PhysicalProperties",
	"Ray",
	"Rect",
	"Region3",
	"Region3int16",
	"UDim",
	"UDim2",
	"Vector2",
	"Vector2int16",
	"Vector3",
	"Vector3int16",
}

-- Lune may hand back a fresh wrapper for the same instance, so modules are cached by path.
local cache = {}
local loading = {}
local requireModule

local function environmentFor(module)
	local env = {
		script = module,
		game = game,
		workspace = game:GetService("Workspace"),
		require = requireModule,
		tick = os.clock,
		time = os.clock,
		task = task,
		warn = print,
		_G = shared,
	}
	for _, name in DATATYPES do
		env[name] = roblox[name]
	end
	-- everything else (string, table, math, pcall, getfenv, ...) falls through to Lune's globals
	return setmetatable(env, { __index = outer })
end

function requireModule(target)
	if typeof(target) ~= "Instance" or not target:IsA("ModuleScript") then
		error("require() needs a ModuleScript in the test runner, got " .. typeof(target), 2)
	end
	local key = target:GetFullName()
	local hit = cache[key]
	if hit then
		return hit.value
	end
	if loading[key] then
		error("cyclic require of " .. key, 2)
	end
	loading[key] = true
	local chunk = luau.load(target.Source, {
		debugName = key,
		environment = environmentFor(target),
		injectGlobals = false,
	})
	local value = table.pack(chunk())
	loading[key] = nil
	if value.n ~= 1 then
		error(key .. ": module code did not return exactly one value", 2)
	end
	cache[key] = { value = value[1] }
	return value[1]
end

-- Prints the result tree, TestEZ TextReporter-style (that one logs through TestService).
local MARK = { Success = "+", Failure = "x", Skipped = "~" }
local function report(results)
	local shown = {}
	local function walk(node, depth)
		for _, child in node.children do
			local pad = string.rep("  ", depth)
			print(pad .. (MARK[child.status] or "?") .. " " .. child.planNode.phrase)
			for _, message in child.errors do
				shown[message] = true
				print(pad .. "    " .. string.gsub(message, "\n", "\n" .. pad .. "    "))
			end
			walk(child, depth + 1)
		end
	end
	walk(results, 0)
	-- TestEZ also lists every test failure here; only print what the tree didn't (e.g. hook errors)
	for _, message in results.errors do
		if not shown[message] then
			print(message)
		end
	end
	print(
		string.format(
			"%d passed, %d failed, %d skipped",
			results.successCount,
			results.failureCount,
			results.skippedCount
		)
	)
end

local replicated = game:GetService("ReplicatedStorage")
local ok, results = pcall(function()
	local TestEZ = requireModule(replicated:FindFirstChild("DevPackages"):FindFirstChild("TestEZ"))
	return TestEZ.TestBootstrap:run({ replicated:FindFirstChild("Tests") }, { report = report })
end)
if not ok then
	print("tests: could not run the suite")
	print(results)
	process.exit(1)
end
if results.successCount + results.failureCount == 0 then
	print("tests: no specs ran")
	process.exit(1)
end
process.exit((results.failureCount > 0 or #results.errors > 0) and 1 or 0)
