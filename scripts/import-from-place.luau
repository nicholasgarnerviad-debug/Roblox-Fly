--[[
	One-off import of the place's scripts into src/, Rojo file conventions:
	  lune run scripts/import-from-place [place.rbxl] [manifest.json]

	  Folder        -> directory
	  ModuleScript  -> Name.luau
	  Script        -> Name.server.luau
	  LocalScript   -> Name.client.luau

	Sources are copied byte-for-byte from the saved place. If a manifest of the live Studio
	scripts is given (build/studio-manifest.json, made through the Studio MCP), every script
	is checked against its hash so src/ provably matches what Studio is running.
	Refuses to run if src/ already has code, so it can't clobber edits.
]]
local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")

local placePath = process.args[1] or "PatchworkSkies.rbxl"
local manifestPath = process.args[2] or "build/studio-manifest.json"

-- FNV-1a 32-bit, identical to the one run inside Studio for the manifest
local function fnv(s: string): string
	local h = 2166136261
	for i = 1, #s do
		h = bit32.bxor(h, string.byte(s, i))
		h = (bit32.lshift(h, 24) + h * 403) % 4294967296
	end
	return string.format("%08x", h)
end

local function hasCode(dir: string): boolean
	for _, name in fs.readDir(dir) do
		local path = dir .. "/" .. name
		if fs.isDir(path) then
			if hasCode(path) then
				return true
			end
		elseif string.match(name, "%.luau?$") then
			return true
		end
	end
	return false
end

local game = roblox.deserializePlace(fs.readFile(placePath))
local ROOTS = {
	{ dir = "src/shared", instance = game:GetService("ReplicatedStorage"):FindFirstChild("Shared") },
	{ dir = "src/server", instance = game:GetService("ServerScriptService"):FindFirstChild("Server") },
	{
		dir = "src/client",
		instance = game:GetService("StarterPlayer"):FindFirstChild("StarterPlayerScripts"):FindFirstChild("Client"),
	},
}

for _, root in ROOTS do
	assert(root.instance, "missing " .. root.dir .. " container in " .. placePath)
	if fs.isDir(root.dir) and hasCode(root.dir) then
		print("refusing: " .. root.dir .. " already contains code")
		process.exit(1)
	end
end

local SUFFIX = { ModuleScript = ".luau", Script = ".server.luau", LocalScript = ".client.luau" }
local exported = {}
local problems = {}

-- exported is keyed "<root dir>/<dotted path>", the same way the manifest names things
local function export(instance, rootDir: string, dir: string, rel: string)
	local name = instance.Name
	local path = rel == "" and name or rel .. "." .. name
	local key = rootDir .. "/" .. path
	if instance.ClassName == "Folder" then
		fs.writeDir(dir .. "/" .. name)
		exported[key] = { class = "Folder" }
		for _, child in instance:GetChildren() do
			export(child, rootDir, dir .. "/" .. name, path)
		end
	elseif SUFFIX[instance.ClassName] then
		if #instance:GetChildren() > 0 then
			table.insert(problems, key .. ": script has children (needs an init file), not exported")
			return
		end
		fs.writeFile(dir .. "/" .. name .. SUFFIX[instance.ClassName], instance.Source)
		exported[key] = { class = instance.ClassName, len = #instance.Source, hash = fnv(instance.Source) }
	else
		table.insert(problems, key .. ": " .. instance.ClassName .. " is not a script or folder, not exported")
	end
end

for _, root in ROOTS do
	fs.writeDir(root.dir)
	for _, child in root.instance:GetChildren() do
		export(child, root.dir, root.dir, "")
	end
end

-- compare with the live Studio manifest
local checked, mismatched = 0, 0
if fs.isFile(manifestPath) then
	local manifest = serde.decode("json", fs.readFile(manifestPath))
	local seen = {}
	for _, item in manifest.items do
		local key = item.root .. "/" .. item.path
		local mine = exported[key]
		seen[key] = true
		if not mine then
			mismatched += 1
			print("MISSING from export: " .. item.root .. "/" .. item.path)
		elseif mine.class ~= item.class or mine.hash ~= item.hash or mine.len ~= item.len then
			mismatched += 1
			print(
				string.format(
					"DIFFERS: %s/%s studio %s %s/%s, file %s %s/%s",
					item.root,
					item.path,
					item.class,
					tostring(item.len),
					tostring(item.hash),
					mine.class,
					tostring(mine.len),
					tostring(mine.hash)
				)
			)
		else
			checked += 1
		end
	end
	for key in exported do
		if not seen[key] then
			mismatched += 1
			print("EXTRA in export (not live in Studio): " .. key)
		end
	end
	print(string.format("verified against Studio: %d match, %d differ", checked, mismatched))
else
	print("no manifest at " .. manifestPath .. ", skipped verification")
end

for _, message in problems do
	print("PROBLEM: " .. message)
end
local count = 0
for _, info in exported do
	if info.class ~= "Folder" then
		count += 1
	end
end
print(string.format("exported %d scripts into src/", count))
process.exit((mismatched > 0 or #problems > 0) and 1 or 0)
