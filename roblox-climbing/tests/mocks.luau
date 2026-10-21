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
