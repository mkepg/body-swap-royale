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
local ShopModel = require(ReplicatedStorage.Shared.ShopModel)
local ShopCatalog = require(ReplicatedStorage.Shared.ShopCatalog)
local ProfileStore = require(script.Parent.ProfileStore)

local ProfileUpdated = Remotes.get("ProfileUpdated")
local RewardGranted = Remotes.get("RewardGranted")
local ShopResult = Remotes.get("ShopResult")

local EconomyService = {}

local profiles = {}  -- [player] = { version, coins, totalXp }
local persisted = {} -- [player] = bool (false => load failed: never save)

local rateStamps = {}   -- [player] = { os.clock() of recent requests }
local saveDebounce = {} -- [player] = token table; newest wins
local save -- forward-declared: scheduleSave below closes over it before its definition

local onEquipChanged = nil -- injected by init.server (avoids Economy<->Control cycle)
function EconomyService.setEquipChangedCallback(cb)
	onEquipChanged = cb
end

local function withinRate(player)
	local now = os.clock()
	local stamps = rateStamps[player] or {}
	local kept = {}
	for _, s in ipairs(stamps) do
		if now - s < Config.SHOP_RATE_WINDOW then kept[#kept + 1] = s end
	end
	-- kept is bounded at SHOP_RATE_MAX -- rejected requests are never recorded, so a flood cannot grow the array
	if #kept >= Config.SHOP_RATE_MAX then
		rateStamps[player] = kept
		return false
	end
	kept[#kept + 1] = now
	rateStamps[player] = kept
	return true
end

local function scheduleSave(player)
	local token = {}
	saveDebounce[player] = token
	task.delay(Config.SHOP_SAVE_DEBOUNCE, function()
		if saveDebounce[player] == token and profiles[player] then
			saveDebounce[player] = nil
			save(player)
		end
	end)
end

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
		ownedItems = profile.ownedItems,
		equipped = profile.equipped,
	}
end

local function pushProfile(player)
	local profile = profiles[player]
	if profile then
		ProfileUpdated:FireClient(player, viewOf(profile))
	end
end

function save(player)
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
	saveDebounce[player] = nil
	rateStamps[player] = nil
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

-- The Soul Shop gauntlet (spec §5.2). `payload` is a CLIENT CLAIM: sanitize
-- shape first, then let the pure ShopModel decide. Malformed/over-rate traffic
-- is dropped silently -- honest clients cannot produce it.
function EconomyService.onShopRequest(player, payload)
	if not withinRate(player) then
		return
	end
	if type(payload) ~= "table" then
		return
	end
	if payload.action == "sync" then
		-- Re-push the current profile so a client that missed the one-time join
		-- push (connected its handler late) can resync on demand. No mutation.
		if profiles[player] and persisted[player] then
			pushProfile(player)
		end
		return
	end
	if type(payload.itemId) ~= "string"
		or #payload.itemId > 64
		or (payload.action ~= "buy" and payload.action ~= "equip") then
		return
	end
	local profile = profiles[player]
	if not profile or not persisted[player] then
		ShopResult:FireClient(player, { ok = false, action = payload.action,
			itemId = payload.itemId, err = "profile_unavailable" })
		return
	end
	if payload.action == "buy" then
		local r = ShopModel.validatePurchase(profile, ShopCatalog, Config.SHOP_PRICES, payload.itemId)
		if not r.ok then
			ShopResult:FireClient(player, { ok = false, action = "buy",
				itemId = payload.itemId, err = r.err })
			return
		end
		ShopModel.applyPurchase(profile, r.item, Config.SHOP_PRICES)
		scheduleSave(player)
	else -- equip ("default" allowed; kind then required and must be a real slot)
		local kind = payload.kind
		if payload.itemId == "default"
			and kind ~= "halo_color" and kind ~= "halo_style" and kind ~= "trail" then
			return
		end
		local r = ShopModel.validateEquip(profile, ShopCatalog, payload.itemId, kind)
		if not r.ok then
			ShopResult:FireClient(player, { ok = false, action = "equip",
				itemId = payload.itemId, err = r.err })
			return
		end
		ShopModel.applyEquip(profile, r.kind, payload.itemId)
	end
	ShopResult:FireClient(player, { ok = true, action = payload.action, itemId = payload.itemId })
	pushProfile(player)
	if onEquipChanged then
		onEquipChanged() -- re-broadcast SoulMap with the new resolved look
	end
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
