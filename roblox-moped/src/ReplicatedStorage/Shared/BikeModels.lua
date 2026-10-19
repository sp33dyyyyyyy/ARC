--[[
	BikeModels  (ModuleScript, ReplicatedStorage/Shared)

	Detailed part-built bike bodies. Each builder gets a ModelKit welded to the
	bike's Chassis and the VehicleData entry, and builds everything visible:
	wheels, frame, fork, engine, exhaust, tank, seat, lights, mudguards ...

	  moped       pedal moped: pedals, chain, two-stroke engine, round muffler
	  scooter     the Aerox 50 stand-in: step-through body, floorboard, variator cover
	  supermoto   the Supermoto 80 stand-in: tall long-travel forks, discs, high pipe

	Coordinates: chassis centre = origin, -Z forward, +Y up, +X right.
	The ground is at y = -(wheelRadius + 0.25). Axles sit at y = -0.25.
	Parts tagged Paint = "body" / "accent" take the bike's two colour options.
]]

local ModelKit = require(script.Parent.ModelKit)

local BikeModels = {}

local V3, CF = Vector3.new, CFrame.new
local rgb = Color3.fromRGB

local C = {
	steel = rgb(140, 143, 150),
	chrome = rgb(208, 211, 217),
	alu = rgb(172, 176, 183),
	dark = rgb(38, 39, 44),
	black = rgb(20, 20, 22),
	seat = rgb(46, 40, 38),
	lens = rgb(255, 246, 214),
	red = rgb(205, 28, 30),
	amber = rgb(255, 150, 30),
	gold = rgb(214, 168, 58),
	rubber = rgb(26, 26, 28),
	plate = rgb(240, 240, 232),
	cream = rgb(236, 228, 208),
}
local M = Enum.Material
local BODY = { paint = "body" }
local ACCENT = { paint = "accent" }

local function mirror(fn)
	fn(-1)
	fn(1)
end

-- headlight: bucket + chrome bezel + glowing lens, axis along Z
local function headlight(kit, pos: Vector3, dia: number, depth: number, shell, shellOpts)
	local face = CF(pos) * CFrame.Angles(0, math.pi / 2, 0)
	kit:cyl("HeadlightShell", depth, dia, dia, face, shell, M.SmoothPlastic, shellOpts)
	kit:cyl("HeadlightBezel", 0.05, dia * 1.04, dia * 1.04, CF(pos + V3(0, 0, -depth / 2)) * CFrame.Angles(0, math.pi / 2, 0), C.chrome, M.Metal)
	kit:cyl("HeadlightLens", 0.04, dia * 0.84, dia * 0.84, CF(pos + V3(0, 0, -depth / 2 - 0.03)) * CFrame.Angles(0, math.pi / 2, 0), C.lens, M.Neon)
end

local function mirrorsAndLevers(kit, barY: number, barZ: number, spread: number)
	mirror(function(s)
		-- brake / clutch lever
		kit:strip("Lever", V3(s * (spread - 0.05), barY + 0.02, barZ - 0.05), V3(s * (spread + 0.2), barY + 0.04, barZ - 0.4), 0.06, 0.04, C.chrome, M.Metal)
		-- mirror stalk, arm and head
		kit:tube("MirrorStalk", V3(s * (spread - 0.3), barY + 0.03, barZ - 0.02), V3(s * (spread - 0.05), barY + 0.62, barZ - 0.08), 0.05, C.dark, M.Metal)
		kit:cyl("MirrorBack", 0.07, 0.42, 0.3, CF(s * (spread - 0.02), barY + 0.74, barZ - 0.12) * CFrame.Angles(0, math.pi / 2, 0), C.dark, M.SmoothPlastic)
		kit:cyl("MirrorGlass", 0.02, 0.36, 0.25, CF(s * (spread - 0.02), barY + 0.74, barZ - 0.16) * CFrame.Angles(0, math.pi / 2, 0), C.chrome, M.Metal)
	end)
end

----------------------------------------------------------------------------
-- MOPED (manual, pedals, two-stroke) - the Spatz
----------------------------------------------------------------------------
function BikeModels.moped(kit, v)
	local g = v.geometry
	local L, R = g.wheelbase, g.wheelRadius
	local zf, zr, ay = -L / 2, L / 2, -0.25

	kit:wheel("Front", V3(0, ay, zf), R, 0.42, { spokes = 9, drum = true, drumSide = 0.26, rimRatio = 0.72 })
	kit:wheel("Rear", V3(0, ay, zr), R, 0.5, { spokes = 9, drum = true, drumSide = -0.3, rimRatio = 0.72 })

	-- steering: fork from the front axle up to the head, with rake
	local headTop = V3(0, 1.85, zf + 0.62)
	local axle = V3(0, ay, zf)
	mirror(function(s)
		local lo = axle:Lerp(headTop, 0.46) + V3(s * 0.3, 0, 0)
		local hi = axle:Lerp(headTop, 1.0) + V3(s * 0.3, 0, 0)
		local low = axle + V3(s * 0.3, 0, 0)
		kit:tube("ForkLeg", low, lo, 0.16, C.alu, M.Metal)
		kit:tube("ForkGaiter", lo, axle:Lerp(headTop, 0.72) + V3(s * 0.3, 0, 0), 0.25, C.black, M.Rubber)
		kit:tube("ForkTube", axle:Lerp(headTop, 0.7) + V3(s * 0.3, 0, 0), hi, 0.2, C.chrome, M.Metal)
	end)
	kit:box("TopYoke", V3(0.95, 0.14, 0.42), CF(headTop + V3(0, 0.05, 0.02)), C.dark, M.Metal)
	kit:box("AxlePlate", V3(0.96, 0.1, 0.16), CF(axle), C.dark, M.Metal)

	-- handlebar, grips, levers, mirrors
	local barY, barZ = 2.24, zf + 0.7
	local bar = { V3(-0.98, barY + 0.03, barZ + 0.28), V3(-0.55, barY, barZ), V3(0.55, barY, barZ), V3(0.98, barY + 0.03, barZ + 0.28) }
	kit:curve("Handlebar", bar, 0.1, C.chrome, M.Metal)
	mirror(function(s)
		kit:tube("Grip", V3(s * 0.98, barY + 0.03, barZ + 0.28), V3(s * 1.3, barY + 0.05, barZ + 0.4), 0.19, C.rubber, M.Rubber)
	end)
	mirrorsAndLevers(kit, barY, barZ + 0.12, 0.98)
	kit:tube("Stem", V3(0, 1.88, zf + 0.64), V3(0, barY - 0.05, barZ), 0.16, C.chrome, M.Metal)

	-- headlight + speedometer + key switch
	headlight(kit, V3(0, 1.95, zf + 0.12), 0.95, 0.5, v.colours[1].body, BODY)
	kit:cyl("Speedo", 0.22, 0.5, 0.5, CF(0, barY + 0.2, barZ + 0.12) * CFrame.Angles(0, 0, math.pi / 2), C.black, M.SmoothPlastic)
	kit:cyl("SpeedoFace", 0.03, 0.4, 0.4, CF(0, barY + 0.32, barZ + 0.12) * CFrame.Angles(0, 0, math.pi / 2), rgb(120, 230, 150), M.Neon)
	kit:box("IgnitionBox", V3(0.3, 0.26, 0.3), CF(0, 1.62, zf + 0.9), C.dark, M.Metal)
	kit:strip("Key", V3(0, 1.62, zf + 0.75), V3(0, 1.62, zf + 0.5), 0.09, 0.03, C.chrome, M.Metal)

	-- front mudguard
	kit:arc("FrontFender", axle, R + 0.22, -0.55, 1.2, 13, 0.62, 0.07, -1, v.colours[1].body, M.SmoothPlastic, BODY)
	mirror(function(s)
		kit:strut("FenderStay", axle + V3(s * 0.3, 0.1, 0), axle + V3(s * 0.3, R + 0.15, 0.08), 0.06, C.dark, M.Metal)
	end)

	-- frame
	local head = V3(0, 1.72, zf + 0.62)
	kit:tube("HeadTube", head + V3(0, -0.3, -0.07), head + V3(0, 0.3, 0.07), 0.32, C.dark, M.Metal)
	kit:curve("Spine", { V3(0, 1.55, zf + 0.7), V3(0, 1.3, -0.5), V3(0, 1.22, 0.35), V3(0, 1.2, 1.15) }, 0.3, C.dark, M.Metal)
	kit:curve("DownTube", { V3(0, 1.45, zf + 0.72), V3(0, 0.55, zf + 1.0), V3(0, -0.05, -0.8) }, 0.28, C.dark, M.Metal)
	kit:curve("Cradle", { V3(0, -0.05, -0.8), V3(0, -0.4, -0.35), V3(0, -0.42, 0.85) }, 0.26, C.dark, M.Metal)
	kit:tube("RearPost", V3(0, 1.2, 1.15), V3(0, -0.3, 1.0), 0.26, C.dark, M.Metal)
	mirror(function(s)
		kit:tube("SubFrame", V3(s * 0.4, 1.2, 0.9), V3(s * 0.5, 1.12, zr + 0.5), 0.13, C.dark, M.Metal)
		kit:tube("SeatStay", V3(s * 0.5, ay, zr), V3(s * 0.42, 1.12, 1.6), 0.12, C.dark, M.Metal)
		kit:tube("SwingArm", V3(s * 0.46, -0.32, 1.0), V3(s * 0.52, ay, zr), 0.2, C.dark, M.Metal)
	end)
	kit:box("SwingArmBrace", V3(1.0, 0.14, 0.2), CF(0, -0.32, 1.05), C.dark, M.Metal)

	-- two-stroke engine: crankcase, cylinder with cooling fins, head, covers
	kit:box("Crankcase", V3(0.74, 0.78, 0.98), CF(0, -0.12, -0.05), C.alu, M.Metal)
	kit:box("Gearbox", V3(0.72, 0.6, 0.72), CF(0, -0.2, 0.72), C.alu, M.Metal)
	kit:cyl("ClutchCover", 0.2, 0.86, 0.86, CF(-0.45, -0.08, 0.02), C.alu, M.Metal)
	kit:cyl("ClutchCoverBoss", 0.08, 0.38, 0.38, CF(-0.58, -0.08, 0.02), C.steel, M.Metal)
	kit:cyl("MagnetoCover", 0.18, 0.78, 0.78, CF(0.45, -0.02, -0.12), C.alu, M.Metal)
	local barrelA, barrelB = V3(0, 0.2, -0.32), V3(0, 1.02, -0.75)
	kit:tube("Barrel", barrelA, barrelB, 0.56, C.steel, M.Metal)
	for i = 1, 6 do
		local t = 0.1 + i * 0.13
		local a = barrelA:Lerp(barrelB, t)
		kit:tube("Fin", a, a + (barrelB - barrelA).Unit * 0.05, 0.86, C.steel, M.Metal)
	end
	kit:tube("CylinderHead", barrelB, barrelB + (barrelB - barrelA).Unit * 0.28, 0.6, C.alu, M.Metal)
	kit:tube("SparkPlug", barrelB + V3(0, 0.1, 0.0), barrelB + V3(0, 0.38, 0.12), 0.1, C.chrome, M.Metal)
	kit:box("PlugCap", V3(0.14, 0.18, 0.14), CF(barrelB + V3(0, 0.46, 0.14)), C.black, M.SmoothPlastic)
	-- carburettor + air box (body-coloured side covers)
	kit:box("Carburettor", V3(0.34, 0.34, 0.52), CF(-0.44, 0.62, -0.34), C.alu, M.Metal)
	kit:tube("IntakeBoot", V3(-0.44, 0.62, -0.1), V3(-0.4, 0.7, 0.35), 0.28, C.black, M.Rubber)
	kit:box("AirBox", V3(0.78, 0.68, 1.0), CF(0, 0.7, 0.62), C.dark, M.SmoothPlastic)
	mirror(function(s)
		kit:stadium("SidePanel", 1.05, 0.66, 0.07, CF(s * 0.44, 0.72, 0.62), v.colours[1].body, M.SmoothPlastic, BODY)
	end)

	-- tank, seat, tail
	kit:pod("Tank", 1.55, 0.78, 0.82, CF(0, 1.52, -0.55), v.colours[1].body, M.SmoothPlastic, BODY)
	kit:pod("TankStripe", 1.2, 0.05, 0.2, CF(0, 1.93, -0.55), v.colours[1].accent, M.SmoothPlastic, ACCENT)
	kit:cyl("FuelCap", 0.1, 0.3, 0.3, CF(0, 1.94, -0.28) * CFrame.Angles(0, 0, math.pi / 2), C.chrome, M.Metal)
	mirror(function(s)
		kit:box("KneePad", V3(0.05, 0.42, 0.62), CF(s * 0.43, 1.46, -0.5), C.rubber, M.Rubber)
	end)
	kit:tube("FuelTap", V3(-0.36, 1.2, -0.12), V3(-0.66, 1.18, -0.12), 0.13, C.gold, M.Metal)
	kit:strip("FuelTapLever", V3(-0.68, 1.18, -0.12), V3(-0.78, 1.0, -0.12), 0.05, 0.03, C.gold, M.Metal)
	kit:pod("SeatBase", 2.0, 0.16, 0.8, CF(0, 1.5, 1.05), C.dark, M.SmoothPlastic, ACCENT)
	kit:pod("SeatCushion", 2.0, 0.3, 0.88, CF(0, 1.66, 1.05), C.seat, M.Fabric)

	-- rear mudguard, rack, tail light, plate
	kit:arc("RearFender", V3(0, ay, zr), R + 0.24, -0.95, 1.0, 13, 0.66, 0.07, 1, v.colours[1].body, M.SmoothPlastic, BODY)
	local tail = V3(0, ay + (R + 0.24) * math.cos(1.0), zr + (R + 0.24) * math.sin(1.0))
	kit:box("TailLight", V3(0.42, 0.22, 0.22), CF(tail + V3(0, 0.1, 0.08)), C.red, M.Neon)
	kit:box("NumberPlate", V3(0.92, 0.46, 0.04), CF(tail + V3(0, -0.34, 0.1)) * CFrame.Angles(math.rad(-12), 0, 0), C.plate, M.SmoothPlastic)
	kit:box("NumberPlateEdge", V3(0.96, 0.5, 0.03), CF(tail + V3(0, -0.34, 0.085)) * CFrame.Angles(math.rad(-12), 0, 0), C.dark, M.SmoothPlastic)
	mirror(function(s)
		kit:tube("RackRail", V3(s * 0.38, 1.2, 1.6), V3(s * 0.38, 1.12, zr + 0.7), 0.07, C.chrome, M.Metal)
	end)
	kit:box("RackTop", V3(0.86, 0.05, 0.4), CF(0, 1.19, zr + 0.55), C.chrome, M.Metal)

	-- rear shocks with springs
	mirror(function(s)
		local lo, hi = V3(s * 0.62, 0.15, zr + 0.1), V3(s * 0.52, 1.1, 1.55)
		kit:tube("ShockBody", lo, hi, 0.1, C.black, M.Metal)
		kit:tube("ShockSpring", lo:Lerp(hi, 0.18), lo:Lerp(hi, 0.82), 0.22, C.chrome, M.Metal)
	end)

	-- exhaust: header down the right side, round muffler to the back
	kit:curve("ExhaustPipe", { V3(0.25, 0.62, -1.0), V3(0.55, 0.42, -1.22), V3(0.66, -0.12, -0.95), V3(0.68, -0.38, -0.2), V3(0.66, -0.4, 0.5) }, 0.2, C.steel, M.Metal)
	kit:tube("Muffler", V3(0.66, -0.4, 0.5), V3(0.64, -0.28, 2.1), 0.56, C.chrome, M.Metal)
	kit:cone("MufflerTip", V3(0.64, -0.28, 2.1), V3(0.64, -0.25, 2.5), 0.5, 0.26, 3, C.chrome, M.Metal)
	kit:tube("MufflerBracket", V3(0.5, 0.1, 1.85), V3(0.62, -0.1, 1.85), 0.08, C.dark, M.Metal)

	-- chain drive on the left + guard
	kit:cyl("RearSprocket", 0.05, 0.9, 0.9, CF(-0.38, ay, zr), C.steel, M.Metal)
	kit:cyl("FrontSprocket", 0.05, 0.4, 0.4, CF(-0.4, -0.22, 0.72), C.steel, M.Metal)
	kit:strip("ChainTop", V3(-0.4, 0.2, zr), V3(-0.4, -0.04, 0.72), 0.06, 0.04, C.black, M.Metal)
	kit:strip("ChainBottom", V3(-0.4, -0.7, zr), V3(-0.4, -0.4, 0.72), 0.06, 0.04, C.black, M.Metal)
	kit:strip("ChainGuard", V3(-0.5, 0.3, zr), V3(-0.5, 0.0, 0.72), 0.04, 0.2, v.colours[1].body, M.SmoothPlastic, BODY)

	-- pedals + kick-start lever
	kit:tube("CrankAxle", V3(-0.78, -0.55, 0.42), V3(0.78, -0.55, 0.42), 0.13, C.steel, M.Metal)
	kit:strut("CrankL", V3(-0.78, -0.55, 0.42), V3(-0.82, -0.96, 0.52), 0.1, C.steel, M.Metal)
	kit:strut("CrankR", V3(0.78, -0.55, 0.42), V3(0.82, -0.1, 0.34), 0.1, C.steel, M.Metal)
	kit:box("PedalL", V3(0.5, 0.07, 0.28), CF(-1.0, -0.98, 0.52), C.dark, M.Metal)
	kit:box("PedalR", V3(0.5, 0.07, 0.28), CF(1.0, -0.08, 0.34), C.dark, M.Metal)
	kit:tube("KickLever", V3(0.72, -0.1, 0.62), V3(0.95, -0.5, 1.05), 0.12, C.steel, M.Metal)
	kit:box("KickPad", V3(0.24, 0.1, 0.3), CF(0.98, -0.55, 1.1), C.rubber, M.Rubber)
	kit:strut("Kickstand", V3(-0.46, -0.3, 0.4), V3(-0.55, -0.7, 0.85), 0.07, C.steel, M.Metal)

	-- attachment points for the start-up prompts
	kit:attach("SeatPoint", V3(0, 1.7, 1.05))
	kit:attach("HandlebarPoint", V3(0, barY, barZ + 0.1))
	kit:attach("FuelTapPoint", V3(-0.7, 1.15, -0.12))
	kit:attach("IgnitionPoint", V3(0, 1.65, zf + 0.9))
	kit:attach("ChokePoint", V3(-0.5, 0.62, -0.34))
	kit:attach("KickPoint", V3(0.95, -0.5, 1.05))
	kit:attach("ExhaustPoint", V3(0.64, -0.25, 2.55))
end

----------------------------------------------------------------------------
-- SCOOTER (step-through, CVT, four-stroke) - the Kuckuck
----------------------------------------------------------------------------
function BikeModels.scooter(kit, v)
	local g = v.geometry
	local L, R = g.wheelbase, g.wheelRadius
	local zf, zr, ay = -L / 2, L / 2, -0.25
	local body = v.colours[1].body

	kit:wheel("Front", V3(0, ay, zf), R, 0.5, { cast = true, drum = true, drumSide = 0.3, rimColor = C.alu, rimRatio = 0.7 })
	kit:wheel("Rear", V3(0, ay, zr), R, 0.6, { cast = true, drum = true, drumSide = 0.32, rimColor = C.alu, rimRatio = 0.7 })

	-- single-sided leading-link style fork, shrouded
	local headTop = V3(0, 1.75, zf + 0.55)
	local axle = V3(0, ay, zf)
	kit:tube("ForkLegR", axle + V3(0.32, 0, 0), axle:Lerp(headTop, 0.55) + V3(0.32, 0, 0), 0.2, C.alu, M.Metal)
	kit:tube("ForkLegL", axle + V3(-0.32, 0, 0), axle:Lerp(headTop, 0.55) + V3(-0.32, 0, 0), 0.2, C.alu, M.Metal)
	kit:box("ForkShroud", V3(0.86, 0.9, 0.5), CF(axle:Lerp(headTop, 0.78)), body, M.SmoothPlastic, BODY)
	kit:arc("FrontFender", axle, R + 0.2, -0.4, 1.25, 13, 0.7, 0.08, -1, body, M.SmoothPlastic, BODY)

	-- handlebar cowl: headlight set into the shell, speedo on top
	kit:pod("BarCowl", 1.5, 0.7, 1.2, CF(0, 2.15, zf + 0.7) * CFrame.Angles(0, math.pi / 2, 0), body, M.SmoothPlastic, BODY)
	headlight(kit, V3(0, 2.05, zf + 0.05), 0.9, 0.45, body, BODY)
	kit:cyl("Speedo", 0.2, 0.7, 0.7, CF(0, 2.55, zf + 0.7) * CFrame.Angles(0, 0, math.pi / 2), C.black, M.SmoothPlastic)
	kit:cyl("SpeedoFace", 0.03, 0.58, 0.58, CF(0, 2.66, zf + 0.7) * CFrame.Angles(0, 0, math.pi / 2), rgb(120, 230, 150), M.Neon)
	local barY, barZ = 2.3, zf + 0.95
	kit:curve("Handlebar", { V3(-0.95, barY, barZ + 0.25), V3(-0.55, barY, barZ), V3(0.55, barY, barZ), V3(0.95, barY, barZ + 0.25) }, 0.1, C.chrome, M.Metal)
	mirror(function(s)
		kit:tube("Grip", V3(s * 0.95, barY, barZ + 0.25), V3(s * 1.3, barY, barZ + 0.38), 0.2, C.rubber, M.Rubber)
	end)
	mirrorsAndLevers(kit, barY, barZ + 0.1, 0.95)

	-- leg shield (front of the step-through) + floorboard + rear bodywork
	kit:box("LegShield", V3(1.05, 2.0, 0.22), CF(0, 0.85, zf + 1.05) * CFrame.Angles(math.rad(-14), 0, 0), body, M.SmoothPlastic, BODY)
	kit:stadium("LegShieldTop", 1.05, 0.24, 1.05, CF(0, 1.88, zf + 1.18) * CFrame.Angles(0, math.pi / 2, 0), body, M.SmoothPlastic, BODY)
	kit:box("Floorboard", V3(1.25, 0.14, 1.5), CF(0, -0.55, -0.35), C.dark, M.DiamondPlate)
	kit:box("FloorMat", V3(1.1, 0.04, 1.4), CF(0, -0.46, -0.35), C.rubber, M.Rubber)
	mirror(function(s)
		kit:box("FloorSkirt", V3(0.1, 0.4, 1.55), CF(s * 0.66, -0.55, -0.35), body, M.SmoothPlastic, BODY)
		kit:stadium("RearBody", 2.2, 1.35, 0.14, CF(s * 0.66, 0.35, 1.55), body, M.SmoothPlastic, BODY)
	end)
	kit:pod("RearBodyTop", 2.2, 0.5, 1.18, CF(0, 1.0, 1.55), body, M.SmoothPlastic, BODY)
	kit:pod("StorageLid", 1.9, 0.3, 1.0, CF(0, 1.16, 1.4), v.colours[1].accent, M.SmoothPlastic, ACCENT)
	kit:pod("Seat", 1.9, 0.34, 0.95, CF(0, 1.4, 1.35), C.seat, M.Fabric)
	kit:box("SeatBase", V3(0.9, 0.12, 1.8), CF(0, 1.22, 1.35), C.dark, M.SmoothPlastic)
	kit:box("GrabRail", V3(0.12, 0.1, 0.8), CF(0, 1.1, 2.55), C.chrome, M.Metal)

	-- engine unit on the swing arm, variator cover on the left, big muffler
	kit:cyl("VariatorCover", 0.24, 1.15, 1.15, CF(-0.58, -0.05, 1.05), body, M.SmoothPlastic, BODY)
	kit:cyl("VariatorCoverRim", 0.28, 0.5, 0.5, CF(-0.62, -0.05, 1.05), C.alu, M.Metal)
	kit:pod("EngineUnit", 1.9, 0.9, 0.8, CF(0, -0.15, 1.2), C.alu, M.Metal)
	kit:tube("Cylinder", V3(0, 0.1, 0.95), V3(0, 0.55, 0.15), 0.62, C.steel, M.Metal)
	for i = 1, 5 do
		local a = V3(0, 0.1, 0.95):Lerp(V3(0, 0.55, 0.15), 0.1 + i * 0.15)
		kit:tube("Fin", a, a + V3(0, 0.02, -0.05), 0.9, C.steel, M.Metal)
	end
	kit:tube("MufflerPipe", V3(0.3, 0.0, 0.1), V3(0.66, -0.35, 0.5), 0.2, C.steel, M.Metal)
	kit:tube("Muffler", V3(0.66, -0.35, 0.5), V3(0.66, -0.2, 2.2), 0.62, C.chrome, M.Metal)
	kit:cone("MufflerTip", V3(0.66, -0.2, 2.2), V3(0.66, -0.15, 2.55), 0.56, 0.3, 3, C.chrome, M.Metal)
	kit:tube("SwingArmR", V3(0.5, -0.3, 0.7), V3(0.5, ay, zr), 0.18, C.dark, M.Metal)
	mirror(function(s)
		local lo, hi = V3(s * 0.62, 0.0, zr + 0.1), V3(s * 0.55, 1.0, 1.9)
		kit:tube("ShockBody", lo, hi, 0.11, C.black, M.Metal)
		kit:tube("ShockSpring", lo:Lerp(hi, 0.2), lo:Lerp(hi, 0.85), 0.24, C.chrome, M.Metal)
	end)
	kit:tube("KickLever", V3(0.72, -0.15, 1.2), V3(0.95, -0.55, 1.65), 0.12, C.steel, M.Metal)
	kit:box("KickPad", V3(0.24, 0.1, 0.3), CF(0.98, -0.6, 1.7), C.rubber, M.Rubber)
	kit:strut("Centrestand", V3(0, -0.3, 1.0), V3(0, -0.85, 1.35), 0.09, C.steel, M.Metal)

	-- tail light, plate, rear fender
	kit:arc("RearFender", V3(0, ay, zr), R + 0.22, 0.2, 1.1, 9, 0.66, 0.07, 1, body, M.SmoothPlastic, BODY)
	kit:box("TailLight", V3(0.8, 0.22, 0.18), CF(0, 1.0, 2.68), C.red, M.Neon)
	kit:box("NumberPlate", V3(0.92, 0.46, 0.04), CF(0, 0.55, 2.74) * CFrame.Angles(math.rad(-8), 0, 0), C.plate, M.SmoothPlastic)
	kit:box("Chrome", V3(0.96, 0.05, 0.04), CF(0, 0.3, 2.72), C.chrome, M.Metal)
	-- front chrome trim
	kit:box("FrontTrim", V3(0.1, 0.12, 0.5), CF(0, 2.45, zf + 0.35), C.chrome, M.Metal)

	kit:attach("SeatPoint", V3(0, 1.6, 1.3))
	kit:attach("HandlebarPoint", V3(0, barY, barZ + 0.1))
	kit:attach("FuelTapPoint", V3(-0.55, 1.1, 0.3))
	kit:attach("IgnitionPoint", V3(0, 2.0, zf + 0.9))
	kit:attach("ChokePoint", V3(-0.5, 0.45, 0.4))
	kit:attach("KickPoint", V3(0.95, -0.55, 1.65))
	kit:attach("ExhaustPoint", V3(0.66, -0.15, 2.6))
end

----------------------------------------------------------------------------
-- SUPERMOTO (tall, long-travel, discs) - Wiesel (2-stroke) / Dachs (4-stroke)
----------------------------------------------------------------------------
function BikeModels.supermoto(kit, v)
	local g = v.geometry
	local L, R = g.wheelbase, g.wheelRadius
	local zf, zr, ay = -L / 2, L / 2, -0.25
	local body, accent = v.colours[1].body, v.colours[1].accent
	local twoStroke = v.engineType == "Two-stroke"

	kit:wheel("Front", V3(0, ay, zf), R, 0.5, { spokes = 12, disc = true, discSide = 0.22, caliper = -0.5, rimColor = C.gold, rimRatio = 0.8 })
	kit:wheel("Rear", V3(0, ay, zr), R, 0.66, { spokes = 12, disc = true, discSide = -0.24, caliper = 0.9, rimColor = C.gold, rimRatio = 0.8 })

	-- upside-down fork (gold sliders), tall and steep
	local headTop = V3(0, 2.35, zf + 0.8)
	local axle = V3(0, ay, zf)
	mirror(function(s)
		local off = V3(s * 0.34, 0, 0)
		kit:tube("ForkSlider", axle + off, axle:Lerp(headTop, 0.5) + off, 0.2, C.gold, M.Metal)
		kit:tube("ForkTube", axle:Lerp(headTop, 0.46) + off, axle:Lerp(headTop, 0.98) + off, 0.26, C.alu, M.Metal)
	end)
	kit:box("TopYoke", V3(1.0, 0.14, 0.5), CF(headTop + V3(0, 0.0, 0.0)), C.dark, M.Metal)
	kit:box("BottomYoke", V3(0.9, 0.16, 0.5), CF(axle:Lerp(headTop, 0.86)), C.dark, M.Metal)
	kit:box("AxleBrace", V3(0.84, 0.1, 0.2), CF(axle:Lerp(headTop, 0.3)), C.dark, M.Metal)
	-- high front mudguard
	kit:arc("FrontFender", axle + V3(0, 0.5, 0.15), R + 0.35, -0.2, 0.95, 10, 0.6, 0.07, -1, body, M.SmoothPlastic, BODY)
	kit:strut("FenderBridge", axle + V3(-0.34, 0.55, 0.1), axle + V3(0.34, 0.55, 0.1), 0.06, C.dark, M.Metal)

	-- handlebar: wide, tapered, with hand guards and number board
	local barY, barZ = 2.75, zf + 1.0
	kit:curve("Handlebar", { V3(-1.15, barY + 0.05, barZ + 0.3), V3(-0.55, barY, barZ), V3(0.55, barY, barZ), V3(1.15, barY + 0.05, barZ + 0.3) }, 0.1, C.black, M.Metal)
	kit:tube("BarBrace", V3(-0.55, barY, barZ), V3(0.55, barY, barZ), 0.07, C.black, M.Metal)
	mirror(function(s)
		kit:tube("Grip", V3(s * 1.15, barY + 0.05, barZ + 0.3), V3(s * 1.55, barY + 0.07, barZ + 0.4), 0.19, C.rubber, M.Rubber)
		kit:strip("Lever", V3(s * 1.1, barY + 0.03, barZ + 0.25), V3(s * 1.3, barY + 0.05, barZ - 0.1), 0.06, 0.04, C.chrome, M.Metal)
	end)
	kit:box("NumberBoard", V3(0.9, 0.85, 0.07), CF(0, 2.55, zf + 0.45) * CFrame.Angles(math.rad(-16), 0, 0), C.plate, M.SmoothPlastic)
	kit:cyl("HeadlightMask", 0.2, 0.62, 0.62, CF(0, 2.5, zf + 0.35) * CFrame.Angles(0, math.pi / 2, 0), C.black, M.SmoothPlastic)
	kit:cyl("HeadlightLens", 0.04, 0.52, 0.52, CF(0, 2.5, zf + 0.24) * CFrame.Angles(0, math.pi / 2, 0), C.lens, M.Neon)
	kit:cyl("Speedo", 0.16, 0.42, 0.42, CF(0, barY + 0.15, barZ + 0.15) * CFrame.Angles(0, 0, math.pi / 2), C.black, M.SmoothPlastic)
	kit:cyl("SpeedoFace", 0.03, 0.34, 0.34, CF(0, barY + 0.25, barZ + 0.15) * CFrame.Angles(0, 0, math.pi / 2), rgb(120, 230, 150), M.Neon)
	kit:box("IgnitionBox", V3(0.3, 0.24, 0.3), CF(0, 2.15, zf + 1.05), C.dark, M.Metal)
	kit:strip("Key", V3(0, 2.15, zf + 0.9), V3(0, 2.15, zf + 0.65), 0.09, 0.03, C.chrome, M.Metal)
	kit:cyl("Starter", 0.14, 0.24, 0.24, CF(0.55, barY - 0.08, barZ + 0.1) * CFrame.Angles(0, 0, math.pi / 2), C.red, M.SmoothPlastic)

	-- frame: twin-spar look
	kit:tube("HeadTube", V3(0, 2.0, zf + 0.9), V3(0, 2.55, zf + 0.85), 0.38, C.dark, M.Metal)
	mirror(function(s)
		kit:curve("Spar", { V3(s * 0.3, 2.0, zf + 1.0), V3(s * 0.38, 1.7, -0.6), V3(s * 0.4, 1.25, 0.4), V3(s * 0.38, 0.75, 1.0) }, 0.24, accent, M.Metal, ACCENT)
		kit:curve("Cradle", { V3(s * 0.3, 1.65, zf + 1.05), V3(s * 0.4, 0.3, zf + 1.3), V3(s * 0.4, -0.45, -0.7), V3(s * 0.4, -0.5, 0.9) }, 0.2, accent, M.Metal, ACCENT)
		kit:tube("SubFrame", V3(s * 0.34, 1.35, 0.7), V3(s * 0.34, 1.5, zr + 0.6), 0.14, accent, M.Metal, ACCENT)
		kit:tube("SeatStay", V3(s * 0.4, 0.9, 1.2), V3(s * 0.34, 1.4, zr + 0.2), 0.12, C.dark, M.Metal)
		-- fat swing arm
		kit:strip("SwingArm", V3(s * 0.48, -0.35, 1.0), V3(s * 0.52, ay, zr), 0.22, 0.4, C.alu, M.Metal)
	end)
	kit:tube("Linkage", V3(0, -0.5, 1.05), V3(0, 0.1, 1.5), 0.12, C.dark, M.Metal)
	kit:tube("MonoShock", V3(0, 0.1, 1.5), V3(0, 1.4, 0.85), 0.2, C.gold, M.Metal)
	kit:tube("MonoSpring", V3(0, 0.3, 1.4), V3(0, 1.1, 0.95), 0.34, C.red, M.Metal)

	-- engine
	kit:box("Crankcase", V3(0.8, 0.85, 1.0), CF(0, -0.1, 0.0), C.alu, M.Metal)
	kit:box("Gearbox", V3(0.78, 0.7, 0.7), CF(0, -0.15, 0.75), C.alu, M.Metal)
	kit:cyl("ClutchCover", 0.2, 0.9, 0.9, CF(-0.48, -0.1, 0.1), C.alu, M.Metal)
	kit:cyl("ClutchBoss", 0.08, 0.42, 0.42, CF(-0.62, -0.1, 0.1), C.black, M.Metal)
	kit:cyl("IgnitionCover", 0.16, 0.7, 0.7, CF(0.48, 0.0, -0.1), C.alu, M.Metal)
	local barrelA, barrelB = V3(0, 0.3, -0.12), V3(0, 1.2, -0.52)
	if twoStroke then
		kit:tube("Barrel", barrelA, barrelB, 0.58, C.steel, M.Metal)
		for i = 1, 5 do
			local a = barrelA:Lerp(barrelB, 0.1 + i * 0.15)
			kit:tube("Fin", a, a + (barrelB - barrelA).Unit * 0.05, 0.8, C.steel, M.Metal)
		end
		kit:tube("CylinderHead", barrelB, barrelB + (barrelB - barrelA).Unit * 0.3, 0.6, C.alu, M.Metal)
	else
		kit:tube("Barrel", barrelA, barrelB, 0.7, C.alu, M.Metal)
		for i = 1, 6 do
			local a = barrelA:Lerp(barrelB, 0.08 + i * 0.13)
			kit:tube("Fin", a, a + (barrelB - barrelA).Unit * 0.045, 0.92, C.alu, M.Metal)
		end
		kit:tube("CylinderHead", barrelB, barrelB + (barrelB - barrelA).Unit * 0.36, 0.78, C.dark, M.Metal)
		kit:box("ValveCover", V3(0.6, 0.18, 0.7), CF(barrelB + V3(0, 0.46, -0.12)), C.red, M.Metal)
	end
	kit:box("AirBox", V3(0.62, 0.8, 0.9), CF(0, 1.1, 0.95), C.dark, M.SmoothPlastic)

	-- radiator shrouds + tank + seat + tail
	mirror(function(s)
		kit:pod("Shroud", 1.5, 0.95, 0.26, CF(s * 0.5, 1.7, -0.45), body, M.SmoothPlastic, BODY)
		kit:stadium("SidePanel", 1.5, 0.7, 0.07, CF(s * 0.4, 1.35, 1.25), body, M.SmoothPlastic, BODY)
	end)
	kit:pod("Tank", 1.35, 0.7, 0.62, CF(0, 2.05, -0.5), body, M.SmoothPlastic, BODY)
	kit:cyl("FuelCap", 0.1, 0.26, 0.26, CF(0, 2.43, -0.7) * CFrame.Angles(0, 0, math.pi / 2), C.chrome, M.Metal)
	kit:pod("SeatBase", 2.2, 0.16, 0.66, CF(0, 1.78, 0.85), C.dark, M.SmoothPlastic)
	kit:pod("SeatCushion", 2.2, 0.28, 0.7, CF(0, 1.9, 0.85), C.seat, M.Fabric)
	kit:pod("Tail", 1.3, 0.34, 0.62, CF(0, 1.88, zr + 0.35), body, M.SmoothPlastic, BODY)
	kit:arc("MudFlap", V3(0, ay, zr), R + 0.3, 0.7, 1.2, 3, 0.5, 0.06, 1, C.black, M.Rubber)
	kit:box("TailLight", V3(0.34, 0.16, 0.14), CF(0, 1.78, zr + 1.0), C.red, M.Neon)
	kit:box("NumberPlate", V3(0.82, 0.42, 0.04), CF(0, 1.3, zr + 1.2) * CFrame.Angles(math.rad(-18), 0, 0), C.plate, M.SmoothPlastic)

	-- exhaust
	if twoStroke then
		-- expansion chamber: header, fat belly, silencer, high on the right
		kit:curve("Header", { V3(0.2, 0.9, -0.85), V3(0.5, 0.7, -1.15), V3(0.68, 0.2, -0.9), V3(0.7, 0.15, -0.3) }, 0.2, C.steel, M.Metal)
		kit:cone("PipeBelly1", V3(0.7, 0.15, -0.3), V3(0.72, 0.3, 0.55), 0.22, 0.68, 4, C.steel, M.Metal)
		kit:cone("PipeBelly2", V3(0.72, 0.3, 0.55), V3(0.72, 0.55, 1.05), 0.68, 0.34, 3, C.steel, M.Metal)
		kit:tube("Silencer", V3(0.7, 0.62, 1.0), V3(0.66, 1.05, zr + 0.95), 0.36, C.alu, M.Metal)
		kit:tube("SilencerCap", V3(0.66, 1.05, zr + 0.95), V3(0.66, 1.08, zr + 1.1), 0.34, C.dark, M.Metal)
	else
		kit:curve("Header", { V3(0.25, 1.0, -0.9), V3(0.55, 0.8, -1.2), V3(0.72, 0.15, -0.9), V3(0.74, -0.1, 0.0), V3(0.72, 0.5, 0.9) }, 0.22, C.chrome, M.Metal)
		kit:tube("Silencer", V3(0.7, 0.55, 0.95), V3(0.66, 1.15, zr + 0.95), 0.42, C.alu, M.Metal)
		kit:tube("SilencerCap", V3(0.66, 1.15, zr + 0.95), V3(0.66, 1.18, zr + 1.12), 0.4, C.dark, M.Metal)
		-- battery box for the electric starter
		kit:box("Battery", V3(0.42, 0.42, 0.34), CF(-0.5, 0.35, 0.95), C.dark, M.SmoothPlastic)
	end

	-- chain, sprockets, footpegs, bash plate
	kit:cyl("RearSprocket", 0.05, 0.9, 0.9, CF(-0.42, ay, zr), C.alu, M.Metal)
	kit:cyl("FrontSprocket", 0.05, 0.4, 0.4, CF(-0.46, -0.22, 0.65), C.alu, M.Metal)
	kit:strip("ChainTop", V3(-0.45, 0.2, zr), V3(-0.45, -0.02, 0.65), 0.06, 0.04, C.black, M.Metal)
	kit:strip("ChainBottom", V3(-0.45, -0.7, zr), V3(-0.45, -0.42, 0.65), 0.06, 0.04, C.black, M.Metal)
	mirror(function(s)
		kit:strut("FootpegArm", V3(s * 0.4, -0.35, 0.3), V3(s * 0.62, -0.6, 0.3), 0.1, C.dark, M.Metal)
		kit:box("Footpeg", V3(0.55, 0.07, 0.24), CF(s * 0.9, -0.62, 0.3), C.steel, M.Metal)
	end)
	kit:box("BashPlate", V3(0.7, 0.1, 1.3), CF(0, -0.6, -0.15), C.alu, M.Metal)
	kit:tube("KickLever", V3(0.78, -0.2, 0.55), V3(0.98, -0.45, 1.05), 0.12, C.steel, M.Metal)
	kit:box("KickPad", V3(0.22, 0.08, 0.28), CF(1.0, -0.5, 1.1), C.rubber, M.Rubber)
	kit:strut("Kickstand", V3(-0.5, -0.3, 0.3), V3(-0.6, -0.8, 0.7), 0.07, C.steel, M.Metal)

	kit:attach("SeatPoint", V3(0, 2.05, 0.85))
	kit:attach("HandlebarPoint", V3(0, barY, barZ + 0.1))
	kit:attach("FuelTapPoint", V3(-0.45, 1.85, -0.4))
	kit:attach("IgnitionPoint", V3(0, 2.15, zf + 1.05))
	kit:attach("ChokePoint", V3(-0.5, 0.7, -0.3))
	kit:attach("KickPoint", V3(1.0, -0.5, 1.1))
	kit:attach("StarterPoint", V3(0.55, barY, barZ + 0.1))
	kit:attach("ExhaustPoint", V3(0.66, 1.1, zr + 1.15))
end

return BikeModels
