class_name FlightMath
extends RefCounted
## Pure helpers shared by the flight model and the SETUP tab previews:
## rate curves, PID gain scaling, battery curve and a 1-axis step-response sim.

const LOOP_DT := 1.0 / 240.0
const A_REF := 140.0         # reference angular authority (rad/s^2 per unit mix) the PID units are normalised to
const KP_UNIT := 0.0150
const KI_UNIT := 0.040       # mix per rad for I = 1
const KD_UNIT := 2.2e-4
const YAW_SCALE := 0.35      # yaw has far less authority and no D; keep its loop gentler
const IDLE := 0.05
const C_REF := 0.4           # throttle at which authority is measured
const V_NOM_FACTOR := 0.85   # typical loaded voltage / full voltage


const PRESETS := {
	"Freestyle": {"pid": {"roll": [45, 80, 30], "pitch": [47, 84, 34], "yaw": [45, 80, 0]},
		"rates": {"roll": [80, 650, 0.25], "pitch": [80, 650, 0.25], "yaw": [80, 500, 0.2]}},
	"Race": {"pid": {"roll": [55, 90, 38], "pitch": [58, 95, 42], "yaw": [44, 80, 0]},
		"rates": {"roll": [110, 800, 0.1], "pitch": [110, 800, 0.1], "yaw": [100, 650, 0.1]}},
	"Cinematic": {"pid": {"roll": [38, 70, 28], "pitch": [40, 74, 30], "yaw": [38, 70, 0]},
		"rates": {"roll": [55, 360, 0.35], "pitch": [55, 360, 0.35], "yaw": [50, 300, 0.3]}},
	"Long Range": {"pid": {"roll": [40, 75, 28], "pitch": [42, 78, 30], "yaw": [40, 72, 0]},
		"rates": {"roll": [70, 450, 0.3], "pitch": [70, 450, 0.3], "yaw": [60, 380, 0.25]}},
}


static func apply_preset(cfg: Dictionary, name: String) -> void:
	var p: Dictionary = PRESETS[name]
	for axis in ["roll", "pitch", "yaw"]:
		var g: Array = p["pid"][axis]
		cfg["pid"][axis] = {"p": g[0], "i": g[1], "d": g[2]}
		var r: Array = p["rates"][axis]
		cfg["rates"][axis] = {"center": float(r[0]), "max": float(r[1]), "expo": float(r[2])}
	cfg["preset"] = name


static func default_cfg() -> Dictionary:
	return {
		"pid": {
			"roll": {"p": 45, "i": 80, "d": 30},
			"pitch": {"p": 47, "i": 84, "d": 34},
			"yaw": {"p": 45, "i": 80, "d": 0},
		},
		"rates": {
			"roll": {"center": 80.0, "max": 650.0, "expo": 0.25},
			"pitch": {"center": 80.0, "max": 650.0, "expo": 0.25},
			"yaw": {"center": 80.0, "max": 500.0, "expo": 0.20},
		},
		"gyro_lpf": 120.0,       # Hz
		"cam_angle": 20.0,       # degrees of FPV camera up-tilt
		"vtx_enabled": true,     # Port tab: VTX UART
		"rx_enabled": true,      # Port tab: receiver UART
		"vtx_power": 1,          # 0=25mW 1=200mW 2=600mW
		"preset": "Freestyle",
		"angle_mode": false,     # start flights in self-level (angle) mode instead of acro
	}


## Betaflight-"actual"-style rate curve. stick -1..1 -> rad/s.
static func rate_setpoint(stick: float, r: Dictionary) -> float:
	var s := clampf(stick, -1.0, 1.0)
	var e: float = r["expo"]
	var shaped := s * (1.0 - e) + s * s * s * e
	var a := absf(shaped)
	var center: float = r["center"]
	var mx: float = r["max"]
	var deg := center * a + (mx - center) * a * a
	return deg_to_rad(deg) * signf(shaped)


## Angular authority (rad/s^2 per unit mix) for body axes x (pitch), y (yaw), z (roll).
static func authority(stats: Dictionary) -> Vector3:
	var dtdc: float = 2.0 * stats["thrust_full"] * C_REF * V_NOM_FACTOR * V_NOM_FACTOR
	var inertia: Vector3 = stats["inertia"]
	var arm: float = stats["arm"]
	var ax: float = 4.0 * 0.5 * dtdc * arm / inertia.x
	var az: float = 4.0 * 0.5 * dtdc * arm / inertia.z
	var ay: float = 4.0 * 0.5 * dtdc * stats["kq"] / inertia.y
	return Vector3(ax, ay, az)


## Gains (mix per rad/s, per rad, per rad/s^2) for one axis.
static func gains(pid: Dictionary, auth: float, scale: float = 1.0) -> Vector3:
	var norm := A_REF / maxf(auth, 1.0) * scale
	return Vector3(float(pid["p"]) * KP_UNIT * norm, float(pid["i"]) * KI_UNIT * norm, float(pid["d"]) * KD_UNIT * norm)


static func lpf_alpha(cutoff_hz: float, dt: float) -> float:
	var rc := 1.0 / (TAU * maxf(cutoff_hz, 1.0))
	return dt / (rc + dt)


## Open-circuit voltage per cell vs state of charge (1 = full).
static func cell_ocv(soc: float) -> float:
	const PTS := [[0.0, 3.2], [0.05, 3.5], [0.1, 3.62], [0.2, 3.72], [0.4, 3.8], [0.6, 3.88], [0.8, 4.0], [0.9, 4.1], [1.0, 4.2]]
	var s := clampf(soc, 0.0, 1.0)
	for i in range(1, PTS.size()):
		if s <= PTS[i][0]:
			var a: Array = PTS[i - 1]
			var b: Array = PTS[i]
			return lerpf(a[1], b[1], (s - a[0]) / (b[0] - a[0]))
	return 4.2


## Simulates a unit step on the roll axis with the real controller structure.
## Returns {"samples": PackedFloat32Array, "overshoot": float, "status": String, "rating": int}
static func step_response(stats: Dictionary, cfg: Dictionary, axis: String = "roll", duration: float = 0.7) -> Dictionary:
	var auth_v := authority(stats)
	var auth: float = {"roll": auth_v.z, "pitch": auth_v.x, "yaw": auth_v.y}[axis]
	var g := gains(cfg["pid"][axis], auth, YAW_SCALE if axis == "yaw" else 1.0)
	var dt := LOOP_DT
	var tau_m: float = 0.45 * stats["prop_tau"]
	var a_g := lpf_alpha(cfg["gyro_lpf"], dt)
	var a_d := lpf_alpha(80.0, dt)
	var w := 0.0
	var wf := 0.0
	var wf_prev := 0.0
	var df := 0.0
	var integ := 0.0
	var m := 0.0
	var u_delay := 0.0
	var out := PackedFloat32Array()
	var n := int(duration / dt)
	var sched := 1.0   # step test is done around the reference throttle
	for i in n:
		var sp := 1.0
		wf += (w - wf) * a_g
		var err := sp - wf
		integ = clampf(integ + g.y * err * dt, -0.4, 0.4)
		var d_raw := (wf - wf_prev) / dt
		wf_prev = wf
		df += (d_raw - df) * a_d
		var u := clampf((g.x * err + integ - g.z * df) * sched, -1.0, 1.0)
		# one loop of compute delay + motor lag
		m += (u_delay - m) * (1.0 - exp(-dt / tau_m))
		u_delay = u
		w += auth * m * dt
		out.append(w)
		if absf(w) > 20.0:
			break
	# metrics
	var peak := 0.0
	var crossings := 0
	var last := 0.0
	var settled_err := 0.0
	for i in out.size():
		peak = maxf(peak, out[i])
		var e: float = out[i] - 1.0
		if i > 5 and signf(e) != signf(last) and absf(e) > 0.02:
			crossings += 1
		if absf(e) > 0.02:
			last = e
	if out.size() > 20:
		settled_err = absf(out[out.size() - 1] - 1.0)
	var overshoot := maxf(peak - 1.0, 0.0)
	var status := "Well tuned"
	var rating := 3
	if out.size() < n or absf(out[out.size() - 1]) > 3.0:
		status = "UNSTABLE - violent oscillation!"
		rating = 0
	elif crossings >= 5 or overshoot > 0.6:
		status = "Oscillating - lower P or raise D"
		rating = 0
	elif crossings >= 3 or overshoot > 0.3:
		status = "Bouncy - needs more D / less P"
		rating = 1
	elif settled_err > 0.25:
		status = "Sluggish - raise P/I"
		rating = 2
	elif overshoot < 0.02 and out.size() > 40 and out[int(0.12 / dt)] < 0.55:
		status = "Sluggish - raise P"
		rating = 2
	return {"samples": out, "overshoot": overshoot, "status": status, "rating": rating}
