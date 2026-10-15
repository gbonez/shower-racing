extends Control

# Bath water with clusters of bubbles; rubber ducks drift south and a little west.

const DRIFT := Vector2(-0.18, 1.0)

var bubble_textures: Array[Texture2D] = []
var duck_texture: Texture2D
var bubbles: Array[Dictionary] = []
var ducks: Array[Dictionary] = []
var time := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	for i in 5:
		bubble_textures.append(load("res://assets/images/bubble%d.png" % (i + 1)) as Texture2D)
	duck_texture = load("res://assets/images/rubberduck.png") as Texture2D


func _populate() -> void:
	var count := 0
	for cluster in 16:
		var center := Vector2(randf() * size.x, randf() * size.y)
		var spread := randf_range(60.0, 170.0)
		for i in randi_range(4, 10):
			bubbles.append({
				"pos": center + Vector2.from_angle(randf() * TAU) * randf() * spread,
				"size": randf_range(24.0, 190.0),
				"tex": count % bubble_textures.size(),
				"phase": randf() * TAU,
				"alpha": randf_range(0.65, 1.0),
				"front": randf() < 0.4,
			})
			count += 1
	for i in 8:
		ducks.append(_spawn_duck(true))


# Ducks enter at a random spot along the top edge and follow the drift line.
func _spawn_duck(scattered: bool) -> Dictionary:
	var duck_size := randf_range(190.0, 320.0)
	var shift := DRIFT.x / DRIFT.y
	var start_x := randf_range(0.0, size.x - shift * size.y)
	var along := randf() * (size.y + duck_size) if scattered else 0.0
	return {
		"pos": Vector2(start_x + shift * along, -duck_size * 0.5 + along),
		"size": duck_size,
		"speed": randf_range(45.0, 85.0),
		"phase": randf() * TAU,
	}


func _process(delta: float) -> void:
	if size.x < 1.0:
		return
	if ducks.is_empty():
		_populate()
	time += delta
	for i in ducks.size():
		var d := ducks[i]
		d["pos"] += DRIFT.normalized() * d["speed"] * delta
		if d["pos"].y > size.y + d["size"] * 0.5 or d["pos"].x < -d["size"]:
			ducks[i] = _spawn_duck(false)
	queue_redraw()


func _draw() -> void:
	var top := Color(0.68, 0.88, 1.0)
	var bottom := Color(0.93, 0.88, 1.0)
	draw_polygon(PackedVector2Array([Vector2.ZERO, Vector2(size.x, 0), size, Vector2(0, size.y)]),
			PackedColorArray([top, top, bottom, bottom]))
	_draw_bubbles(false)
	for d in ducks:
		var bob: float = sin(time * 1.4 + d["phase"])
		var s: float = d["size"]
		draw_set_transform(d["pos"] + Vector2(bob * 6.0, 0.0), bob * 0.08, Vector2.ONE)
		draw_texture_rect(duck_texture, Rect2(Vector2(-s, -s) / 2.0, Vector2(s, s)), false)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	_draw_bubbles(true)


func _draw_bubbles(front: bool) -> void:
	for b in bubbles:
		if b["front"] != front:
			continue
		var s: float = b["size"]
		var p: Vector2 = b["pos"] + Vector2(cos(time * 0.5 + b["phase"]) * 4.0, sin(time * 0.7 + b["phase"]) * 6.0)
		draw_texture_rect(bubble_textures[b["tex"]], Rect2(p - Vector2(s, s) / 2.0, Vector2(s, s)), false,
				Color(1, 1, 1, b["alpha"]))
