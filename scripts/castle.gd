extends RefCounted

# The castle's own look: dark stone bricks, red carpets, columns joined by arches, glowing braziers and
# a throne on a dais. The builders draw into the house node `h` (untyped: it calls the house script's
# helpers); the house script plans the rooms and builds their shells.

const STONE := Color(0.36, 0.35, 0.38)
const DARK_STONE := Color(0.2, 0.19, 0.21)
const RED := Color(0.5, 0.04, 0.07)
const GOLD := Color(0.85, 0.65, 0.18)
const IRON := Color(0.12, 0.12, 0.14)
const WOOD := Color(0.22, 0.14, 0.09)


static func wall_material() -> StandardMaterial3D:
	var img := Image.create(64, 64, false, Image.FORMAT_RGB8)
	for y in 64:
		var row := y >> 4
		var shift := 16 if (row & 1) == 1 else 0
		for x in 64:
			var bx := (x + shift) & 31
			var by := y & 15
			var id := (((x + shift) >> 5) * 5 + row * 3) % 4
			if bx < 1 or by < 1:
				img.set_pixel(x, y, Color(0.08, 0.08, 0.09))
			else:
				img.set_pixel(x, y, STONE.darkened(0.07 * id))
	var m := StandardMaterial3D.new()
	m.albedo_texture = ImageTexture.create_from_image(img)
	m.uv1_triplanar = true
	m.uv1_scale = Vector3.ONE  # one tile per metre of wall
	m.roughness = 0.95
	return m


static func floor_material(size: Vector2) -> StandardMaterial3D:
	var img := Image.create(2, 2, false, Image.FORMAT_RGB8)
	img.set_pixel(0, 0, Color(0.22, 0.21, 0.23))
	img.set_pixel(1, 1, Color(0.22, 0.21, 0.23))
	img.set_pixel(1, 0, Color(0.13, 0.12, 0.14))
	img.set_pixel(0, 1, Color(0.13, 0.12, 0.14))
	var m := StandardMaterial3D.new()
	m.albedo_texture = ImageTexture.create_from_image(img)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	m.uv1_scale = Vector3(size.x / 1.8, size.y / 1.8, 1)
	m.roughness = 0.8
	return m


# Stone pilasters and a heavy lintel around a doorway or archway. `c` is a house connection.
static func frame(h, c: Dictionary) -> void:
	var side: int = c["side"]
	var lo: float = c["lo"]
	var hi: float = c["hi"]
	var boundary: float = c["c"]
	var y0: float = c["y0"]
	var top: float = h.door_h
	var mat: Material = h.main._mat(STONE.lightened(0.08))
	var mid := (lo + hi) / 2.0
	var width := hi - lo
	var horizontal := side < 2
	var trim: float = h.FRAME_TRIM
	for edge in [lo - 0.1 + trim, hi + 0.1 - trim]:
		var size := Vector3(0.2, top, 0.24) if horizontal else Vector3(0.24, top, 0.2)
		var pos := Vector3(edge, y0 + top / 2.0, boundary) if horizontal else Vector3(boundary, y0 + top / 2.0, edge)
		h._p(h.main._box(size), pos, mat, false)
	var beam := Vector3(width + 0.4, 0.3, 0.24) if horizontal else Vector3(0.24, 0.3, width + 0.4)
	var beam_pos := Vector3(mid, y0 + top + 0.15 - trim, boundary) if horizontal else Vector3(boundary, y0 + top + 0.15 - trim, mid)
	h._p(h.main._box(beam), beam_pos, mat, false)


static func furnish(h, r) -> void:
	match r.type:
		"throne_room":
			_throne_room(h, r)
		"great_hall":
			_great_hall(h, r)
		"hallway":
			_gallery(h, r)
		"bedroom":
			_bedroom(h, r)
		"kitchen":
			_kitchen(h, r)
		"closet":
			_storeroom(h, r)
		"courtyard":
			_courtyard(h, r)
		"treasure":
			_treasure(h, r)
		"tower":
			h._furnish_tower(r)
		"tower_top":
			h._furnish_tower_top(r)
	if r.type != "courtyard":
		_decorate(h, r)


static func grass_material(size: Vector2) -> StandardMaterial3D:
	var img := Image.create(8, 8, false, Image.FORMAT_RGB8)
	for y in 8:
		for x in 8:
			img.set_pixel(x, y, Color(0.1, 0.32, 0.13).lerp(Color(0.2, 0.5, 0.2), randf()))
	var m := StandardMaterial3D.new()
	m.albedo_texture = ImageTexture.create_from_image(img)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	m.uv1_scale = Vector3(size.x / 1.2, size.y / 1.2, 1)
	m.roughness = 1.0
	return m


# --- Decoration shared by every castle room ---

static func _decorate(h, r) -> void:
	var area: float = r.rect.size.x * r.rect.size.y
	var inner: Rect2 = r.interior()
	for i in clampi(int(area / 40.0) + 1, 1, 6):
		_torch(h, r)
	for i in clampi(int(area / 70.0), 0, 3):
		_statue(h, r, STONE)
	for i in clampi(int(area / 55.0), 0, 3):
		_shield(h, r)
	if area > 45.0 and r.type != "treasure":
		_weapon_rack(h, r)
	if r.y1 - r.y0 >= 3.5 and area > 60.0:
		var c := inner.get_center()
		var along_x := inner.size.x >= inner.size.y
		var long_len := inner.size.x if along_x else inner.size.y
		var count := 1 if long_len < 12.0 else (2 if long_len < 20.0 else 3)
		for i in count:
			var t := (i - (count - 1) / 2.0) * long_len / count
			_chandelier(h, r, c + (Vector2(t, 0) if along_x else Vector2(0, t)))


static func _torch(h, r) -> void:
	var m: Node3D = h._wall(r, 0.3, 0.12, 0.5)
	if m == null:
		return
	var y := minf(r.y1 - r.y0 - 1.2, 2.2)
	h._b(m, Vector3(0.08, 0.5, 0.08), Vector3(0, y, 0.08), IRON, false)
	h._b(m, Vector3(0.2, 0.06, 0.2), Vector3(0, y + 0.27, 0.12), IRON, false)
	h._p(h._sphere(0.1), Vector3(0, y + 0.4, 0.12), h._glow_material(Color(1.0, 0.5, 0.1)), false, Vector3.ZERO, m)
	var light := OmniLight3D.new()
	light.position = Vector3(0, y + 0.5, 0.45)
	light.light_color = Color(1.0, 0.55, 0.25)
	light.omni_range = 6.0
	light.light_energy = 0.8
	light.light_cull_mask = 1
	m.add_child(light)


static func _chandelier(h, r, p: Vector2) -> void:
	var iron: Material = h.main._mat(IRON)
	var drop := minf(1.8, (r.y1 - r.y0) * 0.3)
	var y: float = r.y1 - drop
	h._p(h.main._cyl(0.02, drop), Vector3(p.x, r.y1 - drop / 2.0, p.y), iron, false)
	var ring := TorusMesh.new()
	ring.inner_radius = 0.55
	ring.outer_radius = 0.63
	h._p(ring, Vector3(p.x, y, p.y), iron, false)
	var wax: Material = h.main._mat(Color(0.92, 0.88, 0.75))
	var flame: Material = h._glow_material(Color(1.0, 0.7, 0.25))
	for i in 8:
		var a := i * TAU / 8.0
		var cp := Vector3(p.x + cos(a) * 0.59, y, p.y + sin(a) * 0.59)
		h._p(h.main._cyl(0.03, 0.2), cp + Vector3(0, 0.1, 0), wax, false)
		h._p(h._sphere(0.04), cp + Vector3(0, 0.25, 0), flame, false)
	var light := OmniLight3D.new()
	light.position = Vector3(p.x, y - 0.3, p.y)
	light.light_color = Color(1.0, 0.7, 0.4)
	light.omni_range = 9.0
	light.light_energy = 0.9
	light.light_cull_mask = 1
	h.add_child(light)


static func _statue(h, r, color: Color) -> void:
	var m: Node3D = h._wall(r, 0.9, 0.9)
	if m == null:
		return
	var mat: Material = h.main._mat(color)
	h._p(h.main._box(Vector3(0.8, 0.6, 0.8)), Vector3(0, 0.3, 0.45), h.main._mat(color.darkened(0.15)), true, Vector3.ZERO, m)
	h._p(h.main._cyl(0.2, 1.0), Vector3(0, 1.1, 0.45), mat, false, Vector3.ZERO, m)
	h._p(h.main._cyl(0.28, 0.12), Vector3(0, 1.55, 0.45), mat, false, Vector3.ZERO, m)
	h._p(h._sphere(0.15), Vector3(0, 1.8, 0.45), mat, false, Vector3.ZERO, m)
	h._p(h.main._box(Vector3(0.05, 1.1, 0.1)), Vector3(0.32, 1.35, 0.45), h.main._mat(IRON.lightened(0.3)), false, Vector3.ZERO, m)
	h._p(h.main._box(Vector3(0.25, 0.05, 0.1)), Vector3(0.32, 0.85, 0.45), mat, false, Vector3.ZERO, m)


static func _shield(h, r) -> void:
	var m: Node3D = h._wall(r, 1.0, 0.1, 0.0)
	if m == null:
		return
	var y := minf(r.y1 - r.y0 - 1.0, 2.4)
	var blade: Material = h.main._mat(IRON.lightened(0.45))
	for tilt in [-40.0, 40.0]:
		h._p(h.main._box(Vector3(0.07, 1.1, 0.03)), Vector3(0, y, 0.03), blade, false, Vector3(0, 0, tilt), m)
	h._b(m, Vector3(0.55, 0.7, 0.05), Vector3(0, y, 0.06), RED.darkened(0.1), false)
	h._b(m, Vector3(0.1, 0.7, 0.06), Vector3(0, y, 0.065), GOLD, false)
	h._b(m, Vector3(0.55, 0.1, 0.06), Vector3(0, y + 0.1, 0.065), GOLD, false)


static func _weapon_rack(h, r) -> void:
	var m: Node3D = h._wall(r, 2.0, 0.5)
	if m == null:
		return
	h._b(m, Vector3(2.0, 0.08, 0.3), Vector3(0, 0.4, 0.2), WOOD)
	h._b(m, Vector3(2.0, 0.08, 0.3), Vector3(0, 1.3, 0.2), WOOD, false)
	for x in [-0.85, 0.85]:
		h._b(m, Vector3(0.08, 1.8, 0.3), Vector3(x, 0.9, 0.2), WOOD, false)
	for i in 5:
		h._p(h.main._cyl(0.02, 1.7), Vector3(-0.7 + i * 0.35, 0.95, 0.2), h.main._mat(Color(0.5, 0.35, 0.2)), false, Vector3.ZERO, m)
		h._p(h.main._cyl(0.03, 0.14), Vector3(-0.7 + i * 0.35, 1.85, 0.2), h.main._mat(IRON.lightened(0.5)), false, Vector3.ZERO, m)


# --- The walled garden ---

static func _courtyard(h, r) -> void:
	var inner: Rect2 = r.interior()
	var c := inner.get_center()
	var flag := STONE.lightened(0.12)
	# Flagstone paths cross the garden and meet at a fountain.
	h._b(h, Vector3(inner.size.x - 0.6, 0.03, 2.2), Vector3(c.x, r.y0 + 0.015, c.y), flag, false)
	h._b(h, Vector3(2.2, 0.03, inner.size.y - 0.6), Vector3(c.x, r.y0 + 0.016, c.y), flag, false)
	r.used.append(Rect2(c.x - inner.size.x / 2.0, c.y - 1.4, inner.size.x, 2.8))
	r.used.append(Rect2(c.x - 1.4, c.y - inner.size.y / 2.0, 2.8, inner.size.y))
	var stone: Material = h.main._mat(STONE)
	h._p(h.main._cyl(1.7, 0.55), Vector3(c.x, r.y0 + 0.275, c.y), stone, true)
	var water: StandardMaterial3D = h._glow_material(Color(0.25, 0.55, 0.95, 0.8))
	water.emission_energy_multiplier = 0.6
	h._p(h.main._cyl(1.5, 0.05), Vector3(c.x, r.y0 + 0.5, c.y), water, false)
	h._p(h.main._cyl(0.25, 1.4), Vector3(c.x, r.y0 + 1.1, c.y), stone, false)
	h._p(h.main._cyl(0.7, 0.18), Vector3(c.x, r.y0 + 1.5, c.y), stone, false)
	h._p(h._sphere(0.18), Vector3(c.x, r.y0 + 1.75, c.y), water, false)
	var mist := OmniLight3D.new()
	mist.position = Vector3(c.x, r.y0 + 2.0, c.y)
	mist.light_color = Color(0.5, 0.7, 1.0)
	mist.omni_range = 8.0
	mist.light_energy = 0.9
	mist.light_cull_mask = 1
	h.add_child(mist)
	# Four raised flower beds, one in each quarter.
	var bed_colors: Array[Color] = [Color(0.95, 0.3, 0.4), Color(0.95, 0.85, 0.3), Color(0.7, 0.4, 0.95), Color(1.0, 0.6, 0.8)]
	for qx in [-1.0, 1.0]:
		for qy in [-1.0, 1.0]:
			var size := Vector2(minf(inner.size.x / 2.0 - 3.2, 5.0), minf(inner.size.y / 2.0 - 3.2, 4.0))
			if size.x < 1.5 or size.y < 1.5:
				continue
			var bc := c + Vector2(qx * (1.6 + size.x / 2.0 + 0.5), qy * (1.6 + size.y / 2.0 + 0.5))
			var rect := Rect2(bc - size / 2.0, size)
			if not h._free(r, rect):
				continue
			r.used.append(rect)
			h._b(h, Vector3(size.x, 0.35, size.y), Vector3(bc.x, r.y0 + 0.175, bc.y), STONE.darkened(0.1))
			h._b(h, Vector3(size.x - 0.3, 0.38, size.y - 0.3), Vector3(bc.x, r.y0 + 0.19, bc.y), Color(0.25, 0.17, 0.1), false)
			for i in int(size.x * size.y * 1.2):
				var fp := Vector3(bc.x + randf_range(-size.x / 2.0 + 0.3, size.x / 2.0 - 0.3), r.y0 + 0.5,
						bc.y + randf_range(-size.y / 2.0 + 0.3, size.y / 2.0 - 0.3))
				h._p(h.main._cyl(0.015, 0.25), fp - Vector3(0, 0.12, 0), h.main._mat(Color(0.15, 0.5, 0.2)), false)
				h._p(h._sphere(0.09), fp, h.main._mat(bed_colors[randi() % bed_colors.size()]), false)
	# Hedges and benches along the walls, trees in the open, lamp posts on the paths.
	for i in 5:
		var m: Node3D = h._wall(r, 2.6, 1.0)
		if m != null:
			h._b(m, Vector3(2.6, 1.1, 0.9), Vector3(0, 0.55, 0.5), Color(0.1, 0.38, 0.14))
			h._b(m, Vector3(2.2, 0.3, 0.8), Vector3(0, 1.2, 0.5), Color(0.12, 0.45, 0.17), false)
	for i in 2:
		var m: Node3D = h._wall(r, 1.8, 0.7)
		if m != null:
			h._b(m, Vector3(1.8, 0.08, 0.5), Vector3(0, 0.5, 0.35), WOOD.lightened(0.15))
			h._b(m, Vector3(1.8, 0.5, 0.06), Vector3(0, 0.8, 0.1), WOOD.lightened(0.15), false)
			for lx in [-0.8, 0.8]:
				h._b(m, Vector3(0.08, 0.5, 0.45), Vector3(lx, 0.25, 0.35), IRON, false)
			r.spots.append(m.to_global(Vector3(0, 0.6, 0.35)))
	for i in 4:
		var tc: Vector2 = h._floor(r, Vector2(1.6, 1.6), 1.0)
		if tc == Vector2.INF:
			continue
		h._p(h.main._cyl(0.22, 2.6), Vector3(tc.x, r.y0 + 1.3, tc.y), h.main._mat(Color(0.3, 0.2, 0.12)), true)
		var leaves: Material = h.main._mat(Color(0.12, 0.42, 0.16))
		h._p(h._sphere(1.1), Vector3(tc.x, r.y0 + 3.2, tc.y), leaves, false)
		h._p(h._sphere(0.8), Vector3(tc.x + 0.6, r.y0 + 4.0, tc.y - 0.3), leaves, false)
	for offset in [Vector2(-5.0, 1.8), Vector2(5.0, -1.8), Vector2(1.8, 4.5), Vector2(-1.8, -4.5)]:
		var lp: Vector2 = c + offset
		if not inner.grow(-1.0).has_point(lp):
			continue
		h._p(h.main._cyl(0.06, 2.6), Vector3(lp.x, r.y0 + 1.3, lp.y), h.main._mat(IRON), false)
		h._p(h._sphere(0.16), Vector3(lp.x, r.y0 + 2.7, lp.y), h._glow_material(Color(1.0, 0.8, 0.4)), false)
		var lamp := OmniLight3D.new()
		lamp.position = Vector3(lp.x, r.y0 + 2.8, lp.y)
		lamp.light_color = Color(1.0, 0.8, 0.5)
		lamp.omni_range = 7.0
		lamp.light_energy = 0.8
		lamp.light_cull_mask = 1
		h.add_child(lamp)
	for i in 2:
		_statue(h, r, STONE.lightened(0.1))
	# Crenellations crown the surrounding walls.
	var merlon: Material = h.main._mat(STONE.lightened(0.05))
	var top: float = r.y1
	var x := inner.position.x + 0.4
	while x < inner.end.x:
		for edge_y in [inner.position.y + 0.15, inner.end.y - 0.15]:
			h._p(h.main._box(Vector3(0.6, 0.5, 0.3)), Vector3(x, top + 0.25, edge_y), merlon, false)
		x += 1.3
	var z := inner.position.y + 0.4
	while z < inner.end.y:
		for edge_x in [inner.position.x + 0.15, inner.end.x - 0.15]:
			h._p(h.main._box(Vector3(0.3, 0.5, 0.6)), Vector3(edge_x, top + 0.25, z), merlon, false)
		z += 1.3


# --- The treasure vault ---

static func _treasure(h, r) -> void:
	var inner: Rect2 = r.interior()
	var c := inner.get_center()
	var gold: StandardMaterial3D = h._glow_material(GOLD)
	gold.emission_energy_multiplier = 0.35
	_carpet(h, Vector3(c.x, r.y0, c.y), Vector2(minf(inner.size.x - 1.0, 4.0), minf(inner.size.y - 1.0, 4.0)))
	r.used.append(Rect2(c - Vector2(2.2, 2.2), Vector2(4.4, 4.4)))
	# The crown rests on a stepped pedestal under its own golden light.
	h._p(h.main._cyl(0.9, 0.3), Vector3(c.x, r.y0 + 0.15, c.y), h.main._mat(STONE.lightened(0.1)), true)
	h._p(h.main._cyl(0.55, 0.7), Vector3(c.x, r.y0 + 0.65, c.y), h.main._mat(STONE.lightened(0.2)), true)
	h._p(h.main._cyl(0.65, 0.08), Vector3(c.x, r.y0 + 1.04, c.y), gold, false)
	h.treasure_spot = Vector3(c.x, r.y0 + 1.08, c.y)
	var glow := OmniLight3D.new()
	glow.position = Vector3(c.x, r.y0 + 2.2, c.y)
	glow.light_color = Color(1.0, 0.85, 0.4)
	glow.omni_range = 9.0
	glow.light_energy = 1.4
	glow.light_cull_mask = 1
	h.add_child(glow)
	# Gold piles, chests, columns and braziers.
	for i in 7:
		var pc: Vector2 = h._floor(r, Vector2(1.2, 1.2), 0.5)
		if pc == Vector2.INF:
			continue
		for k in 3:
			h._p(h.main._cyl(0.55 - k * 0.17, 0.16), Vector3(pc.x, r.y0 + 0.08 + k * 0.15, pc.y), gold, false)
		for k in 5:
			h._p(h.main._cyl(0.07, 0.015), Vector3(pc.x + randf_range(-0.9, 0.9), r.y0 + 0.01, pc.y + randf_range(-0.9, 0.9)), gold, false)
	for i in 3:
		var m: Node3D = h._wall(r, 1.3, 0.9)
		if m != null:
			h._b(m, Vector3(1.2, 0.6, 0.7), Vector3(0, 0.3, 0.45), WOOD)
			h._b(m, Vector3(1.24, 0.1, 0.74), Vector3(0, 0.65, 0.45), GOLD.darkened(0.3), false)
			h._b(m, Vector3(0.16, 0.4, 0.76), Vector3(0, 0.4, 0.45), GOLD.darkened(0.3), false)
			h._p(h.main._cyl(0.35, 0.1), Vector3(0, 0.73, 0.45), gold, false, Vector3(0, 0, 90), m)
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			var cp := Vector2(c.x + sx * (inner.size.x / 2.0 - 0.9), c.y + sy * (inner.size.y / 2.0 - 0.9))
			var rect := Rect2(cp - Vector2(0.5, 0.5), Vector2(1.0, 1.0))
			if h._free(r, rect):
				r.used.append(rect)
				_column(h, cp, r.y0, r.y1 - r.y0)
	for i in 2:
		_statue(h, r, GOLD.darkened(0.15))
	_banners(h, r, 3)


# --- Pieces ---

static func _column(h, p: Vector2, y0: float, height: float) -> void:
	var mat: Material = h.main._mat(STONE.lightened(0.1))
	h._p(h.main._box(Vector3(0.9, 0.3, 0.9)), Vector3(p.x, y0 + 0.15, p.y), mat, false)
	h._p(h.main._cyl(0.3, height), Vector3(p.x, y0 + height / 2.0, p.y), mat, true)
	h._p(h.main._box(Vector3(0.8, 0.25, 0.8)), Vector3(p.x, y0 + height - 0.125, p.y), mat, false)


# Half ring of stone blocks rising from `center` (the spring line) across the span along `axis`.
static func _arch(h, center: Vector3, axis: Vector3, half_width: float, depth: float) -> void:
	var mat: Material = h.main._mat(STONE.lightened(0.05))
	var blocks := 9
	for i in blocks:
		var mid := PI * (i + 0.5) / blocks
		var radial := axis * -cos(mid) + Vector3.UP * sin(mid)
		var tangent := axis * sin(mid) + Vector3.UP * cos(mid)
		var length := 2.0 * half_width * sin(PI / (2.0 * blocks)) * 1.15
		var node: Node3D = h._p(h.main._box(Vector3(length, 0.4, depth)), center + radial * half_width, mat, false)
		node.basis = Basis(tangent, radial, tangent.cross(radial))


static func _brazier(h, r, p: Vector2) -> void:
	var rect := Rect2(p - Vector2(0.4, 0.4), Vector2(0.8, 0.8))
	if not h._free(r, rect):
		return
	r.used.append(rect)
	var iron: Material = h.main._mat(IRON)
	h._p(h.main._cyl(0.28, 0.9), Vector3(p.x, r.y0 + 0.45, p.y), iron, true)
	var bowl := CylinderMesh.new()
	bowl.top_radius = 0.32
	bowl.bottom_radius = 0.16
	bowl.height = 0.25
	h._p(bowl, Vector3(p.x, r.y0 + 1.02, p.y), iron, false)
	var flame := SphereMesh.new()
	flame.radius = 0.17
	flame.height = 0.4
	h._p(flame, Vector3(p.x, r.y0 + 1.3, p.y), h._glow_material(Color(1.0, 0.45, 0.1)), false)
	var fire := OmniLight3D.new()
	fire.position = Vector3(p.x, r.y0 + 1.7, p.y)
	fire.light_color = Color(1.0, 0.5, 0.2)
	fire.omni_range = 7.0
	fire.light_energy = 1.3
	fire.light_cull_mask = 1
	h.add_child(fire)


static func _carpet(h, center: Vector3, size: Vector2) -> void:
	h._b(h, Vector3(size.x, 0.02, size.y), center + Vector3(0, 0.01, 0), RED, false)
	if size.x >= size.y:
		for sgn in [-1.0, 1.0]:
			h._b(h, Vector3(size.x, 0.024, 0.07), center + Vector3(0, 0.012, sgn * (size.y / 2.0 - 0.1)), GOLD, false)
	else:
		for sgn in [-1.0, 1.0]:
			h._b(h, Vector3(0.07, 0.024, size.y), center + Vector3(sgn * (size.x / 2.0 - 0.1), 0.012, 0), GOLD, false)


static func _banners(h, r, count: int) -> void:
	for i in count:
		var m: Node3D = h._wall(r, 1.0, 0.1, 0.0)
		if m == null:
			continue
		var y := minf(r.y1 - r.y0 - 1.6, 3.0)
		h._b(m, Vector3(0.9, 2.6, 0.03), Vector3(0, y, 0.03), RED.darkened(0.1), false)
		h._b(m, Vector3(0.9, 0.12, 0.04), Vector3(0, y + 1.25, 0.035), GOLD, false)
		h._b(m, Vector3(0.28, 0.6, 0.04), Vector3(0, y + 0.2, 0.04), GOLD.darkened(0.1), false)


static func _wall_mount(h, r, side: int, width: float, depth: float) -> Node3D:
	var inner: Rect2 = r.interior()
	var c := inner.get_center()
	var rect: Rect2
	var point: Vector3
	match side:
		0:
			rect = Rect2(c.x - width / 2.0, inner.end.y - depth, width, depth)
			point = Vector3(c.x, r.y0, inner.end.y)
		1:
			rect = Rect2(c.x - width / 2.0, inner.position.y, width, depth)
			point = Vector3(c.x, r.y0, inner.position.y)
		2:
			rect = Rect2(inner.end.x - depth, c.y - width / 2.0, depth, width)
			point = Vector3(inner.end.x, r.y0, c.y)
		_:
			rect = Rect2(inner.position.x, c.y - width / 2.0, depth, width)
			point = Vector3(inner.position.x, r.y0, c.y)
	if not h._free(r, rect.grow(0.2)):
		return null
	r.used.append(rect)
	var n: Vector3 = -h._side_vec(side)
	var m := Node3D.new()
	m.position = point
	m.rotation.y = atan2(n.x, n.z)
	h.add_child(m)
	return m


# Two rows of columns joined by arches along the room's long axis.
static func _arcade(h, r, margin: float) -> void:
	var inner: Rect2 = r.interior()
	var c := inner.get_center()
	var along_x := inner.size.x >= inner.size.y
	var long_len := inner.size.x if along_x else inner.size.y
	var short_len := inner.size.y if along_x else inner.size.x
	var count := floori((long_len - 2.4) / 3.0)
	if count < 2:
		return
	var step := (long_len - 2.4) / count
	var half := step / 2.0
	var height := maxf(r.y1 - r.y0 - half - 0.3, 2.4)
	var axis := Vector3.RIGHT if along_x else Vector3.BACK
	for sgn in [-1.0, 1.0]:
		var placed: Array[bool] = []
		var spots: Array[Vector2] = []
		for i in count + 1:
			var t := -long_len / 2.0 + 1.2 + step * i
			var off: float = sgn * (short_len / 2.0 - margin)
			var p := Vector2(c.x + t, c.y + off) if along_x else Vector2(c.x + off, c.y + t)
			spots.append(p)
			var rect := Rect2(p - Vector2(0.5, 0.5), Vector2(1.0, 1.0))
			var ok: bool = h._free(r, rect)
			if ok:
				r.used.append(rect)
				_column(h, p, r.y0, height)
			placed.append(ok)
		for i in count:
			if placed[i] and placed[i + 1]:
				var mid := (spots[i] + spots[i + 1]) / 2.0
				_arch(h, Vector3(mid.x, r.y0 + height - 0.05, mid.y), axis, half - 0.15, 0.34)


# --- Rooms ---

static func _throne_room(h, r) -> void:
	var inner: Rect2 = r.interior()
	var along_x := inner.size.x >= inner.size.y
	var sides := [2, 3] if along_x else [0, 1]
	sides.shuffle()
	var dais: Node3D = null
	for side in sides:
		dais = _wall_mount(h, r, side, 4.8, 3.4)
		if dais != null:
			break
	_arcade(h, r, 1.1)
	if dais != null:
		var stone := STONE.darkened(0.1)
		h._b(dais, Vector3(4.8, 0.25, 3.4), Vector3(0, 0.125, 1.7), stone)
		h._b(dais, Vector3(3.2, 0.25, 2.0), Vector3(0, 0.375, 1.0), STONE)
		# The throne: iron frame, red cushion, gold finials.
		h._b(dais, Vector3(1.0, 0.45, 0.85), Vector3(0, 0.725, 0.7), IRON)
		h._b(dais, Vector3(0.8, 0.12, 0.65), Vector3(0, 1.0, 0.72), RED, false)
		h._b(dais, Vector3(1.0, 2.6, 0.18), Vector3(0, 1.8, 0.2), IRON)
		h._b(dais, Vector3(0.6, 1.8, 0.04), Vector3(0, 1.9, 0.31), RED.darkened(0.2), false)
		for ax in [-0.55, 0.55]:
			h._b(dais, Vector3(0.14, 0.4, 0.8), Vector3(ax, 1.15, 0.7), IRON, false)
			h._p(h._sphere(0.1), Vector3(ax, 3.2, 0.2), h.main._mat(GOLD), false, Vector3.ZERO, dais)
		h._b(dais, Vector3(1.1, 0.14, 0.2), Vector3(0, 3.15, 0.2), GOLD, false)
		r.spots.append(dais.to_global(Vector3(0, 1.17, 0.72)))
		# Carpet from the dais steps out across the room, and up the steps.
		var long_len := inner.size.x if along_x else inner.size.y
		var run := long_len - 3.6
		_carpet(h, dais.to_global(Vector3(0, 0, 3.4 + run / 2.0)), Vector2(1.8, run) if not along_x else Vector2(run, 1.8))
		h._b(dais, Vector3(1.8, 0.02, 1.6), Vector3(0, 0.26, 2.5), RED, false)
		h._b(dais, Vector3(1.8, 0.02, 0.9), Vector3(0, 0.51, 1.3), RED, false)
		# Balustrade posts along the front of the dais, with a gap for the carpet.
		for sgn in [-1.0, 1.0]:
			for i in 5:
				var x: float = sgn * (1.2 + i * 0.25)
				h._p(h._sphere(0.07), Vector3(x, 1.0, 3.2), h.main._mat(STONE.lightened(0.2)), false, Vector3.ZERO, dais)
				h._p(h.main._cyl(0.06, 0.7), Vector3(x, 0.6, 3.2), h.main._mat(STONE.lightened(0.15)), false, Vector3.ZERO, dais)
			h._b(dais, Vector3(1.3, 0.08, 0.1), Vector3(sgn * 1.85, 0.95, 3.2), STONE.lightened(0.1), false)
		for sx in [-1.7, 1.7]:
			for dist in [4.2, 4.2 + run * 0.5]:
				var bp: Vector3 = dais.to_global(Vector3(sx, 0, dist))
				_brazier(h, r, Vector2(bp.x, bp.z))
	_banners(h, r, 4)
	h._armor_stand(r)


static func _great_hall(h, r) -> void:
	var inner: Rect2 = r.interior()
	var c := inner.get_center()
	var along_x := inner.size.x >= inner.size.y
	var long_len := inner.size.x if along_x else inner.size.y
	_arcade(h, r, 1.0)
	var strip := Rect2(c.x - long_len / 2.0, c.y - 1.3, long_len, 2.6) if along_x \
			else Rect2(c.x - 1.3, c.y - long_len / 2.0, 2.6, long_len)
	_carpet(h, Vector3(c.x, r.y0, c.y), Vector2(long_len - 0.4, 2.0) if along_x else Vector2(2.0, long_len - 0.4))
	r.used.append(strip)
	for sgn in [-1.0, 1.0]:
		for quarter in [-0.25, 0.25]:
			var off := Vector2(quarter * long_len, sgn * 1.7) if along_x else Vector2(sgn * 1.7, quarter * long_len)
			_brazier(h, r, c + off)
	var wood := WOOD.lightened(0.1)
	for i in 2:
		var tc: Vector2 = h._floor(r, Vector2(3.6, 1.2), 0.6)
		if tc == Vector2.INF:
			continue
		h._b(h, Vector3(3.4, 0.08, 1.0), Vector3(tc.x, r.y0 + 0.8, tc.y), wood)
		for lx in [-1.5, 1.5]:
			for lz in [-0.4, 0.4]:
				h._b(h, Vector3(0.12, 0.78, 0.12), Vector3(tc.x + lx, r.y0 + 0.39, tc.y + lz), wood, false)
		for g in 3:
			h._p(h.main._cyl(0.04, 0.12), Vector3(tc.x - 1.0 + g * 1.0, r.y0 + 0.9, tc.y), h.main._mat(GOLD), false)
		r.spots.append(Vector3(tc.x - 0.5, r.y0 + 0.91, tc.y))
	var m: Node3D = h._wall(r, 3.2, 1.0)
	if m != null:
		h._b(m, Vector3(3.2, 2.8, 0.7), Vector3(0, 1.4, 0.35), DARK_STONE.lightened(0.2))
		h._p(h.main._box(Vector3(1.6, 1.1, 0.08)), Vector3(0, 0.6, 0.72), h._glow_material(Color(1.0, 0.4, 0.1)), false, Vector3.ZERO, m)
		h._b(m, Vector3(2.0, 0.15, 0.9), Vector3(0, 1.3, 0.55), STONE, false)
		var glow := OmniLight3D.new()
		glow.position = Vector3(0, 0.9, 1.3)
		glow.light_color = Color(1.0, 0.5, 0.2)
		glow.omni_range = 6.0
		glow.light_energy = 1.2
		glow.light_cull_mask = 1
		m.add_child(glow)
		r.spots.append(m.to_global(Vector3(1.2, 1.46, 0.55)))
	_banners(h, r, 3)
	h._armor_stand(r)
	h._armor_stand(r)


static func _gallery(h, r) -> void:
	var inner: Rect2 = r.interior()
	var c := inner.get_center()
	var along_x := inner.size.x >= inner.size.y
	var long_len := inner.size.x if along_x else inner.size.y
	var wide := 1.4
	_carpet(h, Vector3(c.x, r.y0, c.y), Vector2(long_len - 0.4, wide) if along_x else Vector2(wide, long_len - 0.4))
	r.used.append(Rect2(c.x - long_len / 2.0, c.y - wide / 2.0, long_len, wide) if along_x \
			else Rect2(c.x - wide / 2.0, c.y - long_len / 2.0, wide, long_len))
	for i in 3:
		var m: Node3D = h._wall(r, 0.9, 0.9)
		if m != null:
			var bp: Vector3 = m.to_global(Vector3(0, 0, 0.45))
			_brazier(h, r, Vector2(bp.x, bp.z))
	h._armor_stand(r)
	h._armor_stand(r)
	_banners(h, r, 2)


static func _bedroom(h, r) -> void:
	var wood := WOOD
	var m: Node3D = h._wall(r, 2.4, 2.5)
	if m != null:
		h._b(m, Vector3(1.8, 0.3, 2.2), Vector3(0, 0.15, 1.2), wood)
		h._b(m, Vector3(1.6, 0.25, 2.0), Vector3(0, 0.42, 1.2), RED, false)
		h._b(m, Vector3(0.6, 0.12, 0.4), Vector3(0, 0.6, 0.45), Color(0.85, 0.82, 0.75), false)
		h._b(m, Vector3(1.9, 1.5, 0.15), Vector3(0, 0.85, 0.08), wood)
		for px in [-0.9, 0.9]:
			for pz in [0.1, 2.2]:
				h._b(m, Vector3(0.1, 2.3, 0.1), Vector3(px, 1.15, pz), wood, false)
		h._b(m, Vector3(2.0, 0.06, 2.4), Vector3(0, 2.3, 1.2), RED.darkened(0.2), false)
		r.spots.append(m.to_global(Vector3(0, 0.66, 1.4)))
	m = h._wall(r, 1.2, 0.7)
	if m != null:
		h._b(m, Vector3(1.1, 0.6, 0.55), Vector3(0, 0.3, 0.3), wood)
		h._b(m, Vector3(1.12, 0.08, 0.1), Vector3(0, 0.45, 0.3), IRON, false)
		h._b(m, Vector3(0.08, 0.62, 0.57), Vector3(-0.35, 0.3, 0.3), IRON, false)
		h._b(m, Vector3(0.08, 0.62, 0.57), Vector3(0.35, 0.3, 0.3), IRON, false)
		r.spots.append(m.to_global(Vector3(0, 0.71, 0.3)))
	m = h._wall(r, 0.9, 0.9)
	if m != null:
		var bp: Vector3 = m.to_global(Vector3(0, 0, 0.45))
		_brazier(h, r, Vector2(bp.x, bp.z))
	var rc: Vector2 = h._floor(r, Vector2(2.0, 1.4), 0.4)
	if rc != Vector2.INF:
		h._b(h, Vector3(2.0, 0.02, 1.4), Vector3(rc.x, r.y0 + 0.01, rc.y), RED.darkened(0.15), false)
	_banners(h, r, 1)


static func _kitchen(h, r) -> void:
	var m: Node3D = h._wall(r, 3.0, 1.2)
	if m != null:
		h._b(m, Vector3(3.0, 2.6, 0.9), Vector3(0, 1.3, 0.45), DARK_STONE.lightened(0.2))
		h._p(h.main._box(Vector3(1.4, 1.0, 0.08)), Vector3(0, 0.55, 0.92), h._glow_material(Color(1.0, 0.4, 0.1)), false, Vector3.ZERO, m)
		var pot := SphereMesh.new()
		pot.radius = 0.3
		pot.height = 0.5
		h._p(pot, Vector3(0, 0.45, 1.2), h.main._mat(IRON), false, Vector3.ZERO, m)
		var glow := OmniLight3D.new()
		glow.position = Vector3(0, 0.9, 1.5)
		glow.light_color = Color(1.0, 0.5, 0.2)
		glow.omni_range = 5.0
		glow.light_energy = 1.0
		glow.light_cull_mask = 1
		m.add_child(glow)
		r.spots.append(m.to_global(Vector3(1.2, 0.11, 1.2)))
	var tc: Vector2 = h._floor(r, Vector2(2.6, 1.2), 0.6)
	if tc != Vector2.INF:
		h._b(h, Vector3(2.4, 0.1, 1.0), Vector3(tc.x, r.y0 + 0.85, tc.y), WOOD.lightened(0.1))
		for lx in [-1.0, 1.0]:
			for lz in [-0.35, 0.35]:
				h._b(h, Vector3(0.12, 0.82, 0.12), Vector3(tc.x + lx, r.y0 + 0.41, tc.y + lz), WOOD, false)
		r.spots.append(Vector3(tc.x - 0.6, r.y0 + 0.96, tc.y))
		r.spots.append(Vector3(tc.x + 0.7, r.y0 + 0.96, tc.y))
	for i in 3:
		_barrel(h, r)
	_banners(h, r, 1)


static func _barrel(h, r) -> void:
	var m: Node3D = h._wall(r, 0.8, 0.8)
	if m == null:
		return
	h._p(h.main._cyl(0.35, 0.85), Vector3(0, 0.425, 0.4), h.main._mat(WOOD.lightened(0.15)), true, Vector3.ZERO, m)
	for y in [0.2, 0.65]:
		h._p(h.main._cyl(0.37, 0.05), Vector3(0, y, 0.4), h.main._mat(IRON), false, Vector3.ZERO, m)
	r.spots.append(m.to_global(Vector3(0, 0.96, 0.4)))


static func _storeroom(h, r) -> void:
	for i in 2:
		_barrel(h, r)
	var c: Vector2 = h._floor(r, Vector2(0.7, 0.7), 0.3)
	if c != Vector2.INF:
		h._b(h, Vector3(0.7, 0.6, 0.7), Vector3(c.x, r.y0 + 0.3, c.y), WOOD.lightened(0.2))
		r.spots.append(Vector3(c.x, r.y0 + 0.71, c.y))
