# Sky Climbers — Design Spec

Roblox game about climbing telecom towers and skyscrapers, in the janky-physics, ragdoll-comedy style of Retrograd and Ragdoll Engine.

## 1. Delivery

- Rojo project (`default.project.json`) with Luau source under `src/`. Synced into Roblox Studio with Rojo.
- No imported assets. Towers, textures, UI and sounds-as-IDs are generated or configured in code so the project is self-contained.
- Luau is checked with `selene` and `stylua` where available. Pure-logic modules (stamina, payout, shop math) are unit-testable without Studio.

## 2. Gameplay

### Core loop
Spawn in plaza -> pick a tower -> climb -> rest on ledges to recover stamina -> reach the peak -> payout + counter increments -> spend cash on boosts -> climb something harder.

### Stamina and blackout
- Climbing drains stamina; hanging still drains slowly; resting (on a ledge, platform, or while "chalk-ing" on a rest bar) refills it.
- At 0 stamina the player blacks out: vignette to black, character ragdolls, falls. Fall damage scales with height; landing on a lower ledge stops the fall.
- Stamina is simulated on the **client**. Only the owning client knows its exact Humanoid state (climbing, hanging or grounded) each frame, and stamina only limits the player themselves. Everything of value (cash, climbs, purchases, payouts, fall damage) is server-authoritative. *(This replaces an earlier draft that had the server own stamina.)*

### Towers

| Tower | Height (studs) | Rest spots | Drain | Payout |
|---|---|---|---|---|
| Small mast | 80 | many | 1x | $50 |
| Lattice tower | 200 | some | 1.5x | $200 |
| Skyscraper | 400 | few | 2.5x | $1,000 |
| Supertall | 800 | very few | 4x | $5,000 |

- **Telecom towers** follow real self-supporting lattice towers: 3 or 4 legs tapering from a wide base to a narrow top, stacked bolted sections, chevron/X bracing, platforms with antennas and dishes, a lamp at the top.
- **Skyscrapers** follow stepped-setback supertalls: a central core, setback ledges (used as rest spots), sheer glass faces between them (slippery, high drain), and a spire at the top.

### Peak and counter
- A trigger zone at each peak awards payout once per tower per climb and increments `towerClimbs`.
- HUD shows `Tower climbs: N`; the value persists and appears on a leaderboard.

### Boosts (shop, bought with cash)
Endurance (stamina cap, 10 levels), Recovery speed, Climb speed, Grip (less drain on glass), Soft Landing (reduced fall damage). Costs scale per level. All purchases are validated on the server.

### Extra features
Chosen for value versus effort (YAGNI applied):
1. **Chalk** — consumable that temporarily removes glass slipperiness and cuts drain.
2. **Wind gusts** — at height, gusts push climbers and add drain; a UI cue warns before one arrives.
3. **Checkpoint flags** — planted on rest ledges so a fall can be recovered from.
4. **Daily streak reward** — bonus cash for consecutive days played.
5. **Summit emotes + confetti** — celebratory effect and sound at the peak.
6. **Trails and cosmetics** — unlocked by total climbs.
7. **Day/night + weather cycle** — fog and rain make the supertall harder.

## 3. UI overhaul

- Single dark, modern theme with a high-contrast accent color; consistent corner radii, strokes and UIScale for mobile and console.
- **HUD**: stamina bar with a danger pulse under 20%, height meter, `Tower climbs: N` counter, cash display, chalk count, wind warning icon.
- **Shop**: tabbed panel with boost cards (level, cost, buy button, disabled and "max" states).
- **Blackout screen**: vignette, "You blacked out!" text and a short tip.
- **Toasts** for payouts and unlocks, with tweened animations.
- Screens are built from reusable component modules and use `TweenService`, not per-frame polling.

## 4. Textures and visuals

- No uploaded images. Surfaces use Roblox `Material` values (`Concrete`, `Metal`, `DiamondPlate`, `Glass`, `Neon` accents), tuned colors, `Reflectance` on glass, and `SurfaceAppearance`/`MaterialVariant` where an ID is supplied.
- Lighting pass: `Atmosphere`, `Bloom`, `ColorCorrection`, `SunRays`, and a skybox, with tower warning lights at night.

## 5. Architecture

```
default.project.json
src/
  shared/    Config.lua, Types.lua, StaminaMath.lua, ShopMath.lua, Remotes.lua
  server/    Main.server.lua, TowerBuilder.lua, ClimbService.lua, StaminaService.lua,
             PayoutService.lua, ShopService.lua, DataService.lua, WindService.lua, Leaderboard.lua
  client/    Main.client.lua, ClimbController.lua, Ragdoll.lua, Hud.lua, ShopUI.lua,
             Effects.lua, Components/
tests/       StaminaMath.spec.lua, ShopMath.spec.lua, PayoutRules.spec.lua
```

Each unit has one purpose and a defined interface. `shared/*Math` modules are pure functions, so they can be tested outside Studio.

## 6. Bug prevention (built in, verified by tests or playtest)

- Server-authoritative cash, payouts, purchases and fall damage; clients can't award themselves anything.
- Peak payout is idempotent per tower per climb; the trigger zone debounces.
- DataStore: retries with backoff, session locking guard, save on `PlayerRemoving` and `BindToClose`, defaults for new players, schema versioning.
- Ragdoll state is cleaned up on respawn; Humanoid states are restored; no leaked connections (Maid pattern).
- Stamina cannot go below 0 or above the cap; shop levels are clamped; costs use integer math.
- Fall detection guards against false triggers from teleports and respawns.
- Remotes are rate-limited and validated (type and range checks).

## 7. Testing

- Unit tests for stamina drain/recovery, shop pricing and clamping, payout idempotency.
- A manual Studio playtest checklist: each tower is climbable to the peak, rest ledges recover stamina, blackout and fall work, counter and cash persist after rejoin, shop purchases apply, mobile UI scales.

## 8. Open items

- The user's original reference images never arrived; towers are based on researched references (lattice-tower and Burj Khalifa-style structures). They can be adjusted if images are supplied later.
- Format A (Rojo) is assumed because no preference was given.

## 9. Revision: map, heights and climbing (2026-10-20)

Changes requested after the first playable build:

- **Map** now follows the user's top-down diagram: spawn plaza at the north,
  a central path to the Power Up Shop in the south, Skyscrapers 1-3 on the west,
  Tutorial Tower and Telecom Towers 1-2 on the east, on a fenced cliff island.
- **Heights:** every tower except the smallest is at least 3.5x the original
  (Telecom 700 / 1050, Skyscrapers 1400 / 2100 / 2800). The original small mast
  stays at 80 studs and is renamed "Tutorial Tower".
- **Climbing:** ladders are gone, replaced by "Grip & Lunge". You grab any
  climbable surface, crawl in four directions, lunge upward for extra stamina,
  catch the wall while falling, and mantle onto platforms, balconies and roofs.
- **Bug fix:** the old baseplate was written with `Position`, which Roblox
  place files don't store. It loaded at the origin and buried the map by 8
  studs. The spawn now uses `CFrame`, and the ground is built in code.

## 10. Revision: weather and emotes (2026-10-20)

- **Weather** cycles Clear / Fog / Rain every 90-180s. The server tweens
  Atmosphere, Clouds, brightness and saturation, and publishes the state as
  Workspace's `Weather` attribute. Clients render the rain and lightning, and
  rain multiplies climbing drain by 1.25. The balance test covers rain.
- **Emotes** are bought at the Power Up Shop (server-validated, saved in the
  profile). G opens an emote bar, and the equipped summit emote auto-plays at
  every peak. Animations come from the avatar's own Animate script.

## 11. Revision: Hand-over-Hand climbing, rest bars, calmer wind (2026-10-20)

- Rest platforms and balconies (the "flat bits" left over from the ladder era)
  are gone. Nothing solid sticks out of a climbable face. Rest spots are
  non-colliding yellow rest bars, published as the tower's `RestLevels`
  attribute. Hanging still on one recovers stamina at 70% of the ground rate
  and saves a checkpoint (you respawn gripping the wall).
- Climbing is now Hand-over-Hand: auto-grip by walking or jumping into a tower,
  movement in rhythmic pulls, SPACE to leap, and climbing over the top onto a
  flush summit deck or roof.
- The climbing animation is procedural (Motor6D.Transform). The server shares
  each climber's pose as the character's `ClimbPose` attribute, so every
  client animates everyone.
- Mantle checks use rays instead of bounding boxes. The boxes were inflated by
  the slanted lattice panels and wrongly reported "no room".
- Wind gusts now come every 110-130s, are softer, and only knock off climbers
  below 15% stamina.

## 12. Revision: settings, admin panel, gamepasses (2026-10-20)

- **Settings** window: name tags (hidden locally via `DisplayDistanceType`) and
  camera shake, both saved in the profile.
- **Admin:** the code lives only in server-side `AdminConfig`, is compared in
  full every time, and is rate limited (5 per 10 min). Owner, listed user IDs
  and Studio playtests are auto-admin. Tools: ban/unban by username (Roblox
  `BanAsync` plus a DataStore ban list checked on join), send to plaza (one or
  all), give/take gamepass, and filtered game-wide announcements via
  MessagingService. Every action is re-validated on the server.
- **Gamepasses:** VIP (2x payout), Iron Lungs (+50 stamina), Featherweight
  (0.5x fall damage). Ownership is a Robux purchase OR an admin grant
  (`GrantedPasses` in the profile). Perks are applied in Rules.

## 13. Revision: rock climbing, text fitting, admin password (2026-10-20)

- **Rock climbing:** climbing is a sequence of discrete moves (reach with one
  hand while the body is still, then pull up while the opposite leg pushes),
  with alternating hands, traverse moves, and a dyno on SPACE. Wall logic is in
  `WallClimb` (pure Vector3 maths plus an injected raycaster). The geometry test
  runs it up all 4 faces of all 6 towers from 3 start heights. This caught two
  real bugs, both now fixed: the skyscraper roof lip made the wall end early,
  and the roof top was rejected as somewhere to stand.
- **Animation:** poses come from `ClimbPose` (pure, unit-tested for smooth
  move-to-move continuity and limb ranges) and are applied via Motor6D.C0
  offsets. The old version wrote `Transform`, which Roblox's Animator
  overwrites every frame, so the animation never showed and climbers seemed to
  float. Limb collisions are off while climbing, and default animation tracks
  are stopped.
- **UI:** labels and buttons auto-shrink text to fit (capped at their design
  size), text boxes clip, and button hover highlights the outline instead of
  scaling.
- **Admin:** the password `Evan123` is required for everyone. Auto-admin for
  the owner and Studio is removed. The box masks input.

## 14. Revision: standard climb animation, rope, suction cups, rappel (2026-10-20)

- **Animation:** the procedural C0 pose T-posed in practice and is removed.
  Climbing now plays the avatar's own Animate `climb` animation, which is
  Roblox-owned, works for R15 and R6, and replicates. Speed follows movement
  (frozen when hanging, fast for a dyno, reversed for rappel).
- **No fog:** the Fog weather state is removed and the haze turned down.
- **Summit service-lift huts removed.** You get down by climbing, rappelling,
  or pressing P.
- **Climbing rope:** F clips in. On telecom towers you clip a carabiner onto a
  horizontal girt (tagged `ClipBar`, including a new girt at the summit). On
  skyscrapers you stick a suction cup on the glass. `RopeService` validates the
  point and creates a server-side RopeConstraint (16 studs, visible to all).
  Moves beyond the rope's length are blocked until you reclip higher. While
  clipped: no wind knock-off, resting recovers at 50%, and falls are caught
  (then you re-grab automatically). It unclips automatically at the summit, on
  the ground, at the plaza or on death.
- **Rappel Kit** (one-time $2,500 boost): V slides you down the wall at 35
  studs/s to the ground, from a wall or from a summit edge.
- The climb simulation now also checks a clip beam is within reach at every
  step up every telecom face.

## 15. Revision: lattice-only climbing, real carabiner (2026-10-20)

- **Telecom towers are climbed on their members only.** The invisible
  "ClimbFace" panels (which let you climb anywhere on the tower's outline) are
  gone. Every leg, brace and girt is tagged `ClimbHold`; the shared `Lattice`
  module treats each as a line segment. `WallClimb`'s lattice mode reaches for
  the nearest real member for every move (up, down, sideways, round a corner
  leg onto the next face, dynos, rappelling down the taper). If nothing is in
  reach, the HUD says so. Skyscrapers keep surface climbing on the glass.
- **Carabiner, rebuilt.** The server checks a clip point with the same
  `Lattice` maths the client used to choose it, and always answers with a
  `RopeResult` notification (success, or the reason it failed). Previously a
  rejected or rate-limited clip failed silently. The gear is a welded model
  (D-ring, silver gate, quickdraw sling, rope clip; or a suction cup with a
  handle) that tweens from the harness onto the beam. The climber's avatar
  reaches up using its built-in "point" animation as the clip gesture. Unclip
  requests are never rate limited, and the rope's physical length includes the
  sling, so it never pulls against the climber before the client's limit.
- Climbing raycasts respect `CanCollide`, so walk-through decorations are
  never treated as walls.
- The geometry test runs the lattice climb on every telecom face from three
  spots (middle, halfway out, next to a leg). It checks that the hands are on
  a real beam after every move, that you can traverse round a corner, and that
  you can rappel the whole way down. It also checks that the server accepts
  every clip point the client would pick.

## 16. Revision: clipping fixed at the source (2026-10-20)

- `RopeService.start()` ran last on the server, after `AdminService.start()`,
  which called `MessagingService:SubscribeAsync` directly. That call waits on
  Roblox's servers and can stall (especially in Studio), and while it did the
  rope remote had no listener, so F silently did nothing. The subscribe now
  runs in the background and the rope service starts right after data.
- The server now picks the clip point itself (nearest leg, brace or girt within
  reach of the climber's hands, or the glass in front of them), using the
  client's point only as a hint. Client/server disagreement can no longer
  reject a clip. A server error while clipping is caught and reported.
- The client always sends the request (even when it sees nothing in reach),
  works off the wall too (e.g. standing on a deck), and warns if the server
  doesn't answer within 3 seconds.

## 17. Revision: controls tab, animations, UI click (2026-10-20)

- The column of eight action buttons on the right is replaced by a single
  CONTROLS tab on the right edge (H). It slides out a panel listing every
  control with a key badge, and each action row is a button. On touch-only
  devices, LET GO / CLIP ROPE / RAPPEL appear while climbing.
- Shared `C.animated` open/close for every window (backdrop fade, pop-up with
  overshoot, reverse on close). The emote bar slides up with its buttons
  popping in; the controls rows cascade in.
- `C.click()`: a local keyboard-click sound (`Config.Sounds.UIClick`) on every
  button, toggle and window/tab opening (debounced so one press is one click).

