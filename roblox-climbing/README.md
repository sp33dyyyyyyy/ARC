# Ascent: Roblox climbing game

A skill-based rock climbing game for Roblox: four limbs placed one at a time, stamina, ropes, routes and leaderboards. It is built one stage at a time (see the design doc's Build Order).

**Current build: limb-by-limb climbing with sticky weight shift, stamina, ragdoll falls and death, plus the world: a modern climbing gym (rope walls with auto-belays, bouldering, Kilter board, pro shop, lockers, café), three outdoor crags up to a ~280 m big wall, timed routes with summit cards, mandatory clip-in on every roped wall, gear that changes how you climb, chalk (with a one-tap chalk-up), money (£) and levels, an in-game phone, climbing up over any ledge, summit buttons, saving and leaderboards.**

The name lives in `src/shared/Config.luau` (`Config.GameName`); every sign and the logo use it.

---

## Where everything goes

The project is set up for [Rojo](https://rojo.space) (7.4+), which syncs these files into Studio. Each file becomes one instance:

| File | Studio location | Instance type |
|---|---|---|
| `src/shared/Config.luau` | `ReplicatedStorage.Shared.Config` | ModuleScript |
| `src/shared/Tags.luau` | `ReplicatedStorage.Shared.Tags` | ModuleScript |
| `src/shared/HoldTypes.luau` | `ReplicatedStorage.Shared.HoldTypes` | ModuleScript |
| `src/shared/HoldUtil.luau` | `ReplicatedStorage.Shared.HoldUtil` | ModuleScript |
| `src/shared/ClimbMath.luau` | `ReplicatedStorage.Shared.ClimbMath` | ModuleScript |
| `src/shared/Remotes.luau` | `ReplicatedStorage.Shared.Remotes` | ModuleScript |
| `src/shared/RateLimiter.luau` | `ReplicatedStorage.Shared.RateLimiter` | ModuleScript |
| `src/shared/LimbRig.luau` | `ReplicatedStorage.Shared.LimbRig` | ModuleScript |
| `src/server/Services/ClimbService.luau` | `ServerScriptService.Server.Services.ClimbService` | ModuleScript |
| `src/shared/StaminaMath.luau` | `ReplicatedStorage.Shared.StaminaMath` | ModuleScript |
| `src/server/Services/StaminaService.luau` | `ServerScriptService.Server.Services.StaminaService` | ModuleScript |
| `src/server/Services/RagdollService.luau` | `ServerScriptService.Server.Services.RagdollService` | ModuleScript |
| `src/server/Physics/Ragdoll.luau` | `ServerScriptService.Server.Physics.Ragdoll` | ModuleScript |
| `src/server/Diagnostics/Stage3Check.luau` | `ServerScriptService.Server.Diagnostics.Stage3Check` | ModuleScript |
| `src/server/Main.server.luau` | `ServerScriptService.Server.Main` | **Script** |
| `src/server/Services/HoldService.luau` | `ServerScriptService.Server.Services.HoldService` | ModuleScript |
| `src/server/World/TestWall.luau` | `ServerScriptService.Server.World.TestWall` | ModuleScript |
| `src/server/World/TestWallLayout.luau` | `ServerScriptService.Server.World.TestWallLayout` | ModuleScript |
| `src/server/World/HoldModels.luau` | `ServerScriptService.Server.World.HoldModels` | ModuleScript |
| `src/server/World/Surfaces.luau` | `ServerScriptService.Server.World.Surfaces` | ModuleScript |
| `src/server/World/BuildUtil.luau` | `ServerScriptService.Server.World.BuildUtil` | ModuleScript |
| `src/server/World/Environment.luau` | `ServerScriptService.Server.World.Environment` | ModuleScript |
| `src/server/Diagnostics/Stage1Check.luau` | `ServerScriptService.Server.Diagnostics.Stage1Check` | ModuleScript |
| `src/server/Diagnostics/Stage2Check.luau` | `ServerScriptService.Server.Diagnostics.Stage2Check` | ModuleScript |
| `src/server/Diagnostics/Stage4Check.luau` | `ServerScriptService.Server.Diagnostics.Stage4Check` | ModuleScript |
| `src/server/Services/DataService.luau` | `ServerScriptService.Server.Services.DataService` | ModuleScript |
| `src/server/Services/LeaderboardService.luau` | `ServerScriptService.Server.Services.LeaderboardService` | ModuleScript |
| `src/server/Services/RouteService.luau` | `ServerScriptService.Server.Services.RouteService` | ModuleScript |
| `src/server/Services/RopeService.luau` | `ServerScriptService.Server.Services.RopeService` | ModuleScript |
| `src/server/Services/ChalkService.luau` | `ServerScriptService.Server.Services.ChalkService` | ModuleScript |
| `src/server/Services/ShopService.luau` | `ServerScriptService.Server.Services.ShopService` | ModuleScript |
| `src/server/Services/PropService.luau` | `ServerScriptService.Server.Services.PropService` | ModuleScript |
| `src/server/World/Props.luau` | `ServerScriptService.Server.World.Props` | ModuleScript |
| `src/server/World/Npc.luau` | `ServerScriptService.Server.World.Npc` | ModuleScript |
| `src/shared/Gear.luau` | `ReplicatedStorage.Shared.Gear` | ModuleScript |
| `src/shared/GearModels.luau` | `ReplicatedStorage.Shared.GearModels` | ModuleScript |
| `src/server/World/Gym.luau` | `ServerScriptService.Server.World.Gym` | ModuleScript |
| `src/server/World/Outdoors.luau` | `ServerScriptService.Server.World.Outdoors` | ModuleScript |
| `src/server/World/RockWall.luau` | `ServerScriptService.Server.World.RockWall` | ModuleScript |
| `src/server/World/PanelWall.luau` | `ServerScriptService.Server.World.PanelWall` | ModuleScript |
| `src/server/World/RouteKit.luau` | `ServerScriptService.Server.World.RouteKit` | ModuleScript |
| `src/server/World/RouteGenerator.luau` | `ServerScriptService.Server.World.RouteGenerator` | ModuleScript |
| `src/server/World/Face.luau` | `ServerScriptService.Server.World.Face` | ModuleScript |
| `src/client/Main.client.luau` | `StarterPlayer.StarterPlayerScripts.Client.Main` | **LocalScript** |
| `src/client/Controllers/HoldInspector.luau` | `StarterPlayer.StarterPlayerScripts.Client.Controllers.HoldInspector` | ModuleScript |
| `src/client/Controllers/ClimbController.luau` | `StarterPlayer.StarterPlayerScripts.Client.Controllers.ClimbController` | ModuleScript |
| `src/client/Controllers/ClimbOverlay.luau` | `StarterPlayer.StarterPlayerScripts.Client.Controllers.ClimbOverlay` | ModuleScript |
| `src/client/Controllers/ClimbAnimator.luau` | `StarterPlayer.StarterPlayerScripts.Client.Controllers.ClimbAnimator` | ModuleScript |
| `src/client/Controllers/RouteHud.luau` | `StarterPlayer.StarterPlayerScripts.Client.Controllers.RouteHud` | ModuleScript |
| `src/client/Controllers/GearUI.luau` | `StarterPlayer.StarterPlayerScripts.Client.Controllers.GearUI` | ModuleScript |
| `src/client/Controllers/RopeMotion.luau` | `StarterPlayer.StarterPlayerScripts.Client.Controllers.RopeMotion` | ModuleScript |

`Shared`, `Server`, `Services`, `World`, `Physics`, `Diagnostics`, `Client` and `Controllers` are plain **Folders**.

Each side has exactly one entry script (`Server.Main` and `Client.Main`). Everything else is a ModuleScript with `Init()` and `Start()`, loaded in the order listed at the top of the entry script. Later stages add services (`ClimbService`, `StaminaService`, `RopeService`, `RouteService`, `LeaderboardService`, `DataService`) and controllers (`ClimbController`, `UIController`) the same way.

### What you build by hand in Stage 1

Nothing is required. The server builds the test wall on Play if it is missing. That includes a floor and a spawn if your place has none, so an empty Baseplate works too. These Studio settings are set by the Rojo project. If you copy the scripts by hand, set them yourself:

- **Game Settings → Avatar → Avatar Type: R15.** Limb IK in Stage 2 needs R15. The server warns in Output if someone spawns as R6.
- **Workspace → StreamingEnabled: on.**
- **Lighting → Technology: Future.**
- **MaterialService → Use2022Materials: on.** This gives the newer, more detailed built-in materials.

---

## Setup

### Option A: Rojo (recommended)

1. Install the Rojo CLI 7.4+ ([releases](https://github.com/rojo-rbx/rojo/releases), or `aftman add rojo-rbx/rojo@7.4.4` / `rokit add rojo-rbx/rojo`) and the **Rojo Studio plugin** (from the Creator Store, or `rojo plugin install`).
2. New place: from this folder run `rojo build -o ClimbGame.rbxlx` and open `ClimbGame.rbxlx` in Studio.
   Existing place: open it in Studio.
3. From this folder run `rojo serve`. In Studio, open the Rojo plugin and click **Connect**. Code edits now sync live.

### Option B: copy and paste by hand

1. In **ReplicatedStorage**, create a Folder named `Shared`. Add the four ModuleScripts from `src/shared` with the names in the table above, and paste in each file's contents.
2. In **ServerScriptService**, create a Folder `Server` with a **Script** named `Main`, plus Folders `Services`, `World` and `Diagnostics` holding the ModuleScripts from the table.
3. In **StarterPlayer → StarterPlayerScripts**, create a Folder `Client` with a **LocalScript** named `Main` and a Folder `Controllers` holding `HoldInspector`.
4. Apply the four Studio settings above.

Names matter: the scripts find each other by name (`script.Parent.Services.HoldService`, and so on).

### Optional: build the wall in edit mode

To see and tweak the wall without pressing Play, run this in the **Command Bar** (View → Command Bar):

```lua
require(game.ServerScriptService.Server.World.TestWall).Rebuild()
```

It creates `Workspace.Routes.TestWall`, plus `TestFloor`/`TestSpawn` if needed, and saves them with the place. **If you built the wall in edit mode before v0.1.1, run `Rebuild()` once to get the new realistic models.** Once the wall exists, the server leaves it alone, so hand edits survive. Run `Rebuild()` again to reset it. To change the angle, edit `Config.TestWall.AngleDegrees` (for example `15` for an overhang or `-10` for a slab) and rebuild.

---

## The test wall

```
Workspace.Routes.TestWall          Folder  (RouteName, Grade, HeightStuds, HeightMeters, Indoor)
├── Wall                           painted face plate, tag Climbable, 16 x 24 studs (6.7 m)
├── WallCore                       birch plywood behind it (visible on the edges)
├── Panels/  TNuts/                plywood sheet seams and the bolt-on hole grid
├── Holds/                         20 holds, tag Hold
│     01_Foothold … 20_Jug         attributes HoldType, Quality, HandOK, FootOK, HoldId, Role
│     ├── Grip                     Attachment: where the hand/foot goes
│     └── Lip, Bevel, BoltHead,    decorative child parts (clicking them selects the hold)
│         Chalk, ChalkSmear, …
├── Frame/                         steel posts, rails and braces behind the wall
├── CrashMat                       Model: 3 vinyl segments, Velcro seam covers, sloped front edge
├── StartMarker/  StartPad         taped start box on the mat; invisible volume, tag RouteStart
├── TopOut/                        TopLedge deck (flush with the wall top) and a safety rail
├── Summit                         invisible volume, tag RouteSummit
├── LightRig/                      arms, bar and 3 LED floodlights (SpotLights with shadows)
└── Legend                         route sign on posts with the hold colour key
```

Hold colours on the test wall follow the type: **Jug** green, **Edge** yellow, **Crimp** red, **Sloper** blue, **Pinch** magenta, **Pocket** orange, **Foothold** black, **Crack** grey volumes with a dark slot. Every type appears at least once. There are 2 start jugs (`Role = "Start"`, with two strips of tape under each) and 1 finish jug (`Role = "Finish"`, tape on both sides). No move is longer than 3.6 studs, so the wall can be climbed without a dyno.

### How the realism works

Everything is built from parts at runtime, so no uploaded assets are needed.

- **Holds** (`World/HoldModels.luau`) are shaped per type:
  - jugs have a rolled lip and a dark bucket;
  - edges and crimps have a rounded nose and a bevel underneath;
  - slopers are domes with a recessed bolt;
  - pinches are fins;
  - pockets have a real-looking hole;
  - footholds are screw-on chips with screws;
  - cracks are a slot between two volumes.

  Every hold also has a chalk build-up where hands grip it. Chalk smears and shoe-rubber marks sit on the wall around the holds.
- **Wall**: textured paint over birch plywood, 4 x 8-stud panel seams, a T-nut grid every 0.8 studs (about 22 cm, like a real wall) and a steel frame behind.
- **Lighting** (`World/Environment.luau`) uses Future lighting, environment reflections for PBR materials, soft shadows, atmosphere, light bloom, colour grading and sun rays, plus the floodlights. It is applied once per place. Your own Lighting tweaks are kept after that. `Environment.Apply(true)` re-applies it.
- **No z-fighting**: decals and marks on the wall each sit at their own depth, so no two surfaces flicker against each other.

**Going photo-real with your own textures.** All surfaces are defined in `World/Surfaces.luau`. Each one names a MaterialVariant. To use it, open **View → Material Manager** in Studio and create a MaterialVariant with exactly that name and base material. Add your Color/Normal/Roughness/Metalness maps (free CC0 PBR sets from sites like ambientCG or Poly Haven work well). Every part using that surface picks it up automatically, with no code change. Until a variant with that name exists, Roblox shows the built-in material.

| Variant name | Base material | Used for |
|---|---|---|
| `GymWallPaint` | Plaster | wall face, crack volumes |
| `BirchPlywood` | Wood | wall core, sign backing |
| `HoldUrethane` | Plastic | every hold |
| `MatVinyl` | Leather | crash mat |
| `PolishedConcrete` | Concrete | TestFloor |
| `PaintedSteel` | Metal | frame, rails, light rig |
| `DeckBoards` | WoodPlanks | top-out deck |

Units: 1 stud = 0.28 m (`Config.studsToMeters`).

### Adding your own holds (MeshParts, Toolbox holds, etc.)

`HoldService` accepts any `BasePart` tagged **`Hold`**, at any time, including holds added later by the Wall Builder or the Kilter board. Add the tag in Studio from the **Tags** section of the Properties window. Then set:

| Attribute | Type | Notes |
|---|---|---|
| `HoldType` | string | `Jug`, `Crimp`, `Sloper`, `Pinch`, `Pocket`, `Edge`, `Foothold`, `Crack`. Invalid values become `Edge`, with a warning. |
| `Quality` | number | 0 to 1, how much grip the hold gives. Defaults per type. |
| `HandOK` / `FootOK` | bool | Defaults per type. A Foothold is feet-only, a Pinch is hands-only. |
| `HoldId` | string | Optional. Auto-assigned and made unique. |
| `Role` | string | Optional: `Start` or `Finish`. |

Rotate the hold so its **Front face points away from the wall**, or add an Attachment named `Grip` where the hand should go. Put it in `Workspace.Routes.<RouteName>.Holds`. On server start, HoldService fills in missing attributes, anchors the hold and adds the `Grip` attachment.

---

## Stage 1 test checklist

Press **Play** in Studio and check:

1. **Output shows the self-check passing.** You should see `[HoldService] 20 holds registered`, then a list of `[Stage1Check] PASS …` lines ending in **`[Stage1Check] 11 passed, 0 failed`**. Any `FAIL` line names the hold or part at fault.
2. **You spawn facing the wall.** You see a painted plywood wall with seams and a grid of T-nuts, shaped holds with bolts and chalk, a dark segmented crash mat with a green taped start box, floodlights on arms above the wall, and the route sign on the right. Walk behind the wall to see the steel frame, and look at its edges to see the plywood. Nothing should flicker as you move the camera. Your character is R15, with no R6 warning in Output.
3. **Hover inspector works.** Press H to turn it on, then move the mouse over any hold. It gets an outline and a tooltip with its type, id, `Quality`, whether hands/feet may use it, and its height in metres. The start jugs say **START**, the top jug says **FINISH**, and footholds show `Hands no`.
4. **Press H.** The inspector turns on (it starts off from Stage 2, so it doesn't get in the way of climbing). Press H again and it turns off. On a touch device, tap a hold instead of hovering. Hovering a hold's lip, bolt or chalk also selects the hold. Hovering a chalk smear or T-nut on the wall selects nothing.
5. **Attributes are visible in Studio.** While playing, select `Workspace.Routes.TestWall.Holds.05_Jug`. The Attributes panel shows `HoldType = Jug`, `Quality = 0.9`, `HandOK = true`, `FootOK = true`, `HoldId = TestWall_05`, `Role = Start`, and it has a `Grip` attachment.
6. **Robustness:** stop, set one hold's `HoldType` to `Banana` in edit mode (after building the wall in edit mode), then press Play. Output warns `invalid HoldType Banana; using Edge`, and the tooltip shows the hold as Edge. Undo afterwards.
7. **Re-run the check any time** from the server command bar during Play:
   `require(game.ServerScriptService.Server.Diagnostics.Stage1Check).Run()`

### Offline tests

These run without Studio, using the [Luau CLI](https://github.com/luau-lang/luau/releases) and Python 3:

```
cd roblox-climbing
python3 tests/run.py          # or: LUAU=/path/to/luau python3 tests/run.py
```

- `tests/unit.luau` (15 tests) covers hold types, the wall layout and the rate limiter.
- `tests/climbing.luau` (22 tests) runs the **real** `Config`, `ClimbMath` and wall-layout code with stand-ins for Roblox's `Vector3`/`Vector2` (`tests/mocks.luau`). It covers:
  - the body solver: resting poses, weight shift, never leaving a limb behind;
  - the floor clamp;
  - the dyno, including a 240 Hz physics integration check that the jump lands where it's aimed under Roblox gravity;
  - the free-limb spring (swings a little, then settles, and stays stable at low frame rates);
  - stamina (fewer limbs and worse holds drain faster, resting recovers, sensible times);
  - two-bone IK: hands land exactly on targets, elbows bend towards the pole, the arm straightens towards out-of-reach targets, and R6 single-bone limbs with real shoulder offsets;
  - a search over every limb/hold/shift combination proving the test wall can be climbed from the mat to the finish.

Expected: `ALL TESTS PASSED`.

---

## Climbing (Stage 2)

The climbing works like the reference video: third-person camera, and you **click and drag each limb onto a hold**.

| Control | What it does |
|---|---|
| **Drag a hand or foot** onto a hold | That limb grabs the hold. Rings show on your hands and feet when you're near the wall. |
| While dragging | Holds light up: **green** = a hand can reach it, **teal** = a foot can reach it, **red** = too far. Wrong-type holds stay unlit (footholds are feet-only, pinches hands-only). |
| Drop on empty wall | That limb lets go. With nothing held you fall off. |
| **Click a limb**, or press **Q / E / Z / C** | Selects left hand / right hand / left foot / right foot (yellow ring). Then click a hold. |
| **Click a hold** with nothing selected | The nearest free limb that can reach it takes it. That's also how you get on the wall from the mat. |
| **W A S D** | Shift your weight: the body moves around the holds. Use it to get a far hold in reach. |
| **Hold Space**, aim at a hold, release | Dyno. An ellipse grows around you while it charges. The aim dot turns **green** once the charge is enough to reach the hold under the cursor. On release you fly on a real ballistic arc, both hands reach for the hold, and the nearer hand grabs it when it's in reach. Too little charge falls short and you drop. |
| **V** | Let go of the wall. |
| Mobile | Drag limbs with your finger. Dyno and Let go appear as on-screen buttons while climbing. |
| Gamepad | A = dyno, B = let go. Gamepad limb placement comes in Stage 10. |

The height above the floor shows in a pill at the top centre while you climb.

**How it works**

- `ClimbService` (server) is the authority. It stores what each limb holds as character attributes (`Climb_LeftHand = "TestWall_05"`). It validates every request: rate limit, argument types, hold exists, right limb type, and within reach of the body plus a small latency allowance. It refuses everything else.
- **Animation** (`Client/Controllers/ClimbAnimator.luau`, `Shared/LimbRig.luau`): procedural, with no animation uploads. Every frame, after Roblox's own animations, every climber on screen is posed:
  - hands and feet go onto their holds with **two-bone IK**, so elbows bend down and out and knees go out to the side;
  - a limb moving to a new hold **reaches** for it: it lifts off the wall and arcs across;
  - free limbs hang and swing;
  - the torso leans into the wall, breathes, twists towards a reaching hand, and coils back while a dyno charges;
  - the head looks where you're reaching or aiming.

  Everything eases in and out, and control goes back to the normal walk animations when you let go. It works on **R6 and R15**, and with both kinds of joints Roblox uses: classic `Motor6D`, and the newer `AnimationConstraint` avatar joints. Other players see your climbing pose because each client poses climbers from their attributes.
- Startup is loud on purpose. Each server service starts on its own, so a failure prints `SERVER ERROR in <Service>` and the rest still runs. The client prints `[ClimbController] ready: R15 rig (AnimationConstraint joints), 4/4 limbs, 4 with elbows/knees` when climbing is set up. The server answers every grab, even ones it refuses, and a "Server didn't answer" message appears on screen if it ever doesn't.
- On-screen hints: "Click a hold to grab it…" near the wall, and the climbing controls while you climb.

**Fixed in v0.4** (both from your Output log):
- `couldn't find … 0/4 limbs`: Roblox's new avatars use `AnimationConstraint` joints instead of `Motor6D`. LimbRig now supports both.
- `the server didn't answer a grab`: Roblox fires `CharacterAdded` before the character is in Workspace. The server treated that as "gone" and never registered you, so it ignored every grab. That's also what broke v0.2's IKControls. The server now sets you up on demand and always replies.
- `ClimbController` (client) predicts each request so it feels instant, and rolls back if the server refuses. It holds the body with an `AlignPosition` + `AlignOrientation` at the spot `ClimbMath.solveBody` picks. That spot is between your hands and feet (or hanging below your hands), 1.1 studs off the wall, shifted by WASD, and never further than each limb can reach.
- Anti-cheat: if your body stays further than reach + 4 studs from what you hold for a second, the server takes you off the wall. For 2 seconds after a dyno, the server allows 4 extra studs of reach for the catch, because its copy of your position lags behind you in flight.
- **Arms and legs don't collide with the world** (collision group `ClimberLimbs`). IK can press hands and feet onto holds without the wall shoving the body around. The torso and head still collide.
- **Near the floor** (hanging from the start holds), the body stands on the mat instead of sinking into it.
- Roblox's own ladder climbing is switched off for the character, so it can't take over on wall features.
- **Camera**: third person only (zoom 6 to 40 studs), like the reference. It's set on `StarterPlayer` by the Rojo project. If you set things up by hand, set `CameraMinZoomDistance` to 6 there.
- Reach (studs from the HumanoidRootPart): hands **3.7**, feet **3.1**. These match a default R15 arm/leg at full stretch, so the IK can always actually touch a hold the game lets you take. All tuning is in `Config.Climb`.
- Rules this stage: **one hand** is enough to hang (shaky). Stamina makes that costly in Stage 3. Falling off the wall uses normal physics. Ropes, ragdoll and fall damage come in Stage 4.

The offline tests run the real solver over every limb, hold and WASD shift, and prove the test wall can be climbed from the mat to the finish jug with every hold reachable.

## Stamina, ragdoll and falls (Stage 3)

**Getting tired.** You have a grip stamina bar, the thin vertical bar beside your climber (blue → orange → red).
- It drains while you climb: faster with fewer limbs on (1 limb drains fast, 3 limbs slowly) and on worse holds (jugs are easy, crimps and slopers are hard).
- It **only refills when you rest**: all four limbs on holds, without moving one, for a moment. It refills faster on good holds, and quickly once you're off the wall.
- Each dyno costs 15.
- Below 25 your hands start to shake, you breathe harder, and you get a warning.
- **At zero you peel off the wall and fall.**

Stamina is worked out by the server (`StaminaService`), so it can't be cheated. All numbers are in `Config.Stamina`. Hanging off two edges with no feet lasts about 14 seconds; three limbs on jugs lasts much longer.

**Ragdoll.** You go limp (a real physics ragdoll; every joint becomes a limited ball socket so nothing bends backwards) when:
- you run out of stamina,
- a dyno misses,
- you let go more than about 1.7 m up.

**Falls** are measured from the top of the fall to where your feet land:
| Fall | What happens |
|---|---|
| under 2.5 m (9 studs) | nothing, like a normal jump |
| up to 4.2 m (15 studs) | knocked down, back up after about 2 seconds ("Ouch! 3.1 m fall") |
| 4.2 m or more | **dead**: the ragdoll crumples, the screen fades red with "You fell 5.6 m", respawn after 4 seconds |

Landing on a crash mat raises the lethal height by 20%. On the test wall that means falls from the top holds kill you, and falls from mid-wall knock you down.

**Free limbs** now hang on damped springs. They lag behind and swing when your body moves, then settle: a bit floppier than before, but not rag-doll floppy. All of this works on R6 and R15, with both kinds of joints. All tuning is in `Config.Falls`.

## The world, routes, ropes and saving

Everything is built by the server on Play if it's missing (`Gym`, `Outdoors`, `Crags`, `Routes` in Workspace). To bake it into the place in edit mode, run in the command bar: `require(game.ServerScriptService.Server.World.Gym).Rebuild()` and `require(game.ServerScriptService.Server.World.Outdoors).Rebuild()`.

**The gym** (you spawn on the Ascent logo): a modern gym with a glass front, white walls with charcoal and white oak, steel trusses and soft pendant lights.
- **Rope walls** at the back: the tutorial wall plus two tall walls (about 9 m, with overhangs) carrying four routes, 5b to 6b. Each route has an orange **auto-belay**.
- **Bouldering** on the left: 4 monoliths with 8 colour-coded problems (V0 to V5) over wall-to-wall padding.
- **Kilter room** at the back right: a 40° LED board behind glass with a lit problem, "First Light".
- **Pro shop**, **lockers**, a **café and lounge**, a training corner, and the freestanding leaderboard screen in the lobby.

**Outdoors**, through the yellow door: grass, paths, a pine forest, snowy mountains and three crags.
| Crag | Height | Routes |
|---|---|---|
| Wall A | ~15 m | Greywall Traverse (5a), Mossy Steps (4) |
| Wall B | ~35 m, with an overhang and a ledge | Sentinel Prow (6b), Split Pillar (6c) |
| The Colossus | ~280 m (El Cap scale): slabs, a 35° roof, 9 ledges | The Long Way Up (6a), Skyline Direct (7a) |
Every outdoor route has a rope bag, a chalk bucket and a leaderboard sign at its base. Holds are generated (`RouteGenerator`) so no move is longer than an arm's reach, even past ledges. Ledges let you pass through while you climb, and catch you if you let go above one, so they're places to rest and recover stamina.

**Routes.** Grab a route's low holds and the timer starts (top right; turn it off in the phone's Settings). The run ends if you fall, get caught by the rope, or end up back on the ground.
- **Finishing outdoors:** climb to the top, press **F** to climb up over the edge (hands on the lip, a knee up, stand up), walk to the orange **summit button** on its stone plinth (look for the flag) and click it.
- **Finishing indoors:** click the round orange button on the wall beside the top hold.
- Either way you get the **summit card**: your time, previous best, money and XP, and your leaderboard rank. A button pressed without a run going tells you to start from the bottom.

**Climbing up onto ledges.** Anywhere you climb, when your top hand is at a flat top with room to stand (a crag top, a big-wall ledge, the top of a bouldering monolith), the hint shows **F climb up** (gamepad: D-pad up). The server checks the spot and lets go of your holds, and you climb up and stand. Thin walls with no top to stand on just don't offer it.

**Phone.** Press **P** (or the PHONE button bottom left). Apps:
- **Controls:** every key.
- **Routes** (**M** opens it directly): every route with your best time, and **Go** to travel to its base.
- **Stats:** money, level, summits, metres climbed, best times.
- **Settings:** climbing hints, always show stamina, run timer.
Esc closes it.

**Ropes (optional).** You can free solo anything; nothing nags you to rope up. To rope up, just **click** the rope bag at the base of an outdoor route, or the orange carabiner hanging from an indoor auto-belay (click again to unclip, or tap the rope badge). You'll see a clipping-in animation.
- **Rope physics:** the rope is a real physics rope that sags with a little slack while you climb, because the belayer keeps it just loose. Fall or let go and you drop that slack, the rope stretches and bounces, and you swing on it.
- **Rope animations:** after a catch you flail and grab the rope. Then you sit back in your harness, feet braced on the wall. Then you're lowered: leaning back, walking down the wall step by step, brake hand feeding rope.
- **R** while roped: sit back on the rope and get lowered off (gamepad: X). Grab a hold any time to climb on.
- Outdoors you also see the belayer's side of the rope running from the anchor down to the bag. Auto-belays unclip you when you're back on the floor; rope bags untie you when you walk away.
- Climbing without a rope is free solo: fall from high up and it's fatal.

**Gear (pro shop).** Use **Browse gear** at the shop counter. Spend money (£) on:
| Slot | Items | Effect |
|---|---|---|
| Shoes | Rental, Trail Edge (60), Pro Downturn (250), Velvet Slipper (600) | up to 22% less stamina drain while a foot is on |
| Chalk | Basic bag, Big Bucket (80), Liquid Chalk Pro (300) | chalk lasts longer and helps more |
| Harness | Rental, Featherweight (120), Comp Harness (400) | dynos cost 15 → 12 → 9 stamina |
| Helmet | none, Roc (80), Aurora (150), Vapor (220) | survive falls 10% / 15% / 20% higher |
| Bags | Climbing Pack, Crag Pack (50), Expedition (90), Big Wall (150), Bravo DL 30 (220) | looks |
| Ropes | Yellow, Ocean Blue (30), Hot Pink (30), Stealth Black (60) | your rope's colour outdoors |

Everything is in `src/shared/Gear.luau`. Packs, helmets and chalk bags are **real climbing gear from the Roblox avatar catalog** (accessories load in any game), each in several colours, and the shop shelves display the real items. **Lockers:** use **Customise bag** at the bag station to pick your pack, its colour, your chalk bag (11 looks) and your helmet colour, all free, from pictures of the items. Your gear shows on your character for everyone, and the gym staff and the climbers at each crag camp wear it too.

**Pre-made models.** The furniture, plants, trees, rocks, tents and campfires are free Creator Store models (listed in `src/server/World/Props.luau`; scouted with `tools/world/scout.py`). `PropService` loads them when the server starts, scales each to fit its spot and stands it exactly on the floor. **To use them, publish the place and turn on Game Settings → Security → Allow Loading Third Party Assets.** Without that, every spot keeps a simple built-in stand-in (Output says so), so the world is always complete.

**Text.** Signs and screens use the sharp **Michroma** (titles) and **Sarpanch** (headings) fonts on canvases sized to each sign, so nothing is stretched.

**Weight shift sticks.** While climbing, WASD moves your weight and it stays where you leave it, so you don't have to hold the keys. **X** puts it back in the middle (gamepad: Y).

**Chalk.** Use any chalk bucket (**Chalk up**), or, since everyone carries a chalk bag, press **G** or the **CHALK** button bottom right to chalk up from your bag, even mid-climb (8 s cooldown). Full chalk makes your stamina drain 25% slower and wears off as you climb (`Config.Chalk`).

**Money and levels.** Summits pay money in pounds (more for higher routes, double on your first ascent) and XP. Money, level and chalk show in the strip at the top left. (The save field is still called `gems`, so old saves carry over.)

**Look.** All the screens share one flat, dark style (`src/client/Controllers/Style.luau`): near-black panels with hairline borders, one orange accent, Michroma/Sarpanch/Builder Sans/Roboto Mono fonts, and no emoji.

**Trees and props outside.** Every outdoor tree, rock and bush is a Creator Store model with backup models if one won't load. Placement keeps a footprint for each one, the crag faces, the route bases and the camps, so nothing overlaps (the world audit checks it: `propclash: 0`). Everything saves (`DataService`: one session-locked DataStore entry per player, autosaved). In Studio, saving needs **Game Settings → Security → Enable Studio Access to API Services**. Without it, progress and the leaderboards are kept in memory for the session (Output says so).

**Leaderboards.** Fastest times per route: on each route's sign and on the gym's leaderboard wall, refreshed every minute (OrderedDataStores).

All numbers live in `Config.Routes`, `Config.Rope` and `Config.Chalk`.

## Test checklist

Press **Play** and check:

1. Output ends with **`[Stage1Check] 11 passed, 0 failed`**, **`[Stage2Check] 14 passed, 0 failed`**, **`[Stage3Check] 4 passed, 0 failed`** and **`[Stage4Check] 13 passed, 0 failed`** (Stage4Check checks the gym, the crags, the shop, the click-to-clip ropes and that all 20 routes are complete, each with a finish button). With third-party assets allowed you'll also see `[PropService] N/N props use Creator Store models`. Stage2Check tests the remotes, the limb rig and IK on both an R15 and an R6 test dummy (it names the joint type it found), the limb collision group, 8 server reach/type cases and the body solver. You should also see `[ClimbController] ready: … 4/4 limbs` from the client.
2. **Get on the wall.** Walk onto the green start box. White/grey rings appear on your hands and feet. Drag your right hand onto a start jug (the green one with tape under it). The arm reaches for it and the body lifts into a hang.
3. **Feet.** Drag a foot onto a dark foothold below. Teal markers show which footholds that foot can reach. Your body settles between hands and feet.
4. **Reach rules.** Drag a hand towards the top jug. Its marker is red and dropping it shows "Out of reach". Drag a hand onto a foothold: no marker, and it's refused ("That hold is for feet").
5. **Weight shift.** Tap or hold W and the body moves up, and stays there when you let go. A/D move it sideways. X re-centres it. Holds that were red turn green as you shift towards them.
6. **Select and click.** Press Q (yellow ring on the left hand), then click a hold. Or click a hold with nothing selected, and the nearest limb that can reach it takes it.
7. **Let a limb go.** Drag a limb off a hold onto empty wall. That limb dangles and the body re-settles.
8. **Dyno.** Hold Space: the ellipse grows and a dot shows the aim. Point at a hand hold above. The dot is yellow while the charge is too low and turns green when it's enough. Release on green: you arc up, both hands reach for the hold, and one grabs it. Release early and you fall short onto the mat.
9. **V** drops you off the wall onto the mat.
10. **Multiplayer view.** Use Test → Clients and Servers → 2 players. Each player sees the other's arms and legs on the holds.
11. **Server authority.** Rejected requests show "Can't grab: …" and the limb snaps back.

12. **Clip in, then a timed route.** Click the orange carabiner at the tutorial wall: your hands go to your harness and a blue rope runs to the auto-belay. Climb from the bottom: the timer appears top right, and the rope sags a little below you. Click the orange button on the wall by the top hold: summit card. Press **R**: you sit back on the rope, then lean back and walk down the wall as it lowers you, then it unclips you.
13. **Ropes outdoors.** At Wall A (or M → Go), click the rope bag, climb a bit and press V: you drop the slack, bounce on the rope, flail, settle into the harness and get lowered. Then try a climb without clicking the bag: no rope, no reminder.
13b. **Shop and lockers.** At the pro shop counter, **Browse gear**: buy something once you have the money, and it's equipped straight away. At the lockers, **Customise bag**: change your pack, chalk bag and helmet looks, and see them on your back. Chalk up at a bucket for the chalk-dip animation.
14. **Chalk.** Chalk up at a bucket, or press **G** mid-climb: your hand dips into the bag, the strip top left shows chalk 100%, and it wears off as you climb.
14b. **Top out.** Climb Mossy Steps at Wall A to the top. **F climb up** appears; press F and you climb over the edge and stand. Walk to the flag and click the button: summit card. On a bouldering monolith, F at the top puts you on top of it.
14c. **Phone.** P opens it. Check Controls, Routes (Go travels), Stats and Settings (turn the run timer off and on).
15. **Leaderboards.** After a summit your name appears on the route's sign and on the gym's leaderboard wall within a minute.
16. **Big wall.** M → Go to The Long Way Up. Climb past the first ledge (you slide past it), let go just above it, and you land on it.

Run the checks again any time from the server command bar:
`require(game.ServerScriptService.Server.Diagnostics.Stage4Check).Run()`

---

## Checking the world without Studio

`tools/world` builds the whole world outside Studio with [Lune](https://lune-org.github.io), by running the real World modules, and checks it:
```
rojo build default.project.json -o /tmp/place.rbxlx
lune run tools/world/build.luau /tmp/place.rbxlx /tmp/world.json
python3 tools/world/audit.py /tmp/world.json      # parts through the floor, floating, clashing, over-bright lights
python3 tools/world/render.py /tmp/world.json /tmp/view.png --eye=0,20,60 --at=0,8,0 --terrain
```

## Still to come

From the design doc, not built yet: the iPad wall builder, picking problems on the Kilter board, the phone shop with delivery box, trad gear (cams, nuts) and lead clipping, the camera, skills and daily rewards, custom animation assets, sound, and mobile touch controls polish.
