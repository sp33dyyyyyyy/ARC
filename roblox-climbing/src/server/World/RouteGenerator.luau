--!strict
-- RouteGenerator: lays out the holds of a route procedurally, so big walls don't need
-- thousands of hand-placed holds. Pure Luau with its own seeded random numbers, so the
-- same seed always gives the same route, and tests/climbing.luau can check that generated
-- routes are climbable.
--
-- Output uses the same hold format as TestWallLayout: x = studs right of the wall's centre
-- line, y = studs up the face from its bottom, plus type / role.
--
-- Shape: pairs of holds every `spacing` studs up a line that drifts sideways (traverses) and
-- meanders. Every pair has something for hands and something for feet, the first pair above
-- 5 studs are the start holds, and a jug near the top is the finish. Harder routes use more
-- crimps and slopers, fewer jugs, and wider spacing. No move is longer than 3.6 studs (the
-- tests check thousands of generated holds).

export type HoldSpec = {
	x: number,
	y: number,
	type: string,
	quality: number?,
	role: string?,
	rotation: number?,
}

export type Params = {
	seed: number,
	height: number, -- studs of face to cover
	lineX: number, -- where the line starts (studs right of the wall centre)
	drift: number?, -- studs the line moves sideways over the whole height (traverses)
	wander: number?, -- amplitude of the gentle side-to-side meander
	difficulty: number?, -- 0 (jugs everywhere) .. 1 (crimps and slopers)
	skip: { { number } }?, -- {from, to} heights with no holds (ledges); holds hug both sides
	startY: number?, -- lowest footholds (default 1.6, above a crash mat)
}

local RouteGenerator = {}

-- Park-Miller random numbers: exact in doubles, identical in Studio and the Luau CLI.
local function random(seed: number): () -> number
	local state = math.floor(math.abs(seed)) % 2147483646 + 1
	return function(): number
		state = (state * 16807) % 2147483647
		return (state - 1) / 2147483646
	end
end

local HAND_ONLY = { Pinch = true }
local FOOT_ONLY = { Foothold = true }

local function weights(difficulty: number): { { any } }
	local d = math.clamp(difficulty, 0, 1)
	return {
		{ "Jug", 0.30 - 0.22 * d },
		{ "Edge", 0.25 },
		{ "Crimp", 0.10 + 0.18 * d },
		{ "Sloper", 0.06 + 0.10 * d },
		{ "Pocket", 0.08 },
		{ "Pinch", 0.07 + 0.04 * d },
		{ "Foothold", 0.14 },
	}
end

local function pick(rand: () -> number, table_: { { any } }): string
	local total = 0
	for _, entry in table_ do
		total += entry[2]
	end
	local r = rand() * total
	for _, entry in table_ do
		r -= entry[2]
		if r <= 0 then
			return entry[1]
		end
	end
	return table_[1][1]
end

local function bandAt(y: number, skip: { { number } }): { number }?
	for _, band in skip do
		if y >= band[1] and y <= band[2] then
			return band
		end
	end
	return nil
end

-- Spacing between hold pairs for a difficulty (2.0 easy .. 2.5 hard).
function RouteGenerator.spacing(difficulty: number): number
	return 2.0 + 0.5 * math.clamp(difficulty, 0, 1)
end

function RouteGenerator.generate(params: Params): { HoldSpec }
	local rand = random(params.seed)
	local difficulty = params.difficulty or 0.3
	local drift = params.drift or 0
	local wander = params.wander or 1.2
	local skip = params.skip or {}
	local spacing = RouteGenerator.spacing(difficulty)
	local table_ = weights(difficulty)
	local phase = rand() * 10
	local topY = params.height - 1.4

	local function centre(y: number): number
		return params.lineX + drift * (y / params.height) + wander * math.sin(y / 7 + phase)
	end

	local holds: { HoldSpec } = {}
	local started = false
	local side = if rand() < 0.5 then -1 else 1
	local y = params.startY or 1.6
	local lastY = y
	local below: { [{ number }]: boolean } = {}
	while y <= topY - spacing do
		-- A pair that would land on a ledge goes just under it instead (unless that crowds
		-- the last pair), and the next one just over it, so no move gets any longer.
		local band = bandAt(y, skip)
		if band then
			if not below[band] and band[1] - 0.05 - lastY >= 0.8 then
				y = band[1] - 0.05
			else
				y = band[2] + 0.05
			end
			below[band] = true
		end
		if bandAt(y, skip) == nil and y <= topY - spacing then
			lastY = y
			local c = centre(y)
			local spread = 1.1 + rand() * 0.8
			local a = pick(rand, table_)
			local b = pick(rand, table_)
			-- Every pair needs something for hands and something for feet.
			if FOOT_ONLY[a] and FOOT_ONLY[b] then
				b = "Edge"
			end
			if HAND_ONLY[a] and HAND_ONLY[b] then
				b = "Edge"
			end
			local role: string? = nil
			if not started and y >= 5 then
				-- Start holds: both must take hands, and be friendly.
				started = true
				role = "Start"
				a = if difficulty < 0.5 then "Jug" else "Edge"
				b = a
			end
			local stagger = (rand() - 0.5) * 0.5
			table.insert(holds, { x = c + side * spread, y = y + stagger, type = a, role = role, rotation = (rand() - 0.5) * 30 })
			table.insert(holds, { x = c - side * spread, y = y - stagger, type = b, role = role, rotation = (rand() - 0.5) * 30 })
			side = -side
		end
		y += spacing
	end
	-- The finish is one normal move above the last pair (never a long reach).
	local finishY = lastY + spacing
	table.insert(holds, { x = centre(finishY), y = finishY, type = "Jug", role = "Finish" })
	return holds
end

return table.freeze(RouteGenerator)
