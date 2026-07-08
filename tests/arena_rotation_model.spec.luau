local M = require("../src/shared/ArenaRotationModel")

local function fail(msg) error("ASSERTION FAILED: " .. msg, 2) end
local function expect(cond, msg) if not cond then fail(msg) end end

local IDS = { "hex", "sweeper" }

-- alternation: nil/unknown current -> first; known current -> next, wrapping.
do
	expect(M.next(nil, IDS, "") == "hex", "no current -> first arena")
	expect(M.next("hex", IDS, "") == "sweeper", "hex -> sweeper")
	expect(M.next("sweeper", IDS, "") == "hex", "sweeper wraps back to hex")
	expect(M.next("bogus", IDS, "") == "hex", "unknown current -> first arena")
	print("rotation: alternation OK")
end

-- override pins when it names a known arena; unknown override falls back to rotation.
do
	expect(M.next("hex", IDS, "hex") == "hex", "override pins hex")
	expect(M.next("sweeper", IDS, "hex") == "hex", "override pins regardless of current")
	expect(M.next("hex", IDS, "nope") == "sweeper", "unknown override -> normal rotation")
	expect(M.next("hex", IDS, nil) == "sweeper", "nil override -> normal rotation")
	print("rotation: override OK")
end

-- single-arena list is stable.
do
	expect(M.next(nil, { "hex" }, "") == "hex", "single arena -> itself")
	expect(M.next("hex", { "hex" }, "") == "hex", "single arena repeats")
	print("rotation: single-arena OK")
end

print("ALL ArenaRotationModel TESTS PASSED")
