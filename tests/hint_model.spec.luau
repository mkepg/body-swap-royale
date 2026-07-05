local HintModel = require("../src/shared/HintModel")

local function fail(msg) error("ASSERTION FAILED: " .. msg, 2) end
local function expect(cond, msg) if not cond then fail(msg) end end

local REG = {
	{ id = "a", trigger = "SwapPreview", once = true, priority = 10 },
	{ id = "b", trigger = "SwapPreview", once = true, priority = 20 },
	{ id = "c", trigger = "ControlSwap", once = false, priority = 5 },
}

-- unseen + trigger match -> highest priority row.
do
	local h = HintModel.resolve(REG, {}, "SwapPreview")
	expect(h and h.id == "b", "highest-priority match wins (got " .. tostring(h and h.id) .. ")")
	print("hint: priority tie-break OK")
end

-- unknown trigger -> nil.
do
	expect(HintModel.resolve(REG, {}, "Nope") == nil, "unknown trigger -> nil")
	print("hint: unknown trigger OK")
end

-- once + already seen -> that row is skipped; falls to next unseen match.
do
	local h = HintModel.resolve(REG, { "b" }, "SwapPreview")
	expect(h and h.id == "a", "seen 'b' -> next unseen match 'a'")
	local none = HintModel.resolve(REG, { "a", "b" }, "SwapPreview")
	expect(none == nil, "all matches seen -> nil")
	print("hint: once-ever gating OK")
end

-- once = false always returns even if seen.
do
	local h = HintModel.resolve(REG, { "c" }, "ControlSwap")
	expect(h and h.id == "c", "once=false ignores seen")
	print("hint: once=false OK")
end

-- accepts a set-like seen table too.
do
	local h = HintModel.resolve(REG, { b = true }, "SwapPreview")
	expect(h and h.id == "a", "set-like seen honored")
	print("hint: set-like seen OK")
end

-- empty registry -> nil.
do
	expect(HintModel.resolve({}, {}, "SwapPreview") == nil, "empty registry -> nil")
	print("hint: empty registry OK")
end

-- withSeen is non-mutating + idempotent + deduped.
do
	local orig = { "x" }
	local out = HintModel.withSeen(orig, "y")
	expect(#orig == 1, "original not mutated")
	expect(#out == 2, "withSeen adds")
	local again = HintModel.withSeen(out, "y")
	expect(#again == 2, "withSeen idempotent (no dup)")
	print("hint: withSeen OK")
end

print("ALL HintModel TESTS PASSED")
