-- Rust-style radial (pie) menu: a ring of round buttons around the screen centre.
-- Radial.open({ title, items = { { id, icon, label, sub, info, disabled, selected } }, onPick, switchText, onSwitch })
local TweenService = game:GetService("TweenService")
local UI = require(script.Parent.UI)

local C = UI.Colors
local Radial = {}

local CENTRE_Y = -40 -- the wheel sits a little above the middle so the tool panel stays clear

local gui, root, dial, centre, centreTitle, centreLabel, centreSub, switchBtn
local buttons = {}
local openState = nil

function Radial.init(screenGui)
	gui = screenGui
	root = UI.new("TextButton", {
		Name = "Radial",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.5,
		Text = "",
		AutoButtonColor = false,
		Visible = false,
		ZIndex = 20,
		Parent = gui,
	})
	root.Activated:Connect(function()
		Radial.close()
	end)
	-- the dial face the buttons sit on
	dial = UI.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, CENTRE_Y),
		Size = UDim2.fromOffset(390, 390),
		BackgroundColor3 = C.panel,
		BackgroundTransparency = 0.45,
		ZIndex = 20,
		Parent = root,
	})
	UI.round(dial)
	UI.stroke(dial, C.brass, 2, 0.55)
	centre = UI.panel({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, CENTRE_Y),
		Size = UDim2.fromOffset(214, 214),
		ZIndex = 21,
		Parent = root,
	})
	UI.round(centre)
	UI.stroke(centre, C.brass, 3, 0)
	centreTitle = UI.caption({
		Position = UDim2.fromOffset(15, 30),
		Size = UDim2.new(1, -30, 0, 18),
		Text = "",
		TextSize = 13,
		ZIndex = 22,
		Parent = centre,
	})
	centreLabel = UI.label({
		Position = UDim2.fromOffset(15, 52),
		Size = UDim2.new(1, -30, 0, 28),
		Text = "",
		TextSize = 22,
		TextColor3 = C.accent,
		ZIndex = 22,
		Parent = centre,
	})
	centreSub = UI.label({
		Position = UDim2.fromOffset(24, 84),
		Size = UDim2.new(1, -48, 0, 70),
		Text = "",
		TextSize = 13,
		Font = UI.Body,
		TextWrapped = true,
		TextYAlignment = Enum.TextYAlignment.Top,
		ZIndex = 22,
		Parent = centre,
	})
	switchBtn = UI.button({
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -18),
		Size = UDim2.fromOffset(150, 30),
		Text = "",
		TextSize = 15,
		Variant = "info",
		ZIndex = 23,
		Visible = false,
		Parent = centre,
	})
	switchBtn.Activated:Connect(function()
		if openState and openState.onSwitch then
			openState.onSwitch()
		end
	end)
end

function Radial.isOpen()
	return openState ~= nil
end

function Radial.close()
	openState = nil
	if root then
		root.Visible = false
	end
end

local function showInfo(item)
	centreLabel.Text = item and ((item.icon or "") .. " " .. item.label) or ""
	centreSub.Text = item and ((item.sub and (item.sub .. "\n") or "") .. (item.info or "")) or ""
	centreSub.TextColor3 = (item and item.disabled) and C.danger or C.text
end

function Radial.open(opts)
	for _, b in ipairs(buttons) do
		b:Destroy()
	end
	buttons = {}
	openState = opts
	centreTitle.Text = string.upper(opts.title or "")
	switchBtn.Visible = opts.switchText ~= nil
	switchBtn.Text = opts.switchText or ""
	showInfo(nil)
	local n = #opts.items
	local radius = n > 8 and 225 or 195
	dial.Size = UDim2.fromOffset(radius * 2 + 112, radius * 2 + 112)
	local home = UDim2.new(0.5, 0, 0.5, CENTRE_Y)
	for i, item in ipairs(opts.items) do
		local a = -math.pi / 2 + (i - 1) / n * math.pi * 2
		local b = UI.button({
			Name = "Item_" .. tostring(item.id),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = home,
			Size = UDim2.fromOffset(96, 96),
			Text = "",
			Variant = item.selected and "primary" or "secondary",
			ZIndex = 21,
			Parent = root,
		})
		UI.round(b)
		if item.disabled then
			b.BackgroundColor3 = C.inset
			b.BackgroundTransparency = 0.25
		end
		local ink = item.selected and C.ink or C.text
		UI.label({
			Position = UDim2.fromOffset(0, 12),
			Size = UDim2.new(1, 0, 0, 36),
			Text = item.icon or "",
			TextSize = 32,
			TextTransparency = item.disabled and 0.45 or 0,
			ZIndex = 22,
			Parent = b,
		})
		UI.label({
			Position = UDim2.fromOffset(6, 50),
			Size = UDim2.new(1, -12, 0, 18),
			Text = item.label,
			TextSize = 13,
			TextWrapped = true,
			ZIndex = 22,
			TextColor3 = item.disabled and C.dim or ink,
			Parent = b,
		})
		if item.sub then
			UI.label({
				Position = UDim2.fromOffset(6, 68),
				Size = UDim2.new(1, -12, 0, 16),
				Text = item.sub,
				TextSize = 11,
				Font = UI.Body,
				ZIndex = 22,
				TextColor3 = item.disabled and C.danger or (item.selected and C.ink or C.dim),
				Parent = b,
			})
		end
		b.MouseEnter:Connect(function()
			showInfo(item)
		end)
		b.Activated:Connect(function()
			showInfo(item)
			if item.disabled then
				return
			end
			local pick = opts.onPick
			Radial.close()
			pick(item.id)
		end)
		-- fan out from the middle
		local goal = UDim2.new(0.5, math.cos(a) * radius, 0.5, math.sin(a) * radius + CENTRE_Y)
		TweenService:Create(
			b,
			TweenInfo.new(0.22 + i * 0.012, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
			{ Position = goal }
		):Play()
		table.insert(buttons, b)
	end
	root.Visible = true
	UI.pop(centre, 0.7)
end

return Radial
