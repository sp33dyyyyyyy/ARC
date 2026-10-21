# [YOUR GAME NAME]: Roblox climbing game

A skill-based rock climbing game for Roblox: four limbs placed one at a time, stamina, ropes, routes and leaderboards. It is built one stage at a time (see the design doc's Build Order).

**Current stage: 2, limb-by-limb climbing (click and drag each hand/foot onto holds), weight shifting and dynos, on the realistic test wall from Stage 1.**

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
| `src/shared/ClimbMath.luau` | `ReplicatedStorage.Shared.ClimbMath` | ModuleScript |
| `src/shared/Remotes.luau` | `ReplicatedStorage.Shared.Remotes` | ModuleScript |
| `src/shared/RateLimiter.luau` | `ReplicatedStorage.Shared.RateLimiter` | ModuleScript |
| `src/shared/LimbRig.luau` | `ReplicatedStorage.Shared.LimbRig` | ModuleScript |
| `src/server/Services/ClimbService.luau` | `ServerScriptService.Server.Services.ClimbService` | ModuleScript |
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
| `src/client/Main.client.luau` | `StarterPlayer.StarterPlayerScripts.Client.Main` | **LocalScript** |
| `src/client/Controllers/HoldInspector.luau` | `StarterPlayer.StarterPlayerScripts.Client.Controllers.HoldInspector` | ModuleScript |
| `src/client/Controllers/ClimbController.luau` | `StarterPlayer.StarterPlayerScripts.Client.Controllers.ClimbController` | ModuleScript |
| `src/client/Controllers/ClimbOverlay.luau` | `StarterPlayer.StarterPlayerScripts.Client.Controllers.ClimbOverlay` | ModuleScript |
| `src/client/Controllers/ClimbAnimator.luau` | `StarterPlayer.StarterPlayerScripts.Client.Controllers.ClimbAnimator` | ModuleScript |

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
- `tests/climbing.luau` (16 tests) runs the **real** `Config`, `ClimbMath` and wall-layout code with stand-ins for Roblox's `Vector3`/`Vector2` (`tests/mocks.luau`). It covers:
  - the body solver: resting poses, weight shift, never leaving a limb behind;
  - the floor clamp;
  - the dyno, including a 240 Hz physics integration check that the jump lands where it's aimed under Roblox gravity;
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

## Stage 2 test checklist

Press **Play** and check:

1. Output ends with **`[Stage1Check] 11 passed, 0 failed`** and **`[Stage2Check] 14 passed, 0 failed`**. Stage2Check tests the remotes, the limb rig and IK on both an R15 and an R6 test dummy (it names the joint type it found), the limb collision group, 8 server reach/type cases and the body solver. You should also see `[ClimbController] ready: … 4/4 limbs` from the client.
2. **Get on the wall.** Walk onto the green start box. White/grey rings appear on your hands and feet. Drag your right hand onto a start jug (the green one with tape under it). The arm reaches for it and the body lifts into a hang.
3. **Feet.** Drag a foot onto a dark foothold below. Teal markers show which footholds that foot can reach. Your body settles between hands and feet.
4. **Reach rules.** Drag a hand towards the top jug. Its marker is red and dropping it shows "Out of reach". Drag a hand onto a foothold: no marker, and it's refused ("That hold is for feet").
5. **Weight shift.** Hold W and the body moves up. A/D move it sideways. Holds that were red turn green as you shift towards them.
6. **Select and click.** Press Q (yellow ring on the left hand), then click a hold. Or click a hold with nothing selected, and the nearest limb that can reach it takes it.
7. **Let a limb go.** Drag a limb off a hold onto empty wall. That limb dangles and the body re-settles.
8. **Dyno.** Hold Space: the ellipse grows and a dot shows the aim. Point at a hand hold above. The dot is yellow while the charge is too low and turns green when it's enough. Release on green: you arc up, both hands reach for the hold, and one grabs it. Release early and you fall short onto the mat.
9. **V** drops you off the wall onto the mat.
10. **Multiplayer view.** Use Test → Clients and Servers → 2 players. Each player sees the other's arms and legs on the holds.
11. **Server authority.** Rejected requests show "Can't grab: …" and the limb snaps back.

Run the checks again any time from the server command bar:
`require(game.ServerScriptService.Server.Diagnostics.Stage2Check).Run()`

---

## Coming in Stage 3

Stamina and grip: per-arm pump that drains by hold type and quality, number of limbs on, body stretch, wall angle and cut feet. A stamina bar next to the climber that goes blue to orange to red. Resting on jugs and stances recovers. An arm at zero lets go.
