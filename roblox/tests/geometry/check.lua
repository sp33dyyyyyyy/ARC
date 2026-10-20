-- Runs the real WorldBuilder against the mock and verifies every tower can be
-- climbed with Grip & Lunge, mirroring the client's rules:
--   * every face has climbable surface from the ground to the summit
--   * every rest platform/balcony sticks out far enough to stop a climber
--     (who hangs WallOffset studs off the wall) so they mantle onto it
--   * at every rest level and at the summit there's a free spot to mantle onto,
--     found the same way the client searches (offsets 0, 1.5, 3, 4.5 inward)
--   * nothing solid blocks the middle of each face between rests
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

-- Client mantle search: first offset with a non-climbable floor at `floorY`
-- under it and a free 2x4.6x2 box to stand in.
local function canMantle(solids, climbables, axis, ext, floorY)
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
			local stand = boxAt(onAxis(axis, d, floorY + 3 + 0.3), Vector3.new(2, 4.6, 2))
			local free = true
			for _, S in solids do
				if overlaps(stand, S) then
					free = false
				end
			end
			for _, C in climbables do
				if overlaps(stand, C) then
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
	local climbables, solids, rests = {}, {}, {}
	local peak, baseZone
	local count = 0
	for _, part in tower:GetDescendants() do
		if part:IsA("BasePart") then
			count += 1
			local b = box(inv, part)
			if part.ClassName == "TrussPart" then
				fail(name .. ": still has a ladder")
			elseif part:HasTag("Climbable") then
				table.insert(climbables, b)
			elseif part.Name == "PeakZone" then
				peak = b
			elseif part.Name == "BaseZone" then
				baseZone = b
			elseif part.CanCollide ~= false then
				table.insert(solids, b)
				if part:GetAttribute("Checkpoint") then
					table.insert(rests, b)
				end
			end
		end
	end
	totalParts += count

	-- Rest levels, bottom to top.
	local levels = {}
	for _, r in rests do
		local y = math.round(r.max.Y * 100) / 100
		if not table.find(levels, y) then
			table.insert(levels, y)
		end
	end
	table.sort(levels)
	if #levels == 0 or math.abs(levels[#levels] - H) > EPS then
		fail(string.format("%s: summit rest surface should be at the Height attribute %s", name, tostring(H)))
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

		local prev = 0
		for _, ly in levels do
			local ext = faceExtent(climbables, axis, ly - 1.5)
			if not ext then
				fail(string.format("%s: no wall just below the rest at y=%.1f", face, ly))
				continue
			end
			-- Something overhead must stop the climber (except at a wall-top summit,
			-- where the client mantles over the top instead).
			local head = boxAt(onAxis(axis, ext + CC.WallOffset, ly - 0.5), Vector3.new(1, 1, 1))
			local blocked = false
			for _, S in solids do
				if overlaps(head, S) then
					blocked = true
				end
			end
			local wallEndsHere = faceExtent(climbables, axis, ly + 3) == nil
			if not blocked and not wallEndsHere then
				fail(string.format("%s: rest at y=%.1f doesn't stick out past the climber, they'd climb straight past it", face, ly))
			end
			if not canMantle(solids, climbables, axis, ext, ly) then
				fail(string.format("%s: no free spot to mantle onto at y=%.1f", face, ly))
			end

			-- Corridor in the middle of the face between rests must be clear.
			local lo, hi = prev + 1.5, ly - 2.5
			if hi > lo then
				local mid = (lo + hi) / 2
				local extMid = faceExtent(climbables, axis, mid) or ext
				local d0, d1 = extMid + 0.6, extMid + 2.6
				local a = onAxis(axis, d0, lo)
				local b = onAxis(axis, d1, hi)
				local lateral = if math.abs(axis.X) > 0.5 then Vector3.new(0, 0, 1.5) else Vector3.new(1.5, 0, 0)
				local corridor = {
					min = Vector3.new(math.min(a.X, b.X), lo, math.min(a.Z, b.Z)) - lateral,
					max = Vector3.new(math.max(a.X, b.X), hi, math.max(a.Z, b.Z)) + lateral,
				}
				for _, S in solids do
					if overlaps(corridor, S) then
						fail(string.format("%s: %s blocks the climb between y=%.0f and y=%.0f", face, S.part.Name, lo, hi))
					end
				end
			end
			prev = ly
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
