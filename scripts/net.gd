extends Node

# Transport to the relay server (see server/server.js). Rooms are identified by a 4-character code.

signal joined(code: String, id: int, is_host: bool)
signal peer_joined(id: int, peer_name: String)
signal peer_left(id: int)
signal host_changed(id: int)
signal message(from: int, data: Dictionary)
signal chat(from: int, from_name: String, text: String)
signal failed(reason: String)
signal disconnected
signal kicked(reason: String)
signal notice(text: String)
signal mute_changed(id: int, muted: bool)
signal bans_changed(names: Array)

const DEFAULT_URL := "ws://localhost:8080"
const CONFIG_PATH := "user://multiplayer.cfg"
const CONNECT_TIMEOUT := 10.0

var player_name := "Player"
var server_url := DEFAULT_URL
var my_id := 0
var room_code := ""
var is_host := false
var host_id := 0
var peers := {}  # id -> name, including this player
var muted := {}  # id -> true for players the host has muted
var in_room := false

var _socket: WebSocketPeer
var _pending := {}
var _waited := 0.0


func _ready() -> void:
	set_process(false)
	var cfg := ConfigFile.new()
	if cfg.load(CONFIG_PATH) == OK:
		player_name = cfg.get_value("player", "name", player_name)
		server_url = cfg.get_value("server", "url", server_url)


func save_config() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("player", "name", player_name)
	cfg.set_value("server", "url", server_url)
	cfg.save(CONFIG_PATH)


func host_room() -> void:
	_connect({"t": "host", "name": player_name})


func join_room(code: String) -> void:
	_connect({"t": "join", "code": code.to_upper(), "name": player_name})


func send_to(id: int, data: Dictionary) -> void:
	_send({"t": "msg", "to": id, "data": data})


# Room chat goes through its own relay message so the server can log it; everyone gets it, sender too.
func send_chat(text: String) -> void:
	_send({"t": "chat", "text": text})


# Sends to everyone else in the room.
func broadcast(data: Dictionary) -> void:
	_send({"t": "msg", "to": "all", "data": data})


# Host-only moderation, checked again by the server: "kick", "mute", "unmute", "ban", "promote" take a
# player id; "unban" takes a name; "bans" asks for the list of banned names.
func admin(action: String, target = null) -> void:
	if not is_host:
		return
	if action == "unban":
		_send({"t": "admin", "action": action, "name": str(target)})
	elif target != null and int(target) == my_id:
		return  # the host can't act on themselves
	else:
		_send({"t": "admin", "action": action, "target": target if target != null else 0})


func leave() -> void:
	if _socket != null:
		_socket.close()
	_reset()


func _connect(request: Dictionary) -> void:
	leave()
	_socket = WebSocketPeer.new()
	if _socket.connect_to_url(server_url) != OK:
		_socket = null
		failed.emit("That server address doesn't look right.")
		return
	_pending = request
	_waited = 0.0
	set_process(true)


func _reset() -> void:
	_socket = null
	_pending = {}
	in_room = false
	my_id = 0
	room_code = ""
	is_host = false
	host_id = 0
	peers.clear()
	muted.clear()
	set_process(false)


func _fail(reason: String) -> void:
	leave()
	failed.emit(reason)


func _send(data: Dictionary) -> void:
	if _socket != null and _socket.get_ready_state() == WebSocketPeer.STATE_OPEN:
		_socket.send_text(JSON.stringify(data))


func _process(delta: float) -> void:
	if _socket == null:
		return
	_socket.poll()
	match _socket.get_ready_state():
		WebSocketPeer.STATE_CONNECTING:
			_waited += delta
			if _waited > CONNECT_TIMEOUT:
				_fail("Connection timed out.")
		WebSocketPeer.STATE_OPEN:
			if not _pending.is_empty():
				_send(_pending)
				_pending = {}
			while _socket != null and _socket.get_available_packet_count() > 0:
				_handle(_socket.get_packet().get_string_from_utf8())
		WebSocketPeer.STATE_CLOSED:
			var was_in_room := in_room
			var was_connecting := not _pending.is_empty()
			_reset()
			if was_in_room:
				disconnected.emit()
			elif was_connecting:
				failed.emit("Couldn't connect to the server.")


func _handle(text: String) -> void:
	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	var m: Dictionary = parsed
	match str(m.get("t", "")):
		"joined":
			my_id = int(m["id"])
			room_code = str(m["code"])
			host_id = int(m["hostId"])
			is_host = host_id == my_id
			peers.clear()
			muted.clear()
			for p in m["peers"]:
				peers[int(p["id"])] = str(p["name"])
				if bool(p.get("muted", false)):
					muted[int(p["id"])] = true
			in_room = true
			joined.emit(room_code, my_id, is_host)
		"peer_joined":
			peers[int(m["id"])] = str(m["name"])
			if bool(m.get("muted", false)):
				muted[int(m["id"])] = true
			peer_joined.emit(int(m["id"]), str(m["name"]))
		"peer_left":
			peers.erase(int(m["id"]))
			muted.erase(int(m["id"]))
			peer_left.emit(int(m["id"]))
		"host_changed":
			host_id = int(m["id"])
			is_host = host_id == my_id
			host_changed.emit(host_id)
		"msg":
			if typeof(m.get("data")) == TYPE_DICTIONARY:
				message.emit(int(m["from"]), m["data"])
		"chat":
			chat.emit(int(m.get("from", 0)), str(m.get("name", "?")), str(m.get("text", "")))
		"muted":
			if bool(m.get("muted", false)):
				muted[int(m["id"])] = true
			else:
				muted.erase(int(m["id"]))
			mute_changed.emit(int(m["id"]), bool(m.get("muted", false)))
		"notice":
			notice.emit(str(m.get("msg", "")))
		"bans":
			bans_changed.emit(m.get("names", []))
		"kicked":
			var reason := str(m.get("reason", "You were removed from the room."))
			leave()
			kicked.emit(reason)
		"error":
			_fail(str(m.get("msg", "Server error.")))
