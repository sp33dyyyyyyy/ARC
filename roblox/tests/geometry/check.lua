-- Runs the real WorldBuilder against the mock and verifies every tower can be
-- climbed Hand-over-Hand, mirroring the client's rules:
--   * skyscrapers: every face has climbable glass from the ground to the summit
--   * telecom towers: no invisible climbable walls at all - only the real
--     members (tagged ClimbHold), which the lattice sim climbs
--   * nothing solid is in the climbing lane anywhere (no leftover platforms)
--   * rest bars on every face at every rest level, non-colliding, matching
--     the RestLevels attribute the client reads
--   * every face can climb over the top onto the summit (ray-style mantle)
--   * zones and attributes line up with the geometry
-- (Bundled after mock.lua and the game modules by run_geometry.py.)

local Config = __req("Config")
local Lattice = __req("Lattice")
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

	local isTelecom = tower:GetAttribute("Kind") == "Telecom"
	if isTelecom and #climbables > 0 then
		fail(name .. ": telecom towers must only be climbable on their real members, not a Climbable surface")
	end
	for fi, axis in AXES do
		if isTelecom then
			break -- lattice coverage is checked by the lattice sim below
		end
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
		-- The client's climbing rays skip non-colliding parts (RespectCanCollide).
		if part:IsA("BasePart") and part.CanQuery ~= false and part.CanCollide ~= false then
			table.insert(parts, part)
			if part:HasTag("Climbable") then
				table.insert(climbables, box(inv, part))
			end
		end
	end
	local isTelecom = tower:GetAttribute("Kind") == "Telecom"
	local segments, barSegments = {}, {}
	for _, part in tower:GetDescendants() do
		if part:IsA("BasePart") and part:HasTag("ClimbHold") then
			table.insert(segments, Lattice.segment(part))
		end
	end
	for _, bar in clipBars do
		table.insert(barSegments, Lattice.segment(bar))
	end
	if isTelecom and #clipBars == 0 then
		fail(tower.Name .. ": telecom tower has no beams to clip a rope to")
	end
	-- Mirrors ClimbController.findClipPoint for telecom towers, then checks
	-- RopeService's validation (same Lattice maths) accepts the point.
	local function nearestClip(hands)
		local q = Lattice.nearest(barSegments, hands, Config.Rope.Reach)
		if not q then
			return math.huge
		end
		if not Lattice.nearest(barSegments, q, 1) then
			fail(tower.Name .. ": the server would reject the client's clip point")
		end
		return (q - hands).Magnitude
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
		holds = function()
			return segments
		end,
		faceNormal = function(point)
			return Lattice.faceNormal(towerCF, point)
		end,
	}
	-- The client picks surface or lattice climbing by tower kind.
	local function plan(anchor, normal, vert, lat)
		if isTelecom then
			return WallClimb.latticePlan(world, CC, anchor, normal, vert, lat, CC.ClimbSpeed)
		end
		return WallClimb.plan(world, CC, anchor, normal, vert, lat, CC.ClimbSpeed)
	end
	local function grabFrom(start, dir)
		if isTelecom then
			return WallClimb.latticeGrab(world, CC, start, dir, CC.AutoGripRange)
		end
		return WallClimb.grab(world, CC, start, dir, CC.GripRange)
	end
	local function afterMove(anchor, normal)
		if isTelecom then
			return Lattice.faceNormal(towerCF, anchor)
		end
		local probe = WallClimb.probe(world, CC, anchor, normal)
		return if probe then WallClimb.horizontal(probe.Normal) else normal
	end
	-- How far a face's outer members are from the centre at height y.
	local function latticeExtent(axis, y)
		local best = nil
		for _, seg in segments do
			local dy = seg.b.Y - seg.a.Y
			if math.abs(dy) > 1e-6 and y >= seg.minY and y <= seg.maxY then
				local p = seg.a + (seg.b - seg.a) * ((y - seg.a.Y) / dy)
				local e = (inv * p):Dot(axis)
				best = if best then math.max(best, e) else e
			end
		end
		return best
	end
	local levels = {}
	for value in string.gmatch(tower:GetAttribute("RestLevels") or "", "[^,]+") do
		table.insert(levels, tonumber(value))
	end
	local summits, moves = 0, 0
	for run = 0, 11 do
		local fi, k = run % 4 + 1, math.floor(run / 4)
		local axis = AXES[fi]
		local outward = towerCF:PointToWorldSpace(axis) - towerCF.p
		local start, face
		if isTelecom then
			-- Walk up to the face at three spots: the middle, halfway out, and
			-- right next to a leg.
			local ext = latticeExtent(axis, 3)
			if not ext then
				fail(string.format("%s face %d: no members at the bottom", tower.Name, fi - 1))
				continue
			end
			local side = Vector3.new(-axis.Z, 0, axis.X) * ({ 0, 0.5 * ext, -(ext - 1) })[k + 1]
			start = towerCF:PointToWorldSpace(onAxis(axis, ext + 1.2, 3) + side)
			face = string.format("%s face %d lateral %d (sim)", tower.Name, fi - 1, k)
		else
			local startY = 3 + k
			local ext = faceExtent(climbables, axis, startY)
			start = towerCF:PointToWorldSpace(onAxis(axis, ext + 2, startY))
			face = string.format("%s face %d start y=%d (sim)", tower.Name, fi - 1, startY)
		end
		local firstRun = run < 4
		local anchor, normal = grabFrom(start, -outward)
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
				local right = plan(anchor, normal, 0, 1)
				local left = plan(anchor, normal, 0, -1)
				if not right or not left then
					fail(face .. string.format(": can't traverse sideways at y=%.0f", anchor.Y))
				end
				if isTelecom then
					-- Traverse right all the way round a corner onto the next face.
					local a, n, turned = anchor, normal, false
					for _ = 1, 80 do
						local m = plan(a, n, 0, 1)
						if not m then
							fail(face .. string.format(": traverse got stuck at y=%.0f", a.Y))
							break
						end
						a = m.to
						local n2 = afterMove(a, n)
						if n2:Dot(normal) < 0.5 then
							turned = true
							break
						end
						n = n2
					end
					if not turned then
						fail(face .. ": traversing never reached the next face round the corner")
					end
				end
				local down = plan(anchor, normal, -1, 0)
				if not down or down.to.Y >= anchor.Y then
					fail(face .. string.format(": can't climb down at y=%.0f", anchor.Y))
				end
			end
			if not leapt and anchor.Y > H * 0.5 then
				leapt = true
				local leap = if isTelecom
					then WallClimb.latticeLeap(world, CC, anchor, normal)
					else WallClimb.planLeap(world, CC, anchor, normal)
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
			local move, action = plan(anchor, normal, 1, 0)
			if move then
				if isTelecom then
					-- Hands are always on a real member.
					local hand = WallClimb.handFor(CC, move.to, Lattice.faceNormal(towerCF, move.to))
					if not Lattice.nearest(segments, hand, 0.05) then
						fail(face .. string.format(": hands not on a beam at y=%.0f", hand.Y))
					end
				end
				anchor = move.to
				moves += 1
				normal = afterMove(anchor, normal)
			elseif action == "mantle" then
				local stand = WallClimb.findMantle(world, CC, anchor, normal)
				if not stand then
					fail(face .. string.format(": stuck under something at y=%.0f, can't climb over", anchor.Y))
				elseif math.abs(stand.Y - (H + WallClimb.ROOT_HEIGHT)) > 0.6 then
					fail(face .. string.format(": climbed onto something at y=%.0f before the summit", stand.Y))
				else
					summits += 1
					if isTelecom and firstRun then
						-- Rappel Kit: slide all the way down the lattice.
						local a, n, ok = anchor, normal, true
						while a.Y > WallClimb.ROOT_HEIGHT + 2 do
							local nextPos = WallClimb.latticeSlide(world, CC, a, n, Config.Rope.RappelSpeed / 60)
							if not nextPos or nextPos.Y >= a.Y then
								fail(face .. string.format(": rappel stopped at y=%.0f", a.Y))
								ok = false
								break
							end
							a = nextPos
							n = Lattice.faceNormal(towerCF, a)
						end
						if ok and (a - anchor).Magnitude < H * 0.9 then
							fail(face .. ": rappel didn't get down")
						end
					end
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
		local low, lowNormal = grabFrom(start, -outward)
		if low and firstRun then
			for _ = 1, 20 do
				local move, action = plan(low, lowNormal, -1, 0)
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
	print(string.format(
		"sim  %-16s %d/12 climbs reached the summit (4 faces x 3 %s, %d moves)",
		tower.Name,
		summits,
		if isTelecom then "spots, on the lattice" else "start heights",
		moves
	))
	if summits ~= 12 then
		fail(tower.Name .. ": not every simulated climb reached the summit")
	end
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

-- The loading screen reads these: progress must finish at 100% and "ready".
if workspace:GetAttribute("WorldReady") ~= true or workspace:GetAttribute("LoadProgress") ~= 1 then
	fail("world build didn't report WorldReady / LoadProgress = 1 for the loading screen")
end

print(string.format("%d tower parts, %d world parts, %d failures", totalParts, worldParts, failures))
if failures > 0 then
	error("geometry check failed")
end
