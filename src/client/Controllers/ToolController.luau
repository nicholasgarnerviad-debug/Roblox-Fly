-- Rust-style building tools:
--   Building Plan  place pieces (Q: piece wheel, R: rotate, M: mirror)
--   Hammer         Q: upgrade tier (once an island unlocks it) / rotate / demolish;
--                  in flight, click damage to repair
--   Paint Brush    pick a colour, click a piece (T: paint a balloon's stripe instead)
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Grid = require(Shared.Grid)
local Materials = require(Shared.Materials)
local PartTypes = require(Shared.PartTypes)
local PartBuilder = require(Shared.PartBuilder)
local Remotes = require(Shared.Remotes)
local UI = require(script.Parent.Parent.UI)
local Radial = require(script.Parent.Parent.Radial)

local player = Players.LocalPlayer
local state = ReplicatedStorage:WaitForChild("GameState")
local C = UI.Colors

local Tools = {}

local TOOL_NAMES = { ["Building Plan"] = "Plan", ["Hammer"] = "Hammer", ["Paint Brush"] = "Brush" }
local TOOL_LOOK = {
	Plan = { "\u{1F4D8}", "Building Plan" },
	Hammer = { "\u{1F528}", "Hammer" },
	Brush = { "\u{1F58C}\u{FE0F}", "Paint Brush" },
}
local BLUE = Color3.fromRGB(80, 170, 255)
local RED = Color3.fromRGB(240, 70, 60)
local YELLOW = Color3.fromRGB(255, 210, 80)
local FORWARD = Vector3.new(0, 0, -1)
local HORIZ = { Vector3.new(1, 0, 0), Vector3.new(-1, 0, 0), Vector3.new(0, 0, 1), Vector3.new(0, 0, -1) }
local DECKISH = { Deck = true, Hull = true, Core = true }

local HUD
local equipped, toolConn = nil, nil
local selPart, rot, mirror, page = "Deck", 0, false, 1
local paintColor = nil
local paintStripe = false -- Paint Brush: paint a balloon's stripe instead of its body
local hover, target = nil, nil
local ghost, ghostMirror, ghostType
local highlight
local panel, toolBadge, titleLabel, infoLabel, msgPill, msgLabel, buttonRow, piecesBtn, rotateBtn, mirrorBtn, stripeBtn, swatchRow
local swatches = {}
local busy = false
local msgUntil = 0
local lastTouch = nil

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Include

local function plane()
	return workspace:FindFirstChild("CrewPlane")
end

local function coreCF()
	local m = plane()
	return m and m.PrimaryPart and m.PrimaryPart.CFrame
end

local function building()
	return state:GetAttribute("Phase") == "Build"
end

local function airborne()
	local p = state:GetAttribute("Phase")
	return p == "Flying" or p == "Launching" or p == "Landing"
end

local function nearShip()
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	local cf = coreCF()
	return hrp and cf and (hrp.Position - cf.Position).Magnitude < 90
end

local function flash(text, color)
	msgLabel.Text = text
	msgLabel.TextColor3 = color or C.text
	UI.stroke(msgPill, color or C.brass, 2, 0.1)
	msgPill.Visible = true
	UI.pop(msgPill, 1.12)
	msgUntil = os.clock() + 3
end

local function costText(typeName, materialName)
	local currency, amount = PartTypes.cost(typeName, materialName, Materials)
	local m = Materials.get(currency)
	return string.format("%d %s", amount, m and m.display or currency), currency, amount
end

local function canAfford(typeName, materialName)
	local _, currency, amount = costText(typeName, materialName)
	return (state:GetAttribute(currency) or 0) >= amount
end

-- Occupancy snapshot of the live ship (rebuilt whenever pieces change) ------------

local occCells, occFaces, occCount, occDirty, watched = {}, {}, {}, true, nil

local function occupancy()
	local m = plane()
	if m ~= watched then
		watched = m
		occDirty = true
		if m then
			m.ChildAdded:Connect(function()
				occDirty = true
			end)
			m.ChildRemoved:Connect(function()
				occDirty = true
			end)
		end
	end
	if occDirty then
		occCells, occFaces, occCount = { [Grid.key(0, 1, 0)] = "Reserved" }, {}, {}
		if m then
			for _, model in ipairs(m:GetChildren()) do
				local main = model:FindFirstChild("Main")
				local key = main and main:GetAttribute("Key")
				local t = main and main:GetAttribute("PartType")
				if key and t then
					occCount[t] = (occCount[t] or 0) + 1
					if Grid.isEdgeKey(key) then
						local x, y, z, a = Grid.parseEdge(key)
						for i = 0, (PartTypes.get(t).span or 2) - 1 do
							occFaces[Grid.faceKey(x, y + i, z, a)] = t
						end
					else
						occCells[key] = t
					end
				end
			end
		end
		occDirty = false
	end
	return occCells, occFaces, occCount
end

-- What's under the cursor ---------------------------------------------------------

local function pieceUnder()
	local m, cf = plane(), coreCF()
	if not m or not cf then
		return nil
	end
	rayParams.FilterDescendantsInstances = { m }
	local cam = workspace.CurrentCamera
	local ray
	if lastTouch then
		ray = cam:ScreenPointToRay(lastTouch.X, lastTouch.Y)
	else
		local p = UserInputService:GetMouseLocation()
		ray = cam:ViewportPointToRay(p.X, p.Y)
	end
	local res = workspace:Raycast(ray.Origin, ray.Direction * 300, rayParams)
	if not res then
		return nil
	end
	local inst = res.Instance
	while inst and inst.Parent ~= m do
		inst = inst.Parent
	end
	local main = inst and inst:FindFirstChild("Main")
	local key = main and main:GetAttribute("Key")
	if not key then
		return nil
	end
	local h = {
		key = key,
		model = inst,
		main = main,
		type = main:GetAttribute("PartType"),
		material = main:GetAttribute("Material"),
		reinforced = main:GetAttribute("Reinforced") == true,
		normal = Grid.roundNormal(cf:VectorToObjectSpace(res.Normal)),
		localHit = cf:PointToObjectSpace(res.Position),
	}
	if Grid.isEdgeKey(key) then
		local x, y, z, a = Grid.parseEdge(key)
		h.kind, h.edge, h.span = "edge", { x, y, z, a }, PartTypes.get(h.type).span or 2
	else
		h.kind, h.cell = "cell", Grid.parseV(key)
	end
	return h
end

-- Building Plan: snapping -------------------------------------------------------------

local function computeTarget(h)
	if not h then
		return nil
	end
	local def = PartTypes.get(selPart)
	local n = h.normal
	if def.kind == "edge" then
		if h.kind == "edge" then
			if n.Y > 0.5 then -- stack on top of a wall
				return { edge = { h.edge[1], h.edge[2] + h.span, h.edge[3], h.edge[4] } }
			end
			return nil
		end
		local c = h.cell
		local d
		if n.Y > 0.5 then -- looking down at a floor: snap to its nearest edge
			local lp = h.localHit - Grid.offset(c)
			if math.abs(lp.X) > math.abs(lp.Z) then
				d = Vector3.new(lp.X >= 0 and 1 or -1, 0, 0)
			else
				d = Vector3.new(0, 0, lp.Z >= 0 and 1 or -1)
			end
		elseif math.abs(n.Y) < 0.5 then -- looking at the side of a floor
			d = n
		else
			return nil
		end
		local fx, fz, fa = Grid.faceToward(c.X, c.Z, d)
		return { edge = { fx, c.Y + 1, fz, fa } }
	end
	if h.kind == "edge" then -- step off the wall into the tile beside it
		return { cell = Grid.cellFromLocal(h.localHit + n * 2) }
	end
	return { cell = h.cell + n }
end

local function checkEdge(e, cells, faces, counts)
	local def = PartTypes.get(selPart)
	local x, y, z, a = e[1], e[2], e[3], e[4]
	local span = def.span or 2
	local b = Config.BUILD_BOUNDS
	if y < 1 or y + span - 1 > b.maxY then
		return false, "Too high (or low) for the build bay"
	end
	for i = 0, span - 1 do
		if faces[Grid.faceKey(x, y + i, z, a)] then
			return false, "There's already a wall there"
		end
	end
	local ax, az, bx, bz = Grid.edgeSides(x, z, a)
	local floorBelow = DECKISH[cells[Grid.key(ax, y - 1, az)] or ""] or DECKISH[cells[Grid.key(bx, y - 1, bz)] or ""]
	if not floorBelow and not faces[Grid.faceKey(x, y - 1, z, a)] then
		return false, def.display .. " must stand on the edge of a floor"
	end
	if (counts and counts[selPart] or 0) >= (def.maxPerShip or math.huge) then
		return false, "Limit reached"
	end
	return true
end

local function checkCell(cellV, cells, faces, counts)
	local def = PartTypes.get(selPart)
	if not Grid.inBounds(cellV) then
		return false, "Outside the build bay"
	elseif cells[Grid.keyV(cellV)] then
		return false, "Something's already there"
	end
	local touching = false
	for _, d in ipairs(Grid.Dirs) do
		if cells[Grid.keyV(cellV + d)] then
			touching = true
		end
	end
	for _, d in ipairs(HORIZ) do
		local fx, fz, fa = Grid.faceToward(cellV.X, cellV.Z, d)
		if faces[Grid.faceKey(fx, cellV.Y, fz, fa)] or faces[Grid.faceKey(fx, cellV.Y + 1, fz, fa)] then
			touching = true
		end
	end
	if not touching then
		return false, "Must attach to the airship"
	end
	local below = cells[Grid.keyV(cellV - Vector3.yAxis)]
	if def.needsSupport and not (below == "Deck" or below == "Hull") then
		return false, def.display .. " must stand on a floor"
	elseif def.needsMast and not (below == "Mast" or below == "Sail") then
		return false, def.display .. " goes on top of a mast"
	elseif
		def.needsFrontClear
		and (cells[Grid.keyV(cellV + FORWARD)] or faces[Grid.faceKey(cellV.X, cellV.Y, cellV.Z - 1, "Z")])
	then
		return false, "Propeller needs open air in front"
	elseif cells[Grid.keyV(cellV - FORWARD)] == "Engine" then
		return false, "That would block a propeller"
	elseif def.maxPerShip and (counts[selPart] or 0) >= def.maxPerShip then
		return false, string.format("Max %d %ss per ship: make them count!", def.maxPerShip, def.display)
	end
	return true
end

local function checkTarget(t)
	if not t then
		return false, nil
	end
	local cells, faces, counts = occupancy()
	local ok, why
	if t.edge then
		ok, why = checkEdge(t.edge, cells, faces, counts)
	else
		ok, why = checkCell(t.cell, cells, faces, counts)
	end
	if ok and not canAfford(selPart, PartTypes.placeMaterial(selPart)) then
		return false, "Need " .. costText(selPart, PartTypes.placeMaterial(selPart)) .. " (go gather!)"
	end
	return ok, why
end

local function mirrorTarget(t)
	if t.edge then
		local x, y, z, a = Grid.mirrorEdge(t.edge[1], t.edge[2], t.edge[3], t.edge[4])
		if x == t.edge[1] and z == t.edge[3] then
			return nil
		end
		return { edge = { x, y, z, a } }
	end
	if t.cell.X == 0 then
		return nil
	end
	return { cell = Vector3.new(-t.cell.X, t.cell.Y, t.cell.Z) }
end

-- Ghosts ----------------------------------------------------------------------------

local function clearGhosts()
	for _, g in ipairs({ ghost, ghostMirror }) do
		if g then
			g:Destroy()
		end
	end
	ghost, ghostMirror, ghostType = nil, nil, nil
end

-- Rust-style blueprint hologram: every part becomes glowing ForceField in blue/red.
local function tintGhost(g, ok)
	if g:GetAttribute("Ok") == ok then
		return
	end
	g:SetAttribute("Ok", ok)
	for _, d in ipairs(g:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Color = ok and BLUE or RED
		end
	end
end

local function makeGhost()
	-- show the solid shape (not the thin twig frame) so the hologram reads clearly
	local ghostMat = PartTypes.get(selPart).tiered and "Wood" or PartTypes.placeMaterial(selPart)
	local model = PartBuilder.build(selPart, ghostMat)
	PartBuilder.makeGhost(model)
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Material = Enum.Material.ForceField
			d.MaterialVariant = ""
			d.Transparency = d.Transparency >= 0.99 and 1 or 0.15
		elseif d:IsA("SurfaceGui") or d:IsA("Decal") then
			d:Destroy()
		end
	end
	model.Name = "BuildGhost"
	model.Parent = workspace
	tintGhost(model, true)
	return model
end

local function placeGhost(g, t, ok, r)
	local cf = coreCF()
	if not g or not cf or not t then
		if g then
			g:PivotTo(CFrame.new(0, -1000, 0))
		end
		return
	end
	local def = PartTypes.get(selPart)
	if t.edge then
		local e = t.edge
		g:PivotTo(cf * Grid.edgeCFrame(e[1], e[2], e[3], e[4]) * Grid.rotCFrame(r))
	else
		g:PivotTo(cf * CFrame.new(Grid.offset(t.cell)) * Grid.rotCFrame(def.rotatable and r or 0))
	end
	tintGhost(g, ok == true)
end

-- Radial menus --------------------------------------------------------------------------

local function selectPart(name)
	selPart = name
	if PartTypes.isEdge(name) then
		rot = rot % 2 == 0 and rot or 0
	end
	clearGhosts()
end

local function openPieceWheel()
	local cat = PartTypes.Categories[page]
	local other = PartTypes.Categories[page % #PartTypes.Categories + 1]
	local items = {}
	for _, name in ipairs(cat.parts) do
		local def = PartTypes.get(name)
		local mat = PartTypes.placeMaterial(name)
		table.insert(items, {
			id = name,
			icon = def.icon,
			label = def.display,
			sub = costText(name, mat),
			info = (mat == "Twig" and "Goes down as twig. " or "") .. def.blurb,
			selected = name == selPart,
		})
	end
	Radial.open({
		title = cat.icon .. " " .. cat.name,
		items = items,
		switchText = "\u{21C4} " .. other.name,
		onSwitch = function()
			page = page % #PartTypes.Categories + 1
			openPieceWheel()
		end,
		onPick = function(id)
			selectPart(id)
		end,
	})
end

local function send(action, data, okText)
	if busy then
		return
	end
	busy = true
	task.spawn(function()
		local ok, err = Remotes.get("BuildAction"):InvokeServer(action, data)
		busy = false
		if not ok and err then
			flash(err, C.danger)
		elseif ok and okText then
			flash(okText, C.good)
		end
	end)
end

local function openHammerWheel(h)
	if not h then
		flash("Look at a piece of the ship first.", C.warn)
		return
	end
	if h.type == "Core" then
		flash("The helm can't be changed.", C.warn)
		return
	end
	local def = PartTypes.get(h.type)
	local unlocked = state:GetAttribute("UnlockedIsland") or 1
	local items = {}
	for _, mname in ipairs(Materials.TierOrder) do
		-- only tiers unlocked by landing on later islands are upgrades (Bamboo 2, Scrap 3, Tin 4)
		local island = Materials.upgradeIsland(mname)
		if island and mname ~= h.material and PartTypes.allows(h.type, mname) then
			local mat = Materials.get(mname)
			local locked = island > unlocked
			local affordable = canAfford(h.type, mname)
			local stats = string.format("x%.2g weight, x%.2g HP. %s", mat.weight, mat.hp, mat.blurb)
			table.insert(items, {
				id = "mat:" .. mname,
				icon = mat.icon,
				label = mat.display,
				sub = locked and ("\u{1F512} Island " .. island) or costText(h.type, mname),
				info = locked
						and string.format("Land on island %d to unlock %s upgrades. %s", island, mat.display, stats)
					or stats,
				disabled = locked or not affordable,
			})
		end
	end
	-- reinforcements found while exploring (PartTypes.Reinforce)
	local rf = PartTypes.Reinforce[h.type]
	if rf then
		local found = state:GetAttribute(rf.unlock) == true
		local costs, affordable = {}, true
		for currency, amount in pairs(rf.cost) do
			local m = Materials.get(currency)
			table.insert(costs, string.format("%d %s", amount, m and m.display or currency))
			if (state:GetAttribute(currency) or 0) < amount then
				affordable = false
			end
		end
		table.insert(items, {
			id = "reinforce",
			icon = rf.icon,
			label = h.reinforced and "Reinforced" or rf.display,
			sub = h.reinforced and "\u{2714} done"
				or (found and table.concat(costs, " + ") or "\u{1F512} Find the plans"),
			info = found and rf.blurb or ("Find the plans at " .. rf.where .. ". " .. rf.blurb),
			disabled = h.reinforced or not found or not affordable,
		})
	end
	if def.rotatable or def.kind == "edge" then
		table.insert(items, { id = "rotate", icon = "\u{1F504}", label = "Rotate", info = "Turn this piece." })
	end
	table.insert(items, {
		id = "remove",
		icon = "\u{1F5D1}",
		label = "Demolish",
		sub = "refund",
		info = "Remove it and get the materials back.",
	})
	local key = h.key
	Radial.open({
		title = string.format(
			"%s%s %s",
			h.reinforced and "Reinforced " or "",
			Materials.get(h.material).display,
			def.display
		),
		items = items,
		onPick = function(id)
			if id == "rotate" then
				send("rotate", { key = key })
			elseif id == "remove" then
				send("remove", { key = key, mirror = mirror })
			elseif id == "reinforce" then
				send("reinforce", { key = key, mirror = mirror }, "Balloon reinforced!")
			else
				local mname = string.sub(id, 5)
				send(
					"upgrade",
					{ key = key, material = mname, mirror = mirror },
					"Upgraded to " .. Materials.get(mname).display .. "!"
				)
			end
		end,
	})
end

-- Actions -------------------------------------------------------------------------------

local function rotate()
	if equipped == "Plan" then
		if PartTypes.isEdge(selPart) then
			rot = (rot + 2) % 4
		elseif PartTypes.get(selPart).rotatable then
			rot = (rot + 1) % 4
		else
			flash(PartTypes.get(selPart).display .. " always faces forward.", C.dim)
		end
	elseif equipped == "Hammer" and hover and building() then
		send("rotate", { key = hover.key })
	end
end

local function activate()
	if Radial.isOpen() then
		return
	end
	if equipped == "Plan" then
		if not building() then
			flash("You can only build in the hangar.", C.warn)
			return
		end
		local t = computeTarget(pieceUnder())
		local ok, why = checkTarget(t)
		if not t then
			flash("Aim at the airship to place a piece.", C.warn)
		elseif not ok then
			flash(why or "Can't place that there", C.danger)
		else
			send("place", { partType = selPart, cell = t.cell, edge = t.edge, rot = rot, mirror = mirror })
		end
	elseif equipped == "Hammer" then
		local h = pieceUnder()
		if airborne() then
			if h then
				send("repair", { key = h.key })
			end
		elseif building() then
			openHammerWheel(h)
		end
	elseif equipped == "Brush" then
		local h = pieceUnder()
		if not building() then
			flash("Paint in the hangar.", C.warn)
		elseif h and paintStripe and PartTypes.get(h.type).trim then
			-- "Natural" (no colour) puts the stripe back to its automatic colour
			send("paint", { key = h.key, color = paintColor, part = "trim", mirror = mirror })
		elseif h then
			local color = paintColor or Materials.get(h.material).color
			send("paint", { key = h.key, color = color, mirror = mirror })
		end
	end
end

-- UI --------------------------------------------------------------------------------------

local function refreshButtons()
	if equipped and TOOL_LOOK[equipped] then
		toolBadge.Text = TOOL_LOOK[equipped][1]
	end
	mirrorBtn.Text = mirror and "\u{2194}\u{FE0F} Mirror: ON" or "\u{2194}\u{FE0F} Mirror: OFF"
	UI.setVariant(mirrorBtn, mirror and "info" or "secondary")
	piecesBtn.Visible = equipped == "Plan" or equipped == "Hammer"
	piecesBtn.Text = equipped == "Hammer" and "\u{2699}\u{FE0F} Upgrade" or "\u{2B55} Pieces"
	rotateBtn.Visible = equipped ~= "Brush"
	swatchRow.Visible = equipped == "Brush"
	stripeBtn.Visible = equipped == "Brush"
	stripeBtn.Text = paintStripe and "\u{1F388} Stripe" or "\u{1F3A8} Body"
	UI.setVariant(stripeBtn, paintStripe and "info" or "secondary")
	-- outside the hangar there's nothing to pick (the Hammer only repairs), so the panel
	-- folds down to a slim header and keeps the view clear
	local compact = not building()
	buttonRow.Visible = not compact
	panel.Size = UDim2.fromOffset(compact and 460 or (equipped == "Brush" and 770 or 600), compact and 58 or 102)
	for i, b in pairs(swatches) do
		local selected = (i == 0 and paintColor == nil) or (paintColor ~= nil and Config.PaintColors[i] == paintColor)
		UI.stroke(b, selected and C.accent or C.inset, selected and 3 or 1.5, selected and 0 or 0.3)
	end
end

local function buildUI(gui)
	panel = UI.panel({ Name = "ToolPanel", Size = UDim2.fromOffset(600, 102), Visible = false, Parent = gui })
	UI.padding(panel, 10, 9)
	HUD.dock(panel, HUD.DOCK.Tool)
	-- feedback ("Need 3 Wood", "Upgraded!") pops up in a pill above the panel
	msgPill = UI.panel({
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 0, -16),
		Size = UDim2.fromOffset(0, 34),
		AutomaticSize = Enum.AutomaticSize.X,
		Visible = false,
		Parent = panel,
	})
	UI.padding(msgPill, 14, 0)
	msgLabel = UI.label({
		Size = UDim2.fromOffset(0, 34),
		AutomaticSize = Enum.AutomaticSize.X,
		Text = "",
		TextSize = 17,
		Parent = msgPill,
	})
	toolBadge = UI.badge("", 38, { TextSize = 21, Parent = panel })
	titleLabel = UI.label({
		Position = UDim2.fromOffset(48, 0),
		Size = UDim2.new(1, -48, 0, 21),
		Text = "",
		TextSize = 19,
		TextXAlignment = Enum.TextXAlignment.Left,
		RichText = true,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = panel,
	})
	infoLabel = UI.label({
		Position = UDim2.fromOffset(48, 21),
		Size = UDim2.new(1, -48, 0, 18),
		Text = "",
		TextSize = 14,
		Font = UI.Body,
		TextColor3 = C.dim,
		TextXAlignment = Enum.TextXAlignment.Left,
		RichText = true,
		Parent = panel,
	})
	local row = UI.new("Frame", {
		Position = UDim2.fromOffset(0, 48),
		Size = UDim2.new(1, 0, 0, 34),
		BackgroundTransparency = 1,
		Parent = panel,
	})
	buttonRow = row
	UI.list(row, Enum.FillDirection.Horizontal, 8)
	piecesBtn = UI.button({
		Size = UDim2.fromOffset(160, 32),
		Text = "",
		TextSize = 16,
		LayoutOrder = 1,
		Variant = "primary",
		Key = "Q",
		Parent = row,
	})
	piecesBtn.Activated:Connect(function()
		if equipped == "Plan" then
			openPieceWheel()
		elseif equipped == "Hammer" then
			openHammerWheel(hover)
		end
	end)
	rotateBtn = UI.button({
		Size = UDim2.fromOffset(130, 32),
		Text = "\u{1F504} Rotate",
		TextSize = 16,
		LayoutOrder = 2,
		Key = "R",
		Parent = row,
	})
	rotateBtn.Activated:Connect(rotate)
	mirrorBtn = UI.button({
		Size = UDim2.fromOffset(160, 32),
		Text = "",
		TextSize = 16,
		LayoutOrder = 3,
		Key = "M",
		Parent = row,
	})
	mirrorBtn.Activated:Connect(function()
		mirror = not mirror
		refreshButtons()
	end)
	stripeBtn = UI.button({
		Size = UDim2.fromOffset(130, 32),
		Text = "",
		TextSize = 16,
		LayoutOrder = 4,
		Key = "T",
		Visible = false,
		Parent = row,
	})
	stripeBtn.Activated:Connect(function()
		paintStripe = not paintStripe
		refreshButtons()
	end)
	swatchRow = UI.new(
		"Frame",
		{ Size = UDim2.fromOffset(450, 32), BackgroundTransparency = 1, LayoutOrder = 5, Visible = false, Parent = row }
	)
	UI.list(swatchRow, Enum.FillDirection.Horizontal, 5)
	local natural = UI.button({
		Name = "NaturalBtn",
		Size = UDim2.fromOffset(58, 28),
		Text = "Natural",
		TextSize = 12,
		LayoutOrder = 0,
		Parent = swatchRow,
	})
	natural.Activated:Connect(function()
		paintColor = nil
		refreshButtons()
	end)
	swatches[0] = natural
	for i, col in ipairs(Config.PaintColors) do
		local b = UI.button({
			Name = "Swatch" .. i,
			Size = UDim2.fromOffset(26, 26),
			Text = "",
			BackgroundColor3 = col,
			LayoutOrder = i,
			Parent = swatchRow,
		})
		UI.round(b)
		b.Activated:Connect(function()
			paintColor = col
			refreshButtons()
		end)
		swatches[i] = b
	end
end

local function hoverText(h)
	if not h then
		return ""
	end
	local mat = Materials.get(h.material)
	local hp, max = h.main:GetAttribute("HP") or 0, h.main:GetAttribute("MaxHP") or 1
	local col = UI.hex(hp / max < 0.5 and "danger" or "good")
	return string.format(
		'%s %s %s  \u{2022}  <font color="%s">HP %d/%d</font>',
		mat and mat.icon or "",
		mat and mat.display or "",
		PartTypes.get(h.type).display,
		col,
		hp,
		max
	)
end

local function setEquipped(kind, tool)
	if toolConn then
		toolConn:Disconnect()
		toolConn = nil
	end
	equipped = kind
	Radial.close()
	clearGhosts()
	highlight.Enabled = false
	panel.Visible = kind ~= nil
	if tool then
		toolConn = tool.Activated:Connect(activate)
	end
	if kind then
		refreshButtons()
	end
end

local function watchCharacter(char)
	char.ChildAdded:Connect(function(child)
		if child:IsA("Tool") and TOOL_NAMES[child.Name] then
			setEquipped(TOOL_NAMES[child.Name], child)
		end
	end)
	char.ChildRemoved:Connect(function(child)
		if child:IsA("Tool") and TOOL_NAMES[child.Name] and TOOL_NAMES[child.Name] == equipped then
			setEquipped(nil)
		end
	end)
end

local function update()
	if not equipped then
		return
	end
	if os.clock() > msgUntil then
		msgPill.Visible = false
	end
	if buttonRow.Visible ~= building() then
		refreshButtons()
	end
	if Radial.isOpen() then
		return
	end
	hover = pieceUnder()
	if equipped == "Plan" then
		highlight.Enabled = false
		local def = PartTypes.get(selPart)
		local mat = PartTypes.placeMaterial(selPart)
		titleLabel.Text = string.format(
			'Building Plan:  %s  <font size="15" color="%s">%s%s</font>',
			UI.tint(def.icon .. " " .. def.display, "accent"),
			UI.hex("dim"),
			mat == "Twig" and "twig, " or "",
			costText(selPart, mat)
		)
		if not building() or not nearShip() then
			infoLabel.Text = "Head back to the hangar to build."
			placeGhost(ghost, nil)
			placeGhost(ghostMirror, nil)
			return
		end
		if ghostType ~= selPart then
			clearGhosts()
			ghost, ghostMirror, ghostType = makeGhost(), makeGhost(), selPart
		end
		target = computeTarget(hover)
		local ok, why = checkTarget(target)
		placeGhost(ghost, target, ok, rot)
		local mt = (mirror and target) and mirrorTarget(target) or nil
		if mt then
			placeGhost(ghostMirror, mt, checkTarget(mt), PartTypes.isEdge(selPart) and rot or Grid.mirrorRot(rot))
		else
			placeGhost(ghostMirror, nil)
		end
		if not target then
			infoLabel.Text = def.kind == "edge" and "Aim at the edge of a floor to snap a wall."
				or "Aim at the airship to attach a piece."
		elseif ok then
			infoLabel.Text = UI.tint("\u{25CF} Click to place", BLUE)
				.. "   \u{2022}   the hologram shows where it goes"
		else
			infoLabel.Text = UI.tint("\u{25CF} " .. (why or "Can't place here"), "danger")
		end
	else
		local tool = equipped == "Hammer" and "Hammer" or "Paint Brush"
		if hover then
			highlight.Adornee = hover.model
			highlight.Enabled = true
			local c = equipped == "Brush" and (paintColor or YELLOW) or YELLOW
			highlight.FillColor = c
			highlight.OutlineColor = c
		else
			highlight.Enabled = false
		end
		titleLabel.Text = tool .. (hover and (":  " .. hoverText(hover)) or "")
		if equipped == "Hammer" then
			if airborne() then
				infoLabel.Text = "Click damaged parts to patch them up!"
			elseif building() then
				infoLabel.Text = "Click or Q: upgrade / rotate / demolish the piece you're looking at"
			else
				infoLabel.Text = ""
			end
		elseif not building() then
			infoLabel.Text = "Paint in the hangar."
		elseif hover and PartTypes.get(hover.type).trim then
			infoLabel.Text = paintStripe
					and "Click to paint the balloon's <b>stripe</b>  \u{2022}  T: paint the balloon itself"
				or "Click to paint the <b>balloon</b>  \u{2022}  T: paint its stripe instead"
		else
			infoLabel.Text = "Pick a colour, then click pieces to paint them."
		end
	end
end

function Tools.start(hud)
	HUD = hud
	buildUI(HUD.gui())
	Radial.init(HUD.gui())
	-- NOTE: a Highlight with no Adornee highlights its parent, so keep it disabled when idle
	highlight = Instance.new("Highlight")
	highlight.Name = "ToolHover"
	highlight.Enabled = false
	highlight.FillTransparency = 0.65
	highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	highlight.Parent = workspace.CurrentCamera

	if player.Character then
		watchCharacter(player.Character)
	end
	player.CharacterAdded:Connect(function(char)
		setEquipped(nil)
		watchCharacter(char)
	end)

	UserInputService.InputBegan:Connect(function(input, processed)
		if input.UserInputType == Enum.UserInputType.Touch then
			lastTouch = input.Position
		elseif
			input.UserInputType == Enum.UserInputType.MouseMovement
			or input.UserInputType == Enum.UserInputType.MouseButton1
		then
			lastTouch = nil
		end
		if processed or not equipped then
			return
		end
		local kc = input.KeyCode
		if kc == Enum.KeyCode.Q then
			if Radial.isOpen() then
				Radial.close()
			elseif equipped == "Plan" then
				openPieceWheel()
			elseif equipped == "Hammer" and building() then
				openHammerWheel(hover)
			end
		elseif kc == Enum.KeyCode.R then
			rotate()
		elseif kc == Enum.KeyCode.M then
			mirror = not mirror
			refreshButtons()
		elseif kc == Enum.KeyCode.T and equipped == "Brush" then
			paintStripe = not paintStripe
			refreshButtons()
		end
	end)
	UserInputService.InputChanged:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseMovement then
			lastTouch = nil
		end
	end)
	state:GetAttributeChangedSignal("Phase"):Connect(function()
		Radial.close()
		clearGhosts()
	end)
	RunService.RenderStepped:Connect(update)
end

return Tools
