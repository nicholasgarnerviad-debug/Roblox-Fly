-- Hotbar: replaces Roblox's default backpack bar with one that matches the HUD.
-- Number keys (or a click) equip and put away tools. Hidden while you're piloting.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Weapons = require(Shared.Weapons)
local UI = require(script.Parent.Parent.UI)

local player = Players.LocalPlayer
local C = UI.Colors

local Hotbar = {}

local ICONS = { ["Building Plan"] = "\u{1F4D8}", Hammer = "\u{1F528}", ["Paint Brush"] = "\u{1F58C}\u{FE0F}" }
local ORDER = { ["Building Plan"] = 1, Hammer = 2, ["Paint Brush"] = 3 }
local NUMBER_KEYS = {
	[Enum.KeyCode.One] = 1,
	[Enum.KeyCode.Two] = 2,
	[Enum.KeyCode.Three] = 3,
	[Enum.KeyCode.Four] = 4,
	[Enum.KeyCode.Five] = 5,
	[Enum.KeyCode.Six] = 6,
	[Enum.KeyCode.Seven] = 7,
	[Enum.KeyCode.Eight] = 8,
	[Enum.KeyCode.Nine] = 9,
}

local HUD, bar
local list = {}
local dirty = true

local function info(tool)
	local w = tool:GetAttribute("Weapon")
	local def = w and Weapons.get(w)
	return (def and def.icon) or ICONS[tool.Name] or "\u{2754}", (def and def.display) or tool.Name
end

local function rank(tool)
	if ORDER[tool.Name] then
		return ORDER[tool.Name]
	end
	return tool:GetAttribute("Weapon") == "Cutlass" and 4 or 5
end

local function collect()
	local found, seen = {}, {}
	for _, container in ipairs({ player:FindFirstChildOfClass("Backpack"), player.Character }) do
		for _, t in ipairs(container and container:GetChildren() or {}) do
			if t:IsA("Tool") and not seen[t] then
				seen[t] = true
				table.insert(found, t)
			end
		end
	end
	table.sort(found, function(a, b)
		local ra, rb = rank(a), rank(b)
		if ra ~= rb then
			return ra < rb
		end
		return a.Name < b.Name
	end)
	return found
end

local function toggle(tool)
	local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if not hum or hum.Health <= 0 then
		return
	end
	if tool.Parent == player.Character then
		hum:UnequipTools()
	else
		hum:EquipTool(tool)
	end
end

local function rebuild()
	dirty = false
	for _, c in ipairs(bar:GetChildren()) do
		if c:IsA("GuiButton") then
			c:Destroy()
		end
	end
	list = collect()
	for i, tool in ipairs(list) do
		local icon, name = info(tool)
		local held = tool.Parent == player.Character
		local b =
			UI.button({ Name = "Slot" .. i, Size = UDim2.fromOffset(66, 62), Text = "", LayoutOrder = i, Parent = bar })
		if held then
			b.BackgroundColor3 = C.panel3
			UI.stroke(b, C.accent, 2.5, 0)
		end
		UI.label({
			Position = UDim2.fromOffset(0, 6),
			Size = UDim2.new(1, 0, 0, 30),
			Text = icon,
			TextSize = 26,
			Parent = b,
		})
		UI.label({
			Position = UDim2.new(0, 2, 1, -20),
			Size = UDim2.new(1, -4, 0, 16),
			Text = name,
			TextSize = 11,
			Font = UI.Body,
			TextColor3 = held and C.accent or C.dim,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Parent = b,
		})
		if i <= 9 then
			UI.keycap(tostring(i), {
				Position = UDim2.fromOffset(4, 4),
				Size = UDim2.fromOffset(0, 16),
				TextSize = 10,
				ZIndex = 3,
				Parent = b,
			})
				:FindFirstChildOfClass("UISizeConstraint").MinSize =
				Vector2.new(16, 0)
		end
		b.Activated:Connect(function()
			toggle(tool)
		end)
	end
end

local function watch(container)
	if container then
		container.ChildAdded:Connect(function()
			dirty = true
		end)
		container.ChildRemoved:Connect(function()
			dirty = true
		end)
	end
end

function Hotbar.start(hud)
	HUD = hud
	task.spawn(function()
		for _ = 1, 20 do
			if pcall(StarterGui.SetCoreGuiEnabled, StarterGui, Enum.CoreGuiType.Backpack, false) then
				break
			end
			task.wait(0.5)
		end
	end)
	bar = UI.panel({
		Name = "Hotbar",
		Size = UDim2.fromOffset(0, 76),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundTransparency = 0.15,
		Parent = HUD.gui(),
	})
	UI.padding(bar, 7, 7)
	UI.list(bar, Enum.FillDirection.Horizontal, 7)
	HUD.dock(bar, HUD.DOCK.Hotbar)

	watch(player:WaitForChild("Backpack"))
	if player.Character then
		watch(player.Character)
	end
	player.CharacterAdded:Connect(function(char)
		watch(char)
		dirty = true
		-- a fresh Backpack comes with every respawn
		task.defer(function()
			watch(player:WaitForChild("Backpack"))
			dirty = true
		end)
	end)

	UserInputService.InputBegan:Connect(function(input, processed)
		if processed or HUD.isPilot() then
			return
		end
		local i = NUMBER_KEYS[input.KeyCode]
		if i and list[i] and list[i].Parent then
			toggle(list[i])
		end
	end)
	RunService.Heartbeat:Connect(function()
		if dirty then
			rebuild()
		end
		bar.Visible = #list > 0 and not HUD.isPilot()
	end)
end

return Hotbar
