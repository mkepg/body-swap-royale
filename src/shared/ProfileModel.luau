--[[
	ProfileModel -- PURE profile shape + sanitation. Roblox-free. The persisted
	blob is { version, coins, totalXp }; level is derived from totalXp at read time
	(ProgressionModel), never stored. sanitize() coerces ANY loaded DataStore value
	(nil / partial / corrupt / old-version) into a valid current-version profile, so
	the ProfileStore wrapper stays dumb. `version` is injected (Config.PROFILE_VERSION).
	Location (Roblox): ReplicatedStorage/Shared/ProfileModel  (ModuleScript)
--]]

local ProfileModel = {}

-- Non-negative integer, or nil if v isn't a usable number.
local function toCount(v)
	if type(v) ~= "number" or v ~= v then -- reject non-numbers and NaN
		return nil
	end
	return math.max(0, math.floor(v))
end

function ProfileModel.default(version)
	return { version = version, coins = 0, totalXp = 0 }
end

function ProfileModel.sanitize(blob, version)
	local profile = ProfileModel.default(version)
	if type(blob) == "table" then
		profile.coins = toCount(blob.coins) or 0
		profile.totalXp = toCount(blob.totalXp) or 0
	end
	return profile
end

return ProfileModel
