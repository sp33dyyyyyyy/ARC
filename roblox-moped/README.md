# Moped Days - a Roblox moped & supermoto cruiser (Luau)

A relaxed, slightly comedic village-cruising game: four original bikes
(50-200cc), a proper **start-up procedure** (fuel tap, ignition, choke,
kickstart / starter), **pushing the bike by hand** where weight matters, jobs
for money, fuel and repair costs, and a garage.

All names, models, UI and code are original. Nothing is copied from any
other game. Audio is left as empty slots for **your own** sound ids.

> **Status, honestly:** the code was written and syntax-checked with the Luau
> compiler, and the data/tuning maths was run outside Roblox. It has **not**
> been run inside Roblox Studio (no Studio in the build environment). Expect to
> spend a play session tuning feel; every tuning number lives in
> `GameConfig.lua` and `VehicleData.lua`.

---------------------------------------------------------------------------

## 1. Controls

| | |
|---|---|
| Throttle / brake | `W` / `S` (arrows work too) · rear brake / skid `Space` |
| Steer + lean | `A` `D` |
| Wheelie | hold `Left Shift` with throttle in a low gear |
| Shift down / up | `Z` / `X` (CVT moped ignores it) |
| **Fuel tap** (Off > On > Reserve) | `F` |
| **Ignition** | `I` |
| **Choke** | `C` |
| **Kickstart** (tap it!) | `K` |
| **Electric starter** (Dachs 200 only) | `E` |
| Ride / get on | `R` near the bike · jump to get off |
| **Push the bike** (grab / let go of the bars) | `G` near the handlebars, then just walk |
| Call your bike | `B` |
| Prompts | walk around the bike: tap on the tank, key at the headstock, choke at the carb, kick lever on the right |

Gamepad: left stick steer, R2 throttle, L2 brake, A rear brake, X wheelie,
bumpers shift.  Mobile touch controls are **not** included.

### Test fleet

`GameConfig.TestFleet = true` (the default for now) spawns **all four bikes in a
line in front of you**, full tanks, owned or not, so you can try each one
straight away. Pressing `B` re-spawns the line. Set it to `false` for the normal
one-equipped-bike game. In test mode the HUD and the station prompts use
whichever bike you're riding, or the nearest one.

### Starting a bike (the loop)

1. **Fuel tap** `F` - On. (Reserve gives you the last litre or so.)
2. **Ignition** `I` - On.
3. **Cold engine?** Choke `C` on. **Warm engine?** Choke off.
4. **Kick** `K`. It may take a few kicks; the two-strokes are fussy, the
   Kuckuck is friendly, the Dachs also has a starter button (battery drains on
   failed tries, recharges while running).
5. Too many kicks with choke on a warm engine = **flooded**. Choke off and wait
   ~8 s per flood point.
6. Leave the choke on and it wastes fuel and robs power.

Running dry: the carb bowl keeps the engine alive ~4 s after the tap closes or
the tank hits the reserve line, then it sputters and stalls. Flip the tap to
**Reserve** and limp to a petrol station (engine must be **off** to refuel).

### Pushing

Stand at the handlebars and press `G`. Your walk speed becomes
`16 * clamp(1 - (kg - 40) / 260, 0.25, 0.9)` where `kg` is bike weight **plus
0.74 kg per litre of fuel**. The shove you can give is `1300 / kg`. If the bike
lags behind your hands, your arms stretch and you get dragged back. Jump or
walk too far and you let go.

| Bike | kg (half tank) | walk speed while pushing | shove accel |
|---|---|---|---|
| Spatz 50 | 86.5 | 13.1 studs/s | 15.0 |
| Kuckuck 100 | 107.2 | 11.9 | 12.1 |
| Wiesel 125 | 97.6 | 12.5 | 13.3 |
| Dachs 200 | 138.5 | 9.9 | 9.4 |

Uphill is naturally harder (gravity does that part).

---------------------------------------------------------------------------

## 2. Vehicle roster

All data is in **one file**: `src/ReplicatedStorage/Shared/VehicleData.lua`.
`validate()` refuses to load a bike outside 50-200cc or without exactly two
colours. Price = `3.0 * cc^1.5` rounded to 100; repair = `cc * 0.04` EUR per
health point.

| Bike | Class | Engine | Top | Accel | Brake | Handling | Weight | Tank | Price | Unlock | Colours |
|---|---|---|---|---|---|---|---|---|---|---|---|
| Spatz 50 | Moped | 50cc 2-stroke | 45 km/h | 35 | 30 | 55 | 85 kg | 4.0 L | free | - | Butter Yellow / Fern Green |
| Kuckuck 100 | Moped | 100cc 4-stroke (CVT) | 70 | 50 | 45 | 70 | 105 | 6.0 | 3,000 | own Spatz + 5 jobs | Brick Red / Alpine White |
| Wiesel 125 | Supermoto | 125cc 2-stroke, 5 gears | 105 | 75 | 80 | 85 | 95 | 7.0 | 4,200 | EUR 4,000 earned | Signal Orange / Slate Blue |
| Dachs 200 | Supermoto | 200cc 4-stroke, 5 gears | 135 | 85 | 95 | 70 | 135 | 9.5 | 8,500 | own Wiesel + 20 jobs | Racing Black / Rapeseed Yellow |

Two-strokes have a narrow power band (weak low down, snappy near `peak`) and
burn more fuel. The Wiesel lifts its front wheel easily (`wheelie = 0.9`).

To add a bike: copy one entry in `VehicleData.lua`, change the numbers, done -
garage, physics, fuel, start-up and prices all follow.

---------------------------------------------------------------------------

## 3. Project structure

```
roblox-moped/
├─ default.project.json                  Rojo mapping (optional)
└─ src/
   ├─ ReplicatedStorage/Shared/          (Folder in ReplicatedStorage)
   │   ├─ VehicleData.lua                ModuleScript  <- ALL bike data
   │   ├─ GameConfig.lua                 ModuleScript  tuning numbers
   │   ├─ MissionData.lua                ModuleScript  job templates
   │   ├─ Remotes.lua                    ModuleScript  creates/gets every remote
   │   ├─ ModelKit.lua                   ModuleScript  part-building toolkit (tubes, arcs, spoked wheels ...)
   │   ├─ BikeModels.lua                 ModuleScript  the detailed moped / scooter / supermoto bodies
   │   ├─ BikeFactory.lua                ModuleScript  builds a bike (or loads YOUR model) + physics setup
   │   ├─ BikePhysics.lua                ModuleScript  raycast-wheel two-wheeler solver
   │   ├─ ClientState.lua                ModuleScript  client-only shared telemetry
   │   └─ SoundIds.lua                   ModuleScript  <- paste YOUR audio ids here
   ├─ ServerScriptService/
   │   ├─ Main.server.lua                Script        boots everything in order
   │   └─ Services/                      (Folder)
   │       ├─ DataService.lua            DataStore + pcall/retry + autosave + BindToClose
   │       ├─ EconomyService.lua         the ONLY thing that changes money
   │       ├─ VehicleService.lua         spawn, start-up procedure, fuel, damage, push, prompts
   │       ├─ GarageService.lua          validated buy / equip / spawn
   │       ├─ StationService.lua         petrol station, workshop, garage door prompts
   │       ├─ MissionService.lua         delivery / checkpoint / cruise, server-judged
   │       ├─ TownBuilder.lua            lays out the whole map (core first, scenery in the background)
   │       ├─ Buildings.lua              houses, church, barn, shops, garage, petrol station, Gasthof
   │       └─ Props.lua                  trees, lamps, signs, cars, tractor, maibaum, fountain, power poles ...
   └─ StarterPlayerScripts/              (StarterPlayer > StarterPlayerScripts)
       ├─ BikeClient.client.lua          LocalScript  input + physics for the bike you control
       ├─ EffectsController.client.lua   LocalScript  sound, smoke, shake (cosmetic only)
       └─ UI/                            (Folder)
           ├─ UIKit.lua                  ModuleScript  UI helpers
           ├─ HUD.client.lua             LocalScript  gauges, start-up panel, toasts, money
           ├─ GarageUI.client.lua        LocalScript  garage w/ rotating preview + stat bars
           └─ MissionClient.client.lua   LocalScript  job board, tracker, markers
```

**StarterGui is intentionally empty.** The UIs are built in code from
LocalScripts (with `ResetOnSpawn = false`), so they don't get duplicated on
respawn and everything stays in version control.

**Workspace** (you build / the test world generates):
`Town/` (your map) · `MissionSpots/` (parts named in `MissionData`) ·
tagged props (`GarageDoor`, `Workshop`, `PetrolStation`, `MissionBoard`) ·
`Bikes/` (created at runtime).

**ReplicatedStorage/VehicleModels/** is an empty folder for your imported bike
models, named by vehicle id (`spatz50`, `kuckuck100`, `wiesel125`, `dachs200`).
Empty = the blocky placeholder bikes are generated instead.

### Architecture in one paragraph

Server owns every number that matters (money, owned bikes, fuel, health, mission
progress, who is allowed to do what). Bike state is stored as **Attributes on
the bike Model**, so all clients see fuel/ignition/engine state with no extra
remotes. The one thing the server does *not* simulate is the bike's movement:
the player who is riding or pushing a bike gets **network ownership** and runs
`BikePhysics` locally (responsive, no input lag). The server then watches that
movement and applies consequences: speed-loss = crash damage, flipped = tip-over,
absurd speed = clamped. Clients only do cosmetics (sound, smoke, camera shake).

Bike modes (`Mode` attribute): `Parked` (anchored, kickstand) → `Ride` (seated)
/ `Push` (hands on bars) → `Coast` (let go, rolling to a halt) → `Parked`.

---------------------------------------------------------------------------

## 4. Studio setup, step by step

### Option A - Rojo (recommended)
1. Install Rojo (CLI + Studio plugin).
2. In `roblox-moped/` run `rojo serve`, then in Studio click **Connect**.
3. Skip to step 7.

### Option B - paste by hand
1. New **Baseplate** place (delete the Baseplate if you build your own map).
2. `ReplicatedStorage`: add a **Folder** named `Shared` and a **Folder** named
   `VehicleModels`. Inside `Shared` create 8 **ModuleScripts** with the names
   from the tree above and paste each file.
3. `ServerScriptService`: add a **Script** named `Main` (paste
   `Main.server.lua`) and a **Folder** `Services` with 7 **ModuleScripts**.
4. `StarterPlayer > StarterPlayerScripts`: add **LocalScripts** `BikeClient`
   and `EffectsController`, plus a **Folder** `UI` containing LocalScripts
   `HUD`, `GarageUI`, `MissionClient` and a ModuleScript `UIKit`.
5. File suffix → class: `.server.lua` = Script, `.client.lua` = LocalScript,
   plain `.lua` = ModuleScript. Names in Studio have no suffix.
6. Make sure `Workspace.Gravity` is the default 196.2.

### Both options
7. **Home > Game Settings > Security > Enable Studio Access to API Services**
   (and publish the place, or saves will not work). Without it the game still
   runs, but with a temporary profile that is never saved - by design.
8. Press **Play**. `TownBuilder` generates the map (about 3,300 parts, a second
   or two at server start): village, market square, highway, farm, forest loop
   and the hill hamlet. You spawn at (0, 0, 56) on the main street, next to the
   job board, garage and Werkstatt. Your bike appears in front of you.

### Testing checklist
1. **Start-up:** walk to your Spatz. Try the Ride prompt (`R`) *before*
   starting it - the throttle should do nothing. Then: tap on, ignition on,
   choke on (cold), kick until it catches. Confirm HUD rows go green.
2. **Failure modes:** turn the tap off while running → sputter → stall after
   ~4 s. Kick a warm engine with choke on 4+ times → "Flooded". Set tap to On
   and ride until fuel passes the reserve line → sputter → switch to Reserve.
3. **Pushing:** with the engine off press `G` at the bars and walk. Compare
   the Spatz (light) against the Dachs (buy it by cheating money, see below):
   the Dachs should be visibly slower and drag you back sooner. Let go and
   watch it roll to a stop and park itself.
4. **Riding:** gears (`Z`/`X`), wheelie on the Wiesel (`Shift`), skid with
   `Space`+`S`, lean in corners, ride off the kerb.
5. **Crash:** hit a wall at speed. Health drops, harder = rider ejected, engine
   stalls, 0 health = wrecked until repaired.
6. **Economy:** refuel (engine off!), repair at the Werkstatt, check costs.
7. **Garage:** open it, spin the preview, check locked/unlocked text, buy,
   equip, swap colour.
8. **Missions:** take each of the three types from the board.
9. **Save:** buy something, stop the test, start again, confirm it persists.
10. **Multiplayer:** Test tab → Local Server with 2+ players. Each player gets
    their own bike; only the owner's prompts work; check you can hear/see
    another player's engine and smoke.

Testing the expensive bikes quickly: temporarily set
`Economy.StartingMoney = 50000` in `GameConfig.lua` and `unlock = {}` on the
bike you want in `VehicleData.lua`. (A fresh DataStore key is needed for the
starting money to apply - use a new `StoreName` while testing.)

---------------------------------------------------------------------------

## 5. What YOU need to do

**Map - done for you.** `TownBuilder.lua` generates an original map (zones,
roads, buildings, trees, tagged props and every mission spot). Landmarks:
Kleindorf main street (z=0, x -300..300) with Baeckerei, Dorfladen, Garage,
Werkstatt and Tankstelle Sued; Marktplatz (0,-150) with fountain, church and
Gasthof; Schnellstrasse east along z=0 to x=2400 then north (Tankstelle Nord at
x=1500); Hofweg farm lane south at x=1200; Waldweg loop west/north through pine
forest; Huegeldorf on a plateau up a ramp road at the end of the highway.
Roads are long on purpose - a moped does ~45 studs/s, a Dachs ~130.

To use YOUR OWN map instead: set `GameConfig.GenerateTown = false` (or put your
map in a Folder called `Town`), then tag props (`GarageDoor`, `Workshop`,
`PetrolStation`, `MissionBoard` - any BasePart) and make
`Workspace/MissionSpots` parts named `Spot_Bakery`, `Spot_Gasthof`, `Spot_Farm`,
`Spot_Dorfladen`, `Spot_Huegeldorf`, `CP_Forest1`..`CP_Forest5`. Wheels raycast,
so ground parts must have CanQuery on; keep slopes under ~35 degrees. Missions
whose spots are missing simply aren't offered.

**About "realistic" models.** Everything you see is built from Roblox parts
(boxes, cylinders, spheres) by code - about 430 parts per bike and ~12,000 for
the whole map. That gives a convincing low-poly look (see tools/preview.py to
render any model offline), but it cannot match sculpted meshes. For truly
realistic models, make or get real meshes and drop them in - nothing else has
to change, because both the bikes and the buildings have override slots:

- **Bikes:** Model named after the vehicle id in `ReplicatedStorage/VehicleModels`
  (requirements below).
- **Buildings:** Models in `ReplicatedStorage/TownModels` named
  `Fachwerkhaus1`, `Fachwerkhaus2` ... (houses, picked at random), `Kirche`,
  `Scheune`, `Werkstatt`, `Tankstelle`. Front door faces +Z, origin at ground
  level centre. They replace the generated version automatically.
- Where to get meshes: the Roblox Creator Store (Toolbox > Models, free models
  by other creators - check the licence/creator and look for "low poly village",
  "moped", "motocross"), Roblox Studio's built-in Mesh Generator / Cube 3D AI
  tool (Home > Generate), or model in Blender and import with the 3D Importer.
  Import in Studio - they have to be uploaded to YOUR Roblox account.

**Bike meshes (optional - the generated bikes work)** - import your own and drop a
Model named after each vehicle id into `ReplicatedStorage/VehicleModels`.
Requirements:
- `PrimaryPart` = a part named **Chassis**. Axes: **-Z forward, +X right, +Y up**.
- Wheel centres at chassis-local `(0, -0.25, ±wheelbase/2)`, wheel radius from
  `VehicleData.geometry`. (So bottom of the tyre is `radius + 0.25` below the
  chassis centre.) Model origin height doesn't matter; the server places it.
- A `Seat` (or the factory fails the spawn). Keep it welded.
- Optional `Attachment`s on the Chassis override the default prompt positions:
  `SeatPoint HandlebarPoint FuelTapPoint IgnitionPoint ChokePoint KickPoint
  StarterPoint ExhaustPoint`.
- Parts with Attribute `Paint = "body"` or `"accent"` get the two colour options.
- 1 stud ≈ 0.28 m; wheel radius 0.85-1.05, wheelbase 4-5 studs, rider seat
  roughly 2.6-3 studs above the ground.

**Sounds** - upload your *own* clips (Creator Hub > Assets) and paste the ids
into `SoundIds.lua`: `engineLoop` (looping; pitch follows rpm), `kick`, `crank`,
`startUp`, `sputter`, `stall`, `click`, `crash`, `refuel`, `repair`, `coin`.
Empty = silent, nothing breaks. Per-bike overrides via `perBike`.

**Animations (optional)** - pushing, riding and kicking use simple procedural
poses (arms out to the bars, a leg stomp on the kick lever), set by changing
R15 shoulder/hip joints in `VehicleService` so every player sees them. They
need no asset ids. For polish, publish your own animations and play them
instead (R6 characters get no pose).

**Tuning** - expect to adjust `GameConfig.Physics` (spring, grip), the per-bike
`powerband`, `geometry.maxLeanDeg`, and `Crash.MinSpeedLoss` after a real
play session.

**Publish + enable API services** for DataStore saves (step 7 above).

---------------------------------------------------------------------------

## 6. Known limitations / honest notes

- **Not run in Studio yet** (see top). Most likely first-run tuning: ride
  height/spring feel, steering sensitivity, crash threshold.
- Movement is client-simulated (network ownership), standard for Roblox
  vehicles. A cheating client could ignore its own physics; the server clamps
  speed and still owns money/fuel/health, so the economy can't be cheated.
- Prompts show for everyone on a bike but only the owner can use them.
- No traffic, police or engine/tyre/exhaust upgrades in v1. `VehicleData` is
  structured so upgrades can be added as extra stat multipliers.
- Saves use `UpdateAsync` last-write-wins and no session lock; fine for one
  server per player, add a lock before shipping widely.
- Saved: money, owned bikes (+colour), equipped bike, jobs, lifetime earnings,
  per-bike fuel and health.

---------------------------------------------------------------------------

## 7. Developer tools

`tools/build_rbxlx.py` packs `src/` into `MopedDays.rbxlx` (a place file), no
Rojo needed. `tools/preview.py` runs the real model-building code under a mock
Roblox runtime and renders it to a PNG, so models can be checked without Studio:

```
python3 tools/preview.py bike spatz50 out.png        # one bike, four views
python3 tools/preview.py scene houses out.png        # houses | church | barn | shops | petrol | props
python3 tools/preview.py region out.png -330 -300 330 90 0   # a region of the full town
```
(needs `luau` on PATH or `LUAU=/path/to/luau`, plus numpy and Pillow.)
