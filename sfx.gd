extends Node

const RATE := 22050.0
const MUSIC_RATE := 8000.0

var sounds := {}
var players: Array = []
var next_player := 0
var last_time := {}
var music_player: AudioStreamPlayer

# what the game looked like last frame, so we can notice changes
var prev_stock = {"carb": 0, "lipid": 0, "amino": 0}
var prev_channels := 0
var prev_genes := 0
var prev_mitos := 0
var prev_engulfs := 0
var prev_overlay := false

func _ready() -> void:
	sounds["pop"] = render([
		{"f0": 380.0, "f1": 950.0, "t": 0.0, "d": 0.14, "v": 0.55, "decay": 7.0}], 0.14)
	sounds["absorb"] = render([
		{"f0": 900.0, "f1": 900.0, "t": 0.0, "d": 0.07, "v": 0.22, "decay": 9.0}], 0.07)
	sounds["store"] = render([
		{"f0": 300.0, "f1": 180.0, "t": 0.0, "d": 0.12, "v": 0.45, "decay": 8.0}], 0.12)
	sounds["tick"] = render([
		{"f0": 1500.0, "f1": 1500.0, "t": 0.0, "d": 0.04, "v": 0.18, "decay": 10.0, "wave": "tri"}], 0.04)
	sounds["overflow"] = render([
		{"f0": 140.0, "f1": 90.0, "t": 0.0, "d": 0.14, "v": 0.25, "decay": 6.0, "wave": "square"}], 0.14)
	sounds["build"] = render([
		{"f0": 220.0, "f1": 220.0, "t": 0.0, "d": 0.3, "v": 0.5, "decay": 5.0},
		{"f0": 330.0, "f1": 330.0, "t": 0.07, "d": 0.3, "v": 0.4, "decay": 5.0},
		{"f0": 440.0, "f1": 440.0, "t": 0.14, "d": 0.35, "v": 0.35, "decay": 5.0}], 0.5)
	sounds["gene"] = render([
		{"f0": 523.25, "f1": 523.25, "t": 0.0, "d": 0.45, "v": 0.3, "decay": 4.0, "wave": "tri"},
		{"f0": 659.25, "f1": 659.25, "t": 0.09, "d": 0.45, "v": 0.3, "decay": 4.0, "wave": "tri"},
		{"f0": 783.99, "f1": 783.99, "t": 0.18, "d": 0.45, "v": 0.3, "decay": 4.0, "wave": "tri"},
		{"f0": 1046.5, "f1": 1046.5, "t": 0.27, "d": 0.55, "v": 0.3, "decay": 4.0, "wave": "tri"}], 0.85)
	sounds["open"] = render([
		{"f0": 300.0, "f1": 620.0, "t": 0.0, "d": 0.2, "v": 0.35, "decay": 3.0}], 0.2)
	sounds["close"] = render([
		{"f0": 620.0, "f1": 300.0, "t": 0.0, "d": 0.18, "v": 0.3, "decay": 3.0}], 0.18)

	for i in 8:
		var p := AudioStreamPlayer.new()
		p.volume_db = -4.0
		add_child(p)
		players.append(p)

	music_player = AudioStreamPlayer.new()
	music_player.volume_db = -14.0
	add_child(music_player)
	music_player.stream = make_music()
	music_player.play()

	Game.converted.connect(_on_converted)

func _on_converted() -> void:
	play("tick", 1.0, 0.1)

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_M:
		music_player.stream_paused = not music_player.stream_paused

func play(sound_name: String, pitch: float = 1.0, min_gap: float = 0.0) -> void:
	if not sounds.has(sound_name):
		return
	var now = Time.get_ticks_msec() / 1000.0
	if min_gap > 0.0 and last_time.has(sound_name) and now - last_time[sound_name] < min_gap:
		return
	last_time[sound_name] = now
	var p: AudioStreamPlayer = players[next_player]
	next_player = (next_player + 1) % players.size()
	p.stream = sounds[sound_name]
	p.pitch_scale = pitch * randf_range(0.97, 1.03)
	p.play()

# Watch the game and play a sound whenever something changes.
func _process(_delta: float) -> void:
	if Game.stock.carb > prev_stock.carb:
		play("store", 1.0, 0.06)
	if Game.stock.lipid > prev_stock.lipid:
		play("absorb", 0.8, 0.06)
	if Game.stock.amino > prev_stock.amino:
		play("absorb", 1.15, 0.06)
	prev_stock.carb = Game.stock.carb
	prev_stock.lipid = Game.stock.lipid
	prev_stock.amino = Game.stock.amino

	if Game.channel_list.size() > prev_channels:
		play("build")
	prev_channels = Game.channel_list.size()

	if Game.unlocked.size() > prev_genes:
		play("gene")
	prev_genes = Game.unlocked.size()

	if Game.mitochondria > prev_mitos:
		play("build", 0.8)
	prev_mitos = Game.mitochondria

	var scene = get_tree().current_scene
	if scene != null:
		var traffic = scene.get_node_or_null("Traffic")
		if traffic != null:
			if traffic.engulf_count > prev_engulfs:
				play("pop")
			prev_engulfs = traffic.engulf_count
		var nucleus = scene.get_node_or_null("Nucleus")
		if nucleus != null and nucleus.layer != null:
			var open = nucleus.layer.visible
			if open and not prev_overlay:
				play("open")
			if prev_overlay and not open:
				play("close")
			prev_overlay = open

# Builds a sound from a list of notes and mixes them together.
func render(notes: Array, total: float) -> AudioStreamWAV:
	var n = int(RATE * total)
	var buf := PackedFloat32Array()
	buf.resize(n)
	for note in notes:
		var wave = note.get("wave", "sine")
		var start = int(note.t * RATE)
		var count = int(note.d * RATE)
		var phase := 0.0
		for i in count:
			var idx = start + i
			if idx >= n:
				break
			var k = float(i) / float(count)
			phase += TAU * lerpf(note.f0, note.f1, k) / RATE
			var s = sin(phase)
			if wave == "tri":
				s = asin(sin(phase)) * 2.0 / PI
			elif wave == "square":
				s = signf(sin(phase))
			var env = exp(-note.decay * k) * minf(float(i) / (RATE * 0.004), 1.0)
			buf[idx] += s * env * note.v
	return to_wav(buf, RATE, false, 1.0)

func to_wav(buf: PackedFloat32Array, rate: float, loop: bool, scale: float) -> AudioStreamWAV:
	var n = buf.size()
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		var v = clampf(buf[i] * scale, -1.0, 1.0)
		data.encode_s16(i * 2, int(v * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = int(rate)
	wav.stereo = false
	wav.data = data
	if loop:
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = n
	return wav

# One note of the music. Notes wrap round the end so the loop is seamless.
func add_note(buf: PackedFloat32Array, f: float, t0: float, d: float, vol: float, attack: float, release: float) -> void:
	var n = buf.size()
	var start = int(t0 * MUSIC_RATE)
	var total = int((d + release) * MUSIC_RATE)
	for i in total:
		var t = float(i) / MUSIC_RATE
		var env = 1.0
		if t < attack:
			env = t / attack
		if t > d:
			env = env * (1.0 - (t - d) / release)
		var ph = TAU * f * t
		var s = sin(ph) + 0.25 * sin(2.0 * ph)
		buf[(start + i) % n] += s * env * vol

# A slow chord pad (Am, F, C, G) with a few pentatonic notes floating over it.
func make_music() -> AudioStreamWAV:
	var n = int(MUSIC_RATE * 16.0)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var chords = [
		[110.0, 164.81, 261.63],
		[87.31, 174.61, 261.63],
		[130.81, 196.0, 329.63],
		[98.0, 196.0, 293.66],
	]
	for c in 4:
		for f in chords[c]:
			add_note(buf, f, c * 4.0, 4.0, 0.16, 1.4, 1.6)
	var pluck_f = [440.0, 523.25, 659.25, 587.33, 783.99, 659.25, 523.25, 440.0]
	var pluck_t = [1.0, 2.5, 4.5, 6.0, 8.5, 10.0, 12.0, 14.0]
	for i in pluck_f.size():
		add_note(buf, pluck_f[i], pluck_t[i], 0.05, 0.10, 0.01, 2.0)
	var peak := 0.001
	for i in n:
		peak = maxf(peak, absf(buf[i]))
	return to_wav(buf, MUSIC_RATE, true, 0.7 / peak)
