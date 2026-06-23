--[[
	RoundScreenModel -- PURE round-flow bookend display decision (Lobby + Results).
	Location (Roblox): ReplicatedStorage/Shared/RoundScreenModel  (ModuleScript)

	No Roblox APIs, no clocks, no RNG: the caller injects the RoundStateChanged
	snapshot plus local-player context, and gets back what the banner should show.
	The renderer maps the semantic `accent` string to a Color3, keeping this module
	Roblox-free. Mirrors SwapTelegraphModel / GraceModel.

	state = { phase, winnerName, secondsRemaining }   (swap fields are ignored)
	ctx   = { localPlayerName, connectedCount, minPlayers }

	Returns:
	  visible       : false during Active (banner hidden); true for Lobby/Ended
	  titleText     : the big line (or nil)
	  subtitleText  : the small line under it (or nil)
	  bottomText    : the bottom line (or nil)
	  winnerName    : name for the fixed WINNER label slot (or nil)
	  accent        : "neutral" | "win" | "lose"  (renderer maps to a Color3)
--]]

local RoundScreenModel = {}

function RoundScreenModel.display(state, ctx)
	local phase = state.phase

	if phase == "Lobby" then
		local count = string.format("%d / %d players", ctx.connectedCount, ctx.minPlayers)
		local title
		if state.secondsRemaining == nil then
			title = "Waiting for players"
		else
			title = "Round starting in " .. tostring(state.secondsRemaining)
		end
		return {
			visible = true,
			titleText = title,
			subtitleText = count,
			bottomText = nil,
			winnerName = nil,
			accent = "neutral",
		}
	elseif phase == "Ended" then
		local bottom = nil
		if state.secondsRemaining ~= nil then
			bottom = "Next round in " .. tostring(state.secondsRemaining)
		end
		local winner = state.winnerName
		local title, accent
		if winner == nil then
			title, accent = "Round over", "neutral"
		elseif winner == ctx.localPlayerName then
			title, accent = "Victory", "win"
		else
			title, accent = "Defeated", "lose"
		end
		return {
			visible = true,
			titleText = title,
			subtitleText = nil,
			bottomText = bottom,
			winnerName = winner,
			accent = accent,
		}
	end

	-- Active (or any non-bookend phase): banner hidden.
	return {
		visible = false,
		titleText = nil,
		subtitleText = nil,
		bottomText = nil,
		winnerName = nil,
		accent = "neutral",
	}
end

return RoundScreenModel
