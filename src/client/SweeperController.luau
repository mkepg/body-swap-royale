--[[
	SweeperController (client) -- 100% cosmetic beam rendering for the Soul Sweeper arena.
	Renders per-tier rotating beam bars (low = amber JUMP, high = red STAY GROUNDED) whose
	angle is computed from the pure SweeperModel at the SAME elapsed the server strike math
	uses (round-start server time read from the SweeperField attribute). A faded telegraph
	bar leads each beam so a just-swapped player can read their inherited spot. Never drives
	gameplay -- fed by authoritative state only.

	Location: StarterPlayerScripts/Client/SweeperController (ModuleScript)
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local SweeperModel = require(Shared:WaitForChild("SweeperModel"))

local SweeperController = {}

-- Watch the local player's controlled body for a server sweep stamp and play a brief
-- cosmetic tumble (a decaying spin on the body's root). Debounced: ignores stamps that
-- arrive while a tumble is already playing. Fed by authoritative state; never drives it.
local function watchTumble(getOwnBody)
	local tumbling = false
	local function attach(body)
		local root = body and body:FindFirstChild("HumanoidRootPart")
		if not root then return end
		local last = 0
		body:GetAttributeChangedSignal("SweptAt"):Connect(function()
			local t = body:GetAttribute("SweptAt")
			if not t or t == last or tumbling then return end
			last = t
			tumbling = true
			task.spawn(function()
				local dur = Config.SWEEP_TUMBLE_SECONDS
				local t0 = os.clock()
				while os.clock() - t0 < dur do
					local f = 1 - (os.clock() - t0) / dur -- decay
					root.CFrame = root.CFrame * CFrame.Angles(0, 0, math.rad(18 * f))
					RunService.RenderStepped:Wait()
				end
				tumbling = false
			end)
		end)
	end
	-- Re-attach whenever the controlled body changes (SetControlledBody remote already exists).
	task.spawn(function()
		while true do
			attach(getOwnBody())
			task.wait(1)
		end
	end)
end

local function tierRadius(k) return Config.SWEEP_TOP_RADIUS + k * Config.SWEEP_RADIUS_STEP end
local function tierSurfaceY(k) return Config.SWEEP_TOP_SURFACE_Y - k * Config.SWEEP_TIER_GAP end

local function newBar(folder, len, thickness, color, transparency)
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.Neon
	p.Color = color
	p.Transparency = transparency
	p.Size = Vector3.new(len, thickness, thickness)
	p.Parent = folder
	return p
end

-- One rendered arm: the solid beam + a faded leading telegraph bar.
local function buildArms()
	local folder = workspace:FindFirstChild("SweeperBeams")
	if folder then folder:Destroy() end
	folder = Instance.new("Folder")
	folder.Name = "SweeperBeams"
	folder.Parent = Workspace

	local arms = {}
	for k = 0, Config.SWEEP_TIER_COUNT - 1 do
		local r = tierRadius(k)
		for _, beam in ipairs(Config.SWEEP_TIER_BEAMS[k + 1] or {}) do
			local color = beam.class == "low" and Config.SWEEP_BEAM_LOW_COLOR or Config.SWEEP_BEAM_HIGH_COLOR
			local yOff = beam.class == "low" and Config.SWEEP_BEAM_LOW_Y or Config.SWEEP_BEAM_HIGH_Y
			for armIndex = 0, beam.armCount - 1 do
				arms[#arms + 1] = {
					beam = beam, armIndex = armIndex, k = k, radius = r,
					y = tierSurfaceY(k) + yOff,
					bar = newBar(folder, r, Config.SWEEP_BEAM_THICKNESS, color, 0),
					lead = newBar(folder, r, Config.SWEEP_BEAM_THICKNESS, color, 0.65),
				}
			end
		end
	end
	return folder, arms
end

-- Position a bar so its length runs from center out to the rim along `angle`.
local function placeBar(bar, angle, radius, y)
	local dirX, dirZ = math.cos(angle), math.sin(angle)
	local mid = Vector3.new(dirX * radius / 2, y, dirZ * radius / 2)
	bar.CFrame = CFrame.lookAt(mid, mid + Vector3.new(dirX, 0, dirZ)) * CFrame.Angles(0, math.rad(90), 0)
end

function SweeperController.start(getOwnBody)
	if getOwnBody then watchTumble(getOwnBody) end
	local _folder, arms = buildArms()
	local speedOpts = { rampPerSecond = Config.SWEEP_SPEED_RAMP_PER_SEC, maxSpeed = Config.SWEEP_SPEED_MAX }

	RunService.RenderStepped:Connect(function()
		local field = Workspace:FindFirstChild("SweeperField")
		local startT = field and field:GetAttribute("RoundStartServerT")
		if not startT then return end -- no active sweeper round: leave bars where they are
		local elapsed = Workspace:GetServerTimeNow() - startT
		for _, a in ipairs(arms) do
			local speed = SweeperModel.rampedSpeed(a.beam.baseSpeed, elapsed, speedOpts)
			local angle = SweeperModel.beamAngle(a.beam, a.armIndex, speed, elapsed)
			placeBar(a.bar, angle, a.radius, a.y)
			local lead = angle + a.beam.direction * Config.SWEEP_TELEGRAPH_LEAD
			placeBar(a.lead, lead, a.radius, a.y)
		end
	end)
end

return SweeperController
