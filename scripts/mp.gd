extends Node

# Multiplayer session: lobby settings, readiness, the race schedule and scoring.
# The host's copy of `state` is authoritative and is sent to everyone after every change, so if the
# host leaves, the next player can carry on from their own copy.

signal state_changed
signal chat_changed

const MAX_PLAYERS := 20
const BETWEEN_SECONDS := 10.0
const START_SECONDS := 5.0  # countdown after the host presses start; the host can cancel it
const FINAL_SCORE_SECONDS := 10.0  # after the last race, everyone sees its scores before the end screen
const CHAT_MAX := 100
const MENU_SCENE := "res://scenes/menu.tscn"
const TIMER_MODES := {
	"load": "Level loads",
	"door": "Door is opened",
	"shower": "Shower is started",
}
const ORDER_MODES := {
	"random": "Random",
	"template": "Template order",
}

var active := false
var state: Dictionary = {}
var notice_text := ""  # shown once by the menu, e.g. after a disconnect
var countdown := 0.0  # seconds until the next race, counted down locally
var chat_log: Array[Dictionary] = []  # {from, name, text, system}
var _start_serial := 0  # tells a cancelled countdown's timer apart from the current one


func _ready() -> void:
	Net.joined.connect(_on_joined)
	Net.peer_joined.connect(_on_peer_joined)
	Net.peer_left.connect(_on_peer_left)
	Net.host_changed.connect(_on_host_changed)
	Net.message.connect(_on_message)
	Net.chat.connect(_on_chat)
	Net.kicked.connect(_on_kicked)
	Net.notice.connect(add_system_chat)
	Net.mute_changed.connect(_on_mute_changed)
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
	var over := phase() in ["between", "final_scores", "final"]
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
	if not Net.is_host or phase() == "starting":
		return
	for key in partial:
		state["settings"][key] = partial[key]
	_broadcast()


func set_ready(value: bool) -> void:
	if Net.is_host:
		return
	Net.send_to(Net.host_id, {"k": "ready", "v": value})


func not_ready_count() -> int:
	var n := 0
	for p in players():
		if int(p["id"]) != Net.host_id and not bool(p["ready"]):
			n += 1
	return n


# Host: starts the countdown to the first race. Everyone is brought along, ready or not.
func start_race_set() -> void:
	if not Net.is_host or phase() != "lobby" or state["settings"]["templates"].is_empty():
		return
	_start_serial += 1
	state["phase"] = "starting"
	state["countdown"] = START_SECONDS
	countdown = START_SECONDS
	get_tree().create_timer(START_SECONDS).timeout.connect(_on_start_timer.bind(_start_serial))
	_broadcast()


# Host: calls the start off before the countdown ends.
func cancel_start() -> void:
	if not Net.is_host or phase() != "starting":
		return
	_start_serial += 1
	state["phase"] = "lobby"
	state["countdown"] = 0.0
	countdown = 0.0
	_broadcast()


func _on_start_timer(serial: int) -> void:
	if Net.is_host and phase() == "starting" and serial == _start_serial:
		_begin_race_set()


func _begin_race_set() -> void:
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
	state["history"] = []
	state["end_reason"] = ""
	state["countdown"] = 0.0
	state["phase"] = "racing"
	_broadcast()


func report_finish(time: float) -> void:
	if Net.is_host:
		_record_finish(Net.my_id, time)
	else:
		Net.send_to(Net.host_id, {"k": "finish", "time": time})


# A racer who lost the race (e.g. caught three times by the chaser): no time and no points.
func report_dnf() -> void:
	if Net.is_host:
		_record_dnf(Net.my_id)
	else:
		Net.send_to(Net.host_id, {"k": "dnf"})


# Host: stops the current race for everyone who hasn't finished yet.
func end_race_now() -> void:
	if not Net.is_host or phase() != "racing":
		return
	var finished: Array = []
	for f in state["finishes"]:
		finished.append(int(f["id"]))
	state["participants"] = finished
	state["end_reason"] = "host"
	_check_progress()
	_broadcast()


# Host: ends the whole game now. The current race is scored as it stands and the final scores follow.
func end_game_now() -> void:
	if not Net.is_host or not (phase() in ["racing", "between"]):
		return
	var plan: Array = state["race_plan"]
	plan.resize(mini(race_index() + 1, plan.size()))
	state["end_reason"] = "host"
	if phase() == "racing":
		var finished: Array = []
		for f in state["finishes"]:
			finished.append(int(f["id"]))
		state["participants"] = finished
		_check_progress()
		_broadcast()
	else:
		_begin_final_scores()
		_broadcast()


func send_chat(text: String) -> void:
	var cleaned := text.strip_edges()
	if cleaned != "" and Net.in_room:
		Net.send_chat(cleaned.substr(0, 200))


func add_system_chat(text: String) -> void:
	_push_chat({"from": 0, "name": "", "text": text, "system": true})


func _push_chat(entry: Dictionary) -> void:
	chat_log.append(entry)
	while chat_log.size() > CHAT_MAX:
		chat_log.pop_front()
	chat_changed.emit()


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
	chat_log.clear()


# --- Host logic ---

func _default_state() -> Dictionary:
	var settings := {"templates": GameState.TEMPLATES.keys(), "seeds": [], "races": 3, "timer_start": "shower",
			"order_mode": "random", "item_freq": "regular", "keys": 0}
	for key in GameState.DEFAULT_RULES:
		if not settings.has(key):
			settings[key] = GameState.DEFAULT_RULES[key]
	return {
		"phase": "lobby",
		"settings": settings,
		"players": [],
		"race_index": 0,
		"race_plan": [],
		"participants": [],
		"finishes": [],
		"last_race": {},
		"history": [],
		"end_reason": "",
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
	var ordered: Array = []  # the enabled templates in the template list's own order
	for key in GameState.TEMPLATES:
		if templates.has(key):
			ordered.append(key)
	var plan: Array = []
	var last := ""
	for i in int(s["races"]):
		var chosen: String
		if str(s.get("order_mode", "random")) == "template":
			chosen = ordered[i % ordered.size()]
		else:
			var pool := templates.duplicate()
			if pool.size() > 1:
				pool.erase(last)
			chosen = pool.pick_random()
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


func _record_dnf(id: int) -> void:
	if phase() != "racing" or not in_participants(id):
		return
	for f in state["finishes"]:
		if int(f["id"]) == id:
			return
	var participants: Array = state["participants"]
	for i in range(participants.size() - 1, -1, -1):
		if int(participants[i]) == id:
			participants.remove_at(i)
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
	var results: Array = []
	var finished_ids := {}
	for i in finishes.size():
		var points := finishes.size() - i
		var p := _player(int(finishes[i]["id"]))
		if not p.is_empty():
			p["points"] = int(p["points"]) + points
		finished_ids[int(finishes[i]["id"])] = true
		standings.append({"id": finishes[i]["id"], "name": finishes[i]["name"], "time": finishes[i]["time"], "points": points})
		results.append([finishes[i]["name"], finishes[i]["time"], points])
	var did_not_finish: Array = []
	for p in players():
		if not finished_ids.has(int(p["id"])) and not bool(p["late"]):
			did_not_finish.append(str(p["name"]))
	var entry := current_race()
	state["history"].append({"index": race_index(), "template": str(entry.get("template", "")),
			"seed": str(entry.get("seed_text", "")), "results": results, "dnf": did_not_finish})
	state["finishes"] = finishes
	state["last_race"] = {"index": race_index(), "standings": standings}
	if race_index() + 1 >= race_count():
		_begin_final_scores()
	else:
		state["phase"] = "between"
		state["countdown"] = BETWEEN_SECONDS
		countdown = BETWEEN_SECONDS
		_schedule_next()
	_broadcast()


# After the last race everyone sees that race's scores for a few seconds before the end screen.
func _begin_final_scores() -> void:
	state["phase"] = "final_scores"
	state["countdown"] = FINAL_SCORE_SECONDS
	countdown = FINAL_SCORE_SECONDS
	if str(state.get("end_reason", "")) == "":
		state["end_reason"] = "natural"
	_schedule_next()


func _schedule_next() -> void:
	get_tree().create_timer(maxf(float(state["countdown"]), 0.1)).timeout.connect(
			_on_phase_timer.bind(race_index(), phase()))


func _on_phase_timer(token: int, expected: String) -> void:
	if not Net.is_host or phase() != expected or race_index() != token:
		return
	if expected == "between":
		_next_race()
	elif expected == "final_scores":
		state["phase"] = "final"
		state["countdown"] = 0.0
		_broadcast()


func _next_race() -> void:
	var ids: Array = []
	for p in players():
		p["late"] = false
		ids.append(int(p["id"]))
	state["race_index"] = race_index() + 1
	state["participants"] = ids
	state["finishes"] = []
	state["end_reason"] = ""
	state["phase"] = "racing"
	state["countdown"] = 0.0
	_broadcast()


# --- Network events ---

func _on_joined(_code: String, id: int, is_host: bool) -> void:
	active = true
	chat_log.clear()
	if is_host:
		state = _default_state()
		_add_player(id, Net.player_name, false)
		players()[0]["ready"] = true
		state_changed.emit()


func _on_peer_joined(id: int, peer_name: String) -> void:
	add_system_chat("%s joined the room." % peer_name)
	if not Net.is_host:
		return
	_add_player(id, peer_name, not (phase() in ["lobby", "starting"]))
	_broadcast()


func _on_peer_left(id: int) -> void:
	var left_name := str(_player(id).get("name", ""))
	if left_name != "":
		add_system_chat("%s left the room." % left_name)
	if not Net.is_host:
		return
	_drop_player(id)
	_check_progress()
	_broadcast()


func _on_chat(from: int, from_name: String, text: String) -> void:
	_push_chat({"from": from, "name": from_name, "text": text, "system": false})


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
	if phase() == "starting":
		_start_serial += 1  # the countdown was the old host's; the new one starts over from the lobby
		state["phase"] = "lobby"
		state["countdown"] = 0.0
		countdown = 0.0
	if phase() == "between" or phase() == "final_scores":
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
		"dnf":
			if Net.is_host:
				_record_dnf(from)


func _on_kicked(reason: String) -> void:
	if not active:
		return
	leave()
	notice_text = reason
	get_tree().change_scene_to_file(MENU_SCENE)


func _on_mute_changed(id: int, muted: bool) -> void:
	var who := str(Net.peers.get(id, "A player"))
	add_system_chat("%s was %s." % [who, "muted by the host" if muted else "unmuted"])


func _on_disconnected() -> void:
	if not active:
		return
	leave()
	notice_text = "Lost connection to the server."
	get_tree().change_scene_to_file(MENU_SCENE)
