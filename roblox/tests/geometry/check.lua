-- Runs the real WorldBuilder against the mock and verifies every tower can be
-- climbed Hand-over-Hand, mirroring the client's rules:
--   * every face has climbable surface from the ground to the summit
--   * nothing solid is in the climbing lane anywhere (no leftover platforms)
--   * rest bars on every face at every rest level, non-colliding, matching
--     the RestLevels attribute the client reads
--   * every face can climb over the top onto the summit (ray-style mantle)
--   * zones and attributes line up with the geometry
-- (Bundled after mock.lua and the game modules by run_geometry.py.)

local Config = __req("Config")
local WorldBuilder = __req("WorldBuilder")
local _, towers = WorldBuilder.build()

local CC = Config.Climb
local EPS = 0.05
local failures = 0
local function fail(msg)
	failures += 1
	if failures <= 40 then
		print("FAIL " .. msg)
	end
end

-- Axis-aligned box (in tower space) of a part.
local function box(inv, part)
	local c = inv * part.CFrame
	local s = part.Size / 2
	local hx = math.abs(c.r.X) * s.X + math.abs(c.u.X) * s.Y + math.abs(c.b.X) * s.Z
	local hy = math.abs(c.r.Y) * s.X + math.abs(c.u.Y) * s.Y + math.abs(c.b.Y) * s.Z
	local hz = math.abs(c.r.Z) * s.X + math.abs(c.u.Z) * s.Y + math.abs(c.b.Z) * s.Z
	local p = c.p
	return { min = Vector3.new(p.X - hx, p.Y - hy, p.Z - hz), max = Vector3.new(p.X + hx, p.Y + hy, p.Z + hz), part = part, cf = c }
end

local function overlaps(a, b)
	return a.min.X < b.max.X - 0.01 and a.max.X > b.min.X + 0.01
		and a.min.Y < b.max.Y - 0.01 and a.max.Y > b.min.Y + 0.01
		and a.min.Z < b.max.Z - 0.01 and a.max.Z > b.min.Z + 0.01
end

local function boxAt(center, size)
	return { min = center - size / 2, max = center + size / 2 }
end

local AXES = { Vector3.new(0, 0, -1), Vector3.new(1, 0, 0), Vector3.new(0, 0, 1), Vector3.new(-1, 0, 0) }

-- How far a climbable part's outer surface reaches along `axis` at height y
-- (exact for tilted lattice panels), or nil if it doesn't span y.
local function surfaceExtent(b, axis, y)
	local c = b.cf
	-- Whichever side of the part faces outward along `axis` (a facade block is
	-- climbable on all four sides; a lattice panel only on its +X side).
	local sides = { { c.r, b.part.Size.X / 2 }, { -c.r, b.part.Size.X / 2 }, { c.b, b.part.Size.Z / 2 }, { -c.b, b.part.Size.Z / 2 } }
	local surface = nil
	for _, side in sides do
		if side[1]:Dot(axis) >= 0.9 then
			surface = c.p + side[1] * side[2]
		end
	end
	if not surface then
		return nil
	end
	if math.abs(c.u.Y) < 1e-6 then
		return nil
	end
	local t = (y - surface.Y) / c.u.Y
	if math.abs(t) > b.part.Size.Y / 2 + 1e-6 then
		return nil
	end
	return (surface + c.u * t):Dot(axis)
end

local function faceExtent(climbables, axis, y)
	local best = nil
	for _, b in climbables do
		local e = surfaceExtent(b, axis, y)
		if e and (best == nil or e > best) then
			best = e
		end
	end
	return best
end

-- A point in tower space `d` studs out along `axis` at lateral offset 0.
local function onAxis(axis, d, y)
	return Vector3.new(axis.X * d, y, axis.Z * d)
end

-- Client mantle search (mirrors ClimbController.findMantle): first inward
-- offset with a non-climbable floor at `floorY`, headroom above it, and a clear
-- path from the hold to the standing spot.
local function canMantle(solids, axis, ext, floorY)
	local anchorD = ext + CC.WallOffset
	for _, offset in { 0, 1.5, 3, 4.5, 6 } do
		local d = anchorD - offset
		local p = onAxis(axis, d, floorY)
		local floored = false
		for _, S in solids do
			if math.abs(S.max.Y - floorY) < EPS and p.X >= S.min.X - EPS and p.X <= S.max.X + EPS and p.Z >= S.min.Z - EPS and p.Z <= S.max.Z + EPS then
				floored = true
			end
		end
		if floored then
			local standY = floorY + 3
			local head = boxAt(onAxis(axis, d, floorY + 2.6), Vector3.new(0.2, 4.9, 0.2))
			local a, b = onAxis(axis, anchorD, standY), onAxis(axis, d, standY)
			local path = { min = Vector3.new(math.min(a.X, b.X), standY - 0.05, math.min(a.Z, b.Z)) - Vector3.new(0.05, 0, 0.05), max = Vector3.new(math.max(a.X, b.X), standY + 0.05, math.max(a.Z, b.Z)) + Vector3.new(0.05, 0, 0.05) }
			local free = true
			for _, S in solids do
				if overlaps(head, S) or overlaps(path, S) then
					free = false
				end
			end
			if free then
				return true
			end
		end
	end
	return false
end

local totalParts = 0
for _, tower in towers:GetChildren() do
	local name = tower.Name
	local inv = tower.WorldPivot:Inverse()
	local H = tower:GetAttribute("Height")
	local climbables, solids = {}, {}
	local peak, baseZone
	local count, restBars = 0, 0
	for _, part in tower:GetDescendants() do
		if part:IsA("BasePart") then
			count += 1
			local b = box(inv, part)
			if part.ClassName == "TrussPart" then
				fail(name .. ": still has a ladder")
			elseif part:HasTag("RestBar") then
				restBars += 1
				if part.CanCollide ~= false or part.CanQuery ~= false then
					fail(name .. ": rest bars must not collide or block climbing raycasts")
				end
			elseif part:HasTag("Climbable") then
				table.insert(climbables, b)
			elseif part.Name == "PeakZone" then
				peak = b
			elseif part.Name == "BaseZone" then
				baseZone = b
			elseif part.CanCollide ~= false then
				table.insert(solids, b)
			end
		end
	end
	totalParts += count

	-- Rest levels from the attribute the client reads.
	local levels = {}
	for value in string.gmatch(tower:GetAttribute("RestLevels") or "", "[^,]+") do
		table.insert(levels, tonumber(value))
	end
	local prev = 0
	for _, y in levels do
		if y <= prev then
			fail(name .. ": rest levels must increase")
		end
		prev = y
	end
	local def = Config.TowerTypes[(function()
		for _, entry in Config.Layout do
			if entry.Name == name then
				return entry.Type
			end
		end
		return ""
	end)()]
	local spacing = if def.Kind == "Telecom" then def.SectionHeight else def.BalconyEvery
	local expected = math.round(H / spacing) - 1
	if #levels ~= expected then
		fail(string.format("%s: expected %d rest levels, got %d", name, expected, #levels))
	end
	if restBars ~= #levels * 4 then
		fail(string.format("%s: expected a rest bar on each face at each level (%d), got %d", name, #levels * 4, restBars))
	end

	for fi, axis in AXES do
		local face = string.format("%s face %d", name, fi - 1)
		-- Continuous climbable surface from the ground to the summit.
		for y = 1, H - 1, 2 do
			if not faceExtent(climbables, axis, y) then
				fail(string.format("%s: nothing to grip at y=%d", face, y))
				break
			end
		end
		-- Nothing solid anywhere in the climbing lane, ground to summit
		-- (checked in 10-stud slices so the lane follows the taper).
		for y0 = 1, H - 3, 10 do
			local y1 = math.min(y0 + 10, H - 2)
			local ext = faceExtent(climbables, axis, (y0 + y1) / 2)
			if ext then
				local a, b = onAxis(axis, ext + 0.6, y0), onAxis(axis, ext + 2.6, y1)
				local lateral = if math.abs(axis.X) > 0.5 then Vector3.new(0, 0, 1.5) else Vector3.new(1.5, 0, 0)
				local lane = {
					min = Vector3.new(math.min(a.X, b.X), y0, math.min(a.Z, b.Z)) - lateral,
					max = Vector3.new(math.max(a.X, b.X), y1, math.max(a.Z, b.Z)) + lateral,
				}
				for _, S in solids do
					if overlaps(lane, S) then
						fail(string.format("%s: %s is in the way at y=%.0f-%.0f", face, S.part.Name, S.min.Y, S.max.Y))
					end
				end
			end
		end
		-- Climb over the top onto the summit.
		local topExt = faceExtent(climbables, axis, H - 1.5)
		if not topExt then
			fail(face .. ": no wall just below the summit")
		elseif not canMantle(solids, axis, topExt, H) then
			fail(face .. ": no free spot to climb over onto the summit")
		end
	end

	if not peak or math.abs(peak.min.Y - H) > EPS then
		fail(string.format("%s: peak zone should start at the summit (y=%s)", name, tostring(H)))
	end
	if not baseZone or baseZone.min.Y > EPS then
		fail(name .. ": base zone must touch the ground")
	end
	print(string.format("ok   %-16s height %5d  %2d rest levels  %5d parts", name, H, #levels, count))
end

-- Climb simulation: run the client's real WallClimb code up every face of
-- every tower, against ray-cast tower geometry.
local WallClimb = __req("WallClimb")
local islandTop = workspace:FindFirstChild("World"):FindFirstChild("IslandTop")
for _, tower in towers:GetChildren() do
	local H = tower:GetAttribute("Height")
	local towerCF = tower.WorldPivot
	local inv = towerCF:Inverse()
	local parts = { islandTop }
	local climbables = {}
	local clipBars = {}
	for _, part in tower:GetDescendants() do
		if part:IsA("BasePart") and part:HasTag("ClipBar") then
			table.insert(clipBars, part)
		end
		if part:IsA("BasePart") and part.CanQuery ~= false then
			table.insert(parts, part)
			if part:HasTag("Climbable") then
				table.insert(climbables, box(inv, part))
			end
		end
	end
	local isTelecom = tower:GetAttribute("Kind") == "Telecom"
	if isTelecom and #clipBars == 0 then
		fail(tower.Name .. ": telecom tower has no beams to clip a rope to")
	end
	-- Mirrors ClimbController.findClipPoint for telecom towers.
	local function nearestClip(hands)
		local best = math.huge
		for _, bar in clipBars do
			local cf = bar.CFrame
			local look = -cf.b -- a beam's length runs along its look vector
			local half = bar.Size.Z / 2
			local d = math.clamp((hands - cf.p):Dot(look), -half, half)
			best = math.min(best, ((cf.p + look * d) - hands).Magnitude)
		end
		return best
	end
	local world = {
		cast = function(origin, direction)
			return mockRaycast(parts, origin, direction)
		end,
		climbable = function(instance)
			return instance:HasTag("Climbable")
		end,
		solid = function(instance)
			return instance.CanCollide ~= false
		end,
		noStand = function(instance)
			return instance:HasTag("NoStand")
		end,
	}
	local levels = {}
	for value in string.gmatch(tower:GetAttribute("RestLevels") or "", "[^,]+") do
		table.insert(levels, tonumber(value))
	end
	local speed = CC.ClimbSpeed
	local summits, moves = 0, 0
	for run = 0, 11 do
		local fi, startY = run % 4 + 1, 3 + math.floor(run / 4)
		local axis = AXES[fi]
		local face = string.format("%s face %d start y=%d (sim)", tower.Name, fi - 1, startY)
		local ext = faceExtent(climbables, axis, startY)
		local outward = towerCF:PointToWorldSpace(axis) - towerCF.p
		local start = towerCF:PointToWorldSpace(onAxis(axis, ext + 2, startY))
		local firstRun = run < 4
		local anchor, normal = WallClimb.grab(world, CC, start, -outward, CC.GripRange)
		if not anchor then
			fail(face .. ": can't grab the wall from the ground")
			continue
		end
		local closest = {}
		local traversed, leapt, descended = not firstRun, not firstRun, false
		for _ = 1, 3000 do
			for i, y in levels do
				local gap = math.abs(anchor.Y + WallClimb.HAND_HEIGHT - y)
				closest[i] = math.min(closest[i] or math.huge, gap)
			end
			-- Partway up, check that traversing, leaping and down-climbing work.
			if not traversed and anchor.Y > 12 then
				traversed = true
				local right = WallClimb.plan(world, CC, anchor, normal, 0, 1, speed)
				local left = WallClimb.plan(world, CC, anchor, normal, 0, -1, speed)
				if not right or not left then
					fail(face .. string.format(": can't traverse sideways at y=%.0f", anchor.Y))
				end
				local down = WallClimb.plan(world, CC, anchor, normal, -1, 0, speed)
				if not down or down.to.Y >= anchor.Y then
					fail(face .. string.format(": can't climb down at y=%.0f", anchor.Y))
				end
			end
			if not leapt and anchor.Y > H * 0.5 then
				leapt = true
				local leap = WallClimb.planLeap(world, CC, anchor, normal)
				if not leap or leap.to.Y <= anchor.Y + 1 then
					fail(face .. string.format(": can't leap at y=%.0f", anchor.Y))
				end
			end
			if isTelecom and firstRun then
				local reach = nearestClip(anchor + Vector3.new(0, WallClimb.HAND_HEIGHT, 0))
				if reach > Config.Rope.Reach then
					fail(face .. string.format(": no beam to clip the rope to within reach at y=%.0f (nearest %.1f)", anchor.Y, reach))
				end
			end
			local move, action = WallClimb.plan(world, CC, anchor, normal, 1, 0, speed)
			if move then
				anchor = move.to
				moves += 1
				local probe = WallClimb.probe(world, CC, anchor, normal)
				if probe then
					normal = WallClimb.horizontal(probe.Normal)
				end
			elseif action == "mantle" then
				local stand = WallClimb.findMantle(world, CC, anchor, normal)
				if not stand then
					fail(face .. string.format(": stuck under something at y=%.0f, can't climb over", anchor.Y))
				elseif math.abs(stand.Y - (H + WallClimb.ROOT_HEIGHT)) > 0.6 then
					fail(face .. string.format(": climbed onto something at y=%.0f before the summit", stand.Y))
				else
					summits += 1
				end
				break
			else
				fail(face .. string.format(": stuck at y=%.0f (no wall to reach)", anchor.Y))
				break
			end
		end
		for i, y in levels do
			if (closest[i] or math.huge) > CC.RestBarReach then
				fail(face .. string.format(": hands never get within reach of the rest bar at y=%d", y))
			end
		end
		-- And back down from the first few moves: step off at the bottom.
		local low, lowNormal = WallClimb.grab(world, CC, start, -outward, CC.GripRange)
		if low and firstRun then
			for _ = 1, 20 do
				local move, action = WallClimb.plan(world, CC, low, lowNormal, -1, 0, speed)
				if action == "stepoff" then
					descended = true
					break
				elseif move then
					low = move.to
				else
					break
				end
			end
			if not descended then
				fail(face .. ": can't step off at the bottom")
			end
		elseif not low then
			fail(face .. ": can't grab the wall again from the ground")
		end
	end
	print(string.format("sim  %-16s %d/12 climbs reached the summit (4 faces x 3 start heights, %d moves)", tower.Name, summits, moves))
end

-- The spawn plaza and island top must be at ground level (y = 0..0.5), not buried.
local world = workspace:FindFirstChild("World")
for _, name in { "IslandTop", "Plaza", "MainPath", "ShopYard" } do
	local part = world:FindFirstChild(name)
	if not part then
		fail("world is missing " .. name)
	else
		local top = part.CFrame.p.Y + part.Size.Y / 2
		if top < -0.01 or top > 0.6 then
			fail(string.format("%s top is at y=%.2f, expected ground level", name, top))
		end
	end
end
local worldParts = #world:GetDescendants()

print(string.format("%d tower parts, %d world parts, %d failures", totalParts, worldParts, failures))
if failures > 0 then
	error("geometry check failed")
end
