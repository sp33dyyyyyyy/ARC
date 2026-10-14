class_name DroneSim
extends RefCounted
## Quadcopter flight + power model. Pure data/maths: no nodes, so it can be unit tested.
##
## Frame: X-config, Betaflight motor order. Body axes: +X right, +Y up, -Z forward.
## Positive body rates: x = nose up, y = yaw left (CCW from above), z = roll left.

const G := 9.81
const CRASH_SPEED := 7.0         # m/s of impact into a surface that breaks props (~25 km/h)
const DRONE_RADIUS := 0.09
const BASE_LOAD_A := 0.55        # FC + VTX + camera draw (not on the ESC current sensor)
const IDLE_A := 0.1              # per-motor ESC quiescent current
const CUTOFF_V_CELL := 3.2
const V_FULL_CELL := 4.2

# --- configuration (set by setup()) ---
var stats: Dictionary = {}
var cfg: Dictionary = {}
var cells := 4
var capacity_mah := 1500.0
var mass := 0.5
var inertia := Vector3(1.3e-3, 2.4e-3, 1.3e-3)
var arm := 0.0795
var thrust_full := 13.0
var amps_full := 24.5
var kq := 0.018
var drag_k2 := 0.0045
var tau_motor := 0.015
var auth := Vector3.ONE
var gains_x := Vector3.ZERO
var gains_y := Vector3.ZERO
var gains_z := Vector3.ZERO
var a_gyro := 0.5
var a_dterm := 0.3
var motor_pos: Array = []       # (x, z) per motor in metres
var motor_spin: Array = []      # +1 CW, -1 CCW

# --- state ---
var pos := Vector3.ZERO
var vel := Vector3.ZERO
var basis := Basis.IDENTITY
var omega := Vector3.ZERO       # body rates, rad/s
var armed := false
var angle_mode := false        # self-level: sticks command tilt angle instead of rate
var angle_max := deg_to_rad(55.0)
var angle_gain := 7.0          # rad/s of rate setpoint per rad of angle error
var rx_link := true
var video_link := true

# pilot input
var stick_throttle := 0.0
var stick_roll := 0.0
var stick_pitch := 0.0
var stick_yaw := 0.0

# controller state
var gyro_f := Vector3.ZERO
var turb := Vector3.ZERO        # filtered turbulence / prop-wash torque disturbance (rad/s^2)
var gyro_prev := Vector3.ZERO
var d_f := Vector3.ZERO
var i_term := Vector3.ZERO
var mix_out := Vector3.ZERO     # last PID output in mix units
var cmd: Array = [0.0, 0.0, 0.0, 0.0]
var w: Array = [0.0, 0.0, 0.0, 0.0]            # normalised rpm
var thrust: Array = [0.0, 0.0, 0.0, 0.0]       # N
var amps: Array = [0.1, 0.1, 0.1, 0.1]         # A per motor
var total_amps := 0.0          # ESC current (what the CUR sensor sees)
var current_limit := 90.0      # A the pack/ESC can deliver before power is limited
var limiting := false

# battery
var used_mah := 0.0
var v_oc := 16.8
var v_term := 16.8
var v_filt := 16.8
var r_int := 0.03
var power_lost := false
var low_voltage_warn := false

# events (consumed by the caller each step)
var impact_speed := 0.0
var impact_kind := ""            # "", "ground", "tree", "water"
var impact_normal := Vector3.UP
var impact_point := Vector3.ZERO
var on_ground := false
var time := 0.0
var air_time := 0.0

# world hooks
var ground_height: Callable      # (x, z) -> float
var obstacles: Callable          # (x, z) -> Array of [cx, cz, base_y]   (trees near the point)
var water_level := -1000.0
var water_test: Callable         # (x, z) -> bool  (is there lake here?)

var _rng := RandomNumberGenerator.new()


func setup(p_stats: Dictionary, p_cfg: Dictionary) -> void:
	stats = p_stats
	cfg = p_cfg
	cells = int(stats["cells"])
	capacity_mah = stats["capacity_mah"]
	mass = stats["mass"]
	inertia = stats["inertia"]
	arm = stats["arm"]
	thrust_full = stats["thrust_full"]
	amps_full = stats["amps_full"]
	kq = stats["kq"]
	drag_k2 = stats["drag"]
	tau_motor = 0.45 * stats["prop_tau"]
	auth = FlightMath.authority(stats)
	gains_x = FlightMath.gains(cfg["pid"]["pitch"], auth.x)
	gains_y = FlightMath.gains(cfg["pid"]["yaw"], auth.y, FlightMath.YAW_SCALE)
	gains_z = FlightMath.gains(cfg["pid"]["roll"], auth.z)
	a_gyro = FlightMath.lpf_alpha(cfg["gyro_lpf"], FlightMath.LOOP_DT)
	a_dterm = FlightMath.lpf_alpha(80.0, FlightMath.LOOP_DT)
	motor_pos.clear()
	motor_spin.clear()
	for i in 4:
		var sg: Vector2 = Parts.MOTOR_SIGNS[i]
		motor_pos.append(Vector2(sg.x * arm, sg.y * arm))
		motor_spin.append(1.0 if Parts.MOTOR_SPIN[i] == "CW" else -1.0)
	_rng.seed = 4242
	r_int = 0.030 * pow(1500.0 / capacity_mah, 0.8) * (cells / 4.0)
	current_limit = 60.0 * capacity_mah * 0.001
	reset()


func reset() -> void:
	vel = Vector3.ZERO
	omega = Vector3.ZERO
	basis = Basis.IDENTITY
	armed = false
	gyro_f = Vector3.ZERO
	gyro_prev = Vector3.ZERO
	d_f = Vector3.ZERO
	i_term = Vector3.ZERO
	turb = Vector3.ZERO
	for i in 4:
		cmd[i] = 0.0
		w[i] = 0.0
		thrust[i] = 0.0
		amps[i] = IDLE_A
	used_mah = 0.0
	power_lost = false
	low_voltage_warn = false
	_update_battery(FlightMath.LOOP_DT, BASE_LOAD_A + 4.0 * IDLE_A)
	v_filt = v_term
	time = 0.0
	air_time = 0.0
	impact_kind = ""
	impact_speed = 0.0


func soc() -> float:
	return clampf(1.0 - used_mah / capacity_mah, 0.0, 1.0)


func v_cell() -> float:
	return v_term / cells


func speed() -> float:
	return vel.length()


func set_motor_test(values: Array) -> void:
	pass


# --- main step -------------------------------------------------------------------------
func step(dt: float) -> void:
	time += dt
	impact_kind = ""
	impact_speed = 0.0

	# battery voltage under the *previous* step's load
	var total_batt_a := total_amps + BASE_LOAD_A
	_update_battery(dt, total_batt_a)
	if not power_lost and v_filt < CUTOFF_V_CELL * cells:
		power_lost = true
	low_voltage_warn = v_filt < 3.45 * cells

	var link_ok := rx_link and not power_lost
	var live := armed and link_ok

	# --- controller ---
	var thr := stick_throttle if live else 0.0
	var base := lerpf(FlightMath.IDLE, 1.0, thr) if live else 0.0
	var deltas := [0.0, 0.0, 0.0, 0.0]
	mix_out = Vector3.ZERO
	var pid_active := live and thr > 0.04
	var noise := 0.012 + 0.05 * _avg_w()
	var gyro_raw := omega + Vector3(_rng.randfn(0.0, noise), _rng.randfn(0.0, noise), _rng.randfn(0.0, noise))
	gyro_f += (gyro_raw - gyro_f) * a_gyro
	var d_raw := (gyro_f - gyro_prev) / dt
	gyro_prev = gyro_f
	d_f += (d_raw - d_f) * a_dterm
	if pid_active:
		var sp := Vector3(
			-FlightMath.rate_setpoint(stick_pitch, cfg["rates"]["pitch"]),
			-FlightMath.rate_setpoint(stick_yaw, cfg["rates"]["yaw"]),
			-FlightMath.rate_setpoint(stick_roll, cfg["rates"]["roll"]))
		if angle_mode:
			# outer angle loop: stick -> target tilt, error -> rate setpoint for the (unchanged) rate PIDs
			var ub := basis.inverse() * Vector3.UP
			var tilt_x := -asin(clampf(ub.z, -1.0, 1.0))     # + = nose up
			var tilt_z := asin(clampf(ub.x, -1.0, 1.0))      # + = rolled left
			var max_rate := deg_to_rad(420.0)
			sp.x = clampf(angle_gain * (-stick_pitch * angle_max - tilt_x), -max_rate, max_rate)
			sp.z = clampf(angle_gain * (-stick_roll * angle_max - tilt_z), -max_rate, max_rate)
		var err := sp - gyro_f
		var sched := FlightMath.C_REF / clampf(base, 0.15, 1.0)
		sched = clampf(sched, 0.35, 2.0)
		var vcomp := clampf(pow(14.3 / maxf(v_term / (cells / 4.0), 8.0), 2.0), 0.7, 1.7)
		var g := sched * vcomp
		i_term.x = clampf(i_term.x + gains_x.y * err.x * dt, -0.35, 0.35)
		i_term.y = clampf(i_term.y + gains_y.y * err.y * dt, -0.35, 0.35)
		i_term.z = clampf(i_term.z + gains_z.y * err.z * dt, -0.35, 0.35)
		mix_out.x = (gains_x.x * err.x + i_term.x - gains_x.z * d_f.x) * g
		mix_out.y = (gains_y.x * err.y + i_term.y - gains_y.z * d_f.y) * g
		mix_out.z = (gains_z.x * err.z + i_term.z - gains_z.z * d_f.z) * g
		for i in 4:
			var p: Vector2 = motor_pos[i]
			var ax := -signf(p.y)
			var az := signf(p.x)
			var ay: float = motor_spin[i]
			deltas[i] = 0.5 * (mix_out.x * ax + mix_out.z * az + mix_out.y * ay)
	else:
		i_term = Vector3.ZERO

	# airmode: compress to fit then shift into [idle, 1]
	if live:
		var dmax: float = deltas.max()
		var dmin: float = deltas.min()
		var avail := 1.0 - FlightMath.IDLE
		if dmax - dmin > avail:
			var k := avail / (dmax - dmin)
			for i in 4:
				deltas[i] *= k
			dmax *= k
			dmin *= k
		var b := clampf(base, FlightMath.IDLE - dmin, 1.0 - dmax) if pid_active else base
		for i in 4:
			cmd[i] = clampf(b + deltas[i], 0.0, 1.0)
	else:
		for i in 4:
			cmd[i] = 0.0

	# --- motors, thrust, current ---
	var vfac := clampf(v_term / (V_FULL_CELL * cells), 0.0, 1.0)
	var sum_a := 0.0
	var f_total := 0.0
	var tau_x := 0.0
	var tau_y := 0.0
	var tau_z := 0.0
	var lag := 1.0 - exp(-dt / tau_motor)
	# ESC / pack current limiting: back the motors off when the draw exceeds what the pack can give
	var lim_scale := clampf(current_limit / maxf(total_amps, 0.1), 0.0, 1.0)
	limiting = lim_scale < 0.995
	lim_scale = pow(lim_scale, 0.45)
	for i in 4:
		var target: float = cmd[i] * vfac * lim_scale
		w[i] += (target - w[i]) * lag
		if w[i] < 0.0005:
			w[i] = 0.0
		var t: float = thrust_full * w[i] * w[i]
		thrust[i] = t
		var pw: float = amps_full * pow(w[i], 2.2) / maxf(vfac, 0.25)
		amps[i] = IDLE_A + pw
		sum_a += amps[i]
		f_total += t
		var p: Vector2 = motor_pos[i]
		tau_x += -p.y * t
		tau_z += p.x * t
		tau_y += motor_spin[i] * kq * t
	total_amps = sum_a

	# --- rigid body ---
	var up := basis.y
	var force := up * f_total + Vector3(0, -mass * G, 0)
	var v_len := vel.length()
	force -= vel * (0.012 + drag_k2 * v_len)
	var acc := force / mass
	var alpha := Vector3(tau_x / inertia.x, tau_y / inertia.y, tau_z / inertia.z)
	alpha -= omega * 0.18
	if not on_ground:
		# prop-wash style disturbance: makes under-damped tunes visibly ring
		var sig := 7.0 * (0.3 + _avg_w())
		turb += (Vector3(_rng.randfn(0.0, sig), _rng.randfn(0.0, sig * 0.4), _rng.randfn(0.0, sig)) - turb) * minf(dt / 0.006, 1.0)
		alpha += turb
	omega += alpha * dt
	vel += acc * dt
	pos += vel * dt
	var ang := omega.length() * dt
	if ang > 1e-7:
		var q := basis.get_rotation_quaternion()
		q = q * Quaternion(omega.normalized(), ang)
		basis = Basis(q.normalized())

	_collide(dt)
	if not on_ground:
		air_time += dt

	# --- battery drain ---
	used_mah += (sum_a + BASE_LOAD_A) * dt / 3.6


func _avg_w() -> float:
	return (w[0] + w[1] + w[2] + w[3]) * 0.25


func _update_battery(dt: float, load_a: float) -> void:
	v_oc = FlightMath.cell_ocv(soc()) * cells
	var r := r_int * (1.0 + 0.6 * pow(1.0 - soc(), 2.0))
	v_term = maxf(v_oc - load_a * r, 0.5 * v_oc)
	v_filt += (v_term - v_filt) * (1.0 - exp(-dt / 0.45))


# --- collisions ------------------------------------------------------------------------------
func ground_normal(x: float, z: float) -> Vector3:
	var e := 0.8
	var hx: float = ground_height.call(x + e, z) - ground_height.call(x - e, z)
	var hz: float = ground_height.call(x, z + e) - ground_height.call(x, z - e)
	return Vector3(-hx, 2.0 * e, -hz).normalized()


func _collide(dt: float) -> void:
	on_ground = false
	if not ground_height.is_valid():
		return
	# water
	var gh: float = ground_height.call(pos.x, pos.z)
	if water_test.is_valid() and water_test.call(pos.x, pos.z) and pos.y < water_level + 0.05:
		_hit("water", Vector3.UP, maxf(-vel.y, 0.0), Vector3(pos.x, water_level, pos.z))
		return
	# terrain
	if pos.y < gh + DRONE_RADIUS:
		var n := ground_normal(pos.x, pos.z)
		var vn := vel.dot(n)
		on_ground = true
		if vn < 0.0:
			var spd := -vn
			if spd > CRASH_SPEED:
				_hit("ground", n, spd, Vector3(pos.x, gh, pos.z))
				return
			vel -= n * vn * 1.15
		pos.y = gh + DRONE_RADIUS
		var tang := vel - n * vel.dot(n)
		vel -= tang * minf(6.0 * dt, 1.0)
		omega *= exp(-10.0 * dt)
		# the airframe rests on its feet: settle toward the surface normal when not climbing out
		if f_up_lt_weight():
			var axis := basis.y.cross(n)
			var s := axis.length()
			if s > 1e-4:
				var a := asin(clampf(s, 0.0, 1.0)) * minf(5.0 * dt, 1.0)
				basis = Basis(Quaternion(axis / s, a)) * basis
				basis = basis.orthonormalized()
	# trees
	if obstacles.is_valid():
		var list: Array = obstacles.call(pos.x, pos.z)
		for t in list:
			var gy: float = t[2]
			var sc: float = t[3]
			var dy: float = (pos.y - gy) / sc
			if dy < -0.5 or dy > 10.0:
				continue
			var rad: float = (0.35 if dy < 2.4 else 2.3 * clampf(1.0 - (dy - 2.4) / 7.4, 0.0, 1.0)) * sc
			var d := Vector2(pos.x - t[0], pos.z - t[1])
			var dist := d.length()
			if dist < rad + DRONE_RADIUS:
				var n2 := Vector3(d.x, 0.15, d.y).normalized() if dist > 0.001 else Vector3.RIGHT
				var vn2 := vel.dot(n2)
				if vn2 < 0.0:
					if -vn2 > CRASH_SPEED * 0.8:
						_hit("tree", n2, -vn2, pos)
						return
					vel -= n2 * vn2 * 1.3
				var push := (rad + DRONE_RADIUS - dist)
				pos += Vector3(n2.x, 0, n2.z) * push
				omega *= 0.8


func f_up_lt_weight() -> bool:
	var ft := 0.0
	for t in thrust:
		ft += t
	return ft < mass * G * 1.05


func _hit(kind: String, n: Vector3, spd: float, point: Vector3) -> void:
	impact_kind = kind
	impact_speed = spd
	impact_normal = n
	impact_point = point
	armed = false
