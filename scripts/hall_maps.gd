extends "res://scripts/open_world.gd"

# Two big indoor halls, built from primitives: the warehouse (shelving, a ramp up to mezzanine A, a gap to
# mezzanine B and a high platform C; two hinged catwalks start swung away and are swung into place from
# control panels) and the lab (a mixing station: the three bottles only appear once the player has
# mixed them in the beaker minigame).

const WH_HX := 25.0
const WH_HZ := 18.0
const WH_H := 16.0
const LAB_HX := 22.0
const LAB_HZ := 15.0
const LAB_H := 8.0
const MEZZ_Y := 4.5
const HIGH_Y := 9.0
const NODE_STEP := 2.0
const INFLATE := 0.45
const RAMP_ANGLE := 25.0
const GLASS_COLORS: Array[Color] = [Color(0.9, 0.2, 0.25), Color(0.2, 0.5, 0.95), Color(0.95, 0.85, 0.2),
		Color(0.3, 0.85, 0.4), Color(0.75, 0.35, 0.9), Color(0.95, 0.55, 0.15)]

var _kind := ""
var _mats: Dictionary = {}
var _feet: Array[Rect2] = []  # ground-level solids (x, z)
var _no_items: Array[Rect2] = []  # loose pickups and scenery stay out of these
var _tops: Array[Vector3] = []  # resting spots on crates / benches, 0.11 above the surface
var _glows: Array[Dictionary] = []
var _spinners: Array[Dictionary] = []
var _time := 0.0
var _nav: Dictionary = {}
var _np: Array[Vector3] = []
var _nl: Array[int] = []
var _nfeet: Dictionary = {}
var _reach: Array[Vector3] = []  # ground waypoints the player can walk to

# warehouse
var _bridges: Array[Dictionary] = []
var _deck_a := Rect2(-25, -18, 14, 6)
var _deck_b := Rect2(5, -18, 20, 6)
var _deck_c := Rect2(18, 0, 7, 8)
var _feet_a: Array[Rect2] = []
var _feet_b: Array[Rect2] = []
var _feet_c: Array[Rect2] = []
var _a_tops: Array[Vector3] = []
var _ramp_rect := Rect2(-23.3, -12.0, 2.6, 9.7)

# lab
var _station_bodies: Array[Node] = []
var _slot_mats: Array[StandardMaterial3D] = []
var _prod_ids: Array[String] = ["", "", ""]
var _prod_seeds: Array[int] = []
var _made := 0
var _bench_strips: Array[Dictionary] = []


func build(kind: String) -> void:
	_kind = kind
	if kind == "warehouse":
		_build_warehouse()
	elif kind == "lab":
		_build_lab()
	else:
		super.build(kind)


func customize_env(env: Environment, sun: DirectionalLight3D) -> void:
	if _kind != "warehouse" and _kind != "lab":
		return
	env.background_mode = Environment.BG_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	if _kind == "warehouse":
		env.background_color = Color(0.1, 0.1, 0.11)
		env.ambient_light_color = Color(0.8, 0.82, 0.9)
		env.ambient_light_energy = 0.6
	else:
		env.background_color = Color(0.85, 0.9, 0.92)
		env.ambient_light_color = Color(0.92, 0.97, 1.0)
		env.ambient_light_energy = 0.95
	sun.visible = false


func bind_bottle(index: int, body: PhysicsBody3D, id: String) -> void:
	if _kind != "lab":
		return
	_prod_ids[index] = id
	body.visible = false
	body.collision_layer = 0
	if "active" in body:
		body.set("active", false)
	hidden_bottles[index] = body
	if index < _slot_mats.size() and main.BOTTLE_COLORS.has(id):
		_slot_mats[index].albedo_color = main.BOTTLE_COLORS[id]
		_slot_mats[index].emission = main.BOTTLE_COLORS[id]


func unlock_bottle(index: int, at := Vector3.INF) -> void:
	var body: PhysicsBody3D = hidden_bottles.get(index)
	super.unlock_bottle(index, at)
	if body != null and "active" in body:
		body.set("active", true)


func _process(delta: float) -> void:
	if _glows.is_empty() and _spinners.is_empty():
		return
	_time += delta
	for g in _glows:
		(g["mat"] as StandardMaterial3D).emission_energy_multiplier = float(g["base"]) \
				+ float(g["amp"]) * sin(_time * float(g["speed"]) + float(g["phase"]))
	for s in _spinners:
		(s["node"] as Node3D).rotate_y(delta * float(s["speed"]))


# --- Random spots (valid on every call) ---

func decoy_spot() -> Vector3:
	var r := randf()
	if _kind == "lab":
		return _bench_spot()
	if r < 0.35 and not _tops.is_empty():
		return _tops[randi() % _tops.size()]
	if r < 0.55 and not _a_tops.is_empty():
		return _a_tops[randi() % _a_tops.size()]
	return _floor_spot()


func extra_spot() -> Vector3:
	if _kind == "lab":
		return _bench_spot() if randf() < 0.35 else _floor_spot()
	if randf() < 0.2:
		for attempt in 12:
			var p := Vector2(randf_range(_deck_a.position.x + 0.8, _deck_a.end.x - 0.8),
					randf_range(_deck_a.position.y + 0.8, _deck_a.end.y - 0.8))
			if not _in_feet(p, _feet_a, 0.6) and not Rect2(-24.5, -13.0, 4.5, 1.1).has_point(p):
				return Vector3(p.x, MEZZ_Y + 0.11, p.y)
	return _floor_spot()


func _floor_spot() -> Vector3:
	if _reach.is_empty():
		return spawn + Vector3(0, -0.84, 0)
	var base := _reach[randi() % _reach.size()]
	for attempt in 6:
		var p := Vector2(base.x + randf_range(-0.4, 0.4), base.z + randf_range(-0.4, 0.4))
		if not _in_feet(p, _feet, 0.35) and not _in_feet(p, _no_items, 0.0):
			return Vector3(p.x, 0.11, p.y)
	return Vector3(base.x, 0.11, base.z)


func _bench_spot() -> Vector3:
	if _bench_strips.is_empty():
		return _floor_spot()
	var s: Dictionary = _bench_strips[randi() % _bench_strips.size()]
	var c: Vector3 = s["pos"]
	var half: float = s["half"]
	return Vector3(c.x + randf_range(-half, half), c.y, c.z)


# --- Shared building blocks ---

func _m(color: Color) -> StandardMaterial3D:
	if not _mats.has(color):
		_mats[color] = main._mat(color)
	return _mats[color]


func _glass(color: Color) -> StandardMaterial3D:
	var key := Color(color.r, color.g, color.b, 0.4)
	if not _mats.has(key):
		var m: StandardMaterial3D = main._mat(key)
		m.roughness = 0.1
		_mats[key] = m
	return _mats[key]


func _emit(color: Color, energy: float) -> StandardMaterial3D:
	var m: StandardMaterial3D = main._mat(color)
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = energy
	return m


func _pulse(color: Color, base: float, amp: float, speed: float) -> StandardMaterial3D:
	var m := _emit(color, base)
	_glows.append({"mat": m, "base": base, "amp": amp, "speed": speed, "phase": randf() * TAU})
	return m


func _tile_mat(base: Color, line: Color, cell: float, w: float, d: float) -> StandardMaterial3D:
	var img := Image.create(16, 16, false, Image.FORMAT_RGB8)
	img.fill(base)
	for i in 16:
		img.set_pixel(i, 0, line)
		img.set_pixel(0, i, line)
	var m: StandardMaterial3D = main._mat(Color.WHITE)
	m.albedo_texture = ImageTexture.create_from_image(img)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	m.uv1_scale = Vector3(w / cell, d / cell, 1.0)
	m.roughness = 0.75
	return m


func _mi(mesh: Mesh, pos: Vector3, mat: Material, parent: Node, rot: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation_degrees = rot
	mi.layers = main.mesh_layers
	(parent if parent else self).add_child(mi)
	return mi


func _vis(pos: Vector3, size: Vector3, mat: Material, parent: Node = null, rot := Vector3.ZERO) -> MeshInstance3D:
	return _mi(main._box(size), pos, mat, parent, rot)


func _vcyl(pos: Vector3, r: float, h: float, mat: Material, parent: Node = null, rot := Vector3.ZERO,
		top_r := -1.0) -> MeshInstance3D:
	var c: CylinderMesh = main._cyl(r, h)
	if top_r >= 0.0:
		c.top_radius = top_r
	return _mi(c, pos, mat, parent, rot)


func _vsph(pos: Vector3, r: float, mat: Material, parent: Node = null, squash := 1.0) -> MeshInstance3D:
	var s := _sphere(r)
	var mi := _mi(s, pos, mat, parent, Vector3.ZERO)
	mi.scale = Vector3(1, squash, 1)
	return mi


func _shape(body: StaticBody3D, pos: Vector3, size: Vector3) -> void:
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	cs.shape = box
	cs.position = pos
	body.add_child(cs)


func _add_foot(feet_to: Variant, pos: Vector3, size: Vector3) -> void:
	if feet_to != null:
		(feet_to as Array).append(Rect2(pos.x - size.x / 2.0, pos.z - size.z / 2.0, size.x, size.z))


func _solid(pos: Vector3, size: Vector3, mat: Material, parent: Node = null, rot := Vector3.ZERO,
		feet_to: Variant = null) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = pos
	body.rotation_degrees = rot
	(parent if parent else self).add_child(body)
	_shape(body, Vector3.ZERO, size)
	_mi(main._box(size), Vector3.ZERO, mat, body, Vector3.ZERO)
	_add_foot(feet_to, pos, size)
	return body


func _solid_cyl(pos: Vector3, r: float, h: float, mat: Material, parent: Node = null,
		feet_to: Variant = null) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = pos
	(parent if parent else self).add_child(body)
	var cs := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = r
	shape.height = h
	cs.shape = shape
	body.add_child(cs)
	_mi(main._cyl(r, h), Vector3.ZERO, mat, body, Vector3.ZERO)
	_add_foot(feet_to, pos, Vector3(r * 2.0, h, r * 2.0))
	return body


func _omni(pos: Vector3, range_m: float, energy: float, color := Color.WHITE) -> void:
	var l := OmniLight3D.new()
	l.position = pos
	l.omni_range = range_m
	l.light_energy = energy
	l.light_color = color
	add_child(l)


func _label3d(text: String, pos: Vector3, yaw: float, size: float, color: Color) -> void:
	var l := Label3D.new()
	l.text = text
	l.position = pos
	l.rotation_degrees.y = yaw
	l.pixel_size = size
	l.modulate = color
	l.outline_size = 4
	l.double_sided = false
	add_child(l)


func _in_feet(p: Vector2, feet: Array, margin: float) -> bool:
	for r in feet:
		if (r as Rect2).grow(margin).has_point(p):
			return true
	return false


func _seg_free(a: Vector2, b: Vector2, feet: Array) -> bool:
	var steps := int(a.distance_to(b) / 0.4) + 1
	for i in steps + 1:
		if _in_feet(a.lerp(b, float(i) / steps), feet, 0.3):
			return false
	return true


func _rect_clear(r: Rect2, margin: float) -> bool:
	var g := r.grow(margin)
	for f in _feet:
		if g.intersects(f):
			return false
	for f in _no_items:
		if g.intersects(f):
			return false
	return true


# Walls, floor and ceiling as solid slabs around a hall centred on the origin; the floor top is y = 0.
func _shell(hx: float, hz: float, h: float, floor_mat: Material, wall_mat: Material, ceil_mat: Material) -> void:
	_solid(Vector3(0, -0.25, 0), Vector3(hx * 2 + 1, 0.5, hz * 2 + 1), floor_mat)
	_solid(Vector3(0, h + 0.25, 0), Vector3(hx * 2 + 1, 0.5, hz * 2 + 1), ceil_mat)
	_solid(Vector3(0, h / 2.0, -hz - 0.25), Vector3(hx * 2 + 1, h, 0.5), wall_mat)
	_solid(Vector3(0, h / 2.0, hz + 0.25), Vector3(hx * 2 + 1, h, 0.5), wall_mat)
	_solid(Vector3(-hx - 0.25, h / 2.0, 0), Vector3(0.5, h, hz * 2), wall_mat)
	_solid(Vector3(hx + 0.25, h / 2.0, 0), Vector3(0.5, h, hz * 2), wall_mat)


# A band along the inside of all four walls.
func _wall_band(hx: float, hz: float, y: float, h: float, mat: Material) -> void:
	_vis(Vector3(0, y, -hz + 0.02), Vector3(hx * 2, h, 0.04), mat)
	_vis(Vector3(0, y, hz - 0.02), Vector3(hx * 2, h, 0.04), mat)
	_vis(Vector3(-hx + 0.02, y, 0), Vector3(0.04, h, hz * 2), mat)
	_vis(Vector3(hx - 0.02, y, 0), Vector3(0.04, h, hz * 2), mat)


# A tilted slab whose top surface runs from a to b.
func _slab(a: Vector3, b: Vector3, width: float, thick: float, mat: Material) -> StaticBody3D:
	var dir := b - a
	var length := dir.length()
	var bs := Basis.looking_at(dir.normalized(), Vector3.UP)
	var e := bs.get_euler()
	var mid := (a + b) / 2.0 - bs.y * thick / 2.0
	return _solid(mid, Vector3(width, thick, length), mat, null,
			Vector3(rad_to_deg(e.x), rad_to_deg(e.y), rad_to_deg(e.z)))


# Two solid rails and posts from a to b (a and b are on the walking surface).
func _railing(a: Vector3, b: Vector3, parent: Node = null) -> Node3D:
	var holder := Node3D.new()
	(parent if parent else self).add_child(holder)
	var dir := b - a
	var length := dir.length()
	if length < 0.05:
		return holder
	var bs := Basis.looking_at(dir.normalized(), Vector3.UP)
	var e := bs.get_euler()
	var rot := Vector3(rad_to_deg(e.x), rad_to_deg(e.y), rad_to_deg(e.z))
	var yellow := _m(Color(0.95, 0.78, 0.1))
	for h in [0.5, 1.0]:
		_solid((a + b) / 2.0 + Vector3(0, h, 0), Vector3(0.06, 0.07, length), yellow, holder, rot)
	var posts := maxi(int(length / 2.0), 1)
	for i in posts + 1:
		var p := a.lerp(b, float(i) / posts)
		_vcyl(p + Vector3(0, 0.55, 0), 0.03, 1.1, yellow, holder)
	return holder


# --- Warehouse ---

func _build_warehouse() -> void:
	indoor = true
	respawn_height = -5.0
	player_jump = 0.0
	player_speed = 1.0
	_shell(WH_HX, WH_HZ, WH_H, _tile_mat(Color(0.5, 0.5, 0.52), Color(0.38, 0.38, 0.4), 5.0, WH_HX * 2 + 1, WH_HZ * 2 + 1),
			_m(Color(0.6, 0.6, 0.58)), _m(Color(0.3, 0.31, 0.34)))
	spawn = Vector3(21.0, 0.95, 14.5)
	item_spots["boiler"] = Vector3(21.0, 0.0, -6.0)
	_no_items = [Rect2(17.5, 10.5, 7.0, 6.5), Rect2(-12.5, 6.5, 9.0, 8.5), Rect2(19.0, -8.0, 4.0, 4.0),
			Rect2(-24.0, -12.5, 9.0, 14.5), Rect2(-25, -18, 50, 6.5)]
	_wh_decor()
	_wh_decks()
	_wh_racks()
	_build_shower_rig(Vector3(-8, 0, 11), 0.0)
	_feet.append(Rect2(-9.15, 10.85, 0.3, 0.3))
	_wh_props()
	_wh_nav()


func _wh_decor() -> void:
	var yellow := _m(Color(0.95, 0.78, 0.1))
	var dark := _m(Color(0.2, 0.2, 0.22))
	var steel := _m(Color(0.55, 0.58, 0.62))
	_wall_band(WH_HX, WH_HZ, 0.6, 1.2, _m(Color(0.3, 0.32, 0.36)))
	_wall_band(WH_HX, WH_HZ, 1.3, 0.12, yellow)
	for z in [-5.25, -0.75, 3.75]:
		_vis(Vector3(0, 0.006, z), Vector3(48, 0.012, 0.12), yellow)
	for x in [-6.75, 6.75]:
		_vis(Vector3(x, 0.006, 0), Vector3(0.12, 0.012, 34), yellow)
	_vis(Vector3(21, 0.006, -6), Vector3(4.2, 0.012, 0.15), yellow)
	# roller doors on the east and west walls
	for spec in [[Vector3(WH_HX - 0.06, 2.6, -8.0), -90.0], [Vector3(WH_HX - 0.06, 2.6, 13.0), -90.0],
			[Vector3(-WH_HX + 0.06, 2.6, 8.0), 90.0], [Vector3(-WH_HX + 0.06, 2.6, 14.0), 90.0]]:
		var door := Node3D.new()
		door.position = spec[0]
		door.rotation_degrees.y = spec[1]
		add_child(door)
		_vis(Vector3(0, 0, -0.02), Vector3(5.4, 5.4, 0.04), yellow, door)
		_vis(Vector3(0, 0, 0.02), Vector3(5.0, 5.0, 0.04), _m(Color(0.7, 0.72, 0.74)), door)
		for i in 6:
			_vis(Vector3(0, -2.2 + i * 0.8, 0.05), Vector3(5.0, 0.05, 0.03), steel, door)
	# pipes and ducts
	var pipe_blue := _m(Color(0.2, 0.4, 0.8))
	var pipe_red := _m(Color(0.75, 0.2, 0.15))
	_vcyl(Vector3(0, 13.4, -16.8), 0.55, 49.0, pipe_blue, null, Vector3(0, 0, 90))
	_vcyl(Vector3(0, 12.2, -16.8), 0.3, 49.0, pipe_red, null, Vector3(0, 0, 90))
	_vcyl(Vector3(23.6, 12.8, 0), 0.5, 35.0, steel, null, Vector3(90, 0, 0))
	_vis(Vector3(0, 14.6, 4.0), Vector3(1.8, 1.2, 46.0), steel, null, Vector3(0, 90, 0))
	for x in [-20, -10, 0, 10, 20]:
		_vcyl(Vector3(x, 15.4, 4.0), 0.03, 1.8, dark)
		_vcyl(Vector3(x, 12.9, -16.8), 0.03, 6.0, dark)
	for z in [2.5, 16.6]:
		_vcyl(Vector3(-24.5, 8.0, z), 0.3, 16.0, pipe_blue)
	# hanging lamps and the lights they stand for
	var lamp := _emit(Color(1.0, 0.95, 0.8), 2.5)
	for x in [-18.75, -6.25, 6.25, 18.75]:
		for z in [-12.0, 0.0, 12.0]:
			_vcyl(Vector3(x, 14.2, z), 0.02, 3.6, dark)
			_vcyl(Vector3(x, 12.2, z), 0.9, 0.4, lamp, null, Vector3.ZERO, 0.35)
	for x in [-18.0, -6.0, 6.0, 18.0]:
		for z in [-9.0, 9.0]:
			_omni(Vector3(x, 11.5, z), 24.0, 2.1, Color(1.0, 0.96, 0.88))
	_omni(Vector3(-18, 8.0, -4), 10.0, 1.0, Color(1.0, 0.95, 0.85))
	_omni(Vector3(15, 7.0, -4), 10.0, 1.0, Color(1.0, 0.95, 0.85))
	_omni(Vector3(21, 12.0, 4), 10.0, 1.0, Color(1.0, 0.95, 0.85))
	_label3d("BAY 7", Vector3(0, 9.0, -17.9), 0.0, 0.05, Color(0.95, 0.78, 0.1))


# A platform on columns, with a yellow edge line.
func _deck(rect: Rect2, y: float, cols: Array) -> void:
	var steel := _m(Color(0.45, 0.47, 0.52))
	var c := rect.get_center()
	_solid(Vector3(c.x, y - 0.15, c.y), Vector3(rect.size.x, 0.3, rect.size.y), steel)
	_vis(Vector3(c.x, y + 0.004, c.y), Vector3(rect.size.x - 0.2, 0.01, rect.size.y - 0.2), _m(Color(0.38, 0.4, 0.44)))
	for sz in [-1.0, 1.0]:
		_vis(Vector3(c.x, y - 0.5, c.y + sz * (rect.size.y / 2.0 - 0.1)), Vector3(rect.size.x, 0.4, 0.12), _m(Color(0.25, 0.27, 0.3)))
	for sx in [-1.0, 1.0]:
		_vis(Vector3(c.x + sx * (rect.size.x / 2.0 - 0.1), y - 0.5, c.y), Vector3(0.12, 0.4, rect.size.y), _m(Color(0.25, 0.27, 0.3)))
	for col in cols:
		var v: Vector2 = col
		_solid_cyl(Vector3(v.x, (y - 0.3) / 2.0, v.y), 0.2, y - 0.3, _m(Color(0.3, 0.32, 0.36)), null, _feet)


func _gate(a: Vector3, b: Vector3) -> Node3D:
	return _railing(a, b)


func _wh_decks() -> void:
	var y := MEZZ_Y
	_deck(_deck_a, y, [Vector2(-24.6, -12.3), Vector2(-18.0, -12.3), Vector2(-11.3, -12.3), Vector2(-11.3, -17.7)])
	_deck(_deck_b, y, [Vector2(5.3, -12.3), Vector2(5.3, -17.7), Vector2(12.0, -12.3), Vector2(18.0, -12.3), Vector2(24.6, -12.3)])
	_deck(_deck_c, HIGH_Y, [Vector2(18.4, 0.4), Vector2(24.6, 0.4), Vector2(18.4, 7.6), Vector2(24.6, 7.6)])
	_feet.append(_ramp_rect)

	# ramp up to mezzanine A, with tread decoration and rails
	var tread := _m(Color(0.25, 0.26, 0.28))
	var run := MEZZ_Y / tan(deg_to_rad(RAMP_ANGLE))
	var foot := Vector3(-22.0, 0.0, -12.0 + run)
	var top := Vector3(-22.0, MEZZ_Y, -12.0)
	_slab(foot, top, 2.0, 0.2, _m(Color(0.5, 0.52, 0.56)))
	var rdir := (top - foot).normalized()
	var rbasis := Basis.looking_at(rdir, Vector3.UP)
	var re := rbasis.get_euler()
	var steps := int(foot.distance_to(top) / 0.45)
	for i in range(1, steps):
		var p := foot.lerp(top, float(i) / steps) + rbasis.y * 0.015
		_vis(p, Vector3(1.9, 0.03, 0.14), tread, null, Vector3(rad_to_deg(re.x), rad_to_deg(re.y), rad_to_deg(re.z)))
	for sx in [-23.05, -20.95]:
		_railing(Vector3(sx, 0.0, foot.z), Vector3(sx, MEZZ_Y, -12.0))
	for t in [0.3, 0.6]:
		var q := foot.lerp(top, t)
		_vcyl(Vector3(q.x, (q.y - 0.1) / 2.0, q.z), 0.07, q.y - 0.1, _m(Color(0.3, 0.32, 0.36)))

	# deck rails; the openings for the catwalks are shut by gates until a catwalk is in place
	_railing(Vector3(-25, y, -12), Vector3(-23.05, y, -12))
	_railing(Vector3(-20.95, y, -12), Vector3(-11, y, -12))
	_railing(Vector3(-11, y, -18), Vector3(-11, y, -16))
	_railing(Vector3(-11, y, -14), Vector3(-11, y, -12))
	_railing(Vector3(5, y, -18), Vector3(5, y, -16))
	_railing(Vector3(5, y, -14), Vector3(5, y, -12))
	_railing(Vector3(5, y, -12), Vector3(20, y, -12))
	_railing(Vector3(22, y, -12), Vector3(25, y, -12))
	_railing(Vector3(18, HIGH_Y, 0), Vector3(20, HIGH_Y, 0))
	_railing(Vector3(22, HIGH_Y, 0), Vector3(25, HIGH_Y, 0))
	_railing(Vector3(18, HIGH_Y, 0), Vector3(18, HIGH_Y, 8))
	_railing(Vector3(18, HIGH_Y, 8), Vector3(25, HIGH_Y, 8))

	var gates1: Array[Node3D] = [_gate(Vector3(-11, y, -16), Vector3(-11, y, -14)), _gate(Vector3(5, y, -16), Vector3(5, y, -14))]
	var gates2: Array[Node3D] = [_gate(Vector3(20, y, -12), Vector3(22, y, -12)), _gate(Vector3(20, HIGH_Y, 0), Vector3(22, HIGH_Y, 0))]
	var b1 := _make_bridge(Vector3(-11, y, -14), 0.0, 90.0, 16.0, 0.0, gates1)
	var rise := HIGH_Y - MEZZ_Y
	var b2 := _make_bridge(Vector3(20, y, -12), -90.0, 0.0, sqrt(144.0 + rise * rise), rad_to_deg(atan2(rise, 12.0)), gates2)
	_bridges = [b1, b2]
	b1["panel"] = _panel(Vector3(-19.0, 0.0, -3.8), -45.0, 0, "Catwalk control panel (A to B)")
	b2["panel"] = _panel(Vector3(18.5, y, -17.0), 0.0, 1, "Catwalk control panel (B to C)")

	# mezzanine A and B dressing: crates along the back wall
	for x in [-20.0, -16.0, -13.5]:
		if randf() < 0.75:
			var s := randf_range(0.8, 1.1)
			_crate(Vector3(x + randf_range(-0.5, 0.5), y, -17.4), s, _feet_a, _a_tops)
	var bx := randf_range(8.0, 14.0)
	_crate(Vector3(bx, y, -17.3), 0.9, _feet_b, null)
	bottle_spots.append(Vector3(bx, y + 0.9 + 0.11, -17.3))
	if randf() < 0.7:
		_crate(Vector3(randf_range(22.5, 24.0), y, -14.0), 1.0, _feet_b, null)
	var cx := randf_range(19.8, 23.5)
	var cz := randf_range(3.0, 6.6)
	_crate(Vector3(cx, HIGH_Y, cz), 0.8, _feet_c, null)
	bottle_spots.append(Vector3(cx, HIGH_Y + 0.8 + 0.11, cz))
	_omni(Vector3(-18, MEZZ_Y + 3.0, -15), 9.0, 0.9)
	_omni(Vector3(13, MEZZ_Y + 3.0, -15), 9.0, 0.9)


# Sits on the floor / deck at `base`; returns the top-centre spot.
func _crate(base: Vector3, s: float, feet_to: Variant, tops_to: Variant) -> Vector3:
	var wood := _m(Color(0.6, 0.45, 0.25))
	var slat := _m(Color(0.45, 0.32, 0.17))
	var body := _solid(base + Vector3(0, s / 2.0, 0), Vector3(s, s, s), wood, null, Vector3.ZERO, feet_to)
	_vis(Vector3(0, 0, 0), Vector3(s + 0.02, 0.12, s + 0.02), slat, body)
	_vis(Vector3(0, s / 2.0 - 0.06, 0), Vector3(s + 0.02, 0.12, s + 0.02), slat, body)
	_vis(Vector3(0, -s / 2.0 + 0.06, 0), Vector3(s + 0.02, 0.12, s + 0.02), slat, body)
	var top := base + Vector3(0, s + 0.11, 0)
	if tops_to != null:
		(tops_to as Array).append(top)
	return top


func _make_bridge(pivot_pos: Vector3, swung_yaw: float, joined_yaw: float, length: float, pitch: float,
		gates: Array[Node3D]) -> Dictionary:
	var pivot := Node3D.new()
	pivot.position = pivot_pos
	pivot.rotation_degrees.y = swung_yaw
	add_child(pivot)
	var tilt := Node3D.new()
	tilt.rotation_degrees.x = -pitch
	pivot.add_child(tilt)
	var width := 2.0
	var deck_mat := _m(Color(0.55, 0.57, 0.6))
	_solid(Vector3(width / 2.0, -0.1, length / 2.0), Vector3(width, 0.2, length), deck_mat, tilt)
	var yellow := _m(Color(0.95, 0.78, 0.1))
	for sx in [0.03, width - 0.03]:
		_railing(Vector3(sx, 0, 0), Vector3(sx, 0, length), tilt)
		_vis(Vector3(0.15 if sx < 1.0 else width - 0.15, -0.3, length / 2.0), Vector3(0.1, 0.35, length), _m(Color(0.25, 0.27, 0.3)), tilt)
	var stripes := int(length / 1.5)
	for i in stripes:
		_vis(Vector3(width / 2.0, 0.006, 0.75 + i * 1.5), Vector3(width - 0.3, 0.012, 0.25), yellow, tilt)
	return {"pivot": pivot, "swung": swung_yaw, "joined": joined_yaw, "gates": gates, "used": false}


func _panel(pos: Vector3, yaw: float, index: int, label: String) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = pos
	body.rotation_degrees.y = yaw
	add_child(body)
	_shape(body, Vector3(0, 0.75, 0), Vector3(0.95, 1.5, 0.5))
	var grey := _m(Color(0.35, 0.37, 0.4))
	_vis(Vector3(0, 0.45, 0), Vector3(0.5, 0.9, 0.4), grey, body)
	_vis(Vector3(0, 1.15, 0), Vector3(0.95, 0.7, 0.45), _m(Color(0.28, 0.3, 0.33)), body)
	var screen := _pulse(Color(0.2, 0.95, 0.4), 1.4, 0.5, 3.0)
	_vis(Vector3(0, 1.28, 0.23), Vector3(0.75, 0.3, 0.02), screen, body)
	var colors := [Color(0.9, 0.15, 0.15), Color(0.95, 0.8, 0.1), Color(0.2, 0.8, 0.3)]
	for i in 3:
		_vcyl(Vector3(-0.25 + i * 0.25, 1.0, 0.24), 0.055, 0.04, _emit(colors[i], 1.0), body, Vector3(90, 0, 0))
	_vis(Vector3(0, 1.58, 0), Vector3(1.0, 0.06, 0.5), _m(Color(0.95, 0.78, 0.1)), body)
	var l := OmniLight3D.new()
	l.position = Vector3(0, 1.4, 0.7)
	l.omni_range = 3.5
	l.light_energy = 0.7
	l.light_color = Color(0.5, 1.0, 0.6)
	body.add_child(l)
	body.set_meta("kind", "map_action")
	body.set_meta("label", label)
	body.set_meta("action", _use_bridge.bind(index))
	body.set_meta("screen", screen)
	return body


func _use_bridge(index: int) -> void:
	var b: Dictionary = _bridges[index]
	var panel: StaticBody3D = b["panel"]
	if b["used"]:
		main.say("The catwalk is already in place.")
		return
	b["used"] = true
	panel.set_meta("label", "Catwalk already in place")
	(panel.get_meta("screen") as StandardMaterial3D).albedo_color = Color(1.0, 0.7, 0.1)
	(panel.get_meta("screen") as StandardMaterial3D).emission = Color(1.0, 0.7, 0.1)
	main.say("Motors whine as the catwalk swings into place...")
	var tw := create_tween()
	tw.tween_property(b["pivot"], "rotation_degrees:y", float(b["joined"]), 2.0) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.finished.connect(_bridge_done.bind(index))


func _bridge_done(index: int) -> void:
	for g in _bridges[index]["gates"]:
		if is_instance_valid(g):
			(g as Node).queue_free()
	main.say("The catwalk clicks into place. The way across is open!")


func _rack(x: float, z: float, w: float, h: float, turned := false) -> void:
	var root := StaticBody3D.new()
	root.position = Vector3(x, 0, z)
	if turned:
		root.rotation_degrees.y = 90.0
	add_child(root)
	_shape(root, Vector3(0, h / 2.0, 0), Vector3(w, h, 1.0))
	if turned:
		_feet.append(Rect2(x - 0.5, z - w / 2.0, 1.0, w))
	else:
		_feet.append(Rect2(x - w / 2.0, z - 0.5, w, 1.0))
	var blue := _m(Color(0.15, 0.3, 0.7))
	var orange := _m(Color(0.95, 0.5, 0.1))
	var board := _m(Color(0.55, 0.55, 0.58))
	for sx in [-1.0, 1.0]:
		_vis(Vector3(sx * (w / 2.0 - 0.04), h / 2.0, 0), Vector3(0.08, h, 0.96), blue, root)
	var cartons := [_m(Color(0.7, 0.55, 0.35)), _m(Color(0.62, 0.48, 0.3)), _m(Color(0.78, 0.66, 0.45)), _m(Color(0.85, 0.85, 0.8))]
	var y := 0.3
	while y < h - 0.4:
		_vis(Vector3(0, y, 0), Vector3(w - 0.1, 0.06, 0.95), board, root)
		_vis(Vector3(0, y + 0.1, 0.5), Vector3(w - 0.1, 0.12, 0.04), orange, root)
		if randf() < 0.7:
			var bw := randf_range(0.5, 1.1)
			var bh := randf_range(0.35, 0.8)
			_vis(Vector3(randf_range(-w / 2.0 + 0.7, w / 2.0 - 0.7), y + 0.03 + bh / 2.0, randf_range(-0.1, 0.1)),
					Vector3(bw, bh, randf_range(0.5, 0.8)), cartons[randi() % cartons.size()], root)
		y += 1.25


func _wh_racks() -> void:
	var centers := [-13.5, -10.5, -7.5, -2.0, 1.0, 4.0, 9.5, 12.5, 15.5]
	for z in [-7.5, -3.0, 1.5]:
		for x in centers:
			if randf() < 0.1:
				continue
			_rack(x, z, 3.0, randf_range(3.0, 3.9))
	for x in range(-22, 17, 3):
		if randf() < 0.85:
			_rack(float(x) + 0.5, 17.4, 3.0, randf_range(4.5, 8.0))
	for z in [4.5, 7.5, 10.5, 13.5]:
		if randf() < 0.8:
			_rack(-24.4, z, 3.0, randf_range(4.0, 7.0), true)


func _pallet(pos: Vector3, rot_y := 0.0) -> void:
	var wood := _m(Color(0.7, 0.55, 0.32))
	var body := _solid(pos + Vector3(0, 0.075, 0), Vector3(1.2, 0.15, 1.0), wood, null, Vector3(0, rot_y, 0), _feet)
	_vis(Vector3(0, 0, 0), Vector3(1.22, 0.04, 0.2), _m(Color(0.5, 0.38, 0.2)), body)


func _wh_props() -> void:
	# the ground bottle sits on a crate stack in one of a few yards
	var yards := [Vector2(3.0, 9.5), Vector2(10.0, 10.0), Vector2(-17.0, 8.0)]
	var yard: Vector2 = yards[randi() % yards.size()]
	_pallet(Vector3(yard.x, 0, yard.y))
	var top := _crate(Vector3(yard.x, 0.15, yard.y), 1.2, null, null)
	_feet.append(Rect2(yard.x - 0.7, yard.y - 0.6, 1.4, 1.2))
	bottle_spots.insert(0, top)
	_crate(Vector3(yard.x + 1.4, 0, yard.y + 0.2), 1.0, _feet, null)
	_crate(Vector3(yard.x + 1.4, 1.0, yard.y + 0.2), 0.8, null, null)
	_no_items.append(Rect2(yard.x - 1.0, yard.y - 1.0, 3.4, 2.4))
	_station_forklift(Vector3(-19.0, 0.0, 12.0), 20.0)
	var tries := 0
	var placed := 0
	while placed < 22 and tries < 120:
		tries += 1
		var p := Vector2(randf_range(-23.0, 23.0), randf_range(-17.0, 15.5))
		var big := randf() < 0.45
		var size := Vector2(1.3, 1.3) if big else Vector2(1.0, 1.0)
		var r := Rect2(p - size / 2.0, size)
		if not _rect_clear(r, 1.4):
			continue
		placed += 1
		if big:
			_pallet(Vector3(p.x, 0, p.y), randf_range(-10, 10))
			var s := randf_range(0.8, 1.1)
			_crate(Vector3(p.x, 0.15, p.y), s, null, null)
			if randf() < 0.5:
				_crate(Vector3(p.x, 0.15 + s, p.y), s * 0.8, null, null)
		else:
			var s := randf_range(0.7, 1.4)
			var t := _crate(Vector3(p.x, 0, p.y), s, _feet, _tops if s < 1.45 else null)
			if randf() < 0.5:
				_tops.erase(t)
				_crate(Vector3(p.x, s, p.y), s * 0.75, null, null)
	_no_items.append(Rect2(-24.9, 3.0, 2.0, 13.0))


func _station_forklift(pos: Vector3, yaw: float) -> void:
	var yellow := _m(Color(0.95, 0.75, 0.1))
	var root := _solid(pos + Vector3(0, 0.6, 0), Vector3(1.1, 0.8, 2.0), yellow, null, Vector3(0, yaw, 0))
	_vis(Vector3(0, 1.0, 0.3), Vector3(0.9, 0.08, 0.9), _m(Color(0.1, 0.1, 0.1)), root)
	for sx in [-0.5, 0.5]:
		_vis(Vector3(sx, 1.0, 0.05), Vector3(0.06, 0.9, 0.06), _m(Color(0.2, 0.2, 0.2)), root)
		_vis(Vector3(sx, 0.5, -1.15), Vector3(0.08, 2.4, 0.1), _m(Color(0.25, 0.25, 0.28)), root)
		_vis(Vector3(sx, -0.45, -1.8), Vector3(0.12, 0.06, 1.3), _m(Color(0.25, 0.25, 0.28)), root)
	_vis(Vector3(0, 1.45, 0.1), Vector3(1.0, 0.05, 1.1), _m(Color(0.2, 0.2, 0.2)), root)
	_feet.append(Rect2(pos.x - 1.6, pos.z - 1.6, 3.2, 3.2))


func _wh_nav() -> void:
	_np.clear()
	_nl.clear()
	var step := NODE_STEP
	_nav_grid(Rect2(-24.0, -17.0, 48.0, 34.0), 0.02, 0, _feet, step)
	# ramp, mezzanine A, catwalk 1, mezzanine B, catwalk 2, platform C
	var run := MEZZ_Y / tan(deg_to_rad(RAMP_ANGLE))
	var t := 0.8
	while t < run:
		_np.append(Vector3(-22.0, t * tan(deg_to_rad(RAMP_ANGLE)) + 0.02, -12.0 + run - t))
		_nl.append(1)
		t += 1.8
	_np.append(Vector3(-22.0, MEZZ_Y + 0.02, -12.0))
	_nl.append(1)
	_nav_grid(Rect2(-24.4, -17.4, 12.8, 4.8), MEZZ_Y + 0.02, 2, _feet_a, step)
	for x in range(-11, 6, 2):
		_np.append(Vector3(x, MEZZ_Y + 0.02, -15.0))
		_nl.append(3)
	_nav_grid(Rect2(5.5, -17.4, 19.0, 4.8), MEZZ_Y + 0.02, 4, _feet_b, step)
	var rise := HIGH_Y - MEZZ_Y
	for tt in [1.0, 3.0, 5.0, 7.0, 9.0, 11.0]:
		_np.append(Vector3(21.0, MEZZ_Y + tt * rise / 12.0 + 0.02, -12.0 + tt))
		_nl.append(5)
	_nav_grid(Rect2(18.6, 0.6, 5.8, 6.8), HIGH_Y + 0.02, 6, _feet_c, step)
	_nav_finish([Vector2i(0, 1), Vector2i(1, 2), Vector2i(2, 3), Vector2i(3, 4), Vector2i(4, 5), Vector2i(5, 6)])
	_nav_reach(spawn)


# --- Waypoint graph ---

func _nav_grid(rect: Rect2, y: float, layer: int, feet: Array, step: float) -> void:
	_nfeet[layer] = feet
	var x := rect.position.x
	while x <= rect.end.x + 0.001:
		var z := rect.position.y
		while z <= rect.end.y + 0.001:
			if not _in_feet(Vector2(x, z), feet, INFLATE):
				_np.append(Vector3(x, y, z))
				_nl.append(layer)
			z += step
		x += step


func _nav_finish(joins: Array) -> void:
	var n := _np.size()
	var links: Array = []
	var doors: Array = []
	for i in n:
		links.append([])
		doors.append(null)
	var limit := NODE_STEP * 1.6 + 0.01
	for i in n:
		var a := _np[i]
		for j in range(i + 1, n):
			var b := _np[j]
			if absf(a.x - b.x) > limit or absf(a.z - b.z) > limit or absf(a.y - b.y) > 1.3:
				continue
			if Vector2(a.x - b.x, a.z - b.z).length() > limit:
				continue
			if _nl[i] == _nl[j]:
				if not _seg_free(Vector2(a.x, a.z), Vector2(b.x, b.z), _nfeet.get(_nl[i], [])):
					continue
			elif not (joins.has(Vector2i(_nl[i], _nl[j])) or joins.has(Vector2i(_nl[j], _nl[i]))):
				continue
			elif minf(_nl[i], _nl[j]) == 0.0 and absf(a.x - b.x) > 0.5:
				continue
			(links[i] as Array).append(j)
			(links[j] as Array).append(i)
	_nav = {"pos": _np.duplicate(), "links": links, "doors": doors}


# Walkable ground waypoints reachable from `from`, kept for loose pickups.
func _nav_reach(from: Vector3) -> void:
	_reach.clear()
	var start := -1
	var best := INF
	for i in _np.size():
		var d := Vector2(_np[i].x - from.x, _np[i].z - from.z).length()
		if _nl[i] == 0 and d < best:
			best = d
			start = i
	if start < 0:
		return
	var links: Array = _nav["links"]
	var seen := {start: true}
	var open: Array[int] = [start]
	while not open.is_empty():
		var cur: int = open.pop_back()
		for nb in links[cur]:
			if not seen.has(nb):
				seen[nb] = true
				open.append(nb)
	for i in seen:
		if _nl[i] == 0 and not _in_feet(Vector2(_np[i].x, _np[i].z), _no_items, 0.0):
			_reach.append(_np[i])


func nav_graph() -> Dictionary:
	if _nav.is_empty():
		return super.nav_graph()
	return _nav


# --- Lab ---

func _build_lab() -> void:
	indoor = true
	respawn_height = -5.0
	player_jump = 0.0
	player_speed = 1.0
	_prod_seeds = [randi(), randi(), randi()]
	var white := _m(Color(0.95, 0.97, 0.98))
	_shell(LAB_HX, LAB_HZ, LAB_H, _tile_mat(Color(0.8, 0.93, 0.95), Color(0.3, 0.7, 0.72), 0.5, LAB_HX * 2 + 1, LAB_HZ * 2 + 1),
			white, _m(Color(0.93, 0.95, 0.96)))
	spawn = Vector3(-19.0, 0.95, 0.0)
	item_spots["boiler"] = Vector3(18.0, 0.0, -9.5)
	_no_items = [Rect2(-21.5, -4.0, 5.5, 8.0), Rect2(12.5, 5.5, 8.0, 8.0), Rect2(16.0, -12.0, 4.0, 5.0)]
	_wall_band(LAB_HX, LAB_HZ, 0.6, 1.2, _m(Color(0.2, 0.62, 0.66)))
	_wall_band(LAB_HX, LAB_HZ, 1.26, 0.06, _m(Color(0.95, 0.95, 0.95)))
	_lab_ceiling()
	_lab_floor_marks()
	_lab_station()
	_lab_benches()
	_lab_hoods()
	_lab_shelves()
	_lab_tanks()
	_lab_decon()
	_lab_entrance()
	_feet.append(Rect2(14.85, 8.85, 0.3, 0.3))
	_lab_nav()


func _lab_ceiling() -> void:
	var panel := _emit(Color(1.0, 1.0, 1.0), 1.6)
	var grey := _m(Color(0.7, 0.75, 0.78))
	for x in range(-18, 19, 6):
		for z in [-9.0, 0.0, 9.0]:
			_vis(Vector3(x, LAB_H - 0.03, z), Vector3(2.4, 0.06, 0.8), panel)
	for x in [-14.0, 0.0, 14.0]:
		for z in [-7.0, 7.0]:
			_omni(Vector3(x, 6.6, z), 16.0, 1.5, Color(0.95, 1.0, 1.0))
	_vcyl(Vector3(0, 7.4, -12.0), 0.15, 43.0, _m(Color(0.3, 0.6, 0.9)), null, Vector3(0, 0, 90))
	_vcyl(Vector3(0, 7.0, -12.0), 0.1, 43.0, _m(Color(0.8, 0.3, 0.25)), null, Vector3(0, 0, 90))
	_vcyl(Vector3(0, 7.4, 12.0), 0.15, 43.0, _m(Color(0.7, 0.72, 0.75)), null, Vector3(0, 0, 90))
	_vis(Vector3(-8.0, 7.2, 0.0), Vector3(0.6, 0.5, 26.0), _m(Color(0.75, 0.78, 0.8)))
	var fan := Node3D.new()
	fan.position = Vector3(-8.0, 6.85, 0.0)
	add_child(fan)
	for i in 2:
		_vis(Vector3.ZERO, Vector3(1.6, 0.03, 0.2), _m(Color(0.4, 0.42, 0.45)), fan, Vector3(0, i * 90.0, 0))
	_spinners.append({"node": fan, "speed": 3.0})


func _lab_floor_marks() -> void:
	var teal := _m(Color(0.1, 0.6, 0.65))
	var yellow := _m(Color(0.95, 0.78, 0.1))
	_vis(Vector3(-9.0, 0.006, 0.0), Vector3(18.0, 0.012, 0.18), teal)
	for z in [-3.0, 3.0]:
		_vis(Vector3(-0.6, 0.006, z), Vector3(0.18, 0.012, 3.0), yellow)
	_vis(Vector3(2.0, 0.006, -3.0), Vector3(5.8, 0.012, 0.18), yellow)
	_vis(Vector3(2.0, 0.006, 3.0), Vector3(5.8, 0.012, 0.18), yellow)
	_vis(Vector3(4.7, 0.006, 0.0), Vector3(0.18, 0.012, 6.0), yellow)
	_vis(Vector3(-17.0, 0.006, 0.0), Vector3(0.12, 0.012, 9.0), yellow)


func _lab_station() -> void:
	var cab := _m(Color(0.25, 0.55, 0.6))
	var steel := _m(Color(0.75, 0.78, 0.82))
	var c := Vector3(2.0, 0, 0.0)
	var cabinet := _solid(Vector3(c.x, 0.45, c.z), Vector3(5.2, 0.9, 1.8), cab, null, Vector3.ZERO, _feet)
	var slab := _solid(Vector3(c.x, 0.95, c.z), Vector3(5.4, 0.1, 2.0), _m(Color(0.92, 0.94, 0.95)))
	_station_bodies = [cabinet, slab]
	# three reagent bottles, pipes and the beaker rig
	var reagent := [Color(0.9, 0.18, 0.2), Color(0.2, 0.42, 0.95), Color(0.98, 0.84, 0.18)]
	for i in 3:
		_vcyl(Vector3(-0.4 + i * 0.4, 1.23, -0.55), 0.13, 0.45, _glass(reagent[i]))
		_vcyl(Vector3(-0.4 + i * 0.4, 1.5, -0.55), 0.04, 0.12, _m(Color(0.9, 0.9, 0.9)))
		_vcyl(Vector3(-0.4 + i * 0.4, 1.9, -0.55), 0.015, 0.8, steel)
	_vcyl(Vector3(0.0, 2.3, -0.55), 0.03, 1.2, steel, null, Vector3(0, 0, 90))
	var beaker := StaticBody3D.new()
	beaker.position = Vector3(1.4, 1.6, -0.2)
	add_child(beaker)
	var cs := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = 0.55
	shape.height = 1.2
	cs.shape = shape
	beaker.add_child(cs)
	_vcyl(Vector3.ZERO, 0.55, 1.2, _glass(Color(0.8, 0.95, 1.0)), beaker)
	_vcyl(Vector3(0, -0.15, 0), 0.47, 0.8, _pulse(Color(0.3, 1.0, 0.7), 1.3, 0.9, 2.2), beaker)
	_station_bodies.append(beaker)
	for x in [0.8, 2.0]:
		_vcyl(Vector3(x, 1.95, -0.85), 0.03, 1.9, steel)
	_vis(Vector3(1.4, 2.85, -0.85), Vector3(1.4, 0.06, 0.06), steel)
	_vis(Vector3(1.4, 2.85, -0.5), Vector3(0.06, 0.06, 0.7), steel)
	_vis(Vector3(1.4, 2.72, -0.2), Vector3(0.28, 0.25, 0.28), _m(Color(0.2, 0.25, 0.3)))
	_vcyl(Vector3(1.4, 1.9, -0.2), 0.02, 1.5, steel)
	var paddle := Node3D.new()
	paddle.position = Vector3(1.4, 1.25, -0.2)
	add_child(paddle)
	_vis(Vector3.ZERO, Vector3(0.6, 0.03, 0.09), steel, paddle)
	_spinners.append({"node": paddle, "speed": 4.0})
	# output tray with a coloured ring per product slot
	_vis(Vector3(3.4, 1.03, 0.3), Vector3(2.2, 0.06, 0.7), _m(Color(0.7, 0.72, 0.75)))
	for i in 3:
		var ring_mat := _emit(Color(0.9, 0.9, 0.9), 0.8)
		_slot_mats.append(ring_mat)
		_vcyl(Vector3(2.8 + i * 0.6, 1.065, 0.3), 0.14, 0.012, ring_mat)
		bottle_spots.append(Vector3(2.8 + i * 0.6, 1.17, 0.3))
	_vis(Vector3(3.4, 1.4, 0.95), Vector3(2.2, 0.35, 0.04), _emit(Color(0.2, 0.9, 0.8), 1.2))
	_label3d("OUTPUT", Vector3(3.4, 1.4, 0.98), 0.0, 0.006, Color(0.02, 0.2, 0.2))
	_label3d("MIXING STATION", Vector3(2.0, 3.3, 0.0), 0.0, 0.012, Color(0.2, 0.9, 0.8))
	_label3d("MIXING STATION", Vector3(2.0, 3.3, 0.0), 180.0, 0.012, Color(0.2, 0.9, 0.8))
	_vcyl(Vector3(2.0, 5.75, 0.0), 0.02, 4.5, steel)
	_omni(Vector3(2.0, 2.2, 0.8), 7.0, 1.2, Color(0.6, 1.0, 0.9))
	for body in _station_bodies:
		body.set_meta("kind", "map_action")
		body.set_meta("label", _station_label())
		body.set_meta("action", _use_station)


func _station_label() -> String:
	if _made >= 3:
		return "Mixing station (all products ready)"
	return "Mixing station (product %d/3)" % (_made + 1)


func _use_station() -> void:
	if _made >= 3:
		main.say("All three products are ready. Grab them from the tray!")
		return
	var game: Control = (load("res://scripts/beaker_minigame.gd") as GDScript).new()
	main.open_overlay(game)
	if not game.is_inside_tree():
		return
	var k := _made
	var color: Color = main.BOTTLE_COLORS.get(_prod_ids[k], Color.WHITE)
	game.call("setup", color, mini(k, 2), _prod_seeds[k])
	game.connect("completed", _product_done.bind(k))


func _product_done(k: int) -> void:
	if k != _made:
		return
	_made += 1
	main.close_overlay()
	unlock_bottle(k)
	for body in _station_bodies:
		body.set_meta("label", _station_label())
	main.say("Product %d/3 ready!" % _made)


func _bench(x: float, z: float, length: float, with_items := true) -> void:
	var base := _m(Color(0.25, 0.55, 0.6))
	_solid(Vector3(x, 0.45, z), Vector3(length, 0.9, 1.0), base, null, Vector3.ZERO, _feet)
	_vis(Vector3(x, 0.93, z), Vector3(length + 0.1, 0.06, 1.1), _m(Color(0.93, 0.95, 0.96)))
	_bench_strips.append({"pos": Vector3(x, 0.96 + 0.11, z + 0.25), "half": length / 2.0 - 0.35})
	if with_items:
		_bench_items(x, z, length)


func _bench_items(x: float, z: float, length: float) -> void:
	var count := int(length / 0.8)
	var y := 0.96
	for i in count:
		var ix := x - length / 2.0 + 0.4 + i * 0.8 + randf_range(-0.1, 0.1)
		var iz := z - 0.25 + randf_range(-0.12, 0.05)
		var kind := randi() % 6
		var col: Color = GLASS_COLORS[randi() % GLASS_COLORS.size()]
		match kind:
			0:
				_vcyl(Vector3(ix, y + 0.15, iz), 0.12, 0.3, _glass(col), null, Vector3.ZERO, 0.03)
				_vcyl(Vector3(ix, y + 0.08, iz), 0.1, 0.16, _emit(col, 0.5), null, Vector3.ZERO, 0.055)
			1:
				_vsph(Vector3(ix, y + 0.17, iz), 0.15, _glass(col))
				_vcyl(Vector3(ix, y + 0.38, iz), 0.035, 0.2, _glass(col))
			2:
				_vis(Vector3(ix, y + 0.03, iz), Vector3(0.5, 0.06, 0.18), _m(Color(0.9, 0.9, 0.9)))
				for v in 4:
					_vcyl(Vector3(ix - 0.18 + v * 0.12, y + 0.14, iz), 0.025, 0.16, _glass(GLASS_COLORS[randi() % GLASS_COLORS.size()]))
			3:
				_vis(Vector3(ix, y + 0.22, iz), Vector3(0.45, 0.3, 0.08), _pulse(Color(0.3, 0.9, 1.0), 1.0, 0.4, 1.5 + randf()))
				_vis(Vector3(ix, y + 0.04, iz), Vector3(0.4, 0.08, 0.25), _m(Color(0.2, 0.22, 0.25)))
			4:
				_vcyl(Vector3(ix, y + 0.1, iz), 0.08, 0.2, _m(Color(0.2, 0.22, 0.25)))
				_vcyl(Vector3(ix, y + 0.3, iz), 0.04, 0.3, _m(Color(0.75, 0.78, 0.8)), null, Vector3(30, 0, 0))
			5:
				_vcyl(Vector3(ix, y + 0.12, iz), 0.1, 0.24, _glass(col))
				_vcyl(Vector3(ix, y + 0.07, iz), 0.085, 0.12, _emit(col, 0.4))


func _lab_benches() -> void:
	for z in [-6.5, 6.5]:
		var x := -13.0
		while x <= 11.0:
			var r := Rect2(x - 1.2, z - 0.5, 2.4, 1.0)
			var centrifuge: bool = z < 0.0 and absf(x + 9.6) < 0.1
			if centrifuge or (randf() < 0.88 and not _in_feet(r.get_center(), _no_items, 1.6)):
				_bench(x, z, 2.4, not centrifuge)
			x += 3.4
	# the centrifuge gets its own bench
	var drum := Node3D.new()
	drum.position = Vector3(-9.6, 0.96, -6.6)
	add_child(drum)
	_vcyl(Vector3(0, 0.12, 0), 0.38, 0.24, _m(Color(0.85, 0.87, 0.9)), drum)
	var rotor := Node3D.new()
	rotor.position = Vector3(0, 0.3, 0)
	drum.add_child(rotor)
	for i in 6:
		_vcyl(Vector3(0, 0, 0), 0.03, 0.34, _glass(GLASS_COLORS[i]), rotor, Vector3(0, i * 60.0, 90))
	_vcyl(Vector3(0, 0.08, 0), 0.06, 0.12, _m(Color(0.3, 0.3, 0.35)), rotor)
	_spinners.append({"node": rotor, "speed": 6.0})
	# wall benches along the east end
	_bench(10.0, -13.9, 3.0)
	_bench(-3.0, -13.9, 3.0)


func _lab_hoods() -> void:
	var white := _m(Color(0.9, 0.93, 0.95))
	var teal := _m(Color(0.2, 0.62, 0.66))
	for x in [-18.0, -14.5, -11.0, 7.0, 14.0]:
		_solid(Vector3(x, 0.45, -14.5), Vector3(2.2, 0.9, 1.0), teal, null, Vector3.ZERO, _feet)
		_solid(Vector3(x, 1.75 + 0.5, -14.7), Vector3(2.2, 1.7, 0.6), white, null, Vector3.ZERO, null)
		_vis(Vector3(x, 1.85, -14.15), Vector3(2.0, 1.2, 0.04), _glass(Color(0.6, 0.9, 1.0)))
		_vis(Vector3(x, 1.2, -14.1), Vector3(2.2, 0.08, 0.2), white)
		_vcyl(Vector3(x, 5.5, -14.7), 0.25, 3.8, _m(Color(0.7, 0.72, 0.75)))
		_vis(Vector3(x, 2.65, -14.15), Vector3(0.3, 0.1, 0.02), _emit(Color(0.3, 1.0, 0.5), 1.2))


func _lab_shelves() -> void:
	var white := _m(Color(0.9, 0.92, 0.94))
	var glass_cols := GLASS_COLORS
	for x in [-19.0, -15.0, -11.0, -7.0, -3.0, 1.0, 5.0, 9.0]:
		var z := 14.6
		_solid(Vector3(x, 1.1, z), Vector3(2.4, 2.2, 0.6), _m(Color(0.88, 0.9, 0.92)), null, Vector3.ZERO, _feet)
		for lv in 4:
			var y := 0.45 + lv * 0.5
			_vis(Vector3(x, y, z - 0.31), Vector3(2.3, 0.04, 0.04), _m(Color(0.3, 0.65, 0.7)))
			for i in 3:
				var fx: float = x - 0.8 + i * 0.8 + randf_range(-0.15, 0.15)
				var col: Color = glass_cols[randi() % glass_cols.size()]
				if randf() < 0.5:
					_vcyl(Vector3(fx, y + 0.17, z - 0.33), 0.12, 0.3, _glass(col), null, Vector3.ZERO, 0.03)
				else:
					_vsph(Vector3(fx, y + 0.12, z - 0.33), 0.11, _glass(col))
		_vis(Vector3(x, 2.25, z - 0.31), Vector3(2.4, 0.06, 0.06), white)
	# a tall display wall of vials at the entrance end
	for z in [-9.5, 9.5]:
		_solid(Vector3(-21.4, 1.1, z), Vector3(0.6, 2.2, 2.4), white, null, Vector3.ZERO, _feet)
		for lv in 4:
			for i in 4:
				_vcyl(Vector3(-21.05, 0.4 + lv * 0.5, z - 0.9 + i * 0.6), 0.06, 0.25,
						_glass(glass_cols[(lv + i) % glass_cols.size()]))


func _lab_tanks() -> void:
	var steel := _m(Color(0.72, 0.76, 0.8))
	var band := _m(Color(0.2, 0.62, 0.66))
	for z in [-5.0, -1.0, 3.0]:
		var x := 19.6
		_solid_cyl(Vector3(x, 2.4, z), 1.4, 4.8, steel, null, _feet)
		_vsph(Vector3(x, 4.8, z), 1.4, steel, null, 0.35)
		_vcyl(Vector3(x, 1.2, z), 1.42, 0.2, band)
		_vcyl(Vector3(x, 3.4, z), 1.42, 0.2, band)
		_vcyl(Vector3(x - 1.45, 2.4, z), 0.07, 2.6, _pulse(Color(0.2, 1.0, 0.6), 1.2, 0.7, 1.0 + randf()))
		_vcyl(Vector3(x, 6.0, z), 0.3, 2.4, steel)
	_vcyl(Vector3(21.3, 3.0, -1.0), 0.22, 11.0, _m(Color(0.8, 0.3, 0.25)), null, Vector3(90, 0, 0))
	_vcyl(Vector3(21.3, 6.2, 0.0), 0.35, 8.0, _m(Color(0.3, 0.6, 0.9)), null, Vector3(90, 0, 0))


func _lab_decon() -> void:
	var c := Vector3(16.0, 0.0, 9.0)
	_build_shower_rig(c, 0.0)
	var yellow := _m(Color(0.95, 0.78, 0.1))
	var black := _m(Color(0.12, 0.12, 0.12))
	for i in 12:
		var m := yellow if i % 2 == 0 else black
		_vis(Vector3(c.x - 3.3 + i * 0.6, 0.006, c.z - 3.2), Vector3(0.6, 0.012, 0.3), m)
		_vis(Vector3(c.x - 3.3 + i * 0.6, 0.006, c.z + 3.2), Vector3(0.6, 0.012, 0.3), m)
	for i in 10:
		var m := black if i % 2 == 0 else yellow
		_vis(Vector3(c.x - 3.3, 0.006, c.z - 2.7 + i * 0.6), Vector3(0.3, 0.012, 0.6), m)
		_vis(Vector3(c.x + 3.3, 0.006, c.z + 2.7 - i * 0.6), Vector3(0.3, 0.012, 0.6), m)
	_label3d("DECONTAMINATION", Vector3(c.x, 2.9, 14.9), 180.0, 0.01, Color(0.95, 0.78, 0.1))
	_vis(Vector3(c.x, 2.9, 14.93), Vector3(3.2, 0.5, 0.04), _m(Color(0.1, 0.12, 0.14)))
	# eyewash fountain
	_vcyl(Vector3(c.x + 3.7, 0.5, c.z - 2.0), 0.05, 1.0, _m(Color(0.3, 0.8, 0.4)))
	_vcyl(Vector3(c.x + 3.7, 1.05, c.z - 2.0), 0.25, 0.1, _m(Color(0.3, 0.8, 0.4)))
	_feet.append(Rect2(c.x + 3.55, c.z - 2.15, 0.3, 0.3))
	_omni(Vector3(c.x, 3.0, c.z), 8.0, 0.8, Color(0.7, 0.9, 1.0))


func _lab_entrance() -> void:
	var frame := _m(Color(0.7, 0.72, 0.75))
	_vis(Vector3(-LAB_HX + 0.04, 1.4, 0.0), Vector3(0.06, 2.8, 3.2), frame)
	for sz in [-0.8, 0.8]:
		_vis(Vector3(-LAB_HX + 0.08, 1.4, sz), Vector3(0.04, 2.6, 1.4), _glass(Color(0.6, 0.9, 1.0)))
	_vis(Vector3(-LAB_HX + 0.08, 3.1, 0.0), Vector3(0.05, 0.5, 3.2), _emit(Color(0.2, 0.9, 0.5), 1.0))
	_label3d("EXIT", Vector3(-LAB_HX + 0.12, 3.1, 0.0), 90.0, 0.012, Color(0.02, 0.2, 0.1))
	_vis(Vector3(-20.5, 0.01, 0.0), Vector3(2.0, 0.02, 3.0), _m(Color(0.15, 0.4, 0.45)))
	_label3d("CHEMICAL LAB", Vector3(-LAB_HX + 0.12, 5.2, 0.0), 90.0, 0.03, Color(0.15, 0.6, 0.65))


func _lab_nav() -> void:
	_np.clear()
	_nl.clear()
	_nav_grid(Rect2(-21.0, -14.0, 42.0, 28.0), 0.02, 0, _feet, NODE_STEP)
	_nav_finish([])
	_nav_reach(spawn)
