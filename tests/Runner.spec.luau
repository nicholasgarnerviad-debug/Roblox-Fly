-- Proves the test pipeline itself works: specs run, Roblox datatypes exist, and modules can
-- require each other through instances. Real specs for src/ go next to this one.
return function()
	describe("headless test runner", function()
		it("runs expectations", function()
			expect(1 + 1).to.equal(2)
			expect(function()
				error("boom")
			end).to.throw()
		end)

		it("provides Roblox datatypes", function()
			local sum = Vector3.new(1, 2, 3) + Vector3.new(1, 1, 1)
			expect(sum.Y).to.equal(3)
			expect(typeof(CFrame.new())).to.equal("CFrame")
		end)

		it("requires modules by instance", function()
			local answer = require(script.Parent.Fixtures.Answer)
			expect(answer()).to.equal(42)
		end)
	end)
end
