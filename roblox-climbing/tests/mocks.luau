-- Minimal stand-ins for the Roblox types the shared climbing modules use, so tests/run.py
-- can run the real module code with the Luau CLI. Only what the modules need.

local Vector3 = {}
local V3 = {}

local function v3(x: number, y: number, z: number): any
	return setmetatable({ X = x, Y = y, Z = z }, V3)
end

V3.__add = function(a, b)
	return v3(a.X + b.X, a.Y + b.Y, a.Z + b.Z)
end
V3.__sub = function(a, b)
	return v3(a.X - b.X, a.Y - b.Y, a.Z - b.Z)
end
V3.__mul = function(a, b)
	if type(a) == "number" then
		return v3(b.X * a, b.Y * a, b.Z * a)
	end
	return v3(a.X * b, a.Y * b, a.Z * b)
end
V3.__div = function(a, k)
	return v3(a.X / k, a.Y / k, a.Z / k)
end
V3.__unm = function(a)
	return v3(-a.X, -a.Y, -a.Z)
end
V3.__eq = function(a, b)
	return a.X == b.X and a.Y == b.Y and a.Z == b.Z
end
V3.__tostring = function(a)
	return string.format("(%.3f, %.3f, %.3f)", a.X, a.Y, a.Z)
end
V3.__index = function(a, key)
	if key == "Magnitude" then
		return math.sqrt(a.X * a.X + a.Y * a.Y + a.Z * a.Z)
	elseif key == "Unit" then
		local m = math.sqrt(a.X * a.X + a.Y * a.Y + a.Z * a.Z)
		return v3(a.X / m, a.Y / m, a.Z / m)
	elseif key == "Dot" then
		return function(self, b)
			return self.X * b.X + self.Y * b.Y + self.Z * b.Z
		end
	elseif key == "Cross" then
		return function(self, b)
			return v3(self.Y * b.Z - self.Z * b.Y, self.Z * b.X - self.X * b.Z, self.X * b.Y - self.Y * b.X)
		end
	elseif key == "Lerp" then
		return function(self, b, t)
			return self + (b - self) * t
		end
	end
	return nil
end

Vector3.new = function(x: number?, y: number?, z: number?)
	return v3(x or 0, y or 0, z or 0)
end
Vector3.zero = v3(0, 0, 0)
Vector3.xAxis = v3(1, 0, 0)
Vector3.yAxis = v3(0, 1, 0)
Vector3.zAxis = v3(0, 0, 1)

local Vector2 = {}
local V2 = {}
local function v2(x: number, y: number): any
	return setmetatable({ X = x, Y = y }, V2)
end
V2.__add = function(a, b)
	return v2(a.X + b.X, a.Y + b.Y)
end
V2.__sub = function(a, b)
	return v2(a.X - b.X, a.Y - b.Y)
end
V2.__eq = function(a, b)
	return a.X == b.X and a.Y == b.Y
end
V2.__tostring = function(a)
	return string.format("(%.3f, %.3f)", a.X, a.Y)
end
V2.__index = function(a, key)
	if key == "Magnitude" then
		return math.sqrt(a.X * a.X + a.Y * a.Y)
	elseif key == "Unit" then
		local m = math.sqrt(a.X * a.X + a.Y * a.Y)
		return v2(a.X / m, a.Y / m)
	end
	return nil
end
Vector2.new = function(x: number?, y: number?)
	return v2(x or 0, y or 0)
end
Vector2.zero = v2(0, 0)

local Color3 = {
	fromRGB = function(r, g, b)
		return { R = r / 255, G = g / 255, B = b / 255 }
	end,
	new = function(r, g, b)
		return { R = r, G = g, B = b }
	end,
}

local function enumStub(path: string): any
	return setmetatable({}, {
		__index = function(_, key)
			return enumStub(`{path}.{key}`)
		end,
		__tostring = function()
			return path
		end,
	})
end
local Enum = enumStub("Enum")

-- CFrame: position + 3x3 rotation (rows), enough for LimbRig's maths.
local CFrame = {}
local CF = {}
local function cf(p: any, r: { number }): any
	return setmetatable({ p = p, r = r }, CF)
end
local function rot(r: { number }, v: any): any
	return Vector3.new(r[1] * v.X + r[2] * v.Y + r[3] * v.Z, r[4] * v.X + r[5] * v.Y + r[6] * v.Z, r[7] * v.X + r[8] * v.Y + r[9] * v.Z)
end
local function transpose(r: { number }): { number }
	return { r[1], r[4], r[7], r[2], r[5], r[8], r[3], r[6], r[9] }
end
local function matmul(a: { number }, b: { number }): { number }
	local out = {}
	for i = 0, 2 do
		for j = 1, 3 do
			out[i * 3 + j] = a[i * 3 + 1] * b[j] + a[i * 3 + 2] * b[3 + j] + a[i * 3 + 3] * b[6 + j]
		end
	end
	return out
end
CF.__mul = function(a, b)
	if getmetatable(b) == CF then
		return cf(a.p + rot(a.r, b.p), matmul(a.r, b.r))
	end
	return a.p + rot(a.r, b)
end
CF.__index = function(c, key)
	if key == "Position" then
		return c.p
	elseif key == "Inverse" then
		return function(self)
			local t = transpose(self.r)
			return cf(-rot(t, self.p), t)
		end
	elseif key == "VectorToWorldSpace" then
		return function(self, v)
			return rot(self.r, v)
		end
	elseif key == "VectorToObjectSpace" then
		return function(self, v)
			return rot(transpose(self.r), v)
		end
	end
	return nil
end
CFrame.new = function(x: number?, y: number?, z: number?, ...: number)
	local r = { ... }
	if #r ~= 9 then
		r = { 1, 0, 0, 0, 1, 0, 0, 0, 1 }
	end
	return cf(Vector3.new(x or 0, y or 0, z or 0), r)
end
CFrame.identity = CFrame.new()
CFrame.fromAxisAngle = function(axis: any, angle: number)
	local u = axis.Unit
	local c, s, t = math.cos(angle), math.sin(angle), 1 - math.cos(angle)
	local x, y, z = u.X, u.Y, u.Z
	return cf(Vector3.zero, {
		t * x * x + c, t * x * y - s * z, t * x * z + s * y,
		t * x * y + s * z, t * y * y + c, t * y * z - s * x,
		t * x * z - s * y, t * y * z + s * x, t * z * z + c,
	})
end
