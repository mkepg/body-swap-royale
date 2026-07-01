--[[
	EconomyService (server) -- owns the in-memory authoritative profile cache (the
	session source of truth) and the persisted flag. Loads on join, saves on leave /
	autosave / BindToClose, and awards each round via the pure RewardModel +
	ProgressionModel. Pushes ProfileUpdated (HUD totals) + RewardGranted (per-round
	delta) to the owning client. A profile whose load failed is flagged persisted=false
	and never saved (no clobber).
	Location (Roblox): ServerScriptService/Server/EconomyService  (ModuleScript)
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local RewardModel = require(ReplicatedStorage.Shared.RewardModel)
local ProgressionModel = require(ReplicatedStorage.Shared.ProgressionModel)
local ProfileStore = require(script.Parent.ProfileStore)

local ProfileUpdated = Remotes.get("ProfileUpdated")
local RewardGranted = Remotes.get("RewardGranted")

local EconomyService = {}

local profiles = {}  -- [player] = { version, coins, totalXp }
local persisted = {} -- [player] = bool (false => load failed: never save)

local function progressionOpts()
	return {
		coeff = Config.PROGRESSION_XP_COEFF,
		exp = Config.PROGRESSION_XP_EXP,
		maxLevel = Config.PROGRESSION_MAX_LEVEL,
	}
end

local function rewardOpts()
	return {
		xpBase = Config.REWARD_XP_BASE,
		xpPerSwap = Config.REWARD_XP_PER_SWAP,
		xpWin = Config.REWARD_XP_WIN,
		coinsBase = Config.REWARD_COINS_BASE,
		coinsPerSwap = Config.REWARD_COINS_PER_SWAP,
		coinsWin = Config.REWARD_COINS_WIN,
	}
end

local function viewOf(profile)
	local lv = ProgressionModel.levelFor(profile.totalXp, progressionOpts())
	return {
		coins = profile.coins,
		level = lv.level,
		xpIntoLevel = lv.xpIntoLevel,
		xpForNext = lv.xpForNext,
		progress = lv.progress,
	}
end

local function pushProfile(player)
	local profile = profiles[player]
	if profile then
		ProfileUpdated:FireClient(player, viewOf(profile))
	end
end

local function save(player)
	local profile = profiles[player]
	if profile and persisted[player] then
		ProfileStore.save(player.UserId, profile)
	end
end

function EconomyService.getProfile(player)
	return profiles[player]
end

function EconomyService.onPlayerAdded(player)
	local profile, ok = ProfileStore.load(player.UserId)
	profiles[player] = profile
	persisted[player] = ok
	pushProfile(player)
	if not ok then
		warn(string.format(
			"[BSR] economy: load failed for %s (UserId %d); this session will NOT be saved",
			player.Name, player.UserId))
	end
end

function EconomyService.onPlayerRemoving(player)
	save(player)
	profiles[player] = nil
	persisted[player] = nil
end

-- Award one round to one player. ctx = { survivedSwaps, isWinner, participated }.
-- Mutates the cached profile and fires RewardGranted (delta) + ProfileUpdated (totals).
function EconomyService.awardRound(player, ctx)
	local profile = profiles[player]
	if not profile then
		return -- player left mid-round (profile already saved + dropped)
	end
	-- Pre-award snapshot drives the client's XP-fill animation (XpFillModel start state).
	local beforeLv = ProgressionModel.levelFor(profile.totalXp, progressionOpts())
	local reward = RewardModel.rewardFor(ctx, rewardOpts())
	profile.coins += reward.coins
	profile.totalXp += reward.xp
	local afterLevel = ProgressionModel.levelFor(profile.totalXp, progressionOpts()).level
	RewardGranted:FireClient(player, {
		coins = reward.coins,
		xp = reward.xp,
		leveledUp = afterLevel > beforeLv.level,
		before = {
			level = beforeLv.level,
			xpIntoLevel = beforeLv.xpIntoLevel,
			xpForNext = beforeLv.xpForNext,
		},
	})
	pushProfile(player)
end

function EconomyService.start()
	-- Periodic background autosave for everyone in the server.
	task.spawn(function()
		while true do
			task.wait(Config.ECONOMY_AUTOSAVE_SECONDS)
			for _, player in ipairs(Players:GetPlayers()) do
				save(player)
			end
		end
	end)
	-- Flush all cached profiles on shutdown (within Roblox's BindToClose budget).
	game:BindToClose(function()
		for _, player in ipairs(Players:GetPlayers()) do
			save(player)
		end
	end)
end

return EconomyService
