extends Node
## Fully procedural audio (no asset files): UI/event SFX, a soft generative music
## bed and a synthesized motor whine. Volumes come from Settings (Music / SFX buses).

const RATE := 22050

var _sfx: Dictionary = {}
var _sfx_players: Array[AudioStreamPlayer] = []
var _sfx_next := 0

var _music: AudioStreamPlayer
var _music_pb: AudioStreamGeneratorPlayback
var _music_t := 0.0
var _music_enabled := true

var _motor: AudioStreamPlayer
var _motor_pb: AudioStreamGeneratorPlayback
var _motor_phase := [0.0, 0.0, 0.0, 0.0]
var motor_level := 0.0     # 0..1 loudness
var motor_pitch := 0.0     # 0..1 average rpm
var _motor_smooth := 0.0

var _rng := RandomNumberGenerator.new()

const CHORDS := [
	[220.0, 261.63, 329.63, 440.0],   # Am
	[174.61, 220.0, 261.63, 349.23],  # F
	[261.63, 329.63, 392.0, 523.25],  # C
	[196.0, 246.94, 293.66, 392.0],   # G
]


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.randomize()
	Settings.apply_audio()
	# synthesise the UI/event sounds on a worker thread so startup never stalls on it
	_sfx_task = WorkerThreadPool.add_task(_build_sfx_threaded, false, "sfx synth")
	for i in 6:
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		_sfx_players.append(p)
	_music = _make_generator("Music", 0.25)
	_motor = _make_generator("SFX", 0.12)
	_motor.play()
	_motor_pb = _motor.get_stream_playback()
	# start the music a moment after the window is up (keeps the first frames free)
	get_tree().create_timer(1.5).timeout.connect(func():
		_music.play()
		_music_pb = _music.get_stream_playback())


func _make_generator(bus: String, buffer_len: float) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	var g := AudioStreamGenerator.new()
	g.mix_rate = RATE
	g.buffer_length = buffer_len
	p.stream = g
	p.bus = bus
	add_child(p)
	return p


func play(name: String, pitch: float = 1.0) -> void:
	if not _sfx.has(name) or _sfx_players.is_empty():
		return
	var p := _sfx_players[_sfx_next]
	_sfx_next = (_sfx_next + 1) % _sfx_players.size()
	p.stream = _sfx[name]
	p.pitch_scale = pitch
	p.play()


func set_music(on: bool) -> void:
	_music_enabled = on


func _process(_dt: float) -> void:
	# synthesis runs in GDScript, so skip it entirely when it would be inaudible
	if _music_enabled and Settings.music_vol > 0.001 and Settings.master_vol > 0.001:
		_fill_music()
	if (motor_level > 0.001 or _motor_smooth > 0.002) and Settings.sfx_vol > 0.001:
		_fill_motor()


# --- generators -------------------------------------------------------------
func _fill_music() -> void:
	if _music_pb == null:
		return
	var n := _music_pb.get_frames_available()
	if n <= 0:
		return
	var buf := PackedVector2Array()
	buf.resize(n)
	var dt := 1.0 / RATE
	for i in n:
		var v := 0.0
		if _music_enabled:
			var bar := int(_music_t / 4.0) % CHORDS.size()
			var ch: Array = CHORDS[bar]
			var local := fmod(_music_t, 4.0)
			var env := minf(local * 1.5, 1.0) * minf((4.0 - local) * 1.5, 1.0)
			for f in ch:
				v += sin(TAU * f * _music_t * 0.5) * 0.05 * env
			# gentle plucked arpeggio
			var step := int(local * 2.0) % 4
			var lt := fmod(local * 2.0, 1.0)
			v += sin(TAU * ch[step] * 2.0 * _music_t) * exp(-lt * 5.0) * 0.045
		buf[i] = Vector2(v, v)
		_music_t += dt
	_music_pb.push_buffer(buf)


func _fill_motor() -> void:
	if _motor_pb == null:
		return
	var n := _motor_pb.get_frames_available()
	if n <= 0:
		return
	_motor_smooth = lerpf(_motor_smooth, motor_level, 0.1)
	var buf := PackedVector2Array()
	buf.resize(n)
	var base := 70.0 + motor_pitch * 380.0
	var amp := _motor_smooth * 0.22
	for i in n:
		var v := 0.0
		if amp > 0.001:
			for k in 4:
				var f := base * (1.0 + 0.012 * k)
				_motor_phase[k] = fposmod(_motor_phase[k] + f / RATE, 1.0)
				v += (_motor_phase[k] * 2.0 - 1.0) * 0.25
			v += _rng.randf_range(-1.0, 1.0) * 0.12 * motor_pitch
			v *= amp
		buf[i] = Vector2(v, v)
	_motor_pb.push_buffer(buf)


# --- SFX synthesis -----------------------------------------------------------
var _pcm: Dictionary = {}
var _sfx_task := -1


func _exit_tree() -> void:
	if _sfx_task != -1:
		WorkerThreadPool.wait_for_task_completion(_sfx_task)


func _build_sfx_threaded() -> void:
	_build_sfx()
	call_deferred("_finish_sfx")


## Wrap the synthesised PCM in streams on the main thread.
func _finish_sfx() -> void:
	for k in _pcm:
		var w := AudioStreamWAV.new()
		w.format = AudioStreamWAV.FORMAT_16_BITS
		w.mix_rate = RATE
		w.stereo = false
		w.data = _pcm[k]
		_sfx[k] = w
	print("audio: sfx ready")


func _build_sfx() -> void:
	_pcm["click"] = _tone([[900.0, 1.0]], 0.05, 40.0, 0)
	_pcm["snap"] = _tone([[240.0, 1.0], [480.0, 0.5]], 0.11, 28.0, 2)
	_pcm["error"] = _tone([[150.0, 1.0], [157.0, 1.0]], 0.28, 7.0, 1)
	_pcm["wire"] = _tone([[760.0, 1.0], [1140.0, 0.4]], 0.12, 22.0, 0)
	_pcm["gate"] = _tone([[660.0, 1.0], [990.0, 0.8]], 0.3, 9.0, 0)
	_pcm["warn"] = _tone([[1250.0, 1.0]], 0.16, 12.0, 1)
	_pcm["crash"] = _tone([[70.0, 1.0]], 0.8, 4.5, 3)
	_pcm["arm"] = _tone([[500.0, 1.0], [750.0, 0.8], [1000.0, 0.6]], 0.3, 6.0, 0)
	_pcm["success"] = _tone([[523.0, 1.0], [659.0, 0.9], [784.0, 0.9], [1047.0, 0.8]], 0.7, 3.0, 0)
	_pcm["beep"] = _tone([[880.0, 1.0]], 0.12, 10.0, 0)


## shape: 0 sine, 1 square, 2 sine + noise click, 3 noise burst
func _tone(partials: Array, dur: float, decay: float, shape: int) -> PackedByteArray:
	var n := int(RATE * dur)
	var bytes := PackedByteArray()
	bytes.resize(n * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	var lp := 0.0
	for i in n:
		var t := float(i) / RATE
		var env := exp(-t * decay)
		var v := 0.0
		for pt in partials:
			var ph: float = TAU * pt[0] * t
			if shape == 1:
				v += (1.0 if sin(ph) >= 0.0 else -1.0) * pt[1] * 0.5
			else:
				v += sin(ph) * pt[1]
		v /= float(partials.size())
		if shape == 2:
			v = v * 0.7 + rng.randf_range(-1.0, 1.0) * exp(-t * 90.0) * 0.6
		elif shape == 3:
			lp = lerpf(lp, rng.randf_range(-1.0, 1.0), 0.15)
			v = lp * 1.6 + sin(TAU * partials[0][0] * t) * 0.4
		bytes.encode_s16(i * 2, int(clampf(v * env * 0.6, -1.0, 1.0) * 32767.0))
	return bytes
