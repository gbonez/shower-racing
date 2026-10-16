extends Node3D

# Procedural house attached to the bathroom door. Plans rooms as rectangles first (cheap to retry),
# then builds walls, doors, stairs and furniture. Walls: 0 = +z, 1 = -z, 2 = +x, 3 = -x.

const LEVEL_H := 3.1
const PHOTO_DIR := "res://assets/images/framedphotos/"
const FRAME_TRIM := 0.035  # castle door frames reach this far into the opening so no faces coincide
const DOOR_W := 0.9
const DOOR_H := 2.1
const STAIR_W := 1.8
const STAIR_FOYER := 1.1
const STAIR_RUN := 4.6
const STAIR_LANDING := 1.3
const STAIR_LEN := 7.0
const MAZE_CELLS := 14
const MAZE_BLOCK := 1.8
const Castle := preload("res://scripts/castle.gd")
const Crypt := preload("res://scripts/crypt.gd")
# Ceiling heights by room type for the castle and the crypt; anything not listed is 3 m.
const CASTLE_H := {"throne_room": 7.0, "great_hall": 6.0, "hallway": 4.2, "bedroom": 3.6, "kitchen": 4.0,
		"courtyard": 7.0, "treasure": 4.0}
const CRYPT_H := {"throne_room": 5.5, "great_hall": 5.0, "hallway": 3.4, "bedroom": 3.2, "kitchen": 3.4,
		"tomb": 3.6}

const PALETTE := {
	"living": [Color(0.9, 0.85, 0.75), Color(0.55, 0.38, 0.22)],
	"kitchen": [Color(0.95, 0.93, 0.8), Color(0.9, 0.9, 0.9)],
	"dining": [Color(0.85, 0.72, 0.68), Color(0.5, 0.33, 0.2)],
	"bedroom": [Color(0.75, 0.8, 0.9), Color(0.6, 0.55, 0.5)],
	"hallway": [Color(0.88, 0.86, 0.8), Color(0.5, 0.36, 0.24)],
	"stairs": [Color(0.88, 0.86, 0.8), Color(0.45, 0.32, 0.2)],
	"bathroom2": [Color(0.75, 0.88, 0.92), Color(0.85, 0.9, 0.92)],
	"attic": [Color(0.55, 0.45, 0.35), Color(0.35, 0.26, 0.18)],
	"basement": [Color(0.45, 0.45, 0.47), Color(0.3, 0.3, 0.32)],
	"great_hall": [Color(0.6, 0.58, 0.55), Color(0.4, 0.38, 0.36)],
	"throne_room": [Color(0.55, 0.5, 0.52), Color(0.35, 0.33, 0.35)],
	"tower": [Color(0.55, 0.55, 0.57), Color(0.38, 0.37, 0.38)],
	"tower_top": [Color(0.6, 0.57, 0.52), Color(0.45, 0.35, 0.25)],
	"yard": [Color(0.62, 0.45, 0.28), Color(0.2, 0.5, 0.2)],
}


class Room:
	var type := ""
	var rect := Rect2()  # layout rect, walls included
	var lvl_lo := 0
	var lvl_hi := 0
	var y0 := 0.0
	var y1 := 3.0
	var boiler := false  # the boiler stands in this room
	var wall_t := 0.1
	var dark := false
	var openings: Array[Dictionary] = []  # {side, lo, hi, y0, kind}
	var used: Array[Rect2] = []  # floor footprints taken by furniture and door clearance
	var spots: Array[Vector3] = []  # possible bottle positions
	var out_side := -1  # stairs: side the far end faces
	var near_is_top := false  # stairs: whether the end next to the parent is the upper one
	var maze_side := -1
	var maze_k := 1
	var lit_zones: Array[Rect2] = []  # lit areas inside a dark room, e.g. the bathroom hidden in the maze

	func interior() -> Rect2:
		return rect.grow(-wall_t)


var main  # untyped: calls the main script's build helpers
var rooms: Array[Room] = []
var conns: Array[Dictionary] = []  # {a, b, side, lo, hi, kind, y0, c}
var hall_parallel_chance := 0.6
var hall_len_min := 7.0
var hall_len_max := 11.0
var maze_return := Vector3.ZERO  # where the player lands after falling into a maze pit
var upside_down := false  # walkable ceilings: openings run floor to ceiling and doors hang from the top
var giant := false  # the main script scales the house up; only the bathroom door opens
var want_boiler := false
var size_mult := 1.0
var hall_narrow_min := 1.8
var hall_narrow_max := 2.2
var door_leaves: Array[Dictionary] = []  # {conn, leaf}
var wall_parent: Node = null  # where bathroom walls go, so a scaled house doesn't scale them
var portals: Array[Dictionary] = []  # run-away shower doors: {room, mount, leaf}
var castle := false  # stone walls, carpets, columns and tall halls (also set for the crypt)
var crypt := false  # the castle's spooky cousin: catacombs, coffins and a sealed tomb
var treasure_spot := Vector3.INF  # where the king's crown rests, in house coordinates
var door_w := DOOR_W
var door_h := DOOR_H
var stone_mat: Material = null
var basement_top := Vector3.INF  # top of the stairs down to the basement, in house coordinates
var boiler_placed := false  # a boiler is somewhere in the house
var photos: Array[Texture2D] = []  # pictures for wall frames, loaded on first use
var sealed := false  # run-away shower: the bathroom has no doorway into the house
var power_out := false  # power outage: every room is dark and the house lights stay off
var yard_room: Room = null  # the doghouse's fenced yard
var dog_stake: Vector3 = Vector3.INF  # where the guard dog's chain is pinned, in house coordinates
var yard_spot: Vector3 = Vector3.INF  # the guarded bottle's spot beside the stake, in house coordinates
var room_furniture: Dictionary = {}  # Room -> the furniture nodes built in it, so blockers can be removed
var photo_bag: Array[Texture2D] = []  # photos not yet hung on a wall; refilled when it runs out


# --- Planning ---

func plan(template: String, bath_rect: Rect2, door_side: int, door_pos: float, boiler_on := false,
		runaway_on := false) -> bool:
	for attempt in (400 if template in ["castle", "crypt"] else 80):
		rooms.clear()
		conns.clear()
		sealed = false
		var bath := _new_room("bathroom", bath_rect, 0, 0)
		if _plan_template(template, bath, door_side, door_pos):
			var can_seal := not (template in ["bathroom", "giant_house"] or template in GameState.OPEN_TEMPLATES)
			if template == "runaway_shower" or (runaway_on and can_seal):
				_seal_bathroom()
				sealed = true
			if template != "bathroom" and not (template in GameState.OPEN_TEMPLATES):
				_add_closets()
			if boiler_on:
				want_boiler = true
			_assign_boiler()
			return true
	rooms.clear()
	conns.clear()
	upside_down = false
	giant = false
	want_boiler = false
	castle = false
	crypt = false
	treasure_spot = Vector3.INF
	door_w = DOOR_W
	door_h = DOOR_H
	basement_top = Vector3.INF
	size_mult = 1.0
	power_out = false
	yard_room = null
	dog_stake = Vector3.INF
	yard_spot = Vector3.INF
	_new_room("bathroom", bath_rect, 0, 0)
	return false


# Puts the boiler in the basement when there is one, otherwise in an ordinary room.
func _assign_boiler() -> void:
	boiler_placed = false
	if not want_boiler:
		return
	var pick: Room = null
	for i in range(1, rooms.size()):
		if rooms[i].type == "basement":
			pick = rooms[i]
	if pick == null:
		var options: Array[Room] = []
		for i in range(1, rooms.size()):
			if rooms[i].type in ["living", "kitchen", "dining", "bedroom", "closet", "attic", "great_hall"]:
				options.append(rooms[i])
		if options.is_empty():
			return
		pick = options.pick_random()
	pick.boiler = true
	boiler_placed = true


func _new_room(type: String, rect: Rect2, lo: int, hi: int) -> Room:
	var r := Room.new()
	r.type = type
	r.rect = rect
	r.lvl_lo = lo
	r.lvl_hi = hi
	r.y0 = lo * LEVEL_H
	r.y1 = (hi * LEVEL_H + 3.0) if type == "stairs" else (r.y0 + 3.0)
	if castle and type != "stairs":
		var heights: Dictionary = CRYPT_H if crypt else CASTLE_H
		r.y1 = r.y0 + float(heights.get(type, 3.0))
	if type == "yard":
		r.y1 = r.y0 + 2.4  # a tall fence, open to the sky
	r.dark = type == "basement" or type == "maze"
	rooms.append(r)
	return r


func _plan_template(t: String, bath: Room, ds: int, dp: float) -> bool:
	var door_sides: Array = [ds]
	hall_parallel_chance = 0.6
	hall_len_min = 7.0
	hall_len_max = 11.0
	hall_narrow_min = 1.8
	hall_narrow_max = 2.2
	size_mult = 1.0
	upside_down = false
	giant = false
	want_boiler = false
	castle = false
	crypt = false
	treasure_spot = Vector3.INF
	door_w = DOOR_W
	door_h = DOOR_H
	basement_top = Vector3.INF
	power_out = false
	yard_room = null
	dog_stake = Vector3.INF
	yard_spot = Vector3.INF
	match t:
		"bathroom":
			return true
		"cloud_walk", "beach", "warehouse", "lab", "monster_movie", "golf", "lake", "treasure_hunt":
			return true
		"power_outage":
			power_out = true
			return _plan_house("house", bath, door_sides, dp)
		"chase":
			return _plan_house("house", bath, door_sides, dp)
		"doghouse":
			return _plan_doghouse(bath, door_sides, dp)
		"upside_down":
			upside_down = true
			return _plan_flat_house(bath, door_sides, dp)
		"giant_house":
			giant = true
			return _plan_flat_house(bath, door_sides, dp)
		"castle":
			castle = true
			door_w = 1.3
			door_h = 2.7
			return _plan_castle(bath, door_sides, dp)
		"crypt":
			castle = true
			crypt = true
			door_w = 1.2
			door_h = 2.5
			return _plan_crypt(bath, door_sides, dp)
		"motel":
			hall_parallel_chance = 1.0
			hall_len_min = 12.0
			hall_len_max = 16.0
			var hall := _place("hallway", bath, "door", 0, door_sides, dp)
			if hall == null:
				return false
			var lobby := _place("living", hall, "open", 0, _end_sides(hall))
			if lobby == null or _place("kitchen", lobby, "open", 0) == null:
				return false
			var beds: Array[Room] = []
			for i in randi_range(4, 6):
				var bed := _place("bedroom", hall, "door", 0, _long_sides(hall))
				if bed != null:
					beds.append(bed)
			if beds.size() < 3:
				return false
			for i in randi_range(1, 3):
				_place("bathroom2", beds.pick_random(), "door", 0)
			return true
		"townhouse":
			var hall := _place("hallway", bath, "door", 0, door_sides, dp)
			if hall == null:
				return false
			var stairs := _stairs_random(hall, false, 0)
			if stairs == null:
				return false
			var upper := _place("hallway", stairs, "arch", 1, [stairs.out_side])
			if upper == null:
				return false
			var stairs2 := _stairs_random(upper, false, 1)
			if stairs2 == null:
				return false
			var top := _place("hallway", stairs2, "arch", 2, [stairs2.out_side])
			if top == null:
				return false
			if _place("bedroom", upper, "door", 1) == null or _place("bedroom", top, "door", 2) == null:
				return false
			_place("bedroom", upper, "door", 1)
			_place("bedroom", top, "door", 2)
			var living := _place("living", hall, _open_or_door(), 0)
			if living == null:
				return false
			var kitchen := _place("kitchen", living, _open_or_door(), 0)
			if kitchen == null:
				return false
			_place("dining", kitchen, _open_or_door(), 0)
			for i in randi_range(0, 2):
				var parent := upper if randf() < 0.5 else top
				_place("bathroom2", parent, "door", parent.lvl_lo)
			return true
		"railroad":
			var prev := _place("living", bath, "door", 0, door_sides, dp)
			if prev == null:
				return false
			var chain := ["kitchen", "dining", "bedroom", "bedroom"]
			chain.shuffle()
			for room_type in chain:
				prev = _place(room_type, prev, "door", 0)
				if prev == null:
					return false
			return true
		"studio":
			var living := _place("living", bath, "door", 0, door_sides, dp)
			if living == null:
				return false
			return _place("kitchen", living, "open", 0) != null \
					and _place("bedroom", living, "open", 0) != null
		"two_bedroom":
			var living := _place("living", bath, "door", 0, door_sides, dp)
			if living == null or _place("kitchen", living, "open", 0) == null:
				return false
			return _place("bedroom", living, "door", 0) != null \
					and _place("bedroom", living, "door", 0) != null
		"loft":
			var living := _place("living", bath, "door", 0, door_sides, dp)
			if living == null or _place("kitchen", living, "open", 0) == null:
				return false
			var stairs := _stairs_random(living, false, 0)
			if stairs == null:
				return false
			return _place("bedroom", stairs, "arch", 1, [stairs.out_side]) != null
		"three_bedroom":
			hall_parallel_chance = 1.0
			var hall := _place("hallway", bath, "door", 0, door_sides, dp)
			if hall == null:
				return false
			var living := _place("living", hall, "open", 0, _end_sides(hall))
			if living == null or _place("kitchen", living, "open", 0) == null:
				return false
			for i in 3:
				if _place("bedroom", hall, "door", 0, _long_sides(hall)) == null:
					return false
			return true
	return _plan_house(t, bath, door_sides, dp)


func _plan_house(t: String, bath: Room, door_sides: Array, dp: float) -> bool:
	want_boiler = t == "boiler_room"
	var hall := _place("hallway", bath, "door", 0, door_sides, dp)
	if hall == null:
		return false
	var stairs := _stairs_random(hall, false, 0)
	if stairs == null:
		return false
	var upper := _place("hallway", stairs, "arch", 1, [stairs.out_side])
	if upper == null:
		return false
	var beds := 0
	for i in (randi_range(3, 4) if t == "mansion" else randi_range(1, 4)):
		if _place("bedroom", upper, "door", 1) != null:
			beds += 1
	if beds == 0:
		return false

	if t == "attic" or t == "mansion":
		var up_stairs := _stairs_random(upper, false, 1)
		if up_stairs == null or _place("attic", up_stairs, "arch", 2, [up_stairs.out_side]) == null:
			return false
	if t == "basement" or t == "maze" or t == "mansion" or t == "boiler_room":
		var down_stairs := _stairs_random(hall, true, -1)
		if down_stairs == null:
			return false
		basement_top = _landing_above(down_stairs)
		var basement := _place("basement", down_stairs, "arch", -1, [down_stairs.out_side])
		if basement == null:
			return false
		if t == "maze" and _attach_maze(basement) == null:
			return false

	var living := _place("living", hall, _open_or_door(), 0)
	if living == null:
		return false
	var kitchen := _place("kitchen", living if randf() < 0.7 else hall, _open_or_door(), 0)
	if kitchen == null:
		return false
	if _place("dining", kitchen if randf() < 0.5 else living, _open_or_door(), 0) == null:
		return false
	if t == "mansion":
		_place("living", hall, "door", 0)
	for i in (randi_range(2, 4) if t == "mansion" else _extra_baths()):
		var parent := hall if randf() < 0.5 else upper
		_place("bathroom2", parent, "door", parent.lvl_lo)
	return true


func _open_or_door() -> String:
	return "open" if randf() < 0.5 else "door"


# A one-floor house with a fenced back yard reached by a door from the living areas.
func _plan_doghouse(bath: Room, door_sides: Array, dp: float) -> bool:
	if not _plan_flat_house(bath, door_sides, dp):
		return false
	var hosts: Array[Room] = []
	for r in rooms:
		if r.type in ["living", "kitchen", "dining", "hallway"]:
			hosts.append(r)
	hosts.shuffle()
	for host in hosts:
		var yard := _place("yard", host, "door", 0)
		if yard != null:
			yard_room = yard
			return true
	return false


# Where a player stands just outside the doorway of `stairs`, in the room it hangs off.
func _landing_above(stairs: Room) -> Vector3:
	for c in conns:
		if c["b"] != stairs:
			continue
		var mid := (float(c["lo"]) + float(c["hi"])) / 2.0
		var side: int = c["side"]
		var pos := Vector3(mid, 0.0, float(c["c"])) if side < 2 else Vector3(float(c["c"]), 0.0, mid)
		pos -= _side_vec(side) * 1.3
		pos.y = float(c["y0"]) + 0.95
		return pos
	return Vector3.INF


# One floor: hallway, living room, kitchen, dining area and a few bedrooms (no stairs).
func _plan_flat_house(bath: Room, door_sides: Array, dp: float) -> bool:
	var hall := _place("hallway", bath, "arch" if upside_down else "door", 0, door_sides, dp)
	if hall == null:
		return false
	var living := _place("living", hall, _open_or_door(), 0)
	if living == null:
		return false
	var kitchen := _place("kitchen", living if randf() < 0.7 else hall, _open_or_door(), 0)
	if kitchen == null:
		return false
	_place("dining", kitchen if randf() < 0.5 else living, _open_or_door(), 0)
	var beds := 0
	for i in randi_range(2, 3):
		if _place("bedroom", hall, "door", 0) != null:
			beds += 1
	if beds == 0:
		return false
	for i in _extra_baths():
		_place("bathroom2", hall, "door", 0)
	return true


# A big ground-floor castle: gatehouse gallery, great hall, throne room, kitchen, bedrooms and towers.
func _plan_castle(bath: Room, door_sides: Array, dp: float) -> bool:
	size_mult = 1.7
	hall_len_min = 18.0
	hall_len_max = 24.0
	hall_narrow_min = 4.0
	hall_narrow_max = 5.0
	hall_parallel_chance = 1.0
	var gate := _place("hallway", bath, "door", 0, door_sides, dp)
	if gate == null:
		return false
	var great := _place("great_hall", gate, "open", 0)
	if great == null:
		return false
	var throne := _place("throne_room", great, "open" if randf() < 0.5 else "door", 0)
	if throne == null:
		return false
	if _place("kitchen", great, _open_or_door(), 0) == null:
		return false
	var beds := 0
	for i in randi_range(3, 4):
		var host: Room = gate if randf() < 0.5 else great
		if _place("bedroom", host, "door", 0) != null:
			beds += 1
	if beds == 0:
		return false
	# The treasure vault goes behind the throne room, then a walled garden somewhere along the hall.
	var vault: Room = null
	var vault_hosts: Array = rooms.filter(func(rm): return rm.type == "bedroom")  # tucked behind a bedroom
	vault_hosts.shuffle()
	vault_hosts.append_array([throne, great, gate])
	for host in vault_hosts:
		vault = _place("treasure", host, "door", 0)
		if vault != null:
			break
	if vault == null:
		return false
	var yard: Room = null
	for host in [great, gate, throne]:
		yard = _place("courtyard", host, "door", 0)
		if yard != null:
			break
	if yard == null:
		return false
	for i in 2:
		var tower_host: Room = [gate, great, throne].pick_random()
		var base := _place("tower", tower_host, "door", 0)
		if base == null:
			continue
		var shaft := _stairs_random(base, false, 0)
		if shaft != null and _place("tower_top", shaft, "arch", 1, [shaft.out_side]) == null:
			return false  # stairs that lead nowhere: replan
	return true


# Catacombs: an entrance corridor, an ossuary, a chapel, burial chambers and a sealed tomb.
func _plan_crypt(bath: Room, door_sides: Array, dp: float) -> bool:
	size_mult = 1.6
	hall_len_min = 16.0
	hall_len_max = 22.0
	hall_narrow_min = 3.4
	hall_narrow_max = 4.2
	hall_parallel_chance = 1.0
	var gate := _place("hallway", bath, "door", 0, door_sides, dp)
	if gate == null:
		return false
	var ossuary := _place("great_hall", gate, "open", 0)
	if ossuary == null:
		return false
	var chapel := _place("throne_room", ossuary, "open" if randf() < 0.5 else "door", 0)
	if chapel == null:
		return false
	if _place("kitchen", ossuary, "door", 0) == null:
		return false
	var chambers := 0
	for i in randi_range(3, 4):
		var host: Room = gate if randf() < 0.5 else ossuary
		if _place("bedroom", host, "door", 0) != null:
			chambers += 1
	if chambers == 0:
		return false
	var tomb: Room = null
	for host in [chapel, ossuary, gate]:
		tomb = _place("tomb", host, "door", 0)
		if tomb != null:
			break
	return tomb != null


# Most floor plans get one or two small closets hanging off an ordinary room.
func _add_closets() -> void:
	if randf() >= 0.75:
		return
	var hosts: Array[Room] = []
	for i in range(1, rooms.size()):
		if rooms[i].type in ["hallway", "living", "bedroom", "kitchen", "dining"]:
			hosts.append(rooms[i])
	if hosts.is_empty():
		return
	for i in randi_range(1, 2):
		var host: Room = hosts.pick_random()
		_place("closet", host, "door", host.lvl_lo)


func _extra_baths() -> int:
	var roll := randf()
	if roll < 0.35:
		return 0
	if roll < 0.7:
		return 1
	if roll < 0.9:
		return 2
	return randi_range(3, 4)


func _end_sides(hall: Room) -> Array:
	return [2, 3] if hall.rect.size.x > hall.rect.size.y else [0, 1]


func _long_sides(hall: Room) -> Array:
	return [0, 1] if hall.rect.size.x > hall.rect.size.y else [2, 3]


func _side_vec(side: int) -> Vector3:
	match side:
		0:
			return Vector3(0, 0, 1)
		1:
			return Vector3(0, 0, -1)
		2:
			return Vector3(1, 0, 0)
	return Vector3(-1, 0, 0)


func _room_size(type: String, side: int) -> Vector2:
	var s: Vector2
	match type:
		"living":
			s = Vector2(randf_range(5.5, 7.0), randf_range(5.0, 6.0)) if randf() < 0.5 \
					else Vector2(randf_range(4.0, 4.8), randf_range(4.0, 4.8))
		"kitchen":
			s = Vector2(randf_range(4.8, 6.0), randf_range(4.2, 5.0)) if randf() < 0.5 \
					else Vector2(randf_range(3.2, 3.8), randf_range(3.4, 4.0))
		"dining":
			s = Vector2(randf_range(4.0, 5.0), randf_range(3.8, 4.6))
		"bedroom":
			s = Vector2(randf_range(3.6, 4.6), randf_range(3.6, 4.6))
		"bathroom2":
			s = Vector2(randf_range(2.6, 3.2), randf_range(2.8, 3.4))
		"closet":
			s = Vector2(randf_range(1.8, 2.3), randf_range(1.4, 1.8))
		"attic":
			s = Vector2(randf_range(5.0, 7.0), randf_range(5.0, 7.0))
		"basement":
			s = Vector2(randf_range(7.0, 9.0), randf_range(7.0, 9.0))
		"great_hall":
			s = Vector2(randf_range(8.0, 11.0), randf_range(6.0, 8.0))
		"throne_room":
			s = Vector2(randf_range(8.0, 10.0), randf_range(8.0, 10.0))
		"courtyard":
			s = Vector2(randf_range(13.0, 17.0), randf_range(12.0, 15.0))
		"yard":
			s = Vector2(randf_range(9.0, 11.5), randf_range(8.5, 10.5))
		"treasure":
			s = Vector2(randf_range(7.0, 9.0), randf_range(7.0, 9.0))
		"tomb":
			s = Vector2(randf_range(6.5, 8.5), randf_range(6.5, 8.5))
		"tower", "tower_top":
			s = Vector2(randf_range(4.0, 5.0), randf_range(4.0, 5.0))
		"hallway":
			var long_len := randf_range(hall_len_min, hall_len_max)
			var narrow := randf_range(hall_narrow_min, hall_narrow_max)
			var parallel := randf() < hall_parallel_chance
			var x_long := (side < 2) == parallel
			return Vector2(long_len, narrow) if x_long else Vector2(narrow, long_len)
		_:
			s = Vector2(4.0, 4.0)
	if type in ["living", "kitchen", "dining", "bedroom"]:
		s *= size_mult
	elif castle and type in ["great_hall", "throne_room", "tower", "tower_top", "closet"]:
		s *= 1.5 if type in ["great_hall", "throne_room"] else 1.3
	return s if randf() < 0.5 else Vector2(s.y, s.x)


# Tries random sides and sizes until a room fits; returns null if none did.
func _place(type: String, parent: Room, kind: String, level: int, sides: Array = [0, 1, 2, 3],
		door_pos := NAN) -> Room:
	for attempt in 30:
		var side: int = sides.pick_random()
		var r := _attach(parent, type, _room_size(type, side), side, kind, level, level, door_pos)
		if r != null:
			return r
	return null


func _stairs_random(parent: Room, near_is_top: bool, lo: int) -> Room:
	var sides := [0, 1, 2, 3]
	sides.shuffle()
	for side in sides:
		var size := Vector2(STAIR_W, STAIR_LEN) if side < 2 else Vector2(STAIR_LEN, STAIR_W)
		var s := _attach(parent, "stairs", size, side, "arch", lo, lo + 1)
		if s != null:
			s.out_side = side
			s.near_is_top = near_is_top
			return s
	return null


func _overlaps(rect: Rect2, lvl_lo: int, lvl_hi: int) -> bool:
	for r in rooms:
		if r.lvl_hi < lvl_lo or r.lvl_lo > lvl_hi:
			continue
		if rect.intersects(r.rect):
			return true
	return false


# Places a new room flush against `side` of `parent` and cuts a matching opening in both walls.
func _attach(parent: Room, type: String, size: Vector2, side: int, kind: String,
		lvl_lo: int, lvl_hi: int, door_pos := NAN) -> Room:
	var pr := parent.rect
	var horizontal := side < 2
	var p_lo := pr.position.x if horizontal else pr.position.y
	var p_hi := pr.end.x if horizontal else pr.end.y
	var c_len := size.x if horizontal else size.y
	var depth := size.y if horizontal else size.x
	var c_lo := 0.0
	var dw := DOOR_W if (not is_nan(door_pos) or kind == "arch") else door_w
	if not is_nan(door_pos):
		var m := dw / 2.0 + 0.3
		var lo_min := door_pos + m - c_len
		var lo_max := door_pos - m
		if lo_max < lo_min:
			return null
		c_lo = randf_range(lo_min, lo_max)
	elif kind == "open":
		match randi_range(0, 2):
			0:
				c_lo = p_lo
			1:
				c_lo = p_hi - c_len
			_:
				c_lo = (p_lo + p_hi - c_len) / 2.0
	else:
		var min_ov := dw + 0.7
		var lo_min := p_lo + min_ov - c_len
		var lo_max := p_hi - min_ov
		if lo_max < lo_min:
			return null
		c_lo = randf_range(lo_min, lo_max)
	var ov_lo := maxf(p_lo, c_lo)
	var ov_hi := minf(p_hi, c_lo + c_len)
	var needed := 1.5 if kind == "open" else dw + 0.5
	if ov_hi - ov_lo < needed:
		return null

	var rect: Rect2
	match side:
		0:
			rect = Rect2(c_lo, pr.end.y, c_len, depth)
		1:
			rect = Rect2(c_lo, pr.position.y - depth, c_len, depth)
		2:
			rect = Rect2(pr.end.x, c_lo, depth, c_len)
		_:
			rect = Rect2(pr.position.x - depth, c_lo, depth, c_len)
	if _overlaps(rect, lvl_lo, lvl_hi):
		return null

	var room := _new_room(type, rect, lvl_lo, lvl_hi)
	var y0 := room.y0 if parent.type == "stairs" else parent.y0
	var lo := 0.0
	var hi := 0.0
	match kind:
		"door":
			var center := door_pos if not is_nan(door_pos) \
					else randf_range(ov_lo + 0.3 + dw / 2.0, ov_hi - 0.3 - dw / 2.0)
			lo = center - dw / 2.0
			hi = center + dw / 2.0
		"arch":
			var w := minf(1.2, ov_hi - ov_lo - 0.6)
			var center := door_pos if not is_nan(door_pos) else (ov_lo + ov_hi) / 2.0
			lo = center - w / 2.0
			hi = center + w / 2.0
		_:
			lo = ov_lo + 0.2
			hi = ov_hi - 0.2
	var opening_h := door_h
	if kind == "open":
		opening_h = minf(parent.y1 - parent.y0, room.y1 - room.y0)
	_add_opening(parent, side, lo, hi, y0, kind, opening_h)
	_add_opening(room, side ^ 1, lo, hi, y0, kind, opening_h)
	var boundary := 0.0
	match side:
		0:
			boundary = pr.end.y
		1:
			boundary = pr.position.y
		2:
			boundary = pr.end.x
		_:
			boundary = pr.position.x
	conns.append({"a": parent, "b": room, "side": side, "lo": lo, "hi": hi, "kind": kind,
			"y0": y0, "c": boundary})
	return room


func _add_opening(r: Room, side: int, lo: float, hi: float, y0: float, kind: String, height := DOOR_H) -> void:
	r.openings.append({"side": side, "lo": lo, "hi": hi, "y0": y0, "kind": kind, "h": height})
	r.used.append(_opening_rect(r, side, lo, hi, kind))


# The floor strip kept clear in front of an opening.
func _opening_rect(r: Room, side: int, lo: float, hi: float, kind: String) -> Rect2:
	var inner := r.interior()
	var depth := 0.6 if kind == "open" else 1.1
	match side:
		0:
			return Rect2(lo - 0.15, inner.end.y - depth, hi - lo + 0.3, depth)
		1:
			return Rect2(lo - 0.15, inner.position.y, hi - lo + 0.3, depth)
		2:
			return Rect2(inner.end.x - depth, lo - 0.15, depth, hi - lo + 0.3)
	return Rect2(inner.position.x, lo - 0.15, depth, hi - lo + 0.3)


func _attach_maze(basement: Room) -> Room:
	var grid_n := MAZE_CELLS * 2 + 1
	var span := grid_n * MAZE_BLOCK
	var inner := basement.interior()
	for attempt in 20:
		var side := randi_range(0, 3)
		var horizontal := side < 2
		var p_lo := inner.position.x if horizontal else inner.position.y
		var p_hi := inner.end.x if horizontal else inner.end.y
		if p_hi - p_lo < 3.0:
			continue
		var k := 1 + 2 * randi_range(0, MAZE_CELLS - 1)
		var door_c := randf_range(p_lo + 1.5, p_hi - 1.5)
		var origin := door_c - (k + 0.5) * MAZE_BLOCK
		var br := basement.rect
		var rect: Rect2
		match side:
			0:
				rect = Rect2(origin, br.end.y, span, span)
			1:
				rect = Rect2(origin, br.position.y - span, span, span)
			2:
				rect = Rect2(br.end.x, origin, span, span)
			_:
				rect = Rect2(br.position.x - span, origin, span, span)
		if _overlaps(rect, -1, -1):
			continue
		var m := _new_room("maze", rect, -1, -1)
		m.wall_t = 0.0
		m.maze_side = side ^ 1
		m.maze_k = k
		_add_opening(basement, side, door_c - 0.8, door_c + 0.8, basement.y0, "arch")
		conns.append({"a": basement, "b": m, "kind": "arch"})
		var y := basement.y0 + 0.95
		match side:
			0:
				maze_return = Vector3(door_c, y, inner.end.y - 0.8)
			1:
				maze_return = Vector3(door_c, y, inner.position.y + 0.8)
			2:
				maze_return = Vector3(inner.end.x - 0.8, y, door_c)
			_:
				maze_return = Vector3(inner.position.x + 0.8, y, door_c)
		return m
	return null


# --- Queries used by the main script ---

func room_at(p: Vector3) -> Room:
	for r in rooms:
		if r.interior().has_point(Vector2(p.x, p.z)) and p.y >= r.y0 - 0.2 and p.y <= r.y1:
			return r
	return null


func has_room_type(type: String) -> bool:
	for r in rooms:
		if r.type == type:
			return true
	return false


# True inside the basement and maze, but not on the stairs down or in lit pockets.
func is_dark_at(p: Vector3) -> bool:
	if power_out:
		return true
	var r := room_at(p)
	if r == null or not r.dark:
		return false
	for zone in r.lit_zones:
		if zone.has_point(Vector2(p.x, p.z)):
			return false
	return true


func clamp_to_rooms(pos: Vector3, fallback: Vector3) -> Vector3:
	for r in rooms:
		if r.interior().grow(-0.15).has_point(Vector2(pos.x, pos.z)) \
				and pos.y >= r.y0 - 0.2 and pos.y <= r.y1:
			return pos
	var home := room_at(fallback)
	if home == null:
		home = rooms[0]
	var inner := home.interior().grow(-0.2)
	return Vector3(
		clampf(pos.x, inner.position.x, inner.end.x),
		clampf(pos.y, home.y0 + 0.11, home.y1 - 0.3),
		clampf(pos.z, inner.position.y, inner.end.y))


# Bottle spot lists per room, excluding the main bathroom and the sealed vault and tomb.
func collect_pools() -> Array:
	var pools: Array = []
	for i in range(1, rooms.size()):
		if rooms[i].type in ["tomb", "treasure", "yard"]:
			continue
		if not rooms[i].spots.is_empty():
			pools.append({"type": rooms[i].type, "spots": rooms[i].spots, "level": rooms[i].lvl_lo, "room": rooms[i]})
	return pools


# Where the crypt's bottle waits behind the tomb door.
func tomb_spot() -> Vector3:
	for r in rooms:
		if r.type == "tomb":
			return r.spots.pick_random() if not r.spots.is_empty() else Vector3(r.rect.get_center().x, r.y0 + 0.11, r.rect.get_center().y)
	return Vector3.INF


# Where the crypt crown rests: on the sarcophagus lid beside the tomb's bottle spot (same height
# convention as a bottle spot).
func tomb_crown_spot() -> Vector3:
	for r in rooms:
		if r.type == "tomb":
			var c := r.interior().get_center()
			return Vector3(c.x + 0.7, r.y0 + 1.21, c.y)
	return Vector3.INF


# A spot for the golden key that can be reached while every lock (and the vault) is shut. It goes in one
# of the rooms farthest from the bathroom, up on furniture when there is any.
func golden_key_spot(pools: Array) -> Vector3:
	var locked := {}
	for d in door_leaves:
		if (d["leaf"] as Node).get_meta("locked", false):
			locked[d["leaf"]] = true
	var reach := _reachable(locked)
	var options := pools.filter(func(p): return reach.has(p["room"]) and not p["room"].dark and not p["spots"].is_empty())
	if options.is_empty():
		return Vector3.INF
	var home := rooms[0].rect.get_center()
	options.sort_custom(func(a, b): return home.distance_to(a["room"].rect.get_center()) + 10.0 * a["level"] \
			> home.distance_to(b["room"].rect.get_center()) + 10.0 * b["level"])
	var pool: Dictionary = options.slice(0, maxi(1, options.size() / 3)).pick_random()
	var room: Room = pool["room"]
	var spots: Array = pool["spots"]
	var raised: Array = spots.filter(func(s: Vector3): return s.y - room.y0 > 0.5)
	var spot: Vector3 = raised.pick_random() if not raised.is_empty() else spots.pick_random()
	spots.erase(spot)
	return spot


# --- Template features ---

# Removes the bathroom's doorway so the main script can replace it with a portal.
func _seal_bathroom() -> void:
	var bath := rooms[0]
	var kept: Array[Dictionary] = []
	for c in conns:
		if c["a"] != bath:
			kept.append(c)
			continue
		var child: Room = c["b"]
		for i in range(child.openings.size() - 1, -1, -1):
			if int(child.openings[i]["side"]) == (int(c["side"]) ^ 1) and is_equal_approx(float(child.openings[i]["lo"]), float(c["lo"])):
				child.openings.remove_at(i)
	bath.openings.clear()
	conns = kept


# Rooms reachable from the bathroom when the doors in `locked` (keyed by door leaf) can't be passed.
func _reachable(locked: Dictionary, start: Room = null) -> Dictionary:
	var first: Room = start if start != null else rooms[0]
	var reach := {first: true}
	var frontier: Array = [first]
	while not frontier.is_empty():
		var cur: Room = frontier.pop_back()
		for c in conns:
			var other: Room = null
			if c["a"] == cur:
				other = c["b"]
			elif c["b"] == cur:
				other = c["a"]
			if other == null or reach.has(other):
				continue
			if c.has("leaf") and (locked.has(c["leaf"]) or (c["leaf"] as Node).get_meta("sealed", false)):
				continue
			reach[other] = true
			frontier.append(other)
	return reach


# Invisible waypoints for the run-away bottles: the middle and sides of every room the player can walk
# to (never the bathroom, the maze or a room cut off from the rest) plus one in each doorway. Call it
# after the house is built. Returns {pos, links, doors} in world coordinates, or {} if nothing fits.
func nav_graph() -> Dictionary:
	var start: Room = rooms[1] if sealed and rooms.size() > 1 else rooms[0]
	var reach := _reachable({}, start)
	var positions: Array[Vector3] = []
	var doors: Array = []
	var members: Dictionary = {}  # Room -> indices of the waypoints that belong to it
	for r: Room in reach.keys():
		if r.type == "maze" or (r == rooms[0] and rooms.size() > 1):
			continue
		var ids: Array = []
		for p in _room_waypoints(r):
			positions.append(to_global(p))
			doors.append(null)
			ids.append(positions.size() - 1)
		members[r] = ids
	for c in conns:
		if not c.has("lo") or not reach.has(c["a"]) or not reach.has(c["b"]):
			continue
		if not members.has(c["a"]) and not members.has(c["b"]):
			continue
		var mid := (float(c["lo"]) + float(c["hi"])) / 2.0
		var boundary: float = c["c"]
		var spot := Vector3(mid, float(c["y0"]), boundary) if int(c["side"]) < 2 else Vector3(boundary, float(c["y0"]), mid)
		positions.append(to_global(spot))
		doors.append(c["leaf"] if c["kind"] == "door" and c.has("leaf") else null)
		for room in [c["a"], c["b"]]:
			if members.has(room):
				(members[room] as Array).append(positions.size() - 1)
	if positions.is_empty():
		return {}
	var links: Array = []
	for i in positions.size():
		links.append([])
	for room in members:
		var ids: Array = members[room]
		if (room as Room).type == "stairs":
			# Along the flight, low end to high end, so bottles walk the ramp rather than cut through it.
			var dir := _stairs_dir(room)
			var centre := Vector3(room.rect.get_center().x, 0.0, room.rect.get_center().y)
			ids.sort_custom(func(a: int, b: int) -> bool:
				return (to_local(positions[a]) - centre).dot(dir) < (to_local(positions[b]) - centre).dot(dir))
			for k in ids.size() - 1:
				var lower: int = ids[k]
				var upper: int = ids[k + 1]
				(links[lower] as Array).append(upper)
				(links[upper] as Array).append(lower)
			continue
		for i in ids:
			for j in ids:
				if i != j and not (links[i] as Array).has(j):
					(links[i] as Array).append(j)
	return {"pos": positions, "links": links, "doors": doors}


func _stairs_dir(r: Room) -> Vector3:
	var out_vec := _side_vec(r.out_side)
	return -out_vec if r.near_is_top else out_vec


func _room_waypoints(r: Room) -> Array[Vector3]:
	var result: Array[Vector3] = []
	if r.type == "stairs":
		# Foot of the ramp and top of the ramp; the doorways at both ends are linked to these.
		var centre := Vector3(r.rect.get_center().x, 0.0, r.rect.get_center().y)
		var dir := _stairs_dir(r)
		var z0 := -STAIR_LEN / 2.0 + STAIR_FOYER
		result.append(centre + dir * z0 + Vector3(0, r.y0, 0))
		result.append(centre + dir * (z0 + STAIR_RUN) + Vector3(0, r.y0 + LEVEL_H, 0))
		return result
	var inner := r.interior().grow(-0.7)
	if inner.size.x <= 0.0 or inner.size.y <= 0.0:
		inner = Rect2(r.interior().get_center(), Vector2.ZERO)
	var c := inner.get_center()
	var candidates: Array[Vector2] = [c]
	# A grid of waypoints, denser in bigger rooms, so the bottles have plenty of places to run to.
	var cols := clampi(ceili(inner.size.x / 2.5) + 1, 2, 5)
	var rows := clampi(ceili(inner.size.y / 2.5) + 1, 2, 5)
	for gx in cols:
		for gy in rows:
			candidates.append(Vector2(inner.position.x + inner.size.x * gx / float(cols - 1),
					inner.position.y + inner.size.y * gy / float(rows - 1)))
	for p in candidates:
		if _free(r, Rect2(p - Vector2(0.3, 0.3), Vector2(0.6, 0.6))):
			result.append(Vector3(p.x, r.y0, p.y))
	if result.is_empty():
		result.append(Vector3(c.x, r.y0, c.y))
	return result


# Doors that can be locked: ordinary house doors other than the bathroom's.
func lockable_doors() -> Array:
	var result: Array = []
	if giant:
		return result
	for d in door_leaves:
		if d["conn"]["a"] != rooms[0] and d["conn"]["b"] != rooms[0] and not (d["leaf"] as Node).get_meta("sealed", false):
			result.append(d)
	return result


# Locks up to `count` doors (never the bathroom's). Any key opens any lock, so every key goes in a
# room that can be reached while all the locks are shut; the level can't be made unwinnable by
# spending a key on the "wrong" door. Returns [{leaf, spot}].
func plan_locks(count: int, pools: Array) -> Array:
	var lockable := lockable_doors()
	lockable.shuffle()
	var locked := {}
	var chosen: Array = []
	for i in mini(count, lockable.size()):
		chosen.append(lockable[i])
		locked[lockable[i]["leaf"]] = true
	var reach := _reachable(locked)
	var candidates := pools.filter(func(p): return reach.has(p["room"]) and not p["room"].dark and not p["spots"].is_empty())
	var result: Array = []
	for door in chosen:
		candidates = candidates.filter(func(p): return not p["spots"].is_empty())
		if candidates.is_empty():
			break
		var pool: Dictionary = candidates.pick_random()
		var spots: Array = pool["spots"]
		var index := randi() % spots.size()
		var spot: Vector3 = spots[index]
		spots.remove_at(index)
		result.append({"leaf": door["leaf"], "spot": spot})
	for entry in result:
		var leaf: Node = entry["leaf"]
		leaf.set_meta("locked", true)
		leaf.set_meta("label", "Locked door")
	return result


# Spots for decoy keys: anywhere that isn't dark.
func decoy_spots(pools: Array, count: int) -> Array:
	var result: Array = []
	var candidates := pools.filter(func(p): return not p["room"].dark and not p["spots"].is_empty())
	for i in count:
		candidates = candidates.filter(func(p): return not p["spots"].is_empty())
		if candidates.is_empty():
			break
		var spots: Array = candidates.pick_random()["spots"]
		var index := randi() % spots.size()
		result.append(spots[index])
		spots.remove_at(index)
	return result


# A free-standing door that leads to the (sealed) bathroom, standing against a wall. `mount` has its
# local +z pointing into the room. Behind the leaf is a see-through view of the room on the other side
# (the main script links its `dest`); walking into the doorway while the door is open moves the player
# there. Returns the door leaf, which carries the view as meta "view".
func build_portal_door(mount: Node3D) -> StaticBody3D:
	var wood := Color(0.5, 0.33, 0.2)
	var saved: int = main.mesh_layers
	main.mesh_layers = 1
	var view := PortalView.new()
	view.source = mount
	view.position = Vector3(0, 1.05, 0.03)
	mount.add_child(view)
	_b(mount, Vector3(0.1, 2.2, 0.12), Vector3(-0.5, 1.1, 0.06), wood, false)
	_b(mount, Vector3(0.1, 2.2, 0.12), Vector3(0.5, 1.1, 0.06), wood, false)
	_b(mount, Vector3(1.1, 0.1, 0.12), Vector3(0, 2.15, 0.06), wood, false)
	var pivot := Node3D.new()
	pivot.position = Vector3(-0.45, 0, 0.1)
	mount.add_child(pivot)
	var leaf: Node3D = _b(pivot, Vector3(0.88, 2.08, 0.05), Vector3(0.44, 1.04, 0), wood.darkened(0.1))
	_p(main._cyl(0.025, 0.1), Vector3(0.32, -0.04, 0.06), main._mat(Color(0.8, 0.7, 0.3)), false, Vector3(90, 0, 0), leaf)
	leaf.set_meta("kind", "door")
	leaf.set_meta("label", "Open door")
	leaf.set_meta("pivot", pivot)
	leaf.set_meta("open", false)
	leaf.set_meta("bath_door", false)
	leaf.set_meta("open_angle", -1.7)
	leaf.set_meta("view", view)
	main.mesh_layers = saved
	return leaf as StaticBody3D


# Sets a door open or shut at once, keeping its label in step.
func set_door_open(leaf: Node, is_open: bool) -> void:
	leaf.set_meta("open", is_open)
	leaf.set_meta("label", "Close door" if is_open else "Open door")
	(leaf.get_meta("pivot") as Node3D).rotation.y = float(leaf.get_meta("open_angle")) if is_open else 0.0


# --- Run-away shower door slots ---

const PORTAL_LANDING := 1.1  # how far in front of a slot's wall the player lands
const NAV_CELL := 0.25


# Places between `min_count` and `max_count` door slots on room walls. Every slot is checked: the spot
# where the player lands must be inside its room and reachable on foot from the room's entrances, and
# furniture in the way is removed. If the first passes find too few free walls, furniture is cleared
# off the wall to make room, so at least `min_count` slots exist whenever the house has the walls.
func build_portals(min_count: int, max_count: int) -> void:
	var hosts: Array[Room] = []
	for i in range(1, rooms.size()):
		var r := rooms[i]
		if r.type in ["bathroom2", "closet", "stairs", "maze", "tomb", "treasure", "yard", "courtyard", "basement",
				"tower", "tower_top", "attic"] or r.dark:
			continue
		hosts.append(r)
	if hosts.is_empty():
		return
	hosts.shuffle()
	main.mesh_layers = 1
	for strictness in 3:
		var goal := max_count if strictness == 0 else min_count
		var guard := 0
		while portals.size() < goal and guard < 120:
			var r: Room = hosts[guard % hosts.size()]
			guard += 1
			if _slots_in(r) >= (2 + int(r.rect.get_area() / 30.0) if strictness < 2 else 8):
				continue
			_add_portal(r, strictness)


func _slots_in(r: Room) -> int:
	var n := 0
	for p in portals:
		if p["room"] == r:
			n += 1
	return n


func _add_portal(r: Room, strictness: int) -> void:
	var m: Node3D
	var used_before := r.used.size()
	if strictness == 0:
		m = _wall(r, 1.3, 0.9, 0.15)
	elif strictness == 1:
		m = _wall(r, 1.3, 0.5, 0.0)
	else:
		var side := randi_range(0, 3)
		var inner := r.interior()
		var strip := Rect2(inner.position, Vector2(inner.size.x, 1.7)) if side == 1 \
				else Rect2(Vector2(inner.position.x, inner.end.y - 1.7), Vector2(inner.size.x, 1.7)) if side == 0 \
				else Rect2(Vector2(inner.end.x - 1.7, inner.position.y), Vector2(1.7, inner.size.y)) if side == 2 \
				else Rect2(inner.position, Vector2(1.7, inner.size.y))
		_clear_rect(r, strip)
		used_before = r.used.size()
		m = _wall(r, 1.3, 0.5, 0.0, [side])
	if m == null:
		return
	var door_rect: Rect2 = r.used[r.used.size() - 1] if r.used.size() > used_before else Rect2()
	var depth := _room_depth(r, m)
	var landing := m.to_global(Vector3(0, 0.95, PORTAL_LANDING))
	var near_goal := m.to_global(Vector3(0, 0, 0.5))
	if depth < PORTAL_LANDING + 0.6 or not _reachable_on_foot(r, [near_goal, landing]):
		r.used.erase(door_rect)  # give the wall space back
		m.queue_free()
		return
	if not r.used.has(door_rect):
		r.used.append(door_rect)
	var leaf := build_portal_door(m)
	portals.append({"room": r, "mount": m, "leaf": leaf, "landing": landing, "view": leaf.get_meta("view")})


# Room size across, measured from the mount into the room.
func _room_depth(r: Room, mount: Node3D) -> float:
	var n := mount.global_transform.basis.z
	var inner := r.interior()
	return inner.size.y if absf(n.z) > 0.5 else inner.size.x


func _node_rect(r: Room, node: Node) -> Rect2:
	var result := Rect2()
	var first := true
	var pending: Array[Node] = [node]
	while not pending.is_empty():
		var n: Node = pending.pop_back()
		pending.append_array(n.get_children())
		if not (n is CollisionShape3D) or (n as CollisionShape3D).shape == null or (n as CollisionShape3D).disabled:
			continue
		var cs := n as CollisionShape3D
		var box: AABB = cs.global_transform * cs.shape.get_debug_mesh().get_aabb()
		if box.end.y < r.y0 + 0.2 or box.position.y > r.y0 + 1.7:
			continue
		var flat := Rect2(box.position.x, box.position.z, box.size.x, box.size.z)
		result = flat if first else result.merge(flat)
		first = false
	return result if not first else Rect2()


# Removes the furniture that touches `area` (and the bottle spots and floor claims that went with it).
# Returns how many nodes were removed.
func _clear_rect(r: Room, area: Rect2) -> int:
	var removed := 0
	var props: Array = room_furniture.get(r, [])
	var keep_open: Array[Rect2] = []
	for o in r.openings:
		keep_open.append(_opening_rect(r, int(o["side"]), float(o["lo"]), float(o["hi"]), str(o["kind"])))
	for i in range(props.size() - 1, -1, -1):
		var node: Node3D = props[i]
		if not is_instance_valid(node) or node.is_queued_for_deletion():
			props.remove_at(i)
			continue
		var rect := _node_rect(r, node)
		if not rect.has_area() or not rect.intersects(area):
			continue
		props.remove_at(i)
		node.queue_free()
		removed += 1
		for k in range(r.used.size() - 1, -1, -1):
			if r.used[k].intersects(rect) and not keep_open.has(r.used[k]):
				r.used.remove_at(k)
		for k in range(r.spots.size() - 1, -1, -1):
			if rect.grow(0.15).has_point(Vector2(r.spots[k].x, r.spots[k].z)) and r.spots[k].y > r.y0 + 0.1:
				r.spots.remove_at(k)
	for k in range(r.used.size() - 1, -1, -1):
		if r.used[k].intersects(area) and not keep_open.has(r.used[k]):
			r.used.remove_at(k)
	return removed


# True when each world point in `goals` can be walked to from an entrance of the room. Furniture that is in
# the way gets removed (a few rounds, always the pieces on the cheapest route), so the answer is false only
# when the point can't be reached at all, e.g. outside the walkable floor.
func _reachable_on_foot(r: Room, goals: Array) -> bool:
	var inner := r.interior().grow(-0.3)
	if inner.size.x < 0.4 or inner.size.y < 0.4:
		return false
	var cols := int(ceil(inner.size.x / NAV_CELL))
	var rows := int(ceil(inner.size.y / NAV_CELL))
	var starts: Array[int] = []
	for o in r.openings:
		var mid := (float(o["lo"]) + float(o["hi"])) / 2.0
		var edge := r.interior()
		var p: Vector2
		match int(o["side"]):
			0:
				p = Vector2(mid, edge.end.y - 0.5)
			1:
				p = Vector2(mid, edge.position.y + 0.5)
			2:
				p = Vector2(edge.end.x - 0.5, mid)
			_:
				p = Vector2(edge.position.x + 0.5, mid)
		var cell := _cell_of(inner, p, cols, rows)
		if cell >= 0:
			starts.append(cell)
	if starts.is_empty():
		return false
	for goal: Vector3 in goals:
		var target := _cell_of(inner, Vector2(goal.x, goal.z), cols, rows)
		if target < 0:
			return false
		for round_index in 6:
			var blockers := _blockers_to(r, inner, cols, rows, starts, target)
			if blockers.is_empty():
				break
			if typeof(blockers[0]) == TYPE_INT:
				return false
			for node: Node3D in blockers:
				_clear_rect(r, _node_rect(r, node).grow(0.02))
			if round_index == 5:
				return false
	return true


func _cell_of(inner: Rect2, p: Vector2, cols: int, rows: int) -> int:
	if not inner.grow(0.05).has_point(p):
		return -1
	var cx := clampi(int((p.x - inner.position.x) / NAV_CELL), 0, cols - 1)
	var cy := clampi(int((p.y - inner.position.y) / NAV_CELL), 0, rows - 1)
	return cy * cols + cx


# The furniture nodes on the route with the fewest obstacles from any start cell to `target`. An empty
# result means the way is already clear; [-2] means there is no route at all.
func _blockers_to(r: Room, inner: Rect2, cols: int, rows: int, starts: Array[int], target: int) -> Array:
	var props: Array = room_furniture.get(r, [])
	var owner_of := PackedInt32Array()
	owner_of.resize(cols * rows)
	owner_of.fill(-1)
	var rects: Array[Rect2] = []
	var nodes: Array[Node3D] = []
	for node: Node3D in props:
		if not is_instance_valid(node) or node.is_queued_for_deletion():
			continue
		var rect := _node_rect(r, node)
		if rect.has_area():
			rects.append(rect.grow(0.32))
			nodes.append(node)
	for k in rects.size():
		var rect: Rect2 = rects[k]
		var cx0 := maxi(0, int(floor((rect.position.x - inner.position.x) / NAV_CELL)))
		var cx1 := mini(cols - 1, int(floor((rect.end.x - inner.position.x) / NAV_CELL)))
		var cy0 := maxi(0, int(floor((rect.position.y - inner.position.y) / NAV_CELL)))
		var cy1 := mini(rows - 1, int(floor((rect.end.y - inner.position.y) / NAV_CELL)))
		for cy in range(cy0, cy1 + 1):
			for cx in range(cx0, cx1 + 1):
				var center := inner.position + Vector2((cx + 0.5) * NAV_CELL, (cy + 0.5) * NAV_CELL)
				if rect.has_point(center) and owner_of[cy * cols + cx] < 0:
					owner_of[cy * cols + cx] = k
	var dist := PackedInt32Array()
	dist.resize(cols * rows)
	dist.fill(-1)
	var parent := PackedInt32Array()
	parent.resize(cols * rows)
	parent.fill(-1)
	var current: Array[int] = []
	var upcoming: Array[int] = []
	for s in starts:
		if dist[s] < 0:
			dist[s] = 0 if owner_of[s] < 0 else 1
			(current if dist[s] == 0 else upcoming).append(s)
	var level := 0
	while (not current.is_empty() or not upcoming.is_empty()) and dist[target] < 0:
		if current.is_empty():
			level += 1
			current = upcoming
			upcoming = []
		while not current.is_empty():
			var c: int = current.pop_back()
			var cx := c % cols
			var cy := c / cols
			for step in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var nx: int = cx + step.x
				var ny: int = cy + step.y
				if nx < 0 or ny < 0 or nx >= cols or ny >= rows:
					continue
				var n := ny * cols + nx
				if dist[n] >= 0:
					continue
				parent[n] = c
				if owner_of[n] < 0:
					dist[n] = level
					current.append(n)
				else:
					dist[n] = level + 1
					upcoming.append(n)
	if dist[target] < 0:
		return [-2]
	var result: Array = []
	var at := target
	while at >= 0:
		var k := owner_of[at]
		if k >= 0 and not result.has(nodes[k]):
			result.append(nodes[k])
		at = parent[at]
	return result


# Scales the whole house up around the bathroom doorway; the bathroom and the player stay small.
func apply_giant(factor: float) -> void:
	var pivot := Vector3.ZERO
	for c in conns:
		if c["a"] == rooms[0]:
			var mid := (float(c["lo"]) + float(c["hi"])) / 2.0
			pivot = Vector3(mid, 0.0, float(c["c"])) if int(c["side"]) < 2 else Vector3(float(c["c"]), 0.0, mid)
			break
	scale = Vector3.ONE * factor
	position = pivot * (1.0 - factor)
	_fill_giant_doorway(factor)
	for child in get_children():
		if child is OmniLight3D:
			child.omni_range *= factor
			child.light_energy *= 1.5


# Scaling stretches the hallway's opening for the bathroom door to `factor` times the door's size, which
# leaves the wall above and beside the (unscaled) door open to the void. This fills it with wall in the
# unscaled world, leaving only the real doorway.
func _fill_giant_doorway(factor: float) -> void:
	for c in conns:
		if c["a"] != rooms[0]:
			continue
		var side: int = c["side"]
		var lo: float = c["lo"]
		var hi: float = c["hi"]
		var mid := (lo + hi) / 2.0
		var half := (hi - lo) / 2.0 * factor
		var door_top: float = c["y0"] + door_h
		var open_top: float = c["y0"] + door_h * factor
		var thick: float = rooms[0].wall_t * factor
		var boundary: float = c["c"]
		var away := _side_vec(side)
		var normal_pos := boundary + (away.z if side < 2 else away.x) * thick / 2.0
		var pal: Array = PALETTE["hallway"]
		var mat: Material = main._mat(pal[0])
		var pieces: Array[Dictionary] = [
			{"a0": mid - half, "a1": lo, "y0": c["y0"], "y1": open_top},
			{"a0": hi, "a1": mid + half, "y0": c["y0"], "y1": open_top},
			{"a0": lo, "a1": hi, "y0": door_top, "y1": open_top},
		]
		for piece in pieces:
			var length: float = piece["a1"] - piece["a0"]
			var height: float = piece["y1"] - piece["y0"]
			if length < 0.01 or height < 0.01:
				continue
			var along: float = (piece["a0"] + piece["a1"]) / 2.0
			var size := Vector3(length, height, thick) if side < 2 else Vector3(thick, height, length)
			var at := Vector3(along, piece["y0"] + height / 2.0, normal_pos) if side < 2 \
					else Vector3(normal_pos, piece["y0"] + height / 2.0, along)
			main._prop(main._box(size), at, mat, true, Vector3.ZERO, main)
		break


func toggle_door(body: Node) -> void:
	var is_open: bool = body.get_meta("open")
	var pivot: Node3D = body.get_meta("pivot")
	var angle: float = body.get_meta("open_angle")
	body.set_meta("open", not is_open)
	body.set_meta("label", "Open door" if is_open else "Close door")
	create_tween().tween_property(pivot, "rotation:y", 0.0 if is_open else angle, 0.4)


# --- Building ---

func _p(mesh: PrimitiveMesh, pos: Vector3, mat: Material, solid := true,
		rot := Vector3.ZERO, parent: Node = null) -> Node3D:
	return main._prop(mesh, pos, mat, solid, rot, parent if parent else (wall_parent if wall_parent != null else self))


func _b(parent: Node, size: Vector3, pos: Vector3, color: Color, solid := true) -> Node3D:
	return main._prop(main._box(size), pos, main._mat(color), solid, Vector3.ZERO, parent)


func _sphere(radius: float) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = radius
	s.height = radius * 2.0
	return s


func _pick(options: Array) -> Color:
	return options.pick_random()


func build() -> void:
	door_leaves.clear()
	for i in range(1, rooms.size()):
		_build_room(rooms[i])
	for c in conns:
		if c["kind"] == "door":
			_build_door(c)
	main.mesh_layers = 1


func _build_room(r: Room) -> void:
	main.mesh_layers = 2 if r.dark else 1
	var pal: Array = PALETTE.get(r.type, PALETTE["hallway"])
	var wall_mat: Material = main._mat(pal[0])
	if castle:
		if stone_mat == null:
			stone_mat = Crypt.wall_material() if crypt else Castle.wall_material()
		wall_mat = stone_mat
	if r.type == "stairs":
		_build_stairs(r, wall_mat)
	elif r.type == "maze":
		_build_maze(r)
	else:
		var c := r.rect.get_center()
		var floor_mat: Material
		if r.type == "courtyard" or r.type == "yard":
			floor_mat = Castle.grass_material(r.rect.size)
		elif crypt:
			floor_mat = Crypt.floor_material(r.rect.size)
		elif castle:
			floor_mat = Castle.floor_material(r.rect.size)
		else:
			floor_mat = _floor_material(r.type, pal[1], r.rect.size)
		_p(main._box(Vector3(r.rect.size.x, 0.1, r.rect.size.y)), Vector3(c.x, r.y0 - 0.05, c.y), floor_mat)
		if r.type != "courtyard" and r.type != "yard":
			var ceiling_mat: Material = main._mat(Castle.DARK_STONE) if castle else main._mat(Color(0.95, 0.95, 0.93))
			_p(main._box(Vector3(r.rect.size.x, 0.04, r.rect.size.y)), Vector3(c.x, r.y1 - 0.02, c.y), ceiling_mat)
		build_walls(r, wall_mat)
		if not r.dark:
			if r.type == "courtyard":
				_light(Vector3(c.x, r.y0 + 4.5, c.y), maxf(r.rect.size.x, r.rect.size.y) * 0.9, 0.8)
			elif r.type == "yard":
				_light(Vector3(c.x, r.y0 + 5.0, c.y), maxf(r.rect.size.x, r.rect.size.y) * 1.1, 1.0)
			elif crypt:
				_light(Vector3(c.x, r.y1 - 0.8, c.y), maxf(r.rect.size.x, r.rect.size.y) * 0.7 + 2.0, 0.22)
			elif castle:
				_light(Vector3(c.x, r.y1 - 0.5, c.y), maxf(r.rect.size.x, r.rect.size.y) * 0.8 + 3.0, 0.45)
			else:
				_light(Vector3(c.x, r.y0 + 2.5, c.y), maxf(r.rect.size.x, r.rect.size.y) * 0.75 + 2.0,
						0.5 if r.type == "attic" else 0.9)
		if r.boiler:
			_place_boiler(r)
		var first_prop := get_child_count()
		if crypt:
			Crypt.furnish(self, r)
		elif castle:
			Castle.furnish(self, r)
		else:
			_furnish(r)
		var props: Array[Node3D] = []
		for i in range(first_prop, get_child_count()):
			if get_child(i) is Node3D:
				props.append(get_child(i) as Node3D)
		room_furniture[r] = props
		_floor_spots(r)
	main.mesh_layers = 1


func _floor_material(type: String, color: Color, size: Vector2) -> Material:
	var m: StandardMaterial3D = main._mat(Color.WHITE)
	if type == "kitchen" or type == "bathroom2":
		var img := Image.create(2, 2, false, Image.FORMAT_RGB8)
		img.set_pixel(0, 0, color)
		img.set_pixel(1, 1, color)
		img.set_pixel(1, 0, color.darkened(0.45))
		img.set_pixel(0, 1, color.darkened(0.45))
		m.albedo_texture = ImageTexture.create_from_image(img)
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		m.uv1_scale = Vector3(size.x / 1.6, size.y / 1.6, 1)
	else:
		m.albedo_color = color
	return m


func _light(pos: Vector3, range_m: float, energy: float) -> void:
	if power_out:
		return
	var l := OmniLight3D.new()
	l.position = pos
	l.omni_range = range_m
	l.light_energy = energy
	l.light_color = Color(1.0, 0.95, 0.85)
	l.light_cull_mask = 1
	add_child(l)


func build_walls(r: Room, mat: Material) -> void:
	if giant and r == rooms[0]:
		wall_parent = main  # the scaled house would stretch the bathroom's walls and tiling
	for side in 4:
		var horizontal := side < 2
		var a_lo := r.rect.position.x if horizontal else r.rect.position.y + r.wall_t
		var a_hi := r.rect.end.x if horizontal else r.rect.end.y - r.wall_t
		var ops: Array[Dictionary] = []
		for o in r.openings:
			if o["side"] == side:
				ops.append(o)
		ops.sort_custom(func(a, b): return a["lo"] < b["lo"])
		var cursor := a_lo
		for o in ops:
			var oy: float = o["y0"]
			var o_lo: float = o["lo"]
			var o_hi: float = o["hi"]
			if o_lo > cursor:
				_wall_box(r, side, cursor, o_lo, r.y0, r.y1, mat)
			if oy > r.y0:
				_wall_box(r, side, o_lo, o_hi, r.y0, oy - 0.04, mat)  # stops inside the floor slab, not flush with it
			var top: float = oy + float(o.get("h", DOOR_H))
			if not upside_down and top < r.y1 - 0.01:
				_wall_box(r, side, o_lo, o_hi, top, r.y1, mat)
			cursor = o_hi
		if cursor < a_hi:
			_wall_box(r, side, cursor, a_hi, r.y0, r.y1, mat)
	wall_parent = null


func _wall_box(r: Room, side: int, a0: float, a1: float, ya: float, yb: float, mat: Material) -> void:
	if a1 - a0 < 0.01 or yb - ya < 0.01:
		return
	var t := r.wall_t
	var h := yb - ya
	var ym := (ya + yb) / 2.0
	var am := (a0 + a1) / 2.0
	match side:
		0:
			_p(main._box(Vector3(a1 - a0, h, t)), Vector3(am, ym, r.rect.end.y - t / 2.0), mat)
		1:
			_p(main._box(Vector3(a1 - a0, h, t)), Vector3(am, ym, r.rect.position.y + t / 2.0), mat)
		2:
			_p(main._box(Vector3(t, h, a1 - a0)), Vector3(r.rect.end.x - t / 2.0, ym, am), mat)
		_:
			_p(main._box(Vector3(t, h, a1 - a0)), Vector3(r.rect.position.x + t / 2.0, ym, am), mat)


func _build_door(c: Dictionary) -> void:
	var side: int = c["side"]
	var lo: float = c["lo"]
	var hi: float = c["hi"]
	var y0: float = c["y0"]
	var boundary: float = c["c"]
	var w := hi - lo
	var is_bath_door: bool = c["a"] == rooms[0]
	var holder: Node = main if (giant and is_bath_door) else self
	var along := Vector3.RIGHT if side < 2 else Vector3.BACK
	var normal := Vector3.BACK if side < 2 else Vector3.RIGHT
	var hinge_lo := randf() < 0.5
	var trim := FRAME_TRIM if castle else 0.0
	var hinge := lo + trim if hinge_lo else hi - trim
	var pivot := Node3D.new()
	pivot.position = Vector3(hinge, y0, boundary) if side < 2 else Vector3(boundary, y0, hinge)
	holder.add_child(pivot)
	var d := along if hinge_lo else -along
	var leaf_w := w - 2.0 * trim - 0.02
	var leaf_h := door_h - trim - 0.02
	var leaf_y := leaf_h / 2.0
	var knob_y := 1.0
	if upside_down:
		# The opening runs floor to ceiling, so the leaf does too: nothing to peek through.
		leaf_h = 3.0 - 0.02
		leaf_y = 1.5
	var leaf_size := Vector3(leaf_w, leaf_h, 0.05) if side < 2 else Vector3(0.05, leaf_h, leaf_w)
	var leaf_color := Castle.WOOD if castle else Color(0.5, 0.33, 0.2)
	var vault: bool = (c["b"] as Room).type == "treasure"
	var tomb: bool = (c["b"] as Room).type == "tomb"
	if vault:
		leaf_color = Castle.WOOD  # looks like any other castle door; only its label gives it away
	elif tomb:
		leaf_color = Color(0.3, 0.31, 0.33)
	var leaf := _b(pivot, leaf_size, d * (leaf_w / 2.0) + Vector3(0, leaf_y, 0), leaf_color)
	var knob_rot := Vector3(90, 0, 0) if side < 2 else Vector3(0, 0, 90)
	var knob_color := Castle.IRON.lightened(0.3) if castle else Color(0.8, 0.7, 0.3)
	_p(main._cyl(0.025, 0.1), d * (leaf_w / 2.0 - 0.12) + Vector3(0, knob_y - leaf_y, 0),
			main._mat(knob_color), false, knob_rot, leaf)
	if castle:
		for band_y in [-0.8, 0.0, 0.8]:
			var band := Vector3(leaf_size.x, 0.12, 0.07) if side < 2 else Vector3(0.07, 0.12, leaf_size.z)
			_b(leaf, band, Vector3(0, band_y, 0), Castle.IRON, false)
		Castle.frame(self, c)
	if vault:
		pass
	elif tomb:
		var rune := Vector3(leaf_size.x * 0.6, 0.12, 0.08) if side < 2 else Vector3(0.08, 0.12, leaf_size.z * 0.6)
		for rune_y in [-0.4, 0.1, 0.6]:
			_p(main._box(rune), Vector3(0, rune_y, 0), _glow_material(Color(0.3, 1.0, 0.5)), false, Vector3.ZERO, leaf)
	var swing := normal * (1.0 if randf() < 0.5 else -1.0)
	leaf.set_meta("kind", "door")
	leaf.set_meta("label", "Open door")
	leaf.set_meta("pivot", pivot)
	leaf.set_meta("open", false)
	leaf.set_meta("bath_door", is_bath_door)
	var open_angle := d.signed_angle_to(swing, Vector3.UP)
	leaf.set_meta("open_angle", open_angle)
	if giant and not is_bath_door:
		# Too heavy to move: it rests on the floor, left open a crack or most of the way.
		leaf.set_meta("stuck", true)
		leaf.set_meta("label", "Heavy door")
		leaf.set_meta("open", true)
		pivot.rotation.y = open_angle * [0.25, 0.4, 1.0].pick_random()
	if vault:
		leaf.set_meta("locked", true)
		leaf.set_meta("golden", true)
		leaf.set_meta("sealed", true)
		leaf.set_meta("label", "Golden door")
	elif tomb:
		leaf.set_meta("locked", true)
		leaf.set_meta("puzzle", true)
		leaf.set_meta("sealed", true)
		leaf.set_meta("label", "Sealed tomb door")
	door_leaves.append({"conn": c, "leaf": leaf})
	c["leaf"] = leaf


func _build_stairs(r: Room, wall_mat: Material) -> void:
	var out_vec := _side_vec(r.out_side)
	var dir := -out_vec if r.near_is_top else out_vec
	var center := r.rect.get_center()
	var root := Node3D.new()
	root.position = Vector3(center.x, 0, center.y)
	root.rotation.y = atan2(dir.x, dir.z)
	add_child(root)

	var y_lo := r.y0
	var y_hi := r.y0 + LEVEL_H
	var half := STAIR_LEN / 2.0
	var z0 := -half + STAIR_FOYER
	var z1 := z0 + STAIR_RUN
	var w := STAIR_W
	var wood: Material = main._mat(Color(0.45, 0.32, 0.2))

	_p(main._box(Vector3(w, 0.1, STAIR_LEN)), Vector3(0, y_lo - 0.05, 0), wood, true, Vector3.ZERO, root)
	_p(main._box(Vector3(w, 0.1, half - z1 + 0.1)), Vector3(0, y_hi - 0.05, (z1 - 0.1 + half) / 2.0),
			wood, true, Vector3.ZERO, root)
	_p(main._box(Vector3(w, 0.04, STAIR_LEN)), Vector3(0, y_hi + 2.98, 0),
			main._mat(Color(0.95, 0.95, 0.93)), true, Vector3.ZERO, root)

	var steps := 18
	for i in steps:
		var top := (i + 0.5) * LEVEL_H / steps
		_p(main._box(Vector3(w - 0.24, top, STAIR_RUN / steps)),
				Vector3(0, y_lo + top / 2.0, z0 + (i + 0.5) * STAIR_RUN / steps), wood, false, Vector3.ZERO, root)

	# Invisible slope the player walks on. It rides half a step above the tread centres so the camera
	# never ends up inside a tread, and its low end reaches under the floor for a smooth start.
	var hyp := sqrt(STAIR_RUN * STAIR_RUN + LEVEL_H * LEVEL_H)
	var ang := atan2(LEVEL_H, STAIR_RUN)
	var ramp := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(w - 0.2, 0.2, hyp + 0.5)
	cs.shape = shape
	ramp.add_child(cs)
	var up := Vector3(0, cos(ang), -sin(ang))
	var along_slope := Vector3(0, sin(ang), cos(ang))
	ramp.position = Vector3(0, y_lo + LEVEL_H / 2.0 + LEVEL_H / steps / 2.0, (z0 + z1) / 2.0) - up * 0.1 - along_slope * 0.25
	ramp.rotation.x = -ang
	root.add_child(ramp)

	build_walls(r, wall_mat)
	_light(Vector3(center.x, y_lo + 2.5, center.y), 5.0, 0.8)
	_light(Vector3(center.x, y_hi + 2.5, center.y), 5.0, 0.8)


func _maze_material(color: Color) -> StandardMaterial3D:
	return main._mat(color)


func _maze_gate(r: Room, g: int) -> Vector2i:
	match r.maze_side:
		0:
			return Vector2i(r.maze_k, g - 1)
		1:
			return Vector2i(r.maze_k, 0)
		2:
			return Vector2i(g - 1, r.maze_k)
	return Vector2i(0, r.maze_k)


# Top-left block of the 3x3 bathroom, far from the entrance.
func _maze_bath_spot(gate: Vector2i) -> Vector2i:
	for attempt in 50:
		var spot := Vector2i(5 + 2 * randi_range(0, 8), 5 + 2 * randi_range(0, 8))
		if absi(spot.x - gate.x) + absi(spot.y - gate.y) >= 14:
			return spot
	return Vector2i(21, 21)


# Growing-tree maze (mostly random picks, so many short branches) plus loops.
func _carve_maze(grid: Array[int], g: int) -> void:
	var active: Array[Vector2i] = [Vector2i(1, 1)]
	grid[g + 1] = 0
	while not active.is_empty():
		var idx := active.size() - 1 if randf() < 0.35 else randi_range(0, active.size() - 1)
		var cur := active[idx]
		var dirs: Array[Vector2i] = [Vector2i(2, 0), Vector2i(-2, 0), Vector2i(0, 2), Vector2i(0, -2)]
		dirs.shuffle()
		var carved := false
		for d in dirs:
			var nxt := cur + d
			if nxt.x > 0 and nxt.x < g - 1 and nxt.y > 0 and nxt.y < g - 1 and grid[nxt.y * g + nxt.x] == 1:
				var mid := cur + d / 2
				grid[mid.y * g + mid.x] = 0
				grid[nxt.y * g + nxt.x] = 0
				active.append(nxt)
				carved = true
				break
		if not carved:
			active.remove_at(idx)
	for j in range(1, g - 1):
		for i in range(1, g - 1):
			if (i + j) % 2 == 1 and grid[j * g + i] == 1 and randf() < 0.14:
				var a := Vector2i(i - 1, j) if i % 2 == 0 else Vector2i(i, j - 1)
				var c := Vector2i(i + 1, j) if i % 2 == 0 else Vector2i(i, j + 1)
				if grid[a.y * g + a.x] == 0 and grid[c.y * g + c.x] == 0:
					grid[j * g + i] = 0


# Large open rooms with several entrances. Styles: 0 column grid, 1 central pillar, 2 pit, 3 scattered columns.
func _carve_maze_rooms(grid: Array[int], g: int, bath: Vector2i) -> Array[Dictionary]:
	var sizes: Array[Vector2i] = [Vector2i(5, 5), Vector2i(9, 5), Vector2i(5, 9), Vector2i(11, 9),
			Vector2i(7, 7), Vector2i(9, 9)]
	sizes.shuffle()
	var styles := [0, 1, 2, 3, 0]
	styles.shuffle()
	var colors: Array[Color] = [Color(1, 0.15, 0.1), Color(0.2, 1, 0.3), Color(0.6, 0.2, 1),
			Color(1, 0.7, 0.1), Color(0.2, 0.8, 1)]
	colors.shuffle()
	var taken: Array[Rect2i] = [Rect2i(bath.x, bath.y, 3, 3)]
	var features: Array[Dictionary] = []
	for n in 5:
		var size := sizes[n]
		for attempt in 40:
			var x0 := 3 + 2 * randi_range(0, floori((g - 6 - size.x) / 2.0))
			var y0 := 3 + 2 * randi_range(0, floori((g - 6 - size.y) / 2.0))
			var rect := Rect2i(x0, y0, size.x, size.y)
			var blocked := false
			for t in taken:
				if rect.grow(3).intersects(t):
					blocked = true
			if blocked:
				continue
			taken.append(rect)
			_carve_room(grid, g, rect, styles[n])
			features.append({"rect": rect, "style": styles[n], "color": colors[n]})
			break
	return features


func _carve_room(grid: Array[int], g: int, rect: Rect2i, style: int) -> void:
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			grid[y * g + x] = 0
	for k in 5:
		var odd_x := rect.position.x + 2 * randi_range(0, floori((rect.size.x - 1) / 2.0))
		var odd_y := rect.position.y + 2 * randi_range(0, floori((rect.size.y - 1) / 2.0))
		var block := Vector2i.ZERO
		var outer := Vector2i.ZERO
		match randi_range(0, 3):
			0:
				block = Vector2i(odd_x, rect.position.y - 1)
				outer = Vector2i(odd_x, rect.position.y - 2)
			1:
				block = Vector2i(odd_x, rect.end.y)
				outer = Vector2i(odd_x, rect.end.y + 1)
			2:
				block = Vector2i(rect.position.x - 1, odd_y)
				outer = Vector2i(rect.position.x - 2, odd_y)
			_:
				block = Vector2i(rect.end.x, odd_y)
				outer = Vector2i(rect.end.x + 1, odd_y)
		if grid[outer.y * g + outer.x] == 0:
			grid[block.y * g + block.x] = 0
	var mid := Vector2i(rect.position.x + floori(rect.size.x / 2.0), rect.position.y + floori(rect.size.y / 2.0))
	if style == 1:
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				grid[(mid.y + dy) * g + mid.x + dx] = 1
	elif style == 2:
		grid[mid.y * g + mid.x] = 3


# Opens one side of the bathroom onto a corridor; returns {side, center} for the doorway.
func _open_bath_door(grid: Array[int], g: int, bath: Vector2i, origin: Vector2) -> Dictionary:
	var sides := [0, 1, 2, 3]
	sides.shuffle()
	for side in sides:
		var row := 2 * randi_range(0, 1)
		var block := Vector2i.ZERO
		var outer := Vector2i.ZERO
		match side:
			0:
				block = Vector2i(bath.x + row, bath.y + 3)
				outer = Vector2i(bath.x + row, bath.y + 4)
			1:
				block = Vector2i(bath.x + row, bath.y - 1)
				outer = Vector2i(bath.x + row, bath.y - 2)
			2:
				block = Vector2i(bath.x + 3, bath.y + row)
				outer = Vector2i(bath.x + 4, bath.y + row)
			_:
				block = Vector2i(bath.x - 1, bath.y + row)
				outer = Vector2i(bath.x - 2, bath.y + row)
		if grid[outer.y * g + outer.x] == 0:
			grid[block.y * g + block.x] = 0
			var center := origin.x + (block.x + 0.5) * MAZE_BLOCK if side < 2 \
					else origin.y + (block.y + 0.5) * MAZE_BLOCK
			return {"side": side, "center": center}
	grid[bath.y * g + bath.x - 1] = 0
	grid[bath.y * g + bath.x - 2] = 0
	return {"side": 3, "center": origin.y + (bath.y + 0.5) * MAZE_BLOCK}


# Consecutive cells in row j whose value is in `values`, as Vector2i(start, length).
func _row_runs(grid: Array[int], g: int, j: int, values: Array) -> Array[Vector2i]:
	var runs: Array[Vector2i] = []
	var i := 0
	while i < g:
		if values.has(grid[j * g + i]):
			var start := i
			while i < g and values.has(grid[j * g + i]):
				i += 1
			runs.append(Vector2i(start, i - start))
		else:
			i += 1
	return runs


func _column(r: Room, cell: Vector2i, radius: float, mat: Material, occupied: Dictionary) -> void:
	var b := MAZE_BLOCK
	_p(main._cyl(radius, 3.0), Vector3(r.rect.position.x + (cell.x + 0.5) * b, r.y0 + 1.5,
			r.rect.position.y + (cell.y + 0.5) * b), mat)
	occupied[cell] = true


func _build_maze(r: Room) -> void:
	var g := MAZE_CELLS * 2 + 1
	var b := MAZE_BLOCK
	var y0 := r.y0
	var origin := r.rect.position
	var grid: Array[int] = []  # 0 open, 1 wall, 2 bathroom, 3 pit
	grid.resize(g * g)
	grid.fill(1)

	var gate := _maze_gate(r, g)
	var bath := _maze_bath_spot(gate)
	for dy in 3:
		for dx in 3:
			grid[(bath.y + dy) * g + bath.x + dx] = 2
	_carve_maze(grid, g)
	grid[gate.y * g + gate.x] = 0
	var features := _carve_maze_rooms(grid, g, bath)
	var door := _open_bath_door(grid, g, bath, origin)

	var wall_mat := _maze_material(Color(0.14, 0.13, 0.12))
	var floor_mat := _maze_material(Color(0.1, 0.09, 0.08))
	var ceiling_mat := _maze_material(Color(0.07, 0.065, 0.06))
	for j in g:
		var z := origin.y + (j + 0.5) * b
		for run in _row_runs(grid, g, j, [0, 1]):
			var x := origin.x + (run.x + run.y / 2.0) * b
			_p(main._box(Vector3(run.y * b, 0.1, b)), Vector3(x, y0 - 0.05, z), floor_mat)
		for run in _row_runs(grid, g, j, [0, 1, 3]):
			var x := origin.x + (run.x + run.y / 2.0) * b
			_p(main._box(Vector3(run.y * b, 0.04, b)), Vector3(x, y0 + 2.98, z), ceiling_mat)
		for run in _row_runs(grid, g, j, [1]):
			var x := origin.x + (run.x + run.y / 2.0) * b
			_p(main._box(Vector3(run.y * b, 3.0, b)), Vector3(x, y0 + 1.5, z), wall_mat)
		for i in g:
			if grid[j * g + i] == 3:
				_build_pit(r, Vector2i(i, j))

	# Anything that falls through a pit (or off the map) goes back to the start.
	var net := Area3D.new()
	var net_shape := CollisionShape3D.new()
	var net_box := BoxShape3D.new()
	net_box.size = Vector3(r.rect.size.x, 1.0, r.rect.size.y)
	net_shape.shape = net_box
	net.add_child(net_shape)
	net.position = Vector3(r.rect.get_center().x, y0 - 6.0, r.rect.get_center().y)
	net.body_entered.connect(Callable(main, "_on_pit_entered"))
	add_child(net)

	var occupied := {}
	for f in features:
		_build_maze_feature(r, f, wall_mat, occupied)
	var placed := 0
	for attempt in 60:
		if placed >= 12:
			break
		var cell := Vector2i(1 + 2 * randi_range(0, MAZE_CELLS - 1), 1 + 2 * randi_range(0, MAZE_CELLS - 1))
		if grid[cell.y * g + cell.x] != 0 or occupied.has(cell):
			continue
		if absi(cell.x - gate.x) + absi(cell.y - gate.y) < 5:
			continue
		var in_room := false
		for f in features:
			if (f["rect"] as Rect2i).has_point(cell):
				in_room = true
		if in_room:
			continue
		_column(r, cell, randf_range(0.25, 0.5), wall_mat, occupied)
		placed += 1

	_build_maze_bathroom(r, bath, door)

	# Distance from the gate, so a bottle can be hidden deep inside.
	var dist: Array[int] = []
	dist.resize(g * g)
	dist.fill(-1)
	var queue: Array[Vector2i] = [gate]
	dist[gate.y * g + gate.x] = 0
	var head := 0
	while head < queue.size():
		var q := queue[head]
		head += 1
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var nb: Vector2i = q + d
			if nb.x < 0 or nb.y < 0 or nb.x >= g or nb.y >= g:
				continue
			if grid[nb.y * g + nb.x] == 0 and dist[nb.y * g + nb.x] == -1:
				dist[nb.y * g + nb.x] = dist[q.y * g + q.x] + 1
				queue.append(nb)
	var cells: Array[Vector2i] = []
	for j in range(1, g, 2):
		for i in range(1, g, 2):
			var cell := Vector2i(i, j)
			if dist[j * g + i] >= 0 and not occupied.has(cell):
				cells.append(cell)
	cells.sort_custom(func(a, c): return dist[a.y * g + a.x] > dist[c.y * g + c.x])
	var deep := maxi(1, floori(cells.size() / 4.0))
	for n in 6:
		var cell := cells[randi_range(0, deep - 1)]
		r.spots.append(Vector3(origin.x + (cell.x + 0.5) * b, y0 + 0.11, origin.y + (cell.y + 0.5) * b))


func _build_pit(r: Room, cell: Vector2i) -> void:
	var b := MAZE_BLOCK
	var center := Vector3(r.rect.position.x + (cell.x + 0.5) * b, r.y0, r.rect.position.y + (cell.y + 0.5) * b)
	var area := Area3D.new()
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(b - 0.4, 2.4, b - 0.4)
	cs.shape = shape
	area.add_child(cs)
	area.position = center + Vector3(0, -1.5, 0)
	area.body_entered.connect(Callable(main, "_on_pit_entered"))
	add_child(area)
	# Faint red rim: the only warning before the edge.
	var rim: StandardMaterial3D = main._mat(Color(0.35, 0.0, 0.0))
	rim.emission_enabled = true
	rim.emission = Color(0.6, 0.0, 0.0)
	rim.emission_energy_multiplier = 0.6
	for s in [-1.0, 1.0]:
		_p(main._box(Vector3(b, 0.03, 0.08)), center + Vector3(0, 0.015, s * (b / 2.0 - 0.04)), rim, false)
		_p(main._box(Vector3(0.08, 0.03, b)), center + Vector3(s * (b / 2.0 - 0.04), 0.015, 0), rim, false)


# Each big room gets its own coloured light so it can be told apart from the others.
func _build_maze_feature(r: Room, f: Dictionary, black: Material, occupied: Dictionary) -> void:
	var b := MAZE_BLOCK
	var rect: Rect2i = f["rect"]
	var style: int = f["style"]
	var color: Color = f["color"]
	var center := Vector3(
		r.rect.position.x + (rect.position.x + rect.size.x / 2.0) * b, r.y0,
		r.rect.position.y + (rect.position.y + rect.size.y / 2.0) * b)
	var light := OmniLight3D.new()
	light.position = center + Vector3(0, 2.3, 0)
	light.omni_range = maxf(rect.size.x, rect.size.y) * b * 0.7
	light.light_energy = 1.2
	light.light_color = color
	light.shadow_enabled = true
	add_child(light)
	if style == 0:
		for cx in range(rect.position.x + 1, rect.end.x - 1, 2):
			for cy in range(rect.position.y + 1, rect.end.y - 1, 2):
				_column(r, Vector2i(cx, cy), 0.5, black, occupied)
	elif style == 3:
		var mid := Vector2i(rect.position.x + floori(rect.size.x / 2.0), rect.position.y + floori(rect.size.y / 2.0))
		for n in 6:
			var cell := Vector2i(rect.position.x + randi_range(0, rect.size.x - 1),
					rect.position.y + randi_range(0, rect.size.y - 1))
			if cell != mid:
				_column(r, cell, randf_range(0.2, 0.3), black, occupied)


# A normal, lit bathroom hidden in the maze with a working shower and no products.
func _build_maze_bathroom(r: Room, bath: Vector2i, door: Dictionary) -> void:
	var b := MAZE_BLOCK
	var room := Room.new()
	room.type = "bathroom2"
	room.rect = Rect2(r.rect.position + Vector2(bath.x, bath.y) * b, Vector2(3, 3) * b)
	room.lvl_lo = r.lvl_lo
	room.lvl_hi = r.lvl_hi
	room.y0 = r.y0
	room.y1 = r.y0 + 3.0
	var side: int = door["side"]
	var center: float = door["center"]
	r.lit_zones.append(room.rect)
	_add_opening(room, side, center - 0.6, center + 0.6, r.y0, "arch")

	var c := room.rect.get_center()
	_p(main._box(Vector3(room.rect.size.x, 0.1, room.rect.size.y)), Vector3(c.x, r.y0 - 0.05, c.y),
			_floor_material("bathroom2", Color(0.85, 0.9, 0.92), room.rect.size))
	_p(main._box(Vector3(room.rect.size.x, 0.04, room.rect.size.y)), Vector3(c.x, r.y0 + 2.98, c.y),
			main._mat(Color(0.95, 0.95, 0.93)))
	build_walls(room, main._mat(Color(0.75, 0.88, 0.92)))
	var light := OmniLight3D.new()
	light.position = Vector3(c.x, r.y0 + 2.5, c.y)
	light.omni_range = 7.0
	light.light_energy = 1.3
	add_child(light)
	_build_maze_shower(room, side)
	_furnish_bathroom(room)


func _mount_at(pos: Vector3, n: Vector3) -> Node3D:
	var m := Node3D.new()
	m.position = pos + n * 0.03
	m.rotation.y = atan2(n.x, n.z)
	add_child(m)
	return m


func _build_maze_shower(room: Room, door_side: int) -> void:
	var inner := room.interior()
	var sx := 1 if randf() < 0.5 else -1
	var sz := 1 if randf() < 0.5 else -1
	match door_side:
		2:
			sx = -1
		3:
			sx = 1
		0:
			sz = -1
		1:
			sz = 1
	var size := 1.8
	var wall_x := inner.end.x if sx > 0 else inner.position.x
	var wall_z := inner.end.y if sz > 0 else inner.position.y
	var x_in := wall_x - sx * size
	var z_in := wall_z - sz * size
	var stall := Rect2(minf(wall_x, x_in), minf(wall_z, z_in), size, size)
	var center := stall.get_center()
	room.used.append(stall.grow(0.7))
	var y0 := room.y0

	_b(self, Vector3(size, 0.03, size), Vector3(center.x, y0 + 0.015, center.y), Color(0.6, 0.65, 0.7), false)
	_p(main._box(Vector3(0.02, 3.0, size)), Vector3(wall_x - sx * 0.01, y0 + 1.5, center.y),
			main._tile_material(size, 3.0), false)
	_p(main._box(Vector3(size, 3.0, 0.02)), Vector3(center.x, y0 + 1.5, wall_z - sz * 0.01),
			main._tile_material(size, 3.0), false)

	var glass: Material = main._mat(Color(0.7, 0.9, 1.0, 0.25))
	var a_len := size
	var a_center := center.y
	var b_len := size
	var b_center := center.x
	if randf() < 0.5:
		a_len = size - 0.9
		a_center = wall_z - sz * a_len / 2.0
	else:
		b_len = size - 0.9
		b_center = wall_x - sx * b_len / 2.0
	_p(main._box(Vector3(0.04, 2.2, a_len)), Vector3(x_in, y0 + 1.1, a_center), glass).set_meta("no_drop", true)
	_p(main._box(Vector3(b_len, 2.2, 0.04)), Vector3(b_center, y0 + 1.1, z_in), glass).set_meta("no_drop", true)

	var handle_mount := _mount_at(Vector3(wall_x, y0 + 1.15, center.y), Vector3(-sx, 0, 0))
	var nozzle_dir := Vector3(0, 0, -sz)
	var nozzle_mount := _mount_at(Vector3(center.x, y0 + 2.25, wall_z), nozzle_dir)
	var pivot: Node3D = main.make_handle(handle_mount)
	var spray: CPUParticles3D = main.make_nozzle(nozzle_mount, nozzle_dir)
	main.register_shower(stall, y0, pivot, spray)


# --- Furniture ---

func _free(r: Room, rect: Rect2) -> bool:
	for u in r.used:
		if rect.intersects(u):
			return false
	return true


# Node on a wall of the room; local +z points into the room. Returns null if nothing fits.
func _wall(r: Room, width: float, depth: float, clearance := 0.1, sides: Array = [0, 1, 2, 3]) -> Node3D:
	var inner := r.interior()
	var c := inner.get_center()
	for attempt in 40:
		var side: int = sides.pick_random()
		var length := inner.size.x if side < 2 else inner.size.y
		var half := length / 2.0 - width / 2.0 - 0.1
		if half < 0.0:
			continue
		var along := randf_range(-half, half)
		var rect: Rect2
		var point: Vector3
		match side:
			0:
				rect = Rect2(c.x + along - width / 2.0, inner.end.y - depth, width, depth)
				point = Vector3(c.x + along, r.y0, inner.end.y)
			1:
				rect = Rect2(c.x + along - width / 2.0, inner.position.y, width, depth)
				point = Vector3(c.x + along, r.y0, inner.position.y)
			2:
				rect = Rect2(inner.end.x - depth, c.y + along - width / 2.0, depth, width)
				point = Vector3(inner.end.x, r.y0, c.y + along)
			_:
				rect = Rect2(inner.position.x, c.y + along - width / 2.0, depth, width)
				point = Vector3(inner.position.x, r.y0, c.y + along)
		if _free(r, rect.grow(clearance)):
			r.used.append(rect)
			var n := -_side_vec(side)
			var m := Node3D.new()
			m.position = point
			m.rotation.y = atan2(n.x, n.z)
			add_child(m)
			return m
	return null


# Free spot away from the walls; returns Vector2.INF if nothing fits.
func _floor(r: Room, size: Vector2, margin: float) -> Vector2:
	var inner := r.interior().grow(-margin)
	var half := size / 2.0
	if inner.size.x < size.x or inner.size.y < size.y:
		return Vector2.INF
	for attempt in 40:
		var c := Vector2(randf_range(inner.position.x + half.x, inner.end.x - half.x),
				randf_range(inner.position.y + half.y, inner.end.y - half.y))
		var rect := Rect2(c - half, size)
		if _free(r, rect.grow(0.3)):
			r.used.append(rect)
			return c
	return Vector2.INF


func _spot(r: Room, m: Node3D, local: Vector3) -> void:
	r.spots.append(m.to_global(local))


func _floor_spots(r: Room) -> void:
	var inner := r.interior().grow(-0.5)
	if inner.size.x < 0.5 or inner.size.y < 0.5:
		return
	var added := 0
	for attempt in 30:
		if added >= 3:
			break
		var p := Vector2(randf_range(inner.position.x, inner.end.x), randf_range(inner.position.y, inner.end.y))
		if _free(r, Rect2(p - Vector2(0.25, 0.25), Vector2(0.5, 0.5))):
			r.spots.append(Vector3(p.x, r.y0 + 0.11, p.y))
			added += 1


func _furnish(r: Room) -> void:
	match r.type:
		"living":
			_furnish_living(r)
		"kitchen":
			_furnish_kitchen(r)
		"dining":
			_furnish_dining(r)
		"bedroom":
			_furnish_bedroom(r)
		"hallway":
			_furnish_hallway(r)
		"bathroom2":
			_furnish_bathroom(r)
		"attic":
			_furnish_attic(r)
		"basement":
			_furnish_basement(r)
		"closet":
			_furnish_closet(r)
		"great_hall":
			_furnish_great_hall(r)
		"throne_room":
			_furnish_throne_room(r)
		"tower":
			_furnish_tower(r)
		"tower_top":
			_furnish_tower_top(r)
		"yard":
			_furnish_yard(r)


func _rug(r: Room, size: Vector2, color: Color) -> void:
	var c := r.interior().get_center()
	_b(self, Vector3(size.x, 0.02, size.y), Vector3(c.x, r.y0 + 0.01, c.y), color, false)


func _plant(r: Room) -> void:
	var m := _wall(r, 0.6, 0.6)
	if m == null:
		return
	_p(main._cyl(0.2, 0.3), Vector3(0, 0.15, 0.3), main._mat(Color(0.65, 0.35, 0.25)), true, Vector3.ZERO, m)
	_p(_sphere(0.3), Vector3(0, 0.7, 0.3), main._mat(Color(0.2, 0.55, 0.25)), false, Vector3.ZERO, m)


func _furnish_living(r: Room) -> void:
	var wood := Color(0.4, 0.28, 0.18)
	var sofa_color := _pick([Color(0.35, 0.4, 0.55), Color(0.5, 0.3, 0.3), Color(0.35, 0.5, 0.4), Color(0.45, 0.45, 0.45)])
	var m := _wall(r, 2.3, 1.0)
	if m != null:
		_b(m, Vector3(1.6, 0.4, 0.9), Vector3(0, 0.2, 0.45), sofa_color)
		_b(m, Vector3(1.6, 0.5, 0.2), Vector3(0, 0.65, 0.1), sofa_color)
		_b(m, Vector3(0.2, 0.7, 0.9), Vector3(-0.9, 0.35, 0.45), sofa_color.darkened(0.15))
		_b(m, Vector3(0.2, 0.7, 0.9), Vector3(0.9, 0.35, 0.45), sofa_color.darkened(0.15))
	m = _wall(r, 1.6, 0.5)
	if m != null:
		_b(m, Vector3(1.5, 0.45, 0.4), Vector3(0, 0.225, 0.2), wood)
		_b(m, Vector3(1.1, 0.65, 0.05), Vector3(0, 0.85, 0.2), Color(0.05, 0.05, 0.07), false)
		_spot(r, m, Vector3(0.6, 0.56, 0.2))
	m = _wall(r, 1.0, 0.4)
	if m != null:
		_b(m, Vector3(1.0, 1.9, 0.35), Vector3(0, 0.95, 0.175), wood)
		for i in 5:
			_b(m, Vector3(0.12, 0.28, 0.2), Vector3(-0.35 + i * 0.17, 1.35, 0.24),
					_pick([Color(0.7, 0.2, 0.2), Color(0.2, 0.4, 0.7), Color(0.8, 0.7, 0.2)]), false)
	var c := _floor(r, Vector2(1.1, 0.65), 0.6)
	if c != Vector2.INF:
		_b(self, Vector3(1.1, 0.4, 0.65), Vector3(c.x, r.y0 + 0.2, c.y), wood)
		r.spots.append(Vector3(c.x, r.y0 + 0.51, c.y))
	if r.rect.size.x * r.rect.size.y > 25.0:
		c = _floor(r, Vector2(0.9, 0.9), 0.6)
		if c != Vector2.INF:
			_b(self, Vector3(0.9, 0.45, 0.9), Vector3(c.x, r.y0 + 0.225, c.y), sofa_color.darkened(0.1))
			_b(self, Vector3(0.9, 0.5, 0.2), Vector3(c.x, r.y0 + 0.7, c.y - 0.35), sofa_color.darkened(0.1), false)
	_plant(r)
	_rug(r, Vector2(2.4, 1.6), Color(0.6, 0.35, 0.35))


func _furnish_kitchen(r: Room) -> void:
	var count := randi_range(3, 5)
	var width := count * 0.6
	var m := _wall(r, width, 0.7)
	if m != null:
		_b(m, Vector3(width, 0.9, 0.62), Vector3(0, 0.45, 0.31), Color(0.8, 0.75, 0.65))
		_b(m, Vector3(width + 0.02, 0.04, 0.66), Vector3(0, 0.92, 0.33), Color(0.25, 0.25, 0.28))
		_b(m, Vector3(0.5, 0.02, 0.4), Vector3(-width / 2.0 + 0.4, 0.945, 0.31), Color(0.75, 0.78, 0.8), false)
		_b(m, Vector3(width, 0.7, 0.35), Vector3(0, 1.75, 0.175), Color(0.8, 0.75, 0.65))
		_spot(r, m, Vector3(width / 2.0 - 0.3, 1.05, 0.33))
	m = _wall(r, 0.8, 0.8)
	if m != null:
		_b(m, Vector3(0.75, 1.8, 0.7), Vector3(0, 0.9, 0.35), Color(0.85, 0.87, 0.88))
		_b(m, Vector3(0.04, 0.5, 0.04), Vector3(0.3, 1.2, 0.72), Color(0.4, 0.4, 0.4), false)
	m = _wall(r, 0.7, 0.7)
	if m != null:
		_b(m, Vector3(0.65, 0.9, 0.62), Vector3(0, 0.45, 0.31), Color(0.7, 0.7, 0.72))
		_b(m, Vector3(0.6, 0.02, 0.55), Vector3(0, 0.91, 0.31), Color(0.08, 0.08, 0.08), false)
		_spot(r, m, Vector3(0, 1.02, 0.31))
	if r.rect.size.x * r.rect.size.y > 18.0:
		var c := _floor(r, Vector2(1.8, 0.9), 0.9)
		if c != Vector2.INF:
			_b(self, Vector3(1.8, 0.9, 0.9), Vector3(c.x, r.y0 + 0.45, c.y), Color(0.75, 0.65, 0.5))
			_b(self, Vector3(1.9, 0.04, 1.0), Vector3(c.x, r.y0 + 0.92, c.y), Color(0.9, 0.9, 0.9), false)
			r.spots.append(Vector3(c.x, r.y0 + 1.03, c.y))
	_plant(r)


func _furnish_dining(r: Room) -> void:
	var wood := Color(0.45, 0.3, 0.18)
	var c := _floor(r, Vector2(2.6, 1.8), 0.2)
	if c != Vector2.INF:
		_b(self, Vector3(1.8, 0.06, 0.95), Vector3(c.x, r.y0 + 0.74, c.y), wood)
		for lx in [-0.8, 0.8]:
			for lz in [-0.4, 0.4]:
				_b(self, Vector3(0.07, 0.72, 0.07), Vector3(c.x + lx, r.y0 + 0.36, c.y + lz), wood)
		for cx in [-0.5, 0.5]:
			for cz in [-0.75, 0.75]:
				_b(self, Vector3(0.45, 0.05, 0.45), Vector3(c.x + cx, r.y0 + 0.45, c.y + cz), wood.lightened(0.15), false)
				_b(self, Vector3(0.43, 0.5, 0.05), Vector3(c.x + cx, r.y0 + 0.7, c.y + cz + signf(cz) * 0.22), wood.lightened(0.15), false)
				for lx in [-0.18, 0.18]:
					for lz in [-0.18, 0.18]:
						_b(self, Vector3(0.04, 0.45, 0.04), Vector3(c.x + cx + lx, r.y0 + 0.225, c.y + cz + lz), wood, false)
		r.spots.append(Vector3(c.x, r.y0 + 0.85, c.y))
	var m := _wall(r, 1.4, 0.5)
	if m != null:
		_b(m, Vector3(1.4, 0.85, 0.45), Vector3(0, 0.425, 0.225), wood)
		_spot(r, m, Vector3(0.4, 0.96, 0.225))
	_plant(r)


func _furnish_bedroom(r: Room) -> void:
	var frame := Color(0.4, 0.28, 0.18)
	var m := _wall(r, 2.3, 2.2)
	if m != null:
		_b(m, Vector3(1.6, 0.35, 2.1), Vector3(0, 0.175, 1.05), frame)
		_b(m, Vector3(1.5, 0.2, 2.0), Vector3(0, 0.45, 1.05), Color(0.95, 0.95, 0.95), false)
		_b(m, Vector3(1.64, 0.9, 0.08), Vector3(0, 0.55, 0.04), frame)
		_b(m, Vector3(1.52, 0.12, 1.2), Vector3(0, 0.58, 1.4), _pick([Color(0.3, 0.4, 0.7), Color(0.7, 0.3, 0.35), Color(0.35, 0.6, 0.45)]), false)
		for px in [-0.4, 0.4]:
			_b(m, Vector3(0.5, 0.12, 0.3), Vector3(px, 0.6, 0.35), Color(1, 1, 1), false)
		for nx in [-1.05, 1.05]:
			_b(m, Vector3(0.4, 0.5, 0.4), Vector3(nx, 0.25, 0.25), frame)
			_spot(r, m, Vector3(nx, 0.61, 0.25))
	m = _wall(r, 1.4, 0.65)
	if m != null:
		_b(m, Vector3(1.4, 2.1, 0.6), Vector3(0, 1.05, 0.3), frame.lightened(0.1))
		_b(m, Vector3(0.02, 1.9, 0.02), Vector3(0, 1.05, 0.61), Color(0.2, 0.15, 0.1), false)
	m = _wall(r, 1.0, 0.5)
	if m != null:
		_b(m, Vector3(1.0, 0.85, 0.5), Vector3(0, 0.425, 0.25), frame)
		_spot(r, m, Vector3(0, 0.96, 0.25))
	if randf() < 0.5:
		m = _wall(r, 1.3, 0.9)
		if m != null:
			_b(m, Vector3(1.2, 0.05, 0.6), Vector3(0, 0.74, 0.3), frame.lightened(0.2))
			_b(m, Vector3(0.05, 0.72, 0.55), Vector3(-0.55, 0.36, 0.3), frame.lightened(0.2))
			_b(m, Vector3(0.05, 0.72, 0.55), Vector3(0.55, 0.36, 0.3), frame.lightened(0.2))
			_b(m, Vector3(0.45, 0.05, 0.45), Vector3(0, 0.45, 0.75), Color(0.3, 0.3, 0.35), false)
			_spot(r, m, Vector3(0.3, 0.85, 0.3))
	_rug(r, Vector2(2.0, 1.4), Color(0.45, 0.5, 0.6))


func _furnish_hallway(r: Room) -> void:
	var inner := r.interior()
	var run := Vector3(inner.size.x - 1.0, 0.02, 0.8) if inner.size.x > inner.size.y \
			else Vector3(0.8, 0.02, inner.size.y - 1.0)
	var c := inner.get_center()
	_b(self, run, Vector3(c.x, r.y0 + 0.01, c.y), Color(0.55, 0.2, 0.2), false)
	var m := _wall(r, 0.9, 0.4)
	if m != null:
		_b(m, Vector3(0.9, 0.05, 0.35), Vector3(0, 0.8, 0.2), Color(0.4, 0.28, 0.18))
		_b(m, Vector3(0.06, 0.78, 0.3), Vector3(-0.4, 0.39, 0.2), Color(0.4, 0.28, 0.18))
		_b(m, Vector3(0.06, 0.78, 0.3), Vector3(0.4, 0.39, 0.2), Color(0.4, 0.28, 0.18))
		_spot(r, m, Vector3(0, 0.91, 0.2))
	for i in 3:
		_picture(r)


func _photo_textures() -> Array[Texture2D]:
	if photos.is_empty():
		var found: Array[String] = []
		for file in DirAccess.get_files_at(PHOTO_DIR):
			var file_name := file.trim_suffix(".import")  # exported builds only list the .import files
			if file_name.get_extension().to_lower() in ["jpg", "jpeg", "png", "webp"] and not found.has(file_name):
				found.append(file_name)
		found.sort()
		for file_name in found:
			var tex := load(PHOTO_DIR + file_name) as Texture2D
			if tex != null:
				photos.append(tex)
	return photos


# A framed photo on a wall, sized to the picture's proportions. Every frame in a level gets a different
# photo until all of them have been used once.
func _picture(r: Room) -> void:
	var textures := _photo_textures()
	if textures.is_empty():
		return
	if photo_bag.is_empty():
		photo_bag.assign(textures)
		photo_bag.shuffle()
	var tex: Texture2D = photo_bag.back()
	var aspect := float(tex.get_width()) / float(tex.get_height())
	var pic_w := clampf(0.5 * aspect, 0.4, 0.9)
	var pic_h := pic_w / aspect
	var m := _wall(r, pic_w + 0.12, 0.05, 0.0)
	if m == null:
		return
	photo_bag.pop_back()
	_b(m, Vector3(pic_w + 0.1, pic_h + 0.1, 0.03), Vector3(0, 1.6, 0.02), Color(0.35, 0.22, 0.12), false)
	var mat: StandardMaterial3D = main._mat(Color.WHITE)
	mat.albedo_texture = tex
	var quad := QuadMesh.new()
	quad.size = Vector2(pic_w, pic_h)
	_p(quad, Vector3(0, 1.6, 0.037), mat, false, Vector3.ZERO, m)


func _furnish_bathroom(r: Room) -> void:
	var porcelain := Color(0.97, 0.97, 0.97)
	var m := _wall(r, 0.5, 0.8)
	if m != null:
		_b(m, Vector3(0.5, 0.5, 0.25), Vector3(0, 0.7, 0.125), porcelain)
		_p(main._cyl(0.22, 0.45), Vector3(0, 0.225, 0.5), main._mat(porcelain), true, Vector3.ZERO, m)
	m = _wall(r, 1.0, 0.55)
	if m != null:
		_b(m, Vector3(0.9, 0.85, 0.5), Vector3(0, 0.425, 0.25), Color(0.55, 0.4, 0.28))
		_b(m, Vector3(1.0, 0.05, 0.55), Vector3(0, 0.875, 0.275), porcelain)
		_b(m, Vector3(0.7, 0.03, 0.4), Vector3(0, 0.91, 0.3), Color(0.8, 0.9, 1.0), false)
		_b(m, Vector3(0.7, 0.7, 0.03), Vector3(0, 1.6, 0.015), Color(0.7, 0.85, 0.95), false)
		_spot(r, m, Vector3(0.38, 1.01, 0.3))
	m = _wall(r, 1.7, 0.85)
	if m != null:
		_b(m, Vector3(1.7, 0.55, 0.8), Vector3(0, 0.275, 0.4), porcelain)
		_b(m, Vector3(1.5, 0.02, 0.6), Vector3(0, 0.56, 0.4), Color(0.65, 0.8, 0.9), false)
		_b(m, Vector3(0.1, 0.2, 0.1), Vector3(0.7, 0.65, 0.06), Color(0.75, 0.78, 0.8), false)
		_spot(r, m, Vector3(-0.75, 0.66, 0.4))


func _furnish_yard(r: Room) -> void:
	var inner := r.interior()
	var c := inner.get_center()
	var gate_side := 0
	for o in r.openings:
		gate_side = int(o["side"])
	var away := -_side_vec(gate_side)  # from the gate towards the far fence
	var side_dir := Vector3(away.z, 0, -away.x)
	var depth := inner.size.y if gate_side < 2 else inner.size.x
	var stake := Vector3(c.x, r.y0, c.y) + away * depth * 0.15
	dog_stake = stake
	var angle := randf() * TAU
	yard_spot = stake + Vector3(cos(angle), 0, sin(angle)) * 1.1 + Vector3(0, 0.11, 0)
	r.used.append(Rect2(Vector2(stake.x, stake.z) - Vector2(2.0, 2.0), Vector2(4.0, 4.0)))
	_p(main._cyl(0.04, 0.5), stake + Vector3(0, 0.25, 0), main._mat(Color(0.45, 0.46, 0.5)), false)
	var ring := TorusMesh.new()
	ring.inner_radius = 0.03
	ring.outer_radius = 0.06
	_p(ring, stake + Vector3(0, 0.45, 0), main._mat(Color(0.35, 0.36, 0.4)), false, Vector3(90, 0, 0))

	# The kennel stands against the far fence, facing the gate.
	var kennel := Node3D.new()
	kennel.position = Vector3(c.x, r.y0, c.y) + away * (depth / 2.0 - 0.9) + side_dir * 2.2
	kennel.rotation.y = atan2(-away.x, -away.z)
	add_child(kennel)
	var wood := Color(0.55, 0.36, 0.2)
	_b(kennel, Vector3(1.0, 0.8, 1.2), Vector3(0, 0.4, 0), wood)
	_b(kennel, Vector3(0.45, 0.5, 0.02), Vector3(0, 0.27, 0.605), Color(0.05, 0.04, 0.04), false)
	for slope in [-1.0, 1.0]:
		var roof := _b(kennel, Vector3(0.62, 0.05, 1.3), Vector3(slope * 0.27, 0.92, 0), Color(0.6, 0.2, 0.18), false)
		roof.rotation_degrees.z = -slope * 35.0
	_p(main._cyl(0.15, 0.06), Vector3(c.x, r.y0 + 0.03, c.y) + away * (depth / 2.0 - 2.0) + side_dir * 0.9,
			main._mat(Color(0.8, 0.2, 0.2)), false)
	for i in 6:
		var bush := Vector3(c.x, r.y0, c.y) + away * randf_range(-depth / 2.0 + 0.6, depth / 2.0 - 0.6) \
				+ side_dir * (inner.size.x if gate_side < 2 else inner.size.y) * (0.5 if i % 2 == 0 else -0.5) * 0.92
		_p(_sphere(randf_range(0.35, 0.6)), bush + Vector3(0, 0.3, 0), main._mat(Color(0.15, 0.45, 0.18)), false)
	for i in 10:
		var flower := Vector2(randf_range(inner.position.x + 0.5, inner.end.x - 0.5), randf_range(inner.position.y + 0.5, inner.end.y - 0.5))
		if _free(r, Rect2(flower - Vector2(0.2, 0.2), Vector2(0.4, 0.4))):
			_p(main._cyl(0.06, 0.03), Vector3(flower.x, r.y0 + 0.02, flower.y), main._mat(
					[Color(0.95, 0.3, 0.4), Color(0.98, 0.85, 0.2), Color(0.8, 0.5, 0.95)].pick_random()), false)


func _furnish_closet(r: Room) -> void:
	var inner := r.interior()
	var c := inner.get_center()
	var side: int = int(r.openings[0]["side"]) ^ 1  # the wall opposite the door
	var n := -_side_vec(side)
	var point := Vector3(c.x, r.y0, c.y)
	var length := inner.size.x if side < 2 else inner.size.y
	match side:
		0:
			point.z = inner.end.y
		1:
			point.z = inner.position.y
		2:
			point.x = inner.end.x
		_:
			point.x = inner.position.x
	var m := Node3D.new()
	m.position = point
	m.rotation.y = atan2(n.x, n.z)
	add_child(m)
	var w := minf(length - 0.1, 1.5)
	var wood := Color(0.55, 0.4, 0.28)
	_b(m, Vector3(0.05, 1.8, 0.4), Vector3(-w / 2.0, 0.9, 0.2), wood)
	_b(m, Vector3(0.05, 1.8, 0.4), Vector3(w / 2.0, 0.9, 0.2), wood)
	for y in [0.55, 1.15, 1.75]:
		_b(m, Vector3(w, 0.05, 0.4), Vector3(0, y, 0.2), wood)
		for x in [-w / 3.0, w / 3.0]:
			_b(m, Vector3(0.28, 0.25, 0.3), Vector3(x, y + 0.15, 0.2),
					_pick([Color(0.6, 0.5, 0.35), Color(0.4, 0.45, 0.6), Color(0.6, 0.35, 0.35)]), false)
	_spot(r, m, Vector3(0, 0.67, 0.2))
	r.spots.append(Vector3(c.x, r.y0 + 0.11, c.y))


func _glow_material(color: Color) -> StandardMaterial3D:
	var m: StandardMaterial3D = main._mat(color)
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = 1.5
	return m


func _banners(r: Room, count: int) -> void:
	for i in count:
		var m := _wall(r, 1.0, 0.1, 0.0)
		if m != null:
			_b(m, Vector3(0.8, 2.0, 0.03), Vector3(0, 1.6, 0.03),
					_pick([Color(0.7, 0.1, 0.12), Color(0.15, 0.2, 0.6), Color(0.85, 0.7, 0.15)]), false)


func _armor_stand(r: Room) -> void:
	var m := _wall(r, 0.8, 0.7)
	if m == null:
		return
	var steel: Material = main._mat(Color(0.6, 0.62, 0.66))
	_p(main._box(Vector3(0.5, 0.08, 0.5)), Vector3(0, 0.04, 0.35), steel, true, Vector3.ZERO, m)
	_p(main._cyl(0.2, 1.0), Vector3(0, 0.6, 0.35), steel, true, Vector3.ZERO, m)
	_p(_sphere(0.17), Vector3(0, 1.3, 0.35), steel, false, Vector3.ZERO, m)
	_p(main._cyl(0.015, 1.9), Vector3(0.3, 0.95, 0.35), main._mat(Color(0.45, 0.3, 0.15)), false, Vector3.ZERO, m)


func _furnish_great_hall(r: Room) -> void:
	var wood := Color(0.4, 0.27, 0.15)
	for i in 2:
		var c := _floor(r, Vector2(5.2, 3.0), 0.6)
		if c == Vector2.INF:
			continue
		_b(self, Vector3(4.6, 0.08, 1.0), Vector3(c.x, r.y0 + 0.8, c.y), wood)
		for lx in [-2.0, 2.0]:
			for lz in [-0.4, 0.4]:
				_b(self, Vector3(0.1, 0.78, 0.1), Vector3(c.x + lx, r.y0 + 0.39, c.y + lz), wood, false)
		for bz in [-0.95, 0.95]:
			_b(self, Vector3(4.4, 0.06, 0.4), Vector3(c.x, r.y0 + 0.45, c.y + bz), wood.lightened(0.1), false)
			for bx in [-1.9, 1.9]:
				_b(self, Vector3(0.08, 0.42, 0.3), Vector3(c.x + bx, r.y0 + 0.21, c.y + bz), wood, false)
		for g in 3:
			_p(main._cyl(0.04, 0.12), Vector3(c.x - 1.4 + g * 1.0, r.y0 + 0.9, c.y + randf_range(-0.25, 0.25)),
					main._mat(Color(0.85, 0.7, 0.2)), false)
		r.spots.append(Vector3(c.x - 0.7, r.y0 + 0.91, c.y))
		r.spots.append(Vector3(c.x + 1.4, r.y0 + 0.91, c.y))
	var m := _wall(r, 2.8, 1.0)
	if m != null:
		_b(m, Vector3(2.6, 2.6, 0.8), Vector3(0, 1.3, 0.4), Color(0.45, 0.45, 0.47))
		_p(main._box(Vector3(1.3, 1.0, 0.08)), Vector3(0, 0.6, 0.82), _glow_material(Color(1.0, 0.4, 0.1)), false, Vector3.ZERO, m)
		var fire := OmniLight3D.new()
		fire.position = Vector3(0, 0.8, 1.3)
		fire.light_color = Color(1.0, 0.5, 0.2)
		fire.omni_range = 6.0
		fire.light_energy = 1.2
		fire.light_cull_mask = 1
		m.add_child(fire)
		_spot(r, m, Vector3(1.1, 0.11, 1.0))
	_banners(r, 3)
	_armor_stand(r)
	_armor_stand(r)


func _furnish_throne_room(r: Room) -> void:
	var stone := Color(0.5, 0.5, 0.52)
	var gold := Color(0.9, 0.72, 0.15)
	var m := _wall(r, 4.5, 3.0)
	if m != null:
		_b(m, Vector3(4.2, 0.35, 2.6), Vector3(0, 0.175, 1.4), stone.darkened(0.1))
		_b(m, Vector3(1.0, 0.45, 0.9), Vector3(0, 0.575, 0.8), gold)
		_b(m, Vector3(1.0, 1.6, 0.15), Vector3(0, 1.15, 0.2), gold)
		for ax in [-0.56, 0.56]:
			_b(m, Vector3(0.12, 0.3, 0.9), Vector3(ax, 0.95, 0.8), gold, false)
		_b(m, Vector3(1.6, 0.02, 6.0), Vector3(0, 0.01, 3.0), Color(0.65, 0.08, 0.1), false)
		_spot(r, m, Vector3(0, 0.91, 0.8))
	for i in 6:
		var c := _floor(r, Vector2(1.0, 1.0), 1.0)
		if c != Vector2.INF:
			_p(main._cyl(0.4, 2.96), Vector3(c.x, r.y0 + 1.48, c.y), main._mat(stone), true)
	_banners(r, 4)
	_armor_stand(r)


func _furnish_tower(r: Room) -> void:
	var wood := Color(0.4, 0.27, 0.15)
	var m := _wall(r, 1.8, 0.6)
	if m != null:
		_b(m, Vector3(1.6, 0.08, 0.4), Vector3(0, 0.9, 0.25), wood)
		_b(m, Vector3(0.08, 0.9, 0.4), Vector3(-0.75, 0.45, 0.25), wood)
		_b(m, Vector3(0.08, 0.9, 0.4), Vector3(0.75, 0.45, 0.25), wood)
		for i in 3:
			_p(main._cyl(0.015, 1.8), Vector3(-0.4 + i * 0.4, 1.0, 0.3), main._mat(Color(0.5, 0.5, 0.55)), false, Vector3.ZERO, m)
		_spot(r, m, Vector3(0.5, 1.01, 0.25))
	for i in 3:
		var c := _floor(r, Vector2(0.9, 0.9), 0.5)
		if c != Vector2.INF:
			_p(main._cyl(0.38, 0.9), Vector3(c.x, r.y0 + 0.45, c.y), main._mat(wood.lightened(0.1)), true)
			r.spots.append(Vector3(c.x, r.y0 + 1.01, c.y))
	_crate(r, Vector3(0.6, 0.5, 0.6), Color(0.5, 0.38, 0.25))
	_banners(r, 1)


func _furnish_tower_top(r: Room) -> void:
	var wood := Color(0.45, 0.3, 0.18)
	var c := _floor(r, Vector2(2.2, 2.2), 0.5)
	if c != Vector2.INF:
		_p(main._cyl(0.7, 0.05), Vector3(c.x, r.y0 + 0.75, c.y), main._mat(wood), true)
		_p(main._cyl(0.1, 0.75), Vector3(c.x, r.y0 + 0.375, c.y), main._mat(wood), true)
		for i in 3:
			var a := i * TAU / 3.0
			_p(main._cyl(0.2, 0.45), Vector3(c.x + cos(a) * 1.0, r.y0 + 0.225, c.y + sin(a) * 1.0), main._mat(wood.lightened(0.1)), false)
		r.spots.append(Vector3(c.x, r.y0 + 0.86, c.y))
	var m := _wall(r, 1.2, 0.5)
	if m != null:
		_b(m, Vector3(1.2, 2.0, 0.4), Vector3(0, 1.0, 0.2), wood)
		for i in 4:
			_b(m, Vector3(0.12, 0.28, 0.2), Vector3(-0.4 + i * 0.27, 1.3, 0.24),
					_pick([Color(0.7, 0.2, 0.2), Color(0.2, 0.4, 0.7), Color(0.8, 0.7, 0.2)]), false)
	_banners(r, 2)


# Boiler: a tank with a glowing furnace door, set a few metres in from the stairs where possible.
func _place_boiler(r: Room) -> void:
	var inner := r.interior()
	var pos := Vector3.INF
	for o in r.openings:
		if o["kind"] != "arch":
			continue
		var center := (float(o["lo"]) + float(o["hi"])) / 2.0
		var p := Vector2.ZERO
		match int(o["side"]):
			0:
				p = Vector2(center, inner.end.y - 2.4)
			1:
				p = Vector2(center, inner.position.y + 2.4)
			2:
				p = Vector2(inner.end.x - 2.4, center)
			_:
				p = Vector2(inner.position.x + 2.4, center)
		var rect := Rect2(p - Vector2(0.9, 0.9), Vector2(1.8, 1.8))
		if _free(r, rect):
			r.used.append(rect)
			pos = Vector3(p.x, r.y0, p.y)
		break
	var rot := 0.0
	if pos == Vector3.INF:
		var m := _wall(r, 1.4, 1.2)
		if m == null:
			return
		pos = m.to_global(Vector3(0, 0, 0.6))
		rot = m.rotation.y
	var tank := Items.boiler()
	tank.position = pos
	tank.rotation.y = rot
	for child in tank.get_children():
		if child is MeshInstance3D:
			(child as MeshInstance3D).layers = main.mesh_layers
	add_child(tank)


func _crate(r: Room, size: Vector3, color: Color) -> void:
	var c := _floor(r, Vector2(size.x, size.z), 0.5)
	if c == Vector2.INF:
		return
	_b(self, size, Vector3(c.x, r.y0 + size.y / 2.0, c.y), color)
	r.spots.append(Vector3(c.x, r.y0 + size.y + 0.11, c.y))


func _furnish_attic(r: Room) -> void:
	for i in randi_range(4, 7):
		var s := randf_range(0.4, 0.9)
		_crate(r, Vector3(s, randf_range(0.4, 0.8), s), Color(0.5, 0.38, 0.25))
	var m := _wall(r, 1.0, 0.5)
	if m != null:
		_b(m, Vector3(1.0, 0.5, 0.5), Vector3(0, 0.25, 0.25), Color(0.35, 0.22, 0.15))
		_b(m, Vector3(1.02, 0.1, 0.52), Vector3(0, 0.55, 0.25), Color(0.3, 0.2, 0.12), false)
		_spot(r, m, Vector3(0, 0.71, 0.25))
	m = _wall(r, 0.8, 0.5)
	if m != null:
		_b(m, Vector3(0.7, 1.7, 0.4), Vector3(0, 0.85, 0.25), Color(0.45, 0.4, 0.38))
	_rug(r, Vector2(2.5, 1.8), Color(0.4, 0.25, 0.2))


func _furnish_basement(r: Room) -> void:
	for i in randi_range(4, 7):
		var s := randf_range(0.5, 1.0)
		_crate(r, Vector3(s, randf_range(0.5, 0.9), s), Color(0.55, 0.45, 0.3))
	var m := _wall(r, 1.4, 0.7)
	if m != null:
		_b(m, Vector3(0.65, 0.9, 0.65), Vector3(-0.35, 0.45, 0.35), Color(0.85, 0.85, 0.87))
		_b(m, Vector3(0.65, 0.9, 0.65), Vector3(0.35, 0.45, 0.35), Color(0.85, 0.85, 0.87))
		_spot(r, m, Vector3(0, 1.01, 0.35))
	m = _wall(r, 0.8, 0.8)
	if m != null:
		_p(main._cyl(0.35, 1.5), Vector3(0, 0.75, 0.4), main._mat(Color(0.7, 0.7, 0.72)), true, Vector3.ZERO, m)
	m = _wall(r, 1.6, 0.7)
	if m != null:
		_b(m, Vector3(1.6, 0.05, 0.6), Vector3(0, 0.9, 0.35), Color(0.45, 0.3, 0.18))
		_b(m, Vector3(0.06, 0.88, 0.55), Vector3(-0.75, 0.44, 0.35), Color(0.35, 0.25, 0.15))
		_b(m, Vector3(0.06, 0.88, 0.55), Vector3(0.75, 0.44, 0.35), Color(0.35, 0.25, 0.15))
		_spot(r, m, Vector3(0.4, 1.01, 0.35))
	for i in 2:
		m = _wall(r, 1.2, 0.45)
		if m != null:
			_b(m, Vector3(1.2, 1.9, 0.4), Vector3(0, 0.95, 0.22), Color(0.4, 0.4, 0.42))
			for s in 3:
				_b(m, Vector3(0.3, 0.25, 0.3), Vector3(-0.35 + s * 0.35, 1.0, 0.25), Color(0.55, 0.45, 0.3), false)
