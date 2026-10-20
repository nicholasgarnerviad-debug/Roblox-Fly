-- Themed ProximityPrompts: every prompt in the world gets our keycap card instead of
-- Roblox's default one. Hold prompts fill a bar under the key; on touch screens (or with
-- a mouse) the card itself is the button.
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local UI = require(script.Parent.Parent.UI)

local player = Players.LocalPlayer
local C = UI.Colors

local Prompts = {}

local PAD_KEYS = {
	ButtonA = "A",
	ButtonB = "B",
	ButtonX = "X",
	ButtonY = "Y",
	ButtonL1 = "LB",
	ButtonR1 = "RB",
	ButtonL2 = "LT",
	ButtonR2 = "RT",
	DPadUp = "\u{2191}",
	DPadDown = "\u{2193}",
	DPadLeft = "\u{2190}",
	DPadRight = "\u{2192}",
}

local gui

local function keyText(prompt, inputType)
	if inputType == Enum.ProximityPromptInputType.Gamepad then
		return PAD_KEYS[prompt.GamepadKeyCode.Name] or prompt.GamepadKeyCode.Name
	elseif inputType == Enum.ProximityPromptInputType.Touch then
		return "\u{1F446}"
	end
	local s = UserInputService:GetStringForKeyCode(prompt.KeyboardKeyCode)
	return string.upper(s ~= "" and s or prompt.KeyboardKeyCode.Name)
end

local function show(prompt, inputType)
	local conns = {}
	local bb = UI.new("BillboardGui", {
		Name = "Prompt",
		AlwaysOnTop = true,
		Active = true,
		Size = UDim2.fromOffset(300, 70),
		LightInfluence = 0,
		Adornee = prompt.Parent,
		Parent = gui,
	})
	local card = UI.panel({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(0, 52),
		AutomaticSize = Enum.AutomaticSize.X,
		Parent = bb,
	})
	UI.padding(card, 9, 0)
	UI.list(card, Enum.FillDirection.Horizontal, 10)
	local cap = UI.keycap(
		keyText(prompt, inputType),
		{ Size = UDim2.fromOffset(0, 32), TextSize = 17, LayoutOrder = 1, Parent = card }
	)
	cap:FindFirstChildOfClass("UISizeConstraint").MinSize = Vector2.new(32, 0)
	-- hold progress, just under the keycap (sized by scale only, so the keycap's
	-- AutomaticSize doesn't chase it)
	local holdBar, setHold = UI.bar(
		{ Position = UDim2.new(0, 0, 1, 3), Size = UDim2.new(1, 0, 0, 4), Visible = prompt.HoldDuration > 0 },
		C.accent
	)
	holdBar.Parent = cap
	setHold(0)
	local col = UI.new("Frame", {
		Size = UDim2.fromOffset(0, 0),
		AutomaticSize = Enum.AutomaticSize.XY,
		BackgroundTransparency = 1,
		LayoutOrder = 2,
		Parent = card,
	})
	UI.list(col, Enum.FillDirection.Vertical, 0)
	local object = UI.label({
		Size = UDim2.fromOffset(0, 15),
		AutomaticSize = Enum.AutomaticSize.X,
		TextSize = 13,
		Font = UI.Body,
		TextColor3 = C.dim,
		TextXAlignment = Enum.TextXAlignment.Left,
		LayoutOrder = 1,
		Parent = col,
	})
	local action = UI.label({
		Size = UDim2.fromOffset(0, 22),
		AutomaticSize = Enum.AutomaticSize.X,
		TextSize = 19,
		TextXAlignment = Enum.TextXAlignment.Left,
		LayoutOrder = 2,
		Parent = col,
	})
	local function refresh()
		object.Text = prompt.ObjectText
		object.Visible = prompt.ObjectText ~= ""
		action.Text = prompt.ActionText
		bb.Enabled = prompt.Enabled
	end
	refresh()
	table.insert(conns, prompt.Changed:Connect(refresh))

	local fill
	table.insert(
		conns,
		prompt.PromptButtonHoldBegan:Connect(function()
			local bar = holdBar:FindFirstChild("Fill")
			bar.Visible = true
			bar.Size = UDim2.fromScale(0, 1)
			fill = TweenService:Create(
				bar,
				TweenInfo.new(prompt.HoldDuration, Enum.EasingStyle.Linear),
				{ Size = UDim2.fromScale(1, 1) }
			)
			fill:Play()
		end)
	)
	table.insert(
		conns,
		prompt.PromptButtonHoldEnded:Connect(function()
			if fill then
				fill:Cancel()
			end
			setHold(0)
		end)
	)
	table.insert(
		conns,
		prompt.Triggered:Connect(function()
			UI.pop(card, 1.15)
		end)
	)

	-- tap or click the card to use it
	if inputType == Enum.ProximityPromptInputType.Touch or prompt.ClickablePrompt then
		-- on the billboard, not the card: inside the card's list layout it would stretch it
		local hit = UI.new(
			"TextButton",
			{ Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = "", ZIndex = 5, Parent = bb }
		)
		hit.InputBegan:Connect(function(input)
			if
				input.UserInputType == Enum.UserInputType.Touch
				or input.UserInputType == Enum.UserInputType.MouseButton1
			then
				prompt:InputHoldBegin()
			end
		end)
		hit.InputEnded:Connect(function(input)
			if
				input.UserInputType == Enum.UserInputType.Touch
				or input.UserInputType == Enum.UserInputType.MouseButton1
			then
				prompt:InputHoldEnd()
			end
		end)
	end

	UI.pop(card, 0.7)
	return function()
		for _, c in ipairs(conns) do
			c:Disconnect()
		end
		bb:Destroy()
	end
end

local function claim(d)
	if d:IsA("ProximityPrompt") then
		d.Style = Enum.ProximityPromptStyle.Custom
	end
end

function Prompts.start()
	gui = UI.new("ScreenGui", { Name = "Prompts", ResetOnSpawn = false, Parent = player:WaitForChild("PlayerGui") })
	for _, d in ipairs(workspace:GetDescendants()) do
		claim(d)
	end
	workspace.DescendantAdded:Connect(claim)
	local open = {}
	ProximityPromptService.PromptShown:Connect(function(prompt, inputType)
		if prompt.Style ~= Enum.ProximityPromptStyle.Custom then
			return
		end
		if open[prompt] then
			open[prompt]()
		end
		open[prompt] = show(prompt, inputType)
	end)
	ProximityPromptService.PromptHidden:Connect(function(prompt)
		if open[prompt] then
			open[prompt]()
			open[prompt] = nil
		end
	end)
end

return Prompts
