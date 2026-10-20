-- Always-on HUD: crew materials, objective banner, alert toasts, launch button,
-- destination marker and the end-of-voyage results card. It also docks the
-- bottom-centre frames (hotbar, flight gauges, tool panel, pilot hint) so they stack
-- upwards and never overlap.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Materials = require(Shared.Materials)
local Voyage = require(Shared.Voyage)
local Weather = require(Shared.Weather)
local Remotes = require(Shared.Remotes)
local UI = require(script.Parent.Parent.UI)

local player = Players.LocalPlayer
local state = ReplicatedStorage:WaitForChild("GameState")
local C = UI.Colors

local HUD = {}

-- bottom-centre stacking order, lowest first
HUD.DOCK = { Hotbar = 1, Launch = 2, Tool = 3, Hint = 4 }

local KIND = {
	info = { C.info, "\u{1F4AC}" },
	good = { C.good, "\u{2705}" },
	warn = { C.warn, "\u{26A0}\u{FE0F}" },
	danger = { C.danger, "\u{2757}" },
}
local COIN_ICON = "\u{1F4B0}"
local ALWAYS_SHOW = { Wood = true, Cloth = true, Scrap = true, Coins = true }
local TOAST_TIME = 5.5
local MAX_TOASTS = 4

local gui, scaler, bannerIcon, bannerCol, bannerTitle, bannerSub, alerts, launchBtn, towBtn, hint, hintItems, results
local markerPart, markerName, markerDist
local chips = {}
local docked = {}
local toastOrder = 0
local hintSpec = nil

function HUD.plane()
	return workspace:FindFirstChild("CrewPlane")
end

function HUD.phase()
	return state:GetAttribute("Phase")
end

function HUD.isPilot()
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local seat = hum and hum.SeatPart
	return seat ~= nil and seat.Name == "PilotSeat"
end

function HUD.gui()
	return gui
end

-- The objective banner's text column; FlightPanel adds the route progress bar to it.
function HUD.bannerSlot()
	return bannerCol
end

-- Docking -----------------------------------------------------------------------

function HUD.dock(frame, order)
	frame.AnchorPoint = Vector2.new(0.5, 1)
	table.insert(docked, { order = order, frame = frame })
	table.sort(docked, function(a, b)
		return a.order < b.order
	end)
end

local function restack()
	local y = 12
	local s = scaler.Scale
	for _, e in ipairs(docked) do
		local f = e.frame
		if f.Visible and f.Parent then
			f.Position = UDim2.new(0.5, 0, 1, -y)
			local autoY = f.AutomaticSize == Enum.AutomaticSize.Y or f.AutomaticSize == Enum.AutomaticSize.XY
			y += (autoY and f.AbsoluteSize.Y / s or f.Size.Y.Offset) + 8
		end
	end
end

-- Toasts ------------------------------------------------------------------------

function HUD.toast(text, kind)
	if not alerts then
		return
	end
	toastOrder -= 1
	local k = KIND[kind] or KIND.info
	local f = UI.panel({
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = toastOrder,
		Parent = alerts,
	})
	UI.stroke(f, k[1], 2, 0.1)
	UI.padding(f, 10, 9)
	UI.badge(k[2], 28, { TextSize = 15, StrokeColor = k[1], Parent = f })
	UI.label({
		Position = UDim2.fromOffset(38, 0),
		Size = UDim2.new(1, -38, 0, 28),
		AutomaticSize = Enum.AutomaticSize.Y,
		Text = text,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextSize = 16,
		Parent = f,
	})
	local timer = UI.new("Frame", {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 38, 1, 6),
		Size = UDim2.new(1, -38, 0, 2),
		BackgroundColor3 = k[1],
		BackgroundTransparency = 0.3,
		BorderSizePixel = 0,
		Parent = f,
	})
	TweenService:Create(timer, TweenInfo.new(TOAST_TIME, Enum.EasingStyle.Linear), { Size = UDim2.fromOffset(0, 2) })
		:Play()
	UI.pop(f, 0.85)
	local items = {}
	for _, c in ipairs(alerts:GetChildren()) do
		if c:IsA("Frame") then
			table.insert(items, c)
		end
	end
	table.sort(items, function(a, b)
		return a.LayoutOrder > b.LayoutOrder
	end)
	for i = 1, #items - MAX_TOASTS do
		items[i]:Destroy()
	end
	task.delay(TOAST_TIME, function()
		if f.Parent then
			local s = f:FindFirstChildOfClass("UIScale")
			TweenService:Create(s, TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.In), { Scale = 0 })
				:Play()
			task.wait(0.25)
			f:Destroy()
		end
	end)
end

-- Inventory ---------------------------------------------------------------------

local function iconFor(name)
	if name == "Coins" then
		return COIN_ICON
	end
	local m = Materials.get(name)
	return m and m.icon or "?"
end

-- "+12" that drops out of a chip and fades
local function floatDelta(chip, delta)
	local l = UI.label({
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 1),
		Size = UDim2.fromOffset(60, 18),
		Text = (delta > 0 and "+" or "") .. UI.comma(delta),
		TextSize = 16,
		TextColor3 = delta > 0 and C.good or C.danger,
		TextStrokeTransparency = 0.2,
		TextStrokeColor3 = C.inset,
		ZIndex = 5,
		Parent = chip.Icon,
	})
	TweenService:Create(
		l,
		TweenInfo.new(1.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Position = UDim2.new(0.5, 0, 1, 18), TextTransparency = 1, TextStrokeTransparency = 1 }
	):Play()
	task.delay(1.15, function()
		l:Destroy()
	end)
end

local function refreshChip(name)
	local chip = chips[name]
	local value = state:GetAttribute(name) or 0
	chip.Visible = ALWAYS_SHOW[name] or value > 0
	local old = tonumber(chip:GetAttribute("Value")) or value
	chip:SetAttribute("Value", value)
	chip.Count.Text = UI.comma(value)
	if value ~= old then
		local up = value > old
		chip.Count.TextColor3 = up and C.good or C.danger
		TweenService:Create(chip.Count, TweenInfo.new(0.8), { TextColor3 = C.text }):Play()
		UI.pop(chip.Icon, 1.25)
		floatDelta(chip, value - old)
	end
end

local function buildInventory()
	local bar = UI.panel({
		Name = "Inventory",
		Position = UDim2.fromOffset(14, 10),
		Size = UDim2.fromOffset(0, 46),
		AutomaticSize = Enum.AutomaticSize.X,
		Parent = gui,
	})
	UI.padding(bar, 8, 0)
	UI.list(bar, Enum.FillDirection.Horizontal, 14)
	for i, name in ipairs(Config.Currencies) do
		local chip = UI.new("Frame", {
			Name = name,
			Size = UDim2.fromOffset(0, 32),
			AutomaticSize = Enum.AutomaticSize.X,
			BackgroundTransparency = 1,
			LayoutOrder = i,
			Parent = bar,
		})
		UI.list(chip, Enum.FillDirection.Horizontal, 6)
		UI.badge(iconFor(name), 30, { Name = "Icon", TextSize = 17, LayoutOrder = 1, Parent = chip })
		UI.label({
			Name = "Count",
			Size = UDim2.fromOffset(0, 30),
			AutomaticSize = Enum.AutomaticSize.X,
			Text = "0",
			TextSize = 21,
			LayoutOrder = 2,
			Parent = chip,
		})
		chips[name] = chip
		refreshChip(name)
		state:GetAttributeChangedSignal(name):Connect(function()
			refreshChip(name)
		end)
	end
end

-- Banner / launch / hint ---------------------------------------------------------

local function buildTop()
	local top = UI.new("Frame", {
		Name = "Top",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 10),
		Size = UDim2.fromOffset(0, 0),
		AutomaticSize = Enum.AutomaticSize.XY,
		BackgroundTransparency = 1,
		Parent = gui,
	})
	UI.list(top, Enum.FillDirection.Vertical, 8, Enum.HorizontalAlignment.Center)
	local b = UI.panel({
		Name = "Banner",
		Size = UDim2.fromOffset(0, 50),
		AutomaticSize = Enum.AutomaticSize.XY,
		LayoutOrder = 1,
		Parent = top,
	})
	UI.padding(b, 12, 7)
	UI.list(b, Enum.FillDirection.Horizontal, 10)
	bannerIcon = UI.badge("", 36, { TextSize = 20, LayoutOrder = 1, Parent = b })
	local col = UI.new("Frame", {
		Size = UDim2.fromOffset(0, 0),
		AutomaticSize = Enum.AutomaticSize.XY,
		BackgroundTransparency = 1,
		LayoutOrder = 2,
		Parent = b,
	})
	UI.list(col, Enum.FillDirection.Vertical, 2)
	bannerCol = col
	bannerTitle = UI.label({
		Size = UDim2.fromOffset(0, 22),
		AutomaticSize = Enum.AutomaticSize.X,
		Text = "",
		TextSize = 20,
		TextXAlignment = Enum.TextXAlignment.Left,
		LayoutOrder = 1,
		Parent = col,
	})
	bannerSub = UI.label({
		Size = UDim2.fromOffset(0, 16),
		AutomaticSize = Enum.AutomaticSize.X,
		Text = "",
		TextSize = 14,
		Font = UI.Body,
		TextColor3 = C.dim,
		TextXAlignment = Enum.TextXAlignment.Left,
		LayoutOrder = 2,
		Parent = col,
	})
	-- while exploring an island after landing
	towBtn = UI.button({
		Name = "TowHome",
		Size = UDim2.fromOffset(180, 40),
		Variant = "good",
		Text = "\u{26F5} Tow home",
		TextSize = 19,
		Visible = false,
		LayoutOrder = 2,
		Parent = top,
	})
	towBtn.Activated:Connect(function()
		Remotes.get("Continue"):FireServer()
	end)
end

local function buildLaunch()
	launchBtn = UI.button({
		Name = "Launch",
		Size = UDim2.fromOffset(280, 62),
		Variant = "primary",
		Key = "L",
		Text = "\u{1F680}  LAUNCH!",
		TextSize = 30,
		Visible = false,
		Parent = gui,
	})
	-- a slow brass glow so it reads as the thing to press
	local rim = UI.stroke(launchBtn, Color3.fromRGB(255, 238, 186), 2, 0.2)
	TweenService:Create(
		rim,
		TweenInfo.new(0.8, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
		{ Thickness = 5, Transparency = 0 }
	):Play()
	launchBtn.Activated:Connect(function()
		Remotes.get("Launch"):FireServer()
	end)
	HUD.dock(launchBtn, HUD.DOCK.Launch)

	hint = UI.panel({
		Name = "PilotHint",
		Size = UDim2.fromOffset(0, 38),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundTransparency = 0.2,
		Visible = false,
		Parent = gui,
	})
	UI.padding(hint, 12, 0)
	HUD.dock(hint, HUD.DOCK.Hint)
end

-- spec is a plain string, or a key legend: { { {"W", "S"}, "climb / dive" }, ... }
function HUD.setHint(spec)
	if spec == hintSpec then
		return
	end
	hintSpec = spec
	hint.Visible = spec ~= nil and spec ~= ""
	if hintItems then
		hintItems:Destroy()
		hintItems = nil
	end
	if not hint.Visible then
		return
	end
	hintItems = UI.new("Frame", {
		Size = UDim2.fromScale(0, 1),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundTransparency = 1,
		Parent = hint,
	})
	UI.list(hintItems, Enum.FillDirection.Horizontal, 5)
	if type(spec) == "string" then
		UI.label({
			Size = UDim2.fromOffset(0, 22),
			AutomaticSize = Enum.AutomaticSize.X,
			Text = spec,
			TextSize = 17,
			TextColor3 = C.accent,
			Parent = hintItems,
		})
		return
	end
	local order = 0
	local function add(inst)
		order += 1
		inst.LayoutOrder = order
		inst.Parent = hintItems
	end
	for i, entry in ipairs(spec) do
		if i > 1 then
			add(UI.label({ Size = UDim2.fromOffset(18, 22), Text = "\u{2022}", TextSize = 14, TextColor3 = C.stroke }))
		end
		for _, key in ipairs(entry[1]) do
			add(UI.keycap(key))
		end
		add(UI.label({
			Size = UDim2.fromOffset(0, 22),
			AutomaticSize = Enum.AutomaticSize.X,
			Text = entry[2],
			TextSize = 15,
			Font = UI.Body,
			TextColor3 = C.text,
		}))
	end
end

local function weatherLabel(m)
	local wname = m and m:GetAttribute("Weather") or ""
	local intensity = m and m:GetAttribute("WeatherIntensity") or 0
	local def = Weather.get(wname)
	if not def or intensity < 0.08 then
		return "\u{2600}\u{FE0F}", "Clear skies"
	end
	local word = intensity > 1.3 and "Severe " or (intensity > 0.6 and "Heavy " or "Light ")
	return def.icon, word .. def.display
end

local function updateBanner()
	local phase = HUD.phase()
	local m = HUD.plane()
	local route = Voyage.Routes[state:GetAttribute("Route") or 1]
	local dest = route and Voyage.Islands[route.to]
	local destName = dest and dest.name or "???"
	local icon, title, sub
	if phase == "Build" then
		if HUD.isPilot() then
			icon, title, sub =
				"\u{2708}\u{FE0F}", "You're the pilot!", "Hit LAUNCH when your crew is ready to fly to " .. destName
		else
			icon, title = "\u{1F6E0}\u{FE0F}", "Build your airship"
			sub = "\u{1F4D8} Plan builds  \u{2022}  \u{1F528} Hammer upgrades  \u{2022}  \u{1F58C}\u{FE0F} Brush paints  \u{2022}  take the helm to fly to "
				.. destName
		end
	elseif phase == "Launching" then
		icon, title, sub = "\u{1F680}", "Launch!", "Hold on to something"
	elseif phase == "Flying" then
		icon, title = weatherLabel(m)
		sub = string.format("%s studs to %s", UI.comma(m and m:GetAttribute("Distance") or 0), destName)
	elseif phase == "Landing" then
		icon, title, sub = "\u{1FA82}", "Parachuting down", "to " .. destName
	elseif phase == "Landed" then
		icon, title = "\u{1F3DD}\u{FE0F}", "Exploring " .. destName
		local bits = {}
		if dest and dest.finds then
			local found = 0
			for _, key in ipairs(dest.finds) do
				if state:GetAttribute(key) then
					found += 1
				end
			end
			table.insert(bits, string.format("\u{1F50E} Finds %d/%d", found, #dest.finds))
		end
		if dest and dest.exploreHint and not state:GetAttribute(dest.exploreUnlock) then
			table.insert(bits, dest.exploreHint)
		end
		sub = table.concat(bits, "  \u{2022}  ")
	elseif phase == "Crashed" then
		icon, title, sub = "\u{1F4A5}", "Crashed!", ""
	else
		icon, title, sub = "\u{2753}", tostring(phase), ""
	end
	bannerIcon.Text = icon
	bannerTitle.Text = title
	bannerSub.Text = sub or ""
	bannerSub.Visible = bannerSub.Text ~= ""
end

-- Destination marker --------------------------------------------------------------

local function buildMarker()
	markerPart = UI.new("Part", {
		Name = "DestinationMarker",
		Anchored = true,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		Transparency = 1,
		Size = Vector3.new(1, 1, 1),
		Parent = workspace,
	})
	local bb = UI.new("BillboardGui", {
		Size = UDim2.fromOffset(320, 76),
		AlwaysOnTop = true,
		MaxDistance = 100000,
		LightInfluence = 0,
		Enabled = false,
		Parent = markerPart,
	})
	local pill = UI.panel({
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0),
		Size = UDim2.fromOffset(0, 40),
		AutomaticSize = Enum.AutomaticSize.X,
		Parent = bb,
	})
	UI.padding(pill, 12, 0)
	UI.list(pill, Enum.FillDirection.Horizontal, 8)
	UI.label({
		Size = UDim2.fromOffset(24, 24),
		Text = "\u{1F3DD}\u{FE0F}",
		TextSize = 20,
		LayoutOrder = 1,
		Parent = pill,
	})
	markerName = UI.label({
		Size = UDim2.fromOffset(0, 24),
		AutomaticSize = Enum.AutomaticSize.X,
		Text = "",
		TextSize = 19,
		LayoutOrder = 2,
		Parent = pill,
	})
	markerDist = UI.label({
		Size = UDim2.fromOffset(0, 24),
		AutomaticSize = Enum.AutomaticSize.X,
		Text = "",
		TextSize = 15,
		Font = UI.Body,
		TextColor3 = C.dim,
		LayoutOrder = 3,
		Parent = pill,
	})
	UI.label({
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 40),
		Size = UDim2.fromOffset(30, 26),
		Text = "\u{25BC}",
		TextSize = 22,
		TextColor3 = C.accent,
		TextStrokeTransparency = 0.4,
		Parent = bb,
	})
end

local function updateMarker()
	local phase = HUD.phase()
	local show = phase == "Launching" or phase == "Flying"
	local route = Voyage.Routes[state:GetAttribute("Route") or 1]
	local dest = route and Voyage.Islands[route.to]
	local bb = markerPart:FindFirstChildOfClass("BillboardGui")
	if not show or not dest or not dest.runway then
		bb.Enabled = false
		return
	end
	bb.Enabled = true
	markerPart.Position = dest.runway.start + Vector3.new(0, 30, 0)
	local d = (workspace.CurrentCamera.CFrame.Position - markerPart.Position).Magnitude
	markerName.Text = dest.name
	markerDist.Text = UI.comma(d) .. " studs"
end

-- Results card -----------------------------------------------------------------------

local function fmtTime(sec)
	return string.format("%d:%02d", math.floor(sec / 60), math.floor(sec % 60))
end

function HUD.showResults(data)
	if results then
		results:Destroy()
	end
	local ok = data.success
	local tone = ok and C.good or C.danger
	results = UI.panel({
		Name = "Results",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.46),
		Size = UDim2.fromOffset(500, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = gui,
	})
	UI.stroke(results, tone, 3, 0)
	UI.padding(results, 20, 18)
	UI.list(results, Enum.FillDirection.Vertical, 10, Enum.HorizontalAlignment.Center)
	local order = 0
	local function nextOrder()
		order += 1
		return order
	end
	local function line(text, size, color, font)
		return UI.label({
			Size = UDim2.fromScale(1, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			Text = text,
			TextWrapped = true,
			TextSize = size or 18,
			TextColor3 = color or C.text,
			Font = font or UI.Font,
			LayoutOrder = nextOrder(),
			Parent = results,
		})
	end
	line((ok and "\u{1F389} " or "\u{1F4A5} ") .. data.title, 32, tone)
	if not ok then
		line(
			string.format(
				"You made it %d%% of the way to %s.",
				math.floor((data.progress or 0) * 100),
				data.destination or "the next island"
			),
			17,
			C.dim,
			UI.Body
		)
	end

	-- stat tiles
	local st = data.stats or {}
	local tiles = {
		{ "\u{23F1}\u{FE0F}", fmtTime(data.time or 0), "time" },
		{ "\u{1F4A7}", st.puddles or 0, "bailed" },
		{ "\u{1F527}", st.repairs or 0, "repairs" },
		{ "\u{1F300}", st.restarts or 0, "restarts" },
		{ "\u{2728}", st.powerUps or 0, "power-ups" },
		{ "\u{1F4A5}", st.hits or 0, "rock hits" },
		{ "\u{1F494}", st.partsLost or 0, "parts lost" },
		ok and { "\u{1F6E1}\u{FE0F}", math.floor((data.integrity or 0) * 100) .. "%", "integrity" }
			or { "\u{1F4CD}", math.floor((data.progress or 0) * 100) .. "%", "of the way" },
	}
	local grid = UI.new(
		"Frame",
		{ Size = UDim2.new(1, 0, 0, 132), BackgroundTransparency = 1, LayoutOrder = nextOrder(), Parent = results }
	)
	UI.new("UIGridLayout", {
		CellSize = UDim2.new(0.25, -6, 0, 62),
		CellPadding = UDim2.fromOffset(8, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = grid,
	})
	for i, t in ipairs(tiles) do
		local tile = UI.panel({ LayoutOrder = i, Parent = grid }, "card")
		UI.label({
			Position = UDim2.fromOffset(0, 6),
			Size = UDim2.new(1, 0, 0, 26),
			Text = t[1] .. " " .. tostring(t[2]),
			TextSize = 20,
			Parent = tile,
		})
		UI.caption({
			Position = UDim2.fromOffset(0, 36),
			Size = UDim2.new(1, 0, 0, 16),
			Text = string.upper(t[3]),
			Parent = tile,
		})
	end

	if ok then
		local rewards = {}
		for _, name in ipairs(Config.Currencies) do
			local v = data.rewards and data.rewards[name]
			if v and v > 0 then
				table.insert(rewards, { name, v })
			end
		end
		if #rewards > 0 then
			UI.caption({
				Size = UDim2.new(1, 0, 0, 14),
				Text = "REWARDS",
				TextColor3 = C.accent,
				LayoutOrder = nextOrder(),
				Parent = results,
			})
			local row = UI.new("Frame", {
				Size = UDim2.new(1, 0, 0, 40),
				BackgroundTransparency = 1,
				LayoutOrder = nextOrder(),
				Parent = results,
			})
			UI.list(row, Enum.FillDirection.Horizontal, 10, Enum.HorizontalAlignment.Center)
			for i, r in ipairs(rewards) do
				local chip = UI.panel({
					Size = UDim2.fromOffset(0, 40),
					AutomaticSize = Enum.AutomaticSize.X,
					LayoutOrder = i,
					Parent = row,
				}, "card")
				UI.padding(chip, 8, 0)
				UI.list(chip, Enum.FillDirection.Horizontal, 6)
				UI.badge(iconFor(r[1]), 28, { TextSize = 16, LayoutOrder = 1, Parent = chip })
				UI.label({
					Size = UDim2.fromOffset(0, 28),
					AutomaticSize = Enum.AutomaticSize.X,
					Text = "+" .. UI.comma(r[2]),
					TextSize = 20,
					TextColor3 = C.accent,
					LayoutOrder = 2,
					Parent = chip,
				})
			end
		end
		if data.unlocked and #data.unlocked > 0 then
			line("\u{1F513} New materials: " .. table.concat(data.unlocked, ", "), 19, C.good)
		end
		if data.nextIsland then
			local wdef = data.nextWeather and Weather.get(data.nextWeather)
			line(
				string.format(
					"Next up: %s through the %s %s",
					data.nextIsland,
					wdef and wdef.display or "unknown",
					wdef and wdef.icon or ""
				),
				16,
				C.dim,
				UI.Body
			)
		end
	else
		line(
			"Tip: puddles weigh the ship down. Bail them (E), crank the bilge pump (F), and roof over decks to keep them dry. Pilot: steer into the wind!",
			15,
			C.dim,
			UI.Body
		)
	end

	local row = UI.new(
		"Frame",
		{ Size = UDim2.new(1, 0, 0, 48), BackgroundTransparency = 1, LayoutOrder = nextOrder(), Parent = results }
	)
	UI.list(row, Enum.FillDirection.Horizontal, 12, Enum.HorizontalAlignment.Center)
	if ok then
		local explore = UI.button({
			Size = UDim2.fromOffset(200, 48),
			Text = "\u{1F3DD}\u{FE0F} Explore",
			Variant = "info",
			TextSize = 22,
			LayoutOrder = 1,
			Parent = row,
		})
		explore.Activated:Connect(function()
			if results then
				results:Destroy()
				results = nil
			end
		end)
	end
	local btn = UI.button({
		Size = UDim2.fromOffset(200, 48),
		Text = ok and "Tow home \u{27A1}" or "Back to hangar",
		Variant = ok and "good" or "danger",
		TextSize = 22,
		LayoutOrder = 2,
		Parent = row,
	})
	btn.Activated:Connect(function()
		Remotes.get("Continue"):FireServer()
	end)
	UI.pop(results, 0.8)
end

function HUD.start()
	gui = UI.new("ScreenGui", {
		Name = "HUD",
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		IgnoreGuiInset = false,
		Parent = player:WaitForChild("PlayerGui"),
	})
	scaler = UI.autoScale(gui)
	buildInventory()
	buildTop()
	buildLaunch()
	buildMarker()
	alerts = UI.new("Frame", {
		Name = "Alerts",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -14, 0, 10),
		Size = UDim2.fromOffset(320, 400),
		BackgroundTransparency = 1,
		Parent = gui,
	})
	UI.list(alerts, Enum.FillDirection.Vertical, 6)

	Remotes.get("Notify").OnClientEvent:Connect(HUD.toast)
	Remotes.get("VoyageResult").OnClientEvent:Connect(HUD.showResults)
	state:GetAttributeChangedSignal("Phase"):Connect(function()
		if HUD.phase() == "Build" and results then
			results:Destroy()
			results = nil
		end
	end)

	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc < 0.2 then
			return
		end
		acc = 0
		updateBanner()
		updateMarker()
		launchBtn.Visible = HUD.phase() == "Build" and HUD.isPilot()
		towBtn.Visible = HUD.phase() == "Landed" and results == nil
	end)
	RunService.RenderStepped:Connect(restack)
end

return HUD
