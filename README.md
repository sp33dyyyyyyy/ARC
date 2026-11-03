# FRONTLINE FPV — Garage Warfare

A mid/low-poly drone-factory and FPV combat simulator for Windows, made with **Godot 4.3 (GDScript, Compatibility/OpenGL renderer)**.

You run a small drone workshop out of your home garage for the (fictional) **Kalvarian Volunteer Workshops**. You walk around the garage
in first person, unpack parts, assemble drones component by component on the workbench, tighten every screw, wire and tune them,
certify them on the test station, charge their batteries, and then fly them — in FPV — on test courses, reconnaissance runs and
arcade-style strike missions against the equipment of the (fictional) **Dravic Ironguard**. Missions pay credits and reputation;
you spend them on parts, contracts, upgrades and a bigger workshop.

```
GARAGE (walk) ─ workbench ─ BUILD → WIRE → SETUP → SAVE ─ rack ─ test station (diagnostics) ─ charger
   │                                                                                        │
   └─ computer: WORKSHOP OS ─ parts market → van delivers parcels → unpack into storage     │
                            ─ deployment map → FPV mission → recovered / damaged / lost ────┘
```

No third-party or paid assets are used: every mesh, texture, sound and the music is generated in code
(primitives, procedural noise, synthesised audio). All factions, regions, vehicles and equipment are fictional, and combat is
abstract (health/armour numbers and stylised, non-graphic hit effects) — nothing models real weapons, payloads or vulnerabilities.

---

## Running it

1. Install **Godot 4.3** (standard build, not .NET): <https://godotengine.org/download/archive/4.3-stable/>
2. `Import` this folder (`project.godot`) in the project manager and press **F5**.

Export a standalone Windows `.exe` with the included **Windows Desktop** preset (*Project > Export*), or from the command line:
```
godot --headless --path . --export-release "Windows Desktop" build/FrontlineFPV.exe
```
Saves go to `%APPDATA%\Godot\app_userdata\Frontline FPV - Garage Warfare\` (`career.json`, `save.json`, `settings.cfg`).

From the main menu: **START CAREER** (first time) / **CONTINUE CAREER**, **NEW CAREER**, the current **WORKBENCH**, **OPTIONS**.

---

## Controls

Every action has a keyboard/mouse slot and a gamepad slot and is rebindable in **Options > Controls** (rebinding only steals a key from
actions that are active at the same time, so walking on `W` and throttle on `W` coexist). Button names default to PlayStation glyphs
(**Options > Flight & Pad** switches to Xbox names). Every menu and Workshop OS app is navigable with the D-pad / left stick + Cross,
Circle goes back.

### On foot in the garage

| Action | PC | PS5 DualSense |
|---|---|---|
| Walk | `WASD` | Left stick |
| Look | Mouse | Right stick |
| Interact | `E` | Cross |
| Pick up / put down (drop) | `F` | Square |
| Place held item on the surface you look at | Left mouse | Cross (when nothing under the crosshair accepts it; a held parcel is opened instead) |
| Rotate held item | hold `R` + mouse | hold R1 + right stick |
| Secondary action / inspect | Right mouse | L2 |
| Sprint (hold) | `Shift` | L3 |
| Crouch (toggle) | `Ctrl` | R3 |
| Inventory (tablet, storage tab) | `Tab` | Triangle |
| Workshop tablet | `Q` | Touchpad |
| Pause | `Esc` | Options |

### Workbench (BUILD / WIRE / SETUP)

| Action | PC | Gamepad |
|---|---|---|
| Grab / place / tighten / select | Left mouse (click or drag) | Virtual cursor: left stick moves it, Cross clicks |
| Rotate held part | `R` | R1 |
| Orbit camera | Right-mouse drag | Right stick |
| Zoom | Mouse wheel | R2 / L2 |

### Flying (Mode 2)

| Action | PC | Gamepad |
|---|---|---|
| Throttle / yaw | `W` `S` / `A` `D` | Left stick (throttle = stick position, centre 50 %; optional rate mode in Options) |
| Pitch / roll | Arrow keys | Right stick |
| Arm / disarm | `Space` | Cross |
| Release mission module (pod) | `F` | R2 |
| Flight mode: Beginner → Intermediate → Acro | `B` | R1 |
| Self-level / acro toggle (legacy) | `V` | Square |
| Camera: FPV → chase → spectator | `C` | L1 |
| HUD on/off | `H` | Triangle |
| Mouse-as-sticks | `M` | – |
| Restart (bench test flights) | `F5` | Create |
| Pause / end mission | `Esc` | Options |

**F11** fullscreen, **F3** performance overlay.

---

## The garage (Map 1)

A walkable, fully lit home garage on a suburban lot, with a driveway, a road the delivery van uses, and an outdoor test pad with practice
gates. Equipment is built on one reusable interaction framework (`Interactable` bodies with prompt/use/secondary/accept/pick callbacks and
`Pickable` physics items) with a hover glow and on-screen prompts that show the right key or button.

| Thing | What it does |
|---|---|
| **Cupboard & drawers** (under the bench) | Open/close with animation. The **starter kit** box is in the cupboard; tools live in the drawers. |
| **Parcels** | Pick up, carry, place on any surface, rotate, drop. Open them **inside** the garage: flaps open, the parts pop out into storage. |
| **Workbench** | `E` sits you at the bench with the current build. `RMB` loads a drone from the rack; bringing a held drone puts it on the bench. |
| **Computer** | Opens **WORKSHOP OS** (below). |
| **Storage shelves** | Labelled bins show live stock per category; `E` inspects a bin. |
| **Drone rack** | Every saved drone is shown as its real 3D build with its name. `E` options (set active, to bench, inspect, remove battery), `F` picks it up, `RMB` inspects. |
| **Charging station** | Remove a battery from a drone (rack menu), carry it to a dock (`E`), watch the LED and percentage, take it back and refit it to its drone. |
| **Test station** | Carry a drone to it and press `E`: animated diagnostics (power, FC, link, video, motor spin test, structure, battery) and a report. Passing certifies the drone for deployment. |
| **Garage door / light switch / bench lamp** | Roll-up door with rumble, fluorescent lights that flicker on, a desk lamp. |
| **Deployment case** | Opens the deployment map (or pack a held drone into it). |
| **Outdoor test pad** | Test flights with the active drone: Shakedown, Gate Race, Battery Challenge, Free Flight. |
| **3D printer** (Level 2) | Prints mounts and prop guards for filament credits; the head moves while printing. |
| **Assembly station** (Level 3) | Animated arms; works the automated production orders. |
| **Delivery van** | Drives in when an order arrives, honks, drops the parcel on the driveway and leaves. |

The **tablet** (`Q` / touchpad) shows the career guide, deliveries and ETAs, charging, printing and production, the full inventory and
salvage bin (repair / recycle), and the roster. Notifications pop up on the right. Layout (parcels, tools, batteries, drones left on the
floor, door and light state) is saved. Time of day runs while you're in the garage and is shown on the sky through the open door.

**Tutorial.** On the first career start the **HOW TO PLAY** guide opens (nine chapters with your current key and button
bindings; also on the main menu, `F1` / Create in the garage, the pause menu and the tablet). A **step card** (bottom-left)
and a **floating arrow** over the right object walk a new player through the first loop (starter kit → build → save →
certify → shakedown → first mission → buy parts → repair → contract → Level 2). The workbench has a live **bench guide**
line ("open the Motors tab…", "tighten the screws on…"), the first flights show a **flight school** card for the current
flight mode, a whiteboard in the garage lists the build steps, and loading screens show tips. All hints can be switched off
in **Options > Gameplay**.

---

## Building drones (the workbench)

Parts come from **garage storage** — the tray shows how many of each you own, and installing consumes them.

* Required parts: **frame, 4 motors (2 CW + 2 CCW), 4 props, ESC, flight controller, receiver, VTX, antenna, camera mount, camera, battery**.
  Optional: **protection** (prop guard rings or armour plates) and a **mission module** (training drop pod, twin rack, heavy pod, recon sensor pod).
* Drag or click a part to its glowing slot; `R` rotates it until its arrow matches the yellow marker. Compatibility is enforced
  (spin direction, matching motor/prop models, stack order, digital camera needs a digital VTX, whoops can't take guards or drop modules,
  the heavy pod needs a 7" or armoured frame).
* After placing a part its **screws glow**: click (or hold) the part and a screwdriver drives them one by one (the *Power screwdriver*
  upgrade does all of a part at once). WIRE and SAVE need every part secured.
* **Repair tool**: hold on a damaged part to restore it for credits. **Paint frame** cycles colours. **Strip build** returns everything to
  storage (damaged parts to the salvage bin). Lifting a damaged part off sends it to salvage when you drop it in the tray.
* WIRE and SETUP are the original pad-wiring and Betaflight-style tuning stages. **TEST FLY** flies the bench build on the testing grounds;
  **SAVE DRONE** names it and puts it on the rack (optionally also saving a production preset).

Builds have real trade-offs: mass, thrust-to-weight, hover current and endurance, top speed, agility, durability, control range
(2.4 GHz vs long-range receiver), video range (antenna gain, analogue vs digital), camera tilt and vibration (mount, FC), crash tolerance
(guards/armour) and module payload. Damaged parts reduce motor thrust, add vibration and video noise, cut battery capacity and cause
control glitches. The drone you fly is always the saved build, paint and damage included.

---

## WORKSHOP OS (the computer)

| App | What it does |
|---|---|
| **PARTS MARKET** | Fictional manufacturers (Kestrel Dynamics, Voltforge, Aerofoil Works, Hexacore Labs, Stepline Radio, Lumen Optics, Boreal Cells, Ironweave). Each product has price, quality, mass, specs, compatibility notes, daily stock, a rotating 3D preview, and a garage-level tier. Cart → order → courier ETA. Storage space is limited. |
| **DRONE MANAGER** | Roster with 3D preview and full spec sheet, damage list, rename, set active, save as preset, duplicate (production order), repaint, compare two drones, disassemble. |
| **FACTORY ORDERS** | Customer contracts (racing, training, camera, reconnaissance, utility drones with spec requirements — each drone shows why it does or doesn't qualify), production orders from presets (required/available/missing parts, estimated cost, "order the missing parts"), automated assembly from Level 3, preset management. |
| **DEPLOYMENT MAP** | Missions by region with difficulty, conditions (time, weather, wind), rewards, recovery rules, objectives, a briefing map, drone selection with readiness checks and module rearm cost. |
| **INVENTORY** | Stock per category (sell back at half price) and the salvage bin (repair or recycle). |
| **DIAGNOSTICS** | Virtual checks and the performance report for any drone (certification itself needs the physical test station). |
| **FINANCES** | Balance, recent income/spending, fleet and stock value, statistics, full ledger. |
| **GARAGE UPGRADES** | Levels 1–5 (Home Garage → Improved Workshop → Small Drone Factory → Advanced Drone Production Garage → Professional Drone Development Facility), each adding visible equipment, rack slots, charging docks, storage and market tiers; plus one-off upgrades (power screwdriver, fast charger, extra shelving, bulk supplier, express courier, faster assembly). |
| **SETTINGS** | Opens the options. |

---

## Missions and maps

| Map | Missions |
|---|---|
| **Garage & Testing Grounds** — hills, lake, the garage property | Shakedown Flight (6 gates + land on the pad), Gate Race, Battery Challenge, Free Flight |
| **Rural Conflict Zone — Vessa Lowlands** — fields and hedgerows, valley road, farm, village, checkpoint, training range | Training Range: Static Targets, Eyes on the Road (recon), Convoy Interdiction, Iron Column, Free Flight |
| **Industrial Conflict Zone — Korvo Works** — warehouses, factory hall, chimneys, container yard, rail tracks, helipad | Radar Blackout (with a video-jamming mast), Warehouse Recon, Rotor Hunt, Transport Hunt, Free Flight |

* **Deployment**: a short intro shot of your drone at the field launch point, then FPV. Missions unlock in sequence.
* **Targets** (all fictional): Strelka utility truck, Korsak light armoured carrier, Bastion tracked transport, IG-70 Warden tank,
  Okulus mobile radar, Vespa-9 scout helicopter, Tarn-4 transport helicopter, Kestra patrol UAV, radar installation, jammer mast,
  empty guard tower, range target structures, unoccupied supply containers, field communications unit.
* **Vehicles** drive the road in convoys (followers keep their gap, slow for wrecks, speed up when alerted). **Helicopters** sit on the
  helipad spooling up, take off, climb, fly a patrol loop with banking and altitude changes, hover, return and land; when they notice the
  drone they climb and speed up; when defeated they spin down to a crash. **UAVs** orbit high.
* **Damage states**: smoke below ~55 % health, fire below 25 %, then a stylised blast (flash, shock ring, sparks, dust, debris) and a
  charred wreck that keeps smoking. Objective kills trigger a short slow-motion **cinematic**.
* **Attacks are abstract**: release a pod from the mission module (`F` / R2) — the HUD shows a predicted-impact reticle that turns red
  over a target — or fly into a target (impact strike; the drone is expended). Damage = module power × falloff × (1 − armour).
* **Recon**: keep a target centred in view within range to fill its scan ring (the recon pod and digital cameras scan faster/further).
* **Return to launch**: after the objectives, land at the launch point to recover the drone. Training missions always recover crashed
  drones; in **contested** missions a drone that goes down away from the launch point is **lost** (removed from the roster). Rewards are
  paid as soon as the objectives are done.
* Conditions: dawn / noon / dusk, clear / overcast / fog / rain (particles), wind with gusts and turbulence that push the drone around.

---

## Flight

* Original physics model kept: four thrust vectors, 240 Hz rigid body, rate PIDs with gyro/D-term filtering, live power budget and
  voltage sag, battery cut-off, prop-wash; plus wind/gusts, per-motor health, building collisions and per-build crash tolerance.
* **Beginner**: self-level with a 32° tilt limit and **altitude hold** (throttle centre = hover, up climbs, down descends). **Intermediate**:
  self-level, manual throttle. **Acro**: rate mode. Default in Options; cycle in flight with `B` / R1.
* **Cameras**: FPV (analogue break-up with distance and terrain, or the **digital** link — sharp, then macro-blocking — when an HD VTX is
  fitted), chase, spectator; crash replays and a **cinematic replay** of the whole flight from the result screen.
* **OSD**: speed, altitude, battery, amps, mission/objectives, crosshair, compass with objective bearing, target brackets with health/scan
  progress and distance, off-screen objective arrows, pod count — each element can be switched off in **Options > Flight & Pad**.
* Crashes damage parts depending on impact speed, direction (nose hits hurt the camera), frame durability and guards. The battery's
  charge carries over between flights — charge it at the docks.
* Controller vibration on arming, gates, hits, kills, parcels, doors and pick-ups (toggle in Options).

---

## Options

Seven tabs: **Display** (window mode, V-Sync, frame-rate cap, brightness, flight and garage FOV, HUD), **Graphics** (preset,
**Safe graphics** for weak or crash-prone drivers, render scale, shadows, shadow quality, MSAA, view distance, tree density,
glow, fog, particle amount), **Audio** (master, music, effects, vehicles & ambience, mute in background), **Gameplay**
(difficulty, autosave, tutorial hints and arrows, units, head bob, camera shake, clock), **Flight & Pad** (default flight
mode, mouse sticks, invert pitch, absolute pad throttle, dead zone, stick expo, vibration, PlayStation/Xbox names, look
sensitivity, crouch/sprint toggle or hold), **OSD** (each flight display element) and **Controls** (every binding).
`FrontlineFPV.exe -- --safe` starts with Safe graphics on.

## Performance

Compatibility renderer (OpenGL 3.3) so it starts on any GPU. Graphics presets Low / Medium / High (shadows, MSAA, render scale, tree
count, terrain resolution, draw distance, glow), auto-picked on first launch. Terrain is chunked, trees are MultiMeshes, buildings are
simple boxes with grid-bucketed collision, particles are CPU particles, and worlds build over several frames behind a progress bar.

---

## Automated checks

```
# rules, settings/save robustness, keybind persistence
godot --headless --path . res://tests/logic_test.tscn
godot --headless --path . res://tests/logic_test.tscn -- read

# flight / power model numbers
godot --headless --path . --script res://tests/sim_test.gd

# mission / battery / crash logic in the real FlyStage, and the whole career loop
godot --headless --path . res://tests/driver.tscn -- /tmp race_complete gate_miss battery_complete battery_flat rx_off crash_breaks_prop soft_landing e2e

# screenshots (needs a display or xvfb):
godot --path . res://tests/driver.tscn -- <out_dir> garage garage_interact garage_os garage_delivery bench_new fly_rural fly_industrial fly_strike_loss
```

`e2e` drives the full first-playable loop through the game code: open the starter kit, assemble a drone on the bench (consuming storage,
tightening screws), wire and save it, certify it on the test station, fly the Shakedown, fly the training range and get paid, order parts
and receive the van delivery, repair a damaged motor, and reload the save.

---

## Project layout

```
project.godot, export_presets.cfg, icon.svg
scenes/main.tscn              single scene; everything else is built in code
shaders/analog_fx.gdshader    analogue / digital FPV video effects
scripts/autoload/             Settings (+keybinds/OSD), SaveData (records), Audio (procedural), Game (bench state, flight context),
                              Career (economy, roster, deliveries, contracts, levels, guide), Pad (gamepad glyphs, rumble, cursor)
scripts/data/                 Parts (catalogue, slots, compatibility, stats), Campaign (missions, levels, upgrades, contracts),
                              MeshFactory (part meshes), DroneVisual (assembled drone, paint, damage)
scripts/garage/               Garage (the hub), GaragePlayer, Interactable, Pickable, GarageKit (furniture, van, materials)
scripts/workshop/             Workshop, BuildStage, WireStage, SetupStage
scripts/fly/                  FlyStage, FlyWorld (3 maps), DroneSim, FlightMath, Missions, MissionRunner, CombatTarget,
                              VehicleKit (vehicle models), Fx (particles), Hud
scripts/ui/                   WorkshopOS, Tablet, ContextMenu, DiagnosticsPanel, theme, main menu, options, charts
tests/                        logic/sim tests and the driver (visual + end-to-end)
```

---

## Notes and limits

* Combat, damage and equipment are deliberately abstract and fictional; missions are game objectives, not procedures.
* Wiring is the simplified pad-to-pad harness from the original game; the receiver and antenna are plug-in parts.
* The workbench can't be relocated yet, and the forest, mountain and urban maps are future work.
* The Windows build is unsigned and wasn't run on real Windows hardware here (the screenshots come from Linux/Xvfb with Mesa).
