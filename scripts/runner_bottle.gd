extends CharacterBody3D

# A bottle with arms and legs that runs away from the player. It ignores all collision and follows a
# graph of invisible waypoints (see house.nav_graph), opening doors on the way. After running for a
# while it gets tired and rests; if the player lingers within reach it jumps to a random waypoint.
# Picking it up calls calm(), which removes the limbs and stops it for good.

const SPEED := 4.5  # 50% faster than the player's walking speed (3.0)
const RUN_RADIUS := 12.0  # only runs when the player is this close
const LIFT := 0.23  # body centre height while standing on its legs
const GRAB_RANGE := 3.5  # the player's reach
const GRAB_SECONDS := 5.0
const RUN_SECONDS := 10.0
const TIRED_SECONDS := 5.0
const ARRIVE := 0.2

var threat: Node3D
var house: Node  # opens and closes doors for the bottle
var graph: Dictionary = {}  # {pos: Array[Vector3], links: Array, doors: Array}
var active := true
var limbs: Array[Node3D] = []
var phase := 0.0
var path: Array[int] = []
var path_index := 0
var run_time := 0.0
var tired_time := 0.0
var grab_time := 0.0
var repick_cooldown := 0.0
var door_to_close: Node = null


func setup(color: Color, player: Node3D) -> void:
	collision_layer = 2  # ray clicks still hit it
	collision_mask = 0
	if player != null:
		set_threat(player)
	var cs := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = 0.09
	shape.height = 0.46
	cs.shape = shape
	cs.position = Vector3(0, 0.23, 0)
	add_child(cs)
	_mesh(0.05, 0.22, Vector3(0, LIFT, 0), color)
	_mesh(0.025, 0.05, Vector3(0, LIFT + 0.135, 0), color)
	_mesh(0.03, 0.04, Vector3(0, LIFT + 0.18, 0), Color.WHITE)
	for side in [-1.0, 1.0]:
		limbs.append(_limb(Vector3(side * 0.07, LIFT + 0.05, 0), 0.1, side * 70.0))
		limbs.append(_limb(Vector3(side * 0.03, LIFT - 0.11, 0), 0.12, 0.0))


func set_threat(player: Node3D) -> void:
	threat = player


func _mesh(radius: float, height: float, pos: Vector3, color: Color) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	mi.material_override = m
	mi.position = pos
	add_child(mi)


# A limb hangs from `pos` and swings about the x axis; the pivot keeps the swing at the joint.
func _limb(pos: Vector3, length: float, tilt: float) -> Node3D:
	var pivot := Node3D.new()
	pivot.position = pos
	pivot.rotation_degrees.z = tilt
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.012
	mesh.bottom_radius = 0.012
	mesh.height = length
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.2, 0.2, 0.22)
	mi.material_override = m
	mi.position = Vector3(0, -length / 2.0, 0)
	pivot.add_child(mi)
	add_child(pivot)
	return pivot


func _physics_process(delta: float) -> void:
	if not active or threat == null or graph.is_empty():
		return
	var to_player := threat.global_position - global_position
	var in_reach := to_player.length() < GRAB_RANGE and absf(to_player.y) < 2.5
	grab_time = grab_time + delta if in_reach else 0.0
	if grab_time >= GRAB_SECONDS:
		_teleport_away()
		return
	if tired_time > 0.0:
		tired_time -= delta
		_rest_pose(delta, true)
		_swing(delta, false)
		return
	var chased := to_player.length() < RUN_RADIUS
	if not chased and path.is_empty():
		run_time = maxf(run_time - delta, 0.0)
		_rest_pose(delta, false)
		_swing(delta, false)
		return
	_rest_pose(delta, false)
	repick_cooldown -= delta
	if chased and (path.is_empty() or (repick_cooldown <= 0.0 and _goal_near_player())):
		_pick_path()
	_move(delta)
	_swing(delta, not path.is_empty())
	run_time += delta
	if run_time >= RUN_SECONDS:
		run_time = 0.0
		tired_time = TIRED_SECONDS
		path.clear()


# Slumps forward when tired.
func _rest_pose(delta: float, tired: bool) -> void:
	rotation.x = lerpf(rotation.x, 0.4 if tired else 0.0, delta * 6.0)


func _goal_near_player() -> bool:
	if path.is_empty():
		return true
	var positions: Array = graph["pos"]
	var goal: Vector3 = positions[path[path.size() - 1]]
	return goal.distance_to(threat.global_position) < 5.0 \
			or global_position.distance_to(threat.global_position) < 2.5


func _nearest_node(pos: Vector3) -> int:
	var positions: Array = graph["pos"]
	var best := -1
	var best_cost := INF
	for i in positions.size():
		var p: Vector3 = positions[i]
		var cost := Vector2(p.x - pos.x, p.z - pos.z).length() + absf(p.y - pos.y) * 3.0
		if cost < best_cost:
			best_cost = cost
			best = i
	return best


# Heads for whichever of a few random waypoints is farthest from the player.
func _pick_path() -> void:
	repick_cooldown = 1.0
	var positions: Array = graph["pos"]
	var start := path[path_index] if path_index < path.size() else _nearest_node(global_position)
	if start < 0:
		return
	var best := -1
	var best_score := -INF
	for i in 6:
		var candidate := randi() % positions.size()
		if candidate == start:
			continue
		var p: Vector3 = positions[candidate]
		var score := p.distance_to(threat.global_position)
		if score > best_score:
			best_score = score
			best = candidate
	if best < 0:
		return
	path = _find_path(start, best)
	path_index = 0


func _find_path(from: int, to: int) -> Array[int]:
	var positions: Array = graph["pos"]
	var links: Array = graph["links"]
	var dist := PackedFloat32Array()
	dist.resize(positions.size())
	dist.fill(INF)
	var prev := PackedInt32Array()
	prev.resize(positions.size())
	prev.fill(-1)
	dist[from] = 0.0
	var open: Array[int] = [from]
	var done := {}
	while not open.is_empty():
		var best_k := 0
		for k in open.size():
			if dist[open[k]] < dist[open[best_k]]:
				best_k = k
		var cur: int = open.pop_at(best_k)
		if cur == to:
			break
		if done.has(cur):
			continue
		done[cur] = true
		for n in links[cur]:
			var next: int = n
			var cost := dist[cur] + (positions[cur] as Vector3).distance_to(positions[next])
			if cost < dist[next]:
				dist[next] = cost
				prev[next] = cur
				open.append(next)
	var result: Array[int] = []
	if from != to and prev[to] == -1:
		return result
	var at := to
	while at != -1:
		result.push_front(at)
		at = prev[at]
	return result


func _move(delta: float) -> void:
	if path_index >= path.size():
		path.clear()
		return
	var positions: Array = graph["pos"]
	var index := path[path_index]
	var target: Vector3 = positions[index]
	_open_door_at(index, target)
	var offset := target - global_position
	var step := SPEED * delta
	if offset.length() <= maxf(step, ARRIVE):
		global_position = target
		_arrived(index)
		path_index += 1
		if path_index >= path.size():
			path.clear()
		return
	global_position += offset.normalized() * step
	var flat := Vector2(offset.x, offset.z)
	if flat.length() > 0.05:
		rotation.y = lerp_angle(rotation.y, atan2(offset.x, offset.z), delta * 12.0)


func _teleport_away() -> void:
	grab_time = 0.0
	run_time = 0.0
	tired_time = 0.0
	path.clear()
	door_to_close = null
	rotation.x = 0.0
	var positions: Array = graph["pos"]
	var far: Array[int] = []
	for i in positions.size():
		if (positions[i] as Vector3).distance_to(threat.global_position) > 8.0:
			far.append(i)
	var index: int = far.pick_random() if not far.is_empty() else randi() % positions.size()
	global_position = positions[index]


# A closed door on the way swings open as the bottle gets close (locked and stuck ones are ignored,
# since the bottle passes through everything anyway).
func _open_door_at(index: int, target: Vector3) -> void:
	var doors: Array = graph["doors"]
	var leaf: Node = doors[index]
	if leaf == null or house == null or not is_instance_valid(leaf):
		return
	if leaf.get_meta("open", false) or leaf.get_meta("locked", false) or leaf.get_meta("stuck", false) \
			or leaf.get_meta("bath_door", false):
		return
	var flat := Vector2(target.x - global_position.x, target.z - global_position.z)
	if flat.length() < 2.2:
		house.toggle_door(leaf)
		door_to_close = leaf


# Sometimes shuts the door it just came through.
func _arrived(index: int) -> void:
	var doors: Array = graph["doors"]
	if door_to_close != null and doors[index] == null:
		if is_instance_valid(door_to_close) and door_to_close.get_meta("open", false) and randf() < 0.35:
			house.toggle_door(door_to_close)
		door_to_close = null


func _swing(delta: float, moving: bool) -> void:
	phase += delta * (12.0 if moving else 0.0)
	var swing := sin(phase) * 0.9 if moving else 0.0
	limbs[0].rotation.x = swing
	limbs[1].rotation.x = -swing
	limbs[2].rotation.x = -swing
	limbs[3].rotation.x = swing


# Called when the player grabs it: no more running, and the parts go back to the normal bottle layout.
func calm() -> void:
	active = false
	set_physics_process(false)
	velocity = Vector3.ZERO
	rotation.x = 0.0
	for limb in limbs:
		limb.queue_free()
	limbs.clear()
	for child in get_children():
		if child is Node3D and not child.is_queued_for_deletion():
			child.position.y -= LIFT
	for child in get_children():
		if child is CollisionShape3D:
			var shape := CylinderShape3D.new()
			shape.radius = 0.08
			shape.height = 0.32
			child.shape = shape
			child.position = Vector3(0, 0.045, 0)
