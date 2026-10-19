--[[
	BikePhysics  (ModuleScript, ReplicatedStorage/Shared)

	A small, readable raycast-wheel solver for two-wheelers. It runs on the
	CLIENT that owns the bike (network ownership), every Heartbeat.

	Why not VehicleSeat? A two-wheeler has to lean, wheelie and balance itself.
	VehicleSeat gives you none of that. Here the idea is simple:

	  1. Two invisible wheels (front / rear) raycast down. Each is a spring that
	     holds the chassis at ride height.
	  2. Everything planar (drive, brakes, sideways grip, steering) is applied
	     as plain velocity changes along the ground. Easy to read and tune.
	  3. A "self-righting" controller steers the chassis toward a target up
	     vector: ground normal + lean into the corner + wheelie tilt. The bike
	     can never fall over by itself, which keeps it forgiving.

	The server never trusts this for anything with consequences - money, fuel,
	damage and mission progress are all decided server-side.

	Usage
	  local sim = BikePhysics.new(model, vehicleData)
	  local telemetry = sim:step(input, dt)

	input = {
	  throttle   0..1       (ignored unless engineOn)
	  brake      0..1       front+rear
	  rearBrake  boolean    skids the back wheel
	  steer     -1..1       +1 = right
	  wheelie    boolean
	  engineOn   boolean
	  choke      boolean    (power penalty)
	  push       { pull = Vector3, maxAccel, maxSpeed }?   -- pushing by hand
	  pivot      number?    turn-in-place yaw rate when pushing slowly
	}
]]

local GameConfig = require(script.Parent.GameConfig)
local BikeFactory = require(script.Parent.BikeFactory)

local P = GameConfig.Physics
local STUDS = GameConfig.StudsPerKmh

local BikePhysics = {}
BikePhysics.__index = BikePhysics

local function approach(x: number, target: number, step: number): number
	if x < target then
		return math.min(x + step, target)
	elseif x > target then
		return math.max(x - step, target)
	end
	return x
end

----------------------------------------------------------------------------
-- How hard is it to push this bike by hand? Used by BOTH server (to set the
-- player's walk speed) and client (to size the shove).
-- Heavier bike (and a fuller tank) => lower walk speed + weaker acceleration.
----------------------------------------------------------------------------
function BikePhysics.pushLimits(vehicle, fuelLitres: number?)
	local push = GameConfig.Push
	local kg = vehicle.stats.weightKg + (fuelLitres or 0) * GameConfig.Fuel.LitresToKg
	local fraction = math.clamp(1 - (kg - 40) / 260, push.MinFraction, push.MaxFraction)
	return {
		effectiveKg = kg,
		walkSpeed = push.FreeWalkSpeed * fraction,
		maxAccel = push.Force / kg,
		strain = math.clamp((kg - 60) / 100, 0, 1), -- 0 = light, 1 = heavy (HUD text)
	}
end

----------------------------------------------------------------------------
function BikePhysics.new(model: Model, vehicle)
	local chassis = model.PrimaryPart :: BasePart
	local rp = RaycastParams.new()
	rp.FilterType = Enum.RaycastFilterType.Exclude
	rp.FilterDescendantsInstances = { model }
	rp.IgnoreWater = true

	local self = setmetatable({}, BikePhysics)
	self.model = model
	self.chassis = chassis
	self.vehicle = vehicle
	self.geo = vehicle.geometry
	self.rideHeight = BikeFactory.rideHeight(vehicle.geometry)
	self.rayParams = rp
	self.gear = 1
	self.wheelieAngle = 0
	self.lastForward = chassis.CFrame.LookVector
	-- derived from the readable stat block
	self.topSpeed = vehicle.stats.topSpeedKmh * STUDS
	self.peakAccel = 3.5 + 16 * vehicle.stats.acceleration / 100 -- studs/s^2
	self.brakeAccel = 12 + 48 * vehicle.stats.braking / 100
	self.handling = vehicle.stats.handling / 100
	return self
end

-- Keep the raycasts from hitting characters (rider, pusher, bystanders).
function BikePhysics:setIgnore(instances: { Instance })
	local list = { self.model }
	for _, i in ipairs(instances) do
		table.insert(list, i)
	end
	self.rayParams.FilterDescendantsInstances = list
end

function BikePhysics:shift(direction: number)
	local count = #self.vehicle.drivetrain.gears
	self.gear = math.clamp(self.gear + direction, 1, count)
end

----------------------------------------------------------------------------
function BikePhysics:step(input, dt: number)
	local chassis = self.chassis
	local geo = self.geo
	local vehicle = self.vehicle
	local cf = chassis.CFrame
	local com = chassis.AssemblyCenterOfMass
	local v = chassis.AssemblyLinearVelocity
	local w = chassis.AssemblyAngularVelocity
	local up = cf.UpVector

	----------------------------------------------------------------------
	-- 1. Suspension: two springs along the chassis' own down axis
	----------------------------------------------------------------------
	local rayLen = self.rideHeight + P.SuspensionTravel
	local normalSum = Vector3.zero
	local frontGrounded, rearGrounded = false, false

	for i, z in ipairs({ -geo.wheelbase / 2, geo.wheelbase / 2 }) do
		local origin = cf:PointToWorldSpace(Vector3.new(0, 0, z))
		local hit = workspace:Raycast(origin, -up * rayLen, self.rayParams)
		if hit then
			local n = hit.Normal
			normalSum += n
			if i == 1 then
				frontGrounded = true
			else
				rearGrounded = true
			end
			local compression = self.rideHeight - hit.Distance
			if compression > 0 then
				local arm = hit.Position - com
				local pointVel = v + w:Cross(arm)
				local vn = pointVel:Dot(n)
				-- damper may never remove more than 40% of the velocity per step,
				-- otherwise it overshoots (and explodes) at low frame rates
				local limit = math.abs(vn) / dt * 0.4
				local damping = math.clamp(P.SpringD * vn, -limit, limit)
				local accel = math.clamp(P.SpringK * compression - damping, 0, P.MaxSuspensionAccel)
				local dv = n * (accel * dt)
				v += dv
				w += arm:Cross(dv) / P.GyrationSq
			end
		end
	end

	local grounded = frontGrounded or rearGrounded
	local n = (grounded and normalSum.Magnitude > 0.01) and normalSum.Unit or Vector3.yAxis

	-- forward / right axes lying in the ground plane
	local look = cf.LookVector
	local f = look - n * look:Dot(n)
	if f.Magnitude > 0.1 then
		f = f.Unit
		self.lastForward = f
	else
		f = self.lastForward
	end
	local r = f:Cross(n)

	local vLong = v:Dot(f)
	local vLat = v:Dot(r)
	local speed = math.abs(vLong)

	----------------------------------------------------------------------
	-- 2. Engine, gears, brakes (longitudinal)
	----------------------------------------------------------------------
	local gears = vehicle.drivetrain.gears
	self.gear = math.clamp(self.gear, 1, #gears)
	local gearTop = self.topSpeed * gears[self.gear]
	local ratio = math.max(vLong, 0) / gearTop -- 0..1 = engine rpm fraction
	local pb = vehicle.drivetrain.powerband
	local powerFactor = pb.floor + (1 - pb.floor) * math.exp(-(((ratio - pb.peak) / pb.width) ^ 2))
	if ratio >= 1 then
		powerFactor = 0 -- rev limiter
	elseif ratio > 0.93 then
		powerFactor *= (1 - ratio) / 0.07
	end

	local engineOn = input.engineOn == true
	local throttle = engineOn and math.clamp(input.throttle or 0, 0, 1) or 0
	local chokeMul = input.choke and GameConfig.Fuel.ChokePowerMultiplier or 1
	local driveAccel = throttle * self.peakAccel * powerFactor * chokeMul
	local drag = 0.0006 * vLong * math.abs(vLong)

	local newLong = vLong + (driveAccel - drag) * dt

	if throttle < 0.05 then
		-- engine braking only when the engine is turning; rolling resistance always
		local decel = P.RollingDecel
		if engineOn then
			decel += P.EngineBrake * (1 + self.gear / #gears)
		end
		newLong = approach(newLong, 0, decel * dt)
	end

	local brake = math.clamp(input.brake or 0, 0, 1)
	local brakeFactor = math.clamp(brake + (input.rearBrake and 0.45 or 0), 0, 1)
	if brakeFactor > 0 then
		newLong = approach(newLong, 0, self.brakeAccel * brakeFactor * dt)
	end

	-- Pushing by hand: a limited shove toward where the player's hands are.
	if input.push then
		local pushInfo = input.push
		local targetV = math.clamp(pushInfo.pull:Dot(f) * 3.0, -pushInfo.maxSpeed * 0.5, pushInfo.maxSpeed)
		local a = math.clamp((targetV - vLong) * 6, -pushInfo.maxAccel, pushInfo.maxAccel)
		newLong += a * dt
	end

	----------------------------------------------------------------------
	-- 3. Steering (kinematic bicycle) + lean target
	----------------------------------------------------------------------
	local steer = math.clamp(input.steer or 0, -1, 1)
	local maxSteerAngle = math.rad(28 + 22 * self.handling)
	local steerAngle = steer * maxSteerAngle / (1 + (speed / 28) ^ 2) -- less twitchy when fast
	local yawTarget = -newLong * math.tan(steerAngle) / geo.wheelbase
	if input.pivot and speed < 3 then
		yawTarget += -steer * input.pivot * (1 - speed / 3)
	end

	local leanMax = math.rad(geo.maxLeanDeg)
	local lean = math.clamp(math.atan(newLong * -yawTarget / workspace.Gravity), -leanMax, leanMax)

	----------------------------------------------------------------------
	-- 4. Wheelie (rear grounded, throttle, low gear)
	----------------------------------------------------------------------
	-- Below ~25 deg the rear spring just soaks it up; the front wheel only
	-- lifts for bikes with a high `wheelie` stat (Supermoto easily, Aerox barely).
	local maxWheelie = math.rad(10 + 40 * geo.wheelie)
	local wantWheelie = 0
	if input.wheelie and rearGrounded and throttle > 0.4 and vLong > 3 and self.gear <= 3 then
		wantWheelie = maxWheelie
	end
	local rate = wantWheelie > self.wheelieAngle and P.WheelieUpRate or P.WheelieDownRate
	self.wheelieAngle = approach(self.wheelieAngle, wantWheelie, rate * dt)

	----------------------------------------------------------------------
	-- 5. Apply planar motion (only when a wheel is on the ground)
	----------------------------------------------------------------------
	if grounded then
		v += f * (newLong - vLong)

		local grip = P.GripRate
		if input.rearBrake and brake > 0.5 then
			grip *= 0.45 -- skid: lets the back end step out
		end
		local newLat = vLat * (1 - math.clamp(grip * dt, 0, 1))
		v += r * (newLat - vLat)

		if speed > 0.2 or input.pivot then
			local yawNow = w:Dot(n)
			local response = math.clamp((6 + 8 * self.handling) * dt, 0, 1)
			w += n * ((yawTarget - yawNow) * response)
		end
	end

	----------------------------------------------------------------------
	-- 6. Self-righting: steer the chassis up-vector toward the target
	----------------------------------------------------------------------
	local cl, sl = math.cos(lean), math.sin(lean)
	local cw, sw = math.cos(self.wheelieAngle), math.sin(self.wheelieAngle)
	local desiredUp = ((n * cl + r * sl) * cw - f * sw).Unit
	local target = up:Cross(desiredUp) * P.TiltGain
	if target.Magnitude > P.MaxTiltRate then
		target = target.Unit * P.MaxTiltRate
	end
	local yawPart = n * w:Dot(n)
	local tiltPart = w - yawPart
	tiltPart = tiltPart:Lerp(target, math.clamp((grounded and 25 or 3) * dt, 0, 1))
	w = yawPart + tiltPart
	if w.Magnitude > 14 then
		w = w.Unit * 14
	end

	chassis.AssemblyLinearVelocity = v
	chassis.AssemblyAngularVelocity = w

	return {
		speedKmh = math.abs(newLong) / STUDS,
		forwardSpeed = newLong,
		rpm = engineOn and math.clamp(0.18 + 0.82 * ratio, 0.18, 1) or 0,
		gear = self.gear,
		gearCount = #gears,
		grounded = grounded,
		wheelie = self.wheelieAngle,
		lean = lean,
		skidding = (input.rearBrake and brake > 0.5 and speed > 8) or false,
	}
end

return BikePhysics
