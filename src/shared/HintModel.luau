--[[
	HintModel -- PURE decision core for the centralized hint system. Roblox-free,
	time-free. Given the hint registry, a player's seen-set, and an incoming trigger
	event, decides which hint (if any) to show, honoring per-hint `once` gating and
	`priority`. `withSeen` is the immutable seen-set update. All logic lives here so
	the server glue (HintService) stays dumb and this is lune-testable.
	Location (Roblox): ReplicatedStorage/Shared/HintModel  (ModuleScript)
--]]

local HintModel = {}

-- Accept EITHER an array of ids { "a", "b" } OR a set { a = true } -> canonical set.
local function toSet(seen)
	local set = {}
	if type(seen) == "table" then
		for _, id in ipairs(seen) do
			set[id] = true
		end
		for k, v in pairs(seen) do
			if type(k) == "string" and v then
				set[k] = true
			end
		end
	end
	return set
end

-- Highest-priority registry row whose trigger matches and which is either not `once`
-- or not yet in `seen`. nil if none.
function HintModel.resolve(registry, seen, trigger)
	local seenSet = toSet(seen)
	local best = nil
	for _, hint in ipairs(registry) do
		if hint.trigger == trigger and not (hint.once and seenSet[hint.id]) then
			if not best or (hint.priority or 0) > (best.priority or 0) then
				best = hint
			end
		end
	end
	return best
end

-- Immutable: a new sorted array of unique ids including `id`.
function HintModel.withSeen(seen, id)
	local set = toSet(seen)
	set[id] = true
	local out = {}
	for k in pairs(set) do
		out[#out + 1] = k
	end
	table.sort(out)
	return out
end

return HintModel
