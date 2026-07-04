--[[
	ClientAnimator -- local, per-body, velocity-driven (v1.3 animation model).
	Location: StarterPlayerScripts/Client/ClientAnimator  (ModuleScript)

	Bodies are not player Characters, so the engine's default Animate never runs
	on them, and animations a client plays on a body do NOT replicate. So every
	client animates EVERY body locally, as a pure function of that body's
	replicated movement (AssemblyLinearVelocity + FloorMaterial):

	  - the body you control animates instantly (you own its physics);
	  - other bodies animate from their replicated velocity, matching what you see.

	There is no animation state to desync and no per-swap handoff -- the driver
	never cares who controls a body. It also self-heals: if a wanted track ever
	stops, it is re-played.

	Depends on:
	  ReplicatedStorage.Shared.Config  (ANIM asset ids)
	  workspace.Bodies                 (where BodyManager parents the bodies)
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local ClientAnimator = {}

local WALK_THRESHOLD = 0.5 -- studs/s of horizontal speed before "walk" kicks in
local RISING_THRESHOLD = 1 -- upward studs/s that reads as "jump" rather than "fall"

-- A body's Humanoid can lag one or more frames behind its ChildAdded on a cold join, so
-- loadTracks returns nil and the body would never animate for the session. Retry until the
-- rig replicates (same late-replication class ClientControl already guards against).
local REGISTER_MAX_ATTEMPTS = 10
local REGISTER_RETRY_SECONDS = 0.2

-- [body] = { tracks = { idle, walk, jump, fall }, current = stateName }
local rigs = {}

local function loadTracks(body)
	local hum = body:FindFirstChildOfClass("Humanoid")
	if not hum then return nil end
	local animator = hum:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = hum
	end
	local tracks = {}
	for name, id in pairs(Config.ANIM) do
		local anim = Instance.new("Animation")
		anim.AnimationId = id
		local track = animator:LoadAnimation(anim)
		track.Looped = (name ~= "jump") -- idle/walk/fall loop; jump is a one-shot
		track.Priority = Enum.AnimationPriority.Movement
		tracks[name] = track
	end
	return tracks
end

local function wantedState(body, hum)
	local root = body:FindFirstChild("HumanoidRootPart")
	if not root then return "idle" end
	local vel = root.AssemblyLinearVelocity
	if hum.FloorMaterial == Enum.Material.Air then
		return vel.Y > RISING_THRESHOLD and "jump" or "fall"
	end
	local horizontal = Vector3.new(vel.X, 0, vel.Z).Magnitude
	return horizontal > WALK_THRESHOLD and "walk" or "idle"
end

local function register(body)
	if rigs[body] then return end
	-- Retry off the caller's thread: loadTracks needs the Humanoid, which may not have
	-- replicated yet. Give up after REGISTER_MAX_ATTEMPTS (body is likely gone).
	task.spawn(function()
		for _ = 1, REGISTER_MAX_ATTEMPTS do
			if not body.Parent or rigs[body] then return end -- removed, or registered elsewhere
			local tracks = loadTracks(body)
			if tracks then
				if body.Parent and not rigs[body] then
					rigs[body] = { tracks = tracks, current = nil }
				end
				return
			end
			task.wait(REGISTER_RETRY_SECONDS)
		end
	end)
end

local function update()
	for body, rig in pairs(rigs) do
		if not body.Parent then
			rigs[body] = nil
		else
			local hum = body:FindFirstChildOfClass("Humanoid")
			if hum then
				local want = wantedState(body, hum)
				local track = rig.tracks[want]
				if rig.current ~= want then
					for name, t in pairs(rig.tracks) do
						if name ~= want and t.IsPlaying then
							t:Stop(0.1)
						end
					end
					if track and not track.IsPlaying then
						track:Play(0.1)
					end
					rig.current = want
				elseif track and not track.IsPlaying then
					track:Play(0.1) -- self-heal: re-assert the wanted track
				end
			end
		end
	end
end

function ClientAnimator.start()
	local folder = workspace:WaitForChild("Bodies")
	for _, body in ipairs(folder:GetChildren()) do
		register(body)
	end
	folder.ChildAdded:Connect(function(child)
		task.defer(register, child) -- let the humanoid/rig settle first
	end)
	folder.ChildRemoved:Connect(function(child)
		rigs[child] = nil
	end)
	RunService.RenderStepped:Connect(update)
end

return ClientAnimator
