extends Node3D

# The doghouse's guard dog. It is chained to a stake in the yard and lunges at anyone who comes within
# reach of the soap. A thrown bone sends it running to chew on it for a while. Its picture is the first
# file in assets/images with "dog" in the name; without one a blocky dog is built from boxes.

signal bitten
signal growled

const CHAIN := 3.2  # how far from the stake the dog can get
const RUN_SPEED := 4.2
const BITE_RANGE := 1.0
const SIGHT := 7.0  # how close to the stake someone must be for the dog to notice
const DISTRACT_SECONDS := 14.0
const HEIGHT := 0.85

var active := false
var player: Node3D
var house: Node
var stake := Vector3.ZERO  # world position of the stake, at floor level
var yard_center := Vector3.ZERO
var rest_spot := Vector3.ZERO
var distract_time := 0.0
var chew_spot := Vector3.ZERO
var bone_model: Node3D
var chain: MeshInstance3D
var visual: Node3D
var noticed := false
var bite_cooldown := 0.0
var clock := 0.0


func setup(target: Node3D, home: Node) -> void:
	player = target
	house = home
	stake = home.to_global(home.dog_stake)
	var c: Vector2 = home.yard_room.interior().get_center()
	yard_center = home.to_global(Vector3(c.x, home.yard_room.y0, c.y))
	var away := Vector3(stake.x - yard_center.x, 0, stake.z - yard_center.z).normalized()
	rest_spot = stake + Vector3(-away.z, 0, away.x) * 1.4
	global_position = rest_spot
	_build_visual()
	chain = MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.025, 0.025, 1.0)
	chain.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.4, 0.42, 0.46)
	chain.material_override = mat
	chain.top_level = true
	add_child(chain)


func _build_visual() -> void:
	var tex := AssetImages.find(["dog"])
	if tex != null:
		var sprite := Sprite3D.new()
		sprite.texture = tex
		sprite.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
		sprite.pixel_size = HEIGHT / float(tex.get_height())
		sprite.position.y = HEIGHT / 2.0
		sprite.shaded = false
		sprite.double_sided = true
		add_child(sprite)
		return
	visual = Node3D.new()
	add_child(visual)
	var fur := Color(0.55, 0.36, 0.2)
	var dark := Color(0.3, 0.18, 0.1)
	_box(Vector3(0.34, 0.32, 0.7), Vector3(0, 0.46, 0), fur)
	_box(Vector3(0.26, 0.26, 0.3), Vector3(0, 0.66, 0.42), fur)
	_box(Vector3(0.14, 0.12, 0.16), Vector3(0, 0.6, 0.62), dark)
	_box(Vector3(0.07, 0.14, 0.05), Vector3(-0.1, 0.84, 0.36), dark)
	_box(Vector3(0.07, 0.14, 0.05), Vector3(0.1, 0.84, 0.36), dark)
	_box(Vector3(0.06, 0.06, 0.3), Vector3(0, 0.62, -0.46), fur, Vector3(35, 0, 0))
	for leg in [Vector3(-0.12, 0.15, 0.24), Vector3(0.12, 0.15, 0.24), Vector3(-0.12, 0.15, -0.24), Vector3(0.12, 0.15, -0.24)]:
		_box(Vector3(0.09, 0.3, 0.09), leg, dark)
	for eye in [-0.06, 0.06]:
		_box(Vector3(0.04, 0.04, 0.02), Vector3(eye, 0.7, 0.57), Color(1.0, 0.2, 0.1))


func _box(size: Vector3, pos: Vector3, color: Color, rot_deg := Vector3.ZERO) -> void:
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mi.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mi.material_override = mat
	mi.position = pos
	mi.rotation_degrees = rot_deg
	visual.add_child(mi)


# Where someone the dog bit lands: back towards the gate, out of its reach.
func eject_position() -> Vector3:
	var away := Vector3(stake.x - yard_center.x, 0, stake.z - yard_center.z).normalized()
	return stake - away * (CHAIN + 1.8) + Vector3(0, 0.95, 0)


# A bone thrown at `at`. Returns false if it landed outside the yard or too far from the dog to notice.
func distract(at: Vector3) -> bool:
	var rel := Vector3(at.x - stake.x, 0, at.z - stake.z)
	if rel.length() > 9.0 or house.room_at(at + Vector3(0, 0.2, 0)) != house.yard_room:
		return false
	chew_spot = stake + rel.limit_length(CHAIN - 0.3)
	distract_time = DISTRACT_SECONDS
	if bone_model != null:
		bone_model.queue_free()
	bone_model = Items.bone()
	bone_model.collision_layer = 0
	get_parent().add_child(bone_model)
	bone_model.global_position = Vector3(at.x, stake.y + 0.04, at.z)
	return true


func _physics_process(delta: float) -> void:
	clock += delta
	if not active:
		return
	bite_cooldown -= delta
	var feet: Vector3 = player.global_position - Vector3(0, 0.9, 0)
	var rel := Vector3(feet.x - stake.x, 0, feet.z - stake.z)
	var in_yard: bool = house.room_at(player.global_position) == house.yard_room
	var target := rest_spot
	var speed := RUN_SPEED
	if distract_time > 0.0:
		distract_time -= delta
		target = chew_spot
		if distract_time <= 0.0 and bone_model != null:
			bone_model.queue_free()
			bone_model = null
	elif in_yard and absf(feet.y - stake.y) < 1.5 and rel.length() < CHAIN + SIGHT:
		target = stake + rel.limit_length(CHAIN)
		if not noticed:
			noticed = true
			growled.emit()
	else:
		noticed = false
		speed = 2.0
	var step := target - global_position
	step.y = 0.0
	if step.length() > 0.05:
		global_position += step.normalized() * minf(speed * delta, step.length())
		rotation.y = lerp_angle(rotation.y, atan2(step.x, step.z), minf(delta * 10.0, 1.0))
	global_position.y = stake.y + absf(sin(clock * 9.0)) * 0.04 * (1.0 if step.length() > 0.1 else 0.0)
	if distract_time <= 0.0 and bite_cooldown <= 0.0 and in_yard:
		var gap := Vector3(feet.x - global_position.x, 0, feet.z - global_position.z).length()
		if gap < BITE_RANGE and absf(feet.y - stake.y) < 1.5:
			bite_cooldown = 3.0
			bitten.emit()
	_update_chain()


func _update_chain() -> void:
	var from := stake + Vector3(0, 0.45, 0)
	var to := global_position + Vector3(0, 0.45, 0)
	var length := from.distance_to(to)
	if length < 0.05:
		chain.visible = false
		return
	chain.visible = true
	chain.global_position = (from + to) / 2.0
	chain.look_at(to, Vector3.UP if absf((to - from).normalized().y) < 0.99 else Vector3.RIGHT)
	chain.scale = Vector3(1, 1, length)
