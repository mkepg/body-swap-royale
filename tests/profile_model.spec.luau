local ProfileModel = require("../src/shared/ProfileModel")

local function fail(msg)
	error("ASSERTION FAILED: " .. msg, 2)
end

local function expect(cond, msg)
	if not cond then fail(msg) end
end

local V = 1

-- default() is a fresh zeroed profile stamped with the version.
do
	local p = ProfileModel.default(V)
	expect(p.version == 1 and p.coins == 0 and p.totalXp == 0, "default profile zeroed @ v1")
	print("profile: default OK")
end

-- sanitize(nil) -> default.
do
	local p = ProfileModel.sanitize(nil, V)
	expect(p.version == 1 and p.coins == 0 and p.totalXp == 0, "nil -> default")
	print("profile: sanitize-nil OK")
end

-- sanitize a full valid blob preserves values, restamps version.
do
	local p = ProfileModel.sanitize({ version = 0, coins = 230, totalXp = 1450 }, V)
	expect(p.coins == 230 and p.totalXp == 1450, "values preserved")
	expect(p.version == 1, "version restamped to current")
	print("profile: sanitize-valid OK")
end

-- Partial blob fills missing fields with 0.
do
	local p = ProfileModel.sanitize({ coins = 50 }, V)
	expect(p.coins == 50 and p.totalXp == 0, "missing totalXp -> 0")
	print("profile: sanitize-partial OK")
end

-- Corrupt / wrong-type / negative values coerce to non-negative ints.
do
	local p = ProfileModel.sanitize({ coins = -10, totalXp = "garbage" }, V)
	expect(p.coins == 0, "negative coins clamp to 0, got " .. tostring(p.coins))
	expect(p.totalXp == 0, "string totalXp -> 0")
	local q = ProfileModel.sanitize({ coins = 12.9, totalXp = 7.2 }, V)
	expect(q.coins == 12 and q.totalXp == 7, "floats floored")
	local r = ProfileModel.sanitize("not a table", V)
	expect(r.coins == 0 and r.totalXp == 0, "non-table -> default")
	print("profile: sanitize-corrupt OK")
end

-- Infinity (+/-) is not a usable count and must coerce to 0.
do
	local p = ProfileModel.sanitize({ coins = math.huge, totalXp = -math.huge }, V)
	expect(p.coins == 0, "+inf coins -> 0, got " .. tostring(p.coins))
	expect(p.totalXp == 0, "-inf totalXp -> 0, got " .. tostring(p.totalXp))
	print("profile: sanitize-infinity OK")
end

-- seenHints: default empty; sanitize keeps unique strings, drops junk, dedupes.
do
	local d = ProfileModel.default(V)
	expect(type(d.seenHints) == "table" and #d.seenHints == 0, "default seenHints = {}")
	local p = ProfileModel.sanitize({ coins = 1, totalXp = 1, seenHints = { "a", "a", 7, "b" } }, V)
	expect(#p.seenHints == 2, "dedupe + drop non-strings -> 2, got " .. #p.seenHints)
	local n = ProfileModel.sanitize({ seenHints = "nope" }, V)
	expect(type(n.seenHints) == "table" and #n.seenHints == 0, "non-array seenHints -> {}")
	print("profile: seenHints OK")
end

print("ALL ProfileModel TESTS PASSED")
