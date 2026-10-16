extends Control

# Putting: drag back from the ball like a slingshot, release to putt, and sink it in the cup.

signal completed
signal closed

const COURSE := Vector2(880, 420)
const BALL_R := 9.0
const CUP_R := 16.0
const MAX_DRAG := 160.0
const MIN_DRAG := 10.0
const MAX_SPEED := 1300.0
const SINK_SPEED := 260.0  # faster than this and the ball rolls over the cup
const STOP_SPEED := 10.0
const GRASS_FRICTION := 1.0  # per second
const SAND_FRICTION := 3.2
const WALL_BOUNCE := 0.8
const BUMPER_BOUNCE := 0.75
const CORRIDOR_HALF := 50.0  # keeps a clear lane of at least 100px around the straight shot
const SUNK_TIME := 0.8
const BUMPER_COUNTS := [2, 3, 3]

var level := 0
var tee := Vector2.ZERO
var cup_pos := Vector2.ZERO
var bumpers: Array[Rect2] = []
var sand: Array[Rect2] = []
var sand_dots := PackedVector2Array()
var has_pond := false
var pond_center := Vector2.ZERO
var pond_radius := 0.0
var ball_pos := Vector2.ZERO
var ball_vel := Vector2.ZERO
var shot_start := Vector2.ZERO
var moving := false
var aiming := false
var aim_mouse := Vector2.ZERO
var strokes := 0
var message := ""
var message_time := 0.0
var sunk := false
var sunk_time := 0.0
var time := 0.0
var done := false
var emitted := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP


func setup(difficulty: int, rng_seed: int) -> void:
	level = clampi(difficulty, 0, 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = rng_seed
	tee = Vector2(90, rng.randf_range(110, 310))
	cup_pos = Vector2(790, rng.randf_range(110, 310))
	ball_pos = tee
	shot_start = tee
	bumpers.clear()
	sand.clear()
	has_pond = false
	if level >= 2:
		_place_pond(rng)
	var bumper_count: int = BUMPER_COUNTS[level]
	for i in bumper_count:
		_place_bumper(rng)
	if level >= 1:
		_place_sand(rng)
	queue_redraw()


func complete_now() -> void:
	if emitted:
		return
	done = true
	emitted = true
	aiming = false
	completed.emit()


func _near_line(rect: Rect2) -> bool:
	var grown := rect.grow(CORRIDOR_HALF)
	var steps := ceili(tee.distance_to(cup_pos) / 10.0)
	for i in steps + 1:
		if grown.has_point(tee.lerp(cup_pos, float(i) / steps)):
			return true
	return false


func _circle_hits_rect(center: Vector2, radius: float, rect: Rect2) -> bool:
	var closest := Vector2(clampf(center.x, rect.position.x, rect.end.x), clampf(center.y, rect.position.y, rect.end.y))
	return center.distance_to(closest) < radius


func _overlaps_placed(rect: Rect2) -> bool:
	for other in bumpers:
		if rect.grow(14.0).intersects(other):
			return true
	for other in sand:
		if rect.grow(14.0).intersects(other):
			return true
	return has_pond and _circle_hits_rect(pond_center, pond_radius + 14.0, rect)


func _place_bumper(rng: RandomNumberGenerator) -> void:
	for attempt in 60:
		var w := rng.randf_range(18.0, 30.0)
		var h := rng.randf_range(60.0, 110.0)
		if rng.randf() < 0.4:
			var swap := w
			w = h
			h = swap
		var rect := Rect2(rng.randf_range(190.0, 690.0 - w), rng.randf_range(30.0, 390.0 - h), w, h)
		if not _near_line(rect) and not _overlaps_placed(rect):
			bumpers.append(rect)
			return


func _place_sand(rng: RandomNumberGenerator) -> void:
	for attempt in 60:
		var w := rng.randf_range(110.0, 160.0)
		var h := rng.randf_range(70.0, 120.0)
		var rect := Rect2(rng.randf_range(230.0, 650.0 - w), rng.randf_range(20.0, 400.0 - h), w, h)
		if not _overlaps_placed(rect):
			sand.append(rect)
			sand_dots.clear()
			for i in 40:
				sand_dots.append(rect.position + Vector2(rng.randf() * rect.size.x, rng.randf() * rect.size.y))
			return


func _place_pond(rng: RandomNumberGenerator) -> void:
	for attempt in 60:
		var radius := rng.randf_range(42.0, 56.0)
		var center := Vector2(rng.randf_range(280.0, 640.0), rng.randf_range(radius + 20.0, COURSE.y - radius - 20.0))
		var nearest := Geometry2D.get_closest_point_to_segment(center, tee, cup_pos)
		if center.distance_to(nearest) >= radius + CORRIDOR_HALF:
			has_pond = true
			pond_center = center
			pond_radius = radius
			return


func _scale() -> float:
	return clampf(minf((size.x - 40.0) / COURSE.x, (size.y - 170.0) / COURSE.y), 0.3, 1.0)


func _origin() -> Vector2:
	return (size - COURSE * _scale()) / 2.0


func _to_screen(p: Vector2) -> Vector2:
	return _origin() + p * _scale()


func _to_local(p: Vector2) -> Vector2:
	return (p - _origin()) / _scale()


func _in_sand(p: Vector2) -> bool:
	for rect in sand:
		if rect.has_point(p):
			return true
	return false


func _gui_input(event: InputEvent) -> void:
	if done:
		accept_event()
		return
	if event is InputEventMouseMotion:
		if aiming:
			aim_mouse = _to_local(event.position)
	elif event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			closed.emit()
		elif event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				var grab := maxf(BALL_R + 14.0, 22.0 / _scale())
				if not moving and _to_local(event.position).distance_to(ball_pos) <= grab:
					aiming = true
					aim_mouse = _to_local(event.position)
			elif aiming:
				aiming = false
				var pull := ball_pos - _to_local(event.position)
				if pull.length() >= MIN_DRAG:
					_shoot(_velocity_for(pull))
	accept_event()


func _velocity_for(pull: Vector2) -> Vector2:
	return pull.normalized() * clampf(pull.length() / MAX_DRAG, 0.0, 1.0) * MAX_SPEED


func _shoot(velocity: Vector2) -> void:
	strokes += 1
	shot_start = ball_pos
	ball_vel = velocity
	moving = true
	message = ""
	message_time = 0.0


func _process(delta: float) -> void:
	time += delta
	if message_time > 0.0:
		message_time -= delta
	if sunk:
		sunk_time += delta
		if sunk_time >= SUNK_TIME and not emitted:
			emitted = true
			completed.emit()
	elif moving:
		var remaining := minf(delta, 0.05)
		var steps := clampi(ceili(ball_vel.length() * remaining / 4.0), 1, 40)
		for i in steps:
			_advance(remaining / steps)
			if not moving:
				break
	queue_redraw()


func _advance(dt: float) -> void:
	var friction := SAND_FRICTION if _in_sand(ball_pos) else GRASS_FRICTION
	ball_vel *= exp(-friction * dt)
	ball_pos += ball_vel * dt
	if ball_pos.x < BALL_R:
		ball_pos.x = BALL_R
		ball_vel.x = absf(ball_vel.x) * WALL_BOUNCE
	elif ball_pos.x > COURSE.x - BALL_R:
		ball_pos.x = COURSE.x - BALL_R
		ball_vel.x = -absf(ball_vel.x) * WALL_BOUNCE
	if ball_pos.y < BALL_R:
		ball_pos.y = BALL_R
		ball_vel.y = absf(ball_vel.y) * WALL_BOUNCE
	elif ball_pos.y > COURSE.y - BALL_R:
		ball_pos.y = COURSE.y - BALL_R
		ball_vel.y = -absf(ball_vel.y) * WALL_BOUNCE
	for rect in bumpers:
		_bounce_off(rect)
	if has_pond and ball_pos.distance_to(pond_center) < pond_radius:
		strokes += 1
		ball_pos = shot_start
		ball_vel = Vector2.ZERO
		moving = false
		message = "Splash! Back to the last spot, +1 stroke"
		message_time = 2.0
		return
	var speed := ball_vel.length()
	if ball_pos.distance_to(cup_pos) < CUP_R and speed < SINK_SPEED:
		sunk = true
		done = true
		moving = false
		aiming = false
		sunk_time = 0.0
		return
	if speed < STOP_SPEED:
		ball_vel = Vector2.ZERO
		moving = false


func _bounce_off(rect: Rect2) -> void:
	var closest := Vector2(clampf(ball_pos.x, rect.position.x, rect.end.x), clampf(ball_pos.y, rect.position.y, rect.end.y))
	var diff := ball_pos - closest
	var distance_sq := diff.length_squared()
	if distance_sq >= BALL_R * BALL_R:
		return
	var normal := Vector2.ZERO
	if distance_sq > 0.0001:
		normal = diff / sqrt(distance_sq)
		ball_pos = closest + normal * BALL_R
	else:
		# the centre is inside the rectangle: leave through the nearest edge
		var gaps := [ball_pos.x - rect.position.x, rect.end.x - ball_pos.x, ball_pos.y - rect.position.y, rect.end.y - ball_pos.y]
		var directions := [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]
		var best := 0
		for i in 4:
			if gaps[i] < gaps[best]:
				best = i
		normal = directions[best]
		ball_pos += normal * (gaps[best] + BALL_R)
	if ball_vel.dot(normal) < 0.0:
		ball_vel = ball_vel.bounce(normal) * BUMPER_BOUNCE


func _text(text: String, pos: Vector2, font_size: int, color := Color.WHITE) -> void:
	var font := Ui.font()
	draw_string_outline(font, pos, text, HORIZONTAL_ALIGNMENT_CENTER, size.x, font_size, maxi(2, font_size / 4), Ui.NAVY)
	draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_CENTER, size.x, font_size, color)


func _power_color(power: float) -> Color:
	return Color(0.3, 0.9, 0.35).lerp(Color(1.0, 0.25, 0.2), power)


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.8))
	var s := _scale()
	var origin := _origin()
	var course := Rect2(origin, COURSE * s)
	draw_rect(course.grow(12.0), Color(0.42, 0.28, 0.15))
	draw_rect(course, Color(0.24, 0.55, 0.26))
	for i in 16:
		if i % 2 == 0:
			draw_rect(Rect2(origin + Vector2(i * 55.0 * s, 0), Vector2(55.0 * s, course.size.y)).intersection(course), Color(0.27, 0.6, 0.29))
	for rect in sand:
		draw_rect(Rect2(_to_screen(rect.position), rect.size * s), Color(0.86, 0.76, 0.5))
		draw_rect(Rect2(_to_screen(rect.position), rect.size * s), Color(0.7, 0.6, 0.38), false, 2.0)
	for dot in sand_dots:
		draw_circle(_to_screen(dot), 1.5 * s, Color(0.7, 0.6, 0.38))
	if has_pond:
		var center := _to_screen(pond_center)
		draw_circle(center, pond_radius * s, Color(0.2, 0.5, 0.88))
		draw_arc(center, pond_radius * s, 0.0, TAU, 40, Color(0.7, 0.88, 1.0), 3.0 * s)
		var ripple := fposmod(time * 0.5, 1.0)
		draw_arc(center, pond_radius * s * (0.3 + 0.5 * ripple), 0.0, TAU, 32, Color(0.8, 0.92, 1.0, 1.0 - ripple), 2.0)
	var cup := _to_screen(cup_pos)
	draw_circle(cup, CUP_R * s + 3.0 * s, Color(0.1, 0.25, 0.1))
	draw_circle(cup, CUP_R * s, Color(0.03, 0.03, 0.03))
	for rect in bumpers:
		var r := Rect2(_to_screen(rect.position), rect.size * s)
		draw_rect(Rect2(r.position + Vector2(3, 4) * s, r.size), Color(0, 0, 0, 0.3))
		draw_rect(r, Color(0.55, 0.38, 0.22))
		draw_rect(r, Color(0.3, 0.2, 0.1), false, 3.0)
		draw_line(r.position + Vector2(2, 2), r.position + Vector2(r.size.x - 2.0, 2.0), Color(0.75, 0.58, 0.38), 2.0)
	draw_line(cup, cup + Vector2(0, -64.0 * s), Color(0.95, 0.95, 0.95), 3.0 * s)
	draw_colored_polygon(PackedVector2Array([cup + Vector2(0, -64.0 * s), cup + Vector2(30.0 * s, -54.0 * s), cup + Vector2(0, -44.0 * s)]), Color(0.95, 0.25, 0.25))
	_draw_ball(s)
	_draw_aim(s)
	_draw_texts(s, course)


func _draw_ball(s: float) -> void:
	var pos := _to_screen(ball_pos)
	var radius := BALL_R * s
	if sunk:
		var t := clampf(sunk_time / 0.3, 0.0, 1.0)
		pos = pos.lerp(_to_screen(cup_pos), t)
		radius *= 1.0 - 0.7 * t
	draw_circle(pos + Vector2(2, 3) * s, radius, Color(0, 0, 0, 0.3))
	draw_circle(pos, radius, Color(0.97, 0.97, 0.97))
	draw_arc(pos, radius, 0.0, TAU, 20, Color(0.55, 0.55, 0.6), 1.5)


func _draw_aim(s: float) -> void:
	var meter := Rect2(Vector2(size.x / 2.0 - 150.0 * s, _origin().y + COURSE.y * s + 24.0), Vector2(300.0 * s, 14.0))
	draw_rect(meter, Color(0.08, 0.1, 0.14))
	var power := 0.0
	if aiming:
		var pull := ball_pos - aim_mouse
		power = clampf(pull.length() / MAX_DRAG, 0.0, 1.0)
		if pull.length() >= MIN_DRAG:
			var dir := pull.normalized()
			var start := _to_screen(ball_pos)
			var tip := start + dir * (30.0 + power * 150.0) * s
			var col := _power_color(power)
			draw_line(start + dir * 14.0 * s, tip, col, 4.0 * s)
			var side := dir.orthogonal()
			draw_colored_polygon(PackedVector2Array([tip + dir * 14.0 * s, tip + side * 9.0 * s, tip - side * 9.0 * s]), col)
		draw_line(_to_screen(ball_pos), _to_screen(aim_mouse), Color(1, 1, 1, 0.4), 2.0)
	if power > 0.0:
		draw_rect(Rect2(meter.position, Vector2(meter.size.x * power, meter.size.y)), _power_color(power))
	draw_rect(meter, Color.WHITE, false, 2.0)


func _draw_texts(s: float, course: Rect2) -> void:
	_text("Putting", Vector2(0, course.position.y - 44.0), 34, Color(0.7, 1.0, 0.75))
	_text("Strokes: %d" % strokes, Vector2(0, course.position.y - 14.0), 24)
	_text("Drag back from the ball and release to putt. Right click to step away", Vector2(0, course.end.y + 66.0), 22)
	var label := "Power"
	draw_string_outline(Ui.font(), Vector2(size.x / 2.0 - 150.0 * s - 80.0, course.end.y + 37.0), label, HORIZONTAL_ALIGNMENT_RIGHT, 70.0, 18, 6, Ui.NAVY)
	draw_string(Ui.font(), Vector2(size.x / 2.0 - 150.0 * s - 80.0, course.end.y + 37.0), label, HORIZONTAL_ALIGNMENT_RIGHT, 70.0, 18)
	if sunk:
		_text("Hole in %d!" % strokes, Vector2(0, course.get_center().y + 20.0), 64, Color(1.0, 0.95, 0.5))
	elif message_time > 0.0:
		_text(message, Vector2(0, course.get_center().y), 30, Color(0.7, 0.9, 1.0))
