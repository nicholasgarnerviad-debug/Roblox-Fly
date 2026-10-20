--[[
	Every check in one command, from the repo folder: `lune run scripts/check`

	  selene  lint src/ and tests/ (Roblox std + TestEZ globals)
	  stylua  formatting, check only (never rewrites files)
	  tests   TestEZ specs in tests/, run headlessly (scripts/run-tests.luau)

	Runs every step even if an earlier one fails, then exits non-zero if any did.
]]
local process = require("@lune/process")

local STEPS = {
	{ name = "selene", program = "selene", args = { "src", "tests" } },
	{ name = "stylua", program = "stylua", args = { "--check", "src", "tests", "scripts" } },
	{ name = "tests", program = "lune", args = { "run", "scripts/run-tests" } },
}

local failed = {}
for _, step in STEPS do
	print(string.format("== %s: %s %s", step.name, step.program, table.concat(step.args, " ")))
	local result = process.exec(step.program, step.args, { stdio = "forward" })
	if result.ok then
		print(string.format("== %s: PASS\n", step.name))
	else
		print(string.format("== %s: FAIL (exit %d)\n", step.name, result.code))
		table.insert(failed, step.name)
	end
end

if #failed > 0 then
	print("CHECKS FAILED: " .. table.concat(failed, ", "))
	process.exit(1)
end
print("ALL CHECKS PASSED")
