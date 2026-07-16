--[[
	ProfileModel -- PURE profile shape + sanitation. Roblox-free. The persisted
	blob is { version, coins, totalXp, seenHints, ownedItems, equipped }; level is
	derived from totalXp at read time (ProgressionModel), never stored. sanitize()
	coerces ANY loaded DataStore value (nil / partial / corrupt / old-version) into
	a valid current-version profile, so the ProfileStore wrapper stays dumb.
	`version` is injected (Config.PROFILE_VERSION).
	Location (Roblox): ReplicatedStorage/Shared/ProfileModel  (ModuleScript)
--]]

local ProfileModel = {}

-- Non-negative integer, or nil if v isn't a usable number.
local function toCount(v)
	if type(v) ~= "number" or v ~= v or v == math.huge or v == -math.huge then -- reject non-numbers, NaN, +/-inf
		return nil
	end
	return math.max(0, math.floor(v))
end

-- Array of unique non-empty strings; anything else -> {}. (Persisted hint-seen ids.)
local function toStringList(v)
	local out, seen = {}, {}
	if type(v) == "table" then
		for _, item in ipairs(v) do
			if type(item) == "string" and item ~= "" and not seen[item] then
				seen[item] = true
				out[#out + 1] = item
			end
		end
	end
	return out
end

-- The three equip slots; anything else in a persisted blob is dropped.
local EQUIP_KINDS = { halo_color = true, halo_style = true, trail = true }

-- Map of known kind -> non-empty string item id; everything else -> dropped.
local function toEquipped(v)
	local out = {}
	if type(v) == "table" then
		for kind, id in pairs(v) do
			if EQUIP_KINDS[kind] and type(id) == "string" and id ~= "" then
				out[kind] = id
			end
		end
	end
	return out
end

function ProfileModel.default(version)
	return { version = version, coins = 0, totalXp = 0, seenHints = {}, ownedItems = {}, equipped = {} }
end

function ProfileModel.sanitize(blob, version)
	local profile = ProfileModel.default(version)
	if type(blob) == "table" then
		profile.coins = toCount(blob.coins) or 0
		profile.totalXp = toCount(blob.totalXp) or 0
		profile.seenHints = toStringList(blob.seenHints)
		profile.ownedItems = toStringList(blob.ownedItems)
		profile.equipped = toEquipped(blob.equipped)
	end
	return profile
end

return ProfileModel
