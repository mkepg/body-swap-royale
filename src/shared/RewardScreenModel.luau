--[[
	RewardScreenModel -- PURE display decision for the end-of-round reward panel.
	Roblox-free; mirrors RoundScreenModel. The renderer (ClientEconomyHud) maps these
	strings/values to GUI. `grant` is the per-round delta from RewardGranted
	({ coins, xp, leveledUp }) or nil; `profileView` is the post-award totals from
	ProfileUpdated ({ level, progress, ... }).
	Location (Roblox): ReplicatedStorage/Shared/RewardScreenModel  (ModuleScript)
--]]

local RewardScreenModel = {}

function RewardScreenModel.display(grant, profileView)
	if grant == nil then
		return { visible = false }
	end
	local levelText
	if grant.leveledUp then
		levelText = "Level Up!  " .. tostring(profileView.level)
	else
		levelText = "Level " .. tostring(profileView.level)
	end
	return {
		visible = true,
		coinsText = "+" .. tostring(grant.coins) .. " Coins",
		xpText = "+" .. tostring(grant.xp) .. " XP",
		levelText = levelText,
		levelBarProgress = profileView.progress,
		leveledUp = grant.leveledUp == true,
	}
end

return RewardScreenModel
