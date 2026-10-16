extends Control

# Stardew-style fishing: wait for a bite, hook it in time, then keep the green bar on the fish until the meter fills.

signal completed
signal failed
signal closed

enum Phase { WAIT, BITE, REEL, RESULT }

const TRACK_H := 520.0
const FISH_R := 16.0
const BITE_WINDOW := 1.0
const CAUGHT_TIME := 0.7
const ESCAPED_TIME := 0.8
const LIFT := 1500.0
const GRAVITY := 900.0
const MAX_BAR_SPEED := 520.0
const BAR_BOUNCE := 0.35
const FISH_ACCEL := 1800.0
const START_PROGRESS := 0.25
const BAR_HEIGHTS := [150.0, 125.0, 100.0]
const FISH_SPEEDS := [150.0, 230.0, 320.0]
const DART_CHANCES := [0.1, 0.25, 0.4]
const INTERVAL_MIN := [0.9, 0.6, 0.35]
const INTERVAL_MAX := [1.8, 1.3, 0.9]
const FILL_RATES := [0.2, 0.17, 0.15]
const DRAIN_RATES := [0.12, 0.14, 0.15]
const FISH_COLORS := [Color(1.0, 0.55, 0.2), Color(0.92, 0.3, 0.4), Color(0.4, 0.75, 1.0), Color(0.8, 0.85, 0.3),
	Color(0.7, 0.45, 0.95), Color(0.95, 0.8, 0.3)]

var level := 0
var rng := RandomNumberGenerator.new()
var phase := Phase.WAIT
var wait_time := 1.5
var phase_time := 0.0
var time := 0.0
var fish_color := Color.ORANGE
var holding := false
var bar_pos := 0.0  # top of the catch bar on the track, 0 is the top
var bar_vel := 0.0
var bar_height := 150.0
var fish_y := 0.0
var fish_vel := 0.0
var fish_target := 0.0
var fish_speed_scale := 1.0
var fish_timer := 0.0
var progress := START_PROGRESS
var caught := false
var result_time := 0.0
var reeled := false
var done := false
var emitted := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP


func setup(difficulty: int, rng_seed: int) -> void:
	level = clampi(difficulty, 0, 2)
	rng.seed = rng_seed
	wait_time = rng.randf_range(1.0, 2.5)
	fish_color = FISH_COLORS[rng.randi_range(0, FISH_COLORS.size() - 1)]
	bar_height = BAR_HEIGHTS[level]
	fish_y = rng.randf_range(TRACK_H * 0.25, TRACK_H * 0.75)
	fish_target = fish_y
	bar_pos = TRACK_H - bar_height
	queue_redraw()


func complete_now() -> void:
	if emitted:
		return
	done = true
	emitted = true
	holding = false
	completed.emit()


func _process(delta: float) -> void:
	time += delta
	phase_time += delta
	match phase:
		Phase.WAIT:
			if phase_time >= wait_time:
				phase = Phase.BITE
				phase_time = 0.0
		Phase.BITE:
			if phase_time >= BITE_WINDOW:
				_finish(false)
		Phase.REEL:
			_update_reel(minf(delta, 0.05))
		Phase.RESULT:
			result_time += delta
			if result_time >= (CAUGHT_TIME if caught else ESCAPED_TIME) and not emitted:
				emitted = true
				if caught:
					completed.emit()
				else:
					failed.emit()
	queue_redraw()


func _finish(success: bool) -> void:
	phase = Phase.RESULT
	caught = success
	result_time = 0.0
	done = true
	holding = false


func _start_reel() -> void:
	phase = Phase.REEL
	reeled = true
	phase_time = 0.0
	holding = false
	progress = START_PROGRESS
	bar_vel = 0.0
	_pick_fish_target()


func _gui_input(event: InputEvent) -> void:
	if done:
		accept_event()
		return
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			closed.emit()
		elif event.button_index == MOUSE_BUTTON_LEFT:
			if phase == Phase.REEL:
				holding = event.pressed
			elif event.pressed:
				if phase == Phase.BITE:
					_start_reel()
				elif phase == Phase.WAIT:
					_finish(false)
	accept_event()


func _pick_fish_target() -> void:
	fish_timer = rng.randf_range(INTERVAL_MIN[level], INTERVAL_MAX[level])
	if rng.randf() < DART_CHANCES[level]:
		var direction := -1.0 if fish_y > TRACK_H / 2.0 else 1.0
		if rng.randf() < 0.25:
			direction = -direction
		fish_target = clampf(fish_y + direction * rng.randf_range(180.0, 320.0), FISH_R, TRACK_H - FISH_R)
		fish_speed_scale = 1.8
	else:
		fish_target = rng.randf_range(FISH_R, TRACK_H - FISH_R)
		fish_speed_scale = 1.0


func _update_reel(dt: float) -> void:
	fish_timer -= dt
	if fish_timer <= 0.0:
		_pick_fish_target()
	var top_speed: float = FISH_SPEEDS[level] * fish_speed_scale
	var desired := clampf((fish_target - fish_y) * 3.0, -top_speed, top_speed)
	fish_vel = move_toward(fish_vel, desired, FISH_ACCEL * dt)
	fish_y = clampf(fish_y + fish_vel * dt, FISH_R, TRACK_H - FISH_R)

	bar_vel = clampf(bar_vel + (-LIFT if holding else GRAVITY) * dt, -MAX_BAR_SPEED, MAX_BAR_SPEED)
	bar_pos += bar_vel * dt
	if bar_pos < 0.0:
		bar_pos = 0.0
		bar_vel = 0.0
	elif bar_pos > TRACK_H - bar_height:
		bar_pos = TRACK_H - bar_height
		bar_vel = -bar_vel * BAR_BOUNCE if bar_vel > 60.0 else 0.0

	if _fish_in_bar():
		progress += float(FILL_RATES[level]) * dt
	else:
		progress -= float(DRAIN_RATES[level]) * dt
	progress = clampf(progress, 0.0, 1.0)
	if progress >= 1.0:
		_finish(true)
	elif progress <= 0.0:
		_finish(false)


func _fish_in_bar() -> bool:
	return fish_y + FISH_R * 0.5 >= bar_pos and fish_y - FISH_R * 0.5 <= bar_pos + bar_height


func _text(text: String, pos: Vector2, font_size: int, color := Color.WHITE) -> void:
	var font := Ui.font()
	draw_string_outline(font, pos, text, HORIZONTAL_ALIGNMENT_CENTER, size.x, font_size, maxi(2, font_size / 4), Ui.NAVY)
	draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_CENTER, size.x, font_size, color)


func _ellipse(center: Vector2, rx: float, ry: float, count := 24) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in count + 1:
		var a := TAU * i / count
		points.append(center + Vector2(cos(a) * rx, sin(a) * ry))
	return points


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.8))
	if phase == Phase.REEL or (phase == Phase.RESULT and reeled):
		_draw_reel()
	else:
		_draw_lake()
	if phase == Phase.RESULT:
		var text := "Caught!" if caught else "It got away..."
		_text(text, Vector2(0, size.y / 2.0), 60, Color(0.7, 1.0, 0.75) if caught else Color(1.0, 0.65, 0.6))


func _draw_lake() -> void:
	var s := minf(1.0, minf((size.x - 40.0) / 760.0, (size.y - 150.0) / 440.0))
	var scene := Rect2(size / 2.0 - Vector2(380, 220) * s, Vector2(760, 440) * s)
	var water_y := scene.position.y + scene.size.y * 0.38
	draw_rect(scene, Color(0.62, 0.82, 0.97))
	draw_rect(Rect2(scene.position.x, scene.position.y + scene.size.y * 0.15, scene.size.x, scene.size.y * 0.23), Color(0.72, 0.88, 0.98))
	draw_colored_polygon(PackedVector2Array([Vector2(scene.position.x, water_y), Vector2(scene.position.x + 140.0 * s, water_y - 60.0 * s),
		Vector2(scene.position.x + 300.0 * s, water_y), Vector2(scene.position.x + 480.0 * s, water_y - 40.0 * s),
		Vector2(scene.end.x, water_y)]), Color(0.38, 0.55, 0.45))
	draw_circle(scene.position + Vector2(620, 60) * s, 28.0 * s, Color(1.0, 0.95, 0.65))
	draw_rect(Rect2(scene.position.x, water_y, scene.size.x, scene.end.y - water_y), Color(0.16, 0.42, 0.72))
	for row in 7:
		var y := water_y + (24.0 + row * 38.0) * s
		var points := PackedVector2Array()
		for i in 25:
			var x := scene.position.x + scene.size.x * i / 24.0
			points.append(Vector2(x, y + sin(time * 1.5 + i * 0.7 + row) * 3.0 * s))
		draw_polyline(points, Color(0.5, 0.75, 0.95, 0.5), 2.0)
	draw_rect(scene, Color.WHITE, false, 3.0)

	var bite := phase == Phase.BITE
	var bob := Vector2(scene.get_center().x, water_y + 150.0 * s)
	bob.y += sin(time * 2.0) * 3.0 * s
	if bite:
		bob.y += (10.0 + sin(time * 40.0) * 4.0) * s
	for k in 3:
		var t := fposmod(time * (0.9 if bite else 0.4) + k / 3.0, 1.0)
		draw_polyline(_ellipse(bob + Vector2(0, 6.0 * s), (14.0 + t * 60.0) * s, (5.0 + t * 20.0) * s), Color(0.85, 0.95, 1.0, 1.0 - t), 2.0)
	var tip := Vector2(scene.end.x - 120.0 * s, scene.position.y + 150.0 * s)
	draw_line(Vector2(scene.end.x - 10.0 * s, scene.end.y - 10.0 * s), tip, Color(0.4, 0.26, 0.12), 6.0 * s)
	draw_polyline(PackedVector2Array([tip, tip.lerp(bob, 0.5) + Vector2(0, 28.0 * s), bob]), Color(1, 1, 1, 0.8), 1.5)
	draw_circle(bob, 11.0 * s, Color(0.95, 0.95, 0.95))
	draw_circle(bob + Vector2(0, -4.0 * s), 11.0 * s, Color(0.9, 0.2, 0.2))
	draw_rect(Rect2(bob + Vector2(-11.0 * s, -2.0 * s), Vector2(22.0 * s, 4.0 * s)), Color.WHITE)
	if bite:
		for k in 8:
			var a := k * TAU / 8.0 + time * 3.0
			draw_circle(bob + Vector2(cos(a), sin(a) * 0.5) * (26.0 + fposmod(time * 60.0, 14.0)) * s, 3.0 * s, Color(0.9, 0.97, 1.0, 0.9))
		var left := 1.0 - phase_time / BITE_WINDOW
		draw_arc(bob, 38.0 * s, -PI / 2.0, -PI / 2.0 + TAU * left, 32, Color(1.0, 0.9, 0.3), 4.0)
		_text("!", bob + Vector2(-size.x / 2.0, -50.0 * s), 72, Color(1.0, 0.9, 0.25))

	_text("Fishing", Vector2(0, scene.position.y - 22.0), 34, Color(0.7, 0.9, 1.0))
	var help := "Wait for the bobber to dip, then click as soon as you see the !"
	if bite:
		help = "Click now!"
	_text(help, Vector2(0, scene.end.y + 40.0), 24)
	_text("Right click to step away", Vector2(0, scene.end.y + 68.0), 18, Color(0.85, 0.9, 1.0))


func _draw_reel() -> void:
	var s := minf(1.0, (size.y - 130.0) / TRACK_H)
	var top := (size.y - TRACK_H * s) / 2.0 - 10.0
	var track := Rect2(size.x / 2.0 - 60.0 * s, top, 60.0 * s, TRACK_H * s)
	var meter := Rect2(size.x / 2.0 + 30.0 * s, top, 24.0 * s, TRACK_H * s)
	draw_rect(Rect2(track.position - Vector2(50, 14), Vector2(meter.end.x - track.position.x + 100.0, track.size.y + 28.0)), Color(0.08, 0.14, 0.24))
	for i in 10:
		var shade := Color(0.12, 0.32, 0.6).lerp(Color(0.05, 0.15, 0.35), i / 9.0)
		draw_rect(Rect2(track.position + Vector2(0, track.size.y * i / 10.0), Vector2(track.size.x, track.size.y / 10.0 + 1.0)), shade)
	for k in 6:
		var by := track.end.y - fposmod(time * (20.0 + k * 7.0) + k * 90.0, track.size.y)
		draw_circle(Vector2(track.position.x + track.size.x * (0.2 + 0.12 * k), by), (2.0 + k % 3) * s, Color(0.7, 0.9, 1.0, 0.25))
	var bar := Rect2(track.position.x - 3.0, top + bar_pos * s, track.size.x + 6.0, bar_height * s)
	var inside := _fish_in_bar()
	draw_rect(bar, Color(0.3, 0.85, 0.4, 0.8 if inside else 0.55))
	draw_rect(bar, Color(0.75, 1.0, 0.8) if inside else Color(0.4, 0.7, 0.45), false, 3.0)
	_draw_fish(Vector2(track.get_center().x, top + fish_y * s), s)
	draw_rect(track, Color.WHITE, false, 3.0)
	draw_rect(meter, Color(0.1, 0.1, 0.14))
	var fill := meter.size.y * progress
	draw_rect(Rect2(meter.position.x, meter.end.y - fill, meter.size.x, fill), Color(1.0, 0.35, 0.3).lerp(Color(0.35, 1.0, 0.45), progress))
	draw_rect(meter, Color.WHITE, false, 3.0)
	var percent_pos := Vector2(meter.end.x + 8.0, clampf(meter.end.y - fill + 7.0, meter.position.y + 14.0, meter.end.y))
	draw_string_outline(Ui.font(), percent_pos, "%d%%" % roundi(progress * 100.0), HORIZONTAL_ALIGNMENT_LEFT, 70.0, 18, 6, Ui.NAVY)
	draw_string(Ui.font(), percent_pos, "%d%%" % roundi(progress * 100.0), HORIZONTAL_ALIGNMENT_LEFT, 70.0, 18)

	_text("Fishing", Vector2(0, top - 28.0), 34, Color(0.7, 0.9, 1.0))
	_text("Hold the mouse to lift the bar and keep it on the fish", Vector2(0, track.end.y + 38.0), 24)
	_text("Right click to step away", Vector2(0, track.end.y + 64.0), 18, Color(0.85, 0.9, 1.0))


func _draw_fish(center: Vector2, s: float) -> void:
	var wiggle := sin(time * 10.0) * 3.0 * s
	var body := _ellipse(center, 16.0 * s, 9.0 * s, 14)
	body.remove_at(body.size() - 1)
	draw_colored_polygon(body, fish_color)
	draw_colored_polygon(PackedVector2Array([center + Vector2(12, 0) * s, center + Vector2(26, -9) * s + Vector2(0, wiggle),
		center + Vector2(26, 9) * s + Vector2(0, wiggle)]), fish_color.darkened(0.15))
	draw_colored_polygon(PackedVector2Array([center + Vector2(-2, -8) * s, center + Vector2(6, -15) * s, center + Vector2(8, -7) * s]), fish_color.darkened(0.25))
	draw_polyline(_ellipse(center, 16.0 * s, 9.0 * s, 14), Color(0.1, 0.1, 0.15, 0.8), 1.5)
	draw_circle(center + Vector2(-8, -2) * s, 3.0 * s, Color.WHITE)
	draw_circle(center + Vector2(-9, -2) * s, 1.5 * s, Color.BLACK)
