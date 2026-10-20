-- Tiny UI kit so every screen shares one look: a captain's logbook.
-- Walnut panels framed in brass, cream text, gold highlights and keycaps for hotkeys.
local TweenService = game:GetService("TweenService")

local UI = {}

UI.Colors = {
	panel = Color3.fromRGB(40, 30, 26), -- walnut
	panel2 = Color3.fromRGB(68, 52, 42), -- raised wood: buttons, cards
	panel3 = Color3.fromRGB(94, 72, 56),
	inset = Color3.fromRGB(22, 16, 14), -- bar tracks and wells
	stroke = Color3.fromRGB(132, 98, 62), -- dull brass
	brass = Color3.fromRGB(222, 166, 82),
	accent = Color3.fromRGB(255, 200, 92), -- gold
	text = Color3.fromRGB(255, 246, 230),
	dim = Color3.fromRGB(204, 184, 160),
	ink = Color3.fromRGB(46, 30, 20), -- dark text on gold or cream
	good = Color3.fromRGB(122, 206, 104),
	warn = Color3.fromRGB(247, 176, 64),
	danger = Color3.fromRGB(236, 88, 72),
	info = Color3.fromRGB(104, 184, 240),
	water = Color3.fromRGB(80, 160, 240),
}
UI.Font = Enum.Font.FredokaOne
UI.Body = Enum.Font.BuilderSansBold
UI.Heavy = Enum.Font.BuilderSansExtraBold

local C = UI.Colors
local QUICK = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local SHINE = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(196, 196, 196)) -- lit from above
local METAL = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.new(1, 1, 1)),
	ColorSequenceKeypoint.new(0.5, Color3.fromRGB(150, 150, 150)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(235, 235, 235)),
})

-- "#rrggbb" for RichText: UI.hex("good") or UI.hex(someColor3)
function UI.hex(c)
	return "#" .. (C[c] or c):ToHex()
end

function UI.tint(text, c)
	return string.format('<font color="%s">%s</font>', UI.hex(c), text)
end

function UI.new(class, props, children)
	local inst = Instance.new(class)
	for k, v in pairs(props or {}) do
		if k ~= "Parent" then
			inst[k] = v
		end
	end
	for _, c in ipairs(children or {}) do
		c.Parent = inst
	end
	if props and props.Parent then
		inst.Parent = props.Parent
	end
	return inst
end

function UI.tween(inst, time, goal, style, dir)
	local t = TweenService:Create(
		inst,
		TweenInfo.new(time, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out),
		goal
	)
	t:Play()
	return t
end

function UI.corner(parent, r)
	return UI.new("UICorner", { CornerRadius = UDim.new(0, r or 12), Parent = parent })
end

-- Makes every corner on an object (and its hover sheen) fully round: circles and pills.
function UI.round(inst)
	for _, c in ipairs(inst:GetDescendants()) do
		if c:IsA("UICorner") then
			c.CornerRadius = UDim.new(0.5, 0)
		end
	end
	local own = inst:FindFirstChildOfClass("UICorner") or UI.new("UICorner", { Parent = inst })
	own.CornerRadius = UDim.new(0.5, 0)
	return inst
end

-- One stroke per object: calling again restyles the existing one.
function UI.stroke(parent, color, thickness, transparency)
	local s = parent:FindFirstChildOfClass("UIStroke")
		or UI.new("UIStroke", { ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = parent })
	s.Color = color or C.stroke
	s.Thickness = thickness or 2
	s.Transparency = transparency or 0.2
	return s
end

-- Top-to-bottom shading (multiplies the object's own colours, not its children).
function UI.shade(parent, seq, rotation)
	return UI.new("UIGradient", { Color = seq or SHINE, Rotation = rotation or 90, Parent = parent })
end

function UI.padding(parent, px, py)
	py = py or px
	return UI.new("UIPadding", {
		PaddingTop = UDim.new(0, py),
		PaddingBottom = UDim.new(0, py),
		PaddingLeft = UDim.new(0, px),
		PaddingRight = UDim.new(0, px),
		Parent = parent,
	})
end

function UI.list(parent, dir, pad, align)
	return UI.new("UIListLayout", {
		FillDirection = dir or Enum.FillDirection.Vertical,
		Padding = UDim.new(0, pad or 6),
		SortOrder = Enum.SortOrder.LayoutOrder,
		HorizontalAlignment = align or Enum.HorizontalAlignment.Left,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Parent = parent,
	})
end

-- A brass-framed walnut panel. kind = "card" for a flatter card that sits inside a panel.
function UI.panel(props, kind)
	local card = kind == "card"
	props.BackgroundColor3 = props.BackgroundColor3 or (card and C.panel2 or C.panel)
	props.BackgroundTransparency = props.BackgroundTransparency or (card and 0.25 or 0.05)
	props.BorderSizePixel = 0
	local f = UI.new("Frame", props)
	UI.corner(f, card and 10 or 14)
	local s = UI.stroke(f, card and C.stroke or C.brass, card and 1.5 or 2.5, card and 0.45 or 0.05)
	UI.shade(s, METAL, 45)
	UI.shade(f)
	return f
end

function UI.label(props)
	props.BackgroundTransparency = props.BackgroundTransparency or 1
	props.Font = props.Font or UI.Font
	props.TextColor3 = props.TextColor3 or C.text
	props.TextSize = props.TextSize or 18
	props.RichText = true
	return UI.new("TextLabel", props)
end

-- Small caps-style heading used at the top of cards ("SPEED", "REWARDS").
function UI.caption(props)
	props.Font = props.Font or UI.Heavy
	props.TextSize = props.TextSize or 12
	props.TextColor3 = props.TextColor3 or C.dim
	return UI.label(props)
end

-- A cream keycap showing a hotkey ("Q", "Shift").
function UI.keycap(key, props)
	props = props or {}
	props.Name = props.Name or "Key"
	props.BackgroundColor3 = Color3.fromRGB(246, 234, 212)
	props.BackgroundTransparency = 0
	props.BorderSizePixel = 0
	props.Size = props.Size or UDim2.fromOffset(0, 22)
	props.AutomaticSize = Enum.AutomaticSize.X
	props.Font = UI.Heavy
	props.Text = key
	props.TextSize = props.TextSize or 13
	props.TextColor3 = C.ink
	local k = UI.new("TextLabel", props)
	UI.corner(k, 5)
	UI.stroke(k, C.ink, 1, 0.3)
	UI.new("UIPadding", { PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 6), Parent = k })
	UI.new("UISizeConstraint", { MinSize = Vector2.new(22, 0), Parent = k })
	UI.shade(k, ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(200, 192, 180)))
	return k
end

-- A round icon badge (resource icons, tool icons, toast icons).
function UI.badge(icon, size, props)
	props = props or {}
	local rim = props.StrokeColor or C.brass
	props.StrokeColor = nil
	props.Size = UDim2.fromOffset(size, size)
	props.BackgroundColor3 = props.BackgroundColor3 or C.inset
	props.BackgroundTransparency = props.BackgroundTransparency or 0.15
	props.BorderSizePixel = 0
	props.Text = icon
	props.TextSize = props.TextSize or math.floor(size * 0.58)
	props.Font = UI.Font
	props.TextColor3 = props.TextColor3 or C.text
	local b = UI.new("TextLabel", props)
	UI.corner(b, size)
	UI.stroke(b, rim, 1.5, 0.35)
	return b
end

-- Hover sheen + press squish for any GuiButton. extraWidth covers a right-hand UIPadding.
function UI.pressable(b, extraWidth)
	b.AutoButtonColor = false
	local scale = b:FindFirstChildOfClass("UIScale") or UI.new("UIScale", { Parent = b })
	local sheen = UI.new("Frame", {
		Name = "Sheen",
		Size = UDim2.new(1, extraWidth or 0, 1, 0),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Parent = b,
	})
	local c = b:FindFirstChildOfClass("UICorner")
	if c then
		UI.new("UICorner", { CornerRadius = c.CornerRadius, Parent = sheen })
	end
	local hovering = false
	local function set(t, s)
		TweenService:Create(sheen, QUICK, { BackgroundTransparency = t }):Play()
		TweenService:Create(scale, QUICK, { Scale = s }):Play()
	end
	b.MouseEnter:Connect(function()
		hovering = true
		set(0.88, 1)
	end)
	b.MouseLeave:Connect(function()
		hovering = false
		set(1, 1)
	end)
	b.MouseButton1Down:Connect(function()
		set(0.8, 0.94)
	end)
	b.MouseButton1Up:Connect(function()
		set(hovering and 0.88 or 1, 1)
	end)
	return b
end

-- Button colour schemes: { background, text, rim }
UI.Variants = {
	secondary = { C.panel2, C.text, C.stroke },
	primary = { C.accent, C.ink, Color3.fromRGB(255, 238, 186) },
	good = { Color3.fromRGB(74, 152, 80), C.text, Color3.fromRGB(172, 232, 160) },
	danger = { Color3.fromRGB(176, 64, 52), C.text, Color3.fromRGB(242, 160, 150) },
	info = { Color3.fromRGB(56, 124, 192), C.text, Color3.fromRGB(172, 216, 250) },
}

-- props.Variant picks a colour scheme; props.Key puts a keycap on the right.
function UI.button(props)
	local v = UI.Variants[props.Variant or "secondary"]
	local key = props.Key
	props.Variant, props.Key = nil, nil
	props.BackgroundColor3 = props.BackgroundColor3 or v[1]
	props.TextColor3 = props.TextColor3 or v[2]
	props.Font = props.Font or UI.Font
	props.TextSize = props.TextSize or 18
	props.BorderSizePixel = 0
	local b = UI.new("TextButton", props)
	UI.corner(b, 10)
	UI.stroke(b, v[3], 1.5, 0.3)
	UI.shade(b)
	local pad = 0
	if key then
		pad = 32
		UI.new("UIPadding", { PaddingRight = UDim.new(0, pad), Parent = b })
		UI.keycap(key, {
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, pad - 6, 0.5, 0),
			ZIndex = b.ZIndex + 1,
			Parent = b,
		})
	end
	UI.pressable(b, pad)
	return b
end

-- Restyle a button to another scheme (toggles flip between secondary and info).
function UI.setVariant(b, name)
	local v = UI.Variants[name]
	b.BackgroundColor3 = v[1]
	b.TextColor3 = v[2]
	UI.stroke(b, v[3], 1.5, 0.3)
end

-- Returns (frame, set(frac, color)). The fill glides to its new size.
function UI.bar(props, fillColor)
	props.BackgroundColor3 = props.BackgroundColor3 or C.inset
	props.BackgroundTransparency = props.BackgroundTransparency or 0.1
	props.BorderSizePixel = 0
	local back = UI.new("Frame", props)
	UI.corner(back, 6)
	UI.stroke(back, Color3.new(0, 0, 0), 1, 0.55)
	local fill = UI.new("Frame", {
		Name = "Fill",
		Size = UDim2.fromScale(0.5, 1),
		BackgroundColor3 = fillColor or C.good,
		BorderSizePixel = 0,
		Parent = back,
	})
	UI.corner(fill, 6)
	UI.shade(fill, ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(170, 170, 170)))
	local last = -1
	return back,
		function(frac, color)
			frac = math.clamp(frac, 0, 1)
			if math.abs(frac - last) > 0.002 then
				last = frac
				TweenService:Create(fill, TweenInfo.new(0.18), { Size = UDim2.fromScale(frac, 1) }):Play()
			end
			fill.Visible = frac > 0.004
			if color then
				fill.BackgroundColor3 = color
			end
		end
end

-- Quick bounce, e.g. when a number changes.
function UI.pop(inst, amount)
	local s = inst:FindFirstChildOfClass("UIScale") or UI.new("UIScale", { Parent = inst })
	s.Scale = amount or 1.2
	TweenService:Create(s, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
end

-- Scales a whole ScreenGui with the window so it fits phones and big monitors alike.
function UI.autoScale(screenGui)
	local s = UI.new("UIScale", { Name = "AutoScale", Parent = screenGui })
	local cam = workspace.CurrentCamera
	local function fit()
		local v = cam.ViewportSize
		s.Scale = math.clamp(math.min(v.X / 1440, v.Y / 800), 0.62, 1.15)
	end
	cam:GetPropertyChangedSignal("ViewportSize"):Connect(fit)
	fit()
	return s
end

function UI.comma(n)
	local s = tostring(math.floor(n + 0.5))
	return (s:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", ""))
end

return UI
