--[[
	PingDirectionModel -- PURE screen-projection math for the swap-preview directional
	ping. The controller does the Roblox call (Camera:WorldToViewportPoint) and passes
	the raw numbers here so this stays Roblox-free + lune-testable.

	resolve(sx, sy, sz, w, h, margin):
	  sx,sy = viewport pixel coords; sz = depth (>0 in front of camera, <=0 behind);
	  w,h   = viewport size; margin = edge inset for the off-screen arrow.
	Returns { onScreen, x, y, rotationDeg }:
	  onScreen -> target projects inside the margin rect AND is in front; x,y = sx,sy.
	  else     -> x,y clamped to the margin rect along the direction to the target;
	              rotationDeg rotates an UP-pointing arrow (screen -Y) to face it
	              (0 = up, 90 = right, 180 = down, -90 = left).
	Location (Roblox): ReplicatedStorage/Shared/PingDirectionModel  (ModuleScript)
--]]

local PingDirectionModel = {}

function PingDirectionModel.resolve(sx, sy, sz, w, h, margin)
	local cx, cy = w * 0.5, h * 0.5
	local inFront = sz > 0
	local onScreen = inFront
		and sx >= margin and sx <= (w - margin)
		and sy >= margin and sy <= (h - margin)
	if onScreen then
		return { onScreen = true, x = sx, y = sy, rotationDeg = 0 }
	end

	local dx, dy = sx - cx, sy - cy
	if not inFront then
		dx, dy = -dx, -dy -- behind camera: WorldToViewportPoint mirrors the point; flip it
	end
	if dx == 0 and dy == 0 then
		dy = -1 -- degenerate: point up
	end

	local halfW = math.max(cx - margin, 1)
	local halfH = math.max(cy - margin, 1)
	local scale
	if dx == 0 then
		scale = halfH / math.abs(dy)
	elseif dy == 0 then
		scale = halfW / math.abs(dx)
	else
		scale = math.min(halfW / math.abs(dx), halfH / math.abs(dy))
	end

	return {
		onScreen = false,
		x = cx + dx * scale,
		y = cy + dy * scale,
		rotationDeg = math.deg(math.atan2(dx, -dy)),
	}
end

return PingDirectionModel
