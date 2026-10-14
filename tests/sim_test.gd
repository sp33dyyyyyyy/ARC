extends SceneTree
## Headless checks for the flight/power model.  Run:
##   godot --headless --path . --script res://tests/sim_test.gd

var failures := 0


func check(cond: bool, msg: String) -> void:
	if cond:
		print("  PASS  ", msg)
	else:
		print("  FAIL  ", msg)
		failures += 1


func make_sim(frame := "frame_5", motor := "2306", prop := "5143", bat := "bat_1500") -> DroneSim:
	var placed := DroneVisual.default_placement()
	placed["frame"] = frame
	for i in 4:
		var d: String = Parts.MOTOR_SPIN[i].to_lower()
		placed["motor_%d" % (i + 1)] = "motor_%s_%s" % [motor, d]
		placed["prop_%d" % (i + 1)] = "prop_%s_%s" % [prop, d]
	placed["battery"] = bat
	var stats := Parts.compute_build(placed, {})
	var sim := DroneSim.new()
	sim.setup(stats, FlightMath.default_cfg())
	sim.ground_height = func(_x, _z): return 0.0
	sim.pos = Vector3(0, 0.1, 0)
	return sim


func run_for(sim: DroneSim, secs: float) -> void:
	for i in int(secs * 240):
		sim.step(1.0 / 240.0)


func _init() -> void:
	var stats := Parts.compute_build(DroneVisual.default_placement(), {})
	print("Default build: mass %.0f g, thrust/motor %.1f N, amps_full %.1f A, TWR(loaded) %.1f" % [stats["mass_g"], stats["thrust_full"], stats["amps_full"], stats["twr"]])
	print("authority xyz: ", FlightMath.authority(stats))

	print("== step response (default PID) ==")
	var cfg := FlightMath.default_cfg()
	for axis in ["roll", "pitch", "yaw"]:
		var r := FlightMath.step_response(stats, cfg, axis)
		print("  %s: overshoot %.2f  -> %s" % [axis, r["overshoot"], r["status"]])
	var r0 := FlightMath.step_response(stats, cfg, "roll")
	check(r0["rating"] == 3, "default tune is 'Well tuned' (%s)" % r0["status"])
	for mult in [1.5, 2.0, 3.0, 4.0]:
		var c2 := FlightMath.default_cfg()
		c2["pid"]["roll"]["p"] = 45 * mult
		var rr := FlightMath.step_response(stats, c2, "roll")
		print("  P x%.1f -> overshoot %.2f  %s" % [mult, rr["overshoot"], rr["status"]])
	var c3 := FlightMath.default_cfg()
	c3["pid"]["roll"]["d"] = 0
	var r3 := FlightMath.step_response(stats, c3, "roll")
	print("  D=0 -> overshoot %.2f  %s" % [r3["overshoot"], r3["status"]])
	var c4 := FlightMath.default_cfg()
	c4["pid"]["roll"]["p"] = 15
	var r4 := FlightMath.step_response(stats, c4, "roll")
	print("  P=15 -> %s" % r4["status"])

	print("== amps ==")
	var sim := make_sim()
	sim.armed = true
	run_for(sim, 0.5)
	print("  armed idle: per motor %.2f A, total %.2f A" % [sim.amps[0], sim.total_amps])
	check(sim.amps[0] > 0.08 and sim.amps[0] < 0.2, "idle ~0.1 A per motor")
	sim.stick_throttle = 1.0
	run_for(sim, 0.3)
	print("  full throttle: per motor %.1f A  total %.1f A  V=%.2f" % [sim.amps[0], sim.total_amps, sim.v_term])
	check(sim.amps[0] > 14.0 and sim.amps[0] < 19.0, "full throttle ~15-18 A per motor")
	check(sim.total_amps > 60.0 and sim.total_amps < 80.0, "total up to ~75 A")
	check(sim.v_term < sim.v_oc - 1.0, "voltage sags under load")

	print("== hover ==")
	sim = make_sim()
	sim.armed = true
	sim.stick_throttle = 0.0
	# find hover throttle by simple search
	var best_alt := 0.0
	for thr in [0.28, 0.32, 0.36, 0.40]:
		sim = make_sim()
		sim.armed = true
		sim.stick_throttle = thr
		run_for(sim, 2.0)
		print("  thr %.2f -> alt %.2f vel %.2f amps %.1f tilt %.1f" % [thr, sim.pos.y, sim.vel.y, sim.total_amps, rad_to_deg(sim.basis.y.angle_to(Vector3.UP))])
	var s2 := make_sim()
	s2.armed = true
	s2.stick_throttle = 0.5
	run_for(s2, 1.0)
	print("  thr 0.5 after 1s: y=%.1f vy=%.1f" % [s2.pos.y, s2.vel.y])
	check(s2.pos.y > 3.0, "climbs at 50% throttle")
	check(rad_to_deg(s2.basis.y.angle_to(Vector3.UP)) < 5.0, "stays level without input (PID stable)")

	print("== roll step ==")
	s2.stick_roll = 1.0
	run_for(s2, 0.25)
	print("  after 0.25 s full right roll: roll rate %.0f deg/s, bank %.0f deg" % [rad_to_deg(-s2.omega.z), rad_to_deg(s2.basis.y.angle_to(Vector3.UP))])
	check(s2.omega.z < 0.0, "right stick banks right (negative z rotation)")
	s2.stick_roll = 0.0
	run_for(s2, 1.0)
	print("  rate after release %.1f deg/s" % rad_to_deg(s2.omega.length()))

	print("== yaw ==")
	var s5 := make_sim()
	s5.armed = true
	s5.stick_throttle = 0.45
	run_for(s5, 0.5)
	s5.stick_yaw = 1.0
	run_for(s5, 0.4)
	print("  yaw rate (right stick): %.0f deg/s (expected negative y => clockwise)" % rad_to_deg(s5.omega.y))
	check(s5.omega.y < -1.0, "yaw right turns clockwise")

	print("== angle mode ==")
	var sa := make_sim()
	sa.angle_mode = true
	sa.armed = true
	sa.stick_throttle = 0.45
	run_for(sa, 1.0)
	sa.stick_roll = 0.5
	run_for(sa, 1.2)
	var bank := rad_to_deg(sa.basis.y.angle_to(Vector3.UP))
	print("  half stick -> bank %.0f deg (expected about 27)" % bank)
	check(bank > 18.0 and bank < 36.0, "angle mode holds a tilt proportional to the stick")
	sa.stick_roll = 0.0
	run_for(sa, 1.5)
	check(rad_to_deg(sa.basis.y.angle_to(Vector3.UP)) < 4.0, "angle mode self-levels when the stick is released")

	print("== bad tuning in flight ==")
	for mult in [1.0, 2.0, 3.0, 4.0]:
		var sb := make_sim()
		sb.cfg = FlightMath.default_cfg()
		sb.cfg["pid"]["roll"]["p"] = 45 * mult
		sb.cfg["pid"]["pitch"]["p"] = 47 * mult
		sb.setup(sb.stats, sb.cfg)
		sb.ground_height = func(_x, _z): return 0.0
		sb.pos = Vector3(0, 0.1, 0)
		sb.armed = true
		sb.stick_throttle = 0.45
		run_for(sb, 1.0)
		var acc := 0.0
		var n := 0
		var peak := 0.0
		for i in 480:
			sb.step(1.0 / 240.0)
			acc += sb.omega.x * sb.omega.x + sb.omega.z * sb.omega.z
			peak = maxf(peak, absf(sb.omega.x))
			n += 1
		print("  P x%.0f: hover rate rms %.1f deg/s  peak %.0f deg/s  tilt %.1f" % [mult, rad_to_deg(sqrt(acc / n)), rad_to_deg(peak), rad_to_deg(sb.basis.y.angle_to(Vector3.UP))])
	var sd := make_sim()
	sd.cfg["pid"]["roll"]["d"] = 0
	sd.cfg["pid"]["pitch"]["d"] = 0
	sd.setup(sd.stats, sd.cfg)
	sd.ground_height = func(_x, _z): return 0.0
	sd.pos = Vector3(0, 0.1, 0)
	sd.armed = true
	sd.stick_throttle = 0.45
	run_for(sd, 1.0)
	sd.stick_roll = 0.3
	run_for(sd, 0.2)
	sd.stick_roll = 0.0
	var pk := 0.0
	for i in 240:
		sd.step(1.0 / 240.0)
		pk = maxf(pk, absf(sd.omega.z))
	print("  D=0 after a roll pulse, residual rate peak %.0f deg/s" % rad_to_deg(pk))

	print("== current limiting on a mismatched build ==")
	var sl := make_sim("frame_7", "2306", "5143")
	sl.armed = true
	sl.stick_throttle = 1.0
	run_for(sl, 1.0)
	print("  7in + 2306: total %.0f A, limiting=%s, power_lost=%s" % [sl.total_amps, sl.limiting, sl.power_lost])
	check(not sl.power_lost, "overloaded build is limited, not instantly dead")

	print("== battery to cutoff (hover-ish) ==")
	var s7 := make_sim()
	s7.armed = true
	s7.stick_throttle = 0.38
	var t := 0.0
	while not s7.power_lost and t < 1500.0:
		s7.step(1.0 / 240.0)
		t += 1.0 / 240.0
		if s7.pos.y < 0.0:
			break
	print("  cutoff after %.0f s, used %.0f mAh, v_term %.2f, soc %.2f" % [t, s7.used_mah, s7.v_term, s7.soc()])
	check(s7.power_lost, "battery cutoff triggers")
	var s8 := make_sim()
	s8.armed = true
	s8.stick_throttle = 0.45
	var t8 := 0.0
	while not s8.power_lost and t8 < 600.0:
		s8.step(1.0 / 240.0)
		t8 += 1.0 / 240.0
	s8.step(1.0 / 240.0)
	check(s8.power_lost and s8.cmd[0] == 0.0, "after cutoff motors get no command")

	print("== builds ==")
	for combo in [["frame_3", "2306", "5143"], ["frame_7", "2806", "5143"], ["frame_5", "2207", "5040"], ["frame_5", "2306", "5040"], ["frame_7", "2306", "5143"]]:
		var sm := make_sim(combo[0], combo[1], combo[2])
		sm.armed = true
		sm.stick_throttle = 1.0
		run_for(sm, 0.6)
		var hover_thr := _hover_stick(combo)
		print("  %s %s %s: mass %.0fg thrust %.1fN TWR %.1f  fullthr amps/motor %.1f total %.0f  V %.1f  hover stick %.2f" % [combo[0], combo[1], combo[2], sm.stats["mass_g"], sm.thrust_full, sm.stats["twr"], sm.amps[0], sm.total_amps, sm.v_term, hover_thr])
		var r5 := FlightMath.step_response(sm.stats, FlightMath.default_cfg(), "roll")
		print("      default tune: ", r5["status"])
	quit(1 if failures > 0 else 0)


func _hover_stick(combo: Array) -> float:
	var lo := 0.0
	var hi := 1.0
	for k in 12:
		var mid := (lo + hi) * 0.5
		var sm := make_sim(combo[0], combo[1], combo[2])
		sm.armed = true
		sm.stick_throttle = mid
		run_for(sm, 1.2)
		if sm.vel.y > 0.05:
			hi = mid
		else:
			lo = mid
	return (lo + hi) * 0.5
