extends "res://scripts/open_world.gd"

# Treasure hunt: a beach island in the middle of a swimmable ocean. Five chests lie on the seabed; the
# player swims out, carries one to the shore and clicks to open it. Two are empty, three hold the bottles.
# A shark patrols the water and bites swimmers, sending them back to the beach.

const OCEAN_WALL := 2.4  # island radii out to the invisible wall
const SHARK_SPEED := 1.8
const SHARK_CHASE := 2.6
const SHARK_NOTICE := 14.0
const BITE_RANGE := 1.3
const CHEST_COUNT := 5

var chests: Array[StaticBody3D] = []
var chest_homes: Array[Vector3] = []
var chest_bottle: Array[int] = []  # bottle index inside each chest, or -1 if empty
var shark: Node3D
var shark_target := Vector3.ZERO
var clock := 0.0


func height_at(x: float, z: float) -> float:
	var d := island_distance(x, z)
	var h := -maxf(d - 0.72, 0.0) * 2.2
	var land := clampf((0.8 - d) / 0.25, 0.0, 1.0)
	var clear := clampf((Vector2(x - flat_center.x, z - flat_center.y).length() - 4.0) / 3.0, 0.0, 1.0)
	h += maxf(noise.get_noise_2d(x, z), 0.0) * 1.2 * land * clear
	return maxf(h, SEABED)


func build(_kind: String) -> void:
	swim_level = SEA_LEVEL
	noise.seed = randi()
	noise.frequency = 0.08
	var center := Vector3(randf_range(-3.0, 3.0), 0.0, randf_range(3.0, 6.0))
	flat_center = Vector2(center.x, center.z)
	var sand: StandardMaterial3D = main._mat(Color(0.93, 0.84, 0.6))
	sand.cull_mode = BaseMaterial3D.CULL_DISABLED
	build_heightmap(height_at, Vector2i(101, 101), Vector2(0.0, TZ), sand)
	main._prop(main._box(Vector3(800, 0.2, 800)), Vector3(0, SEA_LEVEL - 0.1, 0), main._mat(Color(0.15, 0.45, 0.8, 0.55)), false, Vector3.ZERO, self)
	main._prop(main._box(Vector3(800, 0.2, 800)), Vector3(0, SEABED - 0.15, 0), main._mat(Color(0.75, 0.68, 0.5)), false, Vector3.ZERO, self)
	var count := 56
	for i in count:
		var a := TAU * i / count
		var p := Vector2(cos(a) * ISLAND_RADII.x, sin(a) * ISLAND_RADII.y) * OCEAN_WALL
		var tangent := Vector2(-sin(a) * ISLAND_RADII.x, cos(a) * ISLAND_RADII.y).normalized()
		_invisible_wall(Vector3(ISLAND_CENTER.x + p.x, 10, ISLAND_CENTER.y + p.y), Vector3(6.0, 20, 1.0), atan2(-tangent.y, tangent.x))
	_build_shower_rig(center, 0.0)
	var sx := center.x + randf_range(-2.0, 2.0)
	var sz := center.z + 7.0
	spawn = Vector3(sx, height_at(sx, sz) + 0.95, sz)
	_scenery(center)
	_build_chests()
	_hide_boiler_and_shark()


func _scenery(center: Vector3) -> void:
	var trunk: Material = main._mat(Color(0.5, 0.35, 0.2))
	var leaf: Material = main._mat(Color(0.2, 0.6, 0.25))
	for i in 6:
		var p := _land_point(0.7)
		if Vector2(p.x - center.x, p.z - center.z).length() < 5.0 or Vector2(p.x - spawn.x, p.z - spawn.z).length() < 3.0:
			continue
		main._prop(main._cyl(0.15, 5.0), p + Vector3(0, 2.5, 0), trunk, true, Vector3(randf_range(-4, 4), 0, randf_range(-4, 4)), self)
		for k in 7:
			var a := k * TAU / 7.0
			main._prop(main._box(Vector3(2.8, 0.06, 0.55)), p + Vector3(cos(a) * 1.3, 5.0, sin(a) * 1.3), leaf, false, Vector3(0, -rad_to_deg(a), -20), self)
	var rock: Material = main._mat(Color(0.5, 0.5, 0.52))
	for i in 6:
		main._prop(_sphere(randf_range(0.4, 1.0)), _land_point(0.95), rock, false, Vector3.ZERO, self)


func _build_chests() -> void:
	var tries := 0
	while chest_homes.size() < CHEST_COUNT and tries < 600:
		tries += 1
		var a := randf() * TAU
		var d := randf_range(1.0, 1.7)
		var p := Vector3(ISLAND_CENTER.x + cos(a) * d * ISLAND_RADII.x, 0.0, ISLAND_CENTER.y + sin(a) * d * ISLAND_RADII.y)
		p.y = height_at(p.x, p.z)
		var spaced := Vector2(p.x - spawn.x, p.z - spawn.z).length() > 8.0
		for q in chest_homes:
			if Vector2(p.x - q.x, p.z - q.z).length() < (7.0 if tries < 400 else 3.0):
				spaced = false
		if spaced:
			chest_homes.append(p)
	var slots: Array[int] = [0, 1, 2, 3, 4]
	slots.shuffle()
	chest_bottle.assign([-1, -1, -1, -1, -1])
	bottle_spots.clear()
	for bottle in 3:
		chest_bottle[slots[bottle]] = bottle
	for k in CHEST_COUNT:
		var body := Items.chest()
		body.position = chest_homes[k] + Vector3(0, float(body.get_meta("rest")), 0)
		body.rotation.y = randf() * TAU
		add_child(body)
		chests.append(body)
	for bottle in 3:
		bottle_spots.append(chest_homes[chest_bottle.find(bottle)] + Vector3(0, 0.11, 0))


func _hide_boiler_and_shark() -> void:
	var boiler_at := _land_point(0.7)
	for attempt in 30:
		boiler_at = _land_point(0.7)
		if Vector2(boiler_at.x - spawn.x, boiler_at.z - spawn.z).length() > 5.0 \
				and Vector2(boiler_at.x - flat_center.x, boiler_at.z - flat_center.y).length() > 4.0:
			break
	item_spots["boiler"] = boiler_at
	bucket_pos = boiler_at
	var tex := AssetImages.find(["shark"])
	if tex == null:
		tex = _shark_texture()
	shark = Node3D.new()
	var sprite := Sprite3D.new()
	sprite.texture = tex
	sprite.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	sprite.pixel_size = 1.6 / float(tex.get_height())
	sprite.position.y = 0.5
	sprite.shaded = false
	sprite.double_sided = true
	shark.add_child(sprite)
	add_child(shark)
	shark.position = _ocean_point()
	shark_target = _ocean_point()


func _ocean_point() -> Vector3:
	var a := randf() * TAU
	var d := randf_range(1.1, 2.2)
	return Vector3(ISLAND_CENTER.x + cos(a) * d * ISLAND_RADII.x, SEA_LEVEL, ISLAND_CENTER.y + sin(a) * d * ISLAND_RADII.y)


# A grey dorsal fin, for when there is no shark picture in the assets.
func _shark_texture() -> Texture2D:
	var img := Image.create(160, 100, false, Image.FORMAT_RGBA8)
	for y in range(5, 71):
		var t := float(y - 5) / 65.0
		for x in range(int(80.0 - 50.0 * t), int(80.0 + 40.0 * t)):
			img.set_pixel(x, y, Color(0.38, 0.42, 0.48))
	return ImageTexture.create_from_image(img)


func bind_bottle(index: int, body: PhysicsBody3D, _id: String) -> void:
	body.visible = false
	body.collision_layer = 0
	hidden_bottles[index] = body


func on_shore(pos: Vector3) -> bool:
	return height_at(pos.x, pos.z) > SEA_LEVEL + 0.05 and pos.y - 0.9 > SEA_LEVEL - 0.1


func open_chest(chest: Node, pl: Node3D) -> String:
	if not on_shore(pl.global_position):
		return ""
	var bottle := chest_bottle[chests.find(chest as StaticBody3D)]
	if bottle < 0:
		return "The chest is empty! Back into the sea for another."
	var ahead := -pl.global_transform.basis.z
	ahead.y = 0.0
	var at := pl.global_position + ahead.normalized()
	at.y = height_at(at.x, at.z) + 0.11
	unlock_bottle(bottle, at)
	return "A bottle! It's on the sand in front of you."


func _physics_process(delta: float) -> void:
	clock += delta
	if shark == null or main.player == null or not main._threats_active():
		return
	var pl: Vector3 = main.player.global_position
	var swimming := pl.y - 0.9 < SEA_LEVEL - 0.2 and island_distance(pl.x, pl.z) > 0.8
	var to := Vector3(pl.x - shark.position.x, 0, pl.z - shark.position.z)
	var chase := swimming and to.length() < SHARK_NOTICE
	if chase and to.length() < BITE_RANGE:
		_bite()
		return
	if not chase and Vector3(shark_target.x - shark.position.x, 0, shark_target.z - shark.position.z).length() < 1.0:
		shark_target = _ocean_point()
	var goal := pl if chase else shark_target
	var dir := Vector3(goal.x - shark.position.x, 0, goal.z - shark.position.z).normalized()
	var next := shark.position + dir * (SHARK_CHASE if chase else SHARK_SPEED) * delta
	if island_distance(next.x, next.z) >= 0.95:
		shark.position.x = next.x
		shark.position.z = next.z
	else:
		shark_target = _ocean_point()
	shark.position.y = SEA_LEVEL + sin(clock * 3.0) * 0.05


func _bite() -> void:
	main.say("A shark bit you! You wake up on the beach.", 4.0)
	main.player.position = spawn
	main.player.velocity = Vector3.ZERO
	var held = main.held
	if held != null and held.get_meta("item", "") == "chest":
		var k := chests.find(held as StaticBody3D)
		held.reparent(self, false)
		held.position = chest_homes[k] + Vector3(0, float(held.get_meta("rest")), 0)
		held.rotation = Vector3.ZERO
		held.scale = Vector3.ONE
		held.collision_layer = Items.ITEM_LAYER
		main.held = null
		main._update_status()
	shark.position = _ocean_point()
	shark_target = _ocean_point()
