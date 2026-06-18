--[[
	ClientRoundHud -- minimal round feedback.
	Location: StarterPlayerScripts/Client/ClientRoundHud  (ModuleScript)

	Renders centered text from the round remotes (lobby countdown, elimination,
	winner) and, when this client is eliminated, retargets the spectator camera to
	a living body. This is intentionally minimal -- the full HUD is a later task.
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Remotes"))
local RoundStateChanged = Remotes.get("RoundStateChanged")
local EliminationEvent = Remotes.get("EliminationEvent")
local SpectateBody = Remotes.get("SpectateBody")

local ClientRoundHud = {}

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

local function makeLabel()
	local gui = Instance.new("ScreenGui")
	gui.Name = "RoundHud"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.Parent = player:WaitForChild("PlayerGui")

	local label = Instance.new("TextLabel")
	label.Name = "Status"
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.fromScale(0.5, 0.18)
	label.Size = UDim2.fromScale(0.8, 0.12)
	label.BackgroundTransparency = 1
	label.TextScaled = true
	label.Font = Enum.Font.GothamBold
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0.4
	label.Text = ""
	label.Parent = gui
	return label
end

function ClientRoundHud.start()
	local label = makeLabel()

	RoundStateChanged.OnClientEvent:Connect(function(state)
		if state.phase == "Lobby" then
			if state.secondsRemaining then
				label.Text = "Round starting in " .. tostring(state.secondsRemaining)
			else
				label.Text = "Waiting for players..."
			end
		elseif state.phase == "Active" then
			label.Text = ""
		elseif state.phase == "Ended" then
			label.Text = state.winnerName and ("Winner: " .. state.winnerName) or "Round over"
		end
	end)

	EliminationEvent.OnClientEvent:Connect(function(playerName)
		if playerName == player.Name then
			label.Text = "You were eliminated"
		end
	end)

	SpectateBody.OnClientEvent:Connect(function(body)
		local hum = body and body:FindFirstChildOfClass("Humanoid")
		if hum then
			camera.CameraType = Enum.CameraType.Custom
			camera.CameraSubject = hum
		end
	end)
end

return ClientRoundHud
