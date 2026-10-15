class_name Ui
extends RefCounted

# Shared pieces of the soapy menu look so new screens match the existing ones.

const BLUE := Color(0.7, 0.88, 1.0)
const PINK := Color(1.0, 0.78, 0.88)
const MINT := Color(0.75, 1.0, 0.85)
const LAVENDER := Color(0.85, 0.8, 1.0)
const YELLOW := Color(1.0, 0.95, 0.7)
const INK := Color(0.06, 0.15, 0.36)
const OUTLINE := Color(0.2, 0.45, 0.85)
const NAVY := Color(0.04, 0.12, 0.3)
# Shades of blue for hover and press feedback, from lightest to deepest.
const SELECT_BLUE := Color(0.82, 0.92, 1.0)
const HOVER_BLUE := Color(0.6, 0.8, 1.0)
const PRESS_BLUE := Color(0.32, 0.58, 0.95)

static var _font: SystemFont


# A bold system font so text stays readable at any size.
static func font() -> Font:
	if _font == null:
		_font = SystemFont.new()
		_font.font_names = PackedStringArray(["Segoe UI", "Verdana", "Arial", "Helvetica", "sans-serif"])
		_font.font_weight = 700
	return _font


static func _box(color: Color, border: Color, radius := 18, margin_x := 18, margin_y := 8) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.set_corner_radius_all(radius)
	box.set_border_width_all(3)
	box.border_color = border
	box.content_margin_left = margin_x
	box.content_margin_right = margin_x
	box.content_margin_top = margin_y
	box.content_margin_bottom = margin_y
	return box


# White text with a blue outline, like the titles.
static func bubbly_label(text: String, font_size: int, outline: int) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_override("font", font())
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", Color.WHITE)
	l.add_theme_color_override("font_outline_color", NAVY)
	l.add_theme_constant_override("outline_size", outline)
	return l


# Dark blue text for use on the translucent panels.
static func ink_label(text: String, font_size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font())
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", INK)
	return l


static func panel_style() -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = Color(1, 1, 1, 0.88)
	box.set_corner_radius_all(28)
	box.set_border_width_all(3)
	box.border_color = Color(1, 1, 1, 0.9)
	box.set_content_margin_all(18)
	return box


static func panel() -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", panel_style())
	return p


# Text fields and drop-downs: white at rest, light blue under the mouse, deeper blue when pressed.
static func style_input(control: Control, states: Array, font_size := 24) -> void:
	for state in states:
		var color := Color(1, 1, 1, 0.95)
		var border := Color(0.7, 0.85, 1.0)
		match String(state):
			"hover":
				color = SELECT_BLUE
				border = HOVER_BLUE
			"pressed":
				color = HOVER_BLUE
				border = PRESS_BLUE
			"focus":
				color = Color(1, 1, 1, 0.98)
				border = PRESS_BLUE
			"disabled", "read_only":
				color = Color(0.9, 0.93, 0.98, 0.9)
		control.add_theme_stylebox_override(state, _box(color, border, 22, 18, 6))
	control.add_theme_font_override("font", font())
	control.add_theme_font_size_override("font_size", font_size)
	for key in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color",
			"font_hover_pressed_color", "font_uneditable_color", "font_disabled_color"]:
		control.add_theme_color_override(key, INK)
	if control is OptionButton:
		_style_popup((control as OptionButton).get_popup(), font_size)


# The list that drops down from an OptionButton.
static func _style_popup(popup: PopupMenu, font_size: int) -> void:
	popup.add_theme_font_override("font", font())
	popup.add_theme_font_size_override("font_size", font_size)
	popup.add_theme_color_override("font_color", INK)
	popup.add_theme_color_override("font_hover_color", NAVY)
	popup.add_theme_stylebox_override("panel", _box(Color(0.97, 0.99, 1.0), HOVER_BLUE, 14, 6, 6))
	popup.add_theme_stylebox_override("hover", _box(HOVER_BLUE, PRESS_BLUE, 10, 10, 4))
	popup.add_theme_constant_override("v_separation", 8)


# Plain buttons: light blue at rest, mid blue under the mouse, deep blue (white text) when pressed.
static func style_button(button: Button, font_size := 22) -> void:
	button.add_theme_stylebox_override("normal", _box(SELECT_BLUE, HOVER_BLUE, 16, 16, 6))
	button.add_theme_stylebox_override("hover", _box(HOVER_BLUE, PRESS_BLUE, 16, 16, 6))
	button.add_theme_stylebox_override("pressed", _box(PRESS_BLUE, NAVY, 16, 16, 6))
	button.add_theme_stylebox_override("focus", _box(Color(0, 0, 0, 0), PRESS_BLUE, 16, 16, 6))
	button.add_theme_stylebox_override("disabled", _box(Color(0.9, 0.93, 0.98, 0.8), Color(0.8, 0.88, 0.98), 16, 16, 6))
	button.add_theme_font_override("font", font())
	button.add_theme_font_size_override("font_size", font_size)
	button.add_theme_color_override("font_color", INK)
	button.add_theme_color_override("font_hover_color", NAVY)
	button.add_theme_color_override("font_pressed_color", Color.WHITE)
	button.add_theme_color_override("font_disabled_color", Color(0.4, 0.5, 0.65))


# Check boxes get a blue highlight behind them while hovered.
static func style_check(check: CheckBox, font_size := 20) -> void:
	check.add_theme_stylebox_override("normal", _box(Color(1, 1, 1, 0), Color(1, 1, 1, 0), 12, 8, 4))
	check.add_theme_stylebox_override("hover", _box(SELECT_BLUE, HOVER_BLUE, 12, 8, 4))
	check.add_theme_stylebox_override("hover_pressed", _box(HOVER_BLUE, PRESS_BLUE, 12, 8, 4))
	check.add_theme_stylebox_override("pressed", _box(Color(0.9, 0.95, 1.0, 0.8), HOVER_BLUE, 12, 8, 4))
	check.add_theme_stylebox_override("focus", _box(Color(0, 0, 0, 0), PRESS_BLUE, 12, 8, 4))
	check.add_theme_font_override("font", font())
	check.add_theme_font_size_override("font_size", font_size)
	for key in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color",
			"font_focus_color", "font_disabled_color"]:
		check.add_theme_color_override(key, INK)


static func bubble(text: String, tint: Color, action: Callable, min_size := Vector2(300, 84)) -> BubbleButton:
	var b := BubbleButton.new()
	b.text = text
	b.tint = tint
	b.custom_minimum_size = min_size
	b.pressed.connect(action)
	return b
