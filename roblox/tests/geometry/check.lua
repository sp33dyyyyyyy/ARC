-- Runs the real WorldBuilder against the mock and verifies every ladder is
-- climbable: solid footing, a clear climbing corridor, a flush arrival
-- platform with headroom, and a peak zone over the summit.
-- (Bundled after mock.lua and the game modules by run_geometry.py.)

local WorldBuilder = __req("WorldBuilder")
local _, towers = WorldBuilder.build()

local EPS = 0.05
local failures = 0
local function fail(msg)
	failures += 1
	print("FAIL " .. msg)
end

local function box(inv, part)
	local c = inv * part.CFrame
	local s = part.Size / 2
	local hx = math.abs(c.r.X) * s.X + math.abs(c.u.X) * s.Y + math.abs(c.b.X) * s.Z
	local hy = math.abs(c.r.Y) * s.X + math.abs(c.u.Y) * s.Y + math.abs(c.b.Y) * s.Z
	local hz = math.abs(c.r.Z) * s.X + math.abs(c.u.Z) * s.Y + math.abs(c.b.Z) * s.Z
	local p = c.p
	return { min = Vector3.new(p.X - hx, p.Y - hy, p.Z - hz), max = Vector3.new(p.X + hx, p.Y + hy, p.Z + hz), part = part }
end

local function overlaps(a, b)
	return a.min.X < b.max.X - 0.01 and a.max.X > b.min.X + 0.01
		and a.min.Y < b.max.Y - 0.01 and a.max.Y > b.min.Y + 0.01
		and a.min.Z < b.max.Z - 0.01 and a.max.Z > b.min.Z + 0.01
end

local function containsXZ(b, x, z)
	return x >= b.min.X - EPS and x <= b.max.X + EPS and z >= b.min.Z - EPS and z <= b.max.Z + EPS
end

local function gapXZ(a, b)
	local dx = math.max(0, a.min.X - b.max.X, b.min.X - a.max.X)
	local dz = math.max(0, a.min.Z - b.max.Z, b.min.Z - a.max.Z)
	return math.max(dx, dz)
end

local totalParts = 0
for _, tower in towers:GetChildren() do
	local name = tower.Name
	local inv = tower.WorldPivot:Inverse()
	local ladders, solids = {}, {}
	local peak, baseZone
	local count = 0
	for _, part in tower:GetDescendants() do
		if part:IsA("BasePart") then
			count += 1
			local b = box(inv, part)
			if part.ClassName == "TrussPart" then
				table.insert(ladders, b)
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

	local summitY = 0
	for i, L in ladders do
		local id = string.format("%s ladder %d", name, i)
		local cx, cz = (L.min.X + L.max.X) / 2, (L.min.Z + L.max.Z) / 2
		-- Outward direction: dominant horizontal axis away from the tower centre.
		local alongX = math.abs(cx) > math.abs(cz)
		local sign = if alongX then (if cx > 0 then 1 else -1) else (if cz > 0 then 1 else -1)
		local outer = if alongX then (if sign > 0 then L.max.X else L.min.X) else (if sign > 0 then L.max.Z else L.min.Z)
		summitY = math.max(summitY, L.max.Y)

		-- Corridor where the climber's body goes: 2 studs outside the ladder.
		local corridor
		if alongX then
			local x0, x1 = outer, outer + 2 * sign
			corridor = {
				min = Vector3.new(math.min(x0, x1), L.min.Y + 0.2, L.min.Z),
				max = Vector3.new(math.max(x0, x1), L.max.Y - EPS, L.max.Z),
			}
		else
			local z0, z1 = outer, outer + 2 * sign
			corridor = {
				min = Vector3.new(L.min.X, L.min.Y + 0.2, math.min(z0, z1)),
				max = Vector3.new(L.max.X, L.max.Y - EPS, math.max(z0, z1)),
			}
		end
		for _, S in solids do
			if overlaps(corridor, S) then
				fail(string.format("%s: climbing corridor blocked by %s at y=%.1f..%.1f", id, S.part.Name, S.min.Y, S.max.Y))
			end
		end

		-- Footing: ground or a solid top surface under the standing spot.
		local standX = if alongX then outer + 1.0 * sign else cx
		local standZ = if alongX then cz else outer + 1.0 * sign
		if L.min.Y > EPS then
			local footed = false
			for _, S in solids do
				if math.abs(S.max.Y - L.min.Y) < EPS and containsXZ(S, standX, standZ) and containsXZ(S, cx, cz) then
					footed = true
				end
			end
			if not footed then
				fail(string.format("%s: nothing to stand on at the bottom (y=%.1f)", id, L.min.Y))
			end
		end

		-- Arrival: a solid surface flush with the ladder top, right next to it.
		local arrival = false
		for _, S in solids do
			if math.abs(S.max.Y - L.max.Y) < EPS and gapXZ(S, L) <= 0.6 and S.min.Y < L.max.Y - 0.2 then
				arrival = true
			end
		end
		if not arrival then
			fail(string.format("%s: no platform flush with the ladder top (y=%.1f)", id, L.max.Y))
		end

		-- Headroom above the ladder top for climbing over.
		local head = { min = Vector3.new(L.min.X, L.max.Y + 0.05, L.min.Z), max = Vector3.new(L.max.X, L.max.Y + 5, L.max.Z) }
		for _, S in solids do
			if overlaps(head, S) then
				fail(string.format("%s: no headroom at the top, %s is in the way", id, S.part.Name))
			end
		end
	end

	if #ladders == 0 then
		fail(name .. ": no ladders")
	end
	if not peak or math.abs(peak.min.Y - summitY) > EPS then
		fail(string.format("%s: peak zone should start at the summit (y=%.1f)", name, summitY))
	end
	if not baseZone or baseZone.min.Y > EPS then
		fail(name .. ": base zone must touch the ground")
	end
	if math.abs(summitY - (tower:GetAttribute("Height") or -1)) > EPS then
		fail(string.format("%s: Height attribute %s but top ladder ends at %s", name, tostring(tower:GetAttribute("Height")), tostring(summitY)))
	end
	print(string.format("ok   %-15s %3d ladders  height %4d  %5d parts", name, #ladders, math.round(summitY), count))
end

print(string.format("%d tower parts total, %d failures", totalParts, failures))
if failures > 0 then
	error("geometry check failed")
end
