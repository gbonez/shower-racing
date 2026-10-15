extends RefCounted

# The crypt's look: mossy catacomb stone, skulls and bones, sarcophagi, chains and eerie green flames.
# Builders draw into the house node `h` (untyped: it calls the house script's helpers).

const Castle := preload("res://scripts/castle.gd")
const STONE := Color(0.27, 0.29, 0.27)
const MOSS := Color(0.16, 0.26, 0.17)
const BONE := Color(0.85, 0.82, 0.7)
const WOOD := Color(0.19, 0.13, 0.09)
const IRON := Color(0.1, 0.1, 0.12)
const GHOST := Color(0.35, 1.0, 0.6)


static func wall_material() -> StandardMaterial3D:
	var img := Image.create(64, 64, false, Image.FORMAT_RGB8)
	for y in 64:
		var row := y >> 4
		var shift := 16 if (row & 1) == 1 else 0
		for x in 64:
			var bx := (x + shift) & 31
			var by := y & 15
			if bx < 1 or by < 1:
				img.set_pixel(x, y, Color(0.04, 0.05, 0.04))
			else:
				var tone := STONE.darkened(0.06 * ((((x + shift) >> 5) * 7 + row * 5) % 4))
				if randf() < 0.18:
					tone = tone.lerp(MOSS, 0.7)
				img.set_pixel(x, y, tone)
	var m := StandardMaterial3D.new()
	m.albedo_texture = ImageTexture.create_from_image(img)
	m.uv1_triplanar = true
	m.uv1_scale = Vector3.ONE
	m.roughness = 1.0
	return m


static func floor_material(size: Vector2) -> StandardMaterial3D:
	var img := Image.create(4, 4, false, Image.FORMAT_RGB8)
	for y in 4:
		for x in 4:
			var tone := Color(0.14, 0.15, 0.14).lerp(Color(0.08, 0.09, 0.08), randf())
			if (x + y) % 2 == 0:
				tone = tone.lightened(0.08)
			img.set_pixel(x, y, tone)
	var m := StandardMaterial3D.new()
	m.albedo_texture = ImageTexture.create_from_image(img)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	m.uv1_scale = Vector3(size.x / 3.2, size.y / 3.2, 1)
	m.roughness = 1.0
	return m


static func furnish(h, r) -> void:
	var area: float = r.rect.size.x * r.rect.size.y
	match r.type:
		"hallway":
			_catacomb(h, r)
		"great_hall":
			_ossuary(h, r)
		"throne_room":
			_chapel(h, r)
		"bedroom":
			_burial_chamber(h, r)
		"kitchen":
			_embalming_room(h, r)
		"closet":
			_bone_room(h, r)
		"tomb":
			_tomb(h, r)
	for i in clampi(int(area / 35.0) + 1, 1, 6):
		_torch(h, r)
	for i in clampi(int(area / 12.0), 2, 14):
		_niche(h, r)
	for i in clampi(int(area / 30.0), 1, 4):
		_bones(h, r)
	if area > 30.0:
		for i in clampi(int(area / 50.0), 0, 3):
			_chains(h, r)
	_cobwebs(h, r)


# --- Small pieces ---

static func _skull(h, parent: Node, pos: Vector3, scale: float) -> void:
	var bone: Material = h.main._mat(BONE)
	h._p(h._sphere(0.09 * scale), pos, bone, false, Vector3.ZERO, parent)
	h._p(h.main._box(Vector3(0.1, 0.05, 0.08) * scale), pos + Vector3(0, -0.09, 0.02) * scale, bone, false, Vector3.ZERO, parent)
	var dark: Material = h.main._mat(Color(0.02, 0.02, 0.02))
	for sx in [-0.035, 0.035]:
		h._p(h._sphere(0.022 * scale), pos + Vector3(sx, 0.0, 0.075) * scale, dark, false, Vector3.ZERO, parent)


static func _bone(h, parent: Node, pos: Vector3, rot: Vector3) -> void:
	h._p(h.main._cyl(0.02, 0.38), pos, h.main._mat(BONE.darkened(0.1)), false, rot, parent)


static func _flame(h, parent: Node, pos: Vector3, energy := 0.5) -> void:
	h._p(h._sphere(0.07), pos, h._glow_material(GHOST), false, Vector3.ZERO, parent)
	var light := OmniLight3D.new()
	light.position = pos + Vector3(0, 0.1, 0)
	light.light_color = GHOST
	light.omni_range = 5.0
	light.light_energy = energy
	light.light_cull_mask = 1
	parent.add_child(light)


static func _torch(h, r) -> void:
	var m: Node3D = h._wall(r, 0.3, 0.12, 0.5)
	if m == null:
		return
	var y := minf(r.y1 - r.y0 - 1.0, 2.1)
	h._b(m, Vector3(0.08, 0.5, 0.08), Vector3(0, y, 0.08), IRON, false)
	h._b(m, Vector3(0.2, 0.06, 0.2), Vector3(0, y + 0.27, 0.12), IRON, false)
	_flame(h, m, Vector3(0, y + 0.4, 0.12), 0.7)


# A burial niche cut into the wall, with a skull and crossed bones.
static func _niche(h, r) -> void:
	var m: Node3D = h._wall(r, 1.2, 0.1, 0.0)
	if m == null:
		return
	var y := randf_range(0.5, minf(r.y1 - r.y0 - 0.9, 2.2))
	h._b(m, Vector3(1.0, 0.55, 0.04), Vector3(0, y, 0.025), Color(0.02, 0.02, 0.02), false)
	h._b(m, Vector3(1.1, 0.06, 0.07), Vector3(0, y - 0.31, 0.04), STONE.lightened(0.1), false)
	_skull(h, m, Vector3(randf_range(-0.2, 0.2), y - 0.15, 0.08), 1.0)
	_bone(h, m, Vector3(0.25, y - 0.2, 0.07), Vector3(90, 0, 20))
	_bone(h, m, Vector3(-0.3, y - 0.2, 0.07), Vector3(90, 0, -25))


static func _bones(h, r) -> void:
	var c: Vector2 = h._floor(r, Vector2(1.2, 1.2), 0.3)
	if c == Vector2.INF:
		return
	var pile := Node3D.new()
	pile.position = Vector3(c.x, r.y0, c.y)
	h.add_child(pile)
	for i in 7:
		_bone(h, pile, Vector3(randf_range(-0.4, 0.4), 0.03 + i * 0.012, randf_range(-0.4, 0.4)),
				Vector3(90, randf() * 180.0, randf_range(-10.0, 10.0)))
	for i in randi_range(1, 3):
		_skull(h, pile, Vector3(randf_range(-0.3, 0.3), 0.1, randf_range(-0.3, 0.3)), 1.0)
	r.spots.append(pile.to_global(Vector3(0, 0.12, 0)))


static func _chains(h, r) -> void:
	var c: Vector2 = h._floor(r, Vector2(0.4, 0.4), 0.6)
	if c == Vector2.INF:
		return
	var length := randf_range(1.2, 2.4)
	h._p(h.main._cyl(0.015, length), Vector3(c.x, r.y1 - length / 2.0, c.y), h.main._mat(IRON), false)
	var ring := TorusMesh.new()
	ring.inner_radius = 0.07
	ring.outer_radius = 0.1
	h._p(ring, Vector3(c.x, r.y1 - length, c.y), h.main._mat(IRON), false, Vector3(90, 0, 0))


static func _cobwebs(h, r) -> void:
	var web: StandardMaterial3D = h.main._mat(Color(1, 1, 1, 0.22))
	web.cull_mode = BaseMaterial3D.CULL_DISABLED
	var inner: Rect2 = r.interior()
	var top: float = r.y1 - 0.75
	var corners: Array[Vector3] = [Vector3(inner.position.x + 0.5, top, inner.position.y + 0.5),
			Vector3(inner.end.x - 0.5, top, inner.position.y + 0.5), Vector3(inner.position.x + 0.5, top, inner.end.y - 0.5),
			Vector3(inner.end.x - 0.5, top, inner.end.y - 0.5)]
	var yaws: Array[float] = [-45.0, 45.0, 45.0, -45.0]
	for i in 4:
		var quad := QuadMesh.new()
		quad.size = Vector2(1.1, 1.3)
		h._p(quad, corners[i], web, false, Vector3(0, yaws[i], 0))


static func _sarcophagus(h, r, ajar := true) -> Node3D:
	var along_x := randf() < 0.5
	var c: Vector2 = h._floor(r, Vector2(2.8, 1.6) if along_x else Vector2(1.6, 2.8), 0.5)
	if c == Vector2.INF:
		return null
	var root := Node3D.new()
	root.position = Vector3(c.x, r.y0, c.y)
	root.rotation.y = 0.0 if along_x else PI / 2.0
	h.add_child(root)
	h._b(root, Vector3(2.2, 0.7, 0.95), Vector3(0, 0.35, 0), STONE)
	var lid: Node3D = h._b(root, Vector3(2.3, 0.16, 1.05), Vector3(0.25 if ajar else 0.0, 0.78, 0.0), STONE.lightened(0.1))
	if ajar:
		lid.rotation.y = 0.12
	h._b(root, Vector3(1.4, 0.03, 0.12), Vector3(0.25 if ajar else 0.0, 0.88, 0), STONE.darkened(0.2), false)
	h._b(root, Vector3(0.12, 0.03, 0.6), Vector3(0.5 if ajar else 0.25, 0.88, 0), STONE.darkened(0.2), false)
	r.spots.append(root.to_global(Vector3(-0.5, 0.86, 0)))
	return root


static func _coffin(h, r) -> void:
	var c: Vector2 = h._floor(r, Vector2(2.2, 1.0), 0.5)
	if c == Vector2.INF:
		return
	var root := Node3D.new()
	root.position = Vector3(c.x, r.y0, c.y)
	h.add_child(root)
	for x in [-0.8, 0.8]:
		h._b(root, Vector3(0.12, 0.35, 0.8), Vector3(x, 0.175, 0), STONE.darkened(0.1), false)
	h._b(root, Vector3(2.0, 0.45, 0.75), Vector3(0, 0.575, 0), WOOD)
	h._b(root, Vector3(1.9, 0.06, 0.65), Vector3(0.1, 0.83, 0.03), WOOD.lightened(0.1), false)
	h._b(root, Vector3(0.1, 0.02, 0.4), Vector3(0.1, 0.87, 0.03), IRON.lightened(0.4), false)
	h._b(root, Vector3(0.5, 0.02, 0.1), Vector3(0.1, 0.87, 0.03), IRON.lightened(0.4), false)
	r.spots.append(root.to_global(Vector3(-0.5, 0.9, 0)))


static func _candles(h, r) -> void:
	var m: Node3D = h._wall(r, 0.8, 0.5, 0.2)
	if m == null:
		return
	h._p(h.main._cyl(0.18, 0.7), Vector3(0, 0.35, 0.3), h.main._mat(STONE.lightened(0.1)), true, Vector3.ZERO, m)
	var wax: Material = h.main._mat(Color(0.85, 0.8, 0.65))
	for i in 3:
		h._p(h.main._cyl(0.03, 0.15 + i * 0.05), Vector3(-0.07 + i * 0.07, 0.78, 0.3), wax, false, Vector3.ZERO, m)
	_flame(h, m, Vector3(0, 1.0, 0.3), 0.5)
	r.spots.append(m.to_global(Vector3(0, 0.72, 0.3)))


# --- Rooms ---

static func _catacomb(h, r) -> void:
	_candles(h, r)
	_candles(h, r)
	for i in 3:
		_skull_stack(h, r)
	for i in 2:
		_coffin(h, r)


# Rows of skulls set into a bone-white wall.
static func _skull_stack(h, r) -> void:
	var m: Node3D = h._wall(r, 2.4, 0.3, 0.0)
	if m == null:
		return
	h._b(m, Vector3(2.4, 1.6, 0.18), Vector3(0, 0.8, 0.1), BONE.darkened(0.45))
	for row in 4:
		for col in 7:
			_skull(h, m, Vector3(-1.05 + col * 0.35 + (0.17 if row % 2 == 1 else 0.0), 0.2 + row * 0.38, 0.22), 1.0)


static func _ossuary(h, r) -> void:
	Castle._arcade(h, r, 1.1)
	for i in 3:
		_skull_stack(h, r)
	for i in 3:
		_sarcophagus(h, r)
	_candles(h, r)
	_candles(h, r)
	_candles(h, r)


static func _chapel(h, r) -> void:
	var inner: Rect2 = r.interior()
	var along_x := inner.size.x >= inner.size.y
	var sides := [2, 3] if along_x else [0, 1]
	sides.shuffle()
	var altar: Node3D = null
	for side in sides:
		altar = Castle._wall_mount(h, r, side, 3.6, 2.2)
		if altar != null:
			break
	Castle._arcade(h, r, 1.1)
	if altar != null:
		h._b(altar, Vector3(3.2, 0.2, 1.8), Vector3(0, 0.1, 1.0), STONE.darkened(0.1))
		h._b(altar, Vector3(2.6, 1.0, 1.0), Vector3(0, 0.7, 0.8), STONE)
		h._b(altar, Vector3(2.8, 0.1, 1.2), Vector3(0, 1.25, 0.8), STONE.lightened(0.1))
		h._b(altar, Vector3(2.0, 0.02, 0.9), Vector3(0, 1.31, 0.8), Color(0.35, 0.03, 0.05), false)
		# A tall cross on the wall behind the altar and a pair of eerie braziers.
		h._b(altar, Vector3(0.25, 3.0, 0.15), Vector3(0, 2.8, 0.1), IRON, false)
		h._b(altar, Vector3(1.4, 0.25, 0.15), Vector3(0, 3.5, 0.1), IRON, false)
		for sx in [-1.5, 1.5]:
			h._p(h.main._cyl(0.1, 1.2), Vector3(sx, 0.6, 1.6), h.main._mat(IRON), false, Vector3.ZERO, altar)
			_flame(h, altar, Vector3(sx, 1.3, 1.6), 0.8)
		_skull(h, altar, Vector3(0.6, 1.41, 0.8), 1.4)
		r.spots.append(altar.to_global(Vector3(-0.6, 1.33, 0.8)))
	# Broken pews facing the altar.
	for i in 3:
		var c: Vector2 = h._floor(r, Vector2(2.6, 0.7), 0.8)
		if c != Vector2.INF:
			h._b(h, Vector3(2.6, 0.08, 0.5), Vector3(c.x, r.y0 + 0.5, c.y), WOOD)
			h._b(h, Vector3(2.6, 0.5, 0.06), Vector3(c.x, r.y0 + 0.8, c.y - 0.22), WOOD, false)
			for lx in [-1.1, 1.1]:
				h._b(h, Vector3(0.08, 0.5, 0.45), Vector3(c.x + lx, r.y0 + 0.25, c.y), WOOD, false)
	for i in 2:
		_sarcophagus(h, r)
	_candles(h, r)
	_candles(h, r)


static func _burial_chamber(h, r) -> void:
	for i in randi_range(2, 3):
		if randf() < 0.5:
			_coffin(h, r)
		else:
			_sarcophagus(h, r)
	_candles(h, r)
	_skull_stack(h, r)


static func _embalming_room(h, r) -> void:
	var c: Vector2 = h._floor(r, Vector2(2.4, 1.1), 0.6)
	if c != Vector2.INF:
		h._b(h, Vector3(2.2, 0.15, 0.9), Vector3(c.x, r.y0 + 0.9, c.y), STONE.lightened(0.15))
		for lx in [-1.0, 1.0]:
			h._b(h, Vector3(0.2, 0.85, 0.7), Vector3(c.x + lx, r.y0 + 0.425, c.y), STONE, false)
		h._b(h, Vector3(1.6, 0.14, 0.55), Vector3(c.x, r.y0 + 1.04, c.y), Color(0.75, 0.72, 0.6), false)
		r.spots.append(Vector3(c.x + 0.8, r.y0 + 1.02, c.y))
	var m: Node3D = h._wall(r, 2.2, 0.6)
	if m != null:
		h._b(m, Vector3(2.2, 0.9, 0.5), Vector3(0, 0.45, 0.28), WOOD)
		h._b(m, Vector3(2.2, 0.06, 0.5), Vector3(0, 1.3, 0.28), WOOD, false)
		var glass: Material = h._glow_material(Color(0.4, 0.9, 0.5, 0.7))
		for i in 6:
			h._p(h.main._cyl(0.1, 0.3), Vector3(-0.9 + i * 0.36, 1.48, 0.28), glass, false, Vector3.ZERO, m)
		r.spots.append(m.to_global(Vector3(0.9, 0.94, 0.28)))
	_candles(h, r)
	for i in 2:
		_skull_stack(h, r)


static func _bone_room(h, r) -> void:
	for i in 2:
		_bones(h, r)
	_candles(h, r)


# The sealed tomb: a great sarcophagus on a glowing rune circle. The crypt's locked-away bottle is here.
static func _tomb(h, r) -> void:
	var inner: Rect2 = r.interior()
	var c := inner.get_center()
	var rune: StandardMaterial3D = h._glow_material(GHOST)
	rune.emission_energy_multiplier = 0.9
	for k in 3:
		var ring := TorusMesh.new()
		ring.inner_radius = 1.6 + k * 0.5
		ring.outer_radius = 1.65 + k * 0.5
		h._p(ring, Vector3(c.x, r.y0 + 0.02, c.y), rune, false)
	h._b(h, Vector3(2.6, 0.9, 1.3), Vector3(c.x, r.y0 + 0.45, c.y), STONE)
	var lid: Node3D = h._b(h, Vector3(2.8, 0.2, 1.45), Vector3(c.x + 0.3, r.y0 + 1.0, c.y), STONE.lightened(0.1))
	lid.rotation.y = 0.15
	r.used.append(Rect2(c - Vector2(2.0, 1.4), Vector2(4.0, 2.8)))
	r.spots.append(Vector3(c.x - 0.7, r.y0 + 1.22, c.y))
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			var p := Vector2(c.x + sx * (inner.size.x / 2.0 - 1.0), c.y + sy * (inner.size.y / 2.0 - 1.0))
			var rect := Rect2(p - Vector2(0.5, 0.5), Vector2(1.0, 1.0))
			if h._free(r, rect):
				r.used.append(rect)
				h._p(h.main._cyl(0.25, 1.1), Vector3(p.x, r.y0 + 0.55, p.y), h.main._mat(STONE.lightened(0.1)), true)
				_flame(h, h, Vector3(p.x, r.y0 + 1.25, p.y), 0.9)
	for i in 3:
		_skull_stack(h, r)
	for i in 2:
		_sarcophagus(h, r, false)
