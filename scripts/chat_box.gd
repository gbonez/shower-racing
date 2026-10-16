class_name ChatBox
extends PanelContainer

# Room chat for the multiplayer lobby and for finished racers watching the others. The messages live in
# MP.chat_log; this only shows them and sends what the player types.

signal typing_changed(typing: bool)

const MAX_LINES := 60
const NAME_COLORS: Array[Color] = [Color(0.15, 0.4, 0.85), Color(0.8, 0.25, 0.45), Color(0.15, 0.6, 0.35),
		Color(0.75, 0.45, 0.1), Color(0.5, 0.3, 0.8), Color(0.1, 0.55, 0.6)]

var overlay := false  # in-game: translucent dark panel, white text
var scroll: ScrollContainer
var lines: VBoxContainer
var input: LineEdit
var shown := 0  # how many entries of MP.chat_log are on screen


func _init(in_game := false) -> void:
	overlay = in_game
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	add_child(box)
	if overlay:
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.02, 0.06, 0.15, 0.62)
		style.set_corner_radius_all(14)
		style.set_content_margin_all(10)
		add_theme_stylebox_override("panel", style)
	else:
		add_theme_stylebox_override("panel", Ui.panel_style())
		box.add_child(Ui.ink_label("Chat", 26))
	scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	lines = VBoxContainer.new()
	lines.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lines.add_theme_constant_override("separation", 2)
	scroll.add_child(lines)
	input = LineEdit.new()
	input.max_length = 200
	input.placeholder_text = "Press Enter to chat" if overlay else "Type a message and press Enter"
	Ui.style_input(input, ["normal", "focus"], 20)
	input.text_submitted.connect(_on_submitted)
	input.focus_entered.connect(func(): typing_changed.emit(true))
	input.focus_exited.connect(func(): typing_changed.emit(false))
	input.gui_input.connect(_on_input_event)
	box.add_child(input)


func _ready() -> void:
	MP.chat_changed.connect(_refresh)
	_refresh()


func is_typing() -> bool:
	return input.has_focus()


func begin_typing() -> void:
	input.grab_focus()


func stop_typing() -> void:
	input.release_focus()


func _on_submitted(text: String) -> void:
	MP.send_chat(text)
	input.clear()
	if overlay:
		input.release_focus()


func _on_input_event(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		input.release_focus()
		input.accept_event()


func _refresh() -> void:
	var log: Array[Dictionary] = MP.chat_log
	if log.size() < shown:
		for child in lines.get_children():
			child.queue_free()
		shown = 0
	for i in range(shown, log.size()):
		lines.add_child(_line(log[i]))
	shown = log.size()
	while lines.get_child_count() > MAX_LINES:
		var oldest := lines.get_child(0)
		lines.remove_child(oldest)
		oldest.queue_free()
	_scroll_to_end.call_deferred()


func _scroll_to_end() -> void:
	scroll.scroll_vertical = int(scroll.get_v_scroll_bar().max_value)


func _line(entry: Dictionary) -> RichTextLabel:
	var l := RichTextLabel.new()
	l.bbcode_enabled = true
	l.fit_content = true
	l.scroll_active = false
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.add_theme_font_override("normal_font", Ui.font())
	l.add_theme_font_override("bold_font", Ui.font())
	l.add_theme_font_size_override("normal_font_size", 18)
	l.add_theme_font_size_override("bold_font_size", 18)
	var text_color := Color.WHITE if overlay else Ui.INK
	l.add_theme_color_override("default_color", text_color)
	var text := str(entry["text"]).replace("[", "[lb]")
	if bool(entry.get("system", false)):
		l.text = "[i][color=#%s]%s[/color][/i]" % [text_color.lerp(Color(0.5, 0.55, 0.65), 0.45).to_html(false), text]
		return l
	var name_color: Color = NAME_COLORS[absi(int(entry["from"])) % NAME_COLORS.size()]
	if overlay:
		name_color = name_color.lightened(0.45)
	l.text = "[b][color=#%s]%s[/color][/b]  %s" % [name_color.to_html(false), str(entry["name"]).replace("[", "[lb]"), text]
	return l
