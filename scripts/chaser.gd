extends Node3D

# Evil Forrest: a figure that hunts the player through the level at half their walking speed, screaming.
# He follows the level's waypoint graph, opens doors on the way, and ignores walls like the run-away
# bottles. When he reaches the player, `caught` is emitted and the main script sends them back to the
# bathroom. His picture is the first file in assets/images whose name has "forrest", "forest" or "evil".

signal caught

const SPEED := 1.5  # half the player's walking speed (3.0)
const CATCH_RANGE := 1.0
const SIGHT_RANGE := 16.0
const GRACE_SECONDS := 6.0  # after spawning or catching someone he lets them go for a while
const HEIGHT := 2.3

static var _scream: AudioStreamWAV

var active := false
var player: Node3D
var house: Node
var graph: Dictionary = {}
var path: Array[int] = []
var path_index := 0
var repath := 0.0
var grace := GRACE_SECONDS
var scream_cooldown := 0.0
var clock := 0.0
var sprite: Sprite3D
var voice: AudioStreamPlayer3D
var door_to_close: Node = null


func setup(target: Node3D, home: Node, nav: Dictionary) -> void:
	player = target
	house = home
	graph = nav
	var tex := AssetImages.find(["forrest", "forest", "evil"])
	if tex == null:
		tex = AssetImages.figure(Color(0.03, 0.09, 0.04), Color(1.0, 0.12, 0.05))
	sprite = Sprite3D.new()
	sprite.texture = tex
	sprite.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	sprite.pixel_size = HEIGHT / float(tex.get_height())
	sprite.position.y = HEIGHT / 2.0
	sprite.shaded = false
	sprite.double_sided = true
	add_child(sprite)
	voice = AudioStreamPlayer3D.new()
	voice.stream = _scream_stream()
	voice.unit_size = 14.0
	voice.max_distance = 80.0
	add_child(voice)
	send_away()


# Moves him to the waypoint farthest from the player and gives them a head start.
func send_away() -> void:
	path.clear()
	grace = GRACE_SECONDS
	door_to_close = null
	var positions: Array = graph["pos"]
	var feet: Vector3 = player.global_position - Vector3(0, 0.9, 0)
	var best := 0
	var best_distance := -1.0
	for i in positions.size():
		var d := (positions[i] as Vector3).distance_to(feet)
		if d > best_distance:
			best_distance = d
			best = i
	global_position = positions[best]


func _physics_process(delta: float) -> void:
	clock += delta
	sprite.position.y = HEIGHT / 2.0 + sin(clock * 3.0) * 0.04
	if not active or graph.is_empty():
		return
	grace = maxf(0.0, grace - delta)
	scream_cooldown -= delta
	var feet: Vector3 = player.global_position - Vector3(0, 0.9, 0)
	var offset := feet - global_position
	var flat := Vector2(offset.x, offset.z).length()
	var same_level := absf(offset.y) < 2.0
	if flat < SIGHT_RANGE and same_level and scream_cooldown <= 0.0:
		scream_cooldown = 12.0
		voice.play()
	if grace <= 0.0 and flat < CATCH_RANGE and same_level:
		voice.play()
		caught.emit()
		return
	repath -= delta
	if repath <= 0.0 or path.is_empty():
		repath = 0.7
		path = NavPath.find_path(graph, NavPath.nearest_node(graph, global_position), NavPath.nearest_node(graph, feet))
		path_index = 0
	_walk(delta, feet)


# Along the waypoints, then straight at the player once the route runs out or they are close by.
func _walk(delta: float, feet: Vector3) -> void:
	var positions: Array = graph["pos"]
	var target := feet
	var flat := Vector2(feet.x - global_position.x, feet.z - global_position.z).length()
	if path_index < path.size() and not (flat < 3.0 and absf(feet.y - global_position.y) < 2.0):
		var index := path[path_index]
		target = positions[index]
		_open_door_at(index, target)
		if global_position.distance_to(target) <= maxf(SPEED * delta, 0.2):
			global_position = target
			_arrived(index)
			path_index += 1
			return
	global_position += (target - global_position).normalized() * SPEED * delta


func _open_door_at(index: int, target: Vector3) -> void:
	var leaf: Node = (graph["doors"] as Array)[index]
	if leaf == null or house == null or not is_instance_valid(leaf) or not house.has_method("toggle_door"):
		return
	if leaf.get_meta("open", false) or leaf.get_meta("locked", false) or leaf.get_meta("stuck", false) \
			or leaf.get_meta("bath_door", false):
		return
	if Vector2(target.x - global_position.x, target.z - global_position.z).length() < 2.2:
		house.toggle_door(leaf)
		door_to_close = leaf


func _arrived(index: int) -> void:
	if door_to_close != null and (graph["doors"] as Array)[index] == null:
		if is_instance_valid(door_to_close) and door_to_close.get_meta("open", false) and randf() < 0.5:
			house.toggle_door(door_to_close)
		door_to_close = null


# A rising, wavering shriek with some rasp, generated once.
static func _scream_stream() -> AudioStreamWAV:
	if _scream != null:
		return _scream
	var rate := 22050
	var length := 1.1
	var count := int(rate * length)
	var data := PackedByteArray()
	data.resize(count * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var phase := 0.0
	for i in count:
		var t := float(i) / rate
		var freq := 700.0 + 900.0 * sin(PI * t / length) + 60.0 * sin(t * 38.0)
		phase += TAU * freq / rate
		var envelope := minf(t * 20.0, 1.0) * clampf((length - t) * 3.0, 0.0, 1.0)
		var s := (sin(phase) * 0.5 + sin(phase * 2.01) * 0.25 + rng.randf_range(-1.0, 1.0) * 0.25) * envelope
		data.encode_s16(i * 2, int(clampf(s, -1.0, 1.0) * 28000.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = rate
	wav.stereo = false
	wav.data = data
	_scream = wav
	return wav
