# Propwash Workshop

A first-person FPV drone game for Windows, made with **Godot 4.3 (GDScript, Forward+ 3D renderer)**.
You build a quadcopter on a workbench, wire it, configure the flight controller in a Betaflight-style
menu and then fly it with a live power budget. Crash or run the battery flat and you are back at the
bench with the same drone.

```
BUILD  ->  WIRE  ->  SETUP  ->  FLY   (crash / flat battery -> back to the workshop, same drone)
```

No third-party or paid assets are used: every mesh, texture, sound and the music is generated in code
(primitives, procedural noise, synthesized audio).

---

## Running it

### In the editor
1. Install **Godot 4.3** (standard build, not .NET): <https://godotengine.org/download/archive/4.3-stable/>
2. `Import` this folder (`project.godot`) in the Godot project manager and press **F5**.
   The first import takes a few seconds (it builds the global-class cache).

### Exporting a standalone Windows `.exe`
1. In the editor: **Editor > Manage Export Templates > Download and Install** (Godot 4.3.stable templates).
2. **Project > Export...** — a **Windows Desktop** preset is already defined in `export_presets.cfg`
   (64-bit, PCK embedded in the exe, so the result is a single file).
3. Press **Export Project**, choose `build/PropwashWorkshop.exe` (untick *Export With Debug*).
4. Run the exe. Settings and progress are written to `%APPDATA%\Godot\app_userdata\Propwash Workshop\`
   (`settings.cfg` and `save.json`).

Command line (same result, handy for CI):
```
godot --headless --path . --export-release "Windows Desktop" build/PropwashWorkshop.exe
```
The preset has `application/modify_resources` switched off so it exports from any OS without `rcedit`/Wine.
If you want a custom exe icon/metadata on Windows, install `rcedit`, set it under
*Editor Settings > Export > Windows*, supply a `.ico` and switch that option back on.

> Verified in the build environment: the project imports clean, the whole flow runs under a software
> Vulkan driver, and `--export-release` produces a valid 64-bit PE executable. The produced `.exe`
> itself could not be launched there (the sandbox is Linux), so please give it a spin on Windows.

---

## Requirements / performance

* Windows 10/11 64-bit, Vulkan 1.1 capable GPU (target: GTX 1060 / RX 580 class at 60 fps).
* Default window 1920x1080 (UI scales with the window; smaller screens get a 90 % window). **F11** toggles fullscreen.
* **Options > Game > Graphics preset** — *Low / Medium / High*:

| Preset | Shadows | MSAA | 3D render scale | Trees | Terrain mesh | Draw distance | Glow / SSAO |
|---|---|---|---|---|---|---|---|
| Low    | off | off | 75 % (FSR 1.0) | 140 | 6 m grid | 420 m | off |
| Medium | 2048 PSSM | 2x | 100 % | 320 | 5 m grid | 650 m | off |
| High   | 4096 PSSM | 4x | 100 % | 520 | 3 m grid | 900 m | on |

Terrain is chunked (frustum-culled), trees are two `MultiMesh`es, the flight model costs ~25 µs per 240 Hz step.
The terrain is generated when a flight starts (about a second on Medium).

---

## Controls (all rebindable in **Options > Controls**; saved to `user://settings.cfg`)

Every action has one **Keyboard/Mouse** slot and one **Gamepad** slot. Binding a key that is already in use
un-binds it from its old action. Gamepad: any standard (XInput/DualShock/etc.) pad.

| Action | Keyboard / mouse (default) | Gamepad (default) |
|---|---|---|
| Throttle up / down | `W` / `S` | Left stick up / down |
| Yaw left / right | `A` / `D` | Left stick left / right |
| Pitch forward / back | `Up` / `Down` | Right stick up / down |
| Roll left / right | `Left` / `Right` | Right stick left / right |
| Arm / disarm | `Space` | `A` |
| Fine stick (hold) | `Shift` | – |
| Self-level (angle) / acro mode | `V` | `X` |
| Mouse-as-sticks toggle | `M` | – |
| HUD on/off | `H` | `Y` |
| Restart mission | `F5` | Back |
| Pause / back | `Esc` | Start |
| Fullscreen | `F11` | – |
| Grab / place / select (workshop) | Left mouse | – |
| Rotate held part | `R` | – |
| Orbit camera (hold) | Right mouse (drag) | – |
| Zoom | Mouse wheel | – |
| Motor test 1-4 (hold, Setup > Motor) | `1` `2` `3` `4` | – |

* **Throttle is non-spring** (like a real radio): `W`/`S` or the left stick *raise/lower* it and it holds.
* Keyboard pitch/roll/yaw are smoothed (about 0.15 s to full deflection); hold `Shift` for half deflection.
* **Mouse stick mode** (Options or `M`): the pointer offset from the screen centre is pitch/roll (the pointer is
  confined and hidden). *Mouse sensitivity* scales the deflection.
* **Acro (rate) mode is the default**; rates (center sensitivity / max rate / expo per axis) are set in **Setup > PID**. For keyboard beginners `V` (or Setup > Firmware)
  switches to **Angle (self-level)** mode, where the sticks command tilt and the same rate PIDs do the work.

---

## The four stages

### 1. BUILD
Green cutting-mat grid, wood-panel backdrop, 3/4 camera (right-drag orbits, wheel zooms). Parts live in a **3D tray**
at the bottom of the screen; pick a category (Frame, Motors, Props, ESC, Flight ctrl, VTX, Camera, Battery).
**Click or drag** a part to a glowing slot. Each slot shows a **blue marker** (attach point) and a **yellow marker**
(orientation: a spin arrow for motors/props, a forward arrow for everything else). Press **R** to rotate a held part until its
white arrow matches the yellow one. Parts snap on release; wrong placements flash red, shake and **bounce back** to the tray with a message.
Click an installed part to pick it up again (parts that depend on it return to the tray too).

* Frames: 5" carbon X (default) + 3" ducted whoop and 7" long-range (unlocks).
* Motors: 2306 2400KV (default), 2207 1800KV, 2806 1300KV — each exists as a CW and a CCW motor (arrow on the bell).
* Props: 5143 tri-blade yellow (default), 5040 bi-blade orange — CW and CCW versions.
* 4-in-1 ESC (M1-M4 pads, ESC1-4 chips, CUR pin, C BAT pad), flight controller (motor pad row, gyro chip), VTX with antenna,
  FPV camera, 4S LiPo (1100 / **1500** / 2200 mAh).
* **Spin direction is enforced**: M1 and M4 are CCW, M2 and M3 are CW (Betaflight "props in"). A motor's arrow must match its slot and
  the prop's spin must match the motor's arrow. All four motors must be the same model, all four props the same model.
* Stack order is enforced bottom-up (ESC, FC, VTX, battery); props need their motor first.

### 2. WIRE
The stack is shown exploded. Click a pad, then the pad it connects to. Cables are coloured tubes; the four pre-soldered motor
leads run along the arms. Wrong pairings **flash red** and are refused with an explanation.

| Wire | Colour |
|---|---|
| FC M1/M2/M3/M4 -> ESC S1/S2/S3/S4 (4-wire pad harness) | yellow / green / blue / white |
| Battery red -> ESC BAT+, black -> ESC BAT- | red / black |
| VTX -> FC UART pad | blue |
| Camera -> FC CAM pad | yellow |
| ESC CUR -> FC CURR (optional) | white |

Battery leads on the **C BAT** (capacitor) pad, power onto signal pads, M1 on S2 etc. are all rejected. Click a connected pad to unplug it.
Without the optional CUR wire the HUD's *total* current reads `--.- A` (per-motor amps still work via the ESC telemetry on the harness).

### 3. SETUP (Betaflight-style, UI only)
Tabs **Firmware** (board/airframe summary, presets, camera angle), **Gyro** (live 3D wireframe + roll/pitch/yaw, gyro low-pass filter),
**Port** (VTX UART, receiver UART, VTX power), **PID** (P/I/D per axis, rates with expo, rate-curve plot and a *simulated step response* that
visibly rings when the tune is bad) and **Motor** (four vertical bars + sliders; hold `1-4` to spin a motor and check wiring/spin direction).
Pick a mission and press **SAVE & FLY**.

### 4. FLY
First-person camera from the nose with an up-tilt (default 20°, adjustable in Setup > Firmware; the FOV also widens by up to 5° with speed).
**Analog FPV effect** (noise, horizontal tearing, chroma bleed, scan lines) grows with distance from the pilot and when terrain blocks the link.
HUD: crosshair, speed (km/h), altitude (AGL), battery voltage bar, live total amps, per-motor amp labels (updated every frame), throttle gauge,
mission info. `H` hides it. `Esc` pauses.

**Missions** (best times and unlocked parts are saved to `user://save.json`):
* *Free flight* over hills, trees and a lake.
* *Gate race*: 12 rings in order against a timer (par shown). Finishing unlocks the 3" whoop frame, 2207 motors, 5040 props and the 2200 mAh pack.
* *Battery challenge*: a ~3.3 km, 17-checkpoint route on **one** pack. Finishing unlocks the 7" frame and 2806 motors.

---

## Flight and power model (summary)

* X-quad, four thrust vectors, rigid-body integration at 240 Hz. Thrust/motor = `T_ref · (KV/2400)^1.3 · (prop diameter)^3 · prop factor` at 100 % rpm and
  scales with rpm² (rpm ∝ throttle × pack voltage). Prop reaction torque gives yaw. Rate-mode PID (P, I, D-on-measurement) with a gyro low-pass,
  a D-term low-pass, throttle/voltage gain scheduling, and airmode-style mixer compression.
* Current per motor: `0.1 A + I_full · rpm^2.2 · (16.8 V / V_pack)`; `I_full` follows thrust^1.5 and falls with prop size. Default 5" build: **~0.1 A/motor idle,
  ~17 A/motor and ~70 A total at full throttle**, ~7-8 A total hover.
* Battery: 4S LiPo, open-circuit voltage from a charge curve, internal resistance (**voltage sags under load**), mAh integration, **cut-off at 3.2 V/cell**
  on a 0.45 s-filtered terminal voltage — below it the ESCs stop and the drone falls. An ESC/pack current limit (60 A per Ah) protects mismatched builds.
* Heavier builds hover at a higher throttle (more current), climb and accelerate slower and drain the pack faster; the 2200 mAh pack proves it.
* Impacts into a surface faster than **7 m/s (≈25 km/h)** crash: 1-4 props break (those facing the impact first), then a slow-motion chase-cam **replay** of the
  last ~4 s plays, then the workshop. Gentle landings are fine. Water contact ends the flight too.

---

## Assumptions I made (the brief left these open)

1. **Units/scale** — workshop 1 unit = 1 cm, flight world in metres. The tray is its own 3D viewport so parts never clip into the bench.
2. **Prop size follows the frame** (the prop part auto-sizes to 3"/5"/7"); thrust uses the prop's diameter. The ducted whoop gets a x1.8 thrust bonus (ducts).
3. **Motor direction** — the brief says motors have a CW/CCW arrow that must match the prop. I model CW/CCW as separate motor *and* prop parts and fix the layout to
   Betaflight props-in order. Motors are pre-soldered to the ESC M1-M4 pads (their leads are drawn along the arms); the player wires the harness, power, VTX and camera.
4. **C BAT pad** is treated as the capacitor pad (a decoy that rejects battery leads). **CUR** is optional and enables the total-amps HUD readout.
5. **Rates** live in the *PID* tab (the brief lists exactly five tabs). Rates are Betaflight-"actual"-like: centre sensitivity, max rate, expo per axis.
6. **PID units are normalised to the airframe** (the FC auto-scales gains for authority), so the defaults are stable on every build and tuning, not airframe
   mismatch, decides oscillation. Bad tuning really rings in flight (a prop-wash style disturbance excites it); the Setup chart shows the same loop.
7. **Port tab has consequences**: receiver UART off -> cannot arm; VTX UART off -> video is pure static. Both default to on. VTX power (25/200/600 mW)
   sets how far the video stays clear (40 / 100 / 180 m clean, 280 / 600 / 1000 m dead). The receiver link fails safe beyond 900 m or at the world edge.
8. **"Slight tilt for speed"** is implemented as the FPV camera up-tilt (default 20°, adjustable) plus a small speed-dependent FOV widening.
9. **FOV** (60-110) is the horizontal field of view.
10. **Battery** is recharged automatically when you return to the workshop; broken props are not (you must scrap them and fit fresh ones in BUILD).
11. **Unlocks** come from *finishing* a mission once (not from beating par). **Options > Unlock all parts (testing)** unlocks everything.
12. **Keybinds** are stored by physical key position, so WASD works on any layout.
13. **Audio** is synthesised at runtime (motor whine, UI sounds, a generative music bed); volumes map to Master/Music/SFX buses.
14. The workshop keeps your current drone in `save.json`; *New drone* on the main menu clears it.
15. The Windows build is unsigned and not tested on real GPUs in this environment (see the note above).

---

## Play-test checklist

Tip: **Options > Unlock all parts (testing)** and the *Quick to Setup & Fly* button on the main menu save time.

- [ ] **Wiring rejects bad input** — WIRE stage: connect FC `M1` to ESC `S2` (red flash + message, no wire). Put the battery **red** lead on `BAT−`, on **C BAT**, or on any
      signal pad (rejected). VTX onto the `CAM` pad (rejected). Then make all nine correct connections; the checklist turns green and *NEXT: SETUP* enables.
- [ ] **Spin direction is enforced** — BUILD: drop a CW motor on the CCW slot M1 (bounces back, "Wrong spin…"). Install the right motors, then try a CW prop on a CCW motor (bounces).
      Mixed motor models or a prop before its motor are also refused. Setup > Motor: hold `1`-`4` and check each arrow's direction matches its label.
- [ ] **Amp readouts change with throttle** — FLY: armed at zero throttle the HUD shows ~0.1 A per motor; raise throttle and the four labels and the total follow
      (hover ≈ 7-8 A total, full throttle ≈ 17 A per motor / ≈ 70 A total). Voltage drops under load and recovers when you lift off.
- [ ] **A crash breaks a prop** — fly into the ground/a tree above ~25 km/h: props break, a slow-mo replay plays, the workshop opens on BUILD with broken props shown.
      Click them to scrap, drop fresh ones on the glowing slots, and you can continue. (A gentle landing breaks nothing.)
- [ ] **Battery cut-off works** — fly (or hover) until the pack empties: *LOW BATTERY* flashes below 3.45 V/cell, at 3.2 V/cell *POWER LOSS* appears, motors stop and the drone drops;
      you land back in the workshop with the pack recharged. Try full throttle with a nearly empty pack to see the voltage sag trigger it earlier.
- [ ] **Keybinds persist after restart** — Options > Controls: rebind *Throttle up* to `T` (and a gamepad axis), close the game, start it again: the new bindings are still there
      (also FOV, preset and volume). Deleting/corrupting `settings.cfg` or `save.json` just resets to defaults.
- [ ] Extras: analog video degrades with distance; `H` hides the HUD; mouse-stick mode (`M`); F11 fullscreen; gate race counts gates in order and saves the best time;
      Setup > PID with P ≈ 100+ and low D shows a ringing step response and a shaky hover.

---

## Automated checks (optional)

```
# fast, no GPU needed (build/wire rules, settings & save robustness, keybind persistence across processes)
godot --headless --path . res://tests/logic_test.tscn
godot --headless --path . res://tests/logic_test.tscn -- read

# flight/power model numbers (idle/full-throttle amps, PID stability, battery cut-off, per-build stats)
godot --headless --path . --script res://tests/sim_test.gd

# mission / battery / crash / landing logic inside the real FlyStage (works headless)
godot --headless --path . res://tests/driver.tscn -- /tmp race_complete gate_miss battery_complete battery_flat rx_off crash_breaks_prop soft_landing

# real mouse-input UI tests + screenshots (needs a display, or xvfb + any Vulkan driver, e.g. lavapipe)
godot --path . res://tests/driver.tscn -- <out_dir> interaction wire_interaction click_mode menu build_partial wire setup_tabs fly crash
```

## Project layout

```
project.godot, export_presets.cfg, icon.svg
scenes/main.tscn            single scene; everything else is built in code
shaders/analog_fx.gdshader  FPV analog break-up
scripts/autoload/           Settings (+keybinds), SaveData, Audio (procedural), Game (shared state)
scripts/data/               Parts (catalogue, slots, wires, stats), MeshFactory (procedural meshes), DroneVisual
scripts/workshop/           Workshop, BuildStage, WireStage, SetupStage
scripts/fly/                FlyStage, FlyWorld (terrain/trees/lake), DroneSim, FlightMath, Missions, Hud
scripts/ui/                 theme, main menu, options/rebinding, charts, gyro view, motor diagram
tests/                      headless logic/sim tests and the visual/interaction driver
```
