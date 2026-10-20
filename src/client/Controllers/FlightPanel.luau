-- Airship stats card (in the hangar) and flight instruments (in the air).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local PlaneStats = require(Shared.PlaneStats)
local Voyage = require(Shared.Voyage)
local UI = require(script.Parent.Parent.UI)

local state = ReplicatedStorage:WaitForChild("GameState")
local C = UI.Colors

local FlightPanel = {}

local FOOTNOTE =
	"Balloons lift you at any speed: only weather can hurt them. Wings lift more the faster you go. Engines, sails and wings set your speed; weight only has to be carried. In rain, open decks fill with puddles: roofs keep them dry!"

local statsPanel, statRows, marginSet, marginValue, verdictText
local panel, route, progressFill, planeMark, stormZone
local gauges = {}
local extrasLabel, windArrow, windText

local function marginColor(m)
	if m < 1 then
		return C.danger
	elseif m < 1.12 then
		return C.warn
	end
	return C.good
end

-- Hangar stats card ----------------------------------------------------------------

local function buildStats(gui)
	statsPanel = UI.panel({
		Name = "PlaneStats",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -14, 0.56, 0),
		Size = UDim2.fromOffset(280, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = gui,
	})
	UI.padding(statsPanel, 14, 12)
	UI.list(statsPanel, Enum.FillDirection.Vertical, 8)
	UI.label({
		Size = UDim2.new(1, 0, 0, 26),
		Text = "\u{1F388} YOUR AIRSHIP",
		TextSize = 23,
		TextColor3 = C.accent,
		TextXAlignment = Enum.TextXAlignment.Left,
		LayoutOrder = 0,
		Parent = statsPanel,
	})

	-- lift margin: the one number that decides whether you fly
	local card = UI.panel(
		{ Size = UDim2.fromScale(1, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 1, Parent = statsPanel },
		"card"
	)
	UI.padding(card, 10, 8)
	UI.list(card, Enum.FillDirection.Vertical, 4)
	local head =
		UI.new("Frame", { Size = UDim2.new(1, 0, 0, 24), BackgroundTransparency = 1, LayoutOrder = 1, Parent = card })
	UI.caption({
		Size = UDim2.fromScale(0.6, 1),
		Text = "\u{2696}\u{FE0F} LIFT MARGIN",
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = head,
	})
	marginValue = UI.label({
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.fromScale(0.4, 1),
		Text = "-",
		TextSize = 24,
		TextXAlignment = Enum.TextXAlignment.Right,
		Parent = head,
	})
	local bar
	bar, marginSet = UI.bar({ Size = UDim2.new(1, 0, 0, 12), LayoutOrder = 2, Parent = card })
	-- x1.0 is where lift equals weight; the bar spans x0.6 to x1.6
	UI.new("Frame", {
		Position = UDim2.new(0.4, -1, 0, -3),
		Size = UDim2.new(0, 2, 1, 6),
		BackgroundColor3 = C.text,
		BorderSizePixel = 0,
		ZIndex = 3,
		Parent = bar,
	})
	local scale =
		UI.new("Frame", { Size = UDim2.new(1, 0, 0, 14), BackgroundTransparency = 1, LayoutOrder = 3, Parent = card })
	UI.caption({
		Size = UDim2.fromScale(0.3, 1),
		Text = "SINKS",
		TextSize = 10,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = scale,
	})
	UI.caption({
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.4, 0),
		Size = UDim2.fromOffset(40, 14),
		Text = "x1.0",
		TextSize = 10,
		Parent = scale,
	})
	UI.caption({
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.fromScale(0.3, 1),
		Text = "SOARS",
		TextSize = 10,
		TextXAlignment = Enum.TextXAlignment.Right,
		Parent = scale,
	})
	verdictText = UI.label({
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Text = "",
		TextWrapped = true,
		TextSize = 16,
		TextXAlignment = Enum.TextXAlignment.Left,
		LayoutOrder = 4,
		Parent = card,
	})

	-- the rest as small tiles, two per row
	local grid = UI.new(
		"Frame",
		{ Size = UDim2.new(1, 0, 0, 3 * 52 + 2 * 6), BackgroundTransparency = 1, LayoutOrder = 2, Parent = statsPanel }
	)
	UI.new("UIGridLayout", {
		CellSize = UDim2.new(0.5, -3, 0, 52),
		CellPadding = UDim2.fromOffset(6, 6),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = grid,
	})
	statRows = {}
	local order = 0
	local function tile(key, icon, label)
		order += 1
		local t = UI.panel({ LayoutOrder = order, Parent = grid }, "card")
		UI.caption({
			Position = UDim2.fromOffset(8, 5),
			Size = UDim2.new(1, -16, 0, 14),
			Text = icon .. " " .. label,
			TextSize = 11,
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = t,
		})
		statRows[key] = UI.label({
			Position = UDim2.fromOffset(8, 21),
			Size = UDim2.new(1, -16, 0, 24),
			Text = "-",
			TextSize = 21,
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = t,
		})
	end
	tile("Weight", "\u{1F9F1}", "WEIGHT")
	tile("Lift", "\u{2B06}\u{FE0F}", "LIFT")
	tile("TopSpeed", "\u{1F4A8}", "TOP SPEED")
	tile("TurnRate", "\u{1F504}", "HANDLING")
	tile("FuelMax", "\u{26FD}", "FUEL")
	tile("Parts", "\u{1F9E9}", "PARTS")

	-- how it all works, folded away until asked for
	local more = UI.button({
		Size = UDim2.new(1, 0, 0, 30),
		Text = "\u{1F4D6} How flying works  \u{25BC}",
		TextSize = 15,
		LayoutOrder = 3,
		Parent = statsPanel,
	})
	local note = UI.label({
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Text = FOOTNOTE,
		TextWrapped = true,
		TextSize = 14,
		TextColor3 = C.dim,
		Font = UI.Body,
		TextXAlignment = Enum.TextXAlignment.Left,
		Visible = false,
		LayoutOrder = 4,
		Parent = statsPanel,
	})
	more.Activated:Connect(function()
		note.Visible = not note.Visible
		more.Text = note.Visible and "\u{1F4D6} How flying works  \u{25B2}" or "\u{1F4D6} How flying works  \u{25BC}"
	end)
end

-- Flight instruments ------------------------------------------------------------------
-- A small see-through card in the bottom-left corner, well clear of the ship (which fills
-- the middle of the pilot's view). Route progress lives in the objective banner up top.

local function gauge(order, icon, title, withBar)
	local f = UI.new("Frame", {
		Size = UDim2.new(1, 0, 0, withBar and 30 or 23),
		BackgroundTransparency = 1,
		LayoutOrder = order,
		Parent = panel,
	})
	local glyph = UI.label({ Size = UDim2.fromOffset(20, 22), Text = icon, TextSize = 15, Parent = f })
	UI.caption({
		Position = UDim2.fromOffset(25, 0),
		Size = UDim2.fromOffset(80, 22),
		Text = title,
		TextSize = 11,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = f,
	})
	local value = UI.label({
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.fromOffset(120, 22),
		Text = "-",
		TextSize = 18,
		TextXAlignment = Enum.TextXAlignment.Right,
		Parent = f,
	})
	local set
	if withBar then
		local _
		_, set = UI.bar({ Position = UDim2.fromOffset(25, 24), Size = UDim2.new(1, -25, 0, 5), Parent = f })
	end
	return { value = value, set = set, frame = f, icon = glyph }
end

local function buildFlight(gui, HUD)
	panel = UI.panel({
		Name = "FlightPanel",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 14, 1, -14),
		Size = UDim2.fromOffset(212, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 0.3,
		Visible = false,
		Parent = gui,
	})
	UI.padding(panel, 12, 9)
	UI.list(panel, Enum.FillDirection.Vertical, 2)
	-- power-up timers, only while one is running
	extrasLabel = UI.label({
		Size = UDim2.new(1, 0, 0, 22),
		Text = "",
		TextSize = 17,
		TextColor3 = C.accent,
		TextXAlignment = Enum.TextXAlignment.Left,
		Visible = false,
		LayoutOrder = 0,
		Parent = panel,
	})
	gauges.speed = gauge(1, "\u{1F4A8}", "SPEED", false)
	gauges.alt = gauge(2, "\u{26F0}\u{FE0F}", "ALTITUDE", false)
	gauges.lift = gauge(3, "\u{1F388}", "LIFT", true)
	gauges.fuel = gauge(4, "\u{26FD}", "FUEL", true)
	gauges.hull = gauge(5, "\u{1F6E1}\u{FE0F}", "HULL", true)
	gauges.water = gauge(6, "\u{1F4A7}", "WATER", true)
	-- wind: the arrow shows which way it pushes the ship (up = forward)
	local wind = gauge(7, "\u{25B2}", "WIND", false)
	windArrow = wind.icon
	windArrow.TextColor3 = C.info
	windText = wind.value
	windText.TextSize = 15

	-- route progress, tucked under the banner text
	route = UI.new("Frame", {
		Size = UDim2.fromOffset(300, 14),
		BackgroundTransparency = 1,
		Visible = false,
		LayoutOrder = 3,
		Parent = HUD.bannerSlot(),
	})
	local track = UI.new("Frame", {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 6, 0.5, 0),
		Size = UDim2.new(1, -30, 0, 7),
		BackgroundColor3 = C.inset,
		BorderSizePixel = 0,
		Parent = route,
	})
	UI.corner(track, 4)
	UI.stroke(track, Color3.new(0, 0, 0), 1, 0.55)
	stormZone = UI.new("Frame", {
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = Color3.fromRGB(96, 112, 150),
		BorderSizePixel = 0,
		Parent = track,
	})
	UI.corner(stormZone, 4)
	progressFill = UI.new("Frame", {
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = C.accent,
		BackgroundTransparency = 0.35,
		BorderSizePixel = 0,
		Parent = track,
	})
	UI.corner(progressFill, 4)
	planeMark = UI.badge("\u{1F388}", 18, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0, 0.5),
		TextSize = 11,
		BackgroundColor3 = C.panel,
		BackgroundTransparency = 0,
		StrokeColor = C.accent,
		ZIndex = 4,
		Parent = track,
	})
	UI.label({
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.fromScale(1, 0.5),
		Size = UDim2.fromOffset(18, 14),
		Text = "\u{1F3DD}\u{FE0F}",
		TextSize = 12,
		Parent = route,
	})
end

local function updateStormZone()
	local r = Voyage.Routes[state:GetAttribute("Route") or 1]
	if not r or not r.curve then
		stormZone.Size = UDim2.fromScale(0, 1)
		return
	end
	local t0, t1
	for i = 0, 100 do
		local t = i / 100
		if Voyage.intensity(r, t) > 0.35 then
			t0 = t0 or t
			t1 = t
		end
	end
	if t0 then
		stormZone.Position = UDim2.fromScale(t0, 0)
		stormZone.Size = UDim2.fromScale(t1 - t0, 1)
	end
end

local function update(HUD)
	local m = HUD.plane()
	local phase = HUD.phase()
	local building = phase == "Build"
	local airborne = phase == "Launching" or phase == "Flying" or phase == "Landing"
	statsPanel.Visible = building and m ~= nil
	panel.Visible = airborne and m ~= nil
	route.Visible = panel.Visible
	if not m then
		return
	end
	local margin = m:GetAttribute("Margin") or 0
	if building then
		statRows.Weight.Text = string.format("%.1f", m:GetAttribute("Weight") or 0)
		statRows.Lift.Text = string.format("%.1f", m:GetAttribute("Lift") or 0)
		statRows.TopSpeed.Text = string.format("%d", m:GetAttribute("TopSpeed") or 0)
		statRows.TurnRate.Text = string.format("%d\u{00B0}/s", m:GetAttribute("TurnRate") or 0)
		statRows.FuelMax.Text = string.format("%d", m:GetAttribute("FuelMax") or 0)
		statRows.Parts.Text = string.format("%d", m:GetAttribute("Parts") or 0)
		marginValue.Text = string.format("x%.2f", margin)
		marginValue.TextColor3 = marginColor(margin)
		marginSet((margin - 0.6) / 1.0, marginColor(margin))
		local verdict, vcolor = PlaneStats.verdict({
			engines = m:GetAttribute("Engines") or 0,
			sails = m:GetAttribute("Sails") or 0,
			margin = margin,
		})
		verdictText.Text = verdict
		verdictText.TextColor3 = vcolor
		return
	end
	if not airborne then
		return
	end
	local progress = m:GetAttribute("Progress") or 0
	progressFill.Size = UDim2.fromScale(progress, 1)
	planeMark.Position = UDim2.fromScale(progress, 0.5)
	gauges.speed.value.Text = string.format("%d", m:GetAttribute("Speed") or 0)
	local climb = m:GetAttribute("Climb") or 0
	local arrow = climb > 2 and " " .. UI.tint("\u{25B2}", "good")
		or (climb < -2 and " " .. UI.tint("\u{25BC}", "danger") or "")
	gauges.alt.value.Text = string.format("%d%s", m:GetAttribute("Altitude") or 0, arrow)
	gauges.alt.value.TextColor3 = (m:GetAttribute("Altitude") or 100) < 40 and C.danger or C.text
	gauges.lift.value.Text = string.format("x%.2f", margin)
	gauges.lift.value.TextColor3 = marginColor(margin)
	gauges.lift.set((margin - 0.6) / 1.0, marginColor(margin))
	local fuel, fuelMax = m:GetAttribute("Fuel") or 0, math.max(m:GetAttribute("FuelMax") or 1, 1)
	gauges.fuel.value.Text = string.format("%d", fuel)
	gauges.fuel.set(fuel / fuelMax, fuel / fuelMax < 0.25 and C.danger or C.warn)
	local integrity = m:GetAttribute("Integrity") or 1
	gauges.hull.value.Text = string.format("%d%%", integrity * 100)
	gauges.hull.set(integrity, integrity < 0.5 and C.danger or C.good)
	local extras = {}
	if (m:GetAttribute("ShieldTime") or 0) > 0 then
		table.insert(extras, string.format("\u{1F6E1}\u{FE0F} %ds", m:GetAttribute("ShieldTime")))
	end
	if (m:GetAttribute("BoostTime") or 0) > 0 then
		table.insert(extras, string.format("\u{26A1} %ds", m:GetAttribute("BoostTime")))
	end
	extrasLabel.Text = table.concat(extras, "   ")
	extrasLabel.Visible = #extras > 0

	-- water aboard as a share of what the ship can carry before it sinks
	local water, cap = m:GetAttribute("Water") or 0, m:GetAttribute("WaterMax") or 0
	local full = cap > 0 and water / cap or (water > 0 and 1 or 0)
	local wcolor = full >= 0.8 and C.danger or (full >= 0.5 and C.warn or C.water)
	gauges.water.value.Text = water < 0.5 and "Dry" or string.format("%d%%", math.floor(full * 100 + 0.5))
	gauges.water.value.TextColor3 = full >= 0.5 and wcolor or C.text
	gauges.water.set(full, wcolor)

	local wind = m:GetAttribute("WindLocal") or Vector2.zero
	local gust = m:GetAttribute("GustWarn") or 0
	if gust ~= 0 then
		-- a gust is about to hit: point the arrow the way it will shove us
		windArrow.Rotation = gust > 0 and 90 or -90
		windArrow.TextColor3 = C.warn
		windText.Text = UI.tint(gust > 0 and "GUST \u{25B6}" or "\u{25C0} GUST", "warn")
	elseif wind.Magnitude < 1 then
		windArrow.Rotation = 0
		windArrow.TextColor3 = C.dim
		windText.Text = "Calm"
	else
		windArrow.Rotation = math.deg(math.atan2(wind.X, wind.Y))
		windArrow.TextColor3 = C.info
		local side = math.abs(wind.X) > math.abs(wind.Y) and (wind.X > 0 and "pushes right" or "pushes left")
			or (wind.Y > 0 and "tailwind" or "headwind")
		windText.Text = string.format(
			'%d <font size="13" color="%s">%s</font>',
			math.floor(wind.Magnitude + 0.5),
			UI.hex("dim"),
			side
		)
	end
end

function FlightPanel.start(HUD)
	local gui = HUD.gui()
	buildStats(gui)
	buildFlight(gui, HUD)
	updateStormZone()
	state:GetAttributeChangedSignal("Route"):Connect(updateStormZone)
	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc >= 0.1 then
			acc = 0
			update(HUD)
		end
	end)
end

return FlightPanel
