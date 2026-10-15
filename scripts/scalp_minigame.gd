extends Control

signal completed

const CELL := 10
var brush_radius := 22.0
var skin_color := Color(0.93, 0.8, 0.7)

var product_color := Color.WHITE
var title := ""
var stages: Array = []  # each: {"name": String, "size": Vector2}
var stage := 0
var cell_cols := 0
var cell_rows := 0
var painted := PackedByteArray()
var covered := 0
var total_cells := 0
var painting := false
var done := false
var last_pos := Vector2.ZERO
var mouse_pos := Vector2(-1000, -1000)


func setup(color: Color, text: String, parts: Array) -> void:
	product_color = color
	title = text
	stages = parts
	_start_stage(0)


func _start_stage(index: int) -> void:
	stage = index
	var stage_size: Vector2 = stages[index]["size"]
	cell_cols = int(stage_size.x / CELL)
	cell_rows = int(stage_size.y / CELL)
	total_cells = cell_cols * cell_rows
	painted = PackedByteArray()
	painted.resize(total_cells)
	covered = 0
	painting = false
	queue_redraw()


func complete_now() -> void:
	if done:
		return
	done = true
	painting = false
	completed.emit()


func _current_rect() -> Rect2:
	var stage_size: Vector2 = stages[stage]["size"]
	return Rect2(size / 2.0 - stage_size / 2.0, stage_size)


func _gui_input(event: InputEvent) -> void:
	if done:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		painting = event.pressed
		if painting:
			last_pos = event.position
			_paint_at(event.position)
	elif event is InputEventMouseMotion:
		mouse_pos = event.position
		if painting:
			var distance := last_pos.distance_to(event.position)
			var steps := maxi(1, ceili(distance / (brush_radius * 0.5)))
			for s in range(1, steps + 1):
				_paint_at(last_pos.lerp(event.position, float(s) / steps))
				if not painting:
					break
			last_pos = event.position
		queue_redraw()
	accept_event()


func _paint_at(p: Vector2) -> void:
	var r := _current_rect()
	if not r.grow(brush_radius).has_point(p):
		return
	var local := p - r.position
	var c0 := maxi(0, floori((local.x - brush_radius) / CELL))
	var c1 := mini(cell_cols - 1, floori((local.x + brush_radius) / CELL))
	var r0 := maxi(0, floori((local.y - brush_radius) / CELL))
	var r1 := mini(cell_rows - 1, floori((local.y + brush_radius) / CELL))
	for cy in range(r0, r1 + 1):
		for cx in range(c0, c1 + 1):
			var center := Vector2((cx + 0.5) * CELL, (cy + 0.5) * CELL)
			if center.distance_squared_to(local) > brush_radius * brush_radius:
				continue
			var idx := cy * cell_cols + cx
			if painted[idx] == 0:
				painted[idx] = 1
				covered += 1
	queue_redraw()
	if covered >= total_cells:
		_finish_stage()


func _finish_stage() -> void:
	if stage + 1 >= stages.size():
		done = true
		painting = false
		completed.emit()
	else:
		_start_stage(stage + 1)


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.8))
	var r := _current_rect()
	draw_rect(r, skin_color)
	for cy in cell_rows:
		for cx in cell_cols:
			if painted[cy * cell_cols + cx] == 1:
				draw_rect(Rect2(r.position + Vector2(cx, cy) * CELL, Vector2(CELL, CELL)), product_color)
	draw_rect(r, Color.WHITE, false, 3.0)

	var font := Ui.font()
	draw_string_outline(font, Vector2(0, r.position.y - 64), title, HORIZONTAL_ALIGNMENT_CENTER, size.x, 30, 8, Ui.NAVY)
	draw_string(font, Vector2(0, r.position.y - 64), title,
		HORIZONTAL_ALIGNMENT_CENTER, size.x, 30)
	var part_name: String = stages[stage]["name"]
	if stages.size() > 1:
		part_name = "%s (%d/%d)" % [part_name, stage + 1, stages.size()]
	draw_string_outline(font, Vector2(0, r.position.y - 20), part_name, HORIZONTAL_ALIGNMENT_CENTER, size.x, 36, 10, Ui.NAVY)
	draw_string(font, Vector2(0, r.position.y - 20), part_name,
		HORIZONTAL_ALIGNMENT_CENTER, size.x, 36, product_color.lightened(0.3))
	var percent := floori(100.0 * covered / total_cells)
	draw_string_outline(font, Vector2(0, r.end.y + 50), "Covered: %d%%" % percent, HORIZONTAL_ALIGNMENT_CENTER, size.x, 28, 8, Ui.NAVY)
	draw_string(font, Vector2(0, r.end.y + 50), "Covered: %d%%" % percent,
		HORIZONTAL_ALIGNMENT_CENTER, size.x, 28)
	draw_arc(mouse_pos, brush_radius, 0.0, TAU, 32, Color.WHITE, 2.0)
