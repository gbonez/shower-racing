extends Node3D

# Open levels with no house around the shower: the cloud parkour course, the beach and the special
# maps (warehouse, lab, monster movie, golf course, lake), which extend this script. The main script
# owns the game rules and reads these members:
#   spawn, bottle_spots (3 bottle positions, 0.11 above the surface), item_spots["boiler"], bucket_pos,
#   respawn_height, decoy_spot(), extra_spot() (any reachable spot for loose pickups, same convention),
#   nav_graph() ({pos, links, doors} for run-away bottles and the chaser), player_jump / player_speed
#   (0 jump = none), indoor, customize_env(env, sun).
# Special maps may keep bottles hidden until the player earns them: bind_bottle() is called for each of
# the first three bottles, and unlock_bottle() reveals one. Bodies with the meta kind = "map_action"
# (plus "label" and a Callable "action") are clickable by the player and call the action.

var main  # untyped: calls the main script's build helpers
var spawn := Vector3(0, 1.0, 0)
var bottle_spots: Array[Vector3] = []
var bucket_pos := Vector3.ZERO
var respawn_height := -25.0
var tank_fill: MeshInstance3D
var tank_body: StaticBody3D
var tank_base_y := 1.3
var tank_height := 1.0
var clouds: Array[Dictionary] = []  # {pos, r}
var item_spots: Dictionary = {}  # cloud walk: "spring" and "brush" -> surface position
var indoor := false  # special maps built inside a hall: no sky, no sun
var player_jump := 0.0  # jump height multiplier; 0 means the player can't jump
var player_speed := 1.0
var swim_level := NAN  # water surface height; the player swims where the ground is deeper than this
var hidden_bottles: Dictionary = {}  # index -> bottle body, for maps that hold bottles back


func build(kind: String) -> void:
	if kind == "cloud_walk":
		_build_clouds()
	else:
		_build_beach()


# Treasure hunt: opens a carried chest if the player is on the shore. Returns the message, or "" if not.
func open_chest(_chest: Node, _player: Node3D) -> String:
	return ""


# Called after build() so a map can change the sky, fog and sun the main script created.
func customize_env(_env: Environment, _sun: DirectionalLight3D) -> void:
	pass


# Called by the main script for each of the first three bottles. A map that holds bottles back hides the
# body here and shows it later through unlock_bottle().
func bind_bottle(_index: int, _body: PhysicsBody3D, _id: String) -> void:
	pass


# Makes a held-back bottle visible and clickable, optionally moving it to `at` first.
func unlock_bottle(index: int, at := Vector3.INF) -> void:
	if not hidden_bottles.has(index):
		return
	var body: PhysicsBody3D = hidden_bottles[index]
	hidden_bottles.erase(index)
	if at != Vector3.INF:
		body.position = at
	body.visible = true
	body.collision_layer = 2


func _sphere(radius: float) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = radius
	s.height = radius * 2.0
	return s


func _mount_at(pos: Vector3, n: Vector3) -> Node3D:
	var m := Node3D.new()
	m.position = pos + n * 0.06
	m.rotation.y = atan2(n.x, n.z)
	add_child(m)
	return m


# Both levels use the same pole-mounted shower: a handle and a head on a post beside a wooden deck.
func _build_shower_rig(center: Vector3, y: float) -> void:
	var wood: Material = main._mat(Color(0.6, 0.42, 0.25))
	var metal: Material = main._mat(Color(0.7, 0.72, 0.75))
	main._prop(main._box(Vector3(2.4, 0.06, 2.4)), Vector3(center.x, y + 0.03, center.z), wood, false, Vector3.ZERO, self)
	var pole := Vector3(center.x - 1.0, y, center.z)
	main._prop(main._cyl(0.06, 2.5), pole + Vector3(0, 1.25, 0), metal, true, Vector3.ZERO, self)
	var handle_mount := _mount_at(pole + Vector3(0, 1.15, 0), Vector3(1, 0, 0))
	var nozzle_mount := _mount_at(pole + Vector3(0, 2.25, 0), Vector3(1, 0, 0))
	var pivot: Node3D = main.make_handle(handle_mount)
	var spray: CPUParticles3D = main.make_nozzle(nozzle_mount, Vector3(1, 0, 0))
	main.register_shower(Rect2(center.x - 1.2, center.z - 1.2, 2.4, 2.4), y, pivot, spray)


# --- Clouds ---

func _cloud_free(p: Vector3, r: float) -> bool:
	for c in clouds:
		var cp: Vector3 = c["pos"]
		if Vector2(p.x - cp.x, p.z - cp.z).length() < r + float(c["r"]) + 0.6 and absf(p.y - cp.y) < 3.0:
			return false
	return true


func _add_cloud(p: Vector3, r: float) -> int:
	clouds.append({"pos": p, "r": r})
	_build_cloud(p, r)
	return clouds.size() - 1


# Adds a cloud a jumpable distance from `from`; returns its index or -1 if nothing fit.
func _next_cloud(from: int, heading: float, r: float, rise := Vector2(-1.2, 0.9), spread := 0.9,
		gap := Vector2(0.9, 1.9)) -> int:
	var f := clouds[from]
	var fp: Vector3 = f["pos"]
	for attempt in 12:
		var h := heading + randf_range(-spread, spread)
		var dist := float(f["r"]) + r + randf_range(gap.x, gap.y)
		var p := fp + Vector3(cos(h) * dist, randf_range(rise.x, rise.y), sin(h) * dist)
		if _cloud_free(p, r):
			return _add_cloud(p, r)
	return -1


# Lays clouds from `from` towards cloud `to`, bending sideways first, until the last one is a jump away
# from it. Gives the course a second way round.
func _build_branch(from: int, to: int, side: float) -> bool:
	var goal: Vector3 = clouds[to]["pos"]
	var goal_r: float = clouds[to]["r"]
	var cur := from
	for step in 7:
		var cp: Vector3 = clouds[cur]["pos"]
		var flat := Vector2(goal.x - cp.x, goal.z - cp.z)
		if step > 0 and flat.length() - float(clouds[cur]["r"]) - goal_r < 2.3 and absf(goal.y - cp.y) < 2.5:
			return true
		var heading := atan2(flat.y, flat.x) + side * (1.0 if step < 2 else 0.25)
		var nxt := _next_cloud(cur, heading, randf_range(1.3, 2.4), Vector2(-0.8, 0.8), 0.35, Vector2(1.0, 2.2))
		if nxt == -1:
			return false
		cur = nxt
	return false


func _heading(from: int, to: int) -> float:
	var a: Vector3 = clouds[from]["pos"]
	var b: Vector3 = clouds[to]["pos"]
	return atan2(b.z - a.z, b.x - a.x)


# The main route changes character every few clouds: plain hops, staircases up and down, zigzags and
# tiny stepping stones.
func _build_clouds() -> void:
	_add_cloud(Vector3.ZERO, 4.0)
	var path: Array[int] = [0]
	var heading := randf() * TAU
	var cur := 0
	var style := 0
	var style_left := 0
	for i in randi_range(14, 20):
		if style_left <= 0:
			style = randi() % 5
			style_left = randi_range(2, 4)
		style_left -= 1
		var r := randf_range(1.5, 2.8)
		var rise := Vector2(-1.2, 0.9)
		var spread := 0.9
		var gap := Vector2(0.9, 1.9)
		var aim := heading
		match style:
			1:
				rise = Vector2(0.8, 1.6)
				r = randf_range(1.4, 2.0)
				spread = 0.4
			2:
				rise = Vector2(-1.6, -0.8)
				r = randf_range(1.4, 2.0)
				spread = 0.4
			3:
				aim += 1.1 if i % 2 == 0 else -1.1
				r = randf_range(1.3, 1.9)
				spread = 0.3
			4:
				r = randf_range(1.2, 1.5)
				gap = Vector2(1.5, 2.3)
				spread = 0.5
		var nxt := _next_cloud(cur, aim, r, rise, spread, gap)
		if nxt == -1:
			break
		heading = _heading(cur, nxt)
		cur = nxt
		path.append(cur)

	var shower := _next_cloud(cur, heading, 3.6)
	if shower == -1:
		shower = cur
	var sp: Vector3 = clouds[shower]["pos"]
	_build_shower_rig(sp, sp.y)

	# Detours that rejoin the route a few clouds on, and loose clouds to hop between.
	if path.size() >= 7:
		for k in randi_range(3, 5):
			var i := randi_range(1, path.size() - 5)
			_build_branch(path[i], path[mini(i + randi_range(2, 4), path.size() - 1)], 1.0 if randf() < 0.5 else -1.0)
	for k in randi_range(10, 16):
		var base_pos: Vector3 = clouds[path[randi_range(0, path.size() - 1)]]["pos"]
		var angle := randf() * TAU
		var r := randf_range(1.2, 3.0)
		var p := base_pos + Vector3(cos(angle), 0.0, sin(angle)) * randf_range(5.0, 10.0) + Vector3(0, randf_range(-2.0, 2.0), 0)
		if _cloud_free(p, r):
			_add_cloud(p, r)

	var bottle_clouds: Array[int] = []
	for b in randi_range(1, 3):
		var start: int = path[randi_range(0, path.size() - 1)]
		var h := randf() * TAU
		var c := start
		for i in randi_range(2, 4):
			var n := _next_cloud(c, h, randf_range(1.5, 2.2))
			if n == -1:
				break
			h = _heading(c, n)
			c = n
		if c != start:
			bottle_clouds.append(c)
	if bottle_clouds.is_empty():
		bottle_clouds.append(path[path.size() - 1])

	for i in 3:
		var index := bottle_clouds[i % bottle_clouds.size()]
		var cp: Vector3 = clouds[index]["pos"]
		var radius: float = clouds[index]["r"]
		var spot := cp + Vector3(0, 0.11, 0)
		for attempt in 10:
			var a := randf() * TAU
			var candidate := cp + Vector3(cos(a), 0.0, sin(a)) * randf_range(0.0, radius * 0.55) + Vector3(0, 0.11, 0)
			var clear := true
			for other in bottle_spots:
				if other.distance_to(candidate) < 0.45:
					clear = false
			if clear:
				spot = candidate
				break
		bottle_spots.append(spot)

	var lowest := 0.0
	for c in clouds:
		lowest = minf(lowest, (c["pos"] as Vector3).y)
	respawn_height = lowest - 25.0

	# Spring shoes sit on an early cloud, the scrub brush on another one along the route.
	var early := path.slice(1, mini(path.size(), 4))
	if early.is_empty():
		early = [path[0]]
	item_spots["spring"] = _spot_on(early.pick_random(), 0.45)
	item_spots["brush"] = _spot_on(path[randi_range(0, path.size() - 1)], 0.35)
	item_spots["boiler"] = _spot_on(path[randi_range(mini(1, path.size() - 1), path.size() - 1)], 0.3)

	spawn = Vector3(0, 1.0, 0)
	_build_far_clouds()


# A bottle position for the decoy: on a random cloud, or somewhere on the beach.
func decoy_spot() -> Vector3:
	if not clouds.is_empty():
		return _spot_on(randi() % clouds.size(), 0.5) + Vector3(0, 0.11, 0)
	return _land_point(0.7) + Vector3(0, 0.11, 0)


# Any reachable surface spot, for loose pickups. Same height convention as the bottle spots.
func extra_spot() -> Vector3:
	return decoy_spot()


func _spot_on(index: int, spread: float) -> Vector3:
	var cp: Vector3 = clouds[index]["pos"]
	var radius: float = clouds[index]["r"]
	var a := randf() * TAU
	return cp + Vector3(cos(a), 0.0, sin(a)) * randf_range(0.0, radius * spread)


# A cloud is a cluster of flattened puffs. Their tops stay at or below the cloud's surface height so
# nothing pokes up through the shower deck or the player's feet.
func _build_cloud(p: Vector3, r: float) -> void:
	var body := StaticBody3D.new()
	body.position = p
	add_child(body)
	var white: Material = main._mat(Color(0.98, 0.98, 1.0))
	var lumps: Array[Vector3] = [Vector3(0.0, 0.0, r * 0.5)]  # x offset, z offset, radius
	var count := maxi(4, int(r * 2.5))
	var start := randf() * TAU
	for i in count:
		var a := start + i * TAU / count + randf_range(-0.3, 0.3)
		var d := r * randf_range(0.35, 0.58)
		lumps.append(Vector3(cos(a) * d, sin(a) * d, r * randf_range(0.34, 0.5)))
	for lump in lumps:
		var vy := randf_range(0.45, 0.75)
		var mi := MeshInstance3D.new()
		mi.mesh = _sphere(1.0)
		mi.material_override = white
		mi.scale = Vector3(lump.z, vy, lump.z)
		mi.position = Vector3(lump.x, -vy - 0.03, lump.y)
		body.add_child(mi)
		var cs := CollisionShape3D.new()
		var shape := CylinderShape3D.new()
		shape.radius = lump.z * 0.85
		shape.height = 0.8
		cs.shape = shape
		cs.position = Vector3(lump.x, -0.4, lump.y)
		body.add_child(cs)
	for i in 3:
		var under := MeshInstance3D.new()
		under.mesh = _sphere(1.0)
		under.material_override = white
		var ur := r * randf_range(0.3, 0.5)
		under.scale = Vector3(ur, randf_range(0.4, 0.7), ur)
		under.position = Vector3(randf_range(-0.4, 0.4) * r, -1.0, randf_range(-0.4, 0.4) * r)
		body.add_child(under)


func _build_far_clouds() -> void:
	var white: Material = main._mat(Color(1, 1, 1, 0.9))
	for i in 60:
		var a := randf() * TAU
		var dist := randf_range(70.0, 190.0)
		var base := Vector3(cos(a) * dist, randf_range(-30.0, 40.0), sin(a) * dist)
		for j in randi_range(3, 6):
			main._prop(_sphere(randf_range(6.0, 16.0)), base + Vector3(randf_range(-14, 14), randf_range(-3, 3), randf_range(-14, 14)),
					white, false, Vector3.ZERO, self)


# --- Beach ---

# The beach is a small island ringed by sea: sand with gentle hills, a shallow slope into the water on
# every side, and a ring of invisible walls so nobody wades out of their depth. Terrain height comes
# from height_at() so props sit on it.
const TW := 61  # height map samples along x, one per metre
const TD := 61
const TZ := 7.0  # world z of the middle of the height map
const SEA_LEVEL := -0.15
const SEABED := -3.0
const ISLAND_CENTER := Vector2(0.0, 7.0)
const ISLAND_RADII := Vector2(15.0, 12.0)  # the old island was about twice this size
const WALL_RING := 1.25  # distance of the wading limit, in island radii

var noise := FastNoiseLite.new()
var flat_center := Vector2.ZERO


# 0 in the middle of the island, 1 at its nominal edge.
func island_distance(x: float, z: float) -> float:
	return Vector2((x - ISLAND_CENTER.x) / ISLAND_RADII.x, (z - ISLAND_CENTER.y) / ISLAND_RADII.y).length()


func height_at(x: float, z: float) -> float:
	var d := island_distance(x, z)
	var h := -maxf(d - 0.72, 0.0) * 2.2  # slopes down into the sea all the way round
	var land := clampf((0.8 - d) / 0.25, 0.0, 1.0)
	var clear := clampf((Vector2(x - flat_center.x, z - flat_center.y).length() - 4.0) / 3.0, 0.0, 1.0)
	h += maxf(noise.get_noise_2d(x, z), 0.0) * 1.2 * land * clear
	return maxf(h, SEABED)


# A random point on the dry sand, no further out than `max_d` island radii.
func _land_point(max_d := 0.75) -> Vector3:
	var a := randf() * TAU
	var r := sqrt(randf()) * max_d
	return _surface(ISLAND_CENTER.x + cos(a) * r * ISLAND_RADII.x, ISLAND_CENTER.y + sin(a) * r * ISLAND_RADII.y)


func _invisible_wall(pos: Vector3, size: Vector3, yaw := 0.0) -> void:
	var body := StaticBody3D.new()
	body.position = pos
	body.rotation.y = yaw
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	body.add_child(cs)
	add_child(body)


# An elliptical ring of walls around the island, in the water.
func _build_wall_ring() -> void:
	var count := 48
	for i in count:
		var a := TAU * i / count
		var p := Vector2(cos(a) * ISLAND_RADII.x, sin(a) * ISLAND_RADII.y) * WALL_RING
		var tangent := Vector2(-sin(a) * ISLAND_RADII.x, cos(a) * ISLAND_RADII.y).normalized()
		_invisible_wall(Vector3(ISLAND_CENTER.x + p.x, 10, ISLAND_CENTER.y + p.y), Vector3(3.2, 20, 1.0),
				atan2(-tangent.y, tangent.x))


# Builds a rendered, collidable terrain from `height_fn(x, z)`. The grid has `samples` points one metre
# apart, centred on `center` (x, z).
func build_heightmap(height_fn: Callable, samples: Vector2i, center: Vector2, material: Material) -> StaticBody3D:
	var data := PackedFloat32Array()
	data.resize(samples.x * samples.y)
	var origin := Vector2(-(samples.x - 1) / 2.0, -(samples.y - 1) / 2.0) + center
	for j in samples.y:
		for i in samples.x:
			data[j * samples.x + i] = height_fn.call(origin.x + i, origin.y + j)
	var shape := HeightMapShape3D.new()
	shape.map_width = samples.x
	shape.map_depth = samples.y
	shape.map_data = data
	var ground := StaticBody3D.new()
	ground.position = Vector3(center.x, 0, center.y)
	var cs := CollisionShape3D.new()
	cs.shape = shape
	ground.add_child(cs)
	add_child(ground)

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for j in samples.y - 1:
		for i in samples.x - 1:
			for corner in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 0), Vector2i(1, 1), Vector2i(0, 1)]:
				var ci: int = i + corner.x
				var cj: int = j + corner.y
				st.add_vertex(Vector3(origin.x + ci, data[cj * samples.x + ci], origin.y + cj))
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = material
	add_child(mi)
	return ground


func _build_terrain() -> void:
	var sand: StandardMaterial3D = main._mat(Color(0.93, 0.84, 0.6))
	sand.cull_mode = BaseMaterial3D.CULL_DISABLED
	build_heightmap(height_at, Vector2i(TW, TD), Vector2(0.0, TZ), sand)


func _surface(x: float, z: float) -> Vector3:
	return Vector3(x, height_at(x, z), z)


# Invisible waypoints for the run-away bottles. Beach: scattered points over the dry sand, all linked.
# Cloud walk: one point on every cloud, linked to the clouds a jump away.
func nav_graph() -> Dictionary:
	var positions: Array[Vector3] = []
	var links: Array = []
	var doors: Array = []
	if not clouds.is_empty():
		for c in clouds:
			positions.append((c["pos"] as Vector3) + Vector3(0, 0.05, 0))
		for i in positions.size():
			var row: Array = []
			for j in positions.size():
				var flat := Vector2(positions[i].x - positions[j].x, positions[i].z - positions[j].z).length()
				if i != j and flat < float(clouds[i]["r"]) + float(clouds[j]["r"]) + 3.0:
					row.append(j)
			links.append(row)
			doors.append(null)
		return {"pos": positions, "links": links, "doors": doors}
	for attempt in 120:
		if positions.size() >= 26:
			break
		var p := _land_point(0.8)
		var spaced := true
		for q in positions:
			if Vector2(p.x - q.x, p.z - q.z).length() < 2.2:
				spaced = false
		if spaced and p.y > 0.0:
			positions.append(p)
	for i in positions.size():
		var row: Array = []
		for j in positions.size():
			if i != j:
				row.append(j)
		links.append(row)
		doors.append(null)
	if positions.is_empty():
		return {}
	return {"pos": positions, "links": links, "doors": doors}


func _build_beach() -> void:
	noise.seed = randi()
	noise.frequency = 0.08
	var center := Vector3(randf_range(-4.0, 4.0), 0.0, randf_range(2.0, 5.0))
	flat_center = Vector2(center.x, center.z)
	_build_terrain()

	var sea: Material = main._mat(Color(0.2, 0.5, 0.85, 0.7))
	main._prop(main._box(Vector3(800, 0.2, 800)), Vector3(0, SEA_LEVEL - 0.1, 0), sea, false, Vector3.ZERO, self)
	main._prop(main._box(Vector3(800, 0.2, 800)), Vector3(0, SEABED - 0.15, 0), main._mat(Color(0.75, 0.68, 0.5)), false, Vector3.ZERO, self)
	# The sea reaches the island from every side: ray clicks hit this thin slab, the player wades through.
	var ocean := StaticBody3D.new()
	ocean.position = Vector3(0, SEA_LEVEL - 0.1, 0)
	ocean.collision_layer = 2
	ocean.collision_mask = 0
	ocean.set_meta("kind", "ocean")
	ocean.set_meta("label", "Ocean")
	var ocs := CollisionShape3D.new()
	var oshape := BoxShape3D.new()
	oshape.size = Vector3(400, 0.2, 400)
	ocs.shape = oshape
	ocean.add_child(ocs)
	add_child(ocean)
	_build_wall_ring()

	_build_shower_rig(center, 0.0)
	_build_tank(center)
	var crate: Material = main._mat(Color(0.55, 0.4, 0.25))
	main._prop(main._box(Vector3(0.5, 0.5, 0.5)), center + Vector3(0.8, 0.31, 0.8), crate, true, Vector3.ZERO, self)

	var sx := center.x + randf_range(-2.0, 2.0)
	var sz := center.z + 8.0
	spawn = Vector3(sx, height_at(sx, sz) + 0.95, sz)
	_build_beach_scenery(center)
	_hide_bucket()
	var boiler_at := _land_point(0.7)
	for attempt in 30:
		boiler_at = _land_point(0.7)
		if Vector2(boiler_at.x - spawn.x, boiler_at.z - spawn.z).length() > 5.0 \
				and Vector2(boiler_at.x - flat_center.x, boiler_at.z - flat_center.y).length() > 4.0:
			break
	item_spots["boiler"] = boiler_at


# The bucket sits on open, gently sloped sand away from the shower, so it is a walk to find but never hidden.
func _hide_bucket() -> void:
	var p := _land_point(0.6)
	for attempt in 60:
		var candidate := _land_point(0.7)
		var flat := absf(height_at(candidate.x + 1.0, candidate.z) - candidate.y) < 0.25 \
				and absf(height_at(candidate.x, candidate.z + 1.0) - candidate.y) < 0.25
		var from_spawn := Vector2(candidate.x - spawn.x, candidate.z - spawn.z).length()
		var from_shower := Vector2(candidate.x - flat_center.x, candidate.z - flat_center.y).length()
		if flat and candidate.y > 0.0 and candidate.y < 0.6 and from_spawn > 5.0 and from_spawn < 14.0 and from_shower > 4.5:
			p = candidate
			break
	bucket_pos = p + Vector3(0, 0.03, 0)


func _build_tank(center: Vector3) -> void:
	var steel: Material = main._mat(Color(0.55, 0.6, 0.65))
	var tank_pos := Vector3(center.x - 2.4, 0.0, center.z)
	for corner in [Vector2(-0.5, -0.5), Vector2(0.5, -0.5), Vector2(-0.5, 0.5), Vector2(0.5, 0.5)]:
		main._prop(main._cyl(0.05, 1.3), tank_pos + Vector3(corner.x, 0.65, corner.y), steel, true, Vector3.ZERO, self)
	tank_body = main._prop(main._cyl(0.75, 1.4), tank_pos + Vector3(0, 1.3 + 0.7, 0), steel, true, Vector3.ZERO, self) as StaticBody3D
	tank_body.set_meta("kind", "tank")
	tank_body.set_meta("label", "Water tank (0/3)")
	main._prop(main._cyl(0.78, 0.08), tank_pos + Vector3(0, 3.05, 0), main._mat(Color(0.4, 0.45, 0.5)), false, Vector3.ZERO, self)
	# Pipe from the tank to the shower post.
	main._prop(main._cyl(0.04, 1.4), Vector3(tank_pos.x + 0.75, 2.2, center.z) + Vector3(0.7, 0, 0), steel, false, Vector3(0, 0, 90), self)
	main._prop(main._cyl(0.04, 1.3), Vector3(center.x - 1.0, 1.9, center.z), steel, false, Vector3.ZERO, self)
	# Water gauge on the side facing the deck.
	var gauge := Vector3(tank_pos.x + 0.77, 2.0, center.z)
	main._prop(main._box(Vector3(0.05, tank_height, 0.18)), gauge, main._mat(Color(0.85, 0.88, 0.9)), false, Vector3.ZERO, self)
	tank_fill = main._prop(main._box(Vector3(0.06, tank_height, 0.12)), gauge, main._mat(Color(0.2, 0.5, 0.95)), false, Vector3.ZERO, self).get_child(0) as MeshInstance3D
	tank_base_y = gauge.y - tank_height / 2.0
	set_tank_level(0)


func set_tank_level(level: int) -> void:
	var fraction := clampf(level / 3.0, 0.02, 1.0)
	tank_fill.scale = Vector3(1, fraction, 1)
	tank_fill.position.y = (tank_base_y + tank_height * fraction / 2.0) - (tank_base_y + tank_height / 2.0)
	tank_body.set_meta("label", "Water tank (%d/3)" % level)


func _build_beach_scenery(center: Vector3) -> void:
	var trunk_mat: Material = main._mat(Color(0.5, 0.35, 0.2))
	var leaf_mat: Material = main._mat(Color(0.2, 0.6, 0.25))
	for i in 6:
		var p := _land_point(0.8)
		if Vector2(p.x - center.x, p.z - center.z).length() < 5.0 or Vector2(p.x - spawn.x, p.z - spawn.z).length() < 3.0:
			continue
		main._prop(main._cyl(0.15, 5.0), p + Vector3(0, 2.5, 0), trunk_mat, true, Vector3(randf_range(-4, 4), 0, randf_range(-4, 4)), self)
		for leaf in 7:
			var a := leaf * TAU / 7.0
			main._prop(main._box(Vector3(2.8, 0.06, 0.55)), p + Vector3(cos(a) * 1.3, 5.0, sin(a) * 1.3),
					leaf_mat, false, Vector3(0, -rad_to_deg(a), -20), self)
		main._prop(_sphere(0.16), p + Vector3(0.2, 4.8, 0.1), trunk_mat, false, Vector3.ZERO, self)

	# Umbrellas with a towel each; the three bottles lie on three different towels.
	var umbrella_colors := [Color(0.95, 0.3, 0.3), Color(0.3, 0.6, 0.95), Color(0.95, 0.85, 0.2), Color(0.4, 0.85, 0.5)]
	var sites: Array[Vector3] = []
	var tries := 0
	while sites.size() < 4 and tries < 160:
		tries += 1
		var p := _land_point(0.6)
		if Vector2(p.x - center.x, p.z - center.z).length() < 4.5 or Vector2(p.x - spawn.x, p.z - spawn.z).length() < 3.0:
			continue
		var apart := true
		for other in sites:
			if Vector2(p.x - other.x, p.z - other.z).length() < (6.5 if sites.size() < 3 else 4.0):
				apart = false
		if apart:
			sites.append(p)
	for i in sites.size():
		var p := sites[i]
		var color: Color = umbrella_colors[i % umbrella_colors.size()]
		main._prop(main._cyl(0.03, 2.2), p + Vector3(0, 1.1, 0), main._mat(Color(0.8, 0.8, 0.8)), false, Vector3.ZERO, self)
		var canopy := CylinderMesh.new()
		canopy.top_radius = 0.0
		canopy.bottom_radius = 1.4
		canopy.height = 0.5
		main._prop(canopy, p + Vector3(0, 2.3, 0), main._mat(color), false, Vector3.ZERO, self)
		var tp := _surface(p.x + 1.5, p.z + 0.4)
		main._prop(main._box(Vector3(1.6, 0.03, 0.8)), tp + Vector3(0, 0.02, 0), main._mat(color.lightened(0.4)), false,
				Vector3(0, randf_range(0, 90), 0), self)
		if bottle_spots.size() < 3:
			bottle_spots.append(tp + Vector3(randf_range(-0.25, 0.25), 0.04 + 0.11, randf_range(-0.1, 0.1)))
	while bottle_spots.size() < 3:
		bottle_spots.append(_land_point(0.5) + Vector3(0, 0.15, 0))
	var rock_mat: Material = main._mat(Color(0.5, 0.5, 0.52))
	for i in 6:
		var p := _land_point(0.95)
		main._prop(_sphere(randf_range(0.4, 1.0)), p, rock_mat, false, Vector3.ZERO, self)
	for i in 2:
		var p := _land_point(0.65)
		main._prop(main._cyl(0.7, 0.5), p + Vector3(0, 0.25, 0), sand_castle_material(), true, Vector3.ZERO, self)
		main._prop(main._cyl(0.4, 0.5), p + Vector3(0, 0.7, 0), sand_castle_material(), false, Vector3.ZERO, self)


func sand_castle_material() -> Material:
	return main._mat(Color(0.85, 0.74, 0.5))
