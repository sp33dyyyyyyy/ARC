-- Minimal Roblox API mock: just enough of Vector3 / CFrame / Instance for the
-- world and tower builders to run in plain Luau.

local function v3(x, y, z)
	return setmetatable({ X = x or 0, Y = y or 0, Z = z or 0 }, Vector3Meta)
end

Vector3Meta = {}
Vector3Meta.__add = function(a, b)
	return v3(a.X + b.X, a.Y + b.Y, a.Z + b.Z)
end
Vector3Meta.__sub = function(a, b)
	return v3(a.X - b.X, a.Y - b.Y, a.Z - b.Z)
end
Vector3Meta.__unm = function(a)
	return v3(-a.X, -a.Y, -a.Z)
end
Vector3Meta.__mul = function(a, b)
	if type(a) == "number" then
		return v3(b.X * a, b.Y * a, b.Z * a)
	elseif type(b) == "number" then
		return v3(a.X * b, a.Y * b, a.Z * b)
	end
	return v3(a.X * b.X, a.Y * b.Y, a.Z * b.Z)
end
Vector3Meta.__div = function(a, b)
	return v3(a.X / b, a.Y / b, a.Z / b)
end
Vector3Meta.__eq = function(a, b)
	return a.X == b.X and a.Y == b.Y and a.Z == b.Z
end
Vector3Meta.__index = function(self, key)
	if key == "Magnitude" then
		return math.sqrt(self.X ^ 2 + self.Y ^ 2 + self.Z ^ 2)
	elseif key == "Unit" then
		local m = math.sqrt(self.X ^ 2 + self.Y ^ 2 + self.Z ^ 2)
		return v3(self.X / m, self.Y / m, self.Z / m)
	elseif key == "Cross" then
		return function(a, b)
			return v3(a.Y * b.Z - a.Z * b.Y, a.Z * b.X - a.X * b.Z, a.X * b.Y - a.Y * b.X)
		end
	elseif key == "Dot" then
		return function(a, b)
			return a.X * b.X + a.Y * b.Y + a.Z * b.Z
		end
	end
	return nil
end

Vector3 = {
	new = v3,
	zero = v3(0, 0, 0),
	one = v3(1, 1, 1),
	xAxis = v3(1, 0, 0),
	yAxis = v3(0, 1, 0),
	zAxis = v3(0, 0, 1),
}

-- CFrame: position p and rotation columns r (X), u (Y), b (Z).
CFrameMeta = {}
local function cf(p, r, u, b)
	return setmetatable({ p = p, r = r, u = u, b = b }, CFrameMeta)
end
local function rot(c, v)
	return c.r * v.X + c.u * v.Y + c.b * v.Z
end
CFrameMeta.__mul = function(a, b)
	if getmetatable(b) == Vector3Meta then
		return a.p + rot(a, b)
	end
	return cf(a.p + rot(a, b.p), rot(a, b.r), rot(a, b.u), rot(a, b.b))
end
CFrameMeta.__add = function(a, v)
	return cf(a.p + v, a.r, a.u, a.b)
end
CFrameMeta.__index = function(self, key)
	if key == "Position" then
		return self.p
	elseif key == "PointToWorldSpace" then
		return function(c, v)
			return c.p + rot(c, v)
		end
	elseif key == "Inverse" then
		return function(c)
			-- transpose of the rotation
			local r = v3(c.r.X, c.u.X, c.b.X)
			local u = v3(c.r.Y, c.u.Y, c.b.Y)
			local b = v3(c.r.Z, c.u.Z, c.b.Z)
			local inv = cf(v3(), r, u, b)
			return cf(-rot(inv, c.p), r, u, b)
		end
	end
	return nil
end

CFrame = {}
function CFrame.new(x, y, z)
	if type(x) == "table" then
		return cf(x, Vector3.xAxis, Vector3.yAxis, Vector3.zAxis)
	end
	return cf(v3(x, y, z), Vector3.xAxis, Vector3.yAxis, Vector3.zAxis)
end
function CFrame.fromMatrix(pos, vX, vY, vZ)
	return cf(pos, vX, vY, vZ or vX:Cross(vY).Unit)
end
function CFrame.lookAt(pos, target, up)
	up = up or Vector3.yAxis
	local look = (target - pos).Unit
	local right = look:Cross(up).Unit
	local upv = right:Cross(look)
	return cf(pos, right, upv, -look)
end
function CFrame.Angles(rx, ry, rz)
	local function rX(a)
		return cf(v3(), v3(1, 0, 0), v3(0, math.cos(a), math.sin(a)), v3(0, -math.sin(a), math.cos(a)))
	end
	local function rY(a)
		return cf(v3(), v3(math.cos(a), 0, -math.sin(a)), v3(0, 1, 0), v3(math.sin(a), 0, math.cos(a)))
	end
	local function rZ(a)
		return cf(v3(), v3(math.cos(a), math.sin(a), 0), v3(-math.sin(a), math.cos(a), 0), v3(0, 0, 1))
	end
	return rX(rx) * rY(ry) * rZ(rz)
end

local Color3Meta = {}
Color3Meta.__index = {
	Lerp = function(a, b, t)
		return setmetatable({ R = a.R + (b.R - a.R) * t, G = a.G + (b.G - a.G) * t, B = a.B + (b.B - a.B) * t }, Color3Meta)
	end,
}
Color3 = {
	new = function(r, g, b)
		return setmetatable({ R = r, G = g, B = b }, Color3Meta)
	end,
	fromRGB = function(r, g, b)
		return setmetatable({ R = r / 255, G = g / 255, B = b / 255 }, Color3Meta)
	end,
}

-- Deterministic stand-in for Roblox's Random.
Random = {}
function Random.new(seed)
	local state = (seed or 1) % 2147483647
	if state <= 0 then
		state += 2147483646
	end
	local r = {}
	local function nextFloat()
		state = (state * 16807) % 2147483647
		return state / 2147483647
	end
	function r:NextNumber(a, b)
		a, b = a or 0, b or 1
		return a + (b - a) * nextFloat()
	end
	function r:NextInteger(a, b)
		return math.min(b, a + math.floor((b - a + 1) * nextFloat()))
	end
	return r
end
UDim = { new = function(...)
	return { ... }
end }
UDim2 = {
	new = function(...)
		return { ... }
	end,
	fromOffset = function(...)
		return { ... }
	end,
	fromScale = function(...)
		return { ... }
	end,
}
Vector2 = { new = function(x, y)
	return { X = x, Y = y }
end }

-- Enum.Material.Metal -> "Material.Metal"
Enum = setmetatable({}, {
	__index = function(_, group)
		return setmetatable({}, {
			__index = function(_, item)
				return group .. "." .. item
			end,
		})
	end,
})

-- Instances --------------------------------------------------------------------
local DEFAULTS = {
	Part = { Size = v3(4, 1, 2), CanCollide = true, Transparency = 0 },
	WedgePart = { Size = v3(4, 1, 2), CanCollide = true, Transparency = 0 },
	TrussPart = { Size = v3(2, 2, 2), CanCollide = true, Transparency = 0 },
}
local BASEPART = { Part = true, TrussPart = true, WedgePart = true, SpawnLocation = true }

InstanceMeta = {}
local methods = {}
function methods.IsA(self, class)
	if class == "BasePart" then
		return BASEPART[self.ClassName] == true
	end
	return self.ClassName == class
end
function methods.SetAttribute(self, k, v)
	self._attrs[k] = v
end
function methods.GetAttribute(self, k)
	return self._attrs[k]
end
function methods.AddTag(self, tag)
	self._tags[tag] = true
end
function methods.HasTag(self, tag)
	return self._tags[tag] == true
end
function methods.GetChildren(self)
	return table.clone(self._children)
end
function methods.GetDescendants(self)
	local out = {}
	local function walk(i)
		for _, c in i._children do
			table.insert(out, c)
			walk(c)
		end
	end
	walk(self)
	return out
end
function methods.FindFirstChild(self, name)
	for _, c in self._children do
		if c.Name == name then
			return c
		end
	end
	return nil
end
function methods.FindFirstChildOfClass(self, class)
	for _, c in self._children do
		if c.ClassName == class then
			return c
		end
	end
	return nil
end

InstanceMeta.__index = function(self, key)
	if methods[key] then
		return methods[key]
	end
	return rawget(self, "_props")[key]
end
InstanceMeta.__newindex = function(self, key, value)
	if key == "Parent" then
		local old = self._props.Parent
		if old then
			local i = table.find(old._children, self)
			if i then
				table.remove(old._children, i)
			end
		end
		if value then
			table.insert(value._children, self)
		end
		self._props.Parent = value
		return
	end
	if key == "Position" then
		local c = self._props.CFrame
		self._props.CFrame = if c then CFrame.new(value) * cf(v3(), c.r, c.u, c.b) else CFrame.new(value)
		return
	end
	if key == "Size" and self.ClassName == "TrussPart" then
		for _, d in { value.X, value.Y, value.Z } do
			assert(d >= 2 and math.abs(d / 2 - math.round(d / 2)) < 1e-6, "TrussPart sizes must be multiples of 2, got " .. d)
		end
	end
	self._props[key] = value
end

Instance = {}
function Instance.new(className)
	local props = { Name = className, CFrame = CFrame.new(0, 0, 0) }
	for k, v in DEFAULTS[className] or {} do
		props[k] = v
	end
	local inst = { ClassName = className, _props = props, _children = {}, _attrs = {}, _tags = {} }
	return setmetatable(inst, InstanceMeta)
end

local services = {}
game = {
	GetService = function(_, name)
		if not services[name] then
			local s = Instance.new(name)
			s.Name = name
			services[name] = s
		end
		return services[name]
	end,
}
workspace = game:GetService("Workspace")
