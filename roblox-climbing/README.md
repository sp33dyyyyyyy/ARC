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
4. Apply the three Studio settings above.

Names matter: the scripts find each other by name (`script.Parent.Services.HoldService`, and so on).

### Optional: build the wall in edit mode

To see and tweak the wall without pressing Play, run this in the **Command Bar** (View → Command Bar):

```lua
require(game.ServerScriptService.Server.World.TestWall).Rebuild()
```

It creates `Workspace.Routes.TestWall`, plus `TestFloor`/`TestSpawn` if needed, and saves them with the place. Once the wall exists, the server leaves it alone, so hand edits survive. Run `Rebuild()` again to reset it. To change the angle, edit `Config.TestWall.AngleDegrees` (for example `15` for an overhang or `-10` for a slab) and rebuild.

---

## The test wall

```
Workspace.Routes.TestWall          Folder  (RouteName, Grade, HeightStuds, HeightMeters, Indoor)
├── Wall                           Part, tag Climbable, 16 x 24 studs (6.7 m)
├── Holds/                         20 Parts, tag Hold
│     01_Foothold … 20_Jug         attributes HoldType, Quality, HandOK, FootOK, HoldId, Role
│     └── Grip                     Attachment (added by HoldService): where the hand/foot goes
├── CrashMat                       Part
├── StartPad                       Part, tag RouteStart
├── TopLedge                       Part to stand on after topping out
├── Summit                         invisible Part, tag RouteSummit
└── Legend                         sign with the hold colour key
```

Hold colours on the test wall follow the type: **Jug** green, **Edge** yellow, **Crimp** red, **Sloper** blue, **Pinch** magenta, **Pocket** orange, **Foothold** dark grey, **Crack** black. Every type appears at least once. There are 2 start jugs (`Role = "Start"`) and 1 finish jug (`Role = "Finish"`). No move is longer than 3.6 studs, so the wall can be climbed without a dyno.

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
2. **You spawn facing the wall.** It is a white wall with coloured holds, a blue crash mat, a green start pad and the legend sign on the right. Your character is R15, with no R6 warning in Output.
3. **Hover inspector works.** Move the mouse over any hold. It gets an outline and a tooltip with its type, id, `Quality`, whether hands/feet may use it, and its height in metres. The start jugs say **START**, the top jug says **FINISH**, and footholds show `Hands no`.
4. **Press H.** The inspector turns off. Press H again and it turns back on. On a touch device, tap a hold instead of hovering.
5. **Attributes are visible in Studio.** While playing, select `Workspace.Routes.TestWall.Holds.05_Jug`. The Attributes panel shows `HoldType = Jug`, `Quality = 0.9`, `HandOK = true`, `FootOK = true`, `HoldId = TestWall_05`, `Role = Start`, and it has a `Grip` attachment.
6. **Robustness:** stop, set one hold's `HoldType` to `Banana` in edit mode (after building the wall in edit mode), then press Play. Output warns `invalid HoldType Banana; using Edge`, and the hold shows as Edge. Undo afterwards.
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
