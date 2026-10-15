extends Control

# The tomb door's lock: a sliding-tile puzzle (3 x 4 grid with one gap). Solve it to open the door for good.

signal solved
signal closed

const COLS := 3
const ROWS := 4
const TILE := 96.0
const GAP := 6.0

var tiles: Array[int] = []  # the tile in each slot, 0 is the gap
var moves := 0
var hover := -1
var done := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	_shuffle()


# Shuffles by sliding tiles from the solved layout, so every puzzle can be solved.
func _shuffle() -> void:
	tiles.clear()
	for i in COLS * ROWS:
		tiles.append((i + 1) % (COLS * ROWS))
	var blank := COLS * ROWS - 1
	var previous := -1
	for step in 100:
		var options := _neighbors(blank)
		options.erase(previous)
		var pick: int = options.pick_random()
		tiles[blank] = tiles[pick]
		tiles[pick] = 0
		previous = blank
		blank = pick
	if _is_solved():
		_shuffle()


func _neighbors(index: int) -> Array[int]:
	var result: Array[int] = []
	var col := index % COLS
	var row := floori(index / float(COLS))
	if col > 0:
		result.append(index - 1)
	if col < COLS - 1:
		result.append(index + 1)
	if row > 0:
		result.append(index - COLS)
	if row < ROWS - 1:
		result.append(index + COLS)
	return result


func _is_solved() -> bool:
	for i in COLS * ROWS:
		if tiles[i] != (i + 1) % (COLS * ROWS):
			return false
	return true


func _origin() -> Vector2:
	return (size - Vector2(COLS, ROWS) * (TILE + GAP) + Vector2(GAP, GAP)) / 2.0


func _slot_rect(index: int) -> Rect2:
	var col := index % COLS
	var row := floori(index / float(COLS))
	return Rect2(_origin() + Vector2(col, row) * (TILE + GAP), Vector2(TILE, TILE))


func _slot_at(p: Vector2) -> int:
	for i in COLS * ROWS:
		if _slot_rect(i).has_point(p):
			return i
	return -1


func _gui_input(event: InputEvent) -> void:
	if done:
		accept_event()
		return
	if event is InputEventMouseMotion:
		hover = _slot_at(event.position)
		queue_redraw()
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			closed.emit()
		elif event.button_index == MOUSE_BUTTON_LEFT:
			_slide(_slot_at(event.position))
	accept_event()


func _slide(slot: int) -> void:
	if slot < 0 or tiles[slot] == 0:
		return
	for n in _neighbors(slot):
		if tiles[n] == 0:
			tiles[n] = tiles[slot]
			tiles[slot] = 0
			moves += 1
			break
	queue_redraw()
	if _is_solved():
		done = true
		solved.emit()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.82))
	var font := Ui.font()
	var origin := _origin()
	var width := COLS * (TILE + GAP) - GAP
	var height := ROWS * (TILE + GAP) - GAP
	draw_rect(Rect2(origin - Vector2(18, 18), Vector2(width + 36, height + 36)), Color(0.1, 0.12, 0.1))
	draw_rect(Rect2(origin - Vector2(18, 18), Vector2(width + 36, height + 36)), Color(0.35, 1.0, 0.6, 0.8), false, 3.0)
	for i in COLS * ROWS:
		var tile := tiles[i]
		if tile == 0:
			continue
		var rect := _slot_rect(i)
		var home := tile == i + 1
		var fill := Color(0.4, 0.42, 0.4).lerp(Color(0.2, 0.5, 0.3), 0.7 if home else 0.0)
		if i == hover:
			fill = fill.lerp(Ui.HOVER_BLUE, 0.45)
		draw_rect(rect, fill)
		draw_rect(rect, Color(0.08, 0.09, 0.08), false, 3.0)
		var label := str(tile)
		var text_pos := Vector2(rect.position.x, rect.position.y + TILE / 2.0 + 14.0)
		draw_string_outline(font, text_pos, label, HORIZONTAL_ALIGNMENT_CENTER, TILE, 44, 8, Color(0.05, 0.06, 0.05))
		draw_string(font, text_pos, label, HORIZONTAL_ALIGNMENT_CENTER, TILE, 44, Color(0.92, 0.95, 0.9))
	draw_string_outline(font, Vector2(0, origin.y - 48), "Sealed tomb door", HORIZONTAL_ALIGNMENT_CENTER, size.x, 36, 10, Ui.NAVY)
	draw_string(font, Vector2(0, origin.y - 48), "Sealed tomb door", HORIZONTAL_ALIGNMENT_CENTER, size.x, 36, Color(0.5, 1.0, 0.7))
	var info := "Slide the stones into order 1 to 11.   Moves: %d   (right click to step away)" % moves
	draw_string_outline(font, Vector2(0, origin.y + height + 64), info, HORIZONTAL_ALIGNMENT_CENTER, size.x, 22, 8, Ui.NAVY)
	draw_string(font, Vector2(0, origin.y + height + 64), info, HORIZONTAL_ALIGNMENT_CENTER, size.x, 22)
