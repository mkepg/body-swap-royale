--[[
	ControlModel -- PURE controllers<->bodies state machine.
	Location (Roblox): ReplicatedStorage/Shared/ControlModel  (ModuleScript)

	No Roblox APIs and no requires of its own, so it can be unit-tested from the
	terminal with lune and shipped unchanged via Rojo. Keys ("players" and
	"bodies") are opaque values compared with ==; in production they are Player
	and body-Model instances, in tests they are plain strings.

	Invariant it maintains: every body in play is controlled by exactly one
	connected player, and every connected player controls exactly one body
	(a bijection). Spawn, swap, and disconnect all preserve it.
--]]

local ControlModel = {}

-- Sattolo's algorithm: one pass, single-cycle permutation = always a derangement
-- (no element keeps its index). `randint(m)` must return an integer in [1, m].
function ControlModel.derange(list, randint)
	for i = #list, 2, -1 do
		local j = randint(i - 1) -- draw from 1..i-1 (never i): guarantees no fixed point
		list[i], list[j] = list[j], list[i]
	end
	return list
end

function ControlModel.new()
	return {
		players = {},      -- [player] = true   (connected set)
		bodyOf = {},       -- [player] = body    (body the player currently controls)
		controllerOf = {}, -- [body]   = player  (inverse of bodyOf)
		ownerBody = {},    -- [player] = body    (the body wearing this player's avatar; stable)
	}
end

-- A player joins/spawns: they own a fresh body and start by controlling it.
function ControlModel.addPlayer(model, player, body)
	model.players[player] = true
	model.ownerBody[player] = body
	model.bodyOf[player] = body
	model.controllerOf[body] = player
end

function ControlModel.controlledBody(model, player)
	return model.bodyOf[player]
end

-- True iff every connected player controls exactly one body and vice versa.
function ControlModel.bijectionHolds(model)
	local nPlayers, nBodies = 0, 0
	for player in pairs(model.players) do
		nPlayers += 1
		local body = model.bodyOf[player]
		if body == nil or model.controllerOf[body] ~= player then
			return false
		end
	end
	for _body, player in pairs(model.controllerOf) do
		nBodies += 1
		if model.players[player] == nil then
			return false
		end
	end
	return nPlayers == nBodies
end

-- Rotate control among the given connected players. Deranges their CURRENT bodies
-- (Sattolo), so nobody keeps the body they were just in. Because it permutes the
-- exact same set of bodies the players already hold, it stays a bijection.
-- Returns an array of { player = <player>, body = <body> } describing the new map.
function ControlModel.swap(model, orderedPlayers, randint)
	assert(#orderedPlayers >= 2, "swap needs >= 2 players")

	local bodies = {}
	for i, player in ipairs(orderedPlayers) do
		bodies[i] = model.bodyOf[player]
	end

	ControlModel.derange(bodies, randint)

	-- Every body in `bodies` gets exactly one new controller, so overwriting
	-- controllerOf/bodyOf fully reassigns with no stale entries.
	local result = {}
	for i, player in ipairs(orderedPlayers) do
		local newBody = bodies[i]
		model.bodyOf[player] = newBody
		model.controllerOf[newBody] = player
		result[i] = { player = player, body = newBody }
	end
	return result
end

return ControlModel
