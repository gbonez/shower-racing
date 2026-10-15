extends Node3D

enum State { IDLE, RUNNING, FINISHED }

const COLOR_NAMES: Array[String] = ["red", "orange", "yellow", "green", "blue", "purple", "cyan", "lime",
		"pink", "brown", "white", "gray"]
const BOTTLE_COLORS := {
	"red": Color(0.9, 0.1, 0.1),
	"orange": Color(1.0, 0.55, 0.05),
	"yellow": Color(0.98, 0.9, 0.1),
	"green": Color(0.1, 0.7, 0.2),
	"blue": Color(0.1, 0.25, 0.95),
	"purple": Color(0.6, 0.2, 0.85),
	"cyan": Color(0.1, 0.85, 0.9),
	"lime": Color(0.6, 0.95, 0.15),
	"pink": Color(1.0, 0.45, 0.7),
	"brown": Color(0.45, 0.28, 0.12),
	"white": Color(0.97, 0.97, 0.97),
	"gray": Color(0.5, 0.5, 0.52),
}
const SKIN_TONES: Array[Color] = [Color(0.98, 0.85, 0.73), Color(0.93, 0.8, 0.7), Color(0.87, 0.68, 0.52),
		Color(0.77, 0.56, 0.38), Color(0.62, 0.42, 0.28), Color(0.45, 0.3, 0.2), Color(0.33, 0.21, 0.14)]
const DECOY_CHANCE := 0.25
# Sizes are multiples of the minigame cell size and roughly follow real body proportions.
const BODY_PARTS: Array = [
	{"name": "Chest", "size": Vector2(300, 180)},
	{"name": "Back", "size": Vector2(300, 240)},
	{"name": "Left Side", "size": Vector2(110, 240)},
	{"name": "Right Side", "size": Vector2(110, 240)},
	{"name": "Left Arm", "size": Vector2(80, 300)},
	{"name": "Right Arm", "size": Vector2(80, 300)},
	{"name": "Left Leg", "size": Vector2(120, 360)},
	{"name": "Right Leg", "size": Vector2(120, 360)},
]
const PlayerScript := preload("res://scripts/player.gd")
const MiniGame := preload("res://scripts/scalp_minigame.gd")
const HELD_POS := Vector3(0.25, -0.25, -0.5)
const HELD_ROT := Vector3(-10, 25, 8)
const HELD_SCALE := 1.3
const SHOWER_SPAWN_CHANCE := 0.7  # for a bathroom bottle: shower vs elsewhere in the bathroom
const HOUSE_SPAWN_CHANCE := 0.5  # for a free bottle: elsewhere in the house vs in the bathroom
const WALL_INSET := 0.03  # keeps wall-mounted shower parts off the tile overlay
const FLASH_POS := Vector3(-0.3, -0.27, -0.55)
const FLASHLIGHT_CHANCE := 0.5  # templates without a basement; basement and maze always get one
const CLOSET_FLASHLIGHT_CHANCE := 0.7  # when the plan has a closet, how often the flashlight is in one
const HouseScript := preload("res://scripts/house.gd")
const OpenWorld := preload("res://scripts/open_world.gd")
const RunnerBottle := preload("res://scripts/runner_bottle.gd")
const SlidingPuzzle := preload("res://scripts/sliding_puzzle.gd")
const ENERGY_CHANCE := 0.25  # per kitchen or closet
const ENERGY_SECONDS := 30.0
const ENERGY_BOOST := 1.33
const BRUSH_CHANCE := 0.25  # per bedroom or closet
const BRUSH_BONUS := 0.33
const BOILER_SECONDS := 60.0  # of running hot water per boiler start
const GIANT_SCALE := 4.0
const TANK_FILLS := 3
const PORTAL_MAX_HOPS := 3  # how many times the run-away bathroom door relocates in total
const PORTAL_COUNT := 8
const DARK_TELEPORT_SECONDS := 5.0
const CLOUD_JUMP := 2.2360679  # sqrt(5): five times the normal jump height
const ITEM_MULT := {"none": 0.0, "low": 0.4, "regular": 1.0, "crazy": 4.0}
const RULE_DEFAULTS := {"run_bottles": false, "run_shower": false, "need_boiler": false,
		"item_freq": "regular", "keys": 0, "no_fake_keys": false}
const SudsBackground := preload("res://scripts/suds_background.gd")
const FORCE_TEMPLATE := ""  # set to a GameState.TEMPLATES key to skip the random pick
const FORCE_SEED := 0  # set to a non-zero number to replay a layout; 0 picks a new seed each launch

var state := State.IDLE
var puzzle: Control  # the tomb door's sliding puzzle while it is open
var crown_speed := 1.0  # the king's crown makes you 50% faster for good
var order: Array[String] = []  # the three product colours, in the order they must be used
var decoy_id := ""  # colour of the decoy bottle, or "" when this level has none
var skin_color := Color(0.93, 0.8, 0.7)
var elapsed := 0.0
var next_index := 0
var message_time := 0.0

var player: PlayerScript
var showers: Array[Dictionary] = []  # {rect, y, pivot, water}; every bathroom shares one on/off state
var held: PhysicsBody3D
var bob_time := 0.0
var bob_amount := 0.0
var hud: CanvasLayer
var minigame: MiniGame
var timer_label: Label
var hint_label: Label
var message_label: Label
var status_label: Label
var house: HouseScript
var template := "bathroom"
var requested_template := ""  # what was asked for, even if planning fell back to bathroom-only
var run_seed := 0
var show_controls := false
var is_paused := false
var pause_layer: CanvasLayer
var win_layer: CanvasLayer
var free_cam: Camera3D
var free_yaw := 0.0
var free_pitch := 0.0
var timer_mode := "shower"  # when the timer starts: "load", "door" or "shower"
var timer_started := false
var mp_race := 0
var mp_spectating := false
var mp_panel: MpPanel
var race_label: Label
var blind_overlay: ColorRect
var blind_amount := 0.0
var mesh_layers := 1  # visual layer for new meshes; basement meshes use 2 so house lights skip them
var bottles: Array[PhysicsBody3D] = []
var runners: Array[RunnerBottle] = []
var is_open_world := false  # cloud walk and beach: no house, bathroom or maze
var is_giant := false
var open_world: OpenWorld
var energy_time := 0.0
var brush_scale := 1.0
var heat_charge := 0.0  # seconds of hot water left (boiler room)
var water_flowing := false
var tank_level := 0
var effect_label: Label
var safe_pos := Vector3.ZERO
var safe_timer := 0.0
var in_bath := true  # run-away shower: the player is inside the bathroom
var bath_portal: Node3D  # the bathroom's own door mount
var bath_leaf: Node  # and its door leaf
var portal_current := -1
var portal_hops := 0
var portal_visited: Array[int] = []  # door slots the bathroom's door has stood in
var rules: Dictionary = RULE_DEFAULTS.duplicate()
var needs_boiler := false
var runner_bottles := false
var dark_time := 0.0
var ambient_base := 0.4
var glow_on := false
var flashlight: SpotLight3D
var has_flashlight := false
var flash_auto := false  # debug: behaves like the old always-equipped flashlight
var flash_model: Node3D
var flash_lens: StandardMaterial3D
var spot_pools: Array = []
var env: Environment
var dark_amount := 0.0
var was_dark := false
var door_wall := 0
var door_along := 0.0

# Layout, generated each run. Walls: 0 = +z, 1 = -z, 2 = +x, 3 = -x.
var room_w := 6.0
var room_d := 6.0
var sx := 1
var sz := -1
var stall_min := Vector2.ZERO
var stall_max := Vector2.ZERO
var stall_walls: Array[Dictionary] = []  # tiled walls inside the stall: {wall, min, max}
var wall_items: Array[Dictionary] = []  # things mounted on stall walls: {wall, along, y, hw, hh}
var used_rects: Array[Rect2] = []  # floor footprints (xz plane) already taken
var shower_spots: Array[Vector3] = []  # possible bottle positions inside the stall
var room_spots: Array[Vector3] = []  # possible bottle positions elsewhere in the bathroom


func _ready() -> void:
	if MP.active and not MP.current_race().is_empty():
		var race := MP.current_race()
		GameState.start_multiplayer(race["template"], int(race["seed"]), str(race.get("seed_text", "")))
		mp_race = MP.race_index()
		timer_mode = str(MP.settings()["timer_start"])
		for key in RULE_DEFAULTS:
			if MP.settings().has(key):
				rules[key] = MP.settings()[key]
		MP.state_changed.connect(_on_mp_state)
	elif GameState.mode == "free":
		for key in RULE_DEFAULTS:
			rules[key] = GameState.rules.get(key, RULE_DEFAULTS[key])
		timer_mode = GameState.free_timer
	if GameState.seed_value == 0:
		GameState.seed_value = FORCE_SEED if FORCE_SEED != 0 else randi_range(1, 999999)
	run_seed = GameState.seed_value
	seed(run_seed)
	_roll_products()
	_generate_layout()
	_setup_house()
	_init_timer_mode()
	if is_open_world:
		_build_sky()
		_build_open_world()
	else:
		_build_environment()
		_build_room()
		_build_shower()
		_build_fixtures()
		house.build()
		if is_giant:
			house.apply_giant(GIANT_SCALE)
		if house.sealed:
			house.build_portals(PORTAL_COUNT)
			for i in house.portals.size():
				_set_slot_active(i, false)
		_spawn_keys()
	_build_bottles()
	_build_flashlight_item()
	_spawn_items()
	_build_player()
	_build_hud()
	_update_status()
	_say(_intro_message(), 6.0)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


# Which three colours are needed (and in what order), whether there is a decoy, and whose skin it is.
func _roll_products() -> void:
	var names := COLOR_NAMES.duplicate()
	names.shuffle()
	order.clear()
	for i in 3:
		order.append(names[i])
	decoy_id = names[3] if randf() < DECOY_CHANCE else ""
	skin_color = SKIN_TONES.pick_random()


func _intro_message() -> String:
	if needs_boiler and template != "beach" and template != "cloud_walk":
		return "The water is cold. Find the boiler before showering!"
	match template:
		"beach":
			return "Find the bucket, fill the tank with ocean water, then turn on the shower!"
		"boiler_room":
			return "The water is cold. Find the boiler before showering!"
		"cloud_walk":
			return "Jump across the clouds (Space) and find the soap and the shower!"
		"upside_down":
			return "The house is upside down. Walk on the ceiling!"
		"giant_house":
			return "Everything is huge! Only the bathroom door opens; the others you can walk under."
	return "Find the shower handle and turn it to start!"


func _process(delta: float) -> void:
	if timer_started and state != State.FINISHED and (not is_paused or MP.active):
		elapsed += delta
	timer_label.text = _format_time(elapsed)
	_update_freecam(delta)

	if is_instance_valid(player.target):
		hint_label.text = player.target.get_meta("label")
	elif held != null:
		hint_label.text = "Left click: Apply | Right click: Put Down" if held.get_meta("kind") == "bottle" \
				else "Left click: Use | Right click: Put Down"
	else:
		hint_label.text = ""

	_update_held(delta)
	_update_effects(delta)
	if not is_open_world:
		_update_darkness(delta)

	if message_time > 0.0:
		message_time -= delta
		if message_time <= 0.0:
			message_label.text = ""


func _unhandled_input(event: InputEvent) -> void:
	if free_cam != null and not is_paused and event is InputEventMouseMotion \
			and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		free_yaw -= event.relative.x * 0.003
		free_pitch = clampf(free_pitch - event.relative.y * 0.003, -1.5, 1.5)
		free_cam.rotation = Vector3(free_pitch, free_yaw, 0)
		return
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	if event.physical_keycode == KEY_ESCAPE:
		if win_layer != null:
			return
		if event.shift_pressed:
			_toggle_freecam()
		else:
			_toggle_pause()
		return
	if is_paused or win_layer != null:
		return
	if MP.active:
		match event.physical_keycode:
			KEY_F:
				_toggle_flashlight()
			KEY_ENTER:
				if mp_spectating and Net.is_host:
					MP.end_race_now()
		return
	match event.physical_keycode:
		KEY_SLASH:
			if minigame != null:
				minigame.complete_now()
		KEY_PERIOD:
			glow_on = not glow_on
			for b in bottles:
				_refresh_bottle(b)
			_say("Debug: bottle glow %s" % ("on" if glow_on else "off"))
		KEY_F:
			_toggle_flashlight()
		KEY_BRACKETRIGHT:
			flash_auto = true
			_equip_flashlight()
			if was_dark:
				_set_flashlight(true)
			_say("Debug: flashlight equipped")
		KEY_BRACKETLEFT:
			show_controls = not show_controls
			status_label.visible = show_controls
		KEY_N:
			if event.shift_pressed:
				player.noclip = not player.noclip
				_say("Debug: noclip %s (WASD fly, Space up, Ctrl down, Shift fast)" % ("on" if player.noclip else "off"))
		KEY_COMMA:
			var names := GameState.TEMPLATES.keys()
			GameState.template = names[(names.find(requested_template) + 1) % names.size()]
			get_tree().reload_current_scene()


# Dims the ambient light underground; the flashlight is something the player has to find.
func _update_darkness(delta: float) -> void:
	var dark := house.is_dark_at(player.position)
	dark_amount = move_toward(dark_amount, 1.0 if dark else 0.0, delta * 1.5)
	env.ambient_light_energy = lerpf(ambient_base, 0.1, dark_amount)
	var crypt_fog := template == "crypt"  # a thin green mist hangs in the catacombs
	env.fog_enabled = crypt_fog or dark_amount > 0.01
	env.fog_density = maxf(0.03 * dark_amount, 0.02 if crypt_fog else 0.0)
	env.fog_light_color = Color(0.05, 0.14, 0.09) if crypt_fog else Color.BLACK
	blind_amount = move_toward(blind_amount, 1.0 if dark and not has_flashlight else 0.0, delta * 2.0)
	blind_overlay.color.a = blind_amount
	var seeing := has_flashlight and flashlight.visible
	if dark and not seeing:
		dark_time += delta
		if dark_time >= DARK_TELEPORT_SECONDS and house.basement_top != Vector3.INF:
			dark_time = 0.0
			player.position = house.to_global(house.basement_top)
			player.velocity = Vector3.ZERO
			_say("It was too dark... you scrambled back up to the top of the stairs.", 5.0)
	else:
		dark_time = 0.0
	if dark == was_dark:
		return
	was_dark = dark
	if dark and not has_flashlight:
		_say("You can't see anything. Find the flashlight to see down here.", 6.0)
	elif has_flashlight and flash_auto:
		_set_flashlight(dark)


# --- Flashlight ---

func _toggle_flashlight() -> void:
	if not has_flashlight:
		_say("You don't have a flashlight yet.")
		return
	_set_flashlight(not flashlight.visible)


func _set_flashlight(on: bool) -> void:
	flashlight.visible = on
	flash_lens.emission_enabled = on
	_update_status()


func _equip_flashlight() -> void:
	if has_flashlight:
		return
	has_flashlight = true
	flash_model = Node3D.new()
	flash_model.position = FLASH_POS
	flash_model.scale = Vector3.ONE * HELD_SCALE
	player.camera.add_child(flash_model)
	flash_lens = _flash_visual(flash_model, true)
	flashlight.position = FLASH_POS + Vector3(0, 0, -0.2)
	_update_status()


# Builds the flashlight model along local -z; returns the lens material so it can glow when on.
func _flash_visual(parent: Node3D, xray: bool) -> StandardMaterial3D:
	var body_mat := _mat(Color(0.12, 0.12, 0.14))
	var head_mat := _mat(Color(0.7, 0.72, 0.75))
	var lens_mat := _mat(Color(1.0, 0.95, 0.7))
	lens_mat.emission = Color(1.0, 0.95, 0.6)
	lens_mat.emission_energy_multiplier = 2.0
	var mats: Array[StandardMaterial3D] = [body_mat, head_mat, lens_mat]
	if xray:
		for i in mats.size():
			mats[i].no_depth_test = true
			mats[i].render_priority = i
	_prop(_cyl(0.03, 0.2), Vector3.ZERO, body_mat, false, Vector3(90, 0, 0), parent)
	_prop(_cyl(0.045, 0.06), Vector3(0, 0, -0.12), head_mat, false, Vector3(90, 0, 0), parent)
	_prop(_cyl(0.04, 0.01), Vector3(0, 0, -0.155), lens_mat, false, Vector3(90, 0, 0), parent)
	return lens_mat


# Always spawns on basement and maze layouts; never in the bathroom. Prefers somewhere upstairs.
func _build_flashlight_item() -> void:
	if is_open_world:
		return
	var chance := 0.0
	if house.has_room_type("basement"):
		chance = 1.0
	elif template != "bathroom":
		chance = FLASHLIGHT_CHANCE
	if randf() >= chance:
		return
	var open := spot_pools.filter(func(p): return not p["spots"].is_empty() and p["type"] != "bathroom2" and p["level"] >= 0)
	var upstairs := open.filter(func(p): return p["level"] >= 1)
	var candidates := upstairs if not upstairs.is_empty() else open
	var closets := open.filter(func(p): return p["type"] == "closet")
	if not closets.is_empty() and randf() < CLOSET_FLASHLIGHT_CHANCE:
		candidates = closets
	if candidates.is_empty():
		return
	var pos := _pop_random(candidates.pick_random()["spots"])
	var body := StaticBody3D.new()
	body.position = pos - Vector3(0, 0.075, 0)
	body.rotation.y = randf() * TAU
	body.set_meta("kind", "flashlight")
	body.set_meta("label", "Flashlight")
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.12, 0.12, 0.36)
	cs.shape = shape
	body.add_child(cs)
	add_child(body)
	_flash_visual(body, false)


func _on_pit_entered(body: Node3D) -> void:
	if body != player:
		return
	player.position = house.maze_return
	player.velocity = Vector3.ZERO
	_say("You fell into a pit and woke up back at the start of the maze...", 5.0)


# --- Game logic ---

func _on_clicked(target: Node) -> void:
	if held != null:
		_use_held(target)
	elif target != null:
		_interact(target)


func _interact(target: Node) -> void:
	match String(target.get_meta("kind")):
		"handle":
			_use_handle()
		"door":
			if target.has_meta("permanent"):
				_say("The tomb door stays open.")
			elif target.has_meta("stuck"):
				_say("This door is far too heavy for someone your size.")
			elif target.has_meta("puzzle") and target.has_meta("locked"):
				_open_puzzle(target)
			elif target.has_meta("golden") and target.has_meta("locked"):
				_say("The golden door is locked. It needs a special golden key.")
			elif target.has_meta("locked"):
				_say("The door is locked. Find a key.")
			else:
				house.toggle_door(target)
				if timer_mode == "door" and not timer_started and target.has_meta("bath_door"):
					timer_started = true
					elapsed = 0.0
		"bottle", "item":
			_pick_up(target as PhysicsBody3D)
		"flashlight":
			_equip_flashlight()
			target.queue_free()
			_say("You found the flashlight! Press F to toggle it.", 5.0)
		"boiler":
			heat_charge = BOILER_SECONDS
			_say("The boiler rumbles to life: %d seconds of hot water once the shower runs!" % int(BOILER_SECONDS), 5.0)
		"ocean":
			_say("Salty. You need something to carry the water in.")
		"tank":
			_say("The tank needs ocean water. Bring it in a bucket.")


func _use_held(target: Node) -> void:
	if String(held.get_meta("kind")) == "bottle":
		if target == null:
			_try_apply()
		else:
			_say("Put down the %s you're holding first." % held.get_meta("label"))
		return
	match String(held.get_meta("item")):
		"energy":
			energy_time = ENERGY_SECONDS
			player.speed_mult = crown_speed * ENERGY_BOOST
			_discard_held("Glug glug! You feel fast for %d seconds." % int(ENERGY_SECONDS))
		"brush":
			brush_scale += BRUSH_BONUS
			_discard_held("You scrub up. Your soap strokes are bigger for good!")
		"key":
			_use_key(target)
		"bucket":
			_use_bucket(target)
		"crown":
			brush_scale += 1.0
			crown_speed = 1.5
			player.speed_mult = crown_speed * (ENERGY_BOOST if energy_time > 0.0 else 1.0)
			_discard_held("You put on the king's crown! Soap strokes are 100% bigger and you move 50% faster for good.")


func _discard_held(message: String) -> void:
	var item := held
	held = null
	item.queue_free()
	_say(message)
	_update_status()


func _use_key(target: Node) -> void:
	var golden: bool = held.get_meta("golden", false)
	if target == null or String(target.get_meta("kind")) != "door":
		_say("Click a locked door to use the key. Right click puts it down.")
	elif not target.has_meta("locked") or not target.has_meta("pivot"):
		_say("That door isn't locked.")
	elif target.has_meta("puzzle"):
		_say("A key won't open this. Its lock is a puzzle.")
	elif target.has_meta("golden") != golden:
		_say("This key doesn't fit the golden lock." if target.has_meta("golden") else "This key is far too big for an ordinary lock.")
	elif held.get_meta("fake", false):
		_discard_held("The key snaps in half! It was a fake.")
	else:
		target.remove_meta("locked")
		target.set_meta("label", "Open door")
		_discard_held("Click! The door is unlocked.")
		house.toggle_door(target)


func _use_bucket(target: Node) -> void:
	var kind := String(target.get_meta("kind")) if target != null else ""
	var filled: bool = held.get_meta("filled")
	if kind == "ocean":
		if filled:
			_say("The bucket is already full.")
		else:
			Items.set_bucket_filled(held, true)
			_say("You scoop up some ocean water.")
	elif kind == "tank":
		if not filled:
			_say("The bucket is empty. Fill it in the ocean first.")
		elif tank_level >= TANK_FILLS:
			_say("The tank is already full.")
		else:
			Items.set_bucket_filled(held, false)
			tank_level += 1
			open_world.set_tank_level(tank_level)
			if tank_level >= TANK_FILLS:
				_say("The tank is full! Turn on the shower.")
			else:
				_say("Tank %d/%d. Go back for more water." % [tank_level, TANK_FILLS])
	else:
		_say("Fill the bucket in the ocean, then pour it into the tank. Right click puts it down.")


func _shower_floor_y(pos: Vector3) -> float:
	for s in showers:
		var floor_y: float = s["y"]
		if pos.y > floor_y - 0.5 and pos.y < floor_y + 2.5 \
				and (s["rect"] as Rect2).has_point(Vector2(pos.x, pos.z)):
			return floor_y
	return NAN


func _in_shower(pos: Vector3) -> bool:
	return not is_nan(_shower_floor_y(pos))


func _pick_up(body: PhysicsBody3D) -> void:
	body.collision_layer = 0
	body.reparent(player.camera, false)
	body.position = HELD_POS
	body.rotation_degrees = HELD_ROT
	body.scale = Vector3.ONE * HELD_SCALE
	held = body
	if body in runners:
		runners.erase(body)
		(body as RunnerBottle).calm()
	_refresh_bottle(body)
	_say("Picked up the %s." % body.get_meta("label"))
	_update_status()


func _on_right_clicked() -> void:
	if held == null:
		return
	var bottle := held
	var pos := _find_drop_position()
	bottle.reparent(self, false)
	bottle.position = pos
	bottle.rotation = Vector3.ZERO
	bottle.scale = Vector3.ONE
	bottle.collision_layer = 1
	held = null
	_refresh_bottle(bottle)
	_update_status()


# Held bottles draw over the scene so they never clip into walls; the glow debug option does the same
# for every bottle. Render priority keeps the bottle's parts in order without depth testing.
func _refresh_bottle(bottle: PhysicsBody3D) -> void:
	if String(bottle.get_meta("kind")) != "bottle":
		return
	var xray := glow_on or bottle == held
	var priority := 0
	for part in bottle.get_children():
		if part is MeshInstance3D:
			_xray_mesh(part as MeshInstance3D, xray, priority)
		else:
			for child in part.get_children():
				if child is MeshInstance3D:
					_xray_mesh(child as MeshInstance3D, xray, priority)
		priority += 1


func _xray_mesh(mi: MeshInstance3D, xray: bool, priority: int) -> void:
	var m := mi.material_override as StandardMaterial3D
	m.no_depth_test = xray
	m.render_priority = priority if xray else 0
	m.emission_enabled = glow_on
	m.emission = m.albedo_color
	m.emission_energy_multiplier = 2.0


func _can_rest_on(hit: Dictionary) -> bool:
	var collider: Object = hit["collider"]
	return Vector3(hit["normal"]).y > 0.7 \
			and not collider.has_meta("kind") and not collider.has_meta("no_drop")


# Bottle origin sits 0.11 above its base.
func _find_drop_position() -> Vector3:
	var rest := float(held.get_meta("rest", 0.11))
	var pos: Vector3
	var hit := player.aim_hit(3.0)
	if not hit.is_empty() and _can_rest_on(hit):
		pos = Vector3(hit["position"]) + Vector3(0, rest, 0)
	else:
		var from := player.camera.global_position
		var forward := -player.global_transform.basis.z
		var reach := 0.9
		var wall_hit := player.cast_ray(from, from + forward * reach)
		if not wall_hit.is_empty():
			reach = maxf(0.2, from.distance_to(Vector3(wall_hit["position"])) - 0.15)
		var above := from + forward * reach
		var floor_hit := player.cast_ray(above, above + Vector3(0, -3, 0))
		if not floor_hit.is_empty() and _can_rest_on(floor_hit):
			pos = Vector3(floor_hit["position"]) + Vector3(0, rest, 0)
		else:
			var base_y := 0.0 if player.flipped else player.position.y - 0.9
			pos = Vector3(above.x, base_y + rest, above.z)
	if not is_open_world and not is_giant:
		pos = house.clamp_to_rooms(pos, player.position)
	var floor_y := _shower_floor_y(pos)
	if not is_nan(floor_y) and pos.y - floor_y > 0.0 and pos.y - floor_y < 0.2:
		pos.y = floor_y + 0.14  # on top of the shower tray
	return pos


func _update_held(delta: float) -> void:
	if held == null and flash_model == null:
		return
	var moving := Vector2(player.velocity.x, player.velocity.z).length() > 0.1
	bob_amount = move_toward(bob_amount, 1.0 if moving else 0.0, delta * 5.0)
	if moving:
		bob_time += delta * 9.0
	var sway := Vector3(0, sin(Time.get_ticks_msec() / 1000.0 * 1.5) * 0.004, 0)
	var bob := Vector3(cos(bob_time * 0.5) * 0.02, sin(bob_time) * 0.025, 0) * bob_amount
	if held != null:
		held.position = HELD_POS + bob + sway
	if flash_model != null:
		flash_model.position = FLASH_POS + Vector3(-bob.x, bob.y, 0) + sway
		flashlight.position = flash_model.position + Vector3(0, 0, -0.2)


func _set_showers(on: bool) -> void:
	water_flowing = on
	for s in showers:
		s["water"].emitting = on
		s["pivot"].rotation_degrees.z = 90.0 if on else 0.0


func register_shower(rect: Rect2, floor_y: float, pivot: Node3D, spray: CPUParticles3D) -> void:
	showers.append({"rect": rect, "y": floor_y, "pivot": pivot, "water": spray})


func _use_handle() -> void:
	match state:
		State.IDLE:
			if template == "beach" and tank_level < TANK_FILLS:
				_say("The tank isn't full yet (%d/%d). Fill it with ocean water first." % [tank_level, TANK_FILLS], 4.0)
				return
			if needs_boiler and heat_charge <= 0.0:
				_say("The water is freezing. Fire up the boiler first!", 4.0)
				return
			state = State.RUNNING
			if timer_mode == "shower":
				timer_started = true
				elapsed = 0.0
			_set_showers(true)
			_say("Shower on! Apply the %s product first." % order[0])
		State.RUNNING:
			if next_index < order.size():
				if needs_boiler and not water_flowing:
					if heat_charge > 0.0:
						_set_showers(true)
						_say("Hot water is back on!")
					else:
						_say("Still cold. Fire up the boiler first!")
				else:
					_say("Apply all the products before turning off the shower!")
			else:
				state = State.FINISHED
				_set_showers(false)
				timer_label.add_theme_color_override("font_color", Color(0.4, 1.0, 0.4))
				_say("Shower off! Final time: %s" % _format_time(elapsed), 1.0e9)
				if MP.active:
					_mp_finish()
				else:
					get_tree().create_timer(1.5).timeout.connect(_show_win_screen)
	_update_status()


func _try_apply() -> void:
	var id: String = held.get_meta("id")
	match state:
		State.IDLE:
			_say("Turn on the shower first!")
		State.RUNNING:
			if not _in_shower(player.position):
				_say("Step into the shower to apply product!")
				return
			if not water_flowing:
				_say("The water is cold! Reheat the boiler and turn the handle again.")
				return
			if held.get_meta("decoy", false):
				_open_minigame(id)
				return
			var index := order.find(id)
			if index == next_index:
				_open_minigame(id)
			elif index < next_index:
				_say("You already used the %s product." % id)
			else:
				_say("Wrong order! Use the %s product next." % order[next_index])


# The tomb door's lock is a sliding puzzle; solving it opens the door for good.
func _open_puzzle(leaf: Node) -> void:
	if puzzle != null:
		return
	var game := SlidingPuzzle.new()
	hud.add_child(game)
	game.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	game.solved.connect(_on_puzzle_solved.bind(leaf))
	game.closed.connect(_close_puzzle)
	puzzle = game
	_update_player_lock()


func _close_puzzle() -> void:
	if puzzle != null:
		puzzle.queue_free()
		puzzle = null
	_update_player_lock()


func _on_puzzle_solved(leaf: Node) -> void:
	await get_tree().create_timer(0.8).timeout
	_close_puzzle()
	leaf.remove_meta("locked")
	leaf.remove_meta("puzzle")
	leaf.set_meta("permanent", true)
	leaf.set_meta("label", "Open tomb door")
	house.toggle_door(leaf)
	_say("The stones grind apart and the tomb door slides open for good.", 5.0)


# Boxes come in different sizes, in steps of the minigame's cell size.
func _varied(box: Vector2) -> Vector2:
	var scaled := Vector2(box.x * randf_range(0.75, 1.25), box.y * randf_range(0.75, 1.25))
	return Vector2(clampf(snappedf(scaled.x, 10.0), 60.0, 420.0), clampf(snappedf(scaled.y, 10.0), 60.0, 420.0))


func _open_minigame(id: String) -> void:
	var game := MiniGame.new()
	game.brush_radius = 22.0 * brush_scale
	game.skin_color = skin_color
	hud.add_child(game)
	game.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if id != decoy_id and order.find(id) == order.size() - 1:
		var parts: Array = []
		for part in BODY_PARTS:
			parts.append({"name": part["name"], "size": _varied(part["size"])})
		parts.shuffle()
		game.setup(BOTTLE_COLORS[id], "Apply %s product to your body" % id, parts)
	else:
		var scalp := [{"name": "Scalp", "size": _varied(Vector2(360, 360))}]
		game.setup(BOTTLE_COLORS[id], "Apply %s product to the scalp" % id, scalp)
	game.completed.connect(_on_minigame_completed.bind(id))
	minigame = game
	_update_player_lock()


func _on_minigame_completed(id: String) -> void:
	minigame.queue_free()
	minigame = null
	_update_player_lock()
	if id == decoy_id:
		next_index = 0
		_say("That was a decoy bottle! The shower starts over: begin again with the %s product." % order[0], 6.0)
		_update_status()
		return
	next_index += 1
	if next_index >= order.size():
		_say("All products applied! Turn the shower handle to turn it off.", 6.0)
	else:
		_say("%s done! Next: %s." % [id.capitalize(), order[next_index]])
	_update_status()


func _update_status() -> void:
	var lines: Array[String] = []
	lines.append("WASD move | Mouse look | Left click pick up / apply | Right click put down | F flashlight | Esc pause | [ hide this")
	var seed_label := GameState.seed_text if GameState.seed_text != "" else str(run_seed)
	lines.append("Layout: %s (seed %s)" % [GameState.TEMPLATES[template], seed_label])
	if GameState.mode == "story":
		lines.append("Story level %d of %d" % [GameState.story_index + 1, GameState.story_order().size()])
	lines.append("Shower: %s" % ["OFF" if state != State.RUNNING else "ON"])
	lines.append("Flashlight: %s" % (("ON" if flashlight.visible else "OFF") if has_flashlight else "not found"))
	lines.append("Holding: %s" % (held.get_meta("label") if held != null else "nothing"))
	status_label.text = "\n".join(lines)


func _show_win_screen() -> void:
	if win_layer != null:
		return
	win_layer = CanvasLayer.new()
	win_layer.layer = 10
	add_child(win_layer)
	var box := _bubble_screen(win_layer)
	_update_player_lock()

	box.add_child(_win_label("Squeaky clean!", 84, 16))
	box.add_child(_win_label("Time %s" % _format_time(elapsed), 44, 10))
	var level_text: String = GameState.TEMPLATES[template]
	var seed_label := GameState.seed_text if GameState.seed_text != "" else str(run_seed)
	if GameState.mode == "story":
		level_text = "Story level %d of %d: %s" % [GameState.story_index + 1, GameState.story_order().size(), level_text]
		if not GameState.has_next():
			level_text += "\nStory complete!"
	box.add_child(_win_label("Level template: %s" % level_text, 28, 8))
	box.add_child(_win_label("Level seed: %s" % seed_label, 28, 8))
	if GameState.has_next():
		_win_button(box, "Next Level", Color(0.75, 1.0, 0.85), _on_next_level)
	_win_button(box, "Restart Level", Color(1.0, 0.95, 0.7), _on_restart_level)
	_win_button(box, "Main Menu", Color(0.85, 0.8, 1.0), _on_main_menu)


# Full-screen bubble backdrop with a centred column for labels and buttons.
func _bubble_screen(layer: CanvasLayer) -> VBoxContainer:
	var backdrop := SudsBackground.new()
	layer.add_child(backdrop)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	var center := CenterContainer.new()
	layer.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	center.add_child(box)
	return box


# Menus and the freecam lock the player; otherwise the mouse is captured for looking.
func _update_player_lock() -> void:
	var menu_open := minigame != null or puzzle != null or is_paused or win_layer != null
	player.frozen = menu_open or free_cam != null
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if menu_open else Input.MOUSE_MODE_CAPTURED


func _toggle_pause() -> void:
	if is_paused:
		pause_layer.queue_free()
		pause_layer = null
		is_paused = false
		_update_player_lock()
		return
	is_paused = true
	pause_layer = CanvasLayer.new()
	pause_layer.layer = 20
	add_child(pause_layer)
	var box := _bubble_screen(pause_layer)
	box.add_child(_win_label("Paused", 84, 16))
	_win_button(box, "Continue", Color(0.75, 1.0, 0.85), _toggle_pause)
	if MP.active:
		_win_button(box, "Leave Race", Color(0.85, 0.8, 1.0), _on_main_menu)
	else:
		_win_button(box, "Restart Level", Color(1.0, 0.95, 0.7), _on_restart_level)
		_win_button(box, "Quit to Menu", Color(0.85, 0.8, 1.0), _on_main_menu)
	_update_player_lock()


func _toggle_freecam() -> void:
	if is_paused or (MP.active and not mp_spectating):
		return
	if free_cam == null:
		free_cam = Camera3D.new()
		add_child(free_cam)
		free_cam.global_transform = player.camera.global_transform
		free_yaw = player.rotation.y
		free_pitch = player.camera.rotation.x
		free_cam.make_current()
		_say("Freecam: WASD move, Space / Ctrl up and down, Shift fast, Shift+Esc to exit", 5.0)
	else:
		player.camera.make_current()
		free_cam.queue_free()
		free_cam = null
		_say("Freecam off")
	_update_player_lock()


func _update_freecam(delta: float) -> void:
	if free_cam == null or is_paused:
		return
	var cam_basis := free_cam.global_transform.basis
	var dir := Vector3.ZERO
	if Input.is_physical_key_pressed(KEY_W):
		dir -= cam_basis.z
	if Input.is_physical_key_pressed(KEY_S):
		dir += cam_basis.z
	if Input.is_physical_key_pressed(KEY_D):
		dir += cam_basis.x
	if Input.is_physical_key_pressed(KEY_A):
		dir -= cam_basis.x
	if Input.is_physical_key_pressed(KEY_SPACE):
		dir += Vector3.UP
	if Input.is_physical_key_pressed(KEY_CTRL):
		dir -= Vector3.UP
	var speed := 18.0 if Input.is_physical_key_pressed(KEY_SHIFT) else 6.0
	free_cam.global_position += dir.normalized() * speed * delta


func _win_label(text: String, font_size: int, outline: int) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_override("font", Ui.font())
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", Color.WHITE)
	l.add_theme_color_override("font_outline_color", Ui.NAVY)
	l.add_theme_constant_override("outline_size", outline)
	return l


func _win_button(parent: Control, text: String, tint: Color, action: Callable) -> void:
	var b := BubbleButton.new()
	b.text = text
	b.tint = tint
	b.custom_minimum_size = Vector2(320, 84)
	b.pressed.connect(action)
	parent.add_child(b)


func _on_next_level() -> void:
	GameState.advance()
	get_tree().reload_current_scene()


func _on_restart_level() -> void:
	get_tree().reload_current_scene()


func _on_main_menu() -> void:
	if MP.active:
		MP.leave()
	get_tree().change_scene_to_file("res://scenes/menu.tscn")


# --- Multiplayer ---

func _init_timer_mode() -> void:
	if timer_mode == "load" or (timer_mode == "door" and template in ["bathroom", "upside_down", "cloud_walk", "beach"]):
		timer_started = true


# Per-frame upkeep for pickups and level rules: energy boost, boiler heat, cloud falls, the HUD line.
func _update_effects(delta: float) -> void:
	var dt := 0.0 if (is_paused and not MP.active) else delta
	if energy_time > 0.0:
		energy_time -= dt
		if energy_time <= 0.0:
			player.speed_mult = crown_speed
			_say("The energy drink wore off.")
	if needs_boiler and water_flowing and state == State.RUNNING:
		heat_charge = maxf(0.0, heat_charge - dt)
		if heat_charge <= 0.0:
			_set_showers(false)
			_say("The hot water ran out! Go reheat the boiler.", 5.0)
	if template == "cloud_walk":
		_update_cloud_safety(dt)
	if template == "upside_down":
		var zone := house.room_at(player.position)
		if zone != null:
			player.flipped = zone != house.rooms[0]
	_update_runaway(dt)
	var parts: Array[String] = []
	if needs_boiler:
		parts.append("Hot water: %ds" % ceili(heat_charge) if heat_charge > 0.0 else "Hot water: cold")
	if template == "beach":
		parts.append("Tank: %d/%d" % [tank_level, TANK_FILLS])
	if energy_time > 0.0:
		parts.append("Speed boost: %ds" % ceili(energy_time))
	if brush_scale > 1.0:
		parts.append("Soap size +%d%%" % roundi((brush_scale - 1.0) * 100.0))
	if crown_speed > 1.0:
		parts.append("Crown: speed +%d%%" % roundi((crown_speed - 1.0) * 100.0))
	effect_label.text = "   ".join(parts)


func _update_cloud_safety(delta: float) -> void:
	safe_timer -= delta
	if player.is_on_floor() and safe_timer <= 0.0:
		safe_timer = 0.4
		safe_pos = player.position
	if player.position.y < open_world.respawn_height:
		player.position = safe_pos + Vector3(0, 0.5, 0)
		player.velocity = Vector3.ZERO
		_say("You fell! Back to the last cloud you stood on.")


# --- Run-away shower ---

# The bathroom's door is an ordinary door. Walking through it while open drops the player at the
# bathroom's current door in the house; the moment they step out, that door moves to another room
# (at most PORTAL_MAX_HOPS times in total), keeping its open/closed state.

func _in_doorway(mount: Node3D, leaf: Node) -> bool:
	if not leaf.get_meta("open"):
		return false
	var local := mount.to_local(player.global_position)
	return absf(local.x) < 0.5 and local.z > -0.2 and local.z < 0.55 and local.y > -0.2 and local.y < 2.0


func _exit_bathroom() -> void:
	in_bath = false
	if timer_mode == "door" and not timer_started:
		timer_started = true
		elapsed = 0.0
	if portal_current < 0:
		portal_current = randi() % house.portals.size()
		portal_visited.append(portal_current)
	var slot: Dictionary = house.portals[portal_current]
	_set_slot_active(portal_current, true)
	house.set_door_open(slot["leaf"], true)
	_land_at(slot["mount"], 1.7)
	if portal_hops < PORTAL_MAX_HOPS:
		_relocate_portal()


func _enter_bathroom() -> void:
	in_bath = true
	_set_slot_active(portal_current, false)
	house.set_door_open(bath_leaf, true)
	_land_at(bath_portal, 1.7)


func _land_at(mount: Node3D, distance: float) -> void:
	player.position = mount.to_global(Vector3(0, 0.95, distance))
	player.rotation.y = mount.global_rotation.y + PI
	player.camera.rotation.x = 0.0
	player.velocity = Vector3.ZERO


# Moves the bathroom's door to another room, preferring rooms it hasn't been in, and keeps the door's
# open/closed state.
func _relocate_portal() -> void:
	var options: Array[int] = []
	for pass_index in 3:
		for i in house.portals.size():
			var mount: Node3D = house.portals[i]["mount"]
			var flat := Vector2(mount.global_position.x - player.position.x, mount.global_position.z - player.position.z)
			var fresh := not portal_visited.has(i)
			var far := flat.length() > 6.0
			if i != portal_current and (pass_index == 2 or (fresh and (far or pass_index == 1))):
				options.append(i)
		if not options.is_empty():
			break
	if options.is_empty():
		return
	var was_open: bool = house.portals[portal_current]["leaf"].get_meta("open")
	_set_slot_active(portal_current, false)
	portal_current = options.pick_random()
	portal_visited.append(portal_current)
	_set_slot_active(portal_current, true)
	house.set_door_open(house.portals[portal_current]["leaf"], was_open)
	portal_hops += 1


# A hidden door is invisible and has no collision.
func _set_slot_active(index: int, active: bool) -> void:
	var mount: Node3D = house.portals[index]["mount"]
	mount.visible = active
	mount.process_mode = Node.PROCESS_MODE_INHERIT if active else Node.PROCESS_MODE_DISABLED


func _update_runaway(_delta: float) -> void:
	if not house.sealed or house.portals.is_empty() or bath_leaf == null:
		return
	if in_bath:
		if _in_doorway(bath_portal, bath_leaf):
			_exit_bathroom()
		return
	var slot: Dictionary = house.portals[portal_current]
	var mount: Node3D = slot["mount"]
	if _in_doorway(mount, slot["leaf"]):
		_enter_bathroom()


func _mp_finish() -> void:
	MP.report_finish(elapsed)
	_mp_spectate()


# After finishing, or when the race is ended for them, players fly around and watch the standings.
func _mp_spectate() -> void:
	if mp_spectating:
		return
	mp_spectating = true
	mp_panel.visible = true
	_toggle_freecam()


func _on_mp_state() -> void:
	match MP.phase():
		"racing":
			if MP.race_index() != mp_race:
				get_tree().reload_current_scene()
		"between":
			_mp_spectate()
		"final":
			_mp_spectate()
			_show_mp_final()


func _show_mp_final() -> void:
	if win_layer != null:
		return
	win_layer = CanvasLayer.new()
	win_layer.layer = 10
	add_child(win_layer)
	var box := _bubble_screen(win_layer)
	box.add_child(_win_label("Final results", 64, 14))
	var lines := MP.leaderboard_lines()
	for i in mini(lines.size(), 6):
		box.add_child(_win_label(lines[i], 28, 8))
	if lines.size() > 6:
		box.add_child(_win_label("+%d more" % (lines.size() - 6), 22, 6))
	_win_button(box, "Return to Lobby", Color(0.75, 1.0, 0.85), _on_mp_lobby)
	_win_button(box, "Quit to Menu", Color(0.85, 0.8, 1.0), _on_main_menu)
	_update_player_lock()


func _on_mp_lobby() -> void:
	if Net.is_host:
		MP.return_to_lobby()
	get_tree().change_scene_to_file("res://scenes/lobby.tscn")


func _say(text: String, duration := 3.0) -> void:
	message_label.text = text
	message_time = duration


func _format_time(t: float) -> String:
	return "%02d:%05.2f" % [floori(t / 60.0), fmod(t, 60.0)]


# --- Layout helpers ---

func _wall_normal(wall: int) -> Vector3:
	match wall:
		0:
			return Vector3(0, 0, -1)
		1:
			return Vector3(0, 0, 1)
		2:
			return Vector3(-1, 0, 0)
	return Vector3(1, 0, 0)


func _wall_point(wall: int, along: float) -> Vector3:
	match wall:
		0:
			return Vector3(along, 0, room_d / 2.0)
		1:
			return Vector3(along, 0, -room_d / 2.0)
		2:
			return Vector3(room_w / 2.0, 0, along)
	return Vector3(-room_w / 2.0, 0, along)


func _footprint(wall: int, along: float, width: float, depth: float) -> Rect2:
	match wall:
		0:
			return Rect2(along - width / 2.0, room_d / 2.0 - depth, width, depth)
		1:
			return Rect2(along - width / 2.0, -room_d / 2.0, width, depth)
		2:
			return Rect2(room_w / 2.0 - depth, along - width / 2.0, depth, width)
	return Rect2(-room_w / 2.0, along - width / 2.0, depth, width)


func _rect_free(r: Rect2) -> bool:
	for used in used_rects:
		if r.intersects(used):
			return false
	return true


# Returns {wall, along} or an empty dictionary if nothing fits.
func _place_on_wall(width: float, depth: float, clearance: float) -> Dictionary:
	for attempt in 40:
		var wall := randi_range(0, 3)
		var length := room_w if wall < 2 else room_d
		var half := length / 2.0 - width / 2.0 - 0.2
		if half <= 0.0:
			continue
		var along := randf_range(-half, half)
		var rect := _footprint(wall, along, width, depth)
		if _rect_free(rect.grow(clearance)):
			used_rects.append(rect)
			return {"wall": wall, "along": along}
	return {}


# Picks a free spot on one of the stall's tiled walls. Returns {wall, along, y} or empty.
func _pick_wall_slot(hw: float, hh: float, y_min: float, y_max: float) -> Dictionary:
	for attempt in 30:
		var w: Dictionary = stall_walls.pick_random()
		var lo: float = w["min"] + hw + 0.3
		var hi: float = w["max"] - hw - 0.3
		if hi < lo:
			continue
		var wall: int = w["wall"]
		var along := randf_range(lo, hi)
		var y := randf_range(y_min, y_max)
		var free := true
		for item in wall_items:
			var item_hw: float = item["hw"]
			var item_hh: float = item["hh"]
			if int(item["wall"]) == wall \
					and absf(float(item["along"]) - along) < item_hw + hw + 0.1 \
					and absf(float(item["y"]) - y) < item_hh + hh + 0.1:
				free = false
				break
		if free:
			wall_items.append({"wall": wall, "along": along, "y": y, "hw": hw, "hh": hh})
			return {"wall": wall, "along": along, "y": y}
	return {}


func _generate_layout() -> void:
	room_w = randf_range(5.0, 8.0)
	room_d = randf_range(5.0, 8.0)
	var stall_w := randf_range(1.6, minf(2.8, room_w * 0.45))
	var stall_d := randf_range(1.6, minf(2.8, room_d * 0.45))
	sx = 1 if randf() < 0.5 else -1
	sz = 1 if randf() < 0.5 else -1
	var wall_x := sx * room_w / 2.0
	var wall_z := sz * room_d / 2.0
	var x_in := wall_x - sx * stall_w
	var z_in := wall_z - sz * stall_d
	stall_min = Vector2(minf(wall_x, x_in), minf(wall_z, z_in))
	stall_max = Vector2(maxf(wall_x, x_in), maxf(wall_z, z_in))
	stall_walls = [
		{"wall": 2 if sx > 0 else 3, "min": stall_min.y, "max": stall_max.y},
		{"wall": 0 if sz > 0 else 1, "min": stall_min.x, "max": stall_max.x},
	]
	used_rects.append(Rect2(stall_min, stall_max - stall_min).grow(0.7))

	var slot := _place_on_wall(1.0, 0.9, 0.1)
	if slot.is_empty():
		slot = _place_on_wall(1.0, 0.9, 0.0)
	if slot.is_empty():
		slot = {"wall": 1 if sz > 0 else 0, "along": 0.0}
	door_wall = slot["wall"]
	door_along = slot["along"]


func _setup_house() -> void:
	template = GameState.template if GameState.template != "" else FORCE_TEMPLATE
	if template == "":
		template = GameState.TEMPLATES.keys().pick_random()
	requested_template = template
	GameState.template = template
	needs_boiler = bool(rules["need_boiler"]) or template == "boiler_room"
	house = HouseScript.new()
	house.main = self
	add_child(house)
	var bath_rect := Rect2(-room_w / 2.0 - 0.1, -room_d / 2.0 - 0.1, room_w + 0.2, room_d + 0.2)
	if not house.plan(template, bath_rect, door_wall, door_along, needs_boiler, bool(rules["run_shower"])):
		template = "bathroom"
	is_open_world = template == "cloud_walk" or template == "beach"
	is_giant = template == "giant_house"
	runner_bottles = template == "runaway_bottles" or (bool(rules["run_bottles"]) and template != "cloud_walk")

# --- Scene building ---

func _mat(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	if color.a < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return m


func _tile_material(length: float, height: float) -> StandardMaterial3D:
	var img := Image.create(16, 16, false, Image.FORMAT_RGB8)
	img.fill(Color(0.72, 0.88, 0.93))
	for i in 16:
		img.set_pixel(i, 0, Color(0.95, 0.95, 0.95))
		img.set_pixel(0, i, Color(0.95, 0.95, 0.95))
	var m := _mat(Color.WHITE)
	m.albedo_texture = ImageTexture.create_from_image(img)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	m.uv1_scale = Vector3(length / 0.4, height / 0.4, 1)
	return m


func _box(size: Vector3) -> BoxMesh:
	var m := BoxMesh.new()
	m.size = size
	return m


func _cyl(radius: float, height: float) -> CylinderMesh:
	var m := CylinderMesh.new()
	m.top_radius = radius
	m.bottom_radius = radius
	m.height = height
	return m


func _prop(mesh: PrimitiveMesh, pos: Vector3, material: Material, solid := true,
		rot_deg := Vector3.ZERO, parent: Node = null) -> Node3D:
	var root: Node3D
	if solid:
		root = StaticBody3D.new()
		var cs := CollisionShape3D.new()
		if mesh is BoxMesh:
			var box := BoxShape3D.new()
			box.size = (mesh as BoxMesh).size
			cs.shape = box
		elif mesh is CylinderMesh:
			var cyl := CylinderShape3D.new()
			cyl.radius = (mesh as CylinderMesh).top_radius
			cyl.height = (mesh as CylinderMesh).height
			cs.shape = cyl
		root.add_child(cs)
	else:
		root = Node3D.new()
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = material
	mi.layers = mesh_layers
	root.add_child(mi)
	root.position = pos
	root.rotation_degrees = rot_deg
	(parent if parent else self).add_child(root)
	return root


# Node at a wall position whose local +z points into the room.
func _mount(wall: int, along: float, y := 0.0, inset := 0.0) -> Node3D:
	var n := _wall_normal(wall)
	var m := Node3D.new()
	m.position = _wall_point(wall, along) + Vector3(0, y, 0) + n * inset
	m.rotation.y = atan2(n.x, n.z)
	add_child(m)
	return m


func _build_sky() -> void:
	env = Environment.new()
	var sky_material := ProceduralSkyMaterial.new()
	if template == "cloud_walk":
		sky_material.sky_top_color = Color(0.25, 0.5, 0.95)
		sky_material.sky_horizon_color = Color(0.75, 0.88, 1.0)
		sky_material.ground_horizon_color = Color(0.75, 0.88, 1.0)
		sky_material.ground_bottom_color = Color(0.55, 0.75, 1.0)
	else:
		sky_material.sky_top_color = Color(0.3, 0.6, 0.95)
		sky_material.sky_horizon_color = Color(0.8, 0.9, 1.0)
		sky_material.ground_horizon_color = Color(0.8, 0.9, 1.0)
		sky_material.ground_bottom_color = Color(0.8, 0.85, 0.9)
	var sky := Sky.new()
	sky.sky_material = sky_material
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 1.0
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 35, 0)
	sun.light_energy = 1.1
	sun.shadow_enabled = true
	add_child(sun)


func _build_open_world() -> void:
	open_world = OpenWorld.new()
	open_world.main = self
	add_child(open_world)
	open_world.build(template)


func _build_environment() -> void:
	env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.1, 0.1, 0.12)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color.WHITE
	env.ambient_light_energy = ambient_base
	if template == "castle":
		# Gloomy: the braziers and torches do most of the lighting.
		ambient_base = 0.2
		env.background_color = Color(0.03, 0.04, 0.1)
		env.ambient_light_color = Color(0.6, 0.62, 0.85)
		env.ambient_light_energy = ambient_base
	elif template == "crypt":
		ambient_base = 0.1
		env.background_color = Color(0.01, 0.02, 0.02)
		env.ambient_light_color = Color(0.45, 0.7, 0.55)
		env.ambient_light_energy = ambient_base
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var main_light := OmniLight3D.new()
	main_light.position = Vector3(0, 2.7, 0)
	main_light.omni_range = maxf(room_w, room_d) * 1.3
	main_light.light_energy = 1.5
	main_light.shadow_enabled = true
	main_light.light_cull_mask = 1
	add_child(main_light)

	var stall_center := (stall_min + stall_max) / 2.0
	var shower_light := OmniLight3D.new()
	shower_light.position = Vector3(stall_center.x, 2.7, stall_center.y)
	shower_light.omni_range = 4.0
	shower_light.light_energy = 1.0
	shower_light.light_cull_mask = 1
	add_child(shower_light)

	_prop(_cyl(0.25, 0.04), Vector3(0, 2.97, 0), _mat(Color(1, 1, 0.9)), false)


func _build_room() -> void:
	var wall_mat := _mat(Color(0.85, 0.92, 0.95))

	var floor_mat := _mat(Color.WHITE)
	var img := Image.create(2, 2, false, Image.FORMAT_RGB8)
	img.set_pixel(0, 0, Color(0.9, 0.9, 0.9))
	img.set_pixel(1, 1, Color(0.9, 0.9, 0.9))
	img.set_pixel(1, 0, Color(0.55, 0.7, 0.8))
	img.set_pixel(0, 1, Color(0.55, 0.7, 0.8))
	floor_mat.albedo_texture = ImageTexture.create_from_image(img)
	floor_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	floor_mat.uv1_scale = Vector3(room_w / 2.0, room_d / 2.0, 1)
	_prop(_box(Vector3(room_w + 0.2, 0.1, room_d + 0.2)), Vector3(0, -0.05, 0), floor_mat)

	_prop(_box(Vector3(room_w + 0.2, 0.04, room_d + 0.2)), Vector3(0, 2.98, 0), wall_mat)
	house.build_walls(house.rooms[0], wall_mat)


func _build_fixtures() -> void:
	var porcelain := _mat(Color(0.97, 0.97, 0.97))
	var chrome := _mat(Color(0.75, 0.78, 0.8))

	if template == "bathroom":
		var door := _mount(door_wall, door_along)
		var leaf := _prop(_box(Vector3(0.9, 2.1, 0.06)), Vector3(0, 1.05, 0.03), _mat(Color(0.5, 0.33, 0.2)), true, Vector3.ZERO, door)
		_prop(_cyl(0.03, 0.06), Vector3(0.3, 1.0, 0.08), chrome, false, Vector3(90, 0, 0), door)
		leaf.set_meta("kind", "door")
		leaf.set_meta("label", "Locked door")
		leaf.set_meta("locked", true)
	elif house.sealed:
		_build_bath_portal()
	if needs_boiler and not house.boiler_placed:
		_build_bath_boiler()

	var slot := _place_on_wall(0.5, 0.8, 0.3)
	if not slot.is_empty():
		var toilet := _mount(slot["wall"], slot["along"])
		_prop(_box(Vector3(0.5, 0.5, 0.25)), Vector3(0, 0.7, 0.125), porcelain, true, Vector3.ZERO, toilet)
		_prop(_cyl(0.22, 0.45), Vector3(0, 0.225, 0.5), porcelain, true, Vector3.ZERO, toilet)
		room_spots.append(toilet.to_global(Vector3(0, 1.06, 0.125)))

	slot = _place_on_wall(1.1, 0.6, 0.3)
	if not slot.is_empty():
		var sink := _mount(slot["wall"], slot["along"])
		_prop(_box(Vector3(1.0, 0.85, 0.5)), Vector3(0, 0.425, 0.25), _mat(Color(0.55, 0.4, 0.28)), true, Vector3.ZERO, sink)
		_prop(_box(Vector3(1.1, 0.05, 0.55)), Vector3(0, 0.875, 0.275), porcelain, true, Vector3.ZERO, sink)
		_prop(_cyl(0.25, 0.03), Vector3(0, 0.91, 0.3), _mat(Color(0.8, 0.9, 1.0)), false, Vector3.ZERO, sink)
		_prop(_cyl(0.015, 0.2), Vector3(0, 1.03, 0.08), chrome, false, Vector3.ZERO, sink)
		_prop(_box(Vector3(0.8, 0.8, 0.03)), Vector3(0, 1.7, 0.015), _mat(Color(0.7, 0.85, 0.95)), false, Vector3.ZERO, sink)
		room_spots.append(sink.to_global(Vector3(0.42, 1.01, 0.35)))
		room_spots.append(sink.to_global(Vector3(-0.42, 1.01, 0.35)))

	for attempt in 30:
		var c := Vector2(randf_range(-room_w / 2.0 + 1.2, room_w / 2.0 - 1.2),
				randf_range(-room_d / 2.0 + 1.0, room_d / 2.0 - 1.0))
		var rug := Rect2(c - Vector2(0.7, 0.45), Vector2(1.4, 0.9))
		if _rect_free(rug):
			used_rects.append(rug)
			_prop(_box(Vector3(1.4, 0.02, 0.9)), Vector3(c.x, 0.01, c.y), _mat(Color(0.9, 0.5, 0.55)), false)
			break

	var floor_count := 0
	for attempt in 60:
		if floor_count >= 5:
			break
		var p := Vector2(
			randf_range(-room_w / 2.0 + 0.5, room_w / 2.0 - 0.5),
			randf_range(-room_d / 2.0 + 0.5, room_d / 2.0 - 0.5))
		if not _rect_free(Rect2(p - Vector2(0.2, 0.2), Vector2(0.4, 0.4))):
			continue
		var spot := Vector3(p.x, 0.11, p.y)
		var far_enough := true
		for q in room_spots:
			if q.y < 0.2 and q.distance_to(spot) < 0.6:
				far_enough = false
		if far_enough:
			room_spots.append(spot)
			floor_count += 1


# The run-away shower's only way out: an ordinary door that leads into the house.
func _build_bath_portal() -> void:
	bath_portal = _mount(door_wall, door_along)
	bath_leaf = house.build_portal_door(bath_portal)


# The boiler stands against a bathroom wall when the level needs one but there is no house to hold it.
func _build_bath_boiler() -> void:
	var slot := _place_on_wall(1.1, 1.1, 0.2)
	if slot.is_empty():
		slot = _place_on_wall(1.1, 1.1, 0.0)
	if slot.is_empty():
		return
	var mount := _mount(slot["wall"], slot["along"])
	var boiler := Items.boiler()
	boiler.position = Vector3(0, 0, 0.6)
	mount.add_child(boiler)


# At least one bottle is always in the bathroom; basement and maze templates force one more down there.
func _build_bottles() -> void:
	if is_open_world:
		var open_ids := order.duplicate()
		open_ids.shuffle()
		for i in open_ids.size():
			_make_bottle(open_ids[i], open_world.bottle_spots[i])
		if decoy_id != "":
			_make_bottle(decoy_id, open_world.decoy_spot())
			bottles[bottles.size() - 1].set_meta("decoy", true)
		return
	spot_pools = _collect_pools()
	var pools := spot_pools
	var targets: Array[String] = []
	if (house.sealed or runner_bottles) and not pools.is_empty():
		# Nothing starts in the bathroom: it is sealed off, or the bottles would just run out.
		while targets.size() < order.size():
			targets.append("house")
	else:
		targets.append("bathroom")
		if house.has_room_type("maze"):
			targets.append("maze")
		elif house.has_room_type("basement"):
			targets.append("basement")
		while targets.size() < order.size():
			var outside := not pools.is_empty() and randf() < HOUSE_SPAWN_CHANCE
			targets.append("house" if outside else "bathroom")
		if (template == "castle" or template == "crypt") and not pools.is_empty():
			# Always at least two bottles outside the bathroom.
			for i in targets.size():
				if targets.count("house") >= 2:
					break
				if targets[i] == "bathroom":
					targets[i] = "house"
	if house.has_room_type("tomb"):
		# The crypt always keeps one bottle behind its tomb door.
		targets[0] = "tomb"
	var ids := order.duplicate()
	ids.shuffle()
	for i in ids.size():
		if targets[i] == "tomb":
			_make_bottle(ids[i], house.tomb_spot(), true)
		else:
			_make_bottle(ids[i], _take_spot(targets[i], pools))
	if decoy_id != "":
		var decoy_target := "house" if not pools.is_empty() and (house.sealed or runner_bottles or randf() < 0.7) else "bathroom"
		_make_bottle(decoy_id, _take_spot(decoy_target, pools))
		bottles[bottles.size() - 1].set_meta("decoy", true)


# Bottle spots per room. In the giant house only floor spots are kept (everything else is out of
# reach) and they are moved to where the scaled house puts them.
func _collect_pools() -> Array:
	var pools := house.collect_pools()
	if not is_giant:
		return pools
	var result: Array = []
	for pool in pools:
		var base_y: float = pool["room"].y0
		var spots: Array = []
		for spot: Vector3 in pool["spots"]:
			if spot.y - base_y < 0.3:
				spots.append(house.global_transform * spot)
		if not spots.is_empty():
			result.append({"type": pool["type"], "spots": spots, "level": 0, "room": pool["room"]})
	return result


func _key_count() -> int:
	var max_keys := house.lockable_doors().size()
	if max_keys == 0:
		return 0
	# 50% no keys, 25% one, 15% two, 10% three or more.
	var roll := randf()
	var count := 0
	if roll >= 0.9:
		count = randi_range(3, 5)
	elif roll >= 0.75:
		count = 2
	elif roll >= 0.5:
		count = 1
	return mini(maxi(count, int(rules["keys"])), max_keys)


# Locks some doors (any key opens any lock) and hides the keys where they can be reached without
# opening a lock. Unless disabled, a couple of fake keys are mixed in: they look the same but snap.
func _spawn_keys() -> void:
	if house.has_room_type("treasure"):
		var gold_spot := house.golden_key_spot(house.collect_pools())
		if gold_spot != Vector3.INF:
			_place_item(Items.golden_key(), gold_spot)
	var count := _key_count()
	if count == 0:
		return
	var placed := house.plan_locks(count, house.collect_pools())
	for entry in placed:
		_place_item(Items.key(), entry["spot"])
	if placed.is_empty() or bool(rules["no_fake_keys"]):
		return
	for spot in house.decoy_spots(house.collect_pools(), randi_range(0, 2)):
		_place_item(Items.key(true), spot)


# Energy drinks (kitchens, closets), scrub brushes (bedrooms, closets), the beach bucket, and on the
# cloud walk a scrub brush. The item frequency rule scales the chances.
func _spawn_items() -> void:
	var mult: float = ITEM_MULT.get(str(rules["item_freq"]), 1.0)
	if is_open_world:
		_spawn_open_items(mult)
		return
	if template == "bathroom":
		return
	if house.treasure_spot != Vector3.INF:
		var crown := Items.crown()
		crown.position = house.treasure_spot + Vector3(0, float(crown.get_meta("rest")), 0)
		add_child(crown)
	for pool in spot_pools:
		var spots: Array = pool["spots"]
		var kind: String = pool["type"]
		if not spots.is_empty() and (kind == "kitchen" or kind == "closet") and randf() < ENERGY_CHANCE * mult:
			_place_item(Items.energy_drink(), _pop_random(spots))
		if not spots.is_empty() and (kind == "bedroom" or kind == "closet") and randf() < BRUSH_CHANCE * mult:
			_place_item(Items.brush(), _pop_random(spots))


func _spawn_open_items(mult: float) -> void:
	if template == "beach":
		var bucket := Items.bucket()
		bucket.position = open_world.bucket_pos + Vector3(0, float(bucket.get_meta("rest")), 0)
		add_child(bucket)
	if needs_boiler:
		var boiler := Items.boiler()
		boiler.position = open_world.item_spots["boiler"]
		add_child(boiler)
	if template == "cloud_walk" and mult > 0.0:
		if randf() < minf(0.5 * mult, 1.0):
			_place_item(Items.brush(), open_world.item_spots["brush"] + Vector3(0, 0.11, 0))


# `spot` is a bottle position: 0.11 above the surface the item lies on.
func _place_item(body: StaticBody3D, spot: Vector3) -> void:
	body.position = spot + Vector3(0, float(body.get_meta("rest")) - 0.11, 0)
	body.rotation.y = randf() * TAU
	add_child(body)


func _take_spot(target: String, pools: Array) -> Vector3:
	if target == "basement" or target == "maze":
		for pool in pools:
			if pool["type"] == target and not pool["spots"].is_empty():
				return _pop_random(pool["spots"])
	elif target == "house":
		var candidates := pools.filter(func(p): return not p["spots"].is_empty())
		if not candidates.is_empty():
			return _pop_random(candidates.pick_random()["spots"])
	var use_shower := randf() < SHOWER_SPAWN_CHANCE
	if shower_spots.is_empty():
		use_shower = false
	elif room_spots.is_empty():
		use_shower = true
	return _pop_random(shower_spots if use_shower else room_spots)


func _pop_random(spots: Array) -> Vector3:
	var i := randi() % spots.size()
	var pos: Vector3 = spots[i]
	spots.remove_at(i)
	return pos


func _build_shower() -> void:
	var glass := _mat(Color(0.7, 0.9, 1.0, 0.25))
	var wall_x := sx * room_w / 2.0
	var wall_z := sz * room_d / 2.0
	var x_in := wall_x - sx * (stall_max.x - stall_min.x)
	var z_in := wall_z - sz * (stall_max.y - stall_min.y)
	var stall_w := stall_max.x - stall_min.x
	var stall_d := stall_max.y - stall_min.y
	var center := (stall_min + stall_max) / 2.0

	_prop(_box(Vector3(stall_w, 0.03, stall_d)), Vector3(center.x, 0.015, center.y), _mat(Color(0.6, 0.65, 0.7)), false)

	# Tile the two room walls that enclose the stall.
	_prop(_box(Vector3(0.02, 3.0, stall_d)), Vector3(wall_x - sx * 0.01, 1.5, center.y), _tile_material(stall_d, 3.0), false)
	_prop(_box(Vector3(stall_w, 3.0, 0.02)), Vector3(center.x, 1.5, wall_z - sz * 0.01), _tile_material(stall_w, 3.0), false)

	# Two glass sides; one of them has a doorway next to the other.
	var gap := 1.0
	var a_len := stall_d
	var a_center := center.y
	var b_len := stall_w
	var b_center := center.x
	if randf() < 0.5:
		a_len = stall_d - gap
		a_center = wall_z - sz * a_len / 2.0
	else:
		b_len = stall_w - gap
		b_center = wall_x - sx * b_len / 2.0
	_prop(_box(Vector3(0.04, 2.2, a_len)), Vector3(x_in, 1.1, a_center), glass).set_meta("no_drop", true)
	_prop(_box(Vector3(b_len, 2.2, 0.04)), Vector3(b_center, 1.1, z_in), glass).set_meta("no_drop", true)

	var pivot := _build_handle(_pick_wall_slot(0.12, 0.12, 1.0, 1.3))
	var spray := _build_nozzle(_pick_wall_slot(0.2, 0.2, 2.1, 2.4))
	register_shower(Rect2(stall_min, stall_max - stall_min), 0.0, pivot, spray)

	var spots: Array[Vector3] = []
	var shelf_mat := _mat(Color(0.8, 0.8, 0.82))
	for i in randi_range(1, 3):
		var slot := _pick_wall_slot(0.35, 0.15, 0.5, 1.7)
		if slot.is_empty():
			continue
		var wall: int = slot["wall"]
		var along: float = slot["along"]
		var y: float = slot["y"]
		var shelf := _mount(wall, along, y, WALL_INSET)
		_prop(_box(Vector3(0.7, 0.04, 0.25)), Vector3(0, 0, 0.125), shelf_mat, true, Vector3.ZERO, shelf)
		for offset in [-0.18, 0.18]:
			spots.append(_wall_point(wall, along + offset) + _wall_normal(wall) * (0.13 + WALL_INSET) + Vector3(0, y + 0.13, 0))

	var floor_spots: Array[Vector3] = []
	for attempt in 40:
		if floor_spots.size() >= 4:
			break
		var p := Vector3(
			randf_range(stall_min.x + 0.4, stall_max.x - 0.4), 0.14,
			randf_range(stall_min.y + 0.4, stall_max.y - 0.4))
		var far_enough := true
		for q in floor_spots:
			if q.distance_to(p) < 0.5:
				far_enough = false
		if far_enough:
			floor_spots.append(p)
	spots.append_array(floor_spots)
	while spots.size() < order.size() + 1:
		spots.append(Vector3(center.x, 0.14, center.y) + Vector3(randf_range(-0.3, 0.3), 0, randf_range(-0.3, 0.3)))
	shower_spots = spots


func _build_handle(slot: Dictionary) -> Node3D:
	return make_handle(_mount(slot["wall"], slot["along"], slot["y"], WALL_INSET))


func _build_nozzle(slot: Dictionary) -> CPUParticles3D:
	var mount := _mount(slot["wall"], slot["along"], slot["y"], WALL_INSET)
	return make_nozzle(mount, _wall_normal(slot["wall"]))


# Builds a shower handle on `mount` (local +z points into the room); returns the part that turns.
func make_handle(mount: Node3D) -> Node3D:
	var chrome := _mat(Color(0.75, 0.78, 0.8))
	_prop(_cyl(0.08, 0.02), Vector3(0, 0, 0.01), chrome, false, Vector3(90, 0, 0), mount)
	_prop(_cyl(0.02, 0.06), Vector3(0, 0, 0.05), chrome, false, Vector3(90, 0, 0), mount)
	var pivot := Node3D.new()
	pivot.position = Vector3(0, 0, 0.09)
	mount.add_child(pivot)
	_prop(_box(Vector3(0.2, 0.04, 0.04)), Vector3(0.07, 0, 0), _mat(Color(0.8, 0.1, 0.1)), false, Vector3.ZERO, pivot)

	var body := StaticBody3D.new()
	body.position = Vector3(0, 0, 0.08)
	body.set_meta("kind", "handle")
	body.set_meta("label", "Shower handle")
	var cs := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.15
	cs.shape = sphere
	body.add_child(cs)
	mount.add_child(body)
	return pivot


# Builds a shower head on `mount` facing along `n` (the wall's inward normal); returns the water spray.
func make_nozzle(mount: Node3D, n: Vector3) -> CPUParticles3D:
	var chrome := _mat(Color(0.75, 0.78, 0.8))
	_prop(_cyl(0.02, 0.3), Vector3(0, 0, 0.15), chrome, false, Vector3(90, 0, 0), mount)
	_prop(_cyl(0.14, 0.05), Vector3(0, -0.04, 0.3), chrome, false, Vector3(-20, 0, 0), mount)

	var spray := CPUParticles3D.new()
	spray.position = mount.position + n * 0.3 + Vector3(0, -0.08, 0)
	spray.emitting = false
	spray.amount = 300
	spray.lifetime = 0.45
	spray.direction = Vector3(n.x * 0.3, -1, n.z * 0.3)
	spray.spread = 18.0
	spray.initial_velocity_min = 2.0
	spray.initial_velocity_max = 3.0
	spray.gravity = Vector3(0, -9.8, 0)
	spray.particle_flag_align_y = true
	spray.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	spray.emission_sphere_radius = 0.1
	var drop := _cyl(0.006, 0.12)
	drop.radial_segments = 4
	drop.rings = 1
	drop.material = _mat(Color(0.5, 0.75, 1.0, 0.6))
	spray.mesh = drop
	add_child(spray)
	return spray


func _make_bottle(id: String, pos: Vector3, force_static := false) -> void:
	var body: PhysicsBody3D
	if runner_bottles and not force_static:
		var runner := RunnerBottle.new()
		runner.setup(BOTTLE_COLORS[id], null)
		runner.position = pos - Vector3(0, 0.11, 0)
		runners.append(runner)
		body = runner
		_tag_bottle(body, id)
		add_child(body)
	else:
		var solid := StaticBody3D.new()
		solid.position = pos
		body = solid
		_tag_bottle(body, id)
		var cs := CollisionShape3D.new()
		var shape := CylinderShape3D.new()
		shape.radius = 0.08
		shape.height = 0.32
		cs.shape = shape
		cs.position = Vector3(0, 0.045, 0)
		body.add_child(cs)
		add_child(body)
		_prop(_cyl(0.05, 0.22), Vector3.ZERO, _mat(BOTTLE_COLORS[id]), false, Vector3.ZERO, body)
		_prop(_cyl(0.025, 0.05), Vector3(0, 0.135, 0), _mat(BOTTLE_COLORS[id]), false, Vector3.ZERO, body)
		_prop(_cyl(0.03, 0.04), Vector3(0, 0.18, 0), _mat(Color.WHITE), false, Vector3.ZERO, body)
	bottles.append(body)


func _tag_bottle(body: PhysicsBody3D, id: String) -> void:
	body.set_meta("kind", "bottle")
	body.set_meta("id", id)
	body.set_meta("label", "%s bottle" % id.capitalize())


func _build_player() -> void:
	var spawn := Vector3(-sx * (room_w / 2.0 - 1.0), 0.95, -sz * (room_d / 2.0 - 1.0))
	if is_open_world:
		spawn = open_world.spawn
	else:
		for attempt in 60:
			var p := Vector2(
				randf_range(-room_w / 2.0 + 0.8, room_w / 2.0 - 0.8),
				randf_range(-room_d / 2.0 + 0.8, room_d / 2.0 - 0.8))
			if _rect_free(Rect2(p - Vector2(0.4, 0.4), Vector2(0.8, 0.8))):
				spawn = Vector3(p.x, 0.95, p.y)
				break
	player = PlayerScript.new()
	player.position = spawn
	safe_pos = spawn
	player.can_jump = template == "cloud_walk"
	if player.can_jump:
		player.jump_mult = CLOUD_JUMP
	if not is_open_world:
		var stall_center := (stall_min + stall_max) / 2.0
		player.rotation.y = atan2(spawn.x - stall_center.x, spawn.z - stall_center.y)
	add_child(player)
	var nav := {}
	if not runners.is_empty():
		nav = open_world.nav_graph() if is_open_world else house.nav_graph()
	for runner in runners:
		runner.set_threat(player)
		runner.house = house
		runner.graph = nav
	player.clicked.connect(_on_clicked)
	player.right_clicked.connect(_on_right_clicked)

	flashlight = SpotLight3D.new()
	flashlight.spot_range = 22.0
	flashlight.spot_angle = 32.0
	flashlight.light_energy = 5.0
	flashlight.shadow_enabled = true
	flashlight.visible = false
	flashlight.position = FLASH_POS + Vector3(0, 0, -0.2)
	player.camera.add_child(flashlight)


func _build_hud() -> void:
	hud = CanvasLayer.new()
	add_child(hud)

	blind_overlay = ColorRect.new()
	blind_overlay.color = Color(0, 0, 0, 0)
	blind_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(blind_overlay)
	blind_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	timer_label = _hud_label(48)
	timer_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	timer_label.offset_top = 10
	timer_label.offset_bottom = 70

	effect_label = _hud_label(24)
	effect_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	effect_label.offset_top = 70
	effect_label.offset_bottom = 110

	var crosshair := _hud_label(28)
	crosshair.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	crosshair.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	crosshair.text = "+"

	hint_label = _hud_label(24)
	hint_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hint_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hint_label.offset_top = 80

	message_label = _hud_label(28)
	message_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	message_label.offset_top = -120
	message_label.offset_bottom = -40

	status_label = _hud_label(18)
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	status_label.position = Vector2(16, 16)
	status_label.visible = show_controls

	if MP.active:
		race_label = _hud_label(22)
		race_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
		race_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		race_label.offset_top = 14
		race_label.offset_right = -16
		race_label.text = MP.race_label()
		mp_panel = MpPanel.new()
		hud.add_child(mp_panel)
		mp_panel.anchor_left = 1.0
		mp_panel.anchor_right = 1.0
		mp_panel.offset_left = -380.0
		mp_panel.offset_right = -20.0
		mp_panel.offset_top = 90.0
		mp_panel.offset_bottom = 90.0
		mp_panel.visible = false


func _hud_label(font_size: int) -> Label:
	var l := Label.new()
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_override("font", Ui.font())
	l.add_theme_font_size_override("font_size", font_size + 4)
	l.add_theme_color_override("font_outline_color", Color(0.02, 0.06, 0.15))
	l.add_theme_constant_override("outline_size", 9)
	hud.add_child(l)
	return l
