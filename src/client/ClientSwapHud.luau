--[[
	ClientSwapHud -- the always-visible swap countdown + the T-3s telegraph.
	Location: StarterPlayerScripts/Client/ClientSwapHud  (ModuleScript)

	Reads `swapAtServerTime` off RoundStateChanged and renders via the pure
	SwapTelegraphModel: a small top-center timer always during Active, and during
	the last PREVIEW_SECONDS a ramping orange->red flash + a big centered 3/2/1 +
	a one-shot audio cue (Config.SWAP_WARNING_SOUND_ID; silent if "").
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local SwapTelegraphModel = require(Shared:WaitForChild("SwapTelegraphModel"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local RoundStateChanged = Remotes.get("RoundStateChanged")

local ClientSwapHud = {}
local player = Players.LocalPlayer

local phase = "Lobby"
local swapAtServerTime = nil
local lastBigInt = nil
local warningSound = nil

function ClientSwapHud.start()
	local gui = Instance.new("ScreenGui")
	gui.Name = "SwapHud"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.Parent = player:WaitForChild("PlayerGui")

	local flash = Instance.new("Frame")
	flash.Name = "Flash"
	flash.Size = UDim2.fromScale(1, 1)
	flash.BackgroundColor3 = Config.TELEGRAPH_FLASH_COLOR
	flash.BackgroundTransparency = 1
	flash.BorderSizePixel = 0
	flash.ZIndex = 1
	flash.Parent = gui

	local timer = Instance.new("TextLabel")
	timer.Name = "Timer"
	timer.AnchorPoint = Vector2.new(0.5, 0)
	timer.Position = UDim2.fromScale(0.5, 0.03)
	timer.Size = UDim2.fromScale(0.16, 0.08)
	timer.BackgroundTransparency = 1
	timer.TextScaled = true
	timer.Font = Enum.Font.GothamBold
	timer.TextColor3 = Color3.new(1, 1, 1)
	timer.TextStrokeTransparency = 0.4
	timer.Text = ""
	timer.ZIndex = 2
	timer.Parent = gui

	local big = Instance.new("TextLabel")
	big.Name = "BigCountdown"
	big.AnchorPoint = Vector2.new(0.5, 0.5)
	big.Position = UDim2.fromScale(0.5, 0.4)
	big.Size = UDim2.fromScale(0.3, 0.3)
	big.BackgroundTransparency = 1
	big.TextScaled = true
	big.Font = Enum.Font.GothamBlack
	big.TextColor3 = Color3.new(1, 1, 1)
	big.TextStrokeTransparency = 0.2
	big.Text = ""
	big.ZIndex = 2
	big.Parent = gui

	if Config.SWAP_WARNING_SOUND_ID ~= "" then
		warningSound = Instance.new("Sound")
		warningSound.Name = "SwapWarning"
		warningSound.SoundId = Config.SWAP_WARNING_SOUND_ID
		warningSound.Parent = SoundService
	end

	RoundStateChanged.OnClientEvent:Connect(function(state)
		phase = state.phase
		if state.swapAtServerTime then
			swapAtServerTime = state.swapAtServerTime
		end
		if phase ~= "Active" then
			swapAtServerTime = nil
			lastBigInt = nil
		end
	end)

	RunService.RenderStepped:Connect(function()
		if phase ~= "Active" or not swapAtServerTime then
			flash.BackgroundTransparency = 1
			timer.Text = ""
			big.Text = ""
			return
		end

		local secondsUntilSwap = swapAtServerTime - workspace:GetServerTimeNow()
		local d = SwapTelegraphModel.display(secondsUntilSwap, Config.PREVIEW_SECONDS)

		timer.Text = d.timerText
		if d.inPreview and d.bigCountdownInt then
			big.Text = tostring(d.bigCountdownInt)
			flash.BackgroundTransparency = 1 - (d.flashAlpha * 0.5) -- up to 50% opaque
			if d.bigCountdownInt ~= lastBigInt then
				lastBigInt = d.bigCountdownInt
				if warningSound and d.bigCountdownInt == Config.PREVIEW_SECONDS then
					warningSound:Play() -- one shot at telegraph entry
				end
			end
		else
			big.Text = ""
			flash.BackgroundTransparency = 1
		end
	end)
end

return ClientSwapHud
