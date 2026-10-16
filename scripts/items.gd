class_name Items
extends RefCounted

# Small pickups built from primitives: energy drink, scrub brush, loofa, keys, spring shoes, bottle radar,
# crowns, the beach bucket, the doghouse bone and the multiplayer household items.

const KEY_COLOR := Color(0.85, 0.65, 0.2)


static func _mat(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	if color.a < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return m


static func _part(parent: Node3D, mesh: Mesh, pos: Vector3, color: Color, rot_deg := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _mat(color)
	mi.position = pos
	mi.rotation_degrees = rot_deg
	parent.add_child(mi)
	return mi


static func _box(size: Vector3) -> BoxMesh:
	var m := BoxMesh.new()
	m.size = size
	return m


static func _cyl(top: float, bottom: float, height: float) -> CylinderMesh:
	var m := CylinderMesh.new()
	m.top_radius = top
	m.bottom_radius = bottom
	m.height = height
	return m


# `rest` is how far the item's origin sits above the surface it lies on. Items sit on physics layer 2:
# the player walks straight through them, but clicks (ray casts) still hit them. Hitboxes are 25% bigger
# than the models so they are easier to aim at.
const HIT_SCALE := 1.25
const ITEM_LAYER := 2


static func _body(item: String, label: String, rest: float, hit_size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = ITEM_LAYER
	body.collision_mask = 0
	body.set_meta("kind", "item")
	body.set_meta("item", item)
	body.set_meta("label", label)
	body.set_meta("rest", rest)
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = hit_size * HIT_SCALE
	cs.shape = shape
	body.add_child(cs)
	return body


static func energy_drink() -> StaticBody3D:
	var body := _body("energy", "Energy drink", 0.06, Vector3(0.1, 0.16, 0.1))
	_part(body, _cyl(0.033, 0.033, 0.12), Vector3.ZERO, Color(0.1, 0.9, 0.35))
	_part(body, _cyl(0.0345, 0.0345, 0.04), Vector3.ZERO, Color(0.05, 0.05, 0.08))
	_part(body, _cyl(0.03, 0.033, 0.012), Vector3(0, 0.066, 0), Color(0.8, 0.82, 0.85))
	_part(body, _cyl(0.033, 0.03, 0.012), Vector3(0, -0.066, 0), Color(0.8, 0.82, 0.85))
	return body


static func brush() -> StaticBody3D:
	var body := _body("brush", "Scrub brush", 0.03, Vector3(0.22, 0.08, 0.1))
	_part(body, _box(Vector3(0.18, 0.024, 0.04)), Vector3(-0.02, 0.012, 0), Color(0.55, 0.38, 0.2))
	_part(body, _box(Vector3(0.1, 0.03, 0.05)), Vector3(0.05, -0.012, 0), Color(0.95, 0.85, 0.3))
	_part(body, _box(Vector3(0.1, 0.012, 0.05)), Vector3(0.05, 0.005, 0), Color(0.5, 0.35, 0.2))
	return body


# Every key looks the same; a fake one only shows its colours when it snaps in a lock.
static func key(fake := false) -> StaticBody3D:
	var color := KEY_COLOR
	var body := _body("key", "Key", 0.02, Vector3(0.14, 0.05, 0.08))
	body.set_meta("fake", fake)
	var ring := TorusMesh.new()
	ring.inner_radius = 0.014
	ring.outer_radius = 0.032
	_part(body, ring, Vector3(-0.055, 0, 0), color)
	_part(body, _box(Vector3(0.1, 0.012, 0.014)), Vector3(0.025, 0, 0), color)
	_part(body, _box(Vector3(0.014, 0.012, 0.03)), Vector3(0.065, 0, 0.012), color)
	_part(body, _box(Vector3(0.012, 0.012, 0.022)), Vector3(0.045, 0, 0.011), color)
	return body


# The vault's key: larger than the others, golden and faintly glowing.
static func golden_key() -> StaticBody3D:
	var gold := Color(1.0, 0.8, 0.15)
	var body := _body("key", "Golden key", 0.04, Vector3(0.3, 0.08, 0.14))
	body.set_meta("golden", true)
	body.set_meta("fake", false)
	var ring := TorusMesh.new()
	ring.inner_radius = 0.03
	ring.outer_radius = 0.07
	var parts: Array[MeshInstance3D] = []
	parts.append(_part(body, ring, Vector3(-0.12, 0, 0), gold))
	parts.append(_part(body, _box(Vector3(0.22, 0.024, 0.03)), Vector3(0.04, 0, 0), gold))
	parts.append(_part(body, _box(Vector3(0.03, 0.024, 0.07)), Vector3(0.14, 0, 0.03), gold))
	parts.append(_part(body, _box(Vector3(0.026, 0.024, 0.05)), Vector3(0.1, 0, 0.025), gold))
	parts.append(_part(body, _box(Vector3(0.04, 0.03, 0.05)), Vector3(-0.03, 0, 0), gold.darkened(0.2)))
	var gem := SphereMesh.new()
	gem.radius = 0.02
	gem.height = 0.04
	var gem_mi := _part(body, gem, Vector3(-0.12, 0.015, 0), Color(0.85, 0.1, 0.2))
	for mi in parts:
		mi.material_override = _mat(gold.darkened(0.2))
	gem_mi.material_override = _mat(Color(0.6, 0.08, 0.14))
	return body


# The king's crown: scrub brush +100% and movement +50% for good.
static func crown() -> StaticBody3D:
	var gold := Color(1.0, 0.78, 0.15)
	var body := _body("crown", "King's crown", 0.1, Vector3(0.36, 0.26, 0.36))
	var band := _part(body, _cyl(0.17, 0.15, 0.1), Vector3.ZERO, gold)
	band.material_override = _glow(gold, 0.5)
	for i in 6:
		var a := i * TAU / 6.0
		var tip := _part(body, _cyl(0.0, 0.035, 0.12), Vector3(cos(a) * 0.16, 0.11, sin(a) * 0.16), gold)
		tip.material_override = _glow(gold, 0.5)
		var jewel := SphereMesh.new()
		jewel.radius = 0.022
		jewel.height = 0.044
		var colors: Array[Color] = [Color(0.85, 0.1, 0.2), Color(0.15, 0.3, 0.95), Color(0.1, 0.75, 0.3)]
		var jewel_mi := _part(body, jewel, Vector3(cos(a) * 0.17, 0.0, sin(a) * 0.17), colors[i % 3])
		jewel_mi.material_override = _glow(colors[i % 3], 0.8)
	return body


# The crypt crown: the king's crown's ghostly twin, found only on the sarcophagus in the crypt's tomb.
# Same bonus: scrub brush +100% and movement +50% for good.
static func crypt_crown() -> StaticBody3D:
	var bone := Color(0.85, 0.9, 0.82)
	var green := Color(0.3, 1.0, 0.55)
	var body := _body("crypt_crown", "Crypt crown", 0.1, Vector3(0.36, 0.28, 0.36))
	var band := _part(body, _cyl(0.17, 0.15, 0.1), Vector3.ZERO, bone)
	band.material_override = _glow(bone, 0.3)
	for i in 5:
		var a := i * TAU / 5.0
		var spike := _part(body, _cyl(0.0, 0.03, 0.15), Vector3(cos(a) * 0.16, 0.12, sin(a) * 0.16), bone)
		spike.material_override = _glow(bone, 0.3)
		var eye := SphereMesh.new()
		eye.radius = 0.02
		eye.height = 0.04
		var eye_mi := _part(body, eye, Vector3(cos(a) * 0.17, 0.0, sin(a) * 0.17), green)
		eye_mi.material_override = _glow(green, 1.4)
	var gem := SphereMesh.new()
	gem.radius = 0.035
	gem.height = 0.07
	var gem_mi := _part(body, gem, Vector3(0, 0.1, 0.17), green)
	gem_mi.material_override = _glow(green, 2.0)
	return body


# A rare, extra-scratchy scrub: soap strokes +50% for good.
static func loofa() -> StaticBody3D:
	var body := _body("loofa", "Loofa", 0.05, Vector3(0.32, 0.1, 0.12))
	_part(body, _cyl(0.045, 0.045, 0.28), Vector3.ZERO, Color(0.85, 0.78, 0.45), Vector3(0, 0, 90))
	for i in 5:
		_part(body, _cyl(0.049, 0.049, 0.02), Vector3(-0.11 + i * 0.055, 0, 0), Color(0.62, 0.55, 0.3), Vector3(0, 0, 90))
	var strap := TorusMesh.new()
	strap.inner_radius = 0.03
	strap.outer_radius = 0.038
	_part(body, strap, Vector3(0.15, 0.03, 0), Color(0.3, 0.7, 0.4), Vector3(0, 90, 0))
	return body


# Shows every bottle through the walls until it is picked up.
static func bottle_radar() -> StaticBody3D:
	var body := _body("radar", "Bottle radar", 0.06, Vector3(0.18, 0.14, 0.18))
	_part(body, _box(Vector3(0.16, 0.04, 0.16)), Vector3(0, -0.04, 0), Color(0.12, 0.13, 0.16))
	var screen := _part(body, _cyl(0.07, 0.07, 0.012), Vector3(0, -0.012, 0), Color(0.1, 0.9, 0.4))
	screen.material_override = _glow(Color(0.1, 0.9, 0.4), 0.9)
	for blip in [Vector3(0.025, 0.0, 0.02), Vector3(-0.03, 0.0, -0.025), Vector3(0.0, 0.0, -0.045)]:
		var dot := SphereMesh.new()
		dot.radius = 0.008
		dot.height = 0.016
		var dot_mi := _part(body, dot, blip + Vector3(0, 0.0, 0), Color.WHITE)
		dot_mi.material_override = _glow(Color(0.8, 1.0, 0.85), 2.5)
	_part(body, _cyl(0.004, 0.004, 0.14), Vector3(0.06, 0.04, -0.06), Color(0.7, 0.72, 0.75))
	return body


# --- Multiplayer items: household things that help or hinder the other racers ---

static func banana_peel() -> StaticBody3D:
	var body := _body("banana", "Banana peel", 0.03, Vector3(0.28, 0.08, 0.2))
	var yellow := Color(0.98, 0.85, 0.15)
	_part(body, _box(Vector3(0.12, 0.025, 0.06)), Vector3.ZERO, yellow)
	for side in [-1.0, 1.0]:
		_part(body, _box(Vector3(0.1, 0.02, 0.05)), Vector3(side * 0.095, 0.015, 0.0), yellow, Vector3(0, 0, -side * 25.0))
		_part(body, _box(Vector3(0.07, 0.015, 0.05)), Vector3(side * 0.04, 0.0, side * 0.06), yellow.darkened(0.1), Vector3(0, side * 40.0, 0))
	_part(body, _box(Vector3(0.025, 0.025, 0.04)), Vector3(0.15, 0.03, 0), Color(0.35, 0.22, 0.1))
	return body


static func bath_bomb() -> StaticBody3D:
	var body := _body("bathbomb", "Bubble bath bomb", 0.05, Vector3(0.14, 0.14, 0.14))
	var ball := SphereMesh.new()
	ball.radius = 0.055
	ball.height = 0.11
	_part(body, ball, Vector3.ZERO, Color(0.95, 0.5, 0.8))
	var band := TorusMesh.new()
	band.inner_radius = 0.052
	band.outer_radius = 0.06
	_part(body, band, Vector3.ZERO, Color(1.0, 0.9, 0.95))
	for k in 5:
		var a := k * TAU / 5.0
		var spark := SphereMesh.new()
		spark.radius = 0.006
		spark.height = 0.012
		var mi := _part(body, spark, Vector3(cos(a) * 0.04, 0.03 + 0.012 * k, sin(a) * 0.04), Color.WHITE)
		mi.material_override = _glow(Color(1, 1, 1), 2.0)
	return body


static func ice_tray() -> StaticBody3D:
	var body := _body("icecubes", "Ice cube tray", 0.03, Vector3(0.3, 0.08, 0.2))
	_part(body, _box(Vector3(0.26, 0.025, 0.18)), Vector3(0, -0.01, 0), Color(0.55, 0.6, 0.7))
	for gx in 3:
		for gz in 2:
			_part(body, _box(Vector3(0.065, 0.05, 0.065)), Vector3(-0.08 + gx * 0.08, 0.025, -0.04 + gz * 0.08), Color(0.75, 0.92, 1.0, 0.75))
	return body


static func box_fan() -> StaticBody3D:
	var body := _body("fan", "Box fan", 0.14, Vector3(0.34, 0.34, 0.16))
	var grey := Color(0.7, 0.72, 0.75)
	_part(body, _box(Vector3(0.3, 0.02, 0.1)), Vector3(0, 0.15, 0), grey)
	_part(body, _box(Vector3(0.3, 0.02, 0.1)), Vector3(0, -0.15, 0), grey)
	_part(body, _box(Vector3(0.02, 0.3, 0.1)), Vector3(0.15, 0, 0), grey)
	_part(body, _box(Vector3(0.02, 0.3, 0.1)), Vector3(-0.15, 0, 0), grey)
	for k in 3:
		_part(body, _box(Vector3(0.24, 0.05, 0.01)), Vector3.ZERO, Color(0.35, 0.55, 0.85), Vector3(0, 0, k * 60.0))
	_part(body, _cyl(0.035, 0.035, 0.06), Vector3.ZERO, Color(0.25, 0.25, 0.3), Vector3(90, 0, 0))
	return body


static func warm_towel() -> StaticBody3D:
	var body := _body("towel", "Warm towel", 0.05, Vector3(0.3, 0.1, 0.22))
	var colors: Array[Color] = [Color(0.95, 0.55, 0.6), Color(0.98, 0.95, 0.9), Color(0.95, 0.55, 0.6)]
	for i in 3:
		_part(body, _box(Vector3(0.26 - i * 0.02, 0.03, 0.2)), Vector3(0, -0.04 + i * 0.032, 0), colors[i], Vector3(0, i * 6.0, 0))
	return body


# The doghouse's guard dog can be distracted with this.
static func bone() -> StaticBody3D:
	var body := _body("bone", "Bone", 0.03, Vector3(0.3, 0.08, 0.12))
	var white := Color(0.96, 0.94, 0.86)
	_part(body, _cyl(0.014, 0.014, 0.2), Vector3.ZERO, white, Vector3(0, 0, 90))
	for end in [-0.1, 0.1]:
		for z in [-0.016, 0.016]:
			var knob := SphereMesh.new()
			knob.radius = 0.022
			knob.height = 0.044
			_part(body, knob, Vector3(end, 0, z), white)
	return body


static func chest() -> StaticBody3D:
	var body := _body("chest", "Treasure chest", 0.15, Vector3(0.6, 0.4, 0.4))
	var wood := Color(0.5, 0.3, 0.14)
	var gold := Color(0.95, 0.75, 0.2)
	_part(body, _box(Vector3(0.5, 0.22, 0.32)), Vector3(0, -0.05, 0), wood)
	_part(body, _cyl(0.16, 0.16, 0.5), Vector3(0, 0.1, 0), wood.lightened(0.08), Vector3(0, 0, 90))
	for x in [-0.2, 0.2]:
		_part(body, _box(Vector3(0.04, 0.3, 0.34)), Vector3(x, 0.02, 0), gold)
	_part(body, _box(Vector3(0.06, 0.08, 0.04)), Vector3(0, 0.0, 0.17), gold)
	return body


static func bucket() -> StaticBody3D:
	var body := _body("bucket", "Bucket (empty)", 0.14, Vector3(0.34, 0.3, 0.34))
	_part(body, _cyl(0.16, 0.12, 0.28), Vector3.ZERO, Color(0.95, 0.4, 0.12))
	_part(body, _cyl(0.145, 0.145, 0.01), Vector3(0, 0.11, 0), Color(0.15, 0.1, 0.08))
	var handle := TorusMesh.new()
	handle.inner_radius = 0.15
	handle.outer_radius = 0.162
	_part(body, handle, Vector3(0, 0.16, 0), Color(0.45, 0.45, 0.5), Vector3(90, 0, 0))
	var water := _part(body, _cyl(0.145, 0.145, 0.012), Vector3(0, 0.125, 0), Color(0.2, 0.55, 0.95, 0.85))
	water.visible = false
	body.set_meta("water", water)
	body.set_meta("filled", false)
	return body


static func set_bucket_filled(body: Node, filled: bool) -> void:
	body.set_meta("filled", filled)
	body.set_meta("label", "Bucket (full)" if filled else "Bucket (empty)")
	(body.get_meta("water") as Node3D).visible = filled


static func spring_shoes() -> StaticBody3D:
	var body := _body("spring", "Spring shoes", 0.07, Vector3(0.3, 0.14, 0.3))
	var coil := TorusMesh.new()
	coil.inner_radius = 0.026
	coil.outer_radius = 0.04
	for side in [-1.0, 1.0]:
		var x: float = side * 0.08
		_part(body, _box(Vector3(0.1, 0.025, 0.26)), Vector3(x, -0.04, 0), Color(0.95, 0.95, 0.95))
		for i in 3:
			_part(body, coil, Vector3(x, -0.01 + i * 0.022, 0.07), Color(0.7, 0.72, 0.78))
			_part(body, coil, Vector3(x, -0.01 + i * 0.022, -0.07), Color(0.7, 0.72, 0.78))
		_part(body, _box(Vector3(0.11, 0.015, 0.26)), Vector3(x, 0.06, 0), Color(0.5, 0.5, 0.56))
		_part(body, _box(Vector3(0.1, 0.07, 0.17)), Vector3(x, 0.1, -0.03), Color(0.9, 0.2, 0.25))
		_part(body, _box(Vector3(0.1, 0.04, 0.07)), Vector3(x, 0.08, 0.1), Color(0.9, 0.2, 0.25))
	return body


static func _glow(color: Color, energy := 1.5) -> StandardMaterial3D:
	var m := _mat(color)
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = energy
	return m


# A water boiler: steel tank with a glowing furnace door. Origin is on the floor; the door faces +z.
static func boiler() -> StaticBody3D:
	var body := StaticBody3D.new()
	body.set_meta("kind", "boiler")
	body.set_meta("label", "Boiler")
	var cs := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = 0.5
	shape.height = 1.9
	cs.shape = shape
	cs.position = Vector3(0, 0.95, 0)
	body.add_child(cs)
	var steel := Color(0.5, 0.52, 0.56)
	_part(body, _cyl(0.5, 0.5, 1.7), Vector3(0, 0.85, 0), steel)
	var dome := SphereMesh.new()
	dome.radius = 0.5
	dome.height = 1.0
	_part(body, dome, Vector3(0, 1.7, 0), steel)
	_part(body, _cyl(0.08, 0.08, 1.2), Vector3(0.35, 2.3, 0), steel)
	var door := MeshInstance3D.new()
	door.mesh = _box(Vector3(0.45, 0.4, 0.06))
	door.material_override = _glow(Color(1.0, 0.35, 0.05))
	door.position = Vector3(0, 0.55, 0.5)
	body.add_child(door)
	var lamp := SphereMesh.new()
	lamp.radius = 0.05
	lamp.height = 0.1
	var lamp_mi := MeshInstance3D.new()
	lamp_mi.mesh = lamp
	lamp_mi.material_override = _glow(Color(1.0, 0.1, 0.05))
	lamp_mi.position = Vector3(0.3, 1.3, 0.45)
	body.add_child(lamp_mi)
	var glow := OmniLight3D.new()
	glow.position = Vector3(0, 1.2, 0.9)
	glow.light_color = Color(1.0, 0.35, 0.1)
	glow.omni_range = 4.5
	glow.light_energy = 0.9
	body.add_child(glow)
	return body
