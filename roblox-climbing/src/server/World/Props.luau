--!strict
-- Props: pre-made models from the Roblox Creator Store (furniture, plants, trees, rocks,
-- tents...), placed by the world builders.
--
-- A builder calls Props.slot(): that makes a Model standing at the spot, with the asset to
-- use, the size to fit it into and the way it faces, and fills it with a simple stand-in
-- built in code. At server start PropService loads the real model (once per asset, then
-- clones it), scales it to fit, stands it exactly on the floor, and swaps it in for the
-- stand-in. If a model can't be loaded (for example "Allow Loading Third Party Assets" is
-- off in Game Settings > Security) the stand-in stays, so the world is always complete.
--
-- All asset ids live in LIBRARY below (scouted with tools/world/scout.py: free models with
-- no scripts, well rated).

local CollectionService = game:GetService("CollectionService")

local Props = {}

Props.TAG = "PropSlot"

export type Entry = {
	id: number,
	name: string,
	collide: boolean, -- solid to walk into (trees and bushes aren't, so no invisible walls)
	sink: number?, -- fraction of the fitted height pushed below the floor (rocks)
	yaw: number?, -- extra turn (degrees) when the model's front isn't its -Z side
}

Props.LIBRARY = table.freeze({
	plant_palm = { id = 8704290264, name = "Potted palm", collide = true },
	plant_floor = { id = 3209557930, name = "Floor plant", collide = true },
	plant_fig = { id = 11900728265, name = "Fiddle-leaf fig", collide = true },
	sofa = { id = 412942154, name = "Modern sofa", collide = true },
	coffee = { id = 12520208389, name = "Coffee machine", collide = true },
	stool = { id = 13001590550, name = "Bar stool", collide = true },
	vending = { id = 10904552162, name = "Snack vending machine", collide = true },
	cooler = { id = 468240417, name = "Water cooler", collide = true },
	locker = { id = 850076059, name = "Gym locker", collide = true },
	bench = { id = 8763019508, name = "Wooden bench", collide = true },
	benchpress = { id = 4974524267, name = "Bench press", collide = true },
	pine_a = { id = 113109119460825, name = "Red cedar pine", collide = false },
	pine_b = { id = 5392132809, name = "Realistic pine", collide = false },
	bush = { id = 8647777369, name = "Bush", collide = false },
	flowerbush = { id = 8174229353, name = "Flower bush", collide = false },
	rock_a = { id = 1192366796, name = "Realistic rock", collide = true, sink = 0.2 },
	rock_b = { id = 8442632450, name = "Mossy rock", collide = true, sink = 0.2 },
	rock_c = { id = 394353111, name = "Realistic rocks", collide = true, sink = 0.15 },
	tent = { id = 341666811, name = "Camping tent", collide = true },
	campfire = { id = 9769594863, name = "Campfire", collide = false },
} :: { [string]: Entry })

-- A prop slot: `base` is the point on the floor (its LookVector is the way the prop
-- faces), `size` the box to fit the model into (it keeps its proportions). `fallback`
-- fills the slot with the stand-in, in world space.
function Props.slot(parent: Instance, key: string, base: CFrame, size: Vector3, fallback: ((Model) -> ())?): Model
	local entry = Props.LIBRARY[key]
	assert(entry, `Props: unknown prop {key}`)
	local model = Instance.new("Model")
	model.Name = `Prop_{key}`
	model:SetAttribute("AssetKey", key)
	model:SetAttribute("Base", base)
	model:SetAttribute("FitSize", size)
	if fallback then
		fallback(model)
	end
	model.Parent = parent
	CollectionService:AddTag(model, Props.TAG)
	return model
end

-- A flat-ground CFrame at `position` facing `facing` (horizontal).
function Props.at(position: Vector3, facing: Vector3): CFrame
	local flat = Vector3.new(facing.X, 0, facing.Z)
	if flat.Magnitude < 1e-3 then
		flat = Vector3.new(0, 0, -1)
	end
	return CFrame.lookAt(position, position + flat.Unit)
end

return table.freeze(Props)
