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
- Stamina is **server-authoritative**. The client only sends input intent (climbing / holding / resting).

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

- Server-authoritative stamina, cash, payout and purchases; clients can't award themselves anything.
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
