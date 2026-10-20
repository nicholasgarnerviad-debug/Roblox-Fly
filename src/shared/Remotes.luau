-- Remote access. The server creates them on demand; clients wait for them.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local FUNCTIONS = { BuildAction = true }

local Remotes = {}

local function getFolder()
	local folder = ReplicatedStorage:FindFirstChild("Remotes")
	if folder then
		return folder
	end
	if RunService:IsServer() then
		folder = Instance.new("Folder")
		folder.Name = "Remotes"
		folder.Parent = ReplicatedStorage
		return folder
	end
	return ReplicatedStorage:WaitForChild("Remotes")
end

function Remotes.get(name)
	local folder = getFolder()
	local remote = folder:FindFirstChild(name)
	if remote then
		return remote
	end
	if RunService:IsServer() then
		remote = Instance.new(FUNCTIONS[name] and "RemoteFunction" or "RemoteEvent")
		remote.Name = name
		remote.Parent = folder
		return remote
	end
	return folder:WaitForChild(name)
end

return Remotes
