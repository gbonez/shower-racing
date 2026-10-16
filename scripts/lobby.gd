extends Control

const GAME_SCENE := "res://scenes/main.tscn"
const MENU_SCENE := "res://scenes/menu.tscn"
const SudsBackground := preload("res://scripts/suds_background.gd")

var code_label: Label
var count_label: Label
var players_box: VBoxContainer
var chat_box: ChatBox
var status_label: Label
var bans_window: Control
var bans_list: VBoxContainer
var bans_button: Button
var checks: Dictionary = {}  # template key -> CheckBox
var enable_all_button: Button
var disable_all_button: Button
var seeds_input: LineEdit
var races_spin: SpinBox
var order_picker: OptionButton
var order_keys: Array = []
var timer_picker: OptionButton
var timer_keys: Array = []
var rule_checks: Dictionary = {}  # setting key -> CheckBox
var freq_picker: OptionButton
var freq_keys := ["none", "low", "regular", "crazy"]
var keys_spin: SpinBox
var ready_button: BubbleButton
var start_button: BubbleButton
var syncing := false  # true while widgets are being filled from the state, so their signals are ignored
var leaving := false


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if not MP.active:
		get_tree().change_scene_to_file.call_deferred(MENU_SCENE)
		return
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var backdrop := SudsBackground.new()
	add_child(backdrop)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build()
	MP.state_changed.connect(_refresh)
	_refresh()


func _build() -> void:
	var margin := MarginContainer.new()
	add_child(margin)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 8)
	margin.add_child(root)

	code_label = Ui.bubbly_label("Room", 64, 14)
	root.add_child(code_label)
	count_label = Ui.bubbly_label("", 24, 8)
	root.add_child(count_label)

	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 16)
	root.add_child(body)

	var left := Ui.panel()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(left)
	var left_box := VBoxContainer.new()
	left.add_child(left_box)
	var players_header := HBoxContainer.new()
	left_box.add_child(players_header)
	var players_title := Ui.ink_label("Players", 26)
	players_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	players_header.add_child(players_title)
	bans_button = Button.new()
	bans_button.text = "Banned players"
	Ui.style_button(bans_button, 18)
	bans_button.pressed.connect(_open_bans)
	players_header.add_child(bans_button)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left_box.add_child(scroll)
	players_box = VBoxContainer.new()
	players_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(players_box)
	chat_box = ChatBox.new()
	chat_box.custom_minimum_size = Vector2(0, 220)
	chat_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left_box.add_child(chat_box)

	var right := Ui.panel()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_stretch_ratio = 1.3
	body.add_child(right)
	var settings_scroll := ScrollContainer.new()
	settings_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right.add_child(settings_scroll)
	var settings := VBoxContainer.new()
	settings.add_theme_constant_override("separation", 6)
	settings.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	settings_scroll.add_child(settings)

	settings.add_child(Ui.ink_label("Templates", 26))
	var bulk := HBoxContainer.new()
	bulk.add_theme_constant_override("separation", 10)
	settings.add_child(bulk)
	enable_all_button = Button.new()
	enable_all_button.text = "Enable all"
	Ui.style_button(enable_all_button, 22)
	enable_all_button.pressed.connect(_set_all_templates.bind(true))
	bulk.add_child(enable_all_button)
	disable_all_button = Button.new()
	disable_all_button.text = "Disable all"
	Ui.style_button(disable_all_button, 22)
	disable_all_button.pressed.connect(_set_all_templates.bind(false))
	bulk.add_child(disable_all_button)
	var template_scroll := ScrollContainer.new()
	template_scroll.custom_minimum_size = Vector2(0, 170)
	template_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	template_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	settings.add_child(template_scroll)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	template_scroll.add_child(grid)
	for key in GameState.TEMPLATES:
		var check := CheckBox.new()
		check.text = GameState.TEMPLATES[key]
		Ui.style_check(check, 22)
		check.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		check.toggled.connect(_on_template_toggled.bind(key))
		grid.add_child(check)
		checks[key] = check

	settings.add_child(Ui.ink_label("Seeds (comma separated, empty = random)", 22))
	seeds_input = LineEdit.new()
	seeds_input.placeholder_text = "random"
	Ui.style_input(seeds_input, ["normal", "focus", "read_only"], 22)
	seeds_input.text_changed.connect(_on_seeds_changed)
	settings.add_child(seeds_input)

	var races_row := HBoxContainer.new()
	races_row.add_child(Ui.ink_label("Races", 22))
	races_spin = SpinBox.new()
	races_spin.min_value = 1
	races_spin.max_value = 20
	races_spin.value = 3
	races_spin.get_line_edit().add_theme_font_size_override("font_size", 22)
	races_spin.get_line_edit().add_theme_color_override("font_color", Ui.INK)
	races_spin.value_changed.connect(_on_races_changed)
	races_row.add_child(races_spin)
	settings.add_child(races_row)

	var order_row := HBoxContainer.new()
	order_row.add_child(Ui.ink_label("Map order  ", 22))
	order_picker = OptionButton.new()
	for key in MP.ORDER_MODES:
		order_keys.append(key)
		order_picker.add_item(MP.ORDER_MODES[key])
	Ui.style_input(order_picker, ["normal", "hover", "pressed", "focus", "disabled"], 22)
	order_picker.item_selected.connect(_on_order_selected)
	order_row.add_child(order_picker)
	settings.add_child(order_row)

	var timer_row := HBoxContainer.new()
	timer_row.add_child(Ui.ink_label("Timer starts when  ", 22))
	timer_picker = OptionButton.new()
	for key in MP.TIMER_MODES:
		timer_keys.append(key)
		timer_picker.add_item(MP.TIMER_MODES[key])
	Ui.style_input(timer_picker, ["normal", "hover", "pressed", "focus", "disabled"], 22)
	timer_picker.item_selected.connect(_on_timer_selected)
	timer_row.add_child(timer_picker)
	settings.add_child(timer_row)

	settings.add_child(Ui.ink_label("Rules", 26))
	for entry in GameState.RULE_TOGGLES:
		var rule := CheckBox.new()
		rule.text = entry[1]
		Ui.style_check(rule, 22)
		rule.toggled.connect(_on_rule_toggled.bind(entry[0]))
		settings.add_child(rule)
		rule_checks[entry[0]] = rule

	var freq_row := HBoxContainer.new()
	freq_row.add_child(Ui.ink_label("Item frequency  ", 22))
	freq_picker = OptionButton.new()
	for label in ["None", "Low", "Regular", "CRAZY"]:
		freq_picker.add_item(label)
	Ui.style_input(freq_picker, ["normal", "hover", "pressed", "focus", "disabled"], 22)
	freq_picker.item_selected.connect(_on_freq_selected)
	freq_row.add_child(freq_picker)
	settings.add_child(freq_row)

	var keys_row := HBoxContainer.new()
	keys_row.add_child(Ui.ink_label("How many keys (at least)  ", 22))
	keys_spin = SpinBox.new()
	keys_spin.min_value = 0
	keys_spin.max_value = 10
	keys_spin.value = 0
	keys_spin.get_line_edit().add_theme_font_size_override("font_size", 22)
	keys_spin.get_line_edit().add_theme_color_override("font_color", Ui.INK)
	keys_spin.value_changed.connect(_on_keys_changed)
	keys_row.add_child(keys_spin)
	settings.add_child(keys_row)

	status_label = Ui.bubbly_label("", 22, 8)
	root.add_child(status_label)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 20)
	root.add_child(buttons)
	ready_button = Ui.bubble("Ready", Ui.MINT, _on_ready_pressed, Vector2(240, 72))
	buttons.add_child(ready_button)
	start_button = Ui.bubble("Start Race", Ui.YELLOW, _on_start_pressed, Vector2(260, 72))
	buttons.add_child(start_button)
	buttons.add_child(Ui.bubble("Leave Room", Ui.LAVENDER, _on_leave_pressed, Vector2(260, 72)))


func _refresh() -> void:
	if leaving or MP.state.is_empty():
		if status_label != null:
			status_label.text = "Waiting for the host..."
		return
	var phase := MP.phase()
	var is_host := Net.is_host
	if phase == "racing" and MP.in_participants(Net.my_id):
		leaving = true
		get_tree().change_scene_to_file(GAME_SCENE)
		return

	syncing = true
	code_label.text = "Room %s" % Net.room_code
	count_label.text = "%d / %d players" % [MP.players().size(), MP.MAX_PLAYERS]
	_rebuild_players(phase)

	var settings := MP.settings()
	for key in checks:
		var check: CheckBox = checks[key]
		check.set_pressed_no_signal(settings["templates"].has(key))
		check.disabled = not is_host
	enable_all_button.disabled = not is_host
	disable_all_button.disabled = not is_host
	if not (is_host and seeds_input.has_focus()):
		seeds_input.text = ", ".join(settings["seeds"])
	seeds_input.editable = is_host
	races_spin.set_value_no_signal(int(settings["races"]))
	races_spin.editable = is_host
	order_picker.select(maxi(order_keys.find(str(settings.get("order_mode", "random"))), 0))
	order_picker.disabled = not is_host
	timer_picker.select(maxi(timer_keys.find(str(settings["timer_start"])), 0))
	timer_picker.disabled = not is_host
	for key in rule_checks:
		var rule: CheckBox = rule_checks[key]
		rule.set_pressed_no_signal(bool(settings.get(key, false)))
		rule.disabled = not is_host
	freq_picker.select(maxi(freq_keys.find(str(settings.get("item_freq", "regular"))), 0))
	freq_picker.disabled = not is_host
	keys_spin.set_value_no_signal(int(settings.get("keys", 0)))
	keys_spin.editable = is_host
	syncing = false

	ready_button.visible = not is_host
	ready_button.text = "Not Ready" if MP.me_ready() else "Ready"
	ready_button.disabled = phase != "lobby"
	start_button.visible = is_host
	bans_button.visible = is_host
	if not is_host:
		_close_bans()
	status_label.text = _status_text(phase, is_host)
	_update_start_button(phase, settings)


func _process(_delta: float) -> void:
	if start_button != null and MP.phase() == "starting":
		_update_start_button("starting", MP.settings())
		status_label.text = _status_text("starting", Net.is_host)


# The host's button starts the race (forcing it if some players aren't ready), and cancels the countdown.
func _update_start_button(phase: String, settings: Dictionary) -> void:
	if phase == "starting":
		start_button.text = "Cancel Start"
		start_button.disabled = false
		return
	var waiting := MP.not_ready_count()
	start_button.text = "Start Race" if waiting == 0 else "Force Start"
	start_button.disabled = phase != "lobby" or settings["templates"].is_empty()


func _status_text(phase: String, is_host: bool) -> String:
	match phase:
		"starting":
			return "The race starts in %d..." % ceili(MP.countdown) + ("  (host: press Cancel Start to stop it)" if is_host else "")
		"racing", "between":
			return "A race is in progress. You'll join the next race."
		"final_scores", "final":
			return "Waiting for the host to bring everyone back to the lobby."
	if is_host:
		if MP.settings()["templates"].is_empty():
			return "Select at least one template to start."
		var waiting := 0
		for p in MP.players():
			if int(p["id"]) != Net.my_id and not bool(p["ready"]):
				waiting += 1
		return "Everyone is ready!" if waiting == 0 else "Waiting for %d player(s) to get ready" % waiting
	return "Ready up and wait for the host to start."


func _rebuild_players(phase: String) -> void:
	for child in players_box.get_children():
		players_box.remove_child(child)
		child.queue_free()
	for p in MP.players():
		var id := int(p["id"])
		var label_text := str(p["name"])
		if id == Net.host_id:
			label_text += "  (host)"
		if id == Net.my_id:
			label_text += "  (you)"
		if Net.muted.has(id):
			label_text += "  [muted]"
		var entry := VBoxContainer.new()
		var row := HBoxContainer.new()
		entry.add_child(row)
		var name_label := Ui.ink_label(label_text, 22)
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name_label)
		var tag := ""
		if bool(p["late"]):
			tag = "joins next race"
		elif id != Net.host_id and phase in ["lobby", "starting"]:
			tag = "READY" if bool(p["ready"]) else "not ready"
		if int(p["points"]) > 0 or phase != "lobby":
			tag = ("%d pts   " % int(p["points"])) + tag
		var tag_label := Ui.ink_label(tag, 20)
		if bool(p["ready"]) and not bool(p["late"]):
			tag_label.add_theme_color_override("font_color", Color(0.15, 0.55, 0.3))
		row.add_child(tag_label)
		if Net.is_host and id != Net.my_id:
			var tools := HBoxContainer.new()
			tools.add_theme_constant_override("separation", 6)
			entry.add_child(tools)
			_tool_button(tools, "Unmute" if Net.muted.has(id) else "Mute", "unmute" if Net.muted.has(id) else "mute", id)
			_tool_button(tools, "Kick", "kick", id)
			_tool_button(tools, "Ban", "ban", id)
			_tool_button(tools, "Make host", "promote", id)
		players_box.add_child(entry)
		players_box.add_child(HSeparator.new())


func _tool_button(parent: Control, text: String, action: String, id: int) -> void:
	var b := Button.new()
	b.text = text
	Ui.style_button(b, 16)
	b.pressed.connect(func(): Net.admin(action, id))
	parent.add_child(b)


# --- Banned players (host only) ---

func _open_bans() -> void:
	if not Net.is_host or bans_window != null:
		return
	bans_window = Control.new()
	add_child(bans_window)
	bans_window.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var shade := ColorRect.new()
	shade.color = Color(0, 0.05, 0.15, 0.55)
	bans_window.add_child(shade)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var center := CenterContainer.new()
	bans_window.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var panel := Ui.panel()
	panel.custom_minimum_size = Vector2(460, 0)
	center.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	panel.add_child(column)
	column.add_child(Ui.ink_label("Banned players", 30))
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 260)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	bans_list = VBoxContainer.new()
	bans_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(bans_list)
	var close := Button.new()
	close.text = "Close"
	Ui.style_button(close, 22)
	close.pressed.connect(_close_bans)
	column.add_child(close)
	Net.bans_changed.connect(_fill_bans)
	_fill_bans([])
	Net.admin("bans")


func _close_bans() -> void:
	if bans_window == null:
		return
	if Net.bans_changed.is_connected(_fill_bans):
		Net.bans_changed.disconnect(_fill_bans)
	bans_window.queue_free()
	bans_window = null
	bans_list = null


func _fill_bans(names: Array) -> void:
	if bans_list == null:
		return
	for child in bans_list.get_children():
		bans_list.remove_child(child)
		child.queue_free()
	if names.is_empty():
		bans_list.add_child(Ui.ink_label("Nobody is banned from this room.", 20))
	for banned in names:
		var row := HBoxContainer.new()
		var label := Ui.ink_label(str(banned), 22)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)
		var unban := Button.new()
		unban.text = "Unban"
		Ui.style_button(unban, 18)
		unban.pressed.connect(func(): Net.admin("unban", str(banned)))
		row.add_child(unban)
		bans_list.add_child(row)


func _on_template_toggled(_pressed: bool, _key: String) -> void:
	if syncing or not Net.is_host:
		return
	var selected: Array = []
	for k in checks:
		if (checks[k] as CheckBox).button_pressed:
			selected.append(k)
	MP.update_settings({"templates": selected})


func _set_all_templates(on: bool) -> void:
	if syncing or not Net.is_host:
		return
	MP.update_settings({"templates": GameState.TEMPLATES.keys() if on else []})


func _on_seeds_changed(text: String) -> void:
	if not syncing and Net.is_host:
		MP.update_settings({"seeds": MP.parse_seeds(text)})


func _on_races_changed(value: float) -> void:
	if not syncing and Net.is_host:
		MP.update_settings({"races": int(value)})


func _on_order_selected(index: int) -> void:
	if not syncing and Net.is_host:
		MP.update_settings({"order_mode": order_keys[index]})


func _on_timer_selected(index: int) -> void:
	if not syncing and Net.is_host:
		MP.update_settings({"timer_start": timer_keys[index]})


func _on_rule_toggled(pressed: bool, key: String) -> void:
	if not syncing and Net.is_host:
		MP.update_settings({key: pressed})


func _on_freq_selected(index: int) -> void:
	if not syncing and Net.is_host:
		MP.update_settings({"item_freq": freq_keys[index]})


func _on_keys_changed(value: float) -> void:
	if not syncing and Net.is_host:
		MP.update_settings({"keys": int(value)})


func _on_ready_pressed() -> void:
	MP.set_ready(not MP.me_ready())


func _on_start_pressed() -> void:
	if MP.phase() == "starting":
		MP.cancel_start()
	else:
		MP.start_race_set()


func _on_leave_pressed() -> void:
	leaving = true
	MP.leave()
	get_tree().change_scene_to_file(MENU_SCENE)
