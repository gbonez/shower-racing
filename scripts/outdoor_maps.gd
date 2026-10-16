extends "res://scripts/open_world.gd"

# The outdoor special maps: a tiny city to stomp (monster_movie), a minigolf park (golf) and a lake to
# fish in (lake). All three keep their bottles hidden until the player earns them (bind_bottle() hides
# them, unlock_bottle() reveals them) and build everything from primitive meshes. They use their own
# height functions; the beach terrain of the base script is not involved.

const CITY_LINES: Array[float] = [-32.0, -16.0, 0.0, 16.0, 32.0]  # street centre lines, both axes
const STREET_W := 2.4
const BLOCK_SIZE := 13.6
const CITY_LIMIT := 34.2
const BUILDING_COLORS: Array[Color] = [Color(0.85, 0.55, 0.45), Color(0.9, 0.82, 0.6), Color(0.6, 0.7, 0.85),
		Color(0.76, 0.76, 0.79), Color(0.55, 0.65, 0.58), Color(0.88, 0.66, 0.36), Color(0.72, 0.52, 0.62),
		Color(0.95, 0.93, 0.88)]
const CRUSH_LINES: Array[String] = ["CRUNCH!", "SQUISH!", "KA-BLOOEY!", "Tiny city, big feet!", "RAAAWR!",
		"Crumble crumble!", "Sorry, mayor!"]

var map_kind := ""
var _time := 0.0
var _mats: Dictionary = {}
var _mm: Dictionary = {}  # key -> {mesh, mat, xf}: instanced decoration, built by _flush_mm()
var _obstacles: Array[Vector3] = []  # x, z, radius: things that spawns and waypoints keep clear of
var _blocked: Array[Rect2] = []
var _bottle_bodies: Dictionary = {}  # bottle index -> body handed to bind_bottle()
var _action_bodies: Array[StaticBody3D] = []


func build(kind: String) -> void:
	map_kind = kind
	indoor = false
	match kind:
		"monster_movie":
			_build_monster()
		"golf":
			_build_golf()
		"lake":
			_build_lake()
		_:
			super.build(kind)
	_flush_mm()


func customize_env(env: Environment, sun: DirectionalLight3D) -> void:
	var sky_material := env.sky.sky_material as ProceduralSkyMaterial if env.sky != null else null
	match map_kind:
		"monster_movie":
			_tint_sky(sky_material, Color(0.42, 0.62, 0.9), Color(0.86, 0.88, 0.92), Color(0.86, 0.88, 0.92))
			env.fog_enabled = true
			env.fog_light_color = Color(0.82, 0.86, 0.92)
			env.fog_density = 0.007
			sun.light_color = Color(1.0, 0.96, 0.9)
			sun.rotation_degrees = Vector3(-52, 40, 0)
		"golf":
			_tint_sky(sky_material, Color(0.2, 0.55, 1.0), Color(0.88, 0.95, 1.0), Color(0.75, 0.9, 0.7))
			sun.light_color = Color(1.0, 0.92, 0.78)
			sun.light_energy = 1.25
			sun.rotation_degrees = Vector3(-46, 28, 0)
			env.ambient_light_energy = 1.1
		"lake":
			_tint_sky(sky_material, Color(0.38, 0.6, 0.9), Color(0.88, 0.9, 0.92), Color(0.6, 0.72, 0.68))
			env.fog_enabled = true
			env.fog_light_color = Color(0.8, 0.86, 0.9)
			env.fog_density = 0.006
			sun.light_color = Color(1.0, 0.9, 0.74)
			sun.rotation_degrees = Vector3(-34, -25, 0)


func _tint_sky(sky_material: ProceduralSkyMaterial, top: Color, horizon: Color, ground: Color) -> void:
	if sky_material == null:
		return
	sky_material.sky_top_color = top
	sky_material.sky_horizon_color = horizon
	sky_material.ground_horizon_color = horizon
	sky_material.ground_bottom_color = ground


func bind_bottle(index: int, body: PhysicsBody3D, _id: String) -> void:
	body.visible = false
	body.collision_layer = 0
	hidden_bottles[index] = body
	_bottle_bodies[index] = body


# unlock_bottle() puts a static bottle's centre at `at` minus 0.11; static bottles are centred, so stand
# the body on the surface properly afterwards.
func _reveal(index: int, at: Vector3) -> void:
	var body: PhysicsBody3D = _bottle_bodies.get(index)
	unlock_bottle(index, at)
	if body is StaticBody3D:
		body.position = at


func nav_graph() -> Dictionary:
	match map_kind:
		"monster_movie":
			return _monster_nav()
		"golf":
			return _golf_nav()
		"lake":
			return _lake_nav()
	return super.nav_graph()


func decoy_spot() -> Vector3:
	match map_kind:
		"monster_movie":
			return _street_spot()
		"golf":
			return _golf_decoy()
		"lake":
			return _lake_decoy()
	return Vector3(0, 0.11, 0)


func extra_spot() -> Vector3:
	match map_kind:
		"monster_movie":
			return _monster_extra()
		"golf":
			return _golf_extra()
		"lake":
			return _lake_extra()
	return Vector3(0, 0.11, 0)


func _process(delta: float) -> void:
	_time += delta
	match map_kind:
		"monster_movie":
			_wobble_hiders()
		"golf":
			for mill in _blades:
				mill.rotation.z += 0.6 * delta
			if _fin != null:
				_fin.rotation.y += 0.9 * delta
		"lake":
			if _boat != null:
				_boat.position.y = -0.32 + sin(_time * 1.3) * 0.025
				_boat.rotation.z = sin(_time * 0.9) * 0.025
				_boat.rotation.x = cos(_time * 0.7) * 0.015


func _physics_process(_delta: float) -> void:
	if map_kind == "monster_movie":
		_check_crush()


# --- Shared helpers ---

func _color(c: Color) -> StandardMaterial3D:
	var key := c.to_html()
	if not _mats.has(key):
		_mats[key] = main._mat(c)
	return _mats[key]


func _glow(c: Color, energy := 1.6) -> StandardMaterial3D:
	var key := "g" + c.to_html() + str(energy)
	if not _mats.has(key):
		var m: StandardMaterial3D = main._mat(c)
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = energy
		_mats[key] = m
	return _mats[key]


func _box(size: Vector3, pos: Vector3, color: Color, solid := false, rot := Vector3.ZERO, parent: Node = null) -> Node3D:
	return main._prop(main._box(size), pos, _color(color), solid, rot, parent if parent != null else self)


func _cylinder(radius: float, height: float, pos: Vector3, color: Color, solid := false, rot := Vector3.ZERO,
		parent: Node = null) -> Node3D:
	return main._prop(main._cyl(radius, height), pos, _color(color), solid, rot, parent if parent != null else self)


func _cone(radius: float, height: float, pos: Vector3, color: Color, parent: Node = null, top_radius := 0.0) -> Node3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = top_radius
	mesh.bottom_radius = radius
	mesh.height = height
	return main._prop(mesh, pos, _color(color), false, Vector3.ZERO, parent if parent != null else self)


func _ball(radius: float, pos: Vector3, color: Color, parent: Node = null, glowing := false) -> Node3D:
	var mat: Material = _glow(color) if glowing else _color(color)
	return main._prop(_sphere(radius), pos, mat, false, Vector3.ZERO, parent if parent != null else self)


func _solid_body(shape: Shape3D, pos: Vector3, rot := Vector3.ZERO, parent: Node = null) -> StaticBody3D:
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)
	body.position = pos
	body.rotation_degrees = rot
	(parent if parent != null else self).add_child(body)
	return body


func _box_shape(size: Vector3) -> BoxShape3D:
	var s := BoxShape3D.new()
	s.size = size
	return s


func _text3d(text: String, pos: Vector3, height: float, color: Color, outline: Color, parent: Node = null,
		billboard := false, yaw_deg := 0.0, outline_px := 14) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = 64
	l.pixel_size = height / 64.0
	l.modulate = color
	l.outline_modulate = outline
	l.outline_size = outline_px
	l.shaded = false
	if billboard:
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.position = pos
	l.rotation_degrees.y = yaw_deg
	(parent if parent != null else self).add_child(l)
	return l


func _clickable(body: StaticBody3D, label: String, action: Callable) -> void:
	body.set_meta("kind", "map_action")
	body.set_meta("label", label)
	body.set_meta("action", action)


func _mm_add(key: String, mesh: Mesh, mat: Material, xf: Transform3D) -> void:
	if not _mm.has(key):
		_mm[key] = {"mesh": mesh, "mat": mat, "xf": []}
	(_mm[key]["xf"] as Array).append(xf)


func _flush_mm() -> void:
	for key in _mm:
		var d: Dictionary = _mm[key]
		var xf: Array = d["xf"]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = d["mesh"]
		mm.instance_count = xf.size()
		for i in xf.size():
			mm.set_instance_transform(i, xf[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = d["mat"]
		mmi.layers = main.mesh_layers
		add_child(mmi)
	_mm.clear()


func _xf(pos: Vector3, scl := Vector3.ONE, yaw := 0.0) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, yaw).scaled(scl), pos)


# The four walls round a square area of half-size `half`, standing just outside it.
func _boundary_walls(half: float) -> void:
	_invisible_wall(Vector3(0, 6, half + 0.5), Vector3(half * 2.0 + 4.0, 12, 1.0))
	_invisible_wall(Vector3(0, 6, -half - 0.5), Vector3(half * 2.0 + 4.0, 12, 1.0))
	_invisible_wall(Vector3(half + 0.5, 6, 0), Vector3(1.0, 12, half * 2.0 + 4.0))
	_invisible_wall(Vector3(-half - 0.5, 6, 0), Vector3(1.0, 12, half * 2.0 + 4.0))


# build_heightmap() draws one flat material; swap its mesh for one coloured per vertex.
func _build_colored_terrain(height_fn: Callable, samples: Vector2i, center: Vector2, color_fn: Callable) -> StaticBody3D:
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var ground := build_heightmap(height_fn, samples, center, mat)
	var mi := get_child(get_child_count() - 1) as MeshInstance3D
	var origin := Vector2(-(samples.x - 1) / 2.0, -(samples.y - 1) / 2.0) + center
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for j in samples.y - 1:
		for i in samples.x - 1:
			for corner in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 0), Vector2i(1, 1), Vector2i(0, 1)]:
				var x: float = origin.x + i + corner.x
				var z: float = origin.y + j + corner.y
				var h: float = height_fn.call(x, z)
				st.set_color(color_fn.call(x, z, h))
				st.add_vertex(Vector3(x, h, z))
	st.generate_normals()
	mi.mesh = st.commit()
	return ground


func _clear_xz(p: Vector2, extra: float) -> bool:
	for o in _obstacles:
		if Vector2(o.x, o.y).distance_to(p) < o.z + extra:
			return false
	for r in _blocked:
		if r.grow(extra).has_point(p):
			return false
	return true


func _segment_clear(a: Vector2, b: Vector2, extra: float, ok_fn: Callable) -> bool:
	var steps := maxi(int(a.distance_to(b) / 0.5), 1)
	for s in steps + 1:
		var p := a.lerp(b, float(s) / steps)
		if not _clear_xz(p, extra) or not ok_fn.call(p):
			return false
	return true


func _link_graph(pos: Array[Vector3], max_dist: float, extra: float, ok_fn: Callable) -> Dictionary:
	var links: Array = []
	var doors: Array = []
	for i in pos.size():
		links.append([])
		doors.append(null)
	for i in pos.size():
		for j in range(i + 1, pos.size()):
			var a := Vector2(pos[i].x, pos[i].z)
			var b := Vector2(pos[j].x, pos[j].z)
			if a.distance_to(b) <= max_dist and _segment_clear(a, b, extra, ok_fn):
				(links[i] as Array).append(j)
				(links[j] as Array).append(i)
	return {"pos": pos, "links": links, "doors": doors}


# --- Monster movie ---

var _bld: Array[Dictionary] = []  # {body, vis, shapes, height, pos, size, color, crushed, hide}
var _hiders: Array[int] = []  # bottle index -> building index
var _crushed := 0
var _park := Rect2()
var _deck := Vector2.ZERO
var _win_dark: StandardMaterial3D
var _win_lit: StandardMaterial3D


func _block_rect(i: int, j: int) -> Rect2:
	return Rect2(CITY_LINES[i] + STREET_W / 2.0, CITY_LINES[j] + STREET_W / 2.0, BLOCK_SIZE, BLOCK_SIZE)


func _build_monster() -> void:
	player_jump = 1.0
	player_speed = 1.0
	respawn_height = -10.0
	_win_dark = main._mat(Color(0.16, 0.2, 0.3))
	_win_dark.cull_mode = BaseMaterial3D.CULL_DISABLED
	_win_lit = main._mat(Color(1.0, 0.9, 0.5))
	_win_lit.emission_enabled = true
	_win_lit.emission = Color(1.0, 0.85, 0.4)
	_win_lit.emission_energy_multiplier = 1.4
	_win_lit.cull_mode = BaseMaterial3D.CULL_DISABLED

	_boundary_walls(CITY_LIMIT)
	_box(Vector3(90, 0.5, 90), Vector3(0, -0.25, 0), Color(0.46, 0.7, 0.38), true)
	for line in CITY_LINES:
		_box(Vector3(66.4, 0.01, STREET_W), Vector3(0, 0.005, line), Color(0.22, 0.23, 0.26))
		_box(Vector3(STREET_W, 0.01, 66.4), Vector3(line, 0.005, 0), Color(0.22, 0.23, 0.26))
	_street_dashes()

	var park_i := randi_range(1, 2)
	_park = _block_rect(park_i, 3)
	var cx := _park.get_center().x
	spawn = Vector3(cx, 0.95, 32.0)
	_deck = Vector2(cx + 3.0, 26.6)

	var cells: Array[Vector2i] = []
	for i in 4:
		for j in 4:
			if not (i == park_i and j == 3):
				cells.append(Vector2i(i, j))
	cells.shuffle()
	var stadiums: Array[Vector2i] = []
	stadiums.append(cells.pop_back())
	stadiums.append(cells.pop_back())
	bottle_spots.resize(3)
	_hiders.resize(3)
	var hide_cells: Array[Vector2i] = [cells[0], cells[1], cells[2]]
	for i in 4:
		for j in 4:
			var cell := Vector2i(i, j)
			var rect := _block_rect(i, j)
			if cell == Vector2i(park_i, 3):
				_build_park(rect)
			elif cell in stadiums:
				_box(Vector3(BLOCK_SIZE, 0.02, BLOCK_SIZE), Vector3(rect.get_center().x, 0.01, rect.get_center().y), Color(0.72, 0.72, 0.7))
				_build_stadium(rect, stadiums.find(cell))
			else:
				_box(Vector3(BLOCK_SIZE, 0.02, BLOCK_SIZE), Vector3(rect.get_center().x, 0.01, rect.get_center().y), Color(0.72, 0.72, 0.7))
				_build_block(rect, hide_cells.find(cell))

	_street_lights()
	_street_cars()
	item_spots["boiler"] = Vector3(cx + 4.2, 0.0, 20.4)


func _street_dashes() -> void:
	var dash: Mesh = main._box(Vector3(0.6, 0.004, 0.06))
	var dash_v: Mesh = main._box(Vector3(0.06, 0.004, 0.6))
	var mat: Material = _color(Color(0.95, 0.9, 0.55))
	for line in CITY_LINES:
		var t := -32.0
		while t <= 32.0:
			var near_crossing := false
			for other in CITY_LINES:
				if absf(t - other) < 2.0:
					near_crossing = true
			if not near_crossing:
				_mm_add("dash_h", dash, mat, _xf(Vector3(t, 0.012, line)))
				_mm_add("dash_v", dash_v, mat, _xf(Vector3(line, 0.012, t)))
			t += 1.5


func _street_lights() -> void:
	var pole_color := Color(0.3, 0.3, 0.34)
	for i in CITY_LINES.size():
		for j in CITY_LINES.size():
			var p := Vector3(CITY_LINES[i] + 1.0, 0, CITY_LINES[j] + 1.0)
			if absf(p.x) > 33.0 or absf(p.z) > 33.0:
				continue
			_cylinder(0.018, 0.8, p + Vector3(0, 0.4, 0), pole_color)
			_ball(0.045, p + Vector3(0, 0.82, 0), Color(1.0, 0.95, 0.7), null, true)


func _street_cars() -> void:
	var palette: Array[Color] = [Color(0.9, 0.2, 0.2), Color(0.2, 0.4, 0.9), Color(0.95, 0.85, 0.2), Color(0.9, 0.9, 0.92),
			Color(0.2, 0.7, 0.4), Color(0.15, 0.15, 0.18)]
	for n in 34:
		var line: float = CITY_LINES[randi() % CITY_LINES.size()]
		var along := randf_range(-31.0, 31.0)
		var off := (0.85 if randf() < 0.5 else -0.85)
		var horizontal := randf() < 0.5
		var p := Vector3(along, 0, line + off) if horizontal else Vector3(line + off, 0, along)
		if Vector2(p.x - spawn.x, p.z - spawn.z).length() < 3.5:
			continue
		var on_crossing := false
		for other in CITY_LINES:
			if absf(along - other) < 1.6:
				on_crossing = true
		if on_crossing:
			continue
		var car := _box(Vector3(0.5, 0.14, 0.26), p + Vector3(0, 0.09, 0), palette[randi() % palette.size()], false,
				Vector3(0, 0 if horizontal else 90, 0))
		_box(Vector3(0.26, 0.1, 0.22), Vector3(-0.02, 0.11, 0), Color(0.55, 0.7, 0.85), false, Vector3.ZERO, car)


func _tiny_tree(p: Vector2, s: float) -> void:
	var trunk: Mesh = main._cyl(0.025, 0.2)
	_mm_add("trunk", trunk, _color(Color(0.45, 0.3, 0.18)), _xf(Vector3(p.x, 0.1 * s, p.y), Vector3.ONE * s))
	if randf() < 0.5:
		_mm_add("crown", _sphere(0.17), _color(Color(0.25, 0.6, 0.27)), _xf(Vector3(p.x, 0.3 * s, p.y), Vector3.ONE * s))
	else:
		var cone := CylinderMesh.new()
		cone.top_radius = 0.0
		cone.bottom_radius = 0.16
		cone.height = 0.4
		_mm_add("cone", cone, _color(Color(0.18, 0.5, 0.28)), _xf(Vector3(p.x, 0.36 * s, p.y), Vector3.ONE * s))


func _build_park(rect: Rect2) -> void:
	var c := rect.get_center()
	_box(Vector3(BLOCK_SIZE, 0.03, BLOCK_SIZE), Vector3(c.x, 0.015, c.y), Color(0.38, 0.72, 0.3))
	var pond := Vector2(c.x - 3.6, 20.5)
	_cylinder(2.15, 0.02, Vector3(pond.x, 0.035, pond.y), Color(0.55, 0.5, 0.4))
	_cylinder(2.0, 0.02, Vector3(pond.x, 0.045, pond.y), Color(0.25, 0.55, 0.9, 0.85))
	_obstacles.append(Vector3(pond.x, pond.y, 2.2))
	for d in 2:
		_ball(0.06, Vector3(pond.x + 0.6 - d * 1.1, 0.09, pond.y + 0.3 + d * 0.5), Color(1.0, 0.85, 0.2))
	var boiler := Vector2(c.x + 4.2, 20.4)
	var attempts := 0
	var placed := 0
	while placed < 14 and attempts < 80:
		attempts += 1
		var p := rect.position + Vector2(randf() * rect.size.x, randf() * rect.size.y)
		var ok := absf(p.x - c.x) > 1.3 and p.distance_to(pond) > 2.9 and p.distance_to(boiler) > 1.5
		ok = ok and p.distance_to(_deck) > 2.6
		if ok:
			_tiny_tree(p, randf_range(0.9, 1.5))
			placed += 1
	for b in [Vector2(c.x + 1.5, 21.3), Vector2(c.x - 1.5, 29.3)]:
		_box(Vector3(0.5, 0.05, 0.15), Vector3(b.x, 0.11, b.y), Color(0.55, 0.38, 0.2))
		_box(Vector3(0.5, 0.1, 0.03), Vector3(b.x, 0.16, b.y + 0.07), Color(0.55, 0.38, 0.2))
	_obstacles.append(Vector3(_deck.x - 1.0, _deck.y, 0.5))
	_blocked.append(Rect2(_deck.x - 1.2, _deck.y - 1.2, 2.4, 2.4))
	_build_shower_rig(Vector3(_deck.x, 0.0, _deck.y), 0.0)


func _build_stadium(rect: Rect2, which: int) -> void:
	var c := rect.get_center()
	var seats: Array[Color] = [Color(0.85, 0.2, 0.2), Color(0.2, 0.4, 0.85), Color(0.95, 0.8, 0.2), Color(0.2, 0.7, 0.4)]
	var seat_a: Color = seats[(which * 2) % 4]
	var seat_b: Color = seats[(which * 2 + 1) % 4]
	_box(Vector3(6.8, 0.012, 4.0), Vector3(c.x, 0.03, c.y), Color(0.95, 0.95, 0.95))
	_box(Vector3(6.4, 0.014, 3.6), Vector3(c.x, 0.032, c.y), Color(0.3, 0.7, 0.3))
	_box(Vector3(0.04, 0.016, 3.6), Vector3(c.x, 0.034, c.y), Color(0.95, 0.95, 0.95))
	_cylinder(0.5, 0.016, Vector3(c.x, 0.033, c.y), Color(0.95, 0.95, 0.95))
	_cylinder(0.46, 0.018, Vector3(c.x, 0.034, c.y), Color(0.3, 0.7, 0.3))
	for side in [-1.0, 1.0]:
		_box(Vector3(0.05, 0.2, 0.6), Vector3(c.x + side * 3.1, 0.12, c.y), Color(0.95, 0.95, 0.95))
		var stand_color: Color = seat_a if side < 0.0 else seat_b
		_box(Vector3(9.2, 0.35, 1.2), Vector3(c.x, 0.175, c.y + side * 2.5), stand_color, true)
		_box(Vector3(9.2, 0.7, 0.6), Vector3(c.x, 0.35, c.y + side * 3.4), stand_color.darkened(0.2), true)
		_box(Vector3(1.2, 0.35, 3.6), Vector3(c.x + side * 4.0, 0.175, c.y), stand_color.lightened(0.15), true)
		_box(Vector3(9.4, 0.05, 1.9), Vector3(c.x, 1.25, c.y + side * 3.3), Color(0.9, 0.9, 0.92))
		for k in [-1.0, 1.0]:
			_cylinder(0.025, 1.2, Vector3(c.x + k * 4.5, 0.62, c.y + side * 3.95), Color(0.5, 0.5, 0.55))
			_cylinder(0.04, 1.7, Vector3(c.x + k * 4.9, 0.85, c.y + side * 4.3), Color(0.35, 0.35, 0.4))
			_box(Vector3(0.32, 0.1, 0.18), Vector3(c.x + k * 4.9, 1.72, c.y + side * 4.3), Color(1.0, 0.98, 0.8), false)
	_box(Vector3(1.5, 0.45, 0.08), Vector3(c.x, 1.0, c.y - 4.8), Color(0.1, 0.12, 0.15))
	_text3d("3 : 2", Vector3(c.x, 1.0, c.y - 4.74), 0.28, Color(1.0, 0.8, 0.2), Color(0, 0, 0, 0), null, false, 180.0, 0)


func _build_block(rect: Rect2, hide_index: int) -> void:
	var cell := rect.size / 3.0
	for ci in 3:
		for cj in 3:
			var centre := rect.position + Vector2((ci + 0.5) * cell.x, (cj + 0.5) * cell.y)
			var forced := hide_index >= 0 and ci == 1 and cj == 1
			if not forced and randf() > 0.72:
				if randf() < 0.5:
					_tiny_tree(centre + Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)), randf_range(0.9, 1.4))
				continue
			centre += Vector2(randf_range(-0.7, 0.7), randf_range(-0.7, 0.7))
			var size := Vector2(randf_range(1.0, 2.2), randf_range(1.0, 2.2))
			var h := randf_range(1.05, 1.25) if forced else randf_range(0.5, 1.25)
			var color: Color = BUILDING_COLORS[randi() % BUILDING_COLORS.size()]
			var style := 0 if forced else randi() % 5
			_make_building(centre, size, h, color, style, hide_index if forced else -1)


func _make_building(pos: Vector2, size: Vector2, h: float, color: Color, style: int, hide_index: int) -> void:
	var body := StaticBody3D.new()
	body.position = Vector3(pos.x, 0, pos.y)
	body.set_meta("building", true)
	body.set_meta("idx", _bld.size())
	add_child(body)
	var vis := Node3D.new()
	body.add_child(vis)
	var shapes: Array[CollisionShape3D] = []
	var roof_color := color.darkened(0.35)
	match style:
		2:  # stepped
			var lower := h * 0.62
			_building_part(body, vis, Vector3(size.x, lower, size.y), Vector3(0, lower / 2.0, 0), color, shapes)
			var upper := Vector3(size.x * 0.62, h - lower, size.y * 0.62)
			_building_part(body, vis, upper, Vector3(0, lower + upper.y / 2.0, 0), color.lightened(0.1), shapes)
			_roof(vis, upper, h, roof_color)
		3:  # L shape
			_building_part(body, vis, Vector3(size.x, h, size.y * 0.55), Vector3(0, h / 2.0, -size.y * 0.225), color, shapes)
			var wing := Vector3(size.x * 0.5, h * 0.72, size.y)
			_building_part(body, vis, wing, Vector3(size.x * 0.25, wing.y / 2.0, 0), color.darkened(0.08), shapes)
			_roof(vis, Vector3(size.x, h, size.y * 0.55), h, roof_color, Vector3(0, 0, -size.y * 0.225))
			_roof(vis, wing, wing.y, roof_color, Vector3(size.x * 0.25, 0, 0))
		_:
			_building_part(body, vis, Vector3(size.x, h, size.y), Vector3(0, h / 2.0, 0), color, shapes)
			_roof(vis, Vector3(size.x, h, size.y), h, roof_color)
			if style == 4 or (hide_index < 0 and randf() < 0.08):
				_water_tower(vis, Vector3(size.x * 0.22, h, size.y * 0.2))
			elif randf() < 0.5 or hide_index >= 0:
				_cylinder(0.012, 0.3, Vector3(-size.x * 0.25, h + 0.17, size.y * 0.2), Color(0.3, 0.3, 0.33), false, Vector3.ZERO, vis)
				_ball(0.02, Vector3(-size.x * 0.25, h + 0.33, size.y * 0.2), Color(1.0, 0.2, 0.2), vis, true)
			else:
				_box(Vector3(0.3, 0.12, 0.25), Vector3(-size.x * 0.2, h + 0.07, 0), Color(0.6, 0.62, 0.65), false, Vector3.ZERO, vis)
	var rec := {"body": body, "vis": vis, "shapes": shapes, "height": h, "pos": pos, "size": size,
			"color": color, "crushed": false, "hide": hide_index, "phase": randf() * TAU}
	_bld.append(rec)
	if hide_index >= 0:
		bottle_spots[hide_index] = Vector3(pos.x, 0.11, pos.y)
		_hiders[hide_index] = _bld.size() - 1


func _building_part(body: StaticBody3D, vis: Node3D, size: Vector3, centre: Vector3, color: Color,
		shapes: Array[CollisionShape3D]) -> void:
	_box(size, centre, color, false, Vector3.ZERO, vis)
	var cs := CollisionShape3D.new()
	cs.shape = _box_shape(size)
	cs.position = centre
	body.add_child(cs)
	shapes.append(cs)
	var mi := MeshInstance3D.new()
	mi.mesh = _window_mesh(size, centre)
	mi.layers = main.mesh_layers
	vis.add_child(mi)


func _roof(vis: Node3D, size: Vector3, top: float, color: Color, offset := Vector3.ZERO) -> void:
	_box(Vector3(size.x + 0.06, 0.03, size.z + 0.06), Vector3(offset.x, top + 0.015, offset.z), color, false, Vector3.ZERO, vis)


func _water_tower(vis: Node3D, p: Vector3) -> void:
	var wood := Color(0.5, 0.36, 0.24)
	for corner in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
		_cylinder(0.01, 0.18, p + Vector3(corner.x * 0.07, 0.09, corner.y * 0.07), wood, false, Vector3.ZERO, vis)
	_cylinder(0.11, 0.2, p + Vector3(0, 0.28, 0), Color(0.6, 0.45, 0.3), false, Vector3.ZERO, vis)
	_cone(0.12, 0.1, p + Vector3(0, 0.43, 0), Color(0.4, 0.3, 0.22), vis)


func _window_mesh(size: Vector3, centre: Vector3) -> ArrayMesh:
	var dark := SurfaceTool.new()
	var lit := SurfaceTool.new()
	dark.begin(Mesh.PRIMITIVE_TRIANGLES)
	lit.begin(Mesh.PRIMITIVE_TRIANGLES)
	dark.set_material(_win_dark)
	lit.set_material(_win_lit)
	var any_dark := false
	var any_lit := false
	var normals: Array[Vector3] = [Vector3(0, 0, 1), Vector3(0, 0, -1), Vector3(1, 0, 0), Vector3(-1, 0, 0)]
	for face in 4:
		var n := normals[face]
		var width := size.x if face < 2 else size.z
		var depth := size.z if face < 2 else size.x
		var t := Vector3.UP.cross(n)
		var cols := int((width - 0.1) / 0.28)
		var rows := int((size.y - 0.2) / 0.24)
		for c in cols:
			for r in rows:
				var u := (c + 0.5) * width / cols - width / 2.0
				var p := centre + n * (depth / 2.0 + 0.004) + t * u + Vector3(0, -size.y / 2.0 + 0.2 + r * 0.24, 0)
				var is_lit := randf() < 0.3
				var st := lit if is_lit else dark
				if is_lit:
					any_lit = true
				else:
					any_dark = true
				var a := p - t * 0.065 - Vector3(0, 0.065, 0)
				var b := p + t * 0.065 - Vector3(0, 0.065, 0)
				var cc := p + t * 0.065 + Vector3(0, 0.065, 0)
				var d := p - t * 0.065 + Vector3(0, 0.065, 0)
				for v in [a, b, cc, a, cc, d]:
					st.set_normal(n)
					st.add_vertex(v)
	var mesh := ArrayMesh.new()
	if any_dark:
		dark.commit(mesh)
	if any_lit:
		lit.commit(mesh)
	return mesh


func _check_crush() -> void:
	var player: CharacterBody3D = main.player
	if player == null:
		return
	for i in player.get_slide_collision_count():
		var hit := player.get_slide_collision(i)
		var collider := hit.get_collider() as Node
		if collider != null and collider.has_meta("building") and hit.get_normal().y > 0.7:
			var rec := _bld[int(collider.get_meta("idx"))]
			if not rec["crushed"]:
				_crush(rec)


func _crush(rec: Dictionary) -> void:
	rec["crushed"] = true
	for cs in rec["shapes"]:
		(cs as CollisionShape3D).set_deferred("disabled", true)
	var vis: Node3D = rec["vis"]
	vis.rotation = Vector3.ZERO
	vis.position = Vector3.ZERO
	var tween := create_tween()
	tween.tween_property(vis, "scale", Vector3(1.1, 0.12, 1.1), 0.4).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	var pos: Vector2 = rec["pos"]
	var size: Vector2 = rec["size"]
	var color: Color = rec["color"]
	for k in 6:
		var a := randf() * TAU
		var r := randf_range(0.55, 0.9) * maxf(size.x, size.y) * 0.8
		var s := randf_range(0.08, 0.2)
		_box(Vector3(s, s * 0.6, s), Vector3(pos.x + cos(a) * r, s * 0.3, pos.y + sin(a) * r),
				color.darkened(randf_range(0.0, 0.4)), false, Vector3(randf_range(-20, 20), randf() * 90.0, randf_range(-20, 20)))
	_crushed += 1
	var line: String = CRUSH_LINES[randi() % CRUSH_LINES.size()]
	var hide_index: int = rec["hide"]
	if hide_index >= 0:
		var top: float = float(rec["height"]) * 0.12
		_reveal(hide_index, Vector3(pos.x, top + 0.11, pos.y))
		main.say("%s A bottle was hiding in the rubble!" % line)
	else:
		main.say("%s (%d crushed)" % [line, _crushed])


func _wobble_hiders() -> void:
	var player: CharacterBody3D = main.player
	if player == null:
		return
	for index in _hiders:
		var rec := _bld[index]
		if rec["crushed"]:
			continue
		var vis: Node3D = rec["vis"]
		var p: Vector2 = rec["pos"]
		var dist := Vector2(player.global_position.x - p.x, player.global_position.z - p.y).length()
		if dist < 5.0:
			var k := 1.0 - dist / 5.0
			var phase: float = rec["phase"]
			vis.rotation = Vector3(cos(_time * 31.0 + phase) * 0.03, 0.0, sin(_time * 38.0 + phase) * 0.045) * (0.4 + k)
			vis.position.x = sin(_time * 47.0 + phase) * 0.012 * k
		elif vis.rotation != Vector3.ZERO:
			vis.rotation = Vector3.ZERO
			vis.position = Vector3.ZERO


func _street_spot() -> Vector3:
	if randf() < 0.3:
		for attempt in 20:
			var p := _park.position + Vector2(randf_range(1.0, _park.size.x - 1.0), randf_range(1.0, _park.size.y - 1.0))
			if p.distance_to(Vector2(_park.get_center().x - 3.6, 20.5)) > 2.6 and p.distance_to(_deck) > 2.6 \
					and p.distance_to(Vector2(_park.get_center().x + 4.2, 20.4)) > 1.5:
				return Vector3(p.x, 0.11, p.y)
	var line: float = CITY_LINES[randi() % CITY_LINES.size()]
	var along := randf_range(-31.0, 31.0)
	var off := randf_range(-0.45, 0.45)
	if randf() < 0.5:
		return Vector3(along, 0.11, line + off)
	return Vector3(line + off, 0.11, along)


func _monster_extra() -> Vector3:
	return _street_spot()


func _monster_nav() -> Dictionary:
	var pos: Array[Vector3] = []
	var links: Array = []
	var n := CITY_LINES.size()
	for i in n:
		for j in n:
			pos.append(Vector3(CITY_LINES[i], 0, CITY_LINES[j]))
			links.append([])
	var add_node := func(p: Vector3) -> int:
		pos.append(p)
		links.append([])
		return pos.size() - 1
	var connect_nodes := func(a: int, b: int) -> void:
		if not (links[a] as Array).has(b):
			(links[a] as Array).append(b)
		if not (links[b] as Array).has(a):
			(links[b] as Array).append(a)
	var hmid: Dictionary = {}
	var vmid: Dictionary = {}
	for i in n - 1:
		for j in n:
			var mid_x := (CITY_LINES[i] + CITY_LINES[i + 1]) / 2.0
			var h_node: int = add_node.call(Vector3(mid_x, 0, CITY_LINES[j]))
			hmid[Vector2i(i, j)] = h_node
			connect_nodes.call(h_node, i * n + j)
			connect_nodes.call(h_node, (i + 1) * n + j)
			var v_node: int = add_node.call(Vector3(CITY_LINES[j], 0, mid_x))
			vmid[Vector2i(j, i)] = v_node
			connect_nodes.call(v_node, j * n + i)
			connect_nodes.call(v_node, j * n + i + 1)
	# The park: a hub linked to the streets around it, plus a few spots inside.
	var cx := _park.get_center().x
	var park_i := 1 if cx < 0.0 else 2
	var hub: int = add_node.call(Vector3(cx, 0, 24.0))
	connect_nodes.call(hub, hmid[Vector2i(park_i, 3)])
	connect_nodes.call(hub, hmid[Vector2i(park_i, 4)])
	connect_nodes.call(hub, vmid[Vector2i(park_i, 3)])
	connect_nodes.call(hub, vmid[Vector2i(park_i + 1, 3)])
	var east: int = add_node.call(Vector3(cx + 4.5, 0, 23.0))
	var west: int = add_node.call(Vector3(cx - 4.5, 0, 28.0))
	connect_nodes.call(hub, east)
	connect_nodes.call(hub, west)
	var doors: Array = []
	doors.resize(pos.size())
	return {"pos": pos, "links": links, "doors": doors}


# --- Golf ---

const LANE_W := 3.5
const FENCE_HALF := 38.5
const TURF := Color(0.1, 0.78, 0.35)
const PATH_COLOR := Color(0.93, 0.88, 0.78)

var _flip := 1.0  # the whole park may be mirrored left to right
var _blades: Array[Node3D] = []
var _fin: Node3D
var _holes: Array[Dictionary] = []  # {ball, cup, done}
var _hole_seeds: Array[int] = []
var _walk_paths: Array[Rect2] = []
var _golf_noise := FastNoiseLite.new()


func _fl(x: float, z: float) -> Vector2:
	return Vector2(x * _flip, z)


# Flat inside the fence; a low berm of hills beyond it.
func _golf_height(x: float, z: float) -> float:
	var m := maxf(absf(x), absf(z))
	if m <= 40.0:
		return 0.0
	var t := clampf((m - 40.0) / 5.0, 0.0, 1.0)
	return sin(t * PI) * (2.4 + 1.4 * _golf_noise.get_noise_2d(x, z))


func _golf_color(x: float, z: float, h: float) -> Color:
	var stripe := (int(floor((x + 100.0) / 3.0)) + int(floor((z + 100.0) / 3.0))) % 2
	var base := Color(0.42, 0.82, 0.3) if stripe == 0 else Color(0.37, 0.76, 0.26)
	return base.lerp(Color(0.2, 0.62, 0.28), clampf(h / 2.5, 0.0, 1.0))


func _build_golf() -> void:
	player_jump = 0.0
	respawn_height = -10.0
	_flip = 1.0 if randf() < 0.5 else -1.0
	_golf_noise.seed = randi()
	_golf_noise.frequency = 0.15
	for k in 3:
		_hole_seeds.append(randi())
	_build_colored_terrain(_golf_height, Vector2i(91, 91), Vector2.ZERO, _golf_color)
	_box(Vector3(500, 0.2, 500), Vector3(0, -0.15, 0), Color(0.3, 0.68, 0.28))
	_golf_fence()
	_boundary_walls(FENCE_HALF + 0.2)
	spawn = Vector3(0, 0.95, 31.0)

	_golf_entrance()
	_golf_paths()
	_build_hole(0, _fl(-22, -8), 0.0, float(randi_range(10, 14)))
	_build_hole(1, _fl(8, -26), 90.0 * _flip, float(randi_range(10, 14)))
	_build_hole(2, _fl(24, 4), 0.0, float(randi_range(10, 14)))
	_golf_pond(_fl(15, 3), 2.3, true)
	for p in [_fl(12.5, 0.0), _fl(17.5, 6.5), _fl(12.0, 7.0), _fl(28.5, 12.5)]:
		_palm(p)
	_build_clubhouse(_fl(-17, 23))
	_build_booth(_fl(7, 28))
	_windmill(self, Vector3(_fl(-28, 28).x, 0, 28), 0.55, true)
	_blocked.append(Rect2(_fl(-28, 28).x - 1.1, 26.9, 2.2, 2.2))
	var deck := _fl(-8, 29)
	_build_shower_rig(Vector3(deck.x, 0, deck.y), 0.0)
	_blocked.append(Rect2(deck.x - 1.2, deck.y - 1.2, 2.4, 2.4))
	_obstacles.append(Vector3(deck.x - 1.0, deck.y, 0.4))
	_golf_decor()
	_string_lights()

	var boiler := Vector2(14, 22)
	for attempt in 60:
		var p := Vector2(randf_range(-30, 30), randf_range(8, 30))
		if _clear_xz(p, 1.5) and p.distance_to(Vector2(spawn.x, spawn.z)) >= 9.0:
			boiler = p
			break
	item_spots["boiler"] = Vector3(boiler.x, 0.0, boiler.y)
	_obstacles.append(Vector3(boiler.x, boiler.y, 0.8))


func _golf_fence() -> void:
	var post := Color(0.98, 0.98, 0.96)
	var picket: Mesh = main._box(Vector3(0.12, 1.0, 0.03))
	var mat: Material = _color(post)
	var len := FENCE_HALF * 2.0 + 0.4
	for side in 4:
		var yaw := side * PI / 2.0
		var dir := Vector3(sin(yaw), 0, cos(yaw))  # outward direction of this side
		var along := Vector3(cos(yaw), 0, -sin(yaw))
		var centre := dir * FENCE_HALF
		_solid_body(_box_shape(Vector3(len, 1.2, 0.2)), centre + Vector3(0, 0.6, 0), Vector3(0, rad_to_deg(yaw), 0))
		for y in [0.3, 0.75]:
			_box(Vector3(len, 0.08, 0.06), centre + Vector3(0, y, 0), Color(0.75, 0.55, 0.35), false, Vector3(0, rad_to_deg(yaw), 0))
		var t := -len / 2.0 + 0.1
		while t < len / 2.0:
			_mm_add("picket", picket, mat, _xf(centre + along * t + Vector3(0, 0.5, 0), Vector3.ONE, yaw))
			t += 0.3


func _golf_entrance() -> void:
	for side in [-1.0, 1.0]:
		var x: float = side * 4.5
		_solid_body(CylinderShape3D.new(), Vector3(x, 2.1, 37.2))
		_cylinder(0.18, 4.2, Vector3(x, 2.1, 37.2), Color(0.9, 0.2, 0.25) if side < 0.0 else Color(0.2, 0.45, 0.95))
		_ball(0.4, Vector3(x, 4.4, 37.2), Color(1.0, 0.85, 0.2))
		_obstacles.append(Vector3(x, 37.2, 0.4))
	_box(Vector3(10.2, 1.6, 0.25), Vector3(0, 4.0, 37.2), Color(1.0, 0.82, 0.15))
	for face in 2:
		_text3d("MINI GOLF", Vector3(0, 4.0, 37.2 + (0.15 if face == 0 else -0.15)), 1.0, Color(0.9, 0.15, 0.2),
				Color(1, 1, 1), null, false, 0.0 if face == 0 else 180.0, 18)


func _path(a: Vector2, b: Vector2, w := 1.6) -> void:
	var rect: Rect2
	if absf(a.x - b.x) < 0.01:
		rect = Rect2(a.x - w / 2.0, minf(a.y, b.y) - w / 2.0, w, absf(a.y - b.y) + w)
	else:
		rect = Rect2(minf(a.x, b.x) - w / 2.0, a.y - w / 2.0, absf(a.x - b.x) + w, w)
	_walk_paths.append(rect)
	var c := rect.get_center()
	_box(Vector3(rect.size.x, 0.03, rect.size.y), Vector3(c.x, 0.02, c.y), PATH_COLOR)


func _golf_paths() -> void:
	_path(_fl(0, 35), _fl(0, -20))
	_path(_fl(0, 29), _fl(-6.6, 29))
	_path(_fl(0, 23), _fl(-14.9, 23))
	_path(_fl(0, 14), _fl(-22, 14))
	_path(_fl(-22, 14), _fl(-22, 0))
	_path(_fl(0, 14), _fl(24, 14))
	_path(_fl(24, 14), _fl(24, 12.2))
	_path(_fl(0, -20), _fl(16.6, -20))
	_path(_fl(16.6, -20), _fl(16.6, -26))
	_path(_fl(6, 28), _fl(0, 28))


# Local frame of a hole: x across the lane, z along it, the tee at +z and the cup at -z.
func _build_hole(index: int, center: Vector2, yaw: float, length: float) -> void:
	var root := Node3D.new()
	root.position = Vector3(center.x, 0, center.y)
	root.rotation_degrees.y = yaw
	add_child(root)
	var palettes: Array = [[Color(0.7, 0.22, 0.15), Color(0.98, 0.96, 0.92)], [Color(0.15, 0.4, 0.9), Color(0.98, 0.96, 0.92)],
			[Color(0.7, 0.22, 0.15), Color(0.15, 0.4, 0.9)]]
	var c1: Color = palettes[index][0]
	var c2: Color = palettes[index][1]
	var w := LANE_W
	_box(Vector3(w, 0.06, length), Vector3(0, 0.03, 0), TURF, true, Vector3.ZERO, root)
	_rail(root, Vector3(0.2, 0.25, length + 0.4), Vector3(-(w / 2.0 + 0.1), 0.125, 0), c1, c2)
	_rail(root, Vector3(0.2, 0.25, length + 0.4), Vector3(w / 2.0 + 0.1, 0.125, 0), c1, c2)
	_rail(root, Vector3(w, 0.25, 0.2), Vector3(0, 0.125, length / 2.0 + 0.1), c1, c2)
	_rail(root, Vector3(w, 0.25, 0.2), Vector3(0, 0.125, -length / 2.0 - 0.1), c1, c2)
	var lane_extent := Vector2(w + 0.4, length + 0.4)
	if absf(sin(deg_to_rad(yaw))) > 0.5:
		lane_extent = Vector2(lane_extent.y, lane_extent.x)
	_blocked.append(Rect2(center - lane_extent / 2.0, lane_extent))

	var tee_z := length / 2.0 - 1.0
	var cup_z := -length / 2.0 + 1.3
	_box(Vector3(1.2, 0.015, 0.9), Vector3(0, 0.0675, tee_z), Color(0.12, 0.12, 0.14), false, Vector3.ZERO, root)
	_box(Vector3(1.28, 0.01, 0.98), Vector3(0, 0.065, tee_z), Color(0.95, 0.95, 0.95), false, Vector3.ZERO, root)
	_cylinder(0.22, 0.016, Vector3(0, 0.068, cup_z), Color(0.97, 0.97, 0.97), false, Vector3.ZERO, root)
	_cylinder(0.17, 0.02, Vector3(0, 0.07, cup_z), Color(0.65, 0.68, 0.72), false, Vector3.ZERO, root)
	_cylinder(0.12, 0.024, Vector3(0, 0.072, cup_z), Color(0.05, 0.05, 0.06), false, Vector3.ZERO, root)
	_cylinder(0.012, 0.8, Vector3(0.5, 0.45, cup_z), Color(0.95, 0.95, 0.95), false, Vector3.ZERO, root)
	_box(Vector3(0.3, 0.17, 0.01), Vector3(0.65, 0.76, cup_z), Color(0.95, 0.1, 0.1), false, Vector3.ZERO, root)
	_cylinder(0.05, 1.2, Vector3(w / 2.0 + 0.8, 0.6, length / 2.0 - 0.3), Color(0.55, 0.38, 0.22), false, Vector3.ZERO, root)
	_text3d(str(index + 1), Vector3(w / 2.0 + 0.8, 1.45, length / 2.0 - 0.3), 0.5, Color(1, 1, 1), c1, root, true, 0.0, 40)
	_obstacles.append(Vector3(root.to_global(Vector3(w / 2.0 + 0.8, 0, length / 2.0 - 0.3)).x,
			root.to_global(Vector3(w / 2.0 + 0.8, 0, length / 2.0 - 0.3)).z, 0.3))

	match index:
		0:
			_hole_bridge(root)
			for side in [-1.0, 1.0]:
				_bumper_post(root, Vector3(side * 0.7, 0.06, 3.0))
				_bumper_post(root, Vector3(side * 0.55, 0.06, -3.0))
		1:
			_windmill(root, Vector3(0, 0.06, 0.4), 1.0, false)
		2:
			_hole_clown(root)
			var pyramid := [Vector3(2.4, 0.18, 1.6), Vector3(1.7, 0.18, 1.1), Vector3(1.0, 0.18, 0.6)]
			var steps: Array[Color] = [Color(0.85, 0.6, 0.95), Color(0.95, 0.6, 0.8), Color(1.0, 0.85, 0.4)]
			for k in 3:
				var sz: Vector3 = pyramid[k]
				_box(sz, Vector3(0, 0.06 + 0.09 + k * 0.18, 2.4), steps[k], true, Vector3.ZERO, root)

	var ball_pos := Vector3(0, 0.075 + 0.12, tee_z)
	var ball := StaticBody3D.new()
	ball.collision_layer = 2
	ball.collision_mask = 0
	var shape := SphereShape3D.new()
	shape.radius = 0.3
	var cs := CollisionShape3D.new()
	cs.shape = shape
	ball.add_child(cs)
	ball.position = ball_pos
	root.add_child(ball)
	_ball(0.12, Vector3.ZERO, Color(1, 1, 1), ball)
	_ball(0.125, Vector3(0.0, 0.0, 0.0), Color(1.0, 0.4, 0.2), ball).scale = Vector3(1.0, 0.12, 1.0)
	_clickable(ball, "Putt the ball (hole %d)" % (index + 1), _putt.bind(index))
	_holes.append({"ball": ball, "cup": root.to_global(Vector3(0, 0.075, cup_z)), "done": false})
	bottle_spots.append((_holes[index]["cup"] as Vector3) + Vector3(0, 0.11, 0))


func _rail(parent: Node3D, size: Vector3, pos: Vector3, c1: Color, c2: Color) -> void:
	var body := _solid_body(_box_shape(size), pos, Vector3.ZERO, parent)
	var along_z := size.z > size.x
	var length := size.z if along_z else size.x
	var n := maxi(int(round(length / 0.7)), 1)
	var seg := length / n
	for k in n:
		var offset := -length / 2.0 + seg * (k + 0.5)
		var seg_size := Vector3(size.x, size.y, seg) if along_z else Vector3(seg, size.y, size.z)
		_box(seg_size, Vector3(0, 0, offset) if along_z else Vector3(offset, 0, 0), c1 if k % 2 == 0 else c2, false,
				Vector3.ZERO, body)


func _bumper_post(parent: Node3D, pos: Vector3) -> void:
	_cylinder(0.15, 0.5, pos + Vector3(0, 0.25, 0), Color(0.9, 0.25, 0.3), true, Vector3.ZERO, parent)
	_cylinder(0.155, 0.1, pos + Vector3(0, 0.3, 0), Color(0.98, 0.98, 0.98), false, Vector3.ZERO, parent)
	_ball(0.15, pos + Vector3(0, 0.5, 0), Color(1.0, 0.85, 0.2), parent)


func _hole_bridge(root: Node3D) -> void:
	var wood := Color(0.62, 0.42, 0.24)
	var theta := asin(0.44 / 1.3)
	for side in [1.0, -1.0]:
		_box(Vector3(3.0, 0.1, 1.3), Vector3(0, 0.233, side * 1.21), wood, true, Vector3(rad_to_deg(theta) * side, 0, 0), root)
	_box(Vector3(3.0, 0.1, 1.2), Vector3(0, 0.45, 0), wood, true, Vector3.ZERO, root)
	for side in [-1.0, 1.0]:
		_box(Vector3(0.25, 0.39, 1.2), Vector3(side * 1.375, 0.255, 0), Color(0.75, 0.25, 0.2), true, Vector3.ZERO, root)
		_box(Vector3(0.06, 0.14, 1.2), Vector3(side * 1.45, 0.57, 0), Color(0.98, 0.96, 0.92), false, Vector3.ZERO, root)


func _hole_clown(root: Node3D) -> void:
	var z := -2.4
	var face := Color(0.98, 0.9, 0.8)
	for side in [-1.0, 1.0]:
		_box(Vector3(1.1, 0.8, 0.4), Vector3(side * 1.05, 0.46, z), face, true, Vector3.ZERO, root)
	_box(Vector3(3.2, 0.9, 0.4), Vector3(0, 1.31, z), face, true, Vector3.ZERO, root)
	_box(Vector3(1.3, 0.1, 0.1), Vector3(0, 0.91, z + 0.22), Color(0.9, 0.1, 0.15), false, Vector3.ZERO, root)
	for side in [-1.0, 1.0]:
		_box(Vector3(0.1, 0.7, 0.1), Vector3(side * 0.6, 0.46, z + 0.22), Color(0.9, 0.1, 0.15), false, Vector3.ZERO, root)
		_ball(0.17, Vector3(side * 0.7, 1.4, z + 0.2), Color(1, 1, 1), root)
		_ball(0.08, Vector3(side * 0.7, 1.4, z + 0.34), Color(0.1, 0.1, 0.15), root)
		_ball(0.2, Vector3(side * 1.0, 1.95, z), Color(1.0, 0.5, 0.15), root)
		_ball(0.2, Vector3(side * 0.55, 2.0, z), Color(0.25, 0.7, 1.0), root)
	_ball(0.17, Vector3(0, 1.17, z + 0.26), Color(0.95, 0.1, 0.1), root)
	_ball(0.2, Vector3(0, 2.05, z), Color(0.9, 0.3, 0.8), root)


# Hub at about 2.4 m on the front face; the four blades are plain decoration that turn on a pivot.
func _windmill(parent: Node3D, pos: Vector3, s: float, small: bool) -> void:
	var root := Node3D.new()
	root.position = pos
	parent.add_child(root)
	var white := Color(0.98, 0.97, 0.95)
	var red := Color(0.85, 0.15, 0.15)
	for side in [-1.0, 1.0]:
		_box(Vector3(1.1, 1.1, 1.5) * s, Vector3(side * 1.1 * s, 0.55 * s, 0), white, true, Vector3.ZERO, root)
	_box(Vector3(3.3, 1.2, 1.5) * s, Vector3(0, 1.7 * s, 0), white, true, Vector3.ZERO, root)
	_box(Vector3(2.4, 0.5, 1.2) * s, Vector3(0, 2.55 * s, 0), white.darkened(0.04), true, Vector3.ZERO, root)
	_box(Vector3(3.36, 0.1, 1.56) * s, Vector3(0, 1.12 * s, 0), red, false, Vector3.ZERO, root)
	_cone(1.35 * s, 0.9 * s, Vector3(0, 3.25 * s, 0), red, root)
	_cylinder(0.12 * s, 0.5 * s, Vector3(0, 2.4 * s, 0.85 * s), red, false, Vector3(90, 0, 0), root)
	var pivot := Node3D.new()
	pivot.position = Vector3(0, 2.4 * s, 1.1 * s)
	root.add_child(pivot)
	for k in 4:
		var arm := Node3D.new()
		arm.rotation_degrees.z = k * 90.0
		pivot.add_child(arm)
		_box(Vector3(0.1, 1.5, 0.06) * s, Vector3(0, 0.75 * s, 0), Color(0.6, 0.42, 0.25), false, Vector3.ZERO, arm)
		_box(Vector3(0.4, 1.0, 0.03) * s, Vector3(0.22 * s, 0.9 * s, 0.02 * s), red if k % 2 == 0 else white, false,
				Vector3.ZERO, arm)
	_ball(0.17 * s, Vector3(0, 0, 0.06 * s), Color(1.0, 0.85, 0.2), pivot)
	_blades.append(pivot)


func _build_clubhouse(center: Vector2) -> void:
	var yaw := 90.0 * _flip
	var root := Node3D.new()
	root.position = Vector3(center.x, 0, center.y)
	root.rotation_degrees.y = yaw
	add_child(root)
	var white := Color(0.98, 0.96, 0.92)
	_box(Vector3(8, 3, 5), Vector3(0, 1.5, 0), white, true, Vector3.ZERO, root)
	var slat_fb: Mesh = main._box(Vector3(0.5, 3.0, 0.05))
	var slat_side: Mesh = main._box(Vector3(0.05, 3.0, 0.5))
	var red: Material = _color(Color(0.9, 0.2, 0.25))
	var yaw_rad := deg_to_rad(yaw)
	for k in 8:
		var x := -3.75 + k * 1.0
		for z in [2.52, -2.52]:
			_mm_add("club_red", slat_fb, red, Transform3D(Basis(Vector3.UP, yaw_rad), root.position + root.basis * Vector3(x, 1.5, z)))
	for k in 5:
		var z := -2.0 + k * 1.0
		for x in [4.02, -4.02]:
			_mm_add("club_red", slat_side, red, Transform3D(Basis(Vector3.UP, yaw_rad), root.position + root.basis * Vector3(x, 1.5, z)))
	_box(Vector3(9.4, 0.2, 6.2), Vector3(0, 3.35, 0), Color(0.25, 0.55, 0.95), false, Vector3(0, 0, 9), root)
	_box(Vector3(9.5, 0.1, 0.3), Vector3(0, 3.6, 3.05), Color(0.95, 0.85, 0.2), false, Vector3(0, 0, 9), root)
	_box(Vector3(1.0, 2.0, 0.08), Vector3(0, 1.0, 2.52), Color(0.45, 0.28, 0.15), false, Vector3.ZERO, root)
	for x in [-2.4, 2.4]:
		_box(Vector3(1.4, 1.0, 0.08), Vector3(x, 1.8, 2.52), Color(0.7, 0.9, 1.0), false, Vector3.ZERO, root)
	for x in [-2.0, 2.0]:
		_cylinder(0.08, 1.0, Vector3(x, 4.0, 1.2), Color(0.55, 0.38, 0.22), false, Vector3.ZERO, root)
	_box(Vector3(5.6, 1.1, 0.15), Vector3(0, 4.7, 1.2), Color(1.0, 0.82, 0.15), false, Vector3.ZERO, root)
	for face in 2:
		_text3d("MINI GOLF", Vector3(0, 4.7, 1.2 + (0.1 if face == 0 else -0.1)), 0.8, Color(0.9, 0.15, 0.2), Color(1, 1, 1),
				root, false, 0.0 if face == 0 else 180.0, 14)
	var extent := Vector2(5, 8)
	_blocked.append(Rect2(center - extent / 2.0, extent))


func _build_booth(center: Vector2) -> void:
	var root := Node3D.new()
	root.position = Vector3(center.x, 0, center.y)
	root.rotation_degrees.y = -90.0 * _flip
	add_child(root)
	_box(Vector3(1.7, 2.2, 1.7), Vector3(0, 1.1, 0), Color(0.55, 0.9, 0.8), true, Vector3.ZERO, root)
	_box(Vector3(1.2, 0.8, 0.06), Vector3(0, 1.4, 0.86), Color(0.7, 0.9, 1.0), false, Vector3.ZERO, root)
	_box(Vector3(2.3, 0.08, 1.2), Vector3(0, 2.1, 1.1), Color(0.95, 0.3, 0.3), false, Vector3(18, 0, 0), root)
	_box(Vector3(2.3, 0.082, 0.3), Vector3(0, 2.07, 1.5), Color(0.98, 0.98, 0.98), false, Vector3(18, 0, 0), root)
	_box(Vector3(1.9, 0.12, 1.9), Vector3(0, 2.25, 0), Color(0.95, 0.3, 0.3), false, Vector3.ZERO, root)
	_text3d("TICKETS", Vector3(0, 1.95, 0.88), 0.22, Color(0.9, 0.15, 0.2), Color(1, 1, 1), root, false, 0.0, 6)
	_blocked.append(Rect2(center - Vector2(1.0, 1.0), Vector2(2.0, 2.0)))


func _golf_pond(center: Vector2, r: float, with_fin: bool) -> void:
	var stone := Color(0.6, 0.6, 0.64)
	_solid_body(CylinderShape3D.new(), Vector3(center.x, 0.15, center.y))
	var body := get_child(get_child_count() - 1) as StaticBody3D
	((body.get_child(0) as CollisionShape3D).shape as CylinderShape3D).radius = r + 0.3
	((body.get_child(0) as CollisionShape3D).shape as CylinderShape3D).height = 0.3
	_cylinder(r, 0.04, Vector3(center.x, 0.3, center.y), Color(0.2, 0.65, 0.95, 0.85))
	_cylinder(r + 0.1, 0.02, Vector3(center.x, 0.28, center.y), Color(0.55, 0.5, 0.4))
	for k in 12:
		var a := k * TAU / 12.0
		_box(Vector3(0.55, 0.4, 0.45), Vector3(center.x + cos(a) * (r + 0.1), 0.2, center.y + sin(a) * (r + 0.1)),
				stone.lightened(randf_range(-0.15, 0.15)), false, Vector3(0, -rad_to_deg(a), 0))
	_obstacles.append(Vector3(center.x, center.y, r + 0.6))
	if with_fin:
		_fin = Node3D.new()
		_fin.position = Vector3(center.x, 0.32, center.y)
		add_child(_fin)
		var fin := PrismMesh.new()
		fin.size = Vector3(0.5, 0.5, 0.06)
		var fin_node: Node3D = main._prop(fin, Vector3(r * 0.55, 0.22, 0), _color(Color(0.45, 0.5, 0.58)), false, Vector3(0, 90, 0), _fin)
		fin_node.name = "Fin"
		_box(Vector3(0.9, 0.02, 0.9), Vector3(r * 0.55, 0.0, 0), Color(0.9, 0.97, 1.0, 0.5), false, Vector3.ZERO, _fin)


func _palm(p: Vector2) -> void:
	var trunk: Array[Color] = [Color(0.95, 0.7, 0.75), Color(0.98, 0.85, 0.6), Color(0.75, 0.65, 0.95)]
	var leaves: Array[Color] = [Color(0.55, 0.95, 0.75), Color(0.5, 0.9, 0.95), Color(0.75, 0.95, 0.5)]
	var k := randi() % 3
	_cylinder(0.12, 3.0, Vector3(p.x, 1.5, p.y), trunk[k], true)
	var yaw := randf() * TAU
	for leaf in 7:
		var a := yaw + leaf * TAU / 7.0
		_box(Vector3(2.4, 0.05, 0.5), Vector3(p.x + cos(a) * 1.1, 3.0, p.y + sin(a) * 1.1), leaves[(k + leaf) % 3], false,
				Vector3(0, -rad_to_deg(a), -22))
	_ball(0.16, Vector3(p.x + 0.15, 2.85, p.y), Color(0.85, 0.5, 0.35))
	_obstacles.append(Vector3(p.x, p.y, 0.4))


func _giant_ball(p: Vector2, r: float, color: Color) -> void:
	var shape := SphereShape3D.new()
	shape.radius = r
	var body := _solid_body(shape, Vector3(p.x, r, p.y))
	_ball(r, Vector3.ZERO, color, body)
	_ball(r * 0.28, Vector3(r * 0.6, r * 0.6, r * 0.45), Color(1, 1, 1), body)
	_obstacles.append(Vector3(p.x, p.y, r))


func _giant_cone(p: Vector2, color: Color) -> void:
	var shape := CylinderShape3D.new()
	shape.radius = 0.4
	shape.height = 1.4
	var body := _solid_body(shape, Vector3(p.x, 0.7, p.y))
	_cone(0.5, 1.4, Vector3.ZERO, color, body, 0.05)
	_cylinder(0.3, 0.2, Vector3(0, 0.15, 0), Color(1, 1, 1), false, Vector3.ZERO, body)
	_box(Vector3(1.1, 0.08, 1.1), Vector3(0, -0.66, 0), Color(0.15, 0.15, 0.18), false, Vector3.ZERO, body)
	_obstacles.append(Vector3(p.x, p.y, 0.6))


func _duck(p: Vector2) -> void:
	var shape := SphereShape3D.new()
	shape.radius = 0.8
	var body := _solid_body(shape, Vector3(p.x, 0.8, p.y))
	body.rotation.y = randf() * TAU
	var yellow := Color(1.0, 0.85, 0.15)
	_ball(0.8, Vector3.ZERO, yellow, body)
	_ball(0.45, Vector3(0.5, 0.95, 0), yellow, body)
	_ball(0.3, Vector3(-0.75, 0.3, 0), yellow, body)
	_box(Vector3(0.4, 0.12, 0.34), Vector3(0.95, 0.9, 0), Color(1.0, 0.5, 0.1), false, Vector3.ZERO, body)
	for side in [-1.0, 1.0]:
		_ball(0.07, Vector3(0.78, 1.1, side * 0.2), Color(0.1, 0.1, 0.12), body)
	_obstacles.append(Vector3(p.x, p.y, 1.0))


func _flower_bed(p: Vector2, size: Vector2) -> void:
	_box(Vector3(size.x, 0.05, size.y), Vector3(p.x, 0.03, p.y), Color(0.4, 0.27, 0.18))
	var colors: Array[Color] = [Color(1.0, 0.3, 0.4), Color(1.0, 0.85, 0.2), Color(0.95, 0.5, 0.95), Color(1.0, 0.6, 0.2)]
	var mesh := _sphere(0.08)
	for k in int(size.x * size.y * 5.0):
		var c := randi() % colors.size()
		_mm_add("flower%d" % c, mesh, _color(colors[c]), _xf(Vector3(p.x + randf_range(-0.45, 0.45) * size.x,
				0.13, p.y + randf_range(-0.45, 0.45) * size.y)))
	_blocked.append(Rect2(p - size / 2.0, size))


func _golf_decor() -> void:
	var colors: Array[Color] = [Color(0.95, 0.25, 0.3), Color(1.0, 0.85, 0.2), Color(0.25, 0.5, 0.95), Color(0.95, 0.45, 0.85),
			Color(0.3, 0.8, 0.45), Color(1.0, 0.55, 0.15)]
	var balls: Array = [[-30, -30, 1.1], [-27.5, -26.5, 0.7], [-11, -20, 0.9], [31, -14, 1.1], [31, 22, 0.8], [-31, 8, 0.9],
			[33, -30, 0.8]]
	for i in balls.size():
		var b: Array = balls[i]
		_giant_ball(_fl(b[0], b[1]), b[2], colors[i % colors.size()])
	var cones: Array = [[-25, -14], [-24, -12], [-14, 6], [30, 14], [-4, -31], [-33, -20]]
	for i in cones.size():
		var cone_at: Array = cones[i]
		_giant_cone(_fl(cone_at[0], cone_at[1]), colors[(i + 2) % colors.size()])
	_duck(_fl(31, 28))
	for bed in [[-3.5, 33, 2.6, 1.0], [3.5, 33, 2.6, 1.0], [-17, 28.5, 5.0, 1.0], [-10, 19.5, 3.0, 1.0], [10, 22, 1.4, 3.0]]:
		var b: Array = bed
		_flower_bed(_fl(b[0], b[1]), Vector2(b[2], b[3]))


func _string_lights() -> void:
	var corners: Array[Vector2] = [Vector2(-36, -36), Vector2(0, -36), Vector2(36, -36), Vector2(36, 0), Vector2(36, 36),
			Vector2(0, 36), Vector2(-36, 36), Vector2(-36, 0)]
	var bulb := _sphere(0.07)
	var glow: Array[Material] = [_glow(Color(1.0, 0.3, 0.3)), _glow(Color(1.0, 0.9, 0.3)), _glow(Color(0.35, 0.6, 1.0)),
			_glow(Color(0.5, 1.0, 0.5))]
	for p in corners:
		_solid_body(CylinderShape3D.new(), Vector3(p.x, 1.7, p.y))
		var body := get_child(get_child_count() - 1) as StaticBody3D
		((body.get_child(0) as CollisionShape3D).shape as CylinderShape3D).radius = 0.08
		((body.get_child(0) as CollisionShape3D).shape as CylinderShape3D).height = 3.4
		_cylinder(0.07, 3.4, Vector3(p.x, 1.7, p.y), Color(0.55, 0.38, 0.22))
		_obstacles.append(Vector3(p.x, p.y, 0.2))
	for i in corners.size():
		var a := corners[i]
		var b := corners[(i + 1) % corners.size()]
		var count := int(a.distance_to(b) / 2.0)
		for k in range(1, count):
			var t := float(k) / count
			var p := a.lerp(b, t)
			_mm_add("bulb%d" % (k % 4), bulb, glow[k % 4], _xf(Vector3(p.x, 3.3 - 0.6 * sin(t * PI), p.y)))


func _putt(index: int) -> void:
	var hole := _holes[index]
	if hole["done"]:
		main.say("Hole %d is done. Nice putting!" % (index + 1))
		return
	var game: Control = (load("res://scripts/golf_minigame.gd") as GDScript).new()
	main.open_overlay(game)
	if main.puzzle != game:
		return
	game.call("setup", mini(index, 2), _hole_seeds[index])
	game.connect("completed", _hole_done.bind(index))


func _hole_done(index: int) -> void:
	main.close_overlay()
	var hole := _holes[index]
	if hole["done"]:
		return
	hole["done"] = true
	(hole["ball"] as StaticBody3D).set_meta("label", "Hole %d done" % (index + 1))
	_reveal(index, (hole["cup"] as Vector3) + Vector3(0, 0.11, 0))
	main.say("Hole %d: sunk! Something shiny pops out of the cup." % (index + 1))


func _golf_decoy() -> Vector3:
	for attempt in 30:
		var r := _walk_paths[randi() % _walk_paths.size()]
		var p := r.position + Vector2(randf_range(0.2, r.size.x - 0.2), randf_range(0.2, r.size.y - 0.2))
		if _clear_xz(p, 0.4) and absf(p.x) < 36.0 and absf(p.y) < 36.0:
			return Vector3(p.x, 0.035 + 0.11, p.y)
	return Vector3(0.0, 0.035 + 0.11, 20.0)


func _golf_extra() -> Vector3:
	for attempt in 60:
		var p := Vector2(randf_range(-35.0, 35.0), randf_range(-35.0, 35.0))
		if _clear_xz(p, 0.7):
			return Vector3(p.x, 0.11, p.y)
	return Vector3(0.0, 0.11, 20.0)


func _golf_nav() -> Dictionary:
	var pos: Array[Vector3] = []
	for xi in range(-32, 33, 8):
		for zi in range(-32, 33, 8):
			var p := Vector2(xi, zi)
			if _clear_xz(p, 0.8):
				pos.append(Vector3(p.x, 0, p.y))
	return _link_graph(pos, 12.0, 0.5, func(q: Vector2) -> bool: return absf(q.x) < 36.0 and absf(q.y) < 36.0)


# --- Lake ---

var _lk_r := 16.0
var _lk_p1 := 0.0
var _lk_p2 := 0.0
var _lk_noise := FastNoiseLite.new()
var _flat: Array[Vector4] = []  # x, z, inner and outer radius of flattened patches
var _boat: Node3D
var _dock_u := Vector2.RIGHT
var _dock_start := 0.0
var _dock_end := 0.0
var _catches := 0
var _fish_seeds: Array[int] = []
var _casts := 0


func _lake_r(theta: float) -> float:
	return _lk_r * (1.0 + 0.09 * sin(2.0 * theta + _lk_p1) + 0.06 * sin(3.0 * theta + _lk_p2))


func _lake_height(x: float, z: float) -> float:
	var inside := _lake_r(atan2(z, x)) - Vector2(x, z).length()
	if inside > 0.0:
		return -minf(0.9 * inside * inside, 4.0)
	var h := (_lk_noise.get_noise_2d(x, z) * 0.5 + 0.5) * 0.5 * smoothstep(3.0, 10.0, -inside)
	h += pow(clampf((maxf(absf(x), absf(z)) - 40.0) / 15.0, 0.0, 1.0), 2.0) * 8.0
	for f in _flat:
		h = lerpf(h, 0.0, 1.0 - smoothstep(f.z, f.w, Vector2(x - f.x, z - f.y).length()))
	return h


func _lake_color(_x: float, _z: float, h: float) -> Color:
	if h < -0.3:
		return Color(0.2, 0.4, 0.45)
	if h < 0.12:
		return Color(0.85, 0.78, 0.55)
	return Color(0.3, 0.55, 0.25).lerp(Color(0.2, 0.42, 0.2), clampf(h / 4.0, 0.0, 1.0))


func _dock_point(d: float, lat := 0.0) -> Vector2:
	return _dock_u * d + Vector2(-_dock_u.y, _dock_u.x) * lat


func _on_dock(p: Vector2) -> bool:
	var d := _dock_u.dot(p)
	return d < _dock_start and d > _dock_end and absf(Vector2(-_dock_u.y, _dock_u.x).dot(p)) < 0.95


func _wall_hit(p: Vector2) -> bool:
	var d := _dock_u.dot(p)
	var lat := absf(Vector2(-_dock_u.y, _dock_u.x).dot(p))
	return d < _dock_start and d > _dock_end - 0.3 and lat > 0.9 and lat < 1.3


func _build_lake() -> void:
	player_jump = 0.0
	respawn_height = -10.0
	_lk_r = randf_range(14.0, 18.0)
	_lk_p1 = randf() * TAU
	_lk_p2 = randf() * TAU
	_lk_noise.seed = randi()
	_lk_noise.frequency = 0.05
	for k in 6:
		_fish_seeds.append(randi())
	var theta_c := randf() * TAU
	var dir_c := Vector2(cos(theta_c), sin(theta_c))
	var cabin := dir_c * (_lake_r(theta_c) + 14.0)
	var toward := -dir_c
	var yaw := atan2(toward.x, toward.y)
	var right := Vector2(cos(yaw), -sin(yaw))
	var rig := cabin + right * 7.2
	var spawn_xz := rig + toward * 5.0
	_flat.append(Vector4(cabin.x, cabin.y, 6.5, 10.0))
	_flat.append(Vector4(rig.x, rig.y, 4.0, 7.5))
	var theta_d := theta_c + 1.0
	_dock_u = Vector2(cos(theta_d), sin(theta_d))
	var r_d := _lake_r(theta_d)
	_dock_start = r_d + 1.0
	_dock_end = r_d - randf_range(6.0, 8.0)
	var shore := _dock_point(r_d + 1.0)
	_flat.append(Vector4(shore.x, shore.y, 3.0, 5.0))

	_build_colored_terrain(_lake_height, Vector2i(111, 111), Vector2.ZERO, _lake_color)
	_boundary_walls(50.0)
	_box(Vector3(500, 0.2, 500), Vector3(0, -6.0, 0), Color(0.2, 0.4, 0.3))
	var water := _cylinder(_lk_r * 1.15 + 2.0, 0.02, Vector3(0, -0.35, 0), Color(0.15, 0.5, 0.8, 0.65))
	water.name = "Water"
	var wshape := CylinderShape3D.new()
	wshape.radius = _lk_r * 1.1
	wshape.height = 0.2
	var wbody := _solid_body(wshape, Vector3(0, -0.35, 0))
	wbody.collision_layer = 2
	wbody.collision_mask = 0
	_action_bodies.append(wbody)
	_build_shore_walls()
	_build_dock()

	_build_cabin(Vector3(cabin.x, 0, cabin.y), yaw)
	_obstacles.append(Vector3(cabin.x, cabin.y, 4.2))
	_build_shower_rig(Vector3(rig.x, 0, rig.y), 0.0)
	_blocked.append(Rect2(rig.x - 1.2, rig.y - 1.2, 2.4, 2.4))
	_obstacles.append(Vector3(rig.x - 1.0, rig.y, 0.4))
	spawn = Vector3(spawn_xz.x, _lake_height(spawn_xz.x, spawn_xz.y) + 0.95, spawn_xz.y)

	for d in [_dock_end + 1.0, (_dock_start + _dock_end) / 2.0, _dock_start - 1.5]:
		var p := _dock_point(d)
		bottle_spots.append(Vector3(p.x, 0.05 + 0.11, p.y))
	_build_trees(spawn_xz)
	var boiler := cabin + right * -9.0
	for attempt in 60:
		var a := randf() * TAU
		var c := Vector2(cos(a), sin(a)) * (_lake_r(a) + randf_range(6.0, 12.0))
		if _clear_xz(c, 1.5) and c.distance_to(spawn_xz) >= 8.0 and _lake_height(c.x, c.y) < 0.4:
			boiler = c
			break
	item_spots["boiler"] = Vector3(boiler.x, _lake_height(boiler.x, boiler.y), boiler.y)
	_obstacles.append(Vector3(boiler.x, boiler.y, 0.8))
	_set_fish_label("Fish here")


func _set_fish_label(text: String) -> void:
	for body in _action_bodies:
		_clickable(body, text, _start_fishing)


func _build_shore_walls() -> void:
	var count := 72
	for k in count:
		var a0 := k * TAU / count
		var a1 := (k + 1) * TAU / count
		var p0 := Vector2(cos(a0), sin(a0)) * (_lake_r(a0) - 0.45)
		var p1 := Vector2(cos(a1), sin(a1)) * (_lake_r(a1) - 0.45)
		var mid := (p0 + p1) / 2.0
		if _dock_u.dot(mid) > 0.0 and absf(Vector2(-_dock_u.y, _dock_u.x).dot(mid)) < 2.2:
			continue
		var d := p1 - p0
		var body := _solid_body(_box_shape(Vector3(d.length() + 0.3, 3.0, 0.5)), Vector3(mid.x, 1.0, mid.y),
				Vector3(0, rad_to_deg(atan2(-d.y, d.x)), 0))
		_action_bodies.append(body)


func _build_dock() -> void:
	var length := _dock_start - _dock_end
	var centre := _dock_point((_dock_start + _dock_end) / 2.0)
	var yaw := rad_to_deg(atan2(_dock_u.x, _dock_u.y))
	_box(Vector3(2.0, 0.1, length), Vector3(centre.x, 0.0, centre.y), Color(0.62, 0.45, 0.27), true, Vector3(0, yaw, 0))
	for k in int(length / 0.5):
		var p := _dock_point(_dock_start - 0.25 - k * 0.5)
		_box(Vector3(2.0, 0.004, 0.03), Vector3(p.x, 0.052, p.y), Color(0.35, 0.24, 0.14), false, Vector3(0, yaw, 0))
	for side in [-1.0, 1.0]:
		var wall_c := _dock_point((_dock_start + _dock_end) / 2.0, side * 1.1)
		_action_bodies.append(_solid_body(_box_shape(Vector3(0.2, 2.5, length)), Vector3(wall_c.x, 1.2, wall_c.y), Vector3(0, yaw, 0)))
		var d := _dock_start
		while d > _dock_end:
			var post := _dock_point(d, side * 1.05)
			_cylinder(0.09, 1.8, Vector3(post.x, -0.5, post.y), Color(0.45, 0.3, 0.18))
			d -= 2.0
	var end_c := _dock_point(_dock_end - 0.1)
	_action_bodies.append(_solid_body(_box_shape(Vector3(2.4, 2.5, 0.2)), Vector3(end_c.x, 1.2, end_c.y), Vector3(0, yaw, 0)))
	_boat = Node3D.new()
	var boat_p := _dock_point(_dock_end + 3.5, 2.4)
	_boat.position = Vector3(boat_p.x, -0.32, boat_p.y)
	_boat.rotation_degrees.y = yaw
	add_child(_boat)
	_box(Vector3(1.0, 0.08, 2.2), Vector3(0, 0.0, 0), Color(0.7, 0.5, 0.3), false, Vector3.ZERO, _boat)
	for side in [-1.0, 1.0]:
		_box(Vector3(0.06, 0.35, 2.2), Vector3(side * 0.5, 0.18, 0), Color(0.85, 0.3, 0.25), false, Vector3.ZERO, _boat)
	_box(Vector3(1.0, 0.35, 0.06), Vector3(0, 0.18, -1.1), Color(0.85, 0.3, 0.25), false, Vector3.ZERO, _boat)


func _build_cabin(pos: Vector3, yaw: float) -> void:
	var root := Node3D.new()
	root.position = pos
	root.rotation.y = yaw
	add_child(root)
	var log_color := Color(0.5, 0.33, 0.2)
	_box(Vector3(5.6, 2.4, 4.2), Vector3(0, 1.2, 0), log_color, true, Vector3.ZERO, root)
	for row in 8:
		var y := 0.15 + row * 0.3
		for z in [2.12, -2.12]:
			_cylinder(0.16, 5.6, Vector3(0, y, z), log_color.darkened(0.1 * (row % 2)), false, Vector3(0, 0, 90), root)
		for x in [2.82, -2.82]:
			_cylinder(0.16, 4.2, Vector3(x, y, 0), log_color.darkened(0.1 * (row % 2)), false, Vector3(90, 0, 0), root)
	for side in [-1.0, 1.0]:
		_box(Vector3(6.2, 0.18, 3.0), Vector3(0, 3.0, side * 1.15), Color(0.45, 0.2, 0.15), false, Vector3(side * 28.0, 0, 0), root)
	_box(Vector3(0.9, 1.7, 0.06), Vector3(0, 0.85, 2.16), Color(0.3, 0.18, 0.1), false, Vector3.ZERO, root)
	for x in [-1.6, 1.6]:
		_box(Vector3(0.8, 0.6, 0.06), Vector3(x, 1.4, 2.16), Color(1.0, 0.9, 0.5), false, Vector3.ZERO, root)
	_box(Vector3(0.6, 1.8, 0.6), Vector3(-1.8, 3.2, -1.0), Color(0.55, 0.55, 0.58), false, Vector3.ZERO, root)


func _build_trees(spawn_xz: Vector2) -> void:
	var placed: Array[Vector2] = []
	var attempts := 0
	while placed.size() < 40 and attempts < 300:
		attempts += 1
		var a := randf() * TAU
		var p := Vector2(cos(a), sin(a)) * (_lake_r(a) + randf_range(9.0, 36.0))
		if absf(p.x) > 46.0 or absf(p.y) > 46.0 or not _clear_xz(p, 2.5) or p.distance_to(spawn_xz) < 6.0:
			continue
		var close := false
		for q in placed:
			if q.distance_to(p) < 3.0:
				close = true
		if close:
			continue
		placed.append(p)
		var s := randf_range(0.8, 1.4)
		var y := _lake_height(p.x, p.y)
		_cylinder(0.22 * s, 1.6 * s, Vector3(p.x, y + 0.8 * s, p.y), Color(0.4, 0.27, 0.16), true)
		for k in 3:
			_cone((1.6 - k * 0.4) * s, 1.8 * s, Vector3(p.x, y + (1.9 + k * 1.1) * s, p.y), Color(0.12, 0.4, 0.22))
		_obstacles.append(Vector3(p.x, p.y, 0.5))
	for k in 10:
		var a := randf() * TAU
		var p := Vector2(cos(a), sin(a)) * (_lake_r(a) + randf_range(3.0, 20.0))
		if _clear_xz(p, 1.0):
			_ball(randf_range(0.3, 0.7), Vector3(p.x, _lake_height(p.x, p.y), p.y), Color(0.5, 0.5, 0.53))


func _start_fishing() -> void:
	if _catches >= 3:
		main.say("No more bottles in this lake.")
		return
	var game: Control = (load("res://scripts/fishing_minigame.gd") as GDScript).new()
	main.open_overlay(game)
	if main.puzzle != game:
		return
	game.call("setup", mini(_catches, 2), _fish_seeds[_casts % _fish_seeds.size()])
	_casts += 1
	game.connect("completed", _on_caught)
	game.connect("failed", _on_fish_lost)


func _on_fish_lost() -> void:
	main.close_overlay()
	main.say("The fish got away... cast again!")


func _on_caught() -> void:
	main.close_overlay()
	_catches += 1
	_reveal(_catches - 1, _catch_spot())
	if _catches >= 3:
		_set_fish_label("No more bottles in this lake")
	main.say("You reel in a bottle! (%d/3)" % _catches)


func _catch_spot() -> Vector3:
	var player: CharacterBody3D = main.player
	var p := Vector2(player.global_position.x, player.global_position.z)
	if _on_dock(p):
		var d := clampf(_dock_u.dot(p) - 1.0, _dock_end + 0.4, _dock_start)
		var q := _dock_point(d)
		return Vector3(q.x, 0.05 + 0.11, q.y)
	var fwd := player.global_transform.basis * Vector3(0, 0, -1)
	var dir := Vector2(fwd.x, fwd.z).normalized()
	for attempt in 2:
		var last := p
		var found := false
		for s in 100:
			var q := p + dir * s * 0.25
			if _lake_height(q.x, q.y) < -0.3:
				found = true
				break
			last = q
		if found:
			var at := last - dir * 1.0
			return Vector3(at.x, maxf(_lake_height(at.x, at.y), 0.0) + 0.11, at.y)
		dir = (-p).normalized()
	return Vector3(p.x, _lake_height(p.x, p.y) + 0.11, p.y)


func _lake_decoy() -> Vector3:
	if randf() < 0.5:
		var q := _dock_point(randf_range(_dock_end + 0.5, _dock_start - 0.5), randf_range(-0.6, 0.6))
		return Vector3(q.x, 0.05 + 0.11, q.y)
	return _lake_extra()


func _lake_extra() -> Vector3:
	for attempt in 60:
		var a := randf() * TAU
		var p := Vector2(cos(a), sin(a)) * (_lake_r(a) + randf_range(2.0, 16.0))
		if _clear_xz(p, 0.8) and absf(p.x) < 44.0 and absf(p.y) < 44.0 and not _wall_hit(p):
			return Vector3(p.x, _lake_height(p.x, p.y) + 0.11, p.y)
	return Vector3(_lake_r(0.0) + 3.0, 0.11, 0.0)


func _lake_nav() -> Dictionary:
	var pos: Array[Vector3] = []
	for k in 20:
		var a := k * TAU / 20.0
		var p := Vector2(cos(a), sin(a)) * (_lake_r(a) + 2.5)
		if _clear_xz(p, 1.0):
			pos.append(Vector3(p.x, _lake_height(p.x, p.y), p.y))
	for k in 12:
		var a := (k + 0.5) * TAU / 12.0
		var p := Vector2(cos(a), sin(a)) * (_lake_r(a) + 7.5)
		if _clear_xz(p, 1.0):
			pos.append(Vector3(p.x, _lake_height(p.x, p.y), p.y))
	var edge := _dock_point(_dock_start + 1.5)
	pos.append(Vector3(edge.x, _lake_height(edge.x, edge.y), edge.y))
	for d in [_dock_start - 1.0, (_dock_start + _dock_end) / 2.0, _dock_end + 1.0]:
		var q := _dock_point(d)
		pos.append(Vector3(q.x, 0.05, q.y))
	return _link_graph(pos, 10.0, 0.4, func(q: Vector2) -> bool:
			return (_lake_height(q.x, q.y) > -0.05 or _on_dock(q)) and not _wall_hit(q))
