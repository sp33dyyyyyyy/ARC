--!nocheck
-- Builds the game's world outside Studio with Lune (https://lune-org.github.io), by running
-- the real World modules from the Rojo-built place, then writes every part to JSON for
-- audit.py (floor/overlap checks) and render.py (pictures).
--
--     rojo build default.project.json -o /tmp/place.rbxlx
--     lune run tools/world/build.luau /tmp/place.rbxlx /tmp/world.json [/tmp/baked.rbxlx]
--
-- The optional third path saves the place with the world already built into it.

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")

local placePath, outPath, bakedPath = process.args[1], process.args[2], process.args[3]
local game = roblox.deserializePlace(fs.readFile(placePath))
local Workspace = game:GetService("Workspace")

-- Engine features Lune doesn't have.
roblox.implementMethod("Instance", "WaitForChild", function(instance, name)
	return instance:FindFirstChild(name)
end)
roblox.implementMethod("Instance", "GetAttributeChangedSignal", function()
	return { Connect = function() end }
end)
local terrainFills = {}
roblox.implementMethod("Terrain", "FillBlock", function(_, cframe, size, material)
	table.insert(terrainFills, { cf = { cframe:GetComponents() }, size = { size.X, size.Y, size.Z }, material = tostring(material) })
end)
roblox.implementMethod("Terrain", "Clear", function() end)
roblox.implementMethod("Terrain", "FillBall", function(_, center, radius, material)
	table.insert(terrainFills, { ball = true, cf = { roblox.CFrame.new(center):GetComponents() }, size = { radius * 2, radius * 2, radius * 2 }, material = tostring(material) })
end)
roblox.implementMethod("Workspace", "Raycast", function()
	return { Position = roblox.Vector3.zero, Instance = Workspace }
end)
roblox.implementMethod("Players", "CreateHumanoidModelFromDescription", function()
	error("no avatars outside Studio")
end)
roblox.implementMethod("RunService", "IsStudio", function()
	return true
end)
roblox.implementMethod("RunService", "IsServer", function()
	return true
end)
roblox.implementMethod("Model", "PivotTo", function(model, cframe)
	local primary = model.PrimaryPart
	local pivot = if primary then primary.CFrame else model:GetBoundingBox()
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.CFrame = cframe * pivot:ToObjectSpace(d.CFrame)
		end
	end
end)
roblox.implementMethod("Model", "GetBoundingBox", function(model)
	local lo, hi = Vector3.one * math.huge, -Vector3.one * math.huge
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			lo = lo:Min(d.CFrame.Position)
			hi = hi:Max(d.CFrame.Position)
		end
	end
	return CFrame.new((lo + hi) / 2), hi - lo
end)
roblox.implementProperty("BasePart", "Position", function(part)
	return part.CFrame.Position
end, function(part, value)
	part.CFrame = part.CFrame - part.CFrame.Position + value
end)
roblox.implementProperty("Attachment", "WorldCFrame", function(a)
	local parent = a.Parent
	return if parent and parent:IsA("BasePart") then parent.CFrame * a.CFrame else a.CFrame
end)
roblox.implementProperty("Attachment", "WorldPosition", function(a)
	local parent = a.Parent
	return (if parent and parent:IsA("BasePart") then parent.CFrame * a.CFrame else a.CFrame).Position
end)
roblox.implementProperty("Attachment", "Position", function(a)
	return a.CFrame.Position
end, function(a, value)
	a.CFrame = a.CFrame - a.CFrame.Position + value
end)

-- require() for ModuleScripts in the place.
local cache = {}
local env
local function requireModule(module)
	if cache[module] ~= nil then
		return cache[module]
	end
	local moduleEnv = table.clone(env)
	moduleEnv.script = module
	-- Lune's own Instance:AddTag shadows CollectionService:AddTag(instance, tag).
	local source = module.Source:gsub("CollectionService:(%a+)%(", "__collection.%1(")
	-- ...and Attachment.WorldCFrame/WorldPosition aren't computed.
	source = source:gsub("([%w_%.]+)%.WorldCFrame", "__worldCFrame(%1)")
	source = source:gsub("([%w_%.]+)%.WorldPosition", "__worldCFrame(%1).Position")
	-- ...and BasePart.Position isn't a real property in Lune.
	local lines = {}
	for line in (source .. "\n"):gmatch("(.-)\n") do
		local indent, target, value = line:match("^(%s*)([%w_%.]+)%.Position%s*=%s*([^=].-)%s*$")
		if indent then
			line = `{indent}__setPos({target}, {value})`
		else
			line = line:gsub("([%w_][%w_%.]*)%.Position", "__pos(%1)")
		end
		table.insert(lines, line)
	end
	source = table.concat(lines, "\n")
	local chunk = luau.load(source, { debugName = module:GetFullName(), environment = moduleEnv })
	local result = chunk()
	cache[module] = result
	return result
end
env = {
	__collection = {
		AddTag = function(instance, tag)
			instance:AddTag(tag)
		end,
		HasTag = function(instance, tag)
			return instance:HasTag(tag)
		end,
		RemoveTag = function(instance, tag)
			instance:RemoveTag(tag)
		end,
		GetTagged = function(tag)
			local list = {}
			for _, d in game:GetDescendants() do
				if d:HasTag(tag) then
					table.insert(list, d)
				end
			end
			return list
		end,
	},
	__worldCFrame = function(a)
		local parent = a.Parent
		return if parent and parent:IsA("BasePart") then parent.CFrame * a.CFrame else a.CFrame
	end,
	__pos = function(x)
		if typeof(x) == "CFrame" then
			return x.Position
		elseif typeof(x) == "Instance" and (x:IsA("BasePart") or x:IsA("Attachment")) then
			return x.CFrame.Position
		end
		return x.Position
	end,
	__setPos = function(x, value)
		if typeof(x) == "Instance" and (x:IsA("BasePart") or x:IsA("Attachment")) then
			x.CFrame = x.CFrame - x.CFrame.Position + value
		else
			x.Position = value
		end
	end,
	RaycastParams = { new = function() return {} end },
	game = game,
	workspace = Workspace,
	require = requireModule,
	task = { wait = function() end, spawn = function(f, ...) f(...) end, defer = function(f, ...) f(...) end, delay = function() end },
	warn = function(...)
		print("WARN", ...)
	end,
}
for _, name in { "Axes", "BrickColor", "CFrame", "Color3", "ColorSequence", "ColorSequenceKeypoint", "Enum", "Faces", "Font", "Instance", "NumberRange", "NumberSequence", "NumberSequenceKeypoint", "PhysicalProperties", "Ray", "Rect", "Region3", "UDim", "UDim2", "Vector2", "Vector3" } do
	env[name] = roblox[name]
end
for _, name in { "print", "pcall", "error", "assert", "type", "typeof", "tostring", "tonumber", "pairs", "ipairs", "next", "select", "setmetatable", "getmetatable", "rawget", "rawset", "rawequal", "table", "string", "math", "os", "utf8", "bit32", "buffer", "coroutine", "unpack", "xpcall" } do
	env[name] = (getfenv(0) :: any)[name]
end

local server = game:GetService("ServerScriptService").Server
for _, name in { "Environment", "Gym", "TestWall", "Outdoors" } do
	local ok, err = pcall(function()
		local module = requireModule(server.World[name])
		if module.Apply then
			module.Apply()
		else
			module.Ensure()
		end
	end)
	print(name, if ok then "built" else "FAILED: " .. tostring(err))
end

-- Dump.
local parts = {}
for _, d in Workspace:GetDescendants() do
	if d:IsA("BasePart") and not d:IsA("Terrain") then
		local mesh = d:FindFirstChildOfClass("SpecialMesh")
		local shape = if mesh and mesh.MeshType == roblox.Enum.MeshType.Sphere then "Ellipsoid" elseif d:IsA("Part") then tostring(d.Shape):gsub("Enum.PartType.", "") elseif d:IsA("WedgePart") then "Wedge" elseif d:IsA("CornerWedgePart") then "CornerWedge" else d.ClassName
		table.insert(parts, {
			path = d:GetFullName(),
			shape = shape,
			size = { d.Size.X, d.Size.Y, d.Size.Z },
			cf = { d.CFrame:GetComponents() },
			color = { d.Color.R, d.Color.G, d.Color.B },
			material = tostring(d.Material):gsub("Enum.Material.", ""),
			transparency = d.Transparency,
			collide = d.CanCollide,
			tags = d:GetTags(),
		})
	end
end
local lights = {}
for _, d in Workspace:GetDescendants() do
	if d:IsA("Light") then
		table.insert(lights, { path = d:GetFullName(), class = d.ClassName, brightness = d.Brightness, range = d.Range, color = { d.Color.R, d.Color.G, d.Color.B } })
	end
end
local lighting = game:GetService("Lighting")
local post = {}
for _, d in lighting:GetChildren() do
	local entry = { class = d.ClassName }
	for _, prop in { "Intensity", "Size", "Threshold", "Brightness", "Contrast", "Saturation" } do
		local ok, value = pcall(function()
			return d[prop]
		end)
		if ok and type(value) == "number" then
			entry[prop] = value
		end
	end
	table.insert(post, entry)
end
fs.writeFile(outPath, serde.encode("json", {
	parts = parts,
	terrain = terrainFills,
	lights = lights,
	lighting = { Brightness = lighting.Brightness, ExposureCompensation = lighting.ExposureCompensation, EnvironmentDiffuseScale = lighting.EnvironmentDiffuseScale, EnvironmentSpecularScale = lighting.EnvironmentSpecularScale, post = post },
}))
print(`{#parts} parts, {#lights} lights, {#terrainFills} terrain fills -> {outPath}`)
if bakedPath then
	fs.writeFile(bakedPath, roblox.serializePlace(game))
	print(`baked place -> {bakedPath}`)
end
