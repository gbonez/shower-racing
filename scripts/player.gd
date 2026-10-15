extends CharacterBody3D

signal clicked(target: Node)  # target is null when nothing interactive is aimed at
signal right_clicked

const SPEED := 3.0
const GRAVITY := 20.0
const JUMP_SPEED := 8.0
const MOUSE_SENS := 0.003
const REACH := 3.5

var frozen := false
var target: Node = null
var camera: Camera3D
var speed_mult := 1.0
var can_jump := false  # only on the cloud level
var flipped := false  # walking on the ceiling: gravity and the view are turned upside down
var roll := 0.0
var noclip := false  # debug fly mode: no gravity, no collision
var jump_mult := 1.0

func _ready() -> void:
	floor_snap_length = 0.3
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.3
	capsule.height = 1.8
	shape.shape = capsule
	add_child(shape)

	camera = Camera3D.new()
	camera.position = Vector3(0, 0.7, 0)
	add_child(camera)
	camera.make_current()


func _unhandled_input(event: InputEvent) -> void:
	if frozen:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var turn := -1.0 if cos(roll) >= 0.0 else 1.0
		rotation.y += turn * event.relative.x * MOUSE_SENS
		camera.rotation.x = clampf(camera.rotation.x - event.relative.y * MOUSE_SENS, -1.5, 1.5)
	elif event is InputEventMouseButton and event.pressed:
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			if event.button_index == MOUSE_BUTTON_LEFT:
				Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		elif event.button_index == MOUSE_BUTTON_LEFT:
			clicked.emit(target)
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			right_clicked.emit()


func _physics_process(delta: float) -> void:
	roll = move_toward(roll, PI if flipped else 0.0, delta * 5.0)
	rotation.z = roll
	up_direction = Vector3.DOWN if flipped else Vector3.UP

	if noclip:
		var fly := Vector3.ZERO
		if not frozen:
			var fwd := float(Input.is_physical_key_pressed(KEY_W)) - float(Input.is_physical_key_pressed(KEY_S))
			var side := float(Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_A))
			var lift := float(Input.is_physical_key_pressed(KEY_SPACE)) - float(Input.is_physical_key_pressed(KEY_CTRL))
			fly = camera.global_transform.basis * Vector3(side, 0, -fwd) + Vector3.UP * lift
		var fly_speed := 14.0 if Input.is_physical_key_pressed(KEY_SHIFT) else 6.0
		velocity = Vector3.ZERO
		global_position += fly * fly_speed * delta
		_update_target()
		return

	var dir := Vector3.ZERO
	if not frozen:
		var forward := float(Input.is_physical_key_pressed(KEY_W)) - float(Input.is_physical_key_pressed(KEY_S))
		var strafe := float(Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_A))
		dir = transform.basis * Vector3(strafe, 0, -forward)
		dir.y = 0.0
		dir = dir.normalized()
	var speed := SPEED * speed_mult
	velocity.x = dir.x * speed
	velocity.z = dir.z * speed
	if is_on_floor():
		velocity.y = 0.0
	else:
		velocity.y += (GRAVITY if flipped else -GRAVITY) * delta
	if can_jump and not frozen and is_on_floor() and Input.is_physical_key_pressed(KEY_SPACE):
		velocity.y = (-JUMP_SPEED if flipped else JUMP_SPEED) * jump_mult
	move_and_slide()
	_update_target()


func cast_ray(from: Vector3, to: Vector3) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [get_rid()]
	return get_world_3d().direct_space_state.intersect_ray(query)


func aim_hit(reach := REACH) -> Dictionary:
	var from := camera.global_position
	return cast_ray(from, from - camera.global_transform.basis.z * reach)


func _update_target() -> void:
	target = null
	if frozen:
		return
	var hit := aim_hit()
	if hit.is_empty():
		return
	var collider: Object = hit["collider"]
	if collider.has_meta("kind"):
		target = collider as Node
