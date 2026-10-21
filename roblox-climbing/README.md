# [YOUR GAME NAME]: Roblox climbing game

A skill-based rock climbing game for Roblox: four limbs placed one at a time, stamina, ropes, routes and leaderboards. It is built one stage at a time (see the design doc's Build Order).

**Current stage: 1, project structure plus one test wall with 20 tagged holds.**

Swap the placeholder name in `src/shared/Config.luau` (`Config.GameName`).

---

## Where everything goes

The project is set up for [Rojo](https://rojo.space) (7.4+), which syncs these files into Studio. Each file becomes one instance:

| File | Studio location | Instance type |
|---|---|---|
| `src/shared/Config.luau` | `ReplicatedStorage.Shared.Config` | ModuleScript |
| `src/shared/Tags.luau` | `ReplicatedStorage.Shared.Tags` | ModuleScript |
| `src/shared/HoldTypes.luau` | `ReplicatedStorage.Shared.HoldTypes` | ModuleScript |
| `src/shared/HoldUtil.luau` | `ReplicatedStorage.Shared.HoldUtil` | ModuleScript |
| `src/server/Main.server.luau` | `ServerScriptService.Server.Main` | **Script** |
| `src/server/Services/HoldService.luau` | `ServerScriptService.Server.Services.HoldService` | ModuleScript |
| `src/server/World/TestWall.luau` | `ServerScriptService.Server.World.TestWall` | ModuleScript |
| `src/server/World/TestWallLayout.luau` | `ServerScriptService.Server.World.TestWallLayout` | ModuleScript |
| `src/server/World/HoldModels.luau` | `ServerScriptService.Server.World.HoldModels` | ModuleScript |
| `src/server/World/Surfaces.luau` | `ServerScriptService.Server.World.Surfaces` | ModuleScript |
| `src/server/World/BuildUtil.luau` | `ServerScriptService.Server.World.BuildUtil` | ModuleScript |
| `src/server/World/Environment.luau` | `ServerScriptService.Server.World.Environment` | ModuleScript |
| `src/server/Diagnostics/Stage1Check.luau` | `ServerScriptService.Server.Diagnostics.Stage1Check` | ModuleScript |
| `src/client/Main.client.luau` | `StarterPlayer.StarterPlayerScripts.Client.Main` | **LocalScript** |
| `src/client/Controllers/HoldInspector.luau` | `StarterPlayer.StarterPlayerScripts.Client.Controllers.HoldInspector` | ModuleScript |

`Shared`, `Server`, `Services`, `World`, `Diagnostics`, `Client` and `Controllers` are plain **Folders**.

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
3. **Hover inspector works.** Move the mouse over any hold. It gets an outline and a tooltip with its type, id, `Quality`, whether hands/feet may use it, and its height in metres. The start jugs say **START**, the top jug says **FINISH**, and footholds show `Hands no`.
4. **Press H.** The inspector turns off. Press H again and it turns back on. On a touch device, tap a hold instead of hovering. Hovering a hold's lip, bolt or chalk also selects the hold. Hovering a chalk smear or T-nut on the wall selects nothing.
5. **Attributes are visible in Studio.** While playing, select `Workspace.Routes.TestWall.Holds.05_Jug`. The Attributes panel shows `HoldType = Jug`, `Quality = 0.9`, `HandOK = true`, `FootOK = true`, `HoldId = TestWall_05`, `Role = Start`, and it has a `Grip` attachment.
6. **Robustness:** stop, set one hold's `HoldType` to `Banana` in edit mode (after building the wall in edit mode), then press Play. Output warns `invalid HoldType Banana; using Edge`, and the tooltip shows the hold as Edge. Undo afterwards.
7. **Re-run the check any time** from the server command bar during Play:
   `require(game.ServerScriptService.Server.Diagnostics.Stage1Check).Run()`

### Offline unit tests

The pure-data modules (hold types and wall layout) have unit tests that run without Studio, using the [Luau CLI](https://github.com/luau-lang/luau/releases):

```
cd roblox-climbing
luau tests/unit.luau
```

Expected: `12 passed, 0 failed`.

---

## Coming in Stage 2

Limb selection (Q/E/Z/C) with a ring on the active limb, click-to-place on holds within reach (green/red hover), R15 `IKControl` arms and legs, WASD weight-shift driven by `AlignPosition`, and the first RemoteEvents (with rate limiting) for server-validated limb placement. These go in `ClimbService` (server) and `ClimbController` (client).
