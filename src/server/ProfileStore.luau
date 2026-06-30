--[[
	ProfileStore (server) -- thin DataStoreService wrapper. load() retries with
	backoff and, on total failure, returns (default, ok=false) so the caller refuses
	to save (no clobber). save() uses UpdateAsync (read-modify-write, never SetAsync)
	and retries. All shape/sanitation logic lives in the pure ProfileModel.
	Location (Roblox): ServerScriptService/Server/ProfileStore  (ModuleScript)
--]]

local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local ProfileModel = require(ReplicatedStorage.Shared.ProfileModel)

local ProfileStore = {}
local store = DataStoreService:GetDataStore(Config.DATASTORE_NAME)

local function keyFor(userId)
	return "player_" .. tostring(userId)
end

-- Returns (profile, ok). ok=false means the load failed every attempt: a default
-- profile is returned for play this session, but the caller must NOT save it.
function ProfileStore.load(userId)
	local key = keyFor(userId)
	for attempt = 1, Config.ECONOMY_LOAD_RETRIES do
		local success, result = pcall(function()
			return store:GetAsync(key)
		end)
		if success then
			return ProfileModel.sanitize(result, Config.PROFILE_VERSION), true
		end
		if attempt < Config.ECONOMY_LOAD_RETRIES then
			task.wait(Config.ECONOMY_RETRY_BACKOFF * attempt)
		end
	end
	return ProfileModel.default(Config.PROFILE_VERSION), false
end

-- Returns ok. UpdateAsync transform returns the sanitized session profile (the
-- in-memory profile is authoritative in this single-server MVP; last write wins).
function ProfileStore.save(userId, profile)
	local key = keyFor(userId)
	local clean = ProfileModel.sanitize(profile, Config.PROFILE_VERSION)
	for attempt = 1, Config.ECONOMY_SAVE_RETRIES do
		local success = pcall(function()
			store:UpdateAsync(key, function()
				return clean
			end)
		end)
		if success then
			return true
		end
		if attempt < Config.ECONOMY_SAVE_RETRIES then
			task.wait(Config.ECONOMY_RETRY_BACKOFF * attempt)
		end
	end
	warn(string.format("[BSR] economy: save failed for UserId %s", tostring(userId)))
	return false
end

return ProfileStore
