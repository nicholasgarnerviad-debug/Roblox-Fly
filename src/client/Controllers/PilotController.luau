-- Pilot input: W/S climb/dive, A/D turn, Shift boost, R/F throttle, L launch.
-- Reads the VehicleSeat's Throttle/Steer too, so gamepad and mobile sticks work.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Remotes)
local UI = require(script.Parent.Parent.UI)

local player = Players.LocalPlayer
local state = ReplicatedStorage:WaitForChild("GameState")

local Pilot = {}

local HUD
local throttle = 1
local wasPilot = false
local last = { pitch = 0, steer = 0, boost = false, throttle = 1, t = 0 }
local mobile = { boost = false, up = false, down = false }
local mobileFrame
local savedMinZoom = 0.5

local HINT_FLY = {
	{ { "W", "S" }, "climb / dive" },
	{ { "A", "D" }, "turn" },
	{ { "Shift" }, "boost" },
	{ { "R", "F" }, "throttle" },
	{ { "Space" }, "leave seat" },
}
-- the full legend shows for a few seconds after take-off, then folds down to this
local HINT_FOLDED = { { { "H" }, "flight controls" } }
local HINT_SECONDS = 8
local hintUntil, hintOpen = 0, false

local function key(k)
	return UserInputService:IsKeyDown(k)
end

local function buildMobile(gui)
	if not UserInputService.TouchEnabled then
		return
	end
	mobileFrame = UI.new("Frame", {
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -20, 1, -170),
		Size = UDim2.fromOffset(170, 190),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = gui,
	})
	local function hold(text, pos, field, variant)
		local b = UI.button({
			Position = pos,
			Size = UDim2.fromOffset(80, 80),
			Text = text,
			TextSize = 30,
			Variant = variant,
			Parent = mobileFrame,
		})
		for _, c in ipairs(b:GetDescendants()) do
			if c:IsA("UICorner") then
				c.CornerRadius = UDim.new(0.5, 0)
			end
		end
		b.InputBegan:Connect(function(i)
			if i.UserInputType == Enum.UserInputType.Touch then
				mobile[field] = true
			end
		end)
		b.InputEnded:Connect(function(i)
			if i.UserInputType == Enum.UserInputType.Touch then
				mobile[field] = false
			end
		end)
	end
	hold("\u{26A1}", UDim2.fromOffset(90, 100), "boost", "primary")
	hold("+", UDim2.fromOffset(0, 10), "up")
	hold("-", UDim2.fromOffset(0, 100), "down")
end

local function onPilotChanged(isPilot)
	wasPilot = isPilot
	if isPilot then
		hintUntil = os.clock() + HINT_SECONDS
		savedMinZoom = player.CameraMinZoomDistance
		player.CameraMinZoomDistance = 55
		task.delay(0.2, function()
			if wasPilot then
				player.CameraMinZoomDistance = 30
			end
		end)
	else
		player.CameraMinZoomDistance = savedMinZoom
		HUD.setHint(nil)
		Remotes.get("PilotInput"):FireServer(0, 0, false, throttle)
	end
	if mobileFrame then
		mobileFrame.Visible = isPilot
	end
end

local function step(dt)
	local isPilot = HUD.isPilot()
	if isPilot ~= wasPilot then
		onPilotChanged(isPilot)
	end
	if not isPilot then
		return
	end
	local phase = state:GetAttribute("Phase")
	if phase == "Launching" or phase == "Flying" then
		HUD.setHint((hintOpen or os.clock() < hintUntil) and HINT_FLY or HINT_FOLDED)
	else
		HUD.setHint(nil) -- in the hangar the LAUNCH button carries its own L keycap
	end

	local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	local seat = hum and hum.SeatPart
	local pitch, steer = 0, 0
	if seat and seat:IsA("VehicleSeat") then
		pitch, steer = seat.ThrottleFloat, seat.SteerFloat
	end
	if key(Enum.KeyCode.W) or key(Enum.KeyCode.Up) then
		pitch = 1
	elseif key(Enum.KeyCode.S) or key(Enum.KeyCode.Down) then
		pitch = -1
	end
	if key(Enum.KeyCode.A) or key(Enum.KeyCode.Left) then
		steer = -1
	elseif key(Enum.KeyCode.D) or key(Enum.KeyCode.Right) then
		steer = 1
	end
	local boost = key(Enum.KeyCode.LeftShift)
		or key(Enum.KeyCode.RightShift)
		or key(Enum.KeyCode.ButtonR2)
		or mobile.boost
	if key(Enum.KeyCode.R) or mobile.up or key(Enum.KeyCode.ButtonR1) then
		throttle = math.min(1, throttle + dt * 0.7)
	elseif key(Enum.KeyCode.F) or mobile.down or key(Enum.KeyCode.ButtonL1) then
		throttle = math.max(0, throttle - dt * 0.7)
	end
	pitch = math.clamp(pitch, -1, 1)
	steer = math.clamp(steer, -1, 1)

	last.t += dt
	local changed = math.abs(pitch - last.pitch) > 0.05
		or math.abs(steer - last.steer) > 0.05
		or boost ~= last.boost
		or math.abs(throttle - last.throttle) > 0.02
	if changed or last.t > 0.5 then
		last.pitch, last.steer, last.boost, last.throttle, last.t = pitch, steer, boost, throttle, 0
		Remotes.get("PilotInput"):FireServer(pitch, steer, boost, throttle)
	end
end

function Pilot.start(hud)
	HUD = hud
	buildMobile(HUD.gui())
	RunService.RenderStepped:Connect(step)
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		if input.KeyCode == Enum.KeyCode.L and HUD.isPilot() and state:GetAttribute("Phase") == "Build" then
			Remotes.get("Launch"):FireServer()
		elseif input.KeyCode == Enum.KeyCode.H and HUD.isPilot() then
			hintOpen = not hintOpen
			hintUntil = 0
		end
	end)
	state:GetAttributeChangedSignal("Phase"):Connect(function()
		if state:GetAttribute("Phase") == "Launching" then
			throttle = 1
			hintUntil = os.clock() + HINT_SECONDS
		end
	end)
end

return Pilot
