--[[
	ClientSwapHud -- the always-visible swap countdown + the T-3s telegraph.
	Location: StarterPlayerScripts/Client/ClientSwapHud  (ModuleScript)

	Reads `swapAtServerTime` off RoundStateChanged and renders via the pure
	SwapTelegraphModel: a small top-center timer always during Active, and during
	the last PREVIEW_SECONDS a ramping orange->red flash + a big centered 3/2/1 +
	a one-shot audio cue (Config.SWAP_WARNING_SOUND_ID; silent if "").

	Look (zones/caps/fonts) comes from the shared HudTheme; behavior is unchanged.
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

local HudTheme = require(script.Parent:WaitForChild("HudTheme"))

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
	gui.DisplayOrder = HudTheme.DisplayOrder.swap
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
	timer.Size = UDim2.fromScale(0.16, 0.08)
	timer.BackgroundTransparency = 1
	timer.Text = ""
	timer.ZIndex = 2
	HudTheme.placeInZone(timer, "topTimer")
	HudTheme.applyMaxSize(timer, "timer")
	HudTheme.styleText(timer, "heading")
	timer.Parent = gui

	local big = Instance.new("TextLabel")
	big.Name = "BigCountdown"
	big.Size = UDim2.fromScale(0.3, 0.3)
	big.BackgroundTransparency = 1
	big.Text = ""
	big.ZIndex = 2
	HudTheme.placeInZone(big, "center")
	HudTheme.styleText(big, "title")
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
			timer.Text = "" -- clear now so the banner's top zone isn't shared for a frame
			big.Text = ""
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

		-- Flash follows telegraph intensity, independent of the number, so it stays
		-- visible through the swap moment (bigCountdownInt is already nil by then and
		-- flashAlpha is held at peak until the next cycle's deadline arrives).
		if d.inPreview then
			flash.BackgroundTransparency = 1 - (d.flashAlpha * 0.5) -- up to 50% opaque
		else
			flash.BackgroundTransparency = 1
		end

		if d.bigCountdownInt then
			big.Text = tostring(d.bigCountdownInt)
			if d.bigCountdownInt ~= lastBigInt then
				lastBigInt = d.bigCountdownInt
				if warningSound and d.bigCountdownInt == Config.PREVIEW_SECONDS then
					warningSound:Play() -- one shot at telegraph entry
				end
			end
		else
			big.Text = ""
		end
	end)
end

return ClientSwapHud
