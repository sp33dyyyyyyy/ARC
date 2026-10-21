--!strict
-- TestWallLayout: size and the 20 holds of the Stage 1 practice wall, as pure data (no
-- Roblox APIs, so tests/unit.luau can check it outside Studio). Where the wall stands and
-- its angle live in Config.TestWall.
--
-- x = studs to the climber's right of the wall centre, y = studs above the floor.
-- The crash mat is 0.8 studs thick, so the lowest footholds start at 1.6.
-- Every hold type appears at least once so each can be tested.

export type HoldSpec = {
	x: number,
	y: number,
	type: string,
	quality: number?, -- nil = the type's DefaultQuality
	role: string?, -- "Start" | "Finish"
	rotation: number?, -- degrees, rotated around the wall normal
}

local holds: { HoldSpec } = {
	-- Feet to step on from the mat
	{ x = -1.4, y = 1.6, type = "Foothold" },
	{ x = 1.4, y = 1.6, type = "Foothold" },
	{ x = -2.0, y = 3.6, type = "Edge" },
	{ x = 1.8, y = 3.6, type = "Foothold" },
	-- Start holds (both hands)
	{ x = -1.3, y = 5.6, type = "Jug", role = "Start" },
	{ x = 1.3, y = 5.6, type = "Jug", role = "Start" },
	-- Middle section
	{ x = -2.2, y = 7.8, type = "Crimp" },
	{ x = 1.0, y = 7.8, type = "Edge", rotation = -10 },
	{ x = -0.6, y = 10.0, type = "Pocket" },
	{ x = 2.4, y = 10.0, type = "Pinch" },
	{ x = -2.6, y = 12.2, type = "Sloper" },
	{ x = 0.8, y = 12.2, type = "Crack" },
	{ x = -1.0, y = 14.4, type = "Crimp", quality = 0.3 },
	{ x = 2.0, y = 14.4, type = "Jug" },
	{ x = -2.2, y = 16.6, type = "Pinch" },
	{ x = 0.6, y = 16.6, type = "Sloper" },
	{ x = -0.4, y = 18.8, type = "Edge" },
	{ x = 2.2, y = 18.8, type = "Pocket" },
	-- Top
	{ x = 1.0, y = 20.8, type = "Crimp" },
	{ x = 0.4, y = 22.6, type = "Jug", role = "Finish" },
}

return table.freeze({
	Width = 16,
	Height = 24,
	Thickness = 1.2,
	-- Every hold except the finish has a hold above it within this many studs, so the
	-- wall can be climbed without a dyno. Checked by the unit tests and Stage1Check.
	MaxMoveGap = 3.6,
	Holds = table.freeze(holds),
})
