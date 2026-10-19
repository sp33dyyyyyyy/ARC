-- Mock Roblox environment with REAL Vector3 / CFrame math that records every
-- Part created, so model-building code can be run offline and rendered.
-- Used by tools/preview.py only. Not part of the game.

local V3 = {}
V3.__index = V3
local function vec(x, y, z) return setmetatable({ X = x, Y = y, Z = z }, V3) end
V3.__add = function(a, b) return vec(a.X + b.X, a.Y + b.Y, a.Z + b.Z) end
V3.__sub = function(a, b) return vec(a.X - b.X, a.Y - b.Y, a.Z - b.Z) end
V3.__unm = function(a) return vec(-a.X, -a.Y, -a.Z) end
V3.__mul = function(a, b)
  if type(a) == "number" then return vec(a * b.X, a * b.Y, a * b.Z) end
  if type(b) == "number" then return vec(a.X * b, a.Y * b, a.Z * b) end
  return vec(a.X * b.X, a.Y * b.Y, a.Z * b.Z)
end
V3.__div = function(a, b)
  if type(b) == "number" then return vec(a.X / b, a.Y / b, a.Z / b) end
  return vec(a.X / b.X, a.Y / b.Y, a.Z / b.Z)
end
V3.__eq = function(a, b) return a.X == b.X and a.Y == b.Y and a.Z == b.Z end
V3.__index = function(t, k)
  if k == "Magnitude" then return math.sqrt(t.X * t.X + t.Y * t.Y + t.Z * t.Z) end
  if k == "Unit" then local m = math.sqrt(t.X * t.X + t.Y * t.Y + t.Z * t.Z) if m == 0 then return t end return vec(t.X / m, t.Y / m, t.Z / m) end
  return V3[k]
end
function V3.Dot(a, b) return a.X * b.X + a.Y * b.Y + a.Z * b.Z end
function V3.Cross(a, b) return vec(a.Y * b.Z - a.Z * b.Y, a.Z * b.X - a.X * b.Z, a.X * b.Y - a.Y * b.X) end
function V3.Lerp(a, b, t) return a + (b - a) * t end
Vector3 = { new = function(x, y, z) return vec(x or 0, y or 0, z or 0) end, zero = vec(0, 0, 0), yAxis = vec(0, 1, 0), xAxis = vec(1, 0, 0), zAxis = vec(0, 0, 1) }

-- CFrame: position p, rotation columns rx, ry, rz (world-space axes)
local CF = {}
local function cfm(p, rx, ry, rz) return setmetatable({ Position = p, R = rx, U = ry, B = rz }, CF) end
CF.__index = function(t, k)
  if k == "LookVector" then return -t.B end
  if k == "RightVector" then return t.R end
  if k == "UpVector" then return t.U end
  if k == "X" then return t.Position.X end
  if k == "Y" then return t.Position.Y end
  if k == "Z" then return t.Position.Z end
  return CF[k]
end
local function rot(c, v) return c.R * v.X + c.U * v.Y + c.B * v.Z end
CF.__mul = function(a, b)
  if getmetatable(b) == V3 then return a.Position + rot(a, b) end
  return cfm(a.Position + rot(a, b.Position), rot(a, vec(b.R.X, b.R.Y, b.R.Z)), rot(a, b.U), rot(a, b.B))
end
-- rotate columns properly: columns of b are vectors expressed in b's parent frame (= a's local frame)
CF.__mul = function(a, b)
  if getmetatable(b) == V3 then return a.Position + rot(a, b) end
  return cfm(a.Position + rot(a, b.Position), rot(a, b.R), rot(a, b.U), rot(a, b.B))
end
function CF.Inverse(c)
  local p = c.Position
  local rx = vec(c.R.X, c.U.X, c.B.X)
  local ry = vec(c.R.Y, c.U.Y, c.B.Y)
  local rz = vec(c.R.Z, c.U.Z, c.B.Z)
  local inv = cfm(vec(0, 0, 0), rx, ry, rz)
  return cfm(-rot(inv, p), rx, ry, rz)
end
function CF.PointToWorldSpace(c, v) return c * v end
function CF.VectorToWorldSpace(c, v) return rot(c, v) end
function CF.ToObjectSpace(c, o) return c:Inverse() * o end
CFrame = {}
CFrame.new = function(x, y, z)
  if getmetatable(x) == V3 then return cfm(x, vec(1, 0, 0), vec(0, 1, 0), vec(0, 0, 1)) end
  return cfm(vec(x or 0, y or 0, z or 0), vec(1, 0, 0), vec(0, 1, 0), vec(0, 0, 1))
end
local function Rx(a) local c, s = math.cos(a), math.sin(a) return cfm(vec(0,0,0), vec(1,0,0), vec(0,c,s), vec(0,-s,c)) end
local function Ry(a) local c, s = math.cos(a), math.sin(a) return cfm(vec(0,0,0), vec(c,0,-s), vec(0,1,0), vec(s,0,c)) end
local function Rz(a) local c, s = math.cos(a), math.sin(a) return cfm(vec(0,0,0), vec(c,s,0), vec(-s,c,0), vec(0,0,1)) end
CFrame.Angles = function(x, y, z) return Rx(x or 0) * Ry(y or 0) * Rz(z or 0) end
CFrame.fromEulerAnglesYXZ = function(x, y, z) return Ry(y) * Rx(x) * Rz(z) end
CFrame.lookAt = function(pos, target, up)
  up = up or vec(0, 1, 0)
  local z = (pos - target).Unit
  local x = up:Cross(z)
  if x.Magnitude < 1e-6 then x = vec(1, 0, 0) end
  x = x.Unit
  local y = z:Cross(x)
  return cfm(pos, x, y, z)
end

Color3 = { fromRGB = function(r, g, b) return { r = r, g = g, b = b } end, new = function(r, g, b) return { r = r * 255, g = g * 255, b = b * 255 } end }
Enum = setmetatable({}, { __index = function(_, k) return setmetatable({}, { __index = function(_, k2) return k .. "." .. k2 end }) end })
UDim2 = { fromOffset = function() return {} end, fromScale = function() return {} end, new = function() return {} end }
UDim = { new = function() return {} end }
PhysicalProperties = { new = function() return {} end }
NumberSequence = { new = function() return {} end }
NumberSequenceKeypoint = { new = function() return {} end }
NumberRange = { new = function() return {} end }
ColorSequence = { new = function() return {} end }
Random = { new = function(seed)
  local state = seed or 1
  local r = {}
  local function nextf() state = (state * 1103515245 + 12345) % 2147483648 return state / 2147483648 end
  r.NextNumber = function(_, a, b) a = a or 0 b = b or 1 return a + nextf() * (b - a) end
  r.NextInteger = function(_, a, b) return a + math.floor(nextf() * (b - a + 1)) end
  return r
end }

-- Instances ------------------------------------------------------------------
PARTS = {}
local Inst = {}
Inst.__index = function(t, k)
  local v = rawget(t, "_p")[k]
  if v ~= nil then return v end
  if k == "Name" then return rawget(t, "_name") end
  if Inst[k] ~= nil then return Inst[k] end
  if type(k) == "string" then return Inst.FindFirstChild(t, k) end
  return nil
end
Inst.__newindex = function(t, k, v)
  local props = rawget(t, "_p")
  if k == "Parent" then
    local old = props.Parent
    if old then for i, c in ipairs(old._kids) do if c == t then table.remove(old._kids, i) break end end end
    props.Parent = v
    if v then table.insert(v._kids, t) end
    return
  end
  props[k] = v
end
function Inst.GetDescendants(t)
  local out = {}
  local function walk(o) for _, c in ipairs(o._kids) do table.insert(out, c) walk(c) end end
  walk(t)
  return out
end
function Inst.GetChildren(t) return t._kids end
function Inst.FindFirstChild(t, name, rec)
  for _, c in ipairs(t._kids) do if c.Name == name then return c end end
  if rec then for _, c in ipairs(t._kids) do local f = Inst.FindFirstChild(c, name, true) if f then return f end end end
  return nil
end
function Inst.FindFirstChildWhichIsA(t, cls, rec)
  for _, c in ipairs(t._kids) do if c.ClassName == cls then return c end end
  if rec then for _, c in ipairs(t._kids) do local f = Inst.FindFirstChildWhichIsA(c, cls, true) if f then return f end end end
  return nil
end
function Inst.IsA(t, cls)
  if t.ClassName == cls then return true end
  local part = { Part = 1, Seat = 1, WedgePart = 1, SpawnLocation = 1, MeshPart = 1 }
  if cls == "BasePart" then return part[t.ClassName] ~= nil end
  return false
end
function Inst.SetAttribute(t, k, v) t._attrs[k] = v end
function Inst.GetAttribute(t, k) return t._attrs[k] end
function Inst.Destroy(t) t.Parent = nil end
function Inst.Clone(t) return t end
function Inst.PivotTo(t, cf)
  local pivot = t.PrimaryPart and t.PrimaryPart.CFrame or CFrame.new(0, 0, 0)
  local rel = pivot:Inverse()
  for _, d in ipairs(t:GetDescendants()) do
    if d.CFrame then d.CFrame = cf * (rel * d.CFrame) end
  end
end
function Inst.WaitForChild(t, n) return t:FindFirstChild(n) end

local PARTCLASSES = { Part = 1, Seat = 1, WedgePart = 1, SpawnLocation = 1 }
Instance = { new = function(cls)
  local t = setmetatable({ _p = { ClassName = cls }, _kids = {}, _attrs = {}, _name = cls }, Inst)
  rawget(t, "_p").Name = cls
  if PARTCLASSES[cls] then
    local p = rawget(t, "_p")
    p.Size = vec(2, 1, 4)
    p.CFrame = CFrame.new(0, 0, 0)
    p.Color = { r = 160, g = 160, b = 160 }
    p.Shape = "PartType.Block"
    p.Material = "Material.Plastic"
    p.Transparency = 0
    p.Position = vec(0, 0, 0)
    table.insert(PARTS, t)
  end
  return t
end }

-- permissive services ---------------------------------------------------------
local function noop() return nil end
local Svc = {}
Svc.__index = function(t, k)
  if k == "FindFirstChild" or k == "FindFirstChildOfClass" or k == "FindFirstChildWhichIsA" then return function() return nil end end
  return noop
end
local function service() return setmetatable({}, Svc) end
Terrain = setmetatable({ _fills = {} }, { __index = function(t, k)
  return function(_, ...) table.insert(t._fills, { k, ... }) end
end })
local wsRoot = Instance.new("Workspace")
workspace = wsRoot
local RS = Instance.new("Folder")
RS.Name = "ReplicatedStorage"
local SHARED = Instance.new("Folder")
SHARED.Name = "Shared"
SHARED.Parent = RS
game = { ReplicatedStorage = RS, GetService = function(_, name) if name == "Workspace" then return wsRoot end if name == "ReplicatedStorage" then return RS end if name == "CollectionService" then return { AddTag = function(_, inst, tag) inst._attrs.__tag = tag end, GetTagged = function() return {} end } end return service() end }
task = { spawn = function(f, ...) f(...) end, wait = function() end, delay = function() end }
warn = function(...) print("WARN:", ...) end
wsRoot.Gravity = 196.2
wsRoot.Terrain = Terrain
typeof = function(v) return type(v) end
RaycastParams = { new = function() return {} end }

-- module loader ---------------------------------------------------------------
MODULES, CACHE = {}, {}
function SETUP_TREE()
  for name in pairs(MODULES) do
    local c = Instance.new("ModuleScript")
    c.Name = name
    c.Parent = SHARED
  end
end
function require(obj)
  local n = type(obj) == "string" and obj or (obj and obj.Name)
  if CACHE[n] ~= nil then return CACHE[n] end
  local f = MODULES[n]
  if not f then error("mock require: no module " .. tostring(n)) end
  local me = SHARED:FindFirstChild(n) or Instance.new("ModuleScript")
  CACHE[n] = f(me)
  return CACHE[n]
end

function DUMP(filter)
  local out = {}
  for _, p in ipairs(PARTS) do
    local a = p.Parent
    local alive = false
    local node = p
    while node do if node == wsRoot or node.IsRoot then alive = true break end node = node.Parent end
    if alive or filter == "all" then
      local c = p.CFrame
      local s = p.Size
      local col = p.Color
      table.insert(out, string.format("%s|%s|%.4f,%.4f,%.4f|%.4f,%.4f,%.4f|%.4f,%.4f,%.4f|%.4f,%.4f,%.4f|%.4f,%.4f,%.4f|%d,%d,%d|%s|%.2f|%s",
        p.ClassName, p.Shape, s.X, s.Y, s.Z, c.Position.X, c.Position.Y, c.Position.Z,
        c.R.X, c.R.Y, c.R.Z, c.U.X, c.U.Y, c.U.Z, c.B.X, c.B.Y, c.B.Z,
        col.r or 0, col.g or 0, col.b or 0, p.Material, p.Transparency or 0, p.Name))
    end
  end
  return table.concat(out, "\n")
end
