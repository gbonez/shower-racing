extends Control

const GAME_SCENE := "res://scenes/main.tscn"
const LOBBY_SCENE := "res://scenes/lobby.tscn"
const SudsBackground := preload("res://scripts/suds_background.gd")
const BLUE := Color(0.7, 0.88, 1.0)
const PINK := Color(1.0, 0.78, 0.88)
const MINT := Color(0.75, 1.0, 0.85)
const LAVENDER := Color(0.85, 0.8, 1.0)
const YELLOW := Color(1.0, 0.95, 0.7)

var title: Label
var page: VBoxContainer
var free_index := 0
var free_seed_input: LineEdit
var name_input: LineEdit
var server_input: LineEdit
var code_input: LineEdit
var status_label: Label
var time := 0.0


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var background := SudsBackground.new()
	add_child(background)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var center := CenterContainer.new()
	add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	center.add_child(column)

	title = Label.new()
	title.text = "Shower Racing"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_bubbly(title, 104, 20)
	column.add_child(title)

	page = VBoxContainer.new()
	page.add_theme_constant_override("separation", 14)
	column.add_child(page)
	_show_main()

	Net.joined.connect(_on_net_joined)
	Net.failed.connect(_on_net_failed)
	if MP.notice_text != "":
		_show_multiplayer()
		_set_status(MP.notice_text)
		MP.notice_text = ""


func _process(delta: float) -> void:
	time += delta
	title.pivot_offset = title.size / 2.0
	title.rotation = sin(time * 1.2) * 0.02
	title.scale = Vector2.ONE * (1.0 + sin(time * 2.0) * 0.02)


func _bubbly(label: Label, font_size: int, outline: int) -> void:
	label.add_theme_font_override("font", Ui.font())
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", Color.WHITE)
	label.add_theme_color_override("font_outline_color", Ui.NAVY if font_size < 60 else Ui.OUTLINE)
	label.add_theme_constant_override("outline_size", outline)
	label.add_theme_color_override("font_shadow_color", Color(0.2, 0.4, 0.7, 0.35))
	label.add_theme_constant_override("shadow_offset_y", 6)


func _clear_page() -> void:
	title.add_theme_font_size_override("font_size", 104)
	for child in page.get_children():
		page.remove_child(child)
		child.queue_free()


func _bubble(text: String, tint: Color, action: Callable, min_size := Vector2(340, 100)) -> BubbleButton:
	var b := BubbleButton.new()
	b.text = text
	b.tint = tint
	b.custom_minimum_size = min_size
	b.pressed.connect(action)
	page.add_child(b)
	return b


func _show_main() -> void:
	_clear_page()
	_bubble("Singleplayer", BLUE, _show_single)
	_bubble("Multiplayer", PINK, _show_multiplayer)
	_bubble("Quit", LAVENDER, get_tree().quit)


func _show_single() -> void:
	_clear_page()
	_bubble("Story Mode", BLUE, _start_story, Vector2(340, 92))
	_bubble("Free Play", MINT, _show_free, Vector2(340, 92))
	_bubble("Surprise Me", YELLOW, _start_surprise, Vector2(340, 92))
	_bubble("Back", LAVENDER, _show_main, Vector2(340, 92))


func _show_free() -> void:
	_clear_page()
	title.add_theme_font_size_override("font_size", 64)
	var template_label := Label.new()
	template_label.text = "Template"
	template_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_bubbly(template_label, 28, 8)
	page.add_child(template_label)

	var picker := OptionButton.new()
	for key in GameState.TEMPLATES:
		picker.add_item(GameState.TEMPLATES[key])
	picker.select(free_index)
	picker.item_selected.connect(func(index: int): free_index = index)
	_style_input(picker, ["normal", "hover", "pressed", "focus"])
	page.add_child(picker)

	var seed_label := Label.new()
	seed_label.text = "Seed (empty = random)"
	seed_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_bubbly(seed_label, 28, 8)
	page.add_child(seed_label)

	var previous := free_seed_input.text if free_seed_input != null else ""
	free_seed_input = LineEdit.new()
	free_seed_input.text = previous
	free_seed_input.placeholder_text = "random"
	free_seed_input.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_style_input(free_seed_input, ["normal", "focus"])
	page.add_child(free_seed_input)

	_add_free_options()

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 16)
	page.add_child(buttons)
	buttons.add_child(Ui.bubble("Generate", MINT, _start_free, Vector2(260, 68)))
	buttons.add_child(Ui.bubble("Back", LAVENDER, _show_single, Vector2(260, 68)))


# The timer and rule options from the multiplayer lobby, kept in GameState for the next level.
func _add_free_options() -> void:
	var panel := Ui.panel()
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(560, 210)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	page.add_child(panel)
	var options := VBoxContainer.new()
	options.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	options.add_theme_constant_override("separation", 6)
	scroll.add_child(options)

	var timer_row := HBoxContainer.new()
	timer_row.add_child(Ui.ink_label("Timer starts when  ", 22))
	var timer_picker := OptionButton.new()
	var timer_keys: Array = MP.TIMER_MODES.keys()
	for key in timer_keys:
		timer_picker.add_item(MP.TIMER_MODES[key])
	timer_picker.select(maxi(timer_keys.find(GameState.free_timer), 0))
	Ui.style_input(timer_picker, ["normal", "hover", "pressed", "focus", "disabled"], 22)
	timer_picker.item_selected.connect(func(index: int): GameState.free_timer = str(timer_keys[index]))
	timer_row.add_child(timer_picker)
	options.add_child(timer_row)

	options.add_child(Ui.ink_label("Rules", 26))
	var rule_list := [["run_bottles", "Always run-away bottles"], ["run_shower", "Always run-away shower"],
			["need_boiler", "Always need the boiler"], ["no_fake_keys", "Disable fake keys"]]
	for entry in rule_list:
		var rule := CheckBox.new()
		rule.text = entry[1]
		Ui.style_check(rule, 22)
		rule.button_pressed = bool(GameState.rules[entry[0]])
		rule.toggled.connect(func(on: bool): GameState.rules[entry[0]] = on)
		options.add_child(rule)

	var freq_keys := ["none", "low", "regular", "crazy"]
	var freq_row := HBoxContainer.new()
	freq_row.add_child(Ui.ink_label("Item frequency  ", 22))
	var freq_picker := OptionButton.new()
	for label in ["None", "Low", "Regular", "CRAZY"]:
		freq_picker.add_item(label)
	freq_picker.select(maxi(freq_keys.find(str(GameState.rules["item_freq"])), 0))
	Ui.style_input(freq_picker, ["normal", "hover", "pressed", "focus", "disabled"], 22)
	freq_picker.item_selected.connect(func(index: int): GameState.rules["item_freq"] = freq_keys[index])
	freq_row.add_child(freq_picker)
	options.add_child(freq_row)

	var keys_row := HBoxContainer.new()
	keys_row.add_child(Ui.ink_label("How many keys (at least)  ", 22))
	var keys_spin := SpinBox.new()
	keys_spin.min_value = 0
	keys_spin.max_value = 10
	keys_spin.value = int(GameState.rules["keys"])
	keys_spin.get_line_edit().add_theme_font_size_override("font_size", 22)
	keys_spin.get_line_edit().add_theme_color_override("font_color", Ui.INK)
	keys_spin.value_changed.connect(func(value: float): GameState.rules["keys"] = int(value))
	keys_row.add_child(keys_spin)
	options.add_child(keys_row)


func _style_input(control: Control, states: Array) -> void:
	Ui.style_input(control, states, 30)
	control.custom_minimum_size = Vector2(420, 58)


func _menu_label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_bubbly(l, 26, 8)
	return l


func _set_status(text: String) -> void:
	if status_label != null and is_instance_valid(status_label):
		status_label.text = text


func _show_multiplayer() -> void:
	_clear_page()
	title.add_theme_font_size_override("font_size", 72)
	page.add_child(_menu_label("Your name"))
	name_input = LineEdit.new()
	name_input.text = Net.player_name
	name_input.max_length = 16
	name_input.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_style_input(name_input, ["normal", "focus"])
	page.add_child(name_input)
	page.add_child(_menu_label("Server"))
	server_input = LineEdit.new()
	server_input.text = Net.server_url
	server_input.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_style_input(server_input, ["normal", "focus"])
	page.add_child(server_input)
	_bubble("Host Room", MINT, _host_room, Vector2(300, 76))
	_bubble("Join Room", YELLOW, _show_join, Vector2(300, 76))
	_bubble("Back", LAVENDER, _show_main, Vector2(300, 76))
	status_label = _menu_label("")
	page.add_child(status_label)


func _show_join() -> void:
	if not _save_connection_inputs():
		return
	_clear_page()
	title.add_theme_font_size_override("font_size", 72)
	page.add_child(_menu_label("Room code"))
	code_input = LineEdit.new()
	code_input.max_length = 4
	code_input.placeholder_text = "ABCD"
	code_input.alignment = HORIZONTAL_ALIGNMENT_CENTER
	code_input.text_changed.connect(_on_code_changed)
	code_input.text_submitted.connect(func(_text: String): _join_room())
	_style_input(code_input, ["normal", "focus"])
	page.add_child(code_input)
	_bubble("Join", MINT, _join_room, Vector2(300, 76))
	_bubble("Back", LAVENDER, _show_multiplayer, Vector2(300, 76))
	status_label = _menu_label("")
	page.add_child(status_label)


func _on_code_changed(text: String) -> void:
	var upper := text.to_upper()
	if upper != text:
		code_input.text = upper
		code_input.caret_column = upper.length()


func _save_connection_inputs() -> bool:
	var chosen := name_input.text.strip_edges()
	Net.player_name = chosen if chosen != "" else "Player"
	var url := server_input.text.strip_edges()
	if not (url.begins_with("ws://") or url.begins_with("wss://")):
		_set_status("The server address should start with ws:// or wss://")
		return false
	Net.server_url = url
	Net.save_config()
	return true


func _host_room() -> void:
	if _save_connection_inputs():
		_set_status("Connecting...")
		Net.host_room()


func _join_room() -> void:
	var code := code_input.text.strip_edges().to_upper()
	if code.length() != 4:
		_set_status("Room codes have 4 characters.")
		return
	_set_status("Connecting...")
	Net.join_room(code)


func _on_net_joined(_code: String, _id: int, _is_host: bool) -> void:
	get_tree().change_scene_to_file(LOBBY_SCENE)


func _on_net_failed(reason: String) -> void:
	_set_status(reason)


func _start_story() -> void:
	GameState.reset_rules()
	GameState.start_story()
	_launch()


func _start_surprise() -> void:
	GameState.reset_rules()
	GameState.start_surprise()
	_launch()


func _start_free() -> void:
	GameState.start_free(GameState.TEMPLATES.keys()[free_index], free_seed_input.text)
	_launch()


func _launch() -> void:
	get_tree().change_scene_to_file(GAME_SCENE)
