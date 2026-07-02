--[[
	DeviceOrientation -- force landscape on mobile.
	Location: StarterPlayerScripts/Client/DeviceOrientation  (ModuleScript)

	Body Swap Royale is a camera-relative arena game; portrait crops away the arena
	and the controls. Setting PlayerGui.ScreenOrientation to LandscapeSensor locks the
	experience to landscape (auto left/right by the device sensor) as soon as the
	player joins. Set on PlayerGui at runtime -- NOT StarterGui, which does not take
	effect on rotation once the session is live. No-op on desktop.
--]]

local Players = game:GetService("Players")

local DeviceOrientation = {}

function DeviceOrientation.start()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	playerGui.ScreenOrientation = Enum.ScreenOrientation.LandscapeSensor
end

return DeviceOrientation
