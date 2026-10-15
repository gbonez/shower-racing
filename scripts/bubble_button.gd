class_name BubbleButton
extends Control

signal pressed

var text := ""
var tint := Color(0.75, 0.9, 1.0)
var hovered := false
var down := false
var disabled := false:
	set(value):
		disabled = value
		down = false
		queue_redraw()
var _tween: Tween


func _init() -> void:
	custom_minimum_size = Vector2(340, 100)
	size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	mouse_filter = Control.MOUSE_FILTER_STOP


func _ready() -> void:
	pivot_offset = size / 2.0
	resized.connect(func(): pivot_offset = size / 2.0)
	mouse_entered.connect(_set_hovered.bind(true))
	mouse_exited.connect(_set_hovered.bind(false))


func _set_hovered(on: bool) -> void:
	hovered = on
	if not on:
		down = false
	_pop()


func _pop() -> void:
	var target := 1.0 if disabled else (0.94 if down else (1.07 if hovered else 1.0))
	if _tween:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(self, "scale", Vector2.ONE * target, 0.15) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if disabled:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			down = true
			_pop()
		else:
			var clicked := down and Rect2(Vector2.ZERO, size).has_point(event.position)
			down = false
			_pop()
			if clicked:
				pressed.emit()


func _draw() -> void:
	var c := size / 2.0
	var radius := size.y / 2.0
	var stretch := size.x / size.y
	var shade := tint
	if not disabled:
		if down:
			shade = tint.lerp(Ui.PRESS_BLUE, 0.8)
		elif hovered:
			shade = tint.lerp(Ui.HOVER_BLUE, 0.7)
	var alpha := (0.95 if hovered else 0.8) * (0.45 if disabled else 1.0)

	draw_set_transform(c, 0.0, Vector2(stretch, 1.0))
	draw_circle(Vector2.ZERO, radius, Color(shade.r, shade.g, shade.b, alpha))
	draw_arc(Vector2.ZERO, radius - 10.0, PI * 0.1, PI * 0.9, 32,
			Color(shade.darkened(0.25), 0.35), 6.0, true)
	draw_arc(Vector2.ZERO, radius - 2.0, 0.0, TAU, 64, Color(1, 1, 1, 0.9), 3.0, true)

	draw_set_transform(c + Vector2(-size.x * 0.24, -size.y * 0.24), -0.45, Vector2(1.7, 1.0))
	draw_circle(Vector2.ZERO, radius * 0.2, Color(1, 1, 1, 0.8))
	draw_set_transform(c + Vector2(size.x * 0.22, size.y * 0.26), 0.0, Vector2(1.0, 1.0))
	draw_circle(Vector2.ZERO, radius * 0.07, Color(1, 1, 1, 0.6))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	# Dark text on the light bubble; white text with a navy outline once it turns a deeper blue.
	var font := Ui.font()
	var font_size := 40
	var pos := Vector2(0, c.y + font_size * 0.36)
	var deep := (hovered or down) and not disabled
	var fill := Color.WHITE if deep else Ui.NAVY
	var edge := Ui.NAVY if deep else Color(1, 1, 1, 0.95)
	if disabled:
		fill = Color(Ui.NAVY, 0.5)
	draw_string_outline(font, pos, text, HORIZONTAL_ALIGNMENT_CENTER, size.x, font_size, 10, edge)
	draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_CENTER, size.x, font_size, fill)
