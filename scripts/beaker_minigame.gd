extends Control

# The lab's chemical mixing: pour three reagents up to their markers, then stir the beaker into the finished soap.

signal completed
signal closed

enum Phase { POUR, STIR, READY }

const POUR_RATE := 0.2  # beaker fractions per second while a bottle is held
const READY_TIME := 0.7
const TOLERANCES := [0.05, 0.035, 0.025]
const TURNS := [3, 4, 5]
const REAGENT_COLORS := [Color(0.9, 0.18, 0.2), Color(0.2, 0.42, 0.95), Color(0.98, 0.84, 0.18)]
const REAGENT_NAMES := ["Red", "Blue", "Yellow"]
const RED_TEXT := Color(1.0, 0.6, 0.55)
const GREEN_TEXT := Color(0.6, 1.0, 0.75)

var soap_color := Color.WHITE
var level := 0
var tolerance := 0.05
var turns_needed := 3
var targets: Array[float] = []  # how much of the beaker each layer should fill
var heights: Array[float] = [0.0, 0.0, 0.0]
var current := 0
var pouring := false
var phase := Phase.POUR
var message := ""
var stirring := false
var stir_has_last := false
var stir_last := 0.0
var stir_total := 0.0
var stir_pos := Vector2.ZERO
var ready_time := 0.0
var time := 0.0
var hover := ""
var done := false
var emitted := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP


func setup(product_color: Color, difficulty: int, rng_seed: int) -> void:
	soap_color = product_color
	level = clampi(difficulty, 0, 2)
	tolerance = TOLERANCES[level]
	turns_needed = TURNS[level]
	var rng := RandomNumberGenerator.new()
	rng.seed = rng_seed
	var picked: Array[float] = [0.2, 0.25, 0.3]
	for attempt in 50:
		var candidate: Array[float] = []
		var total := 0.0
		for i in 3:
			var amount := rng.randi_range(15, 35) / 100.0
			candidate.append(amount)
			total += amount
		if total <= 0.9:
			picked = candidate
			break
	targets = picked
	queue_redraw()


func complete_now() -> void:
	if emitted:
		return
	done = true
	emitted = true
	pouring = false
	stirring = false
	phase = Phase.READY
	stir_total = turns_needed * TAU
	completed.emit()


func _process(delta: float) -> void:
	time += delta
	if phase == Phase.POUR and pouring:
		heights[current] += POUR_RATE * delta
		if _is_over(current):
			pouring = false
	elif phase == Phase.READY and not emitted:
		ready_time += delta
		if ready_time >= READY_TIME:
			emitted = true
			completed.emit()
	queue_redraw()


func _is_over(index: int) -> bool:
	return heights[index] > targets[index] + tolerance + 0.00001


func _is_good(index: int) -> bool:
	return absf(heights[index] - targets[index]) <= tolerance + 0.00001


func _progress() -> float:
	return clampf(absf(stir_total) / (turns_needed * TAU), 0.0, 1.0)


func _scale() -> float:
	return clampf(minf(size.x / 1152.0, size.y / 648.0), 0.4, 1.6)


# Positions are laid out on a 1152 x 648 design grid, with x measured from the centre.
func _pt(x: float, y: float) -> Vector2:
	return Vector2(size.x / 2.0 + x * _scale(), size.y / 2.0 + (y - 324.0) * _scale())


func _rc(x: float, y: float, w: float, h: float) -> Rect2:
	return Rect2(_pt(x, y), Vector2(w, h) * _scale())


func _beaker_rect() -> Rect2:
	return _rc(-105, 150, 210, 240)


func _inner_rect() -> Rect2:
	var s := _scale()
	return _beaker_rect().grow_individual(-6.0 * s, 0.0, -6.0 * s, -6.0 * s)


func _beaker_center() -> Vector2:
	return _beaker_rect().get_center()


func _bottle_rect(index: int) -> Rect2:
	return _rc(-198.0 + 160.0 * index, 445, 76, 120)


func _next_rect() -> Rect2:
	return _rc(170, 250, 140, 46)


func _drain_rect() -> Rect2:
	return _rc(170, 310, 140, 46)


func _level_y(fraction: float) -> float:
	var inner := _inner_rect()
	return inner.end.y - fraction * inner.size.y


# Where a layer should end: on top of the layers actually poured below it.
func _marker_level(index: int) -> float:
	var base := 0.0
	for j in index:
		base += heights[j] if j < current else targets[j]
	return base + targets[index]


func _gui_input(event: InputEvent) -> void:
	if done:
		accept_event()
		return
	if event is InputEventMouseMotion:
		_hover_at(event.position)
		if stirring and phase == Phase.STIR:
			_stir_to(event.position)
	elif event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			closed.emit()
		elif event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_press(event.position)
			else:
				pouring = false
				stirring = false
	accept_event()


func _hover_at(p: Vector2) -> void:
	hover = ""
	if _drain_rect().has_point(p):
		hover = "drain"
	elif phase == Phase.POUR:
		if _next_rect().has_point(p):
			hover = "next"
		for i in 3:
			if _bottle_rect(i).has_point(p):
				hover = "bottle%d" % i


func _press(p: Vector2) -> void:
	if _drain_rect().has_point(p):
		_drain()
	elif phase == Phase.POUR:
		if _next_rect().has_point(p):
			_lock_current()
			return
		for i in 3:
			if _bottle_rect(i).has_point(p):
				_start_pour(i)
				return
	elif phase == Phase.STIR:
		stirring = true
		stir_has_last = false
		_stir_to(p)


func _drain() -> void:
	heights = [0.0, 0.0, 0.0]
	current = 0
	pouring = false
	stirring = false
	stir_total = 0.0
	stir_has_last = false
	phase = Phase.POUR
	message = ""


func _start_pour(index: int) -> void:
	message = ""
	if index < current:
		message = "That reagent is already in the beaker"
		return
	if index > current:
		if index == current + 1:
			_lock_current()
		else:
			message = "Pour in order: Red, Blue, Yellow"
		if current != index:
			return
	if _is_over(current):
		return
	pouring = true


# Locks the current layer in place; the last one moves on to stirring.
func _lock_current() -> void:
	pouring = false
	if _is_over(current):
		return
	if not _is_good(current):
		message = "Not enough %s yet. Keep pouring up to the marker" % REAGENT_NAMES[current]
		return
	message = ""
	if current >= 2:
		phase = Phase.STIR
		stirring = false
	else:
		current += 1


func _stir_to(p: Vector2) -> void:
	stir_pos = p
	var offset := p - _beaker_center()
	if offset.length() < 12.0 * _scale():
		stir_has_last = false
		return
	var angle := offset.angle()
	if stir_has_last:
		stir_total += angle_difference(stir_last, angle)
	stir_last = angle
	stir_has_last = true
	if absf(stir_total) >= turns_needed * TAU:
		phase = Phase.READY
		done = true
		stirring = false
		ready_time = 0.0


func _text(text: String, pos: Vector2, width: float, font_size: int, color := Color.WHITE, align := HORIZONTAL_ALIGNMENT_CENTER) -> void:
	var font := Ui.font()
	var fs := maxi(8, roundi(font_size * _scale()))
	draw_string_outline(font, pos, text, align, width, fs, maxi(2, fs / 4), Ui.NAVY)
	draw_string(font, pos, text, align, width, fs, color)


func _path_at(points: PackedVector2Array, t: float) -> Vector2:
	var total := 0.0
	for i in points.size() - 1:
		total += points[i].distance_to(points[i + 1])
	var remaining := t * total
	for i in points.size() - 1:
		var length := points[i].distance_to(points[i + 1])
		if remaining <= length:
			return points[i].lerp(points[i + 1], remaining / maxf(length, 0.001))
		remaining -= length
	return points[points.size() - 1]


func _button(rect: Rect2, label: String, enabled: bool, hovered: bool) -> void:
	var fill := Ui.HOVER_BLUE if hovered and enabled else Ui.SELECT_BLUE
	if not enabled:
		fill = fill.darkened(0.45)
	draw_rect(rect, fill)
	draw_rect(rect, Ui.NAVY if enabled else Color(0.3, 0.35, 0.45), false, 3.0)
	var font := Ui.font()
	var fs := maxi(8, roundi(24 * _scale()))
	draw_string(font, Vector2(rect.position.x, rect.position.y + rect.size.y / 2.0 + fs * 0.35), label,
		HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, fs, Ui.INK if enabled else Color(0.25, 0.3, 0.4))


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.8))
	var s := _scale()
	var progress := _progress()
	_text("Lab: mix the 3-in-1 soap", _pt(-576, 52), 1152.0 * s, 34, Color(0.75, 1.0, 0.9))
	var help := "Hold a bottle to pour, release at the marker, then press Next. Right click to step away"
	if phase != Phase.POUR:
		help = "Hold the left button and drag in circles around the beaker. Right click to step away"
	_text(help, _pt(-576, 90), 1152.0 * s, 22)
	_draw_status(s)
	_draw_tubes(s)
	_draw_beaker(s, progress)
	_draw_markers(s)
	_draw_bottles(s)
	_draw_controls(s, progress)
	if phase == Phase.READY:
		_text("Product ready!", _pt(-576, 280), 1152.0 * s, 56, soap_color.lightened(0.4))


func _draw_status(s: float) -> void:
	var text := ""
	var color := Color.WHITE
	if phase == Phase.READY:
		text = "Product ready!"
		color = GREEN_TEXT
	elif phase == Phase.STIR:
		text = "Stir it!"
		color = GREEN_TEXT
	elif _is_over(current):
		text = "Too much! Press Drain to start over"
		color = RED_TEXT
	elif message != "":
		text = message
		color = RED_TEXT
	elif _is_good(current):
		text = "Just right! Press Next, or pour the next reagent"
		color = GREEN_TEXT
	elif heights[current] <= 0.0:
		text = "Hold the %s bottle to pour" % REAGENT_NAMES[current]
	else:
		text = "Keep pouring %s up to the marker" % REAGENT_NAMES[current]
	_text(text, _pt(-576, 124), 1152.0 * s, 26, color)


func _draw_tubes(s: float) -> void:
	for i in 3:
		var bx := -160.0 + 160.0 * i
		var points := PackedVector2Array([_pt(bx, 445), _pt(bx, 420), _pt(0, 420), _pt(0, 392)])
		var active := pouring and phase == Phase.POUR and current == i
		var col: Color = REAGENT_COLORS[i]
		draw_polyline(points, Color(0.3, 0.35, 0.42), 9.0 * s)
		draw_polyline(points, col if active else Color(0.12, 0.15, 0.2), 5.0 * s)
		if active:
			for k in 6:
				draw_circle(_path_at(points, fposmod(time * 1.6 + k / 6.0, 1.0)), 3.5 * s, col.lightened(0.5))


func _draw_beaker(s: float, progress: float) -> void:
	var body := _beaker_rect()
	var inner := _inner_rect()
	draw_rect(inner, Color(0.8, 0.92, 1.0, 0.1))
	var base := 0.0
	var top_level := 0.0
	for i in 3:
		var h := minf(heights[i], 1.0 - base)
		if h <= 0.0:
			continue
		var col: Color = REAGENT_COLORS[i]
		col = col.lerp(soap_color, progress)
		var top_y := _level_y(base + h)
		var bottom_y := _level_y(base)
		draw_rect(Rect2(inner.position.x, top_y, inner.size.x, bottom_y - top_y), col)
		draw_line(Vector2(inner.position.x, top_y), Vector2(inner.end.x, top_y), col.lightened(0.45), 2.0)
		base += h
		top_level = base
	if top_level > 0.0:
		_draw_liquid_effects(inner, top_level, progress, s)
	# glass walls, rim and graduation marks
	var glass := Color(0.85, 0.95, 1.0, 0.9)
	draw_polyline(PackedVector2Array([body.position + Vector2(0, -8.0 * s), body.position, body.position + Vector2(0, body.size.y),
		body.end, body.position + Vector2(body.size.x, 0), body.position + Vector2(body.size.x, -8.0 * s)]), glass, 4.0 * s)
	draw_line(body.position + Vector2(-10.0 * s, -8.0 * s), body.position + Vector2(body.size.x + 10.0 * s, -8.0 * s), glass, 5.0 * s)
	draw_line(body.position + Vector2(10.0 * s, 20.0 * s), body.position + Vector2(10.0 * s, body.size.y - 30.0 * s), Color(1, 1, 1, 0.25), 5.0 * s)
	for tick in range(1, 21):
		var f := tick * 0.05
		var y := _level_y(f)
		var long := tick % 2 == 0
		var from_x := body.end.x - (22.0 if long else 12.0) * s
		draw_line(Vector2(from_x, y), Vector2(body.end.x - 3.0 * s, y), glass, 2.0 if long else 1.0)
		if tick % 4 == 0 and tick < 20:
			_text("%d" % roundi(f * 100.0), Vector2(body.end.x + 10.0 * s, y + 5.0 * s), 40.0 * s, 14, glass, HORIZONTAL_ALIGNMENT_LEFT)


func _draw_liquid_effects(inner: Rect2, top_level: float, progress: float, s: float) -> void:
	for k in 4:
		var phase_offset := k * 1.7
		var bx := inner.position.x + inner.size.x * (0.2 + 0.2 * k + 0.05 * sin(time * 2.0 + phase_offset))
		var by := _level_y(top_level * fposmod(time * 0.35 + k * 0.27, 1.0))
		draw_circle(Vector2(bx, by), (2.0 + k % 2) * s, Color(1, 1, 1, 0.3))
	if progress <= 0.0:
		return
	var mid_y := _level_y(top_level / 2.0)
	var half_h := top_level * inner.size.y / 2.0
	var alpha := minf(progress * 3.0, 1.0) * 0.5
	for arm in 3:
		var points := PackedVector2Array()
		for i in 21:
			var t := i / 20.0
			var a := stir_total * 1.5 + arm * TAU / 3.0 + t * TAU * 1.2
			points.append(Vector2(inner.get_center().x + cos(a) * t * inner.size.x * 0.45, mid_y + sin(a) * t * half_h * 0.7))
		draw_polyline(points, Color(1, 1, 1, alpha), 3.0 * s)
	if phase == Phase.STIR:
		var tip := Vector2(clampf(stir_pos.x, inner.position.x + 8.0 * s, inner.end.x - 8.0 * s), clampf(stir_pos.y, mid_y - half_h, mid_y + half_h))
		draw_line(tip, tip + Vector2(18.0, -100.0) * s, Color(0.85, 0.85, 0.9), 6.0 * s)
		draw_circle(tip, 5.0 * s, Color(0.85, 0.85, 0.9))


func _draw_markers(s: float) -> void:
	var body := _beaker_rect()
	for i in 3:
		var col: Color = REAGENT_COLORS[i]
		col = col.lightened(0.15)
		if phase != Phase.POUR or i < current:
			col.a = 0.35
		elif i > current:
			col.a = 0.7
		var lv := _marker_level(i)
		var y := _level_y(lv)
		var band_top := _level_y(lv + tolerance)
		var band_bottom := _level_y(lv - tolerance)
		draw_rect(Rect2(body.position.x - 24.0 * s, band_top, 18.0 * s, band_bottom - band_top), Color(col.r, col.g, col.b, col.a * 0.45))
		draw_line(Vector2(body.position.x - 34.0 * s, y), Vector2(body.position.x + 12.0 * s, y), col, 3.0 * s)
		draw_colored_polygon(PackedVector2Array([Vector2(body.position.x + 12.0 * s, y), Vector2(body.position.x + 2.0 * s, y - 6.0 * s),
			Vector2(body.position.x + 2.0 * s, y + 6.0 * s)]), col)
		_text("%s +%d%%" % [REAGENT_NAMES[i], roundi(targets[i] * 100.0)], Vector2(body.position.x - 218.0 * s, y + 6.0 * s), 180.0 * s, 18, col, HORIZONTAL_ALIGNMENT_RIGHT)


func _draw_bottles(s: float) -> void:
	for i in 3:
		var r := _bottle_rect(i)
		var col: Color = REAGENT_COLORS[i]
		var active := phase == Phase.POUR and i == current
		if not active:
			col = col.darkened(0.45)
		var body := Rect2(r.position + Vector2(0, 40.0 * s), Vector2(r.size.x, r.size.y - 40.0 * s))
		draw_rect(Rect2(r.position + Vector2(20.0 * s, 10.0 * s), Vector2(36.0 * s, 32.0 * s)), Color(0.8, 0.9, 1.0, 0.7))
		draw_rect(Rect2(r.position + Vector2(18.0 * s, 0), Vector2(40.0 * s, 12.0 * s)), Color(0.55, 0.38, 0.22))
		draw_rect(body, Color(0.8, 0.9, 1.0, 0.35))
		draw_rect(body.grow(-4.0 * s), col)
		var outline := Ui.HOVER_BLUE if hover == "bottle%d" % i else Color(0.85, 0.95, 1.0, 0.9)
		if active:
			outline = Color(1, 1, 1, 0.65 + 0.35 * sin(time * 5.0))
		draw_rect(body, outline, false, 3.0)
		draw_circle(body.get_center(), 15.0 * s, Color(0.05, 0.1, 0.25, 0.6))
		_text(str(i + 1), body.get_center() + Vector2(-20.0 * s, 8.0 * s), 40.0 * s, 22)
		_text(REAGENT_NAMES[i], _pt(-160.0 + 160.0 * i - 60.0, 588), 120.0 * s, 18, Color.WHITE if active else Color(0.7, 0.75, 0.8))


func _draw_controls(s: float, progress: float) -> void:
	var next_enabled := phase == Phase.POUR and heights[current] > 0.0 and not _is_over(current)
	if phase == Phase.POUR:
		_button(_next_rect(), "Next" if current < 2 else "Done", next_enabled, hover == "next")
	_button(_drain_rect(), "Drain", phase != Phase.READY, hover == "drain")
	var readout := ""
	if phase == Phase.POUR:
		readout = "Step 1/2: Pour    Layer %d/3 (%s): %d%% of %d%%" % [current + 1, REAGENT_NAMES[current],
			roundi(heights[current] * 100.0), roundi(targets[current] * 100.0)]
	else:
		readout = "Step 2/2: Stir    Turns %.1f / %d" % [absf(stir_total) / TAU, turns_needed]
		var bar := _rc(170, 380, 140, 14)
		draw_rect(bar, Color(0.1, 0.12, 0.18))
		draw_rect(Rect2(bar.position, Vector2(bar.size.x * progress, bar.size.y)), GREEN_TEXT)
		draw_rect(bar, Color.WHITE, false, 2.0)
	_text(readout, _pt(-576, 628), 1152.0 * s, 24)
