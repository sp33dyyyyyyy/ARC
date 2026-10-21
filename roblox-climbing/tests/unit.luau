-- Unit tests for the pure-data modules, run outside Studio with the Luau CLI:
--     luau tests/unit.luau            (from the roblox-climbing folder)
-- Exits with an error if any test fails.

local HoldTypes = require("../src/shared/HoldTypes")
local Layout = require("../src/server/World/TestWallLayout")
local Holds = Layout.Holds
local RateLimiter = require("../src/shared/RateLimiter")

local passed, failed = 0, 0
local function test(name: string, fn: () -> ())
	local ok, err = pcall(fn)
	if ok then
		passed += 1
		print(`PASS  {name}`)
	else
		failed += 1
		print(`FAIL  {name}\n      {err}`)
	end
end

-- HoldTypes.get with the nil case turned into a test failure.
local function def(name: string): HoldTypes.HoldTypeDef
	return assert(HoldTypes.get(name), `unknown hold type {name}`)
end

local function expect(condition: boolean, message: string?)
	if not condition then
		error(message or "expectation failed", 2)
	end
end

-- HoldTypes ----------------------------------------------------------------

test("HoldTypes has the 8 hold types from the design doc", function()
	for _, name in { "Jug", "Crimp", "Sloper", "Pinch", "Pocket", "Edge", "Foothold", "Crack" } do
		expect(HoldTypes.isValid(name), `missing {name}`)
	end
	expect(#HoldTypes.Names == 8, `expected 8 types, got {#HoldTypes.Names}`)
end)

test("HoldTypes rejects unknown names and nil", function()
	expect(not HoldTypes.isValid("Banana"))
	expect(not HoldTypes.isValid(nil))
	expect(not HoldTypes.isValid(42))
	expect(HoldTypes.get(nil) == nil)
	expect(HoldTypes.isValid(HoldTypes.DEFAULT_TYPE))
end)

test("every hold type has sane numbers and at least one usable limb", function()
	for _, name in HoldTypes.Names do
		local d = def(name)
		expect(d.DefaultQuality >= 0 and d.DefaultQuality <= 1, `{name} DefaultQuality`)
		expect(d.DrainMultiplier > 0, `{name} DrainMultiplier`)
		expect(d.SlipFactor > 0, `{name} SlipFactor`)
		expect(d.HandOK or d.FootOK, `{name} is unusable`)
	end
end)

test("jugs drain least; crimps and slopers drain more than average; footholds are feet-only", function()
	local jug, crimp, sloper, foot = def("Jug"), def("Crimp"), def("Sloper"), def("Foothold")
	for _, name in HoldTypes.Names do
		expect(jug.DrainMultiplier <= def(name).DrainMultiplier, `{name} drains less than Jug`)
	end
	expect(crimp.DrainMultiplier > 1 and sloper.DrainMultiplier > 1)
	expect(sloper.SlipFactor > jug.SlipFactor and crimp.SlipFactor > jug.SlipFactor)
	expect(not foot.HandOK and foot.FootOK)
end)

test("HoldTypes data is frozen", function()
	expect(not pcall(function()
		(HoldTypes :: any).DEFAULT_TYPE = "Jug"
	end))
	expect(not pcall(function()
		(HoldTypes.get("Jug") :: any).DrainMultiplier = 0
	end))
end)

-- Test wall layout ---------------------------------------------------------

test("test wall has exactly 20 holds", function()
	expect(#Holds == 20, `got {#Holds}`)
end)

test("every layout hold has a valid type and quality", function()
	for i, spec in Holds do
		expect(HoldTypes.isValid(spec.type), `hold {i} type {spec.type}`)
		if spec.quality then
			expect(spec.quality >= 0 and spec.quality <= 1, `hold {i} quality`)
		end
	end
end)

test("every hold type appears on the test wall", function()
	local seen = {}
	for _, spec in Holds do
		seen[spec.type] = true
	end
	for _, name in HoldTypes.Names do
		expect(seen[name], `{name} missing`)
	end
end)

test("2 start holds (both hand-OK) and 1 finish hold at the top", function()
	local starts, finish = 0, nil
	local top = -math.huge
	for _, spec in Holds do
		top = math.max(top, spec.y)
		if spec.role == "Start" then
			starts += 1
			expect(def(spec.type).HandOK, "start hold must take hands")
		elseif spec.role == "Finish" then
			expect(finish == nil, "more than one finish")
			finish = spec
		end
	end
	expect(starts == 2, `starts={starts}`)
	expect(finish ~= nil and finish.y == top, "finish must be the highest hold")
end)

test("all holds fit on the wall face", function()
	for i, spec in Holds do
		expect(math.abs(spec.x) <= Layout.Width / 2 - 1, `hold {i} x={spec.x}`)
		expect(spec.y > 0 and spec.y <= Layout.Height - 1, `hold {i} y={spec.y}`)
	end
end)

test(`no move longer than the layout MaxMoveGap ({Layout.MaxMoveGap} studs)`, function()
	for i, a in Holds do
		if a.role ~= "Finish" then
			local best = math.huge
			for j, b in Holds do
				if i ~= j and b.y > a.y + 0.5 then
					best = math.min(best, math.sqrt((b.x - a.x) ^ 2 + (b.y - a.y) ^ 2))
				end
			end
			expect(best <= Layout.MaxMoveGap, `hold {i} next gap {best}`)
		end
	end
end)

test("there are footholds below the start holds", function()
	local startY = math.huge
	for _, spec in Holds do
		if spec.role == "Start" then
			startY = math.min(startY, spec.y)
		end
	end
	local feet = 0
	for _, spec in Holds do
		if spec.y < startY - 1.5 and def(spec.type).FootOK then
			feet += 1
		end
	end
	expect(feet >= 2, `feet={feet}`)
end)


-- RateLimiter ---------------------------------------------------------------

test("RateLimiter allows a burst, then refuses", function()
	local limiter = RateLimiter.new(10, 3)
	for i = 1, 3 do
		expect(limiter:allow("p", 0), `burst request {i}`)
	end
	expect(not limiter:allow("p", 0), "4th in the same instant is refused")
end)

test("RateLimiter refills at its rate and caps at the burst", function()
	local limiter = RateLimiter.new(10, 3)
	for _ = 1, 3 do
		limiter:allow("p", 0)
	end
	expect(not limiter:allow("p", 0.05), "half a token after 0.05 s")
	expect(limiter:allow("p", 0.2), "a token after 0.1 s more")
	-- A long wait refills only up to the burst.
	local allowed = 0
	for _ = 1, 10 do
		if limiter:allow("p", 100) then
			allowed += 1
		end
	end
	expect(allowed == 3, `allowed {allowed} after a long wait`)
end)

test("RateLimiter keys are independent and can be forgotten", function()
	local limiter = RateLimiter.new(1, 1)
	expect(limiter:allow("a", 0) and limiter:allow("b", 0))
	expect(not limiter:allow("a", 0))
	limiter:forget("a")
	expect(limiter:allow("a", 0), "forgotten key starts with a full bucket")
end)

print(`\n{passed} passed, {failed} failed`)
if failed > 0 then
	error("unit tests failed")
end
