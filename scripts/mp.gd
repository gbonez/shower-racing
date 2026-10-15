extends Node

# Multiplayer session: lobby settings, readiness, the race schedule and scoring.
# The host's copy of `state` is authoritative and is sent to everyone after every change, so if the
# host leaves, the next player can carry on from their own copy.

signal state_changed

const MAX_PLAYERS := 20
const BETWEEN_SECONDS := 10.0
const MENU_SCENE := "res://scenes/menu.tscn"
const TIMER_MODES := {
	"load": "Level loads",
	"door": "Door is opened",
	"shower": "Shower is started",
}

var active := false
var state: Dictionary = {}
var notice_text := ""  # shown once by the menu, e.g. after a disconnect
var countdown := 0.0  # seconds until the next race, counted down locally


func _ready() -> void:
	Net.joined.connect(_on_joined)
	Net.peer_joined.connect(_on_peer_joined)
	Net.peer_left.connect(_on_peer_left)
	Net.host_changed.connect(_on_host_changed)
	Net.message.connect(_on_message)
	Net.disconnected.connect(_on_disconnected)


func _process(delta: float) -> void:
	if countdown > 0.0:
		countdown = maxf(0.0, countdown - delta)


# --- Queries ---

func phase() -> String:
	return str(state.get("phase", "lobby"))


func players() -> Array:
	return state.get("players", [])


func settings() -> Dictionary:
	return state.get("settings", {})


func race_index() -> int:
	return int(state.get("race_index", 0))


func race_count() -> int:
	return state.get("race_plan", []).size()


func race_label() -> String:
	return "Race %d of %d" % [race_index() + 1, maxi(race_count(), 1)]


func current_race() -> Dictionary:
	var plan: Array = state.get("race_plan", [])
	var index := race_index()
	return plan[index] if index >= 0 and index < plan.size() else {}


func in_participants(id: int) -> bool:
	for x in state.get("participants", []):
		if int(x) == id:
			return true
	return false


func me_ready() -> bool:
	var p := _player(Net.my_id)
	return not p.is_empty() and bool(p["ready"])


func all_ready() -> bool:
	for p in players():
		if int(p["id"]) != Net.host_id and not bool(p["ready"]):
			return false
	return true


func my_finish() -> Dictionary:
	for f in state.get("finishes", []):
		if int(f["id"]) == Net.my_id:
			return f
	return {}


func time_text(t: float) -> String:
	return "%02d:%05.2f" % [floori(t / 60.0), fmod(t, 60.0)]


func parse_seeds(text: String) -> Array:
	var seeds: Array = []
	for part in text.split(","):
		var s := part.strip_edges()
		if s != "":
			seeds.append(s)
	return seeds


# This race's finishers, fastest first, with the points they gained once the race is over.
func standings_lines() -> Array[String]:
	var list: Array = state.get("finishes", []).duplicate()
	list.sort_custom(func(a, b): return float(a["time"]) < float(b["time"]))
	var over := phase() == "between" or phase() == "final"
	var lines: Array[String] = []
	for i in list.size():
		var line := "%d. %s  %s" % [i + 1, list[i]["name"], time_text(float(list[i]["time"]))]
		if over:
			line += "  (+%d)" % (list.size() - i)
		lines.append(line)
	return lines


func leaderboard_lines() -> Array[String]:
	var list: Array = players().duplicate()
	list.sort_custom(func(a, b):
		if int(a["points"]) != int(b["points"]):
			return int(a["points"]) > int(b["points"])
		return str(a["name"]) < str(b["name"]))
	var lines: Array[String] = []
	for i in list.size():
		lines.append("%d. %s  %d pts" % [i + 1, list[i]["name"], int(list[i]["points"])])
	return lines


# --- Actions ---

func update_settings(partial: Dictionary) -> void:
	if not Net.is_host:
		return
	for key in partial:
		state["settings"][key] = partial[key]
	_broadcast()


func set_ready(value: bool) -> void:
	if Net.is_host:
		return
	Net.send_to(Net.host_id, {"k": "ready", "v": value})


func start_race_set() -> void:
	if not Net.is_host or phase() != "lobby" or state["settings"]["templates"].is_empty():
		return
	var ids: Array = []
	for p in players():
		p["points"] = 0
		p["late"] = false
		ids.append(int(p["id"]))
	state["race_plan"] = _build_plan(state["settings"])
	state["race_index"] = 0
	state["participants"] = ids
	state["finishes"] = []
	state["last_race"] = {}
	state["countdown"] = 0.0
	state["phase"] = "racing"
	_broadcast()


func report_finish(time: float) -> void:
	if Net.is_host:
		_record_finish(Net.my_id, time)
	else:
		Net.send_to(Net.host_id, {"k": "finish", "time": time})


# Host: stops the current race for everyone who hasn't finished yet.
func end_race_now() -> void:
	if not Net.is_host or phase() != "racing":
		return
	var finished: Array = []
	for f in state["finishes"]:
		finished.append(int(f["id"]))
	state["participants"] = finished
	_check_progress()
	_broadcast()


func return_to_lobby() -> void:
	if not Net.is_host:
		return
	state["phase"] = "lobby"
	state["countdown"] = 0.0
	for p in players():
		p["ready"] = int(p["id"]) == Net.my_id
		p["late"] = false
	_broadcast()


func leave() -> void:
	Net.leave()
	active = false
	state = {}
	countdown = 0.0


# --- Host logic ---

func _default_state() -> Dictionary:
	return {
		"phase": "lobby",
		"settings": {"templates": GameState.TEMPLATES.keys(), "seeds": [], "races": 3, "timer_start": "shower",
				"run_bottles": false, "run_shower": false, "need_boiler": false, "item_freq": "regular",
				"keys": 0, "no_fake_keys": false},
		"players": [],
		"race_index": 0,
		"race_plan": [],
		"participants": [],
		"finishes": [],
		"last_race": {},
		"countdown": 0.0,
	}


func _player(id: int) -> Dictionary:
	for p in players():
		if int(p["id"]) == id:
			return p
	return {}


func _add_player(id: int, player_name: String, late: bool) -> void:
	if _player(id).is_empty() and players().size() < MAX_PLAYERS:
		players().append({"id": id, "name": player_name, "ready": false, "points": 0, "late": late})


func _broadcast() -> void:
	state["countdown"] = float(state.get("countdown", 0.0))
	state_changed.emit()
	Net.broadcast({"k": "state", "s": state})


func _build_plan(s: Dictionary) -> Array:
	var templates: Array = s["templates"]
	var seeds: Array = s["seeds"]
	var plan: Array = []
	var last := ""
	for i in int(s["races"]):
		var pool := templates.duplicate()
		if pool.size() > 1:
			pool.erase(last)
		var chosen: String = pool.pick_random()
		last = chosen
		var seed_text := ""
		var seed_number := randi_range(1, 999999)
		if not seeds.is_empty():
			seed_text = str(seeds[i % seeds.size()])
			seed_number = GameState.seed_from_text(seed_text)
		plan.append({"template": chosen, "seed": seed_number, "seed_text": seed_text})
	return plan


func _record_finish(id: int, time: float) -> void:
	if phase() != "racing" or not in_participants(id):
		return
	for f in state["finishes"]:
		if int(f["id"]) == id:
			return
	var p := _player(id)
	state["finishes"].append({"id": id, "name": str(p.get("name", "?")), "time": time})
	_check_progress()
	_broadcast()


# Ends the race once every remaining participant has finished or left.
func _check_progress() -> void:
	if not Net.is_host or phase() != "racing":
		return
	var done := {}
	for f in state["finishes"]:
		done[int(f["id"])] = true
	for id in state["participants"]:
		if not done.has(int(id)):
			return
	_finish_race()


# Points: with N finishers, first place gets N, second N-1, and so on. Players who left before
# finishing are not counted, so the scale shrinks with them.
func _finish_race() -> void:
	var finishes: Array = state["finishes"].duplicate()
	finishes.sort_custom(func(a, b): return float(a["time"]) < float(b["time"]))
	var standings: Array = []
	for i in finishes.size():
		var points := finishes.size() - i
		var p := _player(int(finishes[i]["id"]))
		if not p.is_empty():
			p["points"] = int(p["points"]) + points
		standings.append({"id": finishes[i]["id"], "name": finishes[i]["name"], "time": finishes[i]["time"], "points": points})
	state["finishes"] = finishes
	state["last_race"] = {"index": race_index(), "standings": standings}
	if race_index() + 1 >= race_count():
		state["phase"] = "final"
		state["countdown"] = 0.0
	else:
		state["phase"] = "between"
		state["countdown"] = BETWEEN_SECONDS
		countdown = BETWEEN_SECONDS
		_schedule_next()
	_broadcast()


func _schedule_next() -> void:
	get_tree().create_timer(maxf(float(state["countdown"]), 0.1)).timeout.connect(
			_on_next_race_timer.bind(race_index()))


func _on_next_race_timer(token: int) -> void:
	if Net.is_host and phase() == "between" and race_index() == token:
		_next_race()


func _next_race() -> void:
	var ids: Array = []
	for p in players():
		p["late"] = false
		ids.append(int(p["id"]))
	state["race_index"] = race_index() + 1
	state["participants"] = ids
	state["finishes"] = []
	state["phase"] = "racing"
	state["countdown"] = 0.0
	_broadcast()


# --- Network events ---

func _on_joined(_code: String, id: int, is_host: bool) -> void:
	active = true
	if is_host:
		state = _default_state()
		_add_player(id, Net.player_name, false)
		players()[0]["ready"] = true
		state_changed.emit()


func _on_peer_joined(id: int, peer_name: String) -> void:
	if not Net.is_host:
		return
	_add_player(id, peer_name, phase() != "lobby")
	_broadcast()


func _on_peer_left(id: int) -> void:
	if not Net.is_host:
		return
	_drop_player(id)
	_check_progress()
	_broadcast()


func _drop_player(id: int) -> void:
	var list := players()
	for i in range(list.size() - 1, -1, -1):
		if int(list[i]["id"]) == id:
			list.remove_at(i)
	var participants: Array = state.get("participants", [])
	for i in range(participants.size() - 1, -1, -1):
		if int(participants[i]) == id:
			participants.remove_at(i)


func _on_host_changed(id: int) -> void:
	if id != Net.my_id or state.is_empty():
		return
	for p in players().duplicate():
		if not Net.peers.has(int(p["id"])):
			_drop_player(int(p["id"]))
	var me := _player(Net.my_id)
	if not me.is_empty():
		me["ready"] = true
	if phase() == "between":
		state["countdown"] = maxf(countdown, 1.0)
		_schedule_next()
	_check_progress()
	_broadcast()


func _on_message(from: int, data: Dictionary) -> void:
	match str(data.get("k", "")):
		"state":
			if not Net.is_host and from == Net.host_id:
				state = data["s"]
				countdown = float(state.get("countdown", 0.0))
				state_changed.emit()
		"ready":
			if Net.is_host:
				var p := _player(from)
				if not p.is_empty():
					p["ready"] = bool(data.get("v", false))
					_broadcast()
		"finish":
			if Net.is_host:
				_record_finish(from, float(data.get("time", 0.0)))


func _on_disconnected() -> void:
	if not active:
		return
	leave()
	notice_text = "Lost connection to the server."
	get_tree().change_scene_to_file(MENU_SCENE)
